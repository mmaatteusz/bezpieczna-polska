#!/usr/bin/env python3
"""Check original release artifacts before a real-device migration test.

Conservative policy: key rotation needs a separate Android-version/lineage test.
This checks artifacts only, never claims that app data or FCM survived an update.
"""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path


def inspect(path, aapt, apksigner):
    signature = subprocess.check_output(
        [apksigner, 'verify', '--print-certs', str(path)], text=True)
    badging = subprocess.check_output([aapt, 'dump', 'badging', str(path)], text=True)
    package = re.search(r"^package: name='([^']+)' versionCode='(\d+)'", badging, re.M)
    certs = re.findall(r'^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]{64})$', signature, re.M)
    if package is None or not certs:
        raise ValueError('Cannot read package, versionCode or signing certificate')
    digest = hashlib.sha256()
    with path.open('rb') as artifact:
        for chunk in iter(lambda: artifact.read(1024 * 1024), b''):
            digest.update(chunk)
    return dict(sha256=digest.hexdigest(), package=package[1],
                versionCode=int(package[2]), signerSha256=sorted(c.lower() for c in certs))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('previous', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('--package', required=True)
    parser.add_argument('--play-signing-sha256', help='App signing certificate, NOT upload certificate')
    parser.add_argument('--aapt', default='aapt')
    parser.add_argument('--apksigner', default='apksigner')
    args = parser.parse_args()
    old = inspect(args.previous, args.aapt, args.apksigner)
    new = inspect(args.candidate, args.aapt, args.apksigner)
    errors = []
    if old['package'] != args.package or new['package'] != args.package:
        errors.append('Package mismatch: separate applications cannot update each other')
    if new['versionCode'] <= old['versionCode']:
        errors.append('Candidate versionCode must be greater than previous artifact versionCode')
    if old['signerSha256'] != new['signerSha256']:
        errors.append('Signer mismatch: blocked by this policy; assess rotation lineage separately')
    play = args.play_signing_sha256
    if play is not None:
        play = play.replace(':', '').lower()
        if not re.fullmatch(r'[0-9a-f]{64}', play):
            parser.error('Play fingerprint must contain exactly 64 hexadecimal digits')
        if new['signerSha256'] != [play]:
            errors.append('Candidate does not match the supplied Play app signing certificate')
    print(json.dumps(dict(previous=old, candidate=new, errors=errors,
                         artifactCheck='PASS' if not errors else 'FAIL',
                         playCertificateCheck='NOT_CHECKED' if play is None else ('PASS' if new['signerSha256'] == [play] else 'FAIL'),
                         dataMigration='NOT_TESTED', pushDelivery='NOT_TESTED'), indent=2))
    return 1 if errors else 0


if __name__ == '__main__':
    raise SystemExit(main())
