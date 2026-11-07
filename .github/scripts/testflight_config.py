"""Validate deployment inputs without printing credentials."""
import os
import re
import subprocess
import sys
import uuid
from pathlib import Path

REQUIRED = ('ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_PRIVATE_KEY',
            'IOS_CERTIFICATE_PRIVATE_KEY', 'ASC_APP_ID')


def validate(env):
    errors = []
    for name in REQUIRED:
        if not env.get(name, '').strip():
            errors.append(f'{name}: not configured')
    if errors:
        return errors
    if not re.fullmatch(r'[A-Z0-9]{10}', env['ASC_KEY_ID'].strip()):
        errors.append('ASC_KEY_ID: invalid Key ID')
    try:
        uuid.UUID(env['ASC_ISSUER_ID'].strip())
    except ValueError:
        errors.append('ASC_ISSUER_ID: invalid Issuer ID')
    if not re.fullmatch(r'[1-9][0-9]*', env['ASC_APP_ID'].strip()):
        errors.append('ASC_APP_ID: use the numeric Apple ID from app information')
    for name, algorithm in [('ASC_PRIVATE_KEY', 'ec'), ('IOS_CERTIFICATE_PRIVATE_KEY', 'rsa')]:
        # Values go to stdin, never command arguments, files, or logs.
        result = subprocess.run(['openssl', 'pkey', '-pubout', '-outform', 'DER', '-passin', 'pass:'],
                                input=env[name].encode(), capture_output=True, timeout=10)
        # SPKI's algorithm identifier precedes the public-key bit string.
        oid = bytes.fromhex('06072a8648ce3d0201' if algorithm == 'ec' else '06092a864886f70d010101')
        valid = result.returncode == 0 and oid in result.stdout[:50]
        if algorithm == 'ec':
            valid = valid and bytes.fromhex('06082a8648ce3d030107') in result.stdout[:50]
        if not valid:
            errors.append(f'{name}: invalid unencrypted PEM private key')
    return errors


def next_build_number(latest):
    latest = latest.strip()
    if latest in ('', 'null', 'None'):
        return '1'
    if not re.fullmatch(r'[0-9]{1,4}(\.[0-9]{1,2}){0,2}', latest):
        raise ValueError('Unexpected Apple build number; refusing to reuse a number')
    parts = [int(p) for p in latest.split('.')]
    for i in range(len(parts) - 1, -1, -1):
        parts[i] += 1
        if parts[i] <= (9999 if i == 0 else 99):
            return '.'.join(map(str, parts))
        parts[i] = 0
    raise ValueError('Build number limit reached')


def select_xcode():
    candidates = []
    for path in Path('/Applications').glob('Xcode*.app'):
        result = subprocess.run(['/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleShortVersionString',
                                 str(path / 'Contents/Info.plist')], capture_output=True, text=True)
        version = result.stdout.strip()
        if result.returncode == 0 and re.fullmatch(r'[0-9]+(\.[0-9]+)*', version):
            numbers = tuple(int(x) for x in version.split('.'))
            if numbers[0] >= 26:
                candidates.append((numbers, path))
    if not candidates:
        raise ValueError('Xcode 26 or later is required for App Store Connect upload')
    print(max(candidates)[1] / 'Contents/Developer')


def workflow_build_number(latest, run_number, run_attempt):
    # Apple can still report the previous build while a just-uploaded IPA is
    # processing. Workflow run/attempt numbers remain unique during that delay.
    next_build_number(latest)  # Validate the API response, including its format.
    if not re.fullmatch(r'[1-9][0-9]{0,3}', run_number or ''):
        raise ValueError('Workflow run number must be between 1 and 9999')
    if not re.fullmatch(r'[1-9][0-9]?', run_attempt or ''):
        raise ValueError('Workflow attempt must be between 1 and 99')
    number = f'{int(run_number)}.{int(run_attempt)}'
    old = '0' if latest.strip() in ('', 'null', 'None') else latest.strip()
    def parts(value):
        values = [int(p) for p in value.split('.')]
        return tuple(values + [0] * (3 - len(values)))
    if parts(number) <= parts(old):
        raise ValueError('Workflow build number must exceed the Apple build number')
    return number


if __name__ == '__main__':
    try:
        command = sys.argv[1]
        if command == 'check':
            errors = validate(os.environ)
            if errors:
                message = '\n'.join(errors)
                print(message, file=sys.stderr)
                summary = os.environ.get('GITHUB_STEP_SUMMARY')
                if summary:
                    with open(summary, 'a') as out:
                        out.write('TestFlight upload is waiting for Apple configuration.\n\n```\n' +
                                  message + '\n```\nSee TESTFLIGHT.md. No upload was attempted.\n')
                sys.exit(1)
            print('TestFlight credentials and app identifier are configured.')
        elif command == 'next-build-number':
            print(next_build_number(sys.stdin.read()))
        elif command == 'workflow-build-number':
            print(workflow_build_number(sys.stdin.read(),
                                        os.environ.get('GITHUB_RUN_NUMBER'),
                                        os.environ.get('GITHUB_RUN_ATTEMPT')))
        elif command == 'select-xcode':
            select_xcode()
        else:
            raise ValueError('Unknown command')
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        # Errors above never include credential values.
        print(str(error), file=sys.stderr)
        sys.exit(1)
