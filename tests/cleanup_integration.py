"""Run cleanup only inside a disposable HOME; never against the user's files."""
import json
import os
import subprocess
import sqlite3
import tempfile
import time
from pathlib import Path

engine = Path(os.environ.get('YETI_TEST_ENGINE', str(Path(__file__).resolve().parents[1] / 'target/release/yeti3-cleaner')))
with tempfile.TemporaryDirectory(prefix='yeti3-cleaner-test-') as temp:
    home = Path(temp).resolve()
    # No host package manager or Docker command may run during this test.
    tools = home / 'test-bin'
    tools.mkdir()
    for name in ('brew', 'docker', 'xcrun'):
        stub = tools / name
        stub.write_text('#!/bin/sh\necho simulated-cleaner-failure >&2\nexit 7\n')
        stub.chmod(0o755)
    env = {**os.environ, 'HOME': str(home), 'PATH': str(tools) + ':/usr/bin:/bin'}
    def run(*args, ok=True):
        p = subprocess.run([str(engine), *args], env=env, text=True, capture_output=True)
        if ok:
            assert p.returncode == 0, p.stderr
        return p
    def file(rel):
        p = home / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(b'x' * 128)
        for q in [p, p.parent]:
            os.utime(q, (time.time() - 30*86400,)*2)
        return p
    remove = file('Library/Caches/disposable/a')
    keep = file('Library/Caches/keep/a')
    pip = file('Library/Caches/pip/a')
    docs = file('Documents/do-not-touch')
    custom = file('scratch/a')
    nested_repo = file('scratch/repo/.git/config')
    run('scan')
    settings_path = home / 'Library/Application Support/Yeti3-Cleaner/settings.json'
    settings = json.loads(settings_path.read_text())
    settings['development']['pip'] = False
    settings['mobile']['delete_all_local_backups'] = False
    settings_path.write_text(json.dumps(settings))
    editor = json.loads(run('settings-data').stdout)
    assert editor['settings']['development']['pip'] is False
    assert editor['defaults']['development']['pip'] is True
    assert any(item['path'] == str(home / 'Library/Caches/pip') for item in editor['presets'])
    rules_path = settings_path.with_name('folders.json')
    rules = {'include': [str(custom.parent)], 'exclude': [str(keep)]}
    rules_path.write_text(json.dumps(rules))
    preview = run('clean', '--max', '--dry-run').stdout
    assert str(remove.parent) in preview and str(custom) in preview
    assert str(keep.parent) not in preview and str(pip.parent) not in preview
    assert not (home / 'Documents/Yeti3Cleaner/history.sqlite3').exists(), 'dry run wrote history'
    assert run('check-folder', str(home / 'Documents'), ok=False).returncode != 0
    assert run('check-folder', str(home), ok=False).returncode != 0
    run('clean', '--yes')  # Standard mode, disposable HOME only; no managed cleaners.
    assert (home / 'Documents/Yeti3Cleaner/history.sqlite3').exists()
    assert run('history-path').stdout.strip() == str(home / 'Documents/Yeti3Cleaner/history.sqlite3')
    assert not remove.exists() and not custom.exists()
    assert keep.exists() and pip.exists() and docs.exists() and nested_repo.exists()
    # Overlapping cache presets must appear exactly once in a plan.
    settings['development']['pip'] = True
    settings_path.write_text(json.dumps(settings))
    preview = run('clean', '--max', '--dry-run').stdout
    deletes = [line for line in preview.splitlines() if line.startswith('DELETE') and '/pip' in line]
    assert len(deletes) == 1, deletes
    # A reviewed cleanup removes only selected, unchanged paths from the saved plan.
    approved = file('Library/Caches/approved/a')
    changed = file('Library/Caches/changed/a')
    brew_cache = file('Library/Caches/Homebrew/downloads/cache')
    os.utime(brew_cache.parent.parent, (time.time() - 30*86400,)*2)
    plan_path = home / 'review.json'
    report = run('scan', '--max', '--plan-out', str(plan_path)).stdout
    assert str(approved.parent) in report
    later = file('Library/Caches/new-after-scan/a')
    changed.write_bytes(b'updated after preview')
    run('clean', '--max', '--yes', '--plan-in', str(plan_path), '--selected', 'caches')
    assert not approved.exists()
    assert changed.exists() and later.exists() and pip.exists()
    assert brew_cache.exists(), 'unchecked Homebrew category deleted its cache'
    run('clean', '--max', '--yes', '--plan-in', str(plan_path), '--include-docker')
    db = sqlite3.connect(home / 'Documents/Yeti3Cleaner/history.sqlite3')
    errors = db.execute("SELECT error FROM cleanup_entries WHERE run_id=(SELECT MAX(id) FROM cleanup_runs WHERE status != 'running') AND result='error'").fetchall()
    assert errors and all('simulated-cleaner-failure' in row[0] for row in errors), errors
    db.close()
    run('clean', '--max', '--yes', '--plan-in', str(plan_path), '--selected', 'caches', '--include-homebrew')
    assert not brew_cache.exists(), 'selected Homebrew cache was not cleaned'
    # Bad rules must fail closed, not revert to broader defaults.
    rules_path.write_text('{broken')
    assert run('clean', '--yes', ok=False).returncode != 0
    assert pip.exists() and keep.exists()
print('PASS: settings, exclusions, custom folders, protected paths, deduplication, reviewed plan and malformed-rule fail-closed behavior')
