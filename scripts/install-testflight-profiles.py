#!/usr/bin/env python3
"""Install the three App Store profiles and generate manual export options."""
import base64
import datetime
import hashlib
import os
from pathlib import Path
import plistlib
import re
import subprocess

options = plistlib.loads(Path('export/TestFlightExportOptions.plist').read_bytes())
profiles = {
    'com.svk-team.encx-cli': os.environ['IOS_APP_STORE_PROFILE_APP'],
    'com.svk-team.encx-cli.widget': os.environ['IOS_APP_STORE_PROFILE_WIDGET'],
    'com.svk-team.encx-cli.Clip': os.environ['IOS_APP_STORE_PROFILE_CLIP'],
}
identities = subprocess.check_output([
    'security', 'find-identity', '-v', '-p', 'codesigning',
    str(Path(os.environ['RUNNER_TEMP']) / 'app-signing.keychain-db'),
], text=True)
certificates = set(re.findall(r'\b([A-F0-9]{40})\b', identities))
directory = Path.home() / 'Library/Developer/Xcode/UserData/Provisioning Profiles'
directory.mkdir(parents=True, exist_ok=True)
options['provisioningProfiles'] = {}
for bundle, encoded in profiles.items():
    content = base64.b64decode(encoded, validate=True)
    profile = plistlib.loads(subprocess.check_output(['security', 'cms', '-D'], input=content))
    entitlements = profile['Entitlements']
    if (profile['TeamIdentifier'] != [options['teamID']]
            or entitlements['application-identifier'] != options['teamID'] + '.' + bundle
            or entitlements.get('get-task-allow', False)
            or not entitlements.get('beta-reports-active', False)
            or 'ProvisionedDevices' in profile
            or profile.get('ProvisionsAllDevices', False)
            or profile['ExpirationDate'] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)):
        raise SystemExit('Invalid or expired App Store profile for ' + bundle)
    certificates &= {hashlib.sha1(cert).hexdigest().upper() for cert in profile['DeveloperCertificates']}
    uuid = profile['UUID']
    if not re.fullmatch(r'[A-Fa-f0-9-]{36}', uuid):
        raise SystemExit('Invalid profile UUID')
    (directory / (uuid + '.mobileprovision')).write_bytes(content)
    options['provisioningProfiles'][bundle] = uuid
    print('Installed App Store profile for ' + bundle)
if not certificates:
    raise SystemExit('App Store profiles do not match any installed signing identity')
options['signingCertificate'] = sorted(certificates)[0]
options['signingStyle'] = 'manual'
Path('build').mkdir(exist_ok=True)
Path('build/TestFlightExportOptions.plist').write_bytes(plistlib.dumps(options))
