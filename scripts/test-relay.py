#!/usr/bin/env python3
"""End-to-end relay checks. Uses generated inputs and a disposable directory only."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

binary = Path(sys.argv[1] if len(sys.argv) > 1 else ".build/debug/LimitwenRelay").resolve()
with tempfile.TemporaryDirectory(prefix="limitwen-relay-test-") as directory:
    root = Path(directory)
    output = root / "private" / "usage.json"
    payload = {
        "session_id": "DO_NOT_STORE_THIS",
        "workspace": {"current_dir": "/private/fixture"},
        "rate_limits": {
            "five_hour": {"used_percentage": 81, "resets_at": 1800003600},
            "seven_day": {"used_percentage": 31, "resets_at": 1800604800},
        },
        "padding": "x" * 200000,
    }
    data = json.dumps(payload).encode()
    result = subprocess.run([str(binary), "--output", str(output)], input=data, capture_output=True, timeout=5, check=True)
    saved = output.read_text()
    document = json.loads(saved)
    assert [window["usedPercent"] for window in document["windows"]] == [81, 31]
    assert "DO_NOT_STORE_THIS" not in saved and "/private/fixture" not in saved and "padding" not in saved
    assert os.stat(output).st_mode & 0o777 == 0o600
    assert os.stat(output.parent).st_mode & 0o777 == 0o700
    print("PASS: chunked input, normalized quotas, private permissions, metadata discarded")

    for empty in [b'{}', b'{"rate_limits":null}', b'{"rate_limits":{}}']:
        subprocess.run([str(binary), "--output", str(output)], input=empty, capture_output=True, timeout=5, check=True)
        assert output.read_text() == saved, "A session without quota data erased the last real observation"
    print("PASS: sessions without quota data preserve the previous reading and timestamp")

    previous = root / "previous.json"
    previous.write_text(json.dumps({"original": {"command": "exec /bin/cat"}}))
    result = subprocess.run([str(binary), "--output", str(output), "--previous", str(previous)], input=data, capture_output=True, timeout=5, check=True)
    assert result.stdout == data
    print("PASS: existing status-line command receives exact input and preserves output")

    previous.write_text(json.dumps({"original": {"command": "exec /bin/sleep 30"}}))
    start = time.monotonic()
    subprocess.run([str(binary), "--output", str(output), "--previous", str(previous)], input=data, capture_output=True, timeout=5, check=True)
    assert time.monotonic() - start < 4
    print("PASS: a non-reading status-line process cannot block the relay")

    for name, invalid in [("malformed", b"{bad"), ("oversized", b" " * 1048577)]:
        destination = root / (name + ".json")
        subprocess.run([str(binary), "--output", str(destination)], input=invalid, capture_output=True, timeout=5, check=True)
        assert not destination.exists()
        print(f"PASS: {name} input cannot replace a snapshot")

    process = subprocess.Popen([str(binary), "--output", str(root / "unfinished.json")], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    try:
        try:
            process.wait(timeout=4)
        except subprocess.TimeoutExpired:
            raise AssertionError("An input producer that never closes stdin blocks the relay")
        assert not (root / "unfinished.json").exists()
        print("PASS: unfinished stdin has a bounded deadline")
    finally:
        process.kill() if process.poll() is None else None
        process.communicate()
