# CLAUDE.md

## What this is
Byde is a macOS menu bar app (Swift package, SwiftUI) that nudges you to meditate once a day, inside a window you choose.

SPEC.md is the source of truth for behaviour. Read it before changing anything, and update it in the same commit as any behaviour change.

## Before starting
Run `git pull --rebase` first. The README is sometimes edited on GitHub.

## Build and test
- Release build (makes `Byde.app` in the project folder, ad-hoc signed): `./build.sh`. Add `run` to open it afterwards: `./build.sh run`.
- Debug build, which includes the Debug menu: `swift build`, then `.build/debug/Byde`.
- Self-test (schedule and log checks, then exits): `.build/debug/Byde --selftest`, or `.build/release/Byde --selftest` after `./build.sh`. It prints "selftest ok" and "log selftest ok". The flag ships in Release builds.

## Rules
- No third-party dependencies or packages.
- The only network use is the website page and icon fetch (see `Link.swift`). Add no other network calls.
- Debug-only code stays inside `#if DEBUG`.
- Never commit `dist/`, DMGs, `.app` bundles or log files. `.gitignore` already covers them.
- UI copy is neutral and brief: no streaks, guilt, celebration screens or milestone messages.
- Use American English in UI copy. Use British English in README.md and SPEC.md.
- Stop and ask before deleting any file. Deleting code inside a file is fine.
- Keep changes to what was asked. Report anything you interpreted rather than followed literally.

## Releasing
Follow the "Releasing a new version" checklist in SPEC.md.
- Never rebuild a DMG after its SHA-256 is in the cask. A rebuild changes the hash.
- In `../homebrew-tap/Casks/byde.rb`, update `version` and `sha256`. Run `brew style` and `brew audit --cask --online` on it before pushing.
- Create the GitHub Release only after the release commit is pushed, so the tag points at it.
