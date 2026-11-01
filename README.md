# Minical

A minimal calendar that lives in the macOS menu bar.

- Today's date in the menu bar, drawn as a template glyph that adapts to light, dark and tinted menu bars
- Month, week and day views; spring-animated paging by month, week or day (chevrons, trackpad swipe, scroll wheel, keyboard)
- Week view: a week strip over the selected day's hourly timeline
- Day view: what's next in large type, and the whole day from midnight to midnight as one glowing strip with a now marker; point at an event to light it up, click it for its details, above the hourly timeline
- The panel resizes with a smooth animation to fit each view; double-click a time to add an event
- Real calendar data through EventKit: colored event dots, holiday highlighting, and an agenda for the selected day
- Click an event to open it in Calendar; add events inline with `+` (⌘N)
- Options in the `⋯` menu: show/hide events, per-calendar filtering, week start day, launch at login
- Themes after AbleNotch's: System, Black, Faded Glass, Dusk Glass, Liquid Glass (real Liquid Glass on macOS 26) and Pane with eight colours and an adjustable strength, chosen with live previews from Appearance… in the ⋯ menu, along with the highlight colour
- English (Korean translations in progress, kept in `Localization/ko-pending.json`)

## Build

Requires Xcode 16+ (built with Xcode 27) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
xcodebuild -project Minical.xcodeproj -scheme Minical -configuration Release -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Release/Minical.app
```

## Release

`scripts/release.sh [version]` builds a universal (Apple silicon and Intel) app signed with a Developer ID, has Apple notarize it, staples the ticket and packages it as `dist/Minical-<version>.dmg`, ready to hand out outside the App Store. (Minical uses private macOS APIs to keep the panel still across Space switches and to tune its glass, so it can't go through App Store review.)

It needs, once:

1. A **Developer ID Application** certificate in the login keychain (Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application, signed in with the team's account).
2. Notary credentials, with an [app-specific password](https://account.apple.com) for that Apple ID:
   ```sh
   xcrun notarytool store-credentials minical-notary --apple-id <apple id> --team-id <team id> --password <app-specific password>
   ```

`SIGN_IDENTITY=- scripts/release.sh` signs ad hoc and skips notarization, to try the packaging alone.

Regenerate the app icon with `swift scripts/make-icon.swift Minical/Resources/Assets.xcassets/AppIcon.appiconset`.

## Keyboard

| Key | Action |
| --- | --- |
| ← → ↑ ↓ | Move the selected day |
| ⌘← / ⌘→, Page Up / Page Down | Previous / next month, week or day |
| ⌘1 / ⌘2 / ⌘3 (or D / W / M) | Day / week / month view |
| T | Jump to today |
| ⌘N | New event (Return saves, Esc cancels) |
| Return | Open Calendar |
| ⌘Q | Quit |

Debug builds accept `--open` to show the panel at launch, `--preview-window` to show the popover content in a regular window, `--sample-data` to fill it with in-memory events, `--compose` to open the event composer, `--mode week|day|month` to pick the view, `--detail` to open the first event's details in day view, `--theme <name>` to preview a theme without saving it, `--appearance` to open the Appearance sheet, and `--slow-motion [factor]` to play the panel's fade in and out that many times slower (ten by default).
