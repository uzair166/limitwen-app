#!/usr/bin/env python3
"""Check toolchain selection without invoking a compiler or changing xcode-select."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="limitwen-toolchain-") as directory:
    temporary = Path(directory)
    stub = temporary / "xcrun"
    stub.write_text('#!/bin/sh\nprintf "%s" "${DEVELOPER_DIR-<unset>}" > "$LIMITWEN_TOOLCHAIN_LOG"\nexit 37\n')
    stub.chmod(0o700)
    for script in ["test.sh", "build.sh"]:
        for override in [None, "/fixture/Custom Xcode.app/Contents/Developer"]:
            log = temporary / "selection"
            environment = dict(os.environ)
            environment.pop("DEVELOPER_DIR", None)
            if override is not None:
                environment["DEVELOPER_DIR"] = override
            environment["PATH"] = str(temporary) + os.pathsep + environment["PATH"]
            environment["LIMITWEN_TOOLCHAIN_LOG"] = str(log)
            result = subprocess.run([str(root / "scripts" / script)], env=environment, capture_output=True)
            assert result.returncode == 37, "The script must stop at the stub compiler"
            assert log.read_text() == (override or "<unset>"), f"{script} overrides the selected developer directory"
    print("PASS: build/test honor xcode-select and explicit DEVELOPER_DIR overrides")
