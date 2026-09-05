#!/usr/bin/env python3
"""Add an already-uploaded TestFlight build to the public external test group."""
import base64
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec, utils
from cryptography.hazmat.primitives.serialization import load_pem_private_key

APP_ID = '6775334838'
PUBLIC_GROUP_ID = '3ad8d7be-4344-4dda-98c1-3c91d823cf57'

key_id = os.environ['APP_STORE_CONNECT_KEY_ID']
issuer_id = os.environ['APP_STORE_CONNECT_ISSUER_ID']
key = load_pem_private_key(os.environ['APP_STORE_CONNECT_PRIVATE_KEY'].encode(), password=None)
build_number = os.environ['BUILD_NUMBER']


def b64(value):
    return base64.urlsafe_b64encode(value).rstrip(b'=')


def token():
    now = int(time.time())
    header = b64(json.dumps({'alg': 'ES256', 'kid': key_id, 'typ': 'JWT'}).encode())
    payload = b64(json.dumps({'iss': issuer_id, 'iat': now, 'exp': now + 600, 'aud': 'appstoreconnect-v1'}).encode())
    message = header + b'.' + payload
    r, s = utils.decode_dss_signature(key.sign(message, ec.ECDSA(hashes.SHA256())))
    signature = b64(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))
    return (message + b'.' + signature).decode()


def api(path, body=None, method=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        'https://api.appstoreconnect.apple.com/v1/' + path,
        data=data,
        headers={'Authorization': 'Bearer ' + token(), 'Content-Type': 'application/json'},
        method=method,
    )
    with urllib.request.urlopen(req, timeout=30) as response:
        raw = response.read()
        return json.loads(raw) if raw else {}


builds = api('builds?' + urllib.parse.urlencode({
    'filter[app]': APP_ID,
    'filter[version]': build_number,
}))['data']
if len(builds) != 1:
    raise SystemExit(f'Expected exactly one build with version {build_number}, found {len(builds)}')
build = builds[0]
state = build['attributes']['processingState']
if state != 'VALID':
    raise SystemExit(f'Build {build_number} is not ready yet (processingState={state})')
build_id = build['id']
print(f'Found build {build_id} (version {build_number}, state {state})')

try:
    api(f'betaGroups/{PUBLIC_GROUP_ID}/relationships/builds', method='POST', body={
        'data': [{'type': 'builds', 'id': build_id}],
    })
    print('Added build to the public external group')
except urllib.error.HTTPError as e:
    if e.code == 409:
        print('Build was already in the public external group:', e.read().decode())
    else:
        raise SystemExit(f'Failed to add build to public group: {e.code} {e.read().decode()}')

try:
    submission = api('betaAppReviewSubmissions', method='POST', body={
        'data': {
            'type': 'betaAppReviewSubmissions',
            'relationships': {'build': {'data': {'type': 'builds', 'id': build_id}}},
        },
    })
    print('Submitted for Beta App Review:', submission['data']['id'])
except urllib.error.HTTPError as e:
    if e.code == 409:
        print('Build already submitted for Beta App Review:', e.read().decode())
    else:
        raise SystemExit(f'Failed to submit build for Beta App Review: {e.code} {e.read().decode()}')
