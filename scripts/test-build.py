#!/usr/bin/env python3
"""Bundle replacement regressions using disposable files and stub tools."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parent / 'build.sh'

class BundleReplacement(unittest.TestCase):
    def run_build(self, failure=False, running=False):
        directory = tempfile.TemporaryDirectory(prefix='limitwen-build-test-')
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        for name in ['scripts', 'Resources', 'build/Limitwen.app/Contents/MacOS', 'tools', 'binaries']:
            (root / name).mkdir(parents=True)
        shutil.copy2(SOURCE, root / 'scripts/build.sh')
        (root / 'Resources/Info.plist').write_text('fixture')
        (root / 'build/Limitwen.icns').write_text('fixture')
        installed = root / 'build/Limitwen.app/Contents/MacOS/Limitwen'
        installed.write_text('old working executable')
        for name in ['Limitwen', 'LimitwenRelay']:
            (root / 'binaries' / name).write_text('new executable')
        scripts = {
            'xcrun': '#!/bin/sh\ncase "$*" in *--show-bin-path*) printf "%s\\n" "$FIXTURE_BIN";; esac\n',
            'codesign': '#!/bin/sh\nexit "${FIXTURE_SIGN_FAILURE:-0}"\n',
            'pgrep': '#!/bin/sh\nif [ "$FIXTURE_RUNNING" = 1 ]; then echo 123; else exit 1; fi\n',
            'ps': '#!/bin/sh\nprintf "%s\\n" "$FIXTURE_APP"\n',
        }
        for name, source in scripts.items():
            tool = root / 'tools' / name; tool.write_text(source); tool.chmod(0o700)
        env = dict(os.environ, PATH=str(root / 'tools') + os.pathsep + os.environ['PATH'],
            FIXTURE_BIN=str(root / 'binaries'), FIXTURE_APP=str(installed),
            FIXTURE_RUNNING='1' if running else '0', FIXTURE_SIGN_FAILURE='9' if failure else '0')
        result = subprocess.run(['/bin/zsh', str(root / 'scripts/build.sh'), 'release'], env=env, capture_output=True, text=True)
        return root, installed, result

    def test_failed_signing_preserves_installed_app(self):
        root, installed, result = self.run_build(failure=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(installed.read_text(), 'old working executable')

    def test_running_copy_is_not_replaced(self):
        root, installed, result = self.run_build(running=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(installed.read_text(), 'old working executable')
        self.assertIn('Quit', result.stderr)

    def test_success_replaces_bundle_and_removes_staging(self):
        root, installed, result = self.run_build()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(installed.read_text(), 'new executable')
        self.assertEqual(list((root / 'build').glob('.limitwen-stage-*')), [])

if __name__ == '__main__':
    unittest.main()
