"""Root-only acceptance test of the deployed Rust payment authority.

Uses a disposable MySQL schema with empty copies of the live table structures,
a schema-restricted random user and the exact running ads image. No production
accounts, orders or grants are written. No Telegram API or real charge is used.
"""
import hashlib
import json
import secrets
import subprocess
import time
from urllib.parse import urlsplit
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError


def run(args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, timeout=60, **kwargs)


def sql(query):
    return run(['docker', 'exec', '-i', 'gochain-database-1', 'sh', '-c',
                'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot --batch --raw --skip-column-names'],
               input=query.encode()).stdout.decode().strip()


def main():
    suffix = secrets.token_hex(6)
    schema = 'cleaner_qa_' + suffix
    name = 'yeti3-cleaner-qa-' + suffix
    password = secrets.token_hex(32)
    worker = secrets.token_hex(32)
    owner = 'a' * 32
    other = 'b' * 32
    device = 'c' * 32
    foreign_device = 'd' * 32
    operator_token, normal_token = secrets.token_hex(32), secrets.token_hex(32)
    current = json.loads(run(['docker', 'inspect', 'gochain-site-advertising']).stdout)[0]
    source_env = dict(v.split('=', 1) for v in current['Config']['Env'])
    source = urlsplit(source_env['NETWORK_DATABASE_URL'])
    assert source.scheme == 'mysql' and source.hostname
    database = source.path.strip('/')
    assert database.replace('_', '').isalnum()
    tables = ['network_accounts', 'network_compute_devices', 'network_telegram_identities',
              'network_ad_grants', 'network_ad_orders', 'network_ad_settings', 'network_audit', 'network_sessions']
    evidence = []
    try:
        sql(f"CREATE DATABASE {schema}; CREATE USER '{schema}'@'%' IDENTIFIED BY '{password}'; "
            f"GRANT ALL ON {schema}.* TO '{schema}'@'%'; " +
            ''.join(f'CREATE TABLE {schema}.{table} LIKE {database}.{table};' for table in tables) +
            f"INSERT INTO {schema}.network_accounts(id,email,password_hash) VALUES ('{owner}','fixture@example.invalid','not-a-login-hash'); " +
            f"INSERT INTO {schema}.network_accounts(id,email,password_hash) VALUES ('{other}','other@example.invalid','not-a-login-hash'); " +
            f"UPDATE {schema}.network_accounts SET operator=TRUE WHERE id='{owner}'; " +
            ''.join(f"INSERT INTO {schema}.network_sessions(token_hash,account_id,expires_at) VALUES ('{hashlib.sha256(token.encode()).hexdigest()}','{account}',UTC_TIMESTAMP(6)+INTERVAL 1 HOUR); " for token, account in [(operator_token, owner), (normal_token, other)]) +
            ''.join(f"INSERT INTO {schema}.network_compute_devices(id,owner_id,name,token_hash) VALUES ('{key}','{account}','QA fixture','{secrets.token_hex(32)}'); " for key, account in [(device, owner), (foreign_device, other)]) +
            f"INSERT INTO {schema}.network_telegram_identities(telegram_user_id,owner_id) VALUES (42,'{owner}'); " +
            f"INSERT INTO {schema}.network_ad_settings SELECT * FROM {database}.network_ad_settings; " +
            f"UPDATE {schema}.network_ad_settings SET stars_per_usd=231 WHERE id=1;")
        # Docker reads the temporary credential over stdin, never an argument/file.
        env = '\n'.join([
            f'NETWORK_DATABASE_URL=mysql://{schema}:{password}@{source.hostname}:{source.port or 3306}/{schema}',
            'NETWORK_BIND=0.0.0.0:4352',
            'NETWORK_TELEGRAM_WORKER_TOKEN_HASH=' + hashlib.sha256(worker.encode()).hexdigest(),
        ]) + '\n'
        run(['docker', 'run', '-d', '--name', name, '--network', 'gochain_default',
             '--env-file', '/dev/stdin', '-p', '127.0.0.1::4352', '--read-only',
             '--cap-drop', 'ALL', '--memory', '256m', '--cpus', '0.5', current['Image']], input=env.encode())
        container = json.loads(run(['docker', 'inspect', name]).stdout)[0]
        port = container['NetworkSettings']['Ports']['4352/tcp'][0]['HostPort']
        url = 'http://127.0.0.1:' + port + '/api/network/v1/internal/telegram/ads'

        def request(action, expected=200, **fields):
            req = Request(url, data=json.dumps({'telegram_user_id': 42, 'action': action, **fields}).encode(),
                          headers={'Content-Type': 'application/json', 'x-network-bot-token': worker})
            try:
                with urlopen(req, timeout=10) as response:
                    assert response.status == expected
                    return json.load(response)
            except HTTPError as error:
                assert error.code == expected, (action, error.code)
                return {}

        for attempt in range(40):
            try:
                assert request('status')['ads_enabled']
                break
            except (URLError, ConnectionError):
                if attempt == 39:
                    raise
                time.sleep(0.5)
        evidence.append('default ads enabled')

        def account_api(path, payload=None, token=operator_token, expected=(200,)):
            req = Request('http://127.0.0.1:' + port + '/api/network/v1/' + path,
                          data=json.dumps(payload).encode() if payload is not None else None,
                          headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token})
            try:
                with urlopen(req, timeout=10) as response:
                    assert response.status in expected
                    return json.load(response)
            except HTTPError as error:
                assert error.code in expected, (path, error.code)
                return {}

        grant = {'owner_id': owner, 'device_id': None, 'months': 1, 'note': 'Disposable Cleaner acceptance fixture'}
        account_api('operator/ads', grant, token=normal_token, expected=(401, 403))
        account_api('operator/ads', {**grant, 'device_id': foreign_device}, expected=(400,))
        global_grant = account_api('operator/ads', grant)['id']
        assert not request('status')['ads_enabled']
        account_api('operator/ads/' + global_grant + '/revoke', {})
        assert request('status')['ads_enabled']
        local_grant = account_api('operator/ads', {**grant, 'device_id': device})['id']
        assert not account_api('ads/status?device_id=' + device)['ads_enabled']
        assert request('status')['ads_enabled']
        account_api('operator/ads/' + local_grant + '/revoke', {})
        assert account_api('ads/status?device_id=' + device)['ads_enabled']
        evidence.extend(['non-operator cannot grant', 'foreign device rejected',
                         'admin account grant and revoke', 'admin device grant stays device scoped'])
        orders = []
        for months, charge in [(1, 'fixture-charge-1'), (2, 'fixture-charge-2')]:
            invoice = request('invoice', months=months)
            payment = {'order_id': invoice['order_id'], 'currency': 'XTR', 'total_amount': invoice['total_amount']}
            request('precheckout', expected=400, **{**payment, 'total_amount': payment['total_amount'] + 1})
            assert request('precheckout', **payment)['ok']
            assert request('status')['ads_enabled'] == (len(orders) == 0)
            assert not request('paid', charge_id=charge, **payment)['ads_enabled']
            assert request('paid', charge_id=charge, **payment)['replayed']
            orders.append((payment, charge))
        evidence.extend(['incorrect amount rejected', 'precheckout grants nothing',
                         'two paid orders stack', 'duplicate charge is idempotent'])
        count = sql(f"SELECT COUNT(*) FROM {schema}.network_ad_grants WHERE revoked_at IS NULL;")
        assert count == '2'
        before = request('status')['expires_at']
        assert not request('refund', charge_id=orders[0][1], **orders[0][0])['ads_enabled']
        assert request('status')['expires_at'] < before
        request('refund', charge_id=orders[0][1], **orders[0][0])
        assert request('refund', charge_id=orders[1][1], **orders[1][0])['ads_enabled']
        evidence.extend(['refund removes its stacked interval', 'refund replay is idempotent',
                         'last refund restores ads'])
        print(json.dumps({'authority_image': current['Image'], 'checks': evidence,
                          'real_payment': False, 'production_rows_written': 0}))
    finally:
        subprocess.run(['docker', 'rm', '-f', name], capture_output=True)
        sql(f"DROP DATABASE IF EXISTS {schema}; DROP USER IF EXISTS '{schema}'@'%';")
        assert subprocess.run(['docker', 'inspect', name], capture_output=True).returncode != 0
        assert sql(f"SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='{schema}';") == '0'
        print(json.dumps({'temporary_schema_removed': schema, 'temporary_container_removed': name}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(json.dumps({'verified': False, 'error_type': type(error).__name__}))
        raise SystemExit(1)
