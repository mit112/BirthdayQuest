# Privacy Manifest (PrivacyInfo.xcprivacy) — Notes

**Date:** 2026-08-25  **Branch:** feat/privacy-manifest (NOT merged — see "Human step" below)

Adds `BirthdayQuest/BirthdayQuest/PrivacyInfo.xcprivacy`, the App Store privacy manifest (absent before).

## Content decisions (what I could determine factually vs. what needs sign-off)
FACTUAL (from the code):
- `NSPrivacyTracking = false`, `NSPrivacyTrackingDomains = []` — the app links only Firebase
  Auth/Firestore/Storage/Core; no analytics, ads, ATT, or tracking SDK (verified by grep). Firebase
  SDKs ship their OWN manifests, so this app manifest covers only the app's own usage.
- `NSPrivacyAccessedAPITypes`: one entry, `NSPrivacyAccessedAPICategoryFileTimestamp`, reasons
  `C617.1` + `3B52.1`. The app calls `FileManager.attributesOfItem(atPath:)` at 3 sites (media size
  checks) — that API is in Apple's file-timestamp required-reason category regardless of which
  attribute you read. `C617.1` covers the app-container temp/copy files; `3B52.1` covers
  user-picker-selected files. No UserDefaults / systemUptime / disk-space required-reason APIs are
  used by the app itself.

REVIEW REQUIRED before App Store submission (compliance declaration, not a pure code fact):
- `NSPrivacyCollectedDataTypes` declares Photos/Videos, Audio, Other User Content, Name, and User ID,
  all as **App Functionality**, **linked to identity**, **not used for tracking**. This is derived
  from what the code demonstrably transmits to Firebase (gift media/text, participant names, the
  anonymous uid). The developer MUST confirm it matches their actual data practices and the App Store
  Connect privacy "nutrition label" before submitting.

## Human step to finish wiring (one click — deliberately NOT hand-edited into pbxproj)
The project uses Xcode-16 file-system-synchronized folders with an ALL-EMPTY Resources build phase
(no explicit resource entries — `Assets.xcassets` is auto-bundled by the sync). Empirically the sync
auto-adds `.xcassets` but does NOT auto-add `.xcprivacy` to Copy Bundle Resources: a clean
`xcodebuild` leaves the app's manifest out of `BirthdayQuest.app/` (only the Firebase sub-bundles'
own manifests appear). The manifest file is valid (`plutil -lint` OK) and the app still builds green
with it present.

To bundle it: open the project in Xcode, select `PrivacyInfo.xcprivacy`, and check the **BirthdayQuest**
target under Target Membership (File Inspector). Xcode writes a `PBXFileSystemSynchronizedBuildFileExceptionSet`
correctly. Confirm afterward that `BirthdayQuest.app/PrivacyInfo.xcprivacy` exists at the bundle root.
This was left as a human/Xcode-UI action on purpose — hand-editing the pbxproj is the exact thing this
project's folder-sync setup avoids, and a wrong UUID edit would break the whole build.
