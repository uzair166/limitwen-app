#!/usr/bin/env python3
"""Load the actual npm payload with SwiftPM, without accounts or live providers."""
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import tarfile
import tempfile

root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='limitwen-npm-package-') as directory:
    target = Path(directory)
    packed = subprocess.check_output(['npm', 'pack', '--ignore-scripts', '--json', '--pack-destination', str(target)], cwd=root, text=True)
    filename = json.loads(packed)[0]['filename']
    with tarfile.open(target / filename) as archive:
        for member in archive.getmembers():
            path = PurePosixPath(member.name)
            assert not path.is_absolute() and '..' not in path.parts and path.parts[0] == 'package'
            assert member.isfile() or member.isdir(), 'Package must not contain filesystem links'
            destination = target / member.name
            if member.isdir(): destination.mkdir(parents=True, exist_ok=True)
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(archive.extractfile(member).read())
                destination.chmod(member.mode & 0o777)
    manifest = subprocess.check_output(['xcrun', 'swift', 'package', '--package-path', str(target / 'package'), 'describe', '--type', 'json'], text=True)
    targets = {entry['name'] for entry in json.loads(manifest)['targets']}
    assert {'Limitwen', 'LimitwenCoreTests', 'LimitwenAppTests'} <= targets
    assert (target / 'package/LICENSE').is_file()
    assert (target / 'package/vendor/Limitwen.zip').is_file(), 'The signed app must be bundled in npm'
    version = subprocess.check_output(['node', str(target / 'package/bin/limitwen.mjs'), '--version'], text=True).strip()
    assert version == json.loads((target / 'package/package.json').read_text())['version']
    print('PASS: npm payload includes the signed app, source targets, license and working launcher')
