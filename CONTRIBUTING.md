# Contributing

This is a personal project I built as a birthday gift, shared as a template so other people can
make one too. That shapes what's useful here:

**Welcome:** bug fixes, build/setup fixes, documentation corrections, accessibility improvements,
and anything that makes the fork-and-customize path easier.

**Probably not:** new features that add complexity, or turning this into a general-purpose party
platform. It's deliberately a small app.

If you're unsure, open an issue before writing code.

## Setup

See [Getting Started](README.md#getting-started). The one thing that trips everyone up: you need
**your own** Firebase project and your own `GoogleService-Info.plist`. Mine is not in the repo and
never will be.

Requirements:

* Xcode 26 or newer (the deployment target is iOS 26.0)
* Your own Firebase project with Firestore and Storage enabled

## Before you open a PR

* `xcodebuild -project BirthdayQuest/BirthdayQuest.xcodeproj -scheme BirthdayQuest \
   -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` succeeds
* `swiftlint` is clean (config is in `.swiftlint.yml`)
* UI changes include a screenshot or screen recording — this app is almost entirely UI, so
  describing a visual change in prose isn't reviewable

## Things that must never be committed

* `GoogleService-Info.plist` (gitignored — use `GoogleService-Info.plist.example` as reference)
* `firebase-debug.log` or any `*.log` (they contain your Google account email)
* Real names, real photos, real audio, or real video of actual people
* Your `DEVELOPMENT_TEAM` or bundle identifier in `project.pbxproj` — set signing in Xcode's
  UI and leave the change out of your commit
* AI attribution trailers (`Co-Authored-By: Claude`, `Generated with ...`)

## Commit style

Imperative mood, one logical change per commit. Explain *why* in the body when it isn't obvious.
