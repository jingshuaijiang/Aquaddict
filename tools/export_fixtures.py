#!/usr/bin/env python3
"""Export golden fixtures for DiveKit tests from the real Shearwater DB.

Writes, per picked dive: raw decompressed PNF bytes + expected parse output
from the validated Python parser. Also a summary of all 47 dives, and every
dive's raw PNF for the full regression test.
"""
import gzip
import json
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))
from parse_dives import DB_PATH, parse_pnf

FIX = Path(__file__).parent.parent / "DiveKit/Sources/divekit-tests/Fixtures"
PICKS = {0, 31, 46}   # factory deep test, deepest real dive, latest long dive

(FIX / "AllDives").mkdir(parents=True, exist_ok=True)
db = sqlite3.connect(DB_PATH)
rows = db.execute(
    "select d.DiveNumber, l.log_id, l.data_bytes_1 from dive_details d "
    "join log_data l on l.log_id = d.DiveId order by d.DiveDate").fetchall()

summary = []
for num, log_id, blob in rows:
    raw = gzip.decompress(blob[4:])
    header, samples = parse_pnf(raw)
    n = int(num)
    summary.append({"n": n, "maxDepth": round(max(s["depth_m"] for s in samples), 2),
                    "nSamples": header["n_samples"], "gfLow": header["gf_low"],
                    "gfHigh": header["gf_high"], "mode": header["mode"],
                    "surfaceMbar": header["surface_mbar"]})
    (FIX / "AllDives" / f"dive_{n:03d}.pnf.bin").write_bytes(raw)
    if n in PICKS:
        (FIX / f"dive_{n:03d}.pnf.bin").write_bytes(raw)
        (FIX / f"dive_{n:03d}.golden.json").write_text(
            json.dumps({"header": header, "samples": samples}, indent=1))
(FIX / "all_dives_summary.golden.json").write_text(json.dumps(summary, indent=1))
print(f"wrote {len(PICKS)} fixture dives + {len(summary)} raw logs + summary")
