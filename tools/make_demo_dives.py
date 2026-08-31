#!/usr/bin/env python3
"""Build the sanitized demo dives bundled with the public App Store build.

Takes three real dives (owner-approved, Shearwater-Cloud logv13 exports that
never contained GNSS records), then:
  - rewrites the start timestamp (opening record 0, bytes 12-15 BE) to a
    fictional 2026 date, removing the only personal identifier in the blob
  - bumps logVersion (opening record 4, byte 16) to 17 and injects GNSS
    opening/closing records 9 with coordinates of famous public dive sites,
    so the map tab demos without hardware
  - synthesizes a plausible AI tank-pressure trace (sample bytes 28-29,
    12-bit half-psi units) so SAC/RMV/calorie features demo too

Output: DiveTraceApp/Resources/Dives/dive_00{0,1,2}.pnf + meta.json.
Run from repo root: python3 tools/make_demo_dives.py <source-dir>
(source-dir = a copy of the original 47-dive bundle; not in the repo
once the bundle is demo-only — the owner's Shearwater Cloud DB or the
DiveKit fixtures can regenerate the sources.)
"""
import json
import math
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "DiveTraceApp/Resources/Dives"

# (source file, new wall-clock start, lat, lon, site, training)
DEMOS = [
    ("dive_001.pnf", "2026-03-14 09:42:00", -8.27410, 115.59310,
     "USS Liberty, Tulamben", False),
    ("dive_026.pnf", "2026-05-02 10:15:00", 7.13570, 134.22230,
     "Blue Corner, Palau", False),
    ("dive_046.pnf", "2026-07-18 08:30:00", 50.83600, -127.64600,
     "Browning Pass, God's Pocket", True),
]

FEET = 0.3048


def be16(b, o):
    return (b[o] << 8) | b[o + 1]


def gnss_record(kind, lat, lon):
    rec = bytearray(32)
    rec[0] = kind                      # 0x19 opening / 0x29 closing
    rec[16] = 3                        # 3D fix
    rec[21:25] = struct.pack(">i", round(lat * 100000))
    rec[25:29] = struct.pack(">i", round(lon * 100000))
    return bytes(rec)


def sanitize(raw, start, lat, lon):
    recs = [bytearray(raw[i:i + 32]) for i in range(0, len(raw) - 31, 32)]
    opening = {r[0] - 0x10: r for r in recs if 0x10 <= r[0] <= 0x19}

    ts = int(datetime.strptime(start, "%Y-%m-%d %H:%M:%S")
             .replace(tzinfo=timezone.utc).timestamp())
    opening[0][12:16] = struct.pack(">I", ts)
    opening[4][16] = 17               # logVersion >= 17 so GNSS is parsed

    imperial = opening[0][8] == 1
    interval_min = be16(opening[5], 23) / 60000

    # synthetic AI: 3000 psi start, surface SAC ~0.85 bar/min scaled by
    # ambient pressure, gentle wobble so the SAC band isn't a flat line
    bar = 206.8
    n = 0
    for r in recs:
        if r[0] != 0x01 or not any(r):
            continue
        depth_raw = be16(r, 1)
        depth_m = depth_raw * (FEET / 10 if imperial else 0.1)
        ata = 1 + depth_m / 10.0
        bar -= 0.85 * ata * interval_min * (1 + 0.25 * math.sin(n / 9))
        bar = max(bar, 30.0)
        r[28:30] = struct.pack(">H", int(bar * 14.5037738 / 2) & 0x0FFF)
        n += 1

    # inject the GNSS records ahead of the final (0xFF) record
    body = [bytes(r) for r in recs]
    tail = 1 if body and body[-1][0] == 0xFF else 0
    insert = [gnss_record(0x19, lat, lon),
              gnss_record(0x29, lat + 0.0009, lon + 0.0012)]
    body = body[:len(body) - tail] + insert + body[len(body) - tail:]
    return b"".join(body), ts


def main(srcdir):
    src = Path(srcdir)
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.pnf"):
        old.unlink()
    meta = []
    for i, (name, start, lat, lon, site, training) in enumerate(DEMOS):
        cleaned, ts = sanitize((src / name).read_bytes(), start, lat, lon)
        (OUT / f"dive_{i:03d}.pnf").write_bytes(cleaned)
        meta.append({"n": i, "date": start, "training": training})
        print(f"dive_{i:03d}.pnf  {start}  {site}  ts={ts}")
    (OUT / "meta.json").write_text(json.dumps(meta, indent=1))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else OUT)
