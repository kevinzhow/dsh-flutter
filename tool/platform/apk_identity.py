#!/usr/bin/env python3
"""Verify one APK's application identity and signing certificate without key access."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path


def identity(apk, apksigner, aapt):
    signer = subprocess.run([str(apksigner), 'verify', '--verbose', '--print-certs', str(apk)], capture_output=True, text=True, check=True).stdout
    certificates = re.findall(r'^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]+)$', signer, re.M)
    if len(certificates) != 1:
        raise ValueError('Exactly one APK signer is required')
    badging = subprocess.run([str(aapt), 'dump', 'badging', str(apk)], capture_output=True, text=True, check=True).stdout
    package = re.search(r"^package: name='([^']+)' versionCode='(\d+)' versionName='([^']*)'", badging, re.M)
    if package is None:
        raise ValueError('APK package identity is missing')
    return {'package': package[1], 'versionCode': int(package[2]), 'versionName': package[3], 'certificateSha256': certificates[0].lower(), 'apkSha256': hashlib.sha256(apk.read_bytes()).hexdigest(), 'debugCertificate': 'CN=Android Debug' in signer}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--build-tools', type=Path, required=True)
    parser.add_argument('--expected-cert-sha256')
    parser.add_argument('--require-release', action='store_true')
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    result = identity(args.apk, args.build_tools / 'apksigner', args.build_tools / 'aapt')
    if result['package'] != 'app.kevinzhow.whalee':
        parser.error('APK is not Whalee')
    if args.require_release and (not args.expected_cert_sha256 or result['debugCertificate']):
        parser.error('Release verification requires an expected certificate and rejects Android Debug signing')
    if args.expected_cert_sha256 and result['certificateSha256'] != args.expected_cert_sha256.replace(':', '').lower():
        parser.error('APK signing certificate differs from the expected fingerprint')
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: result[k] for k in ['package', 'versionCode', 'versionName', 'debugCertificate']}))


if __name__ == '__main__':
    main()
