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

## Bundle wiring — NO human step needed (corrected 2026-08-28)

**The original claim in this file was wrong, and it is left quoted below because it was believed
for three days and is exactly the kind of thing that gets re-asserted from memory.** It said the
Xcode-16 file-system-synchronized folder auto-adds `.xcassets` but *not* `.xcprivacy`, so the app's
manifest would be missing from `BirthdayQuest.app/` until someone opened Xcode and ticked Target
Membership.

Measured on 2026-08-28 against `main` with the manifest merged, it bundles on its own, in **both**
configurations, with no pbxproj entry and no target-membership tick:

```
$ xcodebuild -scheme BirthdayQuest -destination '…iPhone 17 Pro Max' build      # Release
$ ls "$APP/PrivacyInfo.xcprivacy"                                               # present
$ plutil -convert xml1 -o - "$APP/PrivacyInfo.xcprivacy" | md5 -q               # 78a0c592…
$ plutil -convert xml1 -o - BirthdayQuest/BirthdayQuest/PrivacyInfo.xcprivacy | md5 -q
                                                                                # 78a0c592… (identical)
$ xcodebuild … -configuration Debug build && ls "$DEBUG_APP/PrivacyInfo.xcprivacy"  # also present
```

Byte-identical to the source file, at the bundle root, in Debug and Release. So the manifest is
already shipping and there is nothing left to click. The `grep` for `xcprivacy` in `project.pbxproj`
still returns nothing — that is expected and is the point of the synced folder, not evidence it is
unbundled.

Why the original measurement disagreed is not established. The likeliest explanation is that it was
taken while the manifest existed only on the unmerged `feat/privacy-manifest` branch and the build
under inspection was made from a tree that did not contain the file at all — which would produce
exactly the reported symptom (only the Firebase sub-bundles' own manifests present). Do not re-add
the manual step on the strength of the old note; re-run the two commands above instead.
