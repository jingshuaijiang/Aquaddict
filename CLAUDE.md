# CLAUDE.md — contributor guide for AI (and human) collaborators

## What this project is

Aquaddict: a personal iOS dive log that talks directly to Shearwater dive
computers over BLE. Owner dives Perdix 3 + Peregrine and trains toward GUE
standards — precision of dive data matters more than feature count here.

## Architecture (keep this separation)

- **`DiveKit/`** — platform-independent core. Pure Swift, **zero dependencies,
  no UIKit/SwiftUI/CoreBluetooth**. Parsing (`PNFParser`), protocol
  (`Shearwater/`), math (`TrainingMetrics`, `GasPhysics`, `GasPlanner`).
  Anything computable belongs here, with tests.
- **`DiveTraceApp/`** — SwiftUI app. Views are thin; stores
  (`DiveStore`, `SiteStore`, `BuddyStore`, `PhotoStore`) are `@MainActor
  @Observable` singletons persisting JSON/files to Documents.
  `BLE/ShearwaterBLE.swift` is the only CoreBluetooth code — it implements
  DiveKit's `ShearwaterTransport` protocol.

## Non-negotiable invariants

1. **Parser changes must pass the golden fixtures.** `parse_dives.py` is the
   reference implementation; `DiveKit/Sources/divekit-tests/Fixtures/` holds
   real-dive golden data. If you change field extraction, regenerate fixtures
   with `tools/export_fixtures.py` and explain why values changed.
   Offsets come from libdivecomputer's `shearwater_predator_parser.c` — cite
   the line when adding a field.
2. **Run `cd DiveKit && swift run divekit-tests` before any commit touching
   DiveKit.** (Custom zero-dependency runner — CLT had no XCTest when this
   started. Migrating to swift-testing is welcome.)
3. **Terminology follows Shearwater**: SAC = pressure rate (psi/min | bar/min),
   RMV = volume rate (ft³/min | L/min). The owner will catch mistakes here.
4. **Every user-facing string is bilingual** via `loc("中文", "English")`
   (follows system language). Every quantity goes through `U.*` formatters
   (metric/imperial toggle).
5. **Raw PNF blobs are never discarded** — dives are stored as raw bytes and
   re-parsed on load, so parser improvements retroactively fix old dives.
6. Dive identity = PNF start timestamp (`DiveHeader.startTimestamp`), which is
   the device's wall clock encoded as epoch — always format dates with a UTC
   formatter to read wall-clock fields back (`Dive.dateText`).

## Workflows

```bash
# core tests
cd DiveKit && swift run divekit-tests

# regenerate app project after adding/removing files (required!)
cd DiveTraceApp && xcodegen generate

# simulator build
xcodebuild -project DiveTrace.xcodeproj -scheme DiveTrace \
  -destination 'generic/platform=iOS Simulator' build

# device build + install (owner's setup)
xcodebuild -project DiveTrace.xcodeproj -scheme DiveTrace \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates \
  -derivedDataPath build build
xcrun devicectl device install app --device <UDID> \
  build/Build/Products/Debug-iphoneos/DiveTrace.app
```

- New Swift files are **not** picked up until `xcodegen generate` runs.
- BLE cannot be tested in the simulator. The protocol layer *can* be tested
  headlessly — see `FakeShearwater` in the DiveKit tests, which speaks the
  device side of the protocol and serves real dive fixtures.
- Data source for bundled dives: `tools/export_app_bundle.py` reads the
  owner's local Shearwater Cloud SQLite DB. Don't assume it exists on other
  machines.

## Design language

Committed dark deep-ocean theme (`Theme.swift`): abyss navy ground,
bioluminescent cyan accent, monospaced numerals for instrument readouts.
Series colors: depth cyan `#1D9DB5`, temp amber `#C86F22`, NDL/ppO₂ violet
`#7E6EE0`, SAC green `#74B35A`, violations red `#E85D4A` (reserved).
No dual value axes on charts — overlays are normalized bands with true values
in the scrubber readout. Chinese-first copy, no "engineer aesthetic" tables.

## Known debts / next candidates

- iCloud backup (sites/buddies/photos die with an uninstall today)
- Auto-match photos from the system library by dive time window
- Marker events (PNF record `0x30`) on the chart for cave training
- Tank size settings so RMV stops assuming AL80 (11.1 L)
- Migrate divekit-tests to swift-testing now that Xcode is available
- Dual-computer duplicate merge (same dive on two wrists) is designed
  (dedupe by start-timestamp proximity) but only exact-match implemented
