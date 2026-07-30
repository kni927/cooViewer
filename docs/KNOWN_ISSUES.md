# cooViewer — Known Issues / Things to Be Careful About

This document collects fragile areas, gotchas, and "do not touch lightly" spots
in the codebase. Read this before making non-trivial changes.

---

## 1. MRC (Manual Reference Counting) Project — Watch Out for ARC Mixing

cooViewer's own code is built with **MRC** (Manual Reference Counting) as the
baseline, while the submodules (XADMaster, UniversalDetector) may be built
with ARC (or a mix, depending on the file).

- Do **not** assume ARC semantics (no automatic `retain`/`release`/`autorelease`,
  no implicit `__strong`/`__weak`) when editing `.m` files in the main project.
- When passing objects across the MRC/ARC boundary (e.g. calling into
  XADMaster), be careful about ownership — bridging mistakes here cause subtle
  leaks or over-releases that are hard to reproduce.
- New files added to the project should match the memory-management model of
  the surrounding code unless there's a strong reason to change it (and if you
  do change it, set the `-fobjc-arc` / `-fno-objc-arc` compiler flag explicitly
  for that file in the Xcode build phase).

---

## 2. Nib Dependency — Interface Builder Must Stay in Sync

Several controllers (`Controller`, `PreferenceController`, etc.) are wired up
through `Base.lproj/MainMenu.xib`.

- Any change to an `IBOutlet` or `IBAction` in the `.h`/`.m` files **must** be
  mirrored in the `.xib` (rename, retype, rewire, or remove the connection).
  Forgetting this causes a crash at launch (`NSUnknownKeyException`,
  "this class is not key value coding-compliant for ...") or silently broken
  UI (outlet is nil).
- Conversely, if you delete or rename a control in Interface Builder, check
  that no outlet/action in code still references the old name.
- `MainMenu~.nib` is a **legacy** nib kept for reference only — do not edit it,
  and do not confuse it with the active `MainMenu.xib`.
- Xcode's nib editor can silently leave stale connections behind; after editing
  the xib, build and actually launch the app to confirm there's no
  KVC-compliance crash on startup.

---

## 3. Two-Page Spread Left/Right Detection Is Complex

The logic that decides which physical side (left/right on screen) corresponds
to which logical image (`firstImage`/`secondImage`) depends on **both**:

- the current `readMode` (RTL vs LTR — values `0,2` vs `1,3`), and
- the geometric composition produced by `returnComposeImage:secondImage and:firstImage`.

Mapping (from `composeImage`):
```
RTL (readMode 0,2): LEFT = secondImage, RIGHT = firstImage
LTR (readMode 1,3): LEFT = firstImage,  RIGHT = secondImage
```

This mapping is easy to get backwards, and a mistake won't crash — it will
just silently save/report/act on the *wrong page* of a spread. Any change that
touches page ordering, composition, or click-to-page mapping should be
re-tested in **all four** `readMode` values, with both single pages and
two-page spreads.

---

## 4. `imageInfoForClickPoint:` Is Fragile — Touch Carefully

`Controller.m`'s `imageInfoForClickPoint:(NSPoint)windowPoint` determines which
page of a spread was clicked by comparing the click X position against the
center X of `[[window contentView] frame]`, then re-mapping geometric
left/right to `firstImage`/`secondImage` using the `readMode` rules above.

- It returns an `NSDictionary` with `@"path"` (used for the filename and direct
  file copy) and `@"image"` (an `NSImage`, used as a re-encode fallback).
- There is a known-fixed edge case where the `iS < 0` guard previously returned
  the wrong image for the `@"image"` key (`firstImage` instead of
  `secondImage`) — a reminder that the guard branches here are easy to get
  wrong because they're only reachable in specific spread/index combinations
  that are rarely exercised manually.
- When modifying this method, manually test: single-page mode, two-page spread
  in both reading directions, and clicks very close to the page boundary
  (the geometric center line).

---

## 5. `mouseAction:` Case 59 — Special-Cased, Reason Unclear, Do Not Refactor Blindly

In `Controller_input.m`, the mouse action dispatcher's **case 59**
("Contextual Menu") is handled specially: it calls `[imageView menu]` (the
standard `NSView -menu` property) rather than going through the generic
mouse-action machinery used by other cases.

- The exact historical reason for this special case is **not documented** and
  not obvious from the surrounding code.
- `CustomImageView` overrides `-menu` (not `menuForEvent:`) specifically so
  that this path returns the Save Image... context menu — see Feature #2 in
  `docs/DEV_LOG.md`.
- **Do not** override `menuForEvent:`, change `rightMouseDown:` to call
  `super`, or "simplify" the case 59 branch to match the other cases without
  thorough manual testing — earlier attempts in this vein broke the existing
  mouse-action configuration (right-click stopped routing through
  `mouseAction:` at all).
- The flow to keep in mind:
  ```
  rightMouseDown: → mouseDown: → (on mouseUp:) mouseAction: → case 59 → [imageView menu]
  ```

---

## 5b. Parent-Folder Access Must Stay Lazy (Don't Reintroduce Eager Scans)

`setSameFolderMenu:` (builds the **Open from same folder** submenu) and
`checkCurrentFolderUpdated` (detects whether the current book's folder moved)
both call `NSFileManager` APIs (`contentsOfDirectoryAtPath:`,
`attributesOfItemAtPath:`, `fileExistsAtPath:`) on the **parent directory**
of the currently open book — a location the user did not explicitly pick via
`NSOpenPanel`.

- These are now triggered **only** from `menuNeedsUpdate:` (an
  `NSMenuDelegate` method), i.e. right before the "Open from same folder"
  submenu is actually displayed — see the `docs/DEV_LOG.md` entry "Repeated macOS
  Folder-Access Permission Prompts on `File > Open...`".
- **Do not** call `setSameFolderMenu:` / `checkCurrentFolderUpdated` eagerly
  again from `openPage:last:` or `applicationDidBecomeActive:` (or any other
  frequently-firing path) — doing so reintroduces a macOS folder-access
  permission dialog on every book open / app activation, regardless of
  whether the user ever uses the "same folder" feature.
- The submenu for `openSameFolderMenuItem` is created **once** in
  `awakeFromNib` and reused for the app's lifetime (`removeAllItems` +
  rebuild in place) specifically so its `NSMenuDelegate` stays attached.
  **Do not** go back to allocating a fresh `NSMenu` and swapping it in via
  `setSubmenu:` on every refresh — that drops the delegate and breaks the
  lazy-loading mechanism silently (no crash, the menu just never repopulates
  via `menuNeedsUpdate:` again).

---

## 6. NSImage Size vs. Pixel Dimensions

`NSImage.size` returns **point** dimensions, which can be affected by DPI
metadata embedded in the image file (e.g. a 300 DPI scan reports a smaller
"size" than its pixel dimensions). For anything that needs the actual pixel
resolution (HUD display, save/export, etc.), read
`NSImageRep.pixelsWide` / `pixelsHigh` instead — see `pixelSizeStringForImage:`
in `Controller.m`.

---

## 7. Scroll Wheel Handling — Precision Devices Need Accumulation

`wheelAction:` in `Controller_input.m` accumulates `deltaY` across events
(`wheelDeltaAccum` in `Controller.h`) rather than acting on a single event's
delta, because precision scroll devices (trackpads, MX-style precision mice)
emit many small fractional deltas per physical notch.

- The accumulator must be reset both when the threshold fires **and** when a
  momentum-phase (inertia) event arrives, and also when `wheelSensitivity == 0`
  (otherwise re-enabling sensitivity later can fire a spurious page turn).
- If you touch this code, test with both a traditional notched mouse wheel and
  a precision/trackpad-style device — behavior that looks correct on one can
  be broken on the other.

---

## 8. NSUserDefaults Keys Must Be Registered in `awakeFromNib`

New preference keys (e.g. `ShowResolution`) must have a default value
registered inside `Controller`'s `awakeFromNib`. Skipping this means the first
launch after an update reads `nil`/`0`/`NO` for the new key until the user
opens Preferences and the value happens to get written — leading to
inconsistent first-run behavior that's hard to reproduce once you've run the
app once locally.

---

## 9. Localized Strings

Any new user-facing string must be added to `Localizable.strings` in **both**
`en.lproj` and `ja.lproj`. Missing an entry doesn't crash — it just falls back
to the raw key string (or the other language's string, depending on lookup
order), which is easy to miss during a quick manual test in your own locale.

---

## 10. No Automated Tests — Manual Verification Required

There is no test suite. Every change — especially to the areas above — needs
to be verified by actually building (`xcodebuild -configuration Deployment`)
and running the app (`open build/Deployment/cooViewer.app`) against real
comic archives, in multiple `readMode` / preference combinations where
relevant.

---

## 11. Submodules Are Off-Limits

`XADMaster/` and `UniversalDetector/` are git submodules vendored for archive
extraction and encoding detection. Do not edit them directly in this repo —
any fix belongs upstream. If submodules appear empty after cloning, run:
```bash
git submodule update --init --recursive
```

---

## 12. Unsigned Build → Repeated Folder-Access Prompts / Gatekeeper Translocation

The project builds with `CODE_SIGN_IDENTITY = ""` (no Developer ID — at most
an implicit ad-hoc signature on Apple Silicon). This is **not** an App Sandbox
issue (the app isn't sandboxed at all — no `.entitlements`, no
`com.apple.security.*` keys), but it does interact badly with two separate
macOS subsystems:

**a) TCC folder-access permissions don't persist across rebuilds**
TCC ties "allow this app to access folder X" grants to the app's code
signature/identity. An ad-hoc signature is derived from the binary's content
hash, so it changes on every rebuild — macOS then treats each new build as a
"different app" and re-prompts for folders it already granted access to
before. (See the `docs/DEV_LOG.md` entry on lazy parent-folder access — that fix
reduces *how often* the app touches folders it wasn't explicitly granted, but
can't fix this identity-churn problem.)

**b) App Translocation for binaries downloaded via GitHub Releases**
A `.app` downloaded through a browser gets a `com.apple.quarantine` extended
attribute. If launched from a quarantined location without first being moved
(e.g. straight from `~/Downloads`), macOS runs it from a **randomized
read-only path** (`/private/var/folders/.../AppTranslocation/<uuid>/d/...`)
that changes on every launch — so, again, folder-access grants can't persist,
and the app may also misbehave if it ever assumes a stable bundle path.

**Workarounds (user-side, not a code fix):**
```bash
xattr -cr /Applications/cooViewer.app   # remove quarantine attribute
```
or simply move the `.app` fully into `/Applications` before first launch.

**Real fix (requires paid Apple Developer Program membership):** sign with a
Developer ID Application certificate (`DEVELOPMENT_TEAM` + proper
`CODE_SIGN_IDENTITY`) and notarize via `notarytool`. Switching to plain
ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`) does **not** meaningfully help —
the CDHash still changes every build and Translocation still applies to
quarantined ad-hoc-signed apps.

---

## 13. QuickLook Extensions — Debugging Notes (Signing, UTIs, Tooling)

The `cooViewerPreview`/`cooViewerThumbnail` App Extension targets
(phase 7, `docs/tasks/2026-07-14-05-quicklook-extension.md`) have a few
non-obvious gotchas specific to this project's build setup:

- **`CODE_SIGN_IDENTITY = ""` silently drops entitlements.** Unlike the
  main app (which has no entitlements to begin with), an extension
  target with a `.entitlements` file but an empty
  `CODE_SIGN_IDENTITY` builds "successfully" with only a warning
  ("isn't code signed but requires entitlements") and the sandbox
  entitlements are never actually applied. Both extension targets use
  `CODE_SIGN_IDENTITY = "-"` (ad-hoc) specifically so entitlements get
  embedded — verify with `codesign -d --entitlements -
  path/to/X.appex` after any build-settings change, don't assume the
  absence of a build error means entitlements applied.
- **A file's resolved UTI can silently differ from what cooViewer
  declares.** `.cbz`/`.cbr` are not guaranteed to resolve to
  cooViewer's own `jp.coo.cooViewer.cbz-archive`/`cbr-archive` UTIs —
  another installed app can already export a same-named public UTI
  (e.g. `public.cbz-archive`) that wins the LaunchServices resolution.
  Always check with `mdls -name kMDItemContentType <file>` (not just
  reading the Info.plist declarations) before assuming
  `QLSupportedContentTypes` will actually match. See the DECISIONS.md
  entry "QuickLook: two separate extension targets, and support both
  custom and pre-existing public UTIs" for the fix applied here.
- **`mdls -name kMDItemVersion` / Spotlight metadata is unreliable for
  freshly-built products in a dev/CI-like environment** — even after
  `mdimport -f` and `lsregister -f`, Spotlight may not index a
  just-built `.app`'s version metadata (verified against
  known-working pre-installed apps like Calculator/Xcode, which do
  resolve correctly, ruling out a general Spotlight outage). Don't
  rely on `mdls` alone to confirm a version-string fix — cross-check
  via `defaults read Contents/Info.plist CFBundleShortVersionString`
  and/or the real Finder Get Info panel.
- **`qlmanage -t`/`qlmanage -p` are not reliable for testing modern
  App Extension-based (`QLPreviewProvider`/`QLThumbnailProvider`)
  providers** — `-t` (thumbnail-to-file) was observed to hang
  indefinitely against these extensions, and `-p` opens an interactive
  preview window rather than returning. Prefer driving real Finder
  (select the file, press Space; check icon view for thumbnails) for
  verification, and `pluginkit -m -v | grep <bundle-id-prefix>` to
  confirm the extensions are actually registered.

---

## 14. Double-Click-Doesn't-Switch-Document Report (Phase 9) — Not Reproduced

A report that double-clicking a second `.cbz`/`.cbr` in Finder while
cooViewer already has a different file open brings the app to the
foreground but doesn't load the new file (`docs/tasks/2026-07-15-02-doubleclick-open-investigation.md`)
could **not** be reproduced despite testing same-format switching,
cross-format switching, duplicate LaunchServices registrations (two
installed copies sharing the same bundle ID), and simultaneous
multi-file opens — all via real Finder interaction with temporary
diagnostic logging in place. `application:openFile:`
(`Sources/Controller.m:645`) and the internal load path it shares with
`File > Open` worked correctly every time tested.

- If this recurs, check first for **duplicate installed copies**
  (`mdfind "kMDItemCFBundleIdentifier == 'jp.coo.cooViewer'"` or
  `lsregister -dump | grep -A3 "bundle:.*cooViewer"`) — repeated local
  dev-build installs across different paths (`~/Applications`,
  `/Applications`, etc.) leave stale LaunchServices claim entries that
  can be genuinely confusing to debug against, even though a live test
  with two such copies still routed correctly in this investigation.
- One independent, unrelated bug WAS found and fixed in the same pass:
  `application:openFile:` always returned `NO` even on success
  (violates the documented `NSApplicationDelegate` contract) — fixed
  to return `YES`. No causal link to the reported symptom was
  established.
- `openPage:last:`'s silent-revert-on-load-failure branch
  (`Controller.m:754`) has no user-facing error message — a load
  failure for any reason not exercised in this investigation would
  look, from the user's perspective, identical to "nothing happened,"
  matching the reported symptom. Worth surfacing an error here if the
  report recurs and a failing file/location can be identified.
- **Phase 10 follow-up:** chat investigation pinpointed
  `com.apple.quarantine` as the differentiator between failing and
  working files. Still could not reproduce: tested the exact same
  file with its quarantine attribute intentionally left in place, a
  pre-phase-7 build via `git worktree`, freshly-applied quarantine
  attributes (new UUID, never opened) on both small and 1.4 GB files,
  and the real Developer-ID-signed/notarized `/Applications` release
  build — six variations total, all switched documents correctly. See
  `docs/tasks/2026-07-15-03-quarantine-doubleclick-investigation.md`.
  If this recurs, get a live, step-by-step narrated repro (exact file,
  exact click sequence, any dialogs seen) rather than reasoning from a
  chat description after the fact — this investigation had no actual
  failure to observe or log.

---

## 15. Finder経由での2つ目のファイルオープンが効かない・QuickLookサムネイルが
    更新されない(原因はmacOS側のデーモン状態、再起動で解消・解決済み)

**症状**:
- cooViewerが既に起動している状態で、Finderから別のアーカイブファイルを
  ダブルクリックしても、フォーカスは移るが表示中のドキュメントが切り替わらない。
  File > Openコマンドおよびcold launch(未起動状態からのダブルクリック)は
  問題なく動作していた。
- 同時期に、QuickLookのサムネイル/プレビューが更新されず汎用アイコンのまま
  になる症状も発生。

**調査の経緯**:
- 当初、開いているファイルがsolid RAR / 大容量であることと相関があるように
  見えたが、後の検証でこれは誤りと判明。
- 次に特定ファイル(1.cbz, 1.cbr)固有の問題に見えたが、リネーム・コピーしても
  症状が追従したため、ファイル自体の識別子(inode等)由来でもないと判明。
- com.apple.quarantine属性の有無が一時的に再現性のある差分として特定され、
  quarantine属性を持つファイルへの切り替えが失敗する現象を確認したが、
  後の再検証(TASK.mdに基づく計6パターンの比較テスト)では再現しなくなった。
- 並行して、`build/Deployment/`配下や~/Downloads、~/Dropbox配下に複数の
  cooViewer.appが存在し、QuickLook拡張がそのうち`/Applications`以外の
  ビルドから登録されていたことが判明(pluginkit -m で確認)。整理・
  pluginkit -e ignore/useでの操作、killall Finder / killall Dockを
  行ったが、症状は完全には解消しなかった。
- **最終的に、Mac自体を再起動したところ、ダブルクリックでの切り替え・
  QuickLookサムネイルの両方が正常化した。**

**結論**: 原因はcooViewer側のコードではなく、開発中に短時間で繰り返した
ビルド・複数インストール・pluginkit操作によって、LaunchServices関連の
システムデーモン(lsdなど)やQuickLookのジェネレータキャッシュが不整合な
状態に陥っていたためと推測される(未検証の推測)。killall Finder /
killall Dockでは解消せず、OS再起動でのみ解消した。

**再発時の対処法**:
1. `pluginkit -m -v -p com.apple.quicklook.preview` /
   `com.apple.quicklook.thumbnail` で、`/Applications/cooViewer.app`
   以外の場所からQuickLook拡張が登録されていないか確認する。
2. 余分なcooViewer.appのインストール(特に`build/Deployment/`配下の
   ビルド成果物)を削除する。
3. `killall Finder && killall Dock`を試す。
4. それでも解消しない場合、Mac自体の再起動を試す(これまでの再現例では
   再起動が最も確実だった)。

## 16. Static Analyzer Findings (Survey) — Dead Stores, Potential Leaks, Uninitialized Values (Do Not Fix Blindly)

Recorded from an `xcodebuild analyze` survey (scheme `cooViewer`,
Deployment) on 2026-07-24. These are **not fixed**; this is a tracking
list. This is an MRC project (see #1), so "potential leak" findings must be
reviewed against manual retain/release rules before changing anything.

**Dead stores — `Value stored to ... is never read` (22 at survey time;
now 15).** Seven were incidentally removed with their unused variables in
task `docs/tasks/2026-07-25-03-remove-unused-vars-relocate-decl.md`
(`items`, `fullscreenRect`, `docBounds`, `sx`×2, `manager`×2); the list
below is the original survey and not re-verified line-by-line.

- `Sources/AccessorySettingView.m`: 315 (`oldRect`), 346 (`newRect`),
  357 (`oldRect`), 374 (`newRect`), 397 (`oldRect`), 428 (`newRect`)
- `Sources/COImageLoader.m`: 500 (`items`)
- `Sources/COPopUpTextField.m`: 29 (`tempRect`)
- `Sources/Controller.m`: 197 (`viewBackGround`), 553 (`enu`), 914
  (`lastPages`), 916 (`lastPages`), 2017 (`enu`)
- `Sources/Controller_input.m`: 3108 (`desc`), 3113 (`desc`)
- `Sources/CustomImageView.m`: 1347 (`fullscreenRect`)
- `Sources/FilterPanelController.m`: 85 (`docBounds`)
- `Sources/LoupeView.m`: 177 (`sx`), 213 (`sx`)
- `Sources/NSString_Compare.m`: 47 (`manager`), 60 (`manager`)
- `Sources/PreferenceController.m`: 948 (`bufferingMode`)

**Potential leaks — all 7 RESOLVED** (2026-07-25, task
`docs/tasks/2026-07-25-06-fix-potential-leaks.md`). All were genuine,
reachable MRC leaks; each fixed with the minimal correct
`release`/ownership change. (Line numbers below are the original survey's;
Controller.m shifted −1 after 2026-07-25-03.)

- `Sources/AccessoryView.m`: 691 (`infoString`), 775 (`pageString`) — the
  `else` branch called `-initWithString:` on an already-initialized
  immutable `NSAttributedString` and discarded the `+1` result. Replaced
  with `release` of the old value + `alloc`/`init` of a new one (matching
  the `if` branch).
- `Sources/Controller.m`: 474 (`multiTouchMouseArray`) — `alloc`ed array
  whose contents were copied into `mouseArray` but the array object itself
  was never released; added `release` after the copy (version-migration
  code, runs only on upgrade).
- `Sources/Controller.m`: 2699, 2735, 2771 (`scroll`, now 2698/2734/2770) —
  `[[NSScrollView alloc] init]` added to the view hierarchy (which retains
  it) but the local `+1` was never released; added `[scroll release]` after
  `setDocumentView:` in `fitToScreenWidth:`, `fitToScreenWidthDivide:`,
  `noScale:`.
- `Sources/ThumbnailController.m`: 258 (`image2`) — in `loadMangaImage:back:`
  the `back` branch's `else` returned without releasing the retained
  `image2`; added `[image2 release]`, matching the already-correct `!back`
  branch.

**Uninitialized value — `Receiver in message expression is an
uninitialized value`:**

- `Sources/ThumbnailController.m`: 1015, 1025, 1039, 1047, 1071 —
  **RESOLVED** (2026-07-25, task
  `docs/tasks/2026-07-25-05-fix-uninitialized-lastcell.md`).
  `contextAction:` used an uninitialized `id lastCell` when
  `-getRow:column:forPoint:` failed at menu-action time; it now returns
  early on a lookup miss (invalid clicks are ignored). This was the only
  reachable crash (G1).
- `Sources/COColorPopUpButton.m`: 169 (`fillColor`) — **analyzer false
  positive (G3), do not re-investigate.** The menu titles are a fixed,
  closed set added in the same `awakeFromNib`; every title assigns
  `fillColor` (`Other…` returns early, `Clear` is handled separately), so
  the "no branch assigned it" path is unreachable.
- `Sources/CustomImageView.m`: 988 and 1397 (`transform`) — **analyzer
  false positive (G2), do not re-investigate.** `rotateMode` starts at 0 and
  is only changed by `rotateLeft`/`rotateRight`, which strictly wrap it to
  `[0,3]`; cases 1/2/3 assign `transform` and the `if (rotateMode!=0)` guard
  skips 0, so the switch-`default` (unassigned) path is unreachable. (Was
  line 1398 in the original survey; shifted to 1397 by the 2026-07-25-03
  cleanup.)

**Null pointer dereference:**

- `Sources/COImageLoader.m`: 82 (`contentPathArray` via `self`) —
  **analyzer false positive (G4), do not re-investigate.** Reached only if
  `self = [super init]` returns nil, which `NSObject -init` does not do in
  practice. The post-init `if ([self itemCount]==0)` block sits outside the
  `if (self)` guard (a structural smell), but the path is infeasible.
  **Not a tidy-up candidate:** this note supersedes the earlier "optional
  tidy-up" framing — leave the code as it is.

### RemoteControlWrapper: keep, despite one unused class (2026-07-25)

Recorded here so it is not re-investigated as dead code:

- `GlobalKeyboardDevice` is **unused** — never instantiated anywhere in the
  project (only its own files reference it). Its `hotKeyEventHandler` is
  wired to Carbon *inside* the class, so the function is not removable in
  isolation; the class as a whole is simply never constructed.
- `AppleRemote` from the same library **is live and user-visible**:
  `Controller.m` creates it (`[[AppleRemote alloc] initWithDelegate:self]`)
  and its buttons are exposed in Preferences ▸ Input as assignable keys
  ("AppleRemote Volume up/down", "AppleRemote Menu", "AppleRemote Play",
  …), which users can bind to actions.
- **Decision: removing the RemoteControlWrapper library as a whole is
  declined**, on settings-compatibility grounds — the AppleRemote key
  entries are persisted in user settings, so dropping the library would
  invalidate existing key bindings. Deleting only `GlobalKeyboardDevice`
  from a vendored third-party library is likewise not worth the divergence
  from upstream.

Note: the analyzer also reports 23 "User-facing text should use localized
string macro" hits (localizability, see #9) and 148
`-Wdeprecated-declarations` compiler warnings; those are out of scope here.

## 17. `.cvbdl` Exclusion from `COImageLoader.archiveTypes` Is Intentional — Do Not Remove

- `Sources/COImageLoader.m:37-46` (`+archiveTypes`) explicitly excludes
  `cvbdl` from the extensions treated as archives. This is deliberate, not
  dead code or an oversight — do not remove it as part of a cleanup.
- `.cvbdl` bundles are `LSTypeIsPackage` folders, not real archive files.
  `COArchive` falls back to `archive_read_open_filename` (libarchive) for
  any extension it doesn't specifically dispatch to `COZipArchive`/
  `CORarArchive`, and libarchive cannot open a directory as an archive
  stream. Removing the exclusion would make `.cvbdl` fail to open
  entirely, regressing currently-working behaviour.
- `.cvbdl` is handled correctly today by `COImageLoader`'s generic
  directory-open fallback, which already provides the full documented
  feature set (bookmarks, last-page memory, read direction, and more).
  See `docs/tasks/2026-07-25-16-investigate-cvbdl-support-scope.md` for
  the full investigation this is based on, and
  `docs/DECISIONS.md`'s `.cvbdl` entries for the related product
  decisions (keep as-is in the main app; QuickLook/Thumbnail support
  added separately in v1.5.2 via a directory-listing path that also does
  not go through `COArchive`).

## 18. On-Device QuickLook/Thumbnail Verification: `/Applications` Always Wins LaunchServices Dedup

- On this development machine, `/Applications/cooViewer.app` (the
  Homebrew-managed install) is consistently the copy `pluginkit`/
  LaunchServices resolves for `jp.coo.cooViewer`'s QuickLook Preview and
  Thumbnail extension identifiers — even when a newer build at
  `~/Applications/cooViewer.app` is `lsregister -f`'d and `pluginkit -a`'d
  exactly per `CLAUDE.md`'s On-Device Verification Procedure.
- Version is not the tie-breaker: a freshly built copy reporting a higher
  `CFBundleShortVersionString` (1.5.1 vs. `/Applications`'s 1.5.0) was
  still passed over.
- This blocked on-device Finder/QuickLook verification of new extension
  binaries in both the v1.5.1
  (`docs/tasks/2026-07-25-14-verify-encrypted-zip-on-device.md`) and
  v1.5.2 (`docs/tasks/2026-07-25-17-implement-cvbdl-quicklook.md`)
  development cycles.
- **Standing constraint, not a one-off to fix.** Any future task that
  changes QuickLook/Thumbnail extension code should expect this and plan
  verification accordingly (e.g. logic-level checks against the real
  source, as done in both tasks above) rather than re-discovering it or
  re-attempting registration workarounds mid-task.
- The only workaround found so far: temporarily uninstall the Homebrew
  copy to test the actual signed release artifact immediately before a
  release, then restore Homebrew management via the tap update afterward.
  Not practical for routine development-cycle verification, since it
  requires an uninstall/reinstall around every extension-touching change.

## 19. `awakeFromNib` Writes Registered Defaults Back Into the Persistent Domain — Registered Defaults Are Effectively One-Shot

Backlog item. **Not part of the multi-window plan** — MW-2 removes the
`Fullscreen` key's own instance of this pattern as a side effect of
retiring the preference, and deliberately nothing else. Fixing the
pattern generally is a separate task.

**Partially addressed by MW-3 (2026-07-29).** The specific ordering hazard
in the third bullet below — `registerDefaults:` itself, plus the
KeyArray/MouseArray "set default if absent" calls, racing another nib
object's `awakeFromNib` — is now structurally impossible: that code moved
from `-[Controller awakeFromNib]` into `+[Controller initialize]`
(`Controller.m`), which is guaranteed to run before any nib object's
`awakeFromNib`. The write-back pattern itself (every other row in the table
below, and the general "registered defaults are one-shot" / "reset settings
doesn't reset" consequences) is **unchanged** — that generalized fix remains
its own separate, unscoped backlog task as described below.

`-[Controller awakeFromNib]` registers application defaults
(`Controller.m:63-90`) and then, for a number of keys, **reads the value
and immediately writes it back** into the persistent domain:

| Key | Read | Write-back |
|---|---|---|
| `Fullscreen` | `Controller.m:199` | `Controller.m:273` |
| `OpenLastFolder` | `Controller.m:284` | `Controller.m:285` |
| `ReadSubFolder` | `Controller.m:257` | `Controller.m:274` |
| `Interpolation` | `Controller.m:159` | `Controller.m:161` |
| `ImageCache` | `Controller.m:167` | `Controller.m:168` |

(`ScreenCache`, `ThumbnailCache`, `UseCALayer`, `BufferingMode`,
`ReadMode`, `RememberBookSettings`, `AlwaysRememberLastPage`,
`GoToLastPage`, `OpenLinkMode`, `ChangeCurrentFolder`, `IgnoreImageDpi`,
`SingleSetting`, `Thumbnail`, `LoupeSize`, `LoupeRate` and others follow
the same shape — the list above is the set named in the backlog request,
not the full extent.)

Consequences:

- **A registered default only ever applies on the very first launch.**
  After that a persistent value always exists, so changing a registered
  default in code has no effect on any existing installation.
- **"Reset settings" does not behave like a fresh install.** Removing a
  key causes the next launch to re-register *and re-persist* it, so the
  domain never returns to the clean state a new user gets.
- **It makes nib `awakeFromNib` ordering observable.** Any other nib
  object that reads one of these keys in its own `awakeFromNib` races
  the registration in `Controller.m:90`. `CustomWindow.m:12` does
  exactly this for `Fullscreen`; AppKit does not define the order. See
  `docs/tasks/2026-07-28-02-fullscreen-default-investigation.md`.

Removing a write-back is *usually* safe on its own — `boolForKey:` and
friends search the registration domain too, so a read still yields the
registered default once `registerDefaults:` has run. The catch is the
"once it has run" part: today the write-backs mask the ordering problem
above for every launch after the first, so removing them can expose it.
Any fix should therefore move `registerDefaults:` somewhere guaranteed to
precede all nib `awakeFromNib` calls (e.g. `+initialize` on the app
delegate, or `main.m` before `NSApplicationMain`) rather than just
deleting the write-backs.

Do not fix individual keys opportunistically while working on something
else. Treat it as one scoped task with its own verification, including a
clean-domain launch test.

---

## 20. Cannot Quit While Modal Sheets Are Displayed (Multi-Window Arc, Phase 9)

Three known cases where quit (Cmd+Q, application menu, or AppleEvent) is
blocked or deferred while a modal is active. These are **decided not to
fix** as of v1.6.0.

### Case 1: All Bookmark Browser (`runModalForWindow:`)

The All Bookmarks browser window opened via `File > All Bookmarks…` is
modal (`[NSApplication runModalForWindow:]`). Quit is blocked entirely
while the window is open.

**Workaround:** Close the All Bookmarks window (close button or `Esc`) before
quitting.

### Case 2: Nested-Archive Password Prompt

When opening a password-protected book inside an archive (a `.cbz` inside a
`.zip`, etc.), the password prompt is synchronous and modal. Cmd+Q
**defers** the quit (does not discard it) — answering the password prompt or
cancelling it will then fire the deferred quit; the app does not stay open.

**Why unfixable without a redesign:** The prompt is synchronous (not async)
by design, and converting it would require substantial refactoring of the
archive-load path. See task
`docs/tasks/2026-07-30-01-password-prompt-quit-deferral.md` for the decision.

### Case 3: Archive-Load Progress Sheet

When loading a large archive, a progress sheet may appear. Cmd+Q is
swallowed (the `NSModalSession` consumes it). **However**, an AppleEvent
quit (e.g. `osascript -e 'tell app "cooViewer" to quit'`) works
immediately.

**Workaround:** Wait for the progress sheet to complete, or use an AppleEvent
quit from the shell.

---

## 21. All Bookmark Browser: No Page-Jump-on-Click Gesture

The All Bookmarks browser lists bookmarks for the currently open book, but
there is **no gesture to click a bookmark to jump to that page** — the Open
button in the browser opens a *different* book from a different folder.

This is a feature gap, not a defect. Whether to add it is an owner decision,
left to a future task.

## 20. `en.lproj/Localizable.strings` Is UTF-16LE, `ja.lproj` Is UTF-8

`Resources/en.lproj/Localizable.strings` is UTF-16 little-endian;
`Resources/ja.lproj/Localizable.strings` is UTF-8. Both are valid — the
`.strings` format allows either — but the asymmetry is a trap:

- Appending to the en file with a UTF-8 tool (`cat >>`, `echo >>`, a
  plain `open(path,'a')`) silently produces a file that is *still*
  accepted by `plutil -lint` but whose appended keys do not resolve.
  This happened during MW-1 and was caught only by checking that the new
  keys could be read back with `plutil -extract`.
- Verify string edits semantically, not by eyeballing a diff — git shows
  the UTF-16 file as `Bin` and reports no useful line diff:

```bash
plutil -extract "your new key" raw -o - Resources/en.lproj/Localizable.strings
```

To edit the en file, decode and re-encode explicitly, preserving UTF-16:

```python
raw = open(p, 'rb').read(); text = raw.decode('utf-16')
open(p, 'wb').write((text + addition).encode('utf-16'))
```

Normalising both files to UTF-8 would remove the trap and is a
reasonable standalone task; it has not been done because it rewrites a
large localization file wholesale and wants its own verification pass.

## 21. ~~Composed-Spread Cache Is Not Keyed By Screen~~ — RESOLVED BY DELETION (2026-07-29)

**Closed.** The composed-spread cache no longer exists. The legacy
"Old" composited render path (`BufferingMode = 0`) — and with it
`returnComposeImage:and:`, `screenCacheArray`, the `ScreenCache`
preference and `-imageDisplayIfHasScreenCache` — was removed in
`docs/tasks/2026-07-29-02-remove-legacy-composited-path.md`. Every
spread is now drawn straight into the view, so there is no composite to
cache, no cache key to omit the screen from, and nothing to invalidate
on a screen change.

For the record, the issue was: the cache was keyed by page pair +
`fitScreenMode` but not by screen, and nothing invalidated it when a
window moved between displays. An attempt to reproduce it on displays of
genuinely different logical size *and* scale factor produced a
pixel-identical result, and it required two non-default settings
(`BufferingMode = 0` **and** `ScreenCache > 0`) to be reachable at all.
It was never demonstrated to cause a visible defect, and it is now moot.

See `docs/DECISIONS.md`, "Legacy 'Old' composited render path removed",
for why the path went rather than the bug being fixed in place.

---

## 22. Dev-Session Sandboxes: `open -a` / Direct Apple Events / Accessibility Can Work; Screen Recording Is a Separate, Harder Gate

Some dev sessions (agent sandboxes, headless/remote setups) run with a real
process launcher and `NSWorkspace`/Apple Event dispatch, but the *degree* of
GUI access beyond that varies — this is two separate macOS TCC permission
categories (Accessibility, Screen Recording) plus whether a real
window-server session is attached at all, and they can be unlocked
independently.

**Baseline (no screen/accessibility at all)** — `lsappinfo info -only
front` returns nothing even right after launching an app:

- `open -a cooViewer.app <file>` launches the app for real and exercises its
  full logic (menu actions triggered by `NSApplication`,
  `application:openFile:`, defaults reads/writes) — this works and is a
  reliable way to exercise app behaviour headlessly.
- A **direct Apple Event sent to the app itself** (e.g.
  `osascript -e 'tell application "cooViewer" to quit'`) also works reliably
  — `quit` runs the app's normal termination sequence, which does send
  `windowWillClose:` to open windows before the process exits.
- `System Events` UI scripting does not work at all: `tell application
  "System Events" to tell process "X" to count windows` returns `0` even for
  an app that is definitely running with a document open, `keystroke`
  commands silently no-op, and accessibility-tree queries either hang or
  time out. `screencapture -x` fails outright (`could not create image from
  display`).

**With a screen-sharing session attached (e.g. Jump Desktop/Screen
Sharing) but the sandbox's own process still lacking Screen Recording** —
observed 2026-07-29 in `docs/tasks/2026-07-29-05-mw3-visual-verification.md`:
`System Events` UI scripting **starts working properly**
(`count of windows`, `entire contents`, `click`, setting `AXValue`,
`AXShowMenu` on Dock icons, reading menu bar / sheet / table contents all
behaved correctly and matched real app state), but `screencapture -x` still
fails with "could not create image from display" — Accessibility and Screen
Recording are separate TCC grants, and only one had actually taken effect.
`lsappinfo info -only front` still reported no front app even while
`System Events` could see and interact with the target process correctly —
don't use `lsappinfo` as the sole signal for whether UI scripting will work;
just try a concrete `System Events` query.

**How to apply:** when on-device verification is needed in such a session,
try a targeted `System Events` query rather than assuming the baseline case
applies — the two-permission split above means UI scripting alone can
recover a lot of verification power even without pixels. Structural/state
checks (menu contents, sheet field values, window titles, table rows) can
substitute for a screenshot in most cases: e.g. reading a `Bookmark` menu's
items or a `BookSettings` dictionary via `defaults read` after an add/quit/
relaunch cycle proves a persistence round-trip as convincingly as looking at
it. Only pixel-level checks (image quality, PDF page rendering correctness,
literal visual appearance) genuinely require Screen Recording; if
`screencapture -x` still fails after confirming `System Events` works,
report that specific gap rather than the screen being unavailable outright,
and don't retry more than 2-3 times — request the permission be granted (or
the check be done by the human directly) instead of hunting for a
workaround. Always back up the real defaults domain (`defaults export
<bundle id> <file>`) before UI-driving an app with real user data, and
restore it (`defaults import <bundle id> <file>`) afterward so exercising
doesn't leave test artifacts in the real profile — done for both
`RecentItems`/`LastPages`/`BookSettings` in
`docs/tasks/2026-07-29-04-mw3-persistence-api.md` and the bookmark/
`OpenLastFolder` checks in `...-05-mw3-visual-verification.md`.

**Resolving the Screen Recording gap** — also observed 2026-07-29, later the
same day, in the same task doc: granting Screen Recording to the visible
terminal app (Ghostty) was **not** sufficient — `screencapture` kept
failing until the OS put up its own consent prompt (a "Screen & System
Audio Recording" window under the `System Settings` process, reachable via
`System Events` as `window "Screen & System Audio Recording" of process
"System Settings"`) naming the *actual* process making the capture call —
in a `launchd → tmux → -zsh → claude → zsh` process tree, that was **`tmux`**,
not the terminal emulator. Granting Screen Recording to the right process
(found by triggering a `screencapture` call and reading which process name
the resulting consent prompt names, not by guessing from the visible
terminal app) made `screencapture -x` work immediately.

**A pixel-check gotcha once Screen Recording does work:** a screenshot
taken immediately after an app launches/opens a document can catch the
window mid-first-paint and show solid black/blank content that has nothing
to do with the app's actual rendering — this happened for a PDF page in
`...-05-mw3-visual-verification.md` and was initially (and wrongly) treated
as a rendering defect. A second screenshot taken ~1-2s later, or after
navigating away and back, showed the same page rendering correctly, and a
fresh launch with a longer wait before the first screenshot reproduced the
correct render cleanly. Before reporting a pixel-level defect from a
sandbox screenshot: retake it after a couple of seconds, and cross-check
against a different renderer if one is available (e.g. macOS Preview.app
for a PDF) to rule out a source-file problem too. Don't fix or file the
underlying app as broken on a single black frame.

---

## 23. `open <app-path> <file-path>` (No `-a`) Can Silently Launch the Wrong App — Always Use `open -a`

Discovered 2026-07-29 during MW-4 on-device verification
(`docs/tasks/2026-07-29-06-mw4-menu-actions-responder-chain.md`).

- `open build/cooViewer.app tests/fixtures/generated/test.cbz` (two
  arguments, no `-a`) does **not** mean "open the file with that app". `open`
  treats each argument independently: the `.app` path launches itself (with
  no file to open, since nothing told it to), and the file path is opened
  with **its own LaunchServices-default handler** — on this machine that's
  `/Applications/cooViewer.app` (the Homebrew-managed install; see #18 for
  why `/Applications` reliably wins), not the freshly built test copy.
- Both copies share the same bundle ID (`jp.coo.cooViewer`) and therefore
  the same `NSUserDefaults` domain. The unintended `/Applications` launch
  opened the real, personal `RecentItems`/`LastPages`/`BookSettings` data
  and inserted a test-fixture entry into it — a real user-data mutation,
  not a sandboxed side effect. Caught immediately via `defaults read` (the
  test path was unexpectedly at index 0) and reverted by exporting the
  domain, editing out only the identified inserted entry in binary-plist
  form (XML `plutil`/`plistlib` output can choke on control characters
  present in the archived `NSData` alias blobs — use
  `plistlib.dump(..., fmt=plistlib.FMT_BINARY)` or equivalent), and
  `defaults import`ing the corrected whole domain back. A full before/after
  key-by-key diff confirmed nothing else changed.
- **Always use `open -a "<absolute-path-to-test-build>.app" "<file>"`**
  when launching a dev build with a file argument — `-a` is what actually
  binds the file to that specific app instance instead of going through
  default-handler resolution. This applies generally, not just to
  cooViewer: any dev build that shares a bundle ID with an installed
  release is at risk the same way.
- Compounds #18: because `/Applications` wins LaunchServices dedup here,
  the failure mode from a bare `open app file` mistake is not "nothing
  happens" or "an error" — it's "the *other*, real copy opens the file and
  quietly touches real persistent state." Treat any accidental extra
  `cooViewer` process (check `pgrep -fl cooViewer` for more than one PID)
  as a signal to check `defaults read jp.coo.cooViewer RecentItems` before
  doing anything else.
- Standing practice going forward (already established by #22's guidance
  to back up before UI-driving an app with real data): before any on-device
  session that opens a book, confirm `pgrep -fl cooViewer` shows exactly
  the intended PID from `build/cooViewer.app`, and export the defaults
  domain first regardless, since the launch command itself is a place this
  can go wrong even when the intent was correct.

---

## 24. ~~Bookmark ▸ Edit Bookmark… Is Disabled With No Book Open, So the All Bookmark Browser Is Unreachable~~ — FIXED (2026-07-30)

Fixed by the second of the two candidate fixes below: the browser has its
own **Bookmark ▸ All Bookmarks…** item, targeted at `AppController` so it is
enabled whether or not a window has a book. `Edit Bookmark…` is unchanged and
still First-Responder-targeted. See
`docs/tasks/2026-07-30-06-all-bookmark-entry-and-quit-with-sheet.md` and the
DECISIONS entry it points at. The original report follows; the diagnosis in it
was confirmed on device before the fix — the item was never removed from the
nib, it is disabled for want of a target.


Discovered 2026-07-29 while verifying MW-5's `BookmarkController` split
(`docs/tasks/2026-07-29-08-mw5-bookmark-controller-split.md`).

`-[Controller editBookmark:]` has two branches: with a book open it raises
the per-book Bookmark sheet, and with no book open it raises the app-wide
**All Bookmark** browser (the panel that edits every book's bookmarks and
can reopen a book with its "Open" button).

MW-4 retargeted the `Edit Bookmark...` menu item from `target="484"`
(Controller) to First Responder (`MainMenu.xib`, item `609`). `Controller`
reaches the responder chain only as the window's delegate, so when no window
is open there is no target for `editBookmark:` and AppKit disables the item
before `-validateMenuItem:` is consulted — even though that method's
`Edit Bookmark...` branch deliberately returns YES in exactly that case
(`Controller.m:1927-1933`, with the older `return NO` commented out).

Net effect: the All Bookmark browser has no UI entry point at all. Verified
on device — the menu item is greyed with no window open, and enabled (taking
the per-book branch) with one open. It was reachable before MW-4.

Not fixed in MW-5, which is explicitly a no-logic-change task. Two candidate
fixes, to be decided when the arc reaches it:

- Move the no-book branch to `AppController` (which is always in the
  responder chain) and target the item there — but note MW-7 decision 4
  makes "no window open" impossible while the app runs, which would leave
  the branch dead by design instead.
- Give the browser its own always-enabled menu item on `AppController`,
  separate from the per-book sheet.

The MW-5 split preserved both branches as they are; the app-wide half now
lives in `AllBookmarkController` and was verified by temporarily forcing
`-editBookmark:` down the no-book branch in a throwaway build.

---

## 25. ~~Preferences ▸ OK Crashes the App When a Book Is Open (pre-existing, over-release)~~ — FIXED (2026-07-29)

Found 2026-07-29 during MW-5 on-device verification. **Pre-existing — not
introduced by MW-5.** Bisected by building and running three commits with the
same steps:

| build | result |
|---|---|
| `3d88521` (MW-4, last pushed) | crashes |
| `2cacdc2` (MW-5 2/5) | crashes |
| MW-5 3/5 (`BookWindow.xib`) | crashes |

**Reproduction** (100% so far):

1. Launch, open any book (a folder of images is enough).
2. cooViewer ▸ Settings… (⌘,).
3. Press **OK** (Cancel is fine; the crash is specific to OK).

The app disappears with no crash dialog and no `.ips` report in
`~/Library/Logs/DiagnosticReports`, which is why it can look like a clean
quit. With **no** book open, OK does not crash.

**Evidence**

- Under `lldb`: `EXC_BAD_ACCESS (code=1)` on the main thread in
  `objc_msgSend`, with a garbage receiver — the classic MRC
  message-to-freed-object signature.
- With `NSZombieEnabled=YES`:
  `*** -[CFString copyWithZone:]: message sent to deallocated instance`.
  So the over-released object is an `NSString`, and it is copied (not just
  retained) by whatever touches it after the free.
- Immediately before the crash the log shows
  `-[NSWindow makeKeyWindow] called on <AccessoryWindow …> which returned NO
  from -[NSWindow canBecomeKeyWindow]`, i.e. the
  `[[NSApp keyWindow] makeKeyAndOrderFront:self]` line in the DIALOG_OK branch
  of `-[PreferenceController preferences]` resolved `keyWindow` to the page-bar
  child window. That is the last identifiable step before the fault.

**Where to look.** The OK branch runs a long block of
`[defaults setObject:…]` calls, releases the six key/mouse arrays, then posts
`PreferencesDidChange`, which reaches
`-[BookWindowController preferencesDidChange:]` → `-setPreferences`. The
"book open" precondition points at `-setPreferences` (or something it drives,
such as the page-bar/accessory rebuild), not at the defaults writing, since
the no-book case takes the same writing path and survives. A string ivar
released without a matching retain is the shape to look for.

Not fixed in MW-5, which is a no-logic-change task by definition. It should be
its own task; `NSZombieEnabled` plus a breakpoint on the zombie message will
name the string in one run.

**Resolved 2026-07-29** (`docs/tasks/2026-07-29-08-fix-preferences-ok-crash.md`).

The over-released string was the page bar's, and the unbalanced release was
inside `-[AccessoryView setPageString:]` itself — an aliasing bug, not a
missing retain anywhere else. Full backtrace at the zombie message:

```
-[BookWindowController setPreferences]
  -> -[CustomImageView setPreferences]
    -> -[AccessoryView setPreferences]
      -> -[AccessoryView setPageString:]
        -> -[NSConcreteAttributedString initWithString:attributes:]   <- reads freed memory
```

`AccessoryView` keeps the page string as an `NSAttributedString *pageString`,
and `-[AccessoryView pageString]` returns `[pageString string]` — the
attributed string's **own** backing store, whose lifetime is the attributed
string's. `-[AccessoryView setPreferences]` re-renders the current page string
with the newly built attributes by calling `-setPageString:[pageString string]`
(`AccessoryView.m:187` and `:198`), so the argument is owned by the ivar. The
setter then did:

```objc
[pageString release];                                    // frees `string` too
pageString = [[NSAttributedString alloc] initWithString:string ...];  // reads it
```

That is the whole bug: **a setter that released its old value before consuming
its argument, with a caller that legitimately passes a value owned by that old
value.** It only fired with a book open because with no book
`-[BookWindowController]` sets the page string to nil, `pageString` is nil, and
`-setPageString:` takes its `if (!string)` early return.

Fixed by giving the setter the standard MRC create-then-release ordering:
build the new attributed string, *then* release the old one, then assign. The
`if (!pageString)` special case went away with it (`[nil release]` is a no-op).
No `retain` was added at the crash site and no caller changed.

Verified on device with `NSZombieEnabled=YES`: Preferences OK with a book open
no longer crashes and logs no zombie message; the page bar still renders its
string correctly afterwards; Cancel, the no-book case, and a settings
round-trip (change -> OK -> reopen -> persisted) all behave as before.

**Note for the next reader — one latent instance of the same shape remains.**
`-[AccessoryView setInfoString:]` (`AccessoryView.m:681`) has the identical
release-then-consume ordering. It cannot fire today: `infoString` has no
getter and all of its callers pass freshly built strings, never
`[infoString string]`. It was left alone because this task was scoped to the
actual over-release; give it the same ordering if that file is touched again.

**Closed out 2026-07-29** by
`docs/tasks/2026-07-29-09-accessoryview-followups.md`, which took the three
follow-ups filed here as its own task:

1. `-setInfoString:` now has the safe ordering (prophylactic; still no caller
   that could trigger it).
2. The `pageStringAttr` "leak" **did not exist** — that follow-up note was
   written from the assignment sites without reading the release block at the
   top of the same method (`AccessoryView.m:75`). Retracted, with runtime
   evidence, in the #25 task archive. No code change.
3. The duplicated `-setPageString:` call in `-setPreferences` was removed
   after confirming it had no observable effect; the reasoning is in that
   archive.


## 26. ~~No per-window class in `BookWindow.xib` has a `-dealloc`~~ — FIXED (2026-07-29, MW-7)

Audited during MW-6 item 6 (`docs/tasks/2026-07-29-10-mw6-per-window-behaviour.md`),
which the task asked for while adding the one `-dealloc` it was scoped to.

Every object that MW-5 moved into `BookWindow.xib` is per-window, so from MW-7
onwards each closed window destroys a set of them. Of the eleven classes
involved, **only `AccessoryView` now has a `-dealloc`**:

| class | `-dealloc` |
|---|---|
| `AccessoryView` | **added in MW-6** (never runs yet — see below) |
| `BookWindowController` | none |
| `CustomImageView` | none |
| `CustomWindow` | none |
| `AccessoryWindow` | none |
| `ThumbnailController` | none |
| `ThumbnailMatrix` | none |
| `ThumbnailPanel` | none |
| `BookmarkController` | none |
| `BookmarkPanel` | none |
| `FullImagePanel` / `FullImageView` | none |
| `FilterPanelController` | none |

This is latent, not a live defect: there is one window, it is never closed in
a way that destroys these objects, and the process exit reclaims everything.
`BookWindowController` is the largest of them — roughly forty retained ivars,
several `NSMutableArray`s and an `NSLock` — and it is also the one whose
teardown interacts with the lookahead threads, so it is not a mechanical
addition.

**Two things MW-7 must verify, which MW-6 could not:**

1. **`-[AccessoryView dealloc]` has never executed.** It was written from the
   ownership visible in the class (see the commit message on `58a66bf` for
   the full argument), not from a leak trace, and with one window the view
   lives as long as the app. The first window close under MW-7 is its first
   run. Both timers are `repeats:NO` and target `self`, so the run loop keeps
   the view alive for up to their 2 s interval after the window goes — the
   `-invalidate` calls in `-dealloc` therefore guard a *future* repeating
   timer rather than making `-dealloc` reachable. A repeating timer added
   later without an explicit teardown call would keep the view alive forever.
2. **Whether the rest of the table gets the same treatment.** MW-5 already
   deferred "no leaked nib top-level objects" to MW-7; this table is what
   that check has to cover. Recommended approach when it is done: a dealloc
   log or `leaks` on a build that opens and closes several windows, rather
   than writing eleven `-dealloc`s from inspection.

**Resolution (MW-7, `7abc21a`).** Nine classes gained a `-dealloc`:
`BookWindowController`, `CustomWindow`, `CustomImageView`,
`ThumbnailController`, `ThumbnailMatrix`, `BookmarkController`,
`FullImagePanel`, `FullImageView` and `FilterPanelController`.
`ThumbnailPanel`, `BookmarkPanel` and `AccessoryWindow` own no object ivars
and deliberately got **no** `-dealloc` rather than an empty one.

Verified, not inferred: a build with a temporary `NSLog` in each `-dealloc`
(and a temporary one added to the three classes that ship without) was driven
through a three-window session, and **all thirteen classes logged exactly one
deallocation per retired window**, `-[AccessoryView dealloc]` included — its
first ever execution. `leaks` on the shipping build showed no cooViewer
per-window object leaked after opening and closing a second window.

Two things the write-from-inspection approach would have missed and the run
confirmed:

- **The window/view group is released one close behind.** `CustomWindow`,
  `CustomImageView`, `AccessoryWindow` and `AccessoryView` are not
  deallocated when their own window closes but when the *next* window does
  (AppKit holds the most recently closed window). Do not read a missing
  dealloc for those four immediately after a close as a leak.
- **The last window is never retired**, so its objects are never deallocated
  — see `docs/DECISIONS.md`, MW-7 decision 1. That is the one path these
  methods do not exercise.

## 27. ~~`Recent Books` menu items are targeted at whichever window built them~~ — FIXED (2026-07-29, MW-7)

Found while implementing MW-6 item 3, which fixed the same shape for the
bookmark menu, the "Open from same folder" submenu and the read/sort
check-marks — but Recent Books was not in that item's list, so it was left
alone.

`-[BookWindowController setOpenRecentMenu]` builds the shared Recent Books
submenu and sets `[menuItem setTarget:self]` on every item. The *contents* are
app-wide (they come from the `RecentItems` default), so unlike the other three
menus they do not go stale — but the targets are per-window. With more than
one window, choosing a recent book would open it into whichever window last
rebuilt the menu, not the front one.

Harmless today: one window, one target. Two ways to fix it in MW-7 — rebuild
the menu in `-windowDidBecomeMain:` alongside the bookmark menu, or drop the
explicit target so `-openFromOpenRecent:` resolves through the responder chain
like the actions MW-4 retargeted. The second is smaller and matches the
direction of travel, but note `-setOpenRecentMenu` is also called from
`-[AppController clearRecent:]` and from `-openPage:last:`.

**Resolution (MW-7, `44b3a82`).** The second option: `-setOpenRecentMenu` no
longer sets a target, so `-openFromOpenRecent:` resolves through the responder
chain. The submenu is `autoenablesItems="NO"` in `MainMenu.xib`, so the
explicit `setEnabled:NO` on missing files still stands and no validation pass
was introduced. Verified with two windows: with the *slot 0* window front and
the *slot 1* window the last to have rebuilt the menu, choosing a recent book
replaced the front window's book and left the other window alone.

## 28. `-[FilterPanelController deleteFilter:]` drops a `CIFilter` without unregistering its KVO observers

Found while writing that class's `-dealloc` in MW-7 (KNOWN_ISSUES #26).

`-drawFilterUIViews` registers the controller as a KVO observer of **every
input key of every selected `CIFilter`**:

```objc
[newFilter addObserver:self forKeyPath:attrkey options:… context:nil];
```

Nothing removes those registrations when the user clicks a filter's close
button. `-deleteFilter:` just does
`[selectedFilters removeObjectForKey:[sender identifier]]`, which releases
the filter while it is still observed — "was deallocated while key value
observers were still registered", which is a hard error, not a leak.

Not observed in practice, which is why it is recorded rather than fixed: the
filter is also retained by the KVO machinery and by
`-setUserDefaults`'s `NSKeyedArchiver` pass, so it does not actually reach
`-dealloc` at that moment on the paths exercised so far. It is a live trap
for anyone who changes the ownership around `selectedFilters`.

`-[FilterPanelController dealloc]` (MW-7) does unregister, because there the
release is guaranteed. The fix is the same three lines in `-deleteFilter:`;
it was left out because MW-7's scope was the window lifetime, not the filter
UI, and the fix wants a test with a filter actually applied.

---

## 29. Alias Manager path helpers leak a few `CFString`s per book open

Measured in MW-7 with `leaks` and `MallocStackLogging`: opening and closing
a second window adds roughly four small `ROOT LEAK: <CFString>` blocks
(~350 bytes), attributed to `-[BookWindowController pathFromAlias:]` under
`-setOpenRecentMenu` / `-openPage:last:`. No cooViewer *object* leaks — the
whole per-window object graph is destroyed correctly (#26) — so this is a
bounded, per-open string leak, not a growing one per window.

The cause is the deprecated Alias Manager (`FSNewAliasFromPath`,
`FSCopyAliasInfo`, …) wrapped in `-aliasFromPath:` / `-pathFromAlias:` /
`-dataFromAlias:` / `-aliasFromData:`. `docs/multiwindow-plan.md` already
lists **Alias Manager → `NSURL` bookmark data** as an out-of-scope follow-up
for the whole MW arc; this is the concrete cost of not having done it, and
the migration is where it should be fixed rather than by patching individual
`CFRelease` calls into the existing helpers.

Also still open from the MW-5 follow-up: the bounded 6-allocation
`NSBezierPath` leak in `-[AccessoryView setFrame:]`, which shows in the same
`leaks` output as a 3-block, 704-byte root leak.

---

## 30. An empty or unreadable book opens as a one-page book, not as a failure

`-[COImageLoader initWithPath:displayPath:readSubFolder:controller:]` ends
with:

```objc
if ([self itemCount]==0) {
    [contentPathArray addObject:[[NSBundle mainBundle] pathForResource:@"empty" ofType:@"png"]];
}
```

so a loader never reports zero items. Two consequences, both found while
implementing Step-0 decision 4 (2026-07-30):

- `-[BookWindowController openPage:last:]`'s guard
  `[newImageLoader itemCount] < 1` is **dead** — it cannot fire. The only
  live half of that condition is `[newImageLoader mode] < 0`, which means a
  cancelled archive read or a cancelled/failed password prompt.
- Opening a garbage archive or an empty folder therefore *succeeds*: a
  window opens showing the placeholder page, and the path is added to
  Recent Books as a real book. There is no error reported to the user
  beyond a line in the console.

Not fixed here because it is a UX decision, not a defect with an obvious
right answer: the placeholder also serves the legitimate case of a book
whose pages fail to decode individually. Whoever changes it should
distinguish "this book has no readable pages" from "this page failed",
and then decide whether `-openPage:last:` should surface an alert rather
than silently closing the window.

Note for anyone testing the failure path: use a cancelled **archive read** —
open a large archive and press Esc while the progress sheet is up (a ~100 MB
`.7z` reliably shows one; a ZIP will not, since `COZipArchive` only reads the
central directory). A corrupt file does not reach it.

*Updated 2026-07-30 (window-modal password prompt).* This entry used to name
a cancelled password prompt as the other way in. It no longer is: cancelling
the prompt now leaves the window bookless and ordered out instead of taking
the `-performClose:` branch (`docs/DECISIONS.md`, decision 4 of "The archive
password prompt is window-modal…"). The cancelled read above is what remains,
which is also why the quit-on-last-close guard this entry discusses had to
stay — verified, not assumed.

The UX question this entry is really about — what an unreadable book *should*
do — is still open and still a decision rather than a defect: the placeholder
serves the legitimate case of a book whose pages fail to decode individually.
Whoever changes it should distinguish "this book has no readable pages" from
"this page failed", and then decide whether `-openPage:last:` should surface
an alert.

---

## 31. The first open into a freshly shown window is not pixel-identical to a later open of the same book

Found while verifying MW-8's image-quality gate (2026-07-30), and
**unrelated to window restoration** — it reproduces with restoration
switched off.

Reproduction, same session, same window, same book, same page, window not
moved or resized in between:

1. Let the app open a book into a window that has just been created and
   shown (a Finder open into a new window, or `OpenLastFolder` at launch).
   Capture the content area.
2. In the same window, switch to another book via File ▸ Recent Books and
   back again. Capture the same rectangle.

The two captures differ: the page borders move by about one pixel and the
glyph edges pick up a thin anti-aliasing outline. Measured on a 3340×1960
capture: ~46 700 differing samples, max delta 58; the diff map is outlines
only, never fills. Two captures of the *same* state are byte-identical, so
this is not capture noise.

That means one of the two composes against a slightly different view
bounds — almost certainly the first one, since `-openPage:last:` orders the
window front and then displays, whereas the second open runs with the view
already laid out. `CLAUDE.md` calls out that spread geometry now comes
entirely from `-[CustomImageView getDrawImagesInfo:and:]` with no
compositor in between, so "when does the view learn its bounds" is a
rendering concern.

Not a resampling-count defect: the softness measurement (fraction of pixels
that are neither near-black nor near-white, which is what an extra resample
raises) does not go up — in the MW-8 measurements the first/restored render
was slightly *sharper* than the re-open, not blurrier. So this is a layout
rounding difference, not a second scaling step.

Whoever picks this up should establish which of the two is drawn at the
right size before changing anything, and must count resampling steps before
and after per the inviolable rule at the top of `CLAUDE.md`.

---

## 32. ~~A Finder open of a book that window restoration is bringing back gives two windows on the same book~~ — FIXED (2026-07-30)

Found by the MW-9 regression pass (2026-07-30) and fixed the same day; see
`docs/tasks/2026-07-30-04-fix-duplicate-window-on-restored-book.md`. A Finder
request that arrives during launch is now held until every restored window
has its book, then routed through the same de-duplication, so the restored
window is brought forward at its saved page instead of a second window being
opened. The original report follows.

It is the one interaction between MW-8's window restoration and Step-0
decision 2 ("the same book opened twice brings the existing window forward")
that the de-duplication did not cover.

Reproduction (default settings, nothing disabled):

1. Open a book, quit with its window still open — the ordinary Cmd+Q. macOS
   saves restorable state for that window.
2. Open the *same* book from Finder (or `open -a cooViewer.app <book>`).
3. Two windows appear on that book: the restored one, at its saved page, and
   a second one the open request created, at page 1.

Control: close every window before quitting (File ▸ Close All, which also
quits per decision 4), so there is nothing to restore, and the same Finder
open produces exactly one window.

Cause: when the open request is de-duplicated, no window has a book yet, so
`-[AppController windowControllerShowingBook:]` has nothing to match against
and the request opens a window of its own. `-emptyWindowController` already
declines a window that is mid-restoration (`-isAwaitingRestoredBook`), which
is why the open created a new window rather than racing the restoration into
the same one; what was missing is a *deferred* dedup — a book that is about
to be restored is not yet a book that is open.

*Correction to this entry's original wording (2026-07-30, made while fixing
it):* the cause was first written up as "`application:openFile:` runs before
AppKit decodes window state", inherited from the comment MW-8 left on
`-applicationDidFinishLaunching:`. Instrumenting every launch hook on macOS 26
shows that state is decoded **before** `-applicationDidFinishLaunching:`, and
the open request arrives after that — what has not happened by then is the
restored *book open*, which `-restoreStateWithCoder:` defers by one run-loop
pass. The measured order is in `docs/DECISIONS.md`; it does not change the
symptom, but it is what the fix had to be built on.

MW-9 recorded this rather than fixing it, because that task was a
verification pass. The fix is
`docs/tasks/2026-07-30-04-fix-duplicate-window-on-restored-book.md`, and the
question it had to settle first — which window wins — was decided by the
project owner in that task: the restored window, at its saved page.

---

## 33. Loading a book still blocks the other windows

MW-1 replaced the app-modal password `NSAlert` with a sheet on the window
whose book needs the password, and moved the archive read off the main
thread. What it deliberately did **not** do — recorded as deferred by design
in `docs/tasks/2026-07-28-03-mw1-archive-load-concurrency.md` — is make the
whole open asynchronous. Now that MW-7 and MW-8 have shipped real multiple
windows, that deferral is user-visible, so it is recorded here rather than
only in a task archive.

Observed in the MW-9 pass (2026-07-30) with two windows open: while the
password sheet for an encrypted archive is up on its own window, the menu
bar is disabled application-wide (`enabled = false` on File and View items),
so the other window cannot be operated until the prompt is answered. The
sheet itself is attached to the correct window, which is what the arc's
acceptance matrix asked for; the modality is the leftover.

Cause: `-[BookWindowController askArchivePassword:wrongPassword:]` needs a
synchronous answer for `COImageLoader`'s retry loop, so it presents the
sheet and then runs `[NSApp runModalForWindow:]` — an application-modal
loop around a window-modal sheet. The same shape applies to the load itself.

Nothing is dropped or corrupted; this is a responsiveness limitation. The
fix is the asynchronous open MW-1 named as "the better end state once MW-7
lands", not a change to the sheet.

### The password half is FIXED (2026-07-30)

The prompt is window-modal now: the open is continuation-passing, so the
sheet needs no modal loop, and with one up the other windows can be raised,
driven from the menus and paged. See
`docs/tasks/2026-07-30-05-window-modal-password-prompt.md` and
`docs/DECISIONS.md`, "The archive password prompt is window-modal…".

**What remains open is the loading half only:** a *load* still blocks the
other windows, because `-runArchiveLoadNamed:usingBlock:` drives the progress
sheet from an `NSApp` modal session. Deliberately pending rather than
forgotten — a local archive opens in well under a second, so the deferral
costs nothing in practice, and the same continuation-passing seam the password
half now uses is where an asynchronous open would go. The prompt for an
archive nested *inside* another archive also still uses the synchronous,
app-modal path, by design (see decision 3 in that DECISIONS entry).

---

## 23. v1.6.0 Release — Known Limitations

### #34: Cannot quit while modals are displayed (three cases)

Three scenarios remain where quit (Cmd+Q, application menu, or AppleEvent) is
blocked or deferred while a modal is active. These are **decided not to fix**
as of v1.6.0.

- **All Bookmarks browser** (`runModalForWindow:`): The browser is modal.
  Close it before quitting.
- **Nested-archive password prompt**: Quit is **deferred** — answering the
  prompt or cancelling it will then fire the deferred quit; the app does not
  stay open.
- **Archive-load progress sheet**: Cmd+Q is swallowed by the `NSModalSession`.
  An AppleEvent quit (e.g. `osascript -e 'tell app "cooViewer" to quit'`)
  works immediately.

See DECISIONS.md "Three modal-quit edge cases" for details.

### #35: All Bookmarks browser has no bookmark-to-page navigation

The browser displays bookmarks from the current book but does not support
clicking a bookmark to jump to that page. The Open button switches to a
different book. This is a feature gap left to future consideration.

---

## 36. ~~Closing one of several windows crashes in `-[AccessoryView drawRect:]`~~ — FIXED (2026-07-30)

Shipped in v1.6.0 and reported from the field: with more than one window
open, closing one crashed the app with `EXC_BAD_ACCESS` in
`-[AccessoryView drawRect:] + 60`, on `objc_msgSend` with `x1` = selector
`indicator`. Single-window builds never showed it because closing the only
window also ended the process.

**Cause — use-after-free on an unretained outlet.** `AccessoryView`'s
`controller` and `imageView` are `IBOutlet`s and are deliberately not
retained (see the `-dealloc` comment in that class). When
`-[BookWindowController dealloc]` runs, `controller` becomes a **dangling
pointer, not nil** — which is why the reported fault address
(`0x00657fec4301bf38`) is garbage rather than zero, and why a nil check
alone cannot prevent the crash.

The view outlives the controller because of #26: the window/view group
(`CustomWindow`, `CustomImageView`, `AccessoryWindow`, `AccessoryView`) is
released **one close behind**, since AppKit holds the most recently closed
window. During that interval the `AccessoryWindow` child window is still in
the display cycle, so a draw request queued before the close still reaches
`-drawRect:`.

The reliable trigger is the auto-hide timer. With `PageBarAutoHide` or
`PageNumAutoHide` on (both are on in the owner's profile),
`-mouseMoved:` schedules `accessoryTimer` for 2 s; `-hideAccessory` then
calls `-displayRect:`. Hovering over a window and closing it within those
2 s fires the timer into the retired view.

**Fix.** `-[AccessoryView detachFromWindowController]` sets both outlets to
nil by **direct ivar assignment**, called from
`-[BookWindowController windowWillClose:]`.

Two things that look like alternatives and are not:

- **`AccessoryWindow -dealloc` is the wrong call site.** By #26 it runs one
  close *late* — after the controller has already been freed and after the
  crash interval. `-windowWillClose:` is the only point still inside it.
- **KVC is the wrong mechanism.** This project is MRC, and
  `-setValue:nil forKey:` releases the previous value — that would send
  `-release` to the already-deallocated controller, converting a
  read-after-free into an over-release.

Nil guards were also added in `-drawRect:`, `-mouseMoved:`,
`-drawPageBarBubble` and `-pageBarRect`. They are **insurance, not the
fix**: they only help once the pointers have actually been nil'd.

Reproduced and verified with real output — see
`docs/tasks/2026-07-30-08-fix-multiwindow-close-crash.md`.

**Not covered by this fix:** `CustomImageView`'s `target` ivar is the same
unretained-back-reference shape and was left alone as out of scope. It has
not been observed crashing; recorded here so it is not mistaken for
verified-safe.
