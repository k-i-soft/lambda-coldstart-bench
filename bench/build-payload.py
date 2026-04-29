#!/usr/bin/env python3
"""Erzeugt eine Bench-Payload mit frischer UUID. Schreibt JSON nach stdout.

Aufruf:
    python3 build-payload.py 1k    # 1024 byte
    python3 build-payload.py 100k  # 102400 byte
    python3 build-payload.py 1m    # 1048576 byte

Die Ziel-Groesse bezieht sich auf die UTF-8-Bytelaenge der gesamten Antwort
(also inklusive JSON-Wrapping). Damit ist die transportierte Lambda-Payload
fuer jede Stufe genau so gross wie der Label sagt.
"""

from __future__ import annotations

import json
import sys
import uuid

SIZES = {
    "1k": 1024,
    "100k": 102400,
    "1m": 1048576,
}


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in SIZES:
        print(f"Usage: {sys.argv[0]} {{{'|'.join(SIZES)}}}", file=sys.stderr)
        return 2

    target = SIZES[sys.argv[1]]
    uid = str(uuid.uuid4())

    skeleton = json.dumps({"id": uid, "payload": ""}, separators=(",", ":"))
    overhead = len(skeleton.encode("utf-8"))
    fill_len = max(1, target - overhead)
    payload = "a" * fill_len

    out = json.dumps({"id": uid, "payload": payload}, separators=(",", ":"))
    sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
