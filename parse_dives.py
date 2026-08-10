#!/usr/bin/env python3
"""Parse per-second depth/temperature profiles from Shearwater Cloud's local database.

The dive samples live in `log_data.data_bytes_1`: a 4-byte length prefix followed by
a gzip stream. Decompressed, it is Shearwater's PNF format — a sequence of 32-byte
records. Field offsets follow libdivecomputer's shearwater_predator_parser.c.

Usage:
    python3 parse_dives.py              # list all dives
    python3 parse_dives.py 46           # parse dive #46, print profile + write CSV
    python3 parse_dives.py all          # export every dive to csv/
"""

import csv
import gzip
import sqlite3
import struct
import sys
from pathlib import Path

DB_PATH = Path.home() / (
    "Library/Containers/research.shearwater.cloud/Data/Library/Application Support/"
    "research.shearwater.cloud/users/jjsbanana@gmail.com/dive_data.db"
)

RECORD_SIZE = 32  # SZ_SAMPLE_PETREL

# Record types (first byte of each 32-byte record)
DIVE_SAMPLE = 0x01
OPENING = range(0x10, 0x1A)
CLOSING = range(0x20, 0x2A)
FINAL = 0xFF

FEET = 0.3048
PSI_PER_BAR = 14.5037738


def be16(buf, off):
    return struct.unpack_from(">H", buf, off)[0]


def parse_pnf(raw):
    """Parse a decompressed PNF blob into (header dict, list of sample dicts)."""
    opening = {}
    closing = {}
    records = [raw[i:i + RECORD_SIZE] for i in range(0, len(raw) - RECORD_SIZE + 1, RECORD_SIZE)]

    for rec in records:
        t = rec[0]
        if t in OPENING:
            opening[t - 0x10] = rec
        elif t in CLOSING:
            closing[t - 0x20] = rec

    # Units flag: byte 8 of opening record 0 (0 = metric, 1 = imperial)
    imperial = opening[0][8] == 1
    logversion = opening[4][16] if 4 in opening else 0
    # Sample interval in ms: u16 at bytes 23-24 of opening record 5
    interval_ms = be16(opening[5], 23) if (logversion >= 9 and 5 in opening) else 10000

    samples = []
    t_ms = 0
    for rec in records:
        if rec[0] != DIVE_SAMPLE or not any(rec):
            continue
        t_ms += interval_ms

        depth_raw = be16(rec, 1)          # 1/10 m or 1/10 ft
        depth_m = depth_raw * FEET / 10.0 if imperial else depth_raw / 10.0

        temp = struct.unpack_from("b", rec, 14)[0]  # signed byte, °C or °F
        if temp < 0:
            temp = min(temp + 102, 0)     # libdivecomputer's negative-temp fix
        temp_c = (temp - 32.0) * 5.0 / 9.0 if imperial else float(temp)

        deco_stop = be16(rec, 3)          # first stop depth (m/ft), 0 = no deco
        tts_min = be16(rec, 5)            # time to surface, minutes
        ndl_min = rec[10]                 # no-deco limit, minutes
        avg_ppo2 = rec[7] / 100.0
        o2, he = rec[8], rec[9]

        s = {
            "time_s": t_ms // 1000,
            "depth_m": round(depth_m, 2),
            "temp_c": round(temp_c, 1),
            "ndl_min": ndl_min,
            "tts_min": tts_min,
            "deco_stop": deco_stop,
            "avg_ppo2": avg_ppo2,
            "o2": o2,
            "he": he,
        }

        # Tank pressure (AI transmitters), logversion >= 7: u16 at offsets 28 and 20
        if logversion >= 7:
            for name, off in (("tank1_bar", 28), ("tank2_bar", 20)):
                p = be16(rec, off)
                if p < 0xFFF0 and (p & 0x0FFF):
                    s[name] = round((p & 0x0FFF) * 2 / PSI_PER_BAR, 1)

        samples.append(s)

    header = {
        "imperial": imperial,
        "logversion": logversion,
        "interval_ms": interval_ms,
        "n_samples": len(samples),
    }
    return header, samples


def load_dive(db, dive_id):
    blob = db.execute(
        "select data_bytes_1 from log_data where log_id = ?", (dive_id,)
    ).fetchone()[0]
    return parse_pnf(gzip.decompress(blob[4:]))  # skip 4-byte length prefix


def ascii_plot(samples, width=60, height=15):
    max_depth = max(s["depth_m"] for s in samples) or 1
    step = max(1, len(samples) // width)
    cols = [samples[i]["depth_m"] for i in range(0, len(samples), step)][:width]
    lines = []
    for row in range(height):
        threshold = max_depth * row / (height - 1)
        lines.append("".join("█" if d >= threshold else " " for d in cols))
    lines[0] = "0m " + lines[0][3:]
    lines[-1] = f"{max_depth:.0f}m".ljust(3) + lines[-1][3:]
    return "\n".join(lines)


def main():
    db = sqlite3.connect(DB_PATH)
    dives = db.execute(
        "select d.DiveNumber, d.DiveDate, d.Depth, d.DiveLengthTime, l.log_id "
        "from dive_details d join log_data l on l.log_id = d.DiveId "
        "order by d.DiveDate"
    ).fetchall()

    arg = sys.argv[1] if len(sys.argv) > 1 else None

    if arg is None:
        print(f"{'#':>3}  {'date':19}  {'max m':>6}  {'length':>7}")
        for num, date, depth, secs, _ in dives:
            print(f"{num:>3}  {date:19}  {float(depth):6.1f}  {int(secs)//60:4d}:{int(secs)%60:02d}")
        print("\nRun: python3 parse_dives.py <number>   or: python3 parse_dives.py all")
        return

    out_dir = Path(__file__).parent / "csv"
    out_dir.mkdir(exist_ok=True)
    targets = dives if arg == "all" else [d for d in dives if d[0] == arg]
    if not targets:
        sys.exit(f"dive #{arg} not found")

    for num, date, depth, secs, log_id in targets:
        header, samples = load_dive(db, log_id)
        path = out_dir / f"dive_{int(num):03d}_{date[:10]}.csv"
        with open(path, "w", newline="") as f:
            fields = sorted({k for s in samples for k in s}, key=lambda k: k != "time_s")
            w = csv.DictWriter(f, fieldnames=fields)
            w.writeheader()
            w.writerows(samples)
        print(f"dive #{num} {date}: {header['n_samples']} samples @ {header['interval_ms']}ms, "
              f"max {max(s['depth_m'] for s in samples):.1f}m, "
              f"temp {min(s['temp_c'] for s in samples):.0f}-{max(s['temp_c'] for s in samples):.0f}°C "
              f"-> {path.name}")
        if arg != "all":
            print("\n" + ascii_plot(samples) + "\n")
            for s in samples[:5]:
                print(s)


if __name__ == "__main__":
    main()
