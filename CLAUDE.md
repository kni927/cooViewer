# CLAUDE.md

## Project Overview
cooViewer — A simple comic viewer for macOS (Objective-C / Cocoa)

## Tech Stack
- Language: Objective-C
- Framework: Cocoa (AppKit)
- Build: Xcode / xcodebuild
- Submodules: XADMaster (archive extraction), UniversalDetector (character encoding detection)

## Setup
```bash
git clone --recursive https://github.com/<yourname>/cooViewer.git
cd cooViewer
xcodebuild -configuration Deployment
open build/Deployment/cooViewer.app
```

## Build Commands
```bash
xcodebuild -configuration Deployment   # release build
xcodebuild -configuration Debug        # debug build
```
Note: No automated tests. Verify behavior manually.

## Key Files
- Controller.m / Controller.h       — Main controller (page control, UI)
- Controller_input.m                — Keyboard and mouse input handling
- CustomImageView.m / .h            — Image display view
- AccessoryView.m / .h              — Page bar (bottom HUD)
- COImageLoader.m / .h              — Image and archive loading

## Coding Rules
- Objective-C (be careful with MRC/ARC mixing; MRC is the baseline)
- When changing IBOutlet / IBAction, also update the Interface Builder file (.xib)
- When adding NSUserDefaults keys, register default values inside awakeFromNib
- Add localized strings to Localizable.strings in both Resources/en.lproj and Resources/ja.lproj
- Images/icons live in Assets.xcassets (load with [NSImage imageNamed:]); other bundle resources (xibs, strings, document icons, etc.) live in Resources/

## Do Not Modify
- XADMaster/, UniversalDetector/ — Submodules. Do not edit directly.
- MainMenu~.nib — Legacy nib. Leave it alone.

## Commit Rules
- Prefix: feat: / fix: / refactor: / docs:
- One commit per feature recommended

## Development Log
See `docs/dev-log.md` for a full history of changes made to this fork,
including implementation details, bug fixes, architecture notes, and release workflow.
