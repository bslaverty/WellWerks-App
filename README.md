# WellWerks Flutter

Flutter foundation for the WellWerks oilfield toolbox app.

## Current update

- Numeric fields now request the phone number keypad.
- Rate calculators start blank instead of using pre-filled/sample values.
- Gauge fields still allow entries like `12 3/8`.
- Production Tank keeps default Tank Factor at `1.67 BBL/In`, with other fields blank.
- Added Shift Report screen that pulls the latest Quick Round reading and formats Mach Energy / Continental previews for copy to iMessage.
- Production Inventory supports oil/water produced, hauled, pumped, optional capacity, and 75% near-full alert logic.

## Run locally

```bash
flutter pub get
flutter run
```
