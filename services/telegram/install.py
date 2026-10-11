"""Run as root on the licensing origin, from a reviewed staged copy.

Only the Cleaner service, its isolated internal authority and its nginx location
are managed. Secrets come from the operator keychain, never command arguments.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
from bot import post
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path('/opt/yeti3-cleaner-bot')
CONFIG = Path('/etc/yeti3-cleaner-bot')
NAME = 'yeti3-cleaner-ad-authority'
ORIGIN = 'https://license.gochain.space'
PUBLIC_PATH = '/api/cleaner/telegram/webhook'


def run(args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, timeout=60, **kwargs)


def vault(action, entry, value=None):
    result = run(['/usr/local/bin/yeti3-keychain', action, entry],
                 input=(json.dumps(value) + '\n').encode() if value else None)
    return json.loads(result.stdout)


def request(url, payload=None, headers=None):
    if url.startswith('https://api.telegram.org/'):
        return post(url, payload or {}, headers, timeout=10)
    req = Request(url, data=json.dumps(payload).encode() if payload is not None else None,
                  headers={'Content-Type': 'application/json', **(headers or {})})
    with urlopen(req, timeout=10) as response:
        return json.load(response)


def secret_file(path, values):
    # Environment files never contain newlines supplied by a secret/provider.
    if any('\n' in str(v) or '\r' in str(v) for v in values.values()):
        raise ValueError('Invalid environment value')
    path.write_text(''.join(k + '=' + str(v) + '\n' for k, v in values.items()))
    path.chmod(0o600)


def main():
    if os.geteuid() != 0:
        raise PermissionError('Root operator required')
    source = Path(__file__).resolve().parent
    relay = '/run/gochain-telegram-egress/api.sock'
    if Path(relay).exists():
        os.environ['CLEANER_TELEGRAM_RELAY'] = relay
    token = vault('reveal', 'telegram/yeti3cleanerbot/admin')['secret']['token']
    payment = vault('reveal', 'telegram/yeti3cleanerbot/payments')['secret']
    telegram = 'https://api.telegram.org/bot' + token + '/'
    me = request(telegram + 'getMe')
    assert me.get('ok') and me['result']['username'] == 'yeti3cleanerbot'
    before = request(telegram + 'getWebhookInfo')['result']
    destination = ORIGIN + PUBLIC_PATH
    assert before['url'] in ('', destination), 'Another webhook exists; preserving it'
    # Current live image and its database source; do not rebuild shared services.
    current = json.loads(run(['docker', 'inspect', 'gochain-site-advertising']).stdout)[0]
    environment = dict(v.split('=', 1) for v in current['Config']['Env'])
    image = current['Image']
    assert current['Config']['Cmd'] == ['gochain-ads']
    worker_hash = hashlib.sha256(payment['worker_token'].encode()).hexdigest()
    CONFIG.mkdir(parents=True, exist_ok=True, mode=0o700)
    CONFIG.chmod(0o700)
    root_existed = ROOT.exists()
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o755)
    backup = Path('/var/backups/yeti3-cleaner-bot') / str(time.time_ns())
    backup.mkdir(parents=True, mode=0o700)
    if root_existed:
        for name in ('bot.py', 'yeti3-cleaner-bot.service'):
            if (ROOT / name).exists():
                shutil.copy2(ROOT / name, backup / name)
    authority_env = CONFIG / 'authority.env'
    if not authority_env.exists():
        secret_file(authority_env, {
            'NETWORK_DATABASE_URL': environment['NETWORK_DATABASE_URL'],
            'NETWORK_BIND': '0.0.0.0:4352',
            'NETWORK_TELEGRAM_WORKER_TOKEN_HASH': worker_hash,
        })
    inspect = subprocess.run(['docker', 'inspect', NAME], capture_output=True)
    created = inspect.returncode != 0
    if created:
        run(['docker', 'run', '-d', '--name', NAME, '--restart', 'unless-stopped',
             '--network', 'gochain_default', '--env-file', str(authority_env),
             '-p', '127.0.0.1:4352:4352', '--read-only', '--tmpfs', '/tmp:rw,noexec,nosuid,size=8m',
             '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges:true',
             '--memory', '256m', '--cpus', '0.5', '--pids-limit', '64',
             '--log-opt', 'max-size=5m', '--log-opt', 'max-file=2', image])
    else:
        active = json.loads(inspect.stdout)[0]
        env = dict(v.split('=', 1) for v in active['Config']['Env'])
        assert active['Image'] == image, 'Authority image differs; review rollback before replacing'
        assert env.get('NETWORK_TELEGRAM_WORKER_TOKEN_HASH') == worker_hash
        assert active['State']['Running']
    # No account or order is created. 409 proves the worker credential was
    # accepted and the synthetic ID has no linked account.
    for attempt in range(12):
        try:
            request('http://127.0.0.1:4352/api/network/v1/internal/telegram/ads',
                    {'telegram_user_id': 0, 'action': 'status'},
                    {'x-network-bot-token': payment['worker_token']})
            raise RuntimeError('Unexpected linked fixture identity')
        except HTTPError as error:
            if error.code == 409:
                break
            raise
        except OSError:
            if attempt == 11:
                raise
            time.sleep(0.5)
    # Checkout is enabled separately after the real Stars tariff is configured.
    enabled = os.environ.get('CLEANER_STARS_ENABLED') == 'true'
    secret_file(CONFIG / 'runtime.env', {
        'CLEANER_TELEGRAM_BOT_TOKEN': token,
        'CLEANER_NETWORK_WORKER_TOKEN': payment['worker_token'],
        'CLEANER_WEBHOOK_SECRET': payment['webhook_secret'],
        'CLEANER_AUTHORITY_ORIGIN': 'http://127.0.0.1:4352',
        'CLEANER_TELEGRAM_RELAY': '/run/yeti3-cleaner-telegram.sock' if Path(relay).exists() else '',
        'CLEANER_STARS_ENABLED': str(enabled).lower(),
    })
    shutil.copy2(source / 'bot.py', ROOT / 'bot.py')
    if subprocess.run(['id', '-u', 'yeti3-cleaner-bot'], capture_output=True).returncode:
        run(['useradd', '--system', '--user-group', '--no-create-home', '--shell', '/usr/sbin/nologin', 'yeti3-cleaner-bot'])
    for unit in ('yeti3-cleaner-telegram.socket', 'yeti3-cleaner-telegram.service'):
        shutil.copy2(source / unit, Path('/etc/systemd/system') / unit)
    shutil.copy2(source / 'yeti3-cleaner-bot.service', ROOT / 'yeti3-cleaner-bot.service')
    shutil.copy2(ROOT / 'yeti3-cleaner-bot.service', '/etc/systemd/system/yeti3-cleaner-bot.service')
    run(['systemctl', 'daemon-reload'])
    run(['systemctl', 'enable', '--now', 'yeti3-cleaner-telegram.socket'])
    run(['systemctl', 'enable', '--now', 'yeti3-cleaner-bot'])
    if root_existed:
        run(['systemctl', 'restart', 'yeti3-cleaner-bot'])
    for attempt in range(60):
        try:
            assert request('http://127.0.0.1:8097/health')['ready']
            break
        except OSError:
            if attempt == 59:
                raise
            time.sleep(0.5)
    vhost = Path('/etc/nginx/sites-enabled/license.gochain.space.conf').resolve()
    old = vhost.read_text()
    (backup / 'nginx.before.conf').write_text(old)
    marker = '# YETI3 Cleaner bot webhook v1'
    if marker not in old:
        assert PUBLIC_PATH not in old, 'Existing route needs review'
        # Bind only to the existing TLS server; preserve every unrelated block.
        tls = old.index('listen 443')
        start = old.rfind('server {', 0, tls) + len('server {')
        assert start >= len('server {')
        vhost.write_text(old[:start] + '\n' + marker + '\n' + (source / 'nginx.location.conf').read_text() + old[start:])
        try:
            run(['nginx', '-t']); run(['systemctl', 'reload', 'nginx'])
        except Exception:
            vhost.write_text(old)
            raise
    # Check the public origin without a synthetic financial event.
    req = Request(destination, data=b'{}',
                  headers={'X-Telegram-Bot-Api-Secret-Token': payment['webhook_secret'],
                           'Content-Type': 'application/json'})
    with urlopen(req, timeout=15) as response:
        assert response.status == 200 and response.read() == b'ok'
    result = request(telegram + 'setWebhook', {'url': destination,
        'secret_token': payment['webhook_secret'],
        'allowed_updates': ['message', 'callback_query', 'pre_checkout_query'],
        'drop_pending_updates': False})
    assert result.get('ok')
    after = request(telegram + 'getWebhookInfo')['result']
    assert after['url'] == destination
    print(json.dumps({'webhook_verified': True, 'checkout_enabled': enabled,
                      'pending_updates': after['pending_update_count'],
                      'authority_image': image, 'backup': str(backup)}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # Request exceptions may contain a bot token in their URL. Never print them.
        print(json.dumps({'installed': False, 'error_type': type(error).__name__}))
        raise SystemExit(1)
