#!/usr/bin/env python3
"""Export the user's real dives into the DiveTrace app bundle resources.

Until BLE download lands, the app ships with the user's own 47 dives: raw PNF
logs (parsed at launch by DiveKit) plus a meta.json carrying what PNF alone
doesn't give us yet (dive number, start date, demo training tags).
"""
import gzip
import json
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))
from parse_dives import DB_PATH

OUT = Path(__file__).parent.parent / "DiveTraceApp/Resources/Dives"
OUT.mkdir(parents=True, exist_ok=True)

db = sqlite3.connect(DB_PATH)
rows = db.execute(
    "select d.DiveNumber, d.DiveDate, l.data_bytes_1 from dive_details d "
    "join log_data l on l.log_id = d.DiveId order by d.DiveDate").fetchall()

meta = []
for num, date, blob in rows:
    n = int(num)
    (OUT / f"dive_{n:03d}.pnf").write_bytes(gzip.decompress(blob[4:]))
    meta.append({"n": n, "date": date, "training": n >= 27})
(OUT / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1))
print(f"exported {len(meta)} dives to {OUT}")
