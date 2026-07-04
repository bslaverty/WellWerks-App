# WellWerks TestFlight Build Notes

This project is set up for the App Store Connect bundle ID:

`com.bslaverty.wellwerksapp`

## Important

For TestFlight, use a **Release Archive** with **Apple Distribution**, not Apple Development. Apple Development profiles require a registered physical iPhone and caused the earlier "no devices" error.

## Mac/Xcode steps

1. Open the project with:

   ```bash
   open ios/Runner.xcworkspace
   ```

2. In Xcode, select:

   `Runner` project → `TARGETS` → `Runner` → `Signing & Capabilities`

3. Confirm:

   - Team: `BRENDAN SHANE LAVERTY`
   - Bundle Identifier: `com.bslaverty.wellwerksapp`
   - Automatically manage signing: checked

4. At the top device selector, choose:

   `Any iOS Device (arm64)`

5. Archive:

   `Product` → `Archive`

6. When Organizer opens:

   `Distribute App` → `App Store Connect` → `Upload`

## If signing still complains

In Apple Developer, make sure this exists:

- Identifier/App ID: `com.bslaverty.wellwerksapp`
- Certificate: `Apple Distribution`
- Profile type for TestFlight/App Store: `App Store Connect`

The Xcode project has been patched so Release/Profile builds use `Apple Distribution`.
