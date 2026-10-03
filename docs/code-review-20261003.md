# Code Review and Dead-Code Report — 2026-10-03

Read-only review of the current sources (v1.6.5, `main` at `651b5ed`). No
source file was changed. Deletion and fixes are separate, later tasks
(`CLAUDE.md` ▸ Dead Code). Task record:
`docs/tasks/2026-10-03-04-cbr-perf-and-code-review.md`.

## Scope and method

- **Reviewed:** `Sources/`, `PreviewExtension/`, `ThumbnailExtension/`,
  `NewWindowHelper/`. Not `vendor/` (only consulted for API contracts).
- **Looked for:** correctness defects only — MRC over/under-release,
  observers and timers outliving their owner, UI from background threads,
  races on shared state, error paths, untrusted-input handling, and anything
  that would affect the render-path rule (`CLAUDE.md` ▸ INVIOLABLE).
- **How:** the sources were split into four read-only passes
  (`BookWindowController*`; views, app and thumbnail classes; archive layer,
  preferences, bookmarks, remote control, extensions and helper; dead code).
  Each finding was then checked against `docs/KNOWN_ISSUES.md`.
- **Verification level**, given per finding:
  - **re-read** — the TF session re-read the code path itself and agrees.
  - **read** — established by one review pass reading the path end to end;
    not independently re-read.
  - **plausible** — the code allows it; the trigger was not traced to the
    end or depends on timing or OS behaviour.
  - **reproduced** — exercised in a scratch harness that compiles the
    current sources (outside the repository).
  - Nothing was reproduced by running the app.
- Line numbers are those of `651b5ed`.

## Render-path rule: holds

Checked in every pass. The spread path is still decoded `NSImage` →
`-[CustomImageView setImages:]` → `-drawRect:` → `-drawImages:and:` → one
`drawInRect:fromRect:` per page (`Sources/CustomImageView.m:1464`, `:1467`);
the single-page path is one `drawInRect:fromRect:` (`:1077`). `LoupeView` and
`FullImageView` also draw the decoded image directly. The `lockFocus`
composites that exist (thumbnail grid in `ThumbnailController.m`, page-bar
bubble at `AccessoryView.m:515`) are not on the page render path. Finding M10
is a geometry defect inside the one step, not an added step.

## Findings, most severe first

| # | Sev. | Where | Summary | Fix size | Level | KNOWN_ISSUES |
|---|---|---|---|---|---|---|
| H1 | high | `BookWindowController.m:2353-2357`, `:2436-2440` | Page input in a bookless window recurses forever → crash | S | re-read | not recorded |
| H2 | high | `NSString_Compare.m:16-22` | `-finderCompareS:` copies any-length strings into 1024-unit stack buffers | S | **reproduced** | not recorded |
| H3 | high | `COImageLoader.m:604-607`, `:640-651` | Nested-archive extraction writes outside the temp dir (`..` in entry names) | S–M | re-read | not recorded |
| H4 | high | `BookmarkController.m:83`, `:87`, `:33` | `bookName` released in `sheetDidEnd:` and again in `-dealloc` | S | re-read | not recorded |
| H5 | high | `BookWindowController.m:133` | `-dealloc` invalidates a slideshow timer that is already freed | S | re-read | not recorded |
| M1 | medium | `CustomImageView.m:233-244` | Save Image… onto its own source deletes the original | S | re-read | not recorded |
| M2 | medium | `ThumbnailController.m:550` etc., `:1000` | Thumbnail fill chain keeps running after its window is gone | S | re-read (no cancel on close); timing plausible | not recorded |
| M3 | medium | `AppController.m:553-556`, `:580-583`; `BookWindowController.m:1360`, `:4099` | Menu opens are not gated while a password sheet is up; book settings get crossed | S–M | read | not recorded (#33 is only the modality) |
| M4 | medium | `BookWindowController_input.m:2473-2543` | Next/previous-folder walks a lazily built submenu that may be stale or empty | S | read | not recorded |
| M5 | medium | `BookWindowController_input.m:2739`, `:2741`, `:2798`, `:2800`; `BookWindowController.m:2178-2181`, `:2383-2432` | Lookahead thread synchronisation gaps beyond what MW-7 fixed | M | read / plausible | not recorded |
| M6 | medium | `CORarHeaderIndex.m:213`, `:338-342`; `CORarArchive.m:437-458` | RAR links counted differently by header index and cursor → pages shift (RAR5) or a broken page (RAR4) | M | **reproduced** | not recorded |
| M7 | medium | `COArchive.m:103-126`; `COCoverExtractor.m:76` | Mislabelled `.cbr`/`.cbz` falls back to full in-memory extraction, also in the QuickLook extensions | S–M | read | not recorded |
| M8 | medium | `ThumbnailController.m:111`, `AccessoryView.m:408` → `BookWindowController.m:2066-2131` | `cacheArray` mutated from the main thread without `lock` while a lookahead thread uses it (only with `ImageCache` ≠ 0) | S–M | read | not recorded |
| M9 | low–med | `COZipArchive.m:231-267` | A wrong ZipCrypto password is accepted about 1 time in 128 | S | read | not recorded |
| M10 | low–med | `CustomImageView.m:1422-1425`, `:1464-1469` | Spread `fromRect` truncated to whole points (geometry, not an extra step) | S + spread capture | read | not recorded (#6 is general) |
| M11 | low–med | `CustomImageView.m:400-409`; `BookWindowController_input.m:2700-2705` | Page-bar click in the last 2 px goes past the last page (wrap or next book) | S | read | not recorded |
| M12 | low–med | `ThumbnailController.m:1312`, `FullImagePanel.m:39`, `BookWindowController_input.m:56`, `BookmarkPanel.m:20`, `PreferenceController.m:2263`, `:2374` | `characterAtIndex:0` on a possibly empty key string | S | plausible | not recorded |
| L1 | low | `COZipArchive.m:316`, `:340-354` | ZIP entry buffer sized from the declared size, plus automatic prefetch (decompression bomb) | S | plausible | not recorded |
| L2 | low | `COImageLoader.m:604-606` | One unreadable nested archive aborts the whole book | S | read | related to #30 |
| L3 | low | `COCoverExtractor.m:99-100` | QuickLook extensions keep decoding (prefetch) after returning the cover | S | read | not recorded |
| L4 | low | `COImageLoader.m:203-204`, `:617`, `:651` | Duplicate entry names all resolve to the first entry | M | read | not recorded |
| L5 | low | `BookWindowController_input.m:2113` and four similar sites | `objectAtIndex:0` after `-lookahead` on a one-page book | S | read | not recorded |
| L6 | low | `CustomImageView.m:20-23`; `FilterPanelController.m:230` | Filter changes in one window apply to every window | S–M | read | not recorded (owner to confirm intent) |
| L7 | low | `COPopUpTextField.m:13-16` | `NSPopUpButton` leaked per closed window (no `-dealloc`) | S | read | not recorded (#26 table omits it) |
| L8 | low | `BookWindowController.m:312-342` | `keyArray`/`mouseArray` mutated while enumerated (legacy profiles only) | S | plausible | not recorded |
| L9 | low | `CORarHeaderIndex.m:312`, `:348` | RAR4 64-bit data size not bounds-checked before pointer arithmetic | S | read | not recorded |
| L10 | low | `COImageLoader.m:642-644` | `mkdtemp` writes into `-fileSystemRepresentation`'s const buffer; failure unchecked | S | re-read | not recorded |
| L11 | low | `ThumbnailMatrix.m:41-46`; `AccessoryView.m:250-252`, `:375-377`; `BookWindowController.m:2131`, `:2531`; `COArchive.m:287`, `CORarArchive.m:464` | Minor: bookmark-icon removal skips entries; uninitialised shadow radius; negative `ImageCache` disables trimming; 256 KB stack buffers on 512 KB threads | S each | read / plausible | not recorded |

### H1. Page input in a bookless window recurses forever

`-lockedImageDisplay` treats `nowPage == [completeMutableArray count]` as
"end of book". With no book, `completeMutableArray` is nil, so `0 == 0`, and
with `LoopCheck` 0 (its unregistered default) it sets `nowPage = 0`, calls the
lookahead (which adds nothing) and calls itself again, without bound.
`-imageDisplay` has no book check, and neither do its callers.

- **Trigger:** v1.6.5 File ▸ New Window (⌘N) shows exactly such a window
  (`docs/tasks/2026-10-03-01-v1.6.5-features.md`). A click in the left half
  (default mouse action), a scroll-wheel notch, a next-page key, or a go-to
  action in that window should crash with a stack overflow. The same applies
  to a ⌘N window left empty after a cancelled password prompt.
- **Fix (S):** return early from `-imageDisplay` / `-lockedImageDisplay` when
  `[completeMutableArray count] == 0`; optionally guard the input entry points
  with `-hasBookOpen` (keeping Esc and close working).
- **Not reproduced:** in a screen session on `build/cooViewer.app`, File ▸ New
  Window produced the empty "Viewer" window, but the real click into it was
  refused by the session's permission classifier; an earlier background
  (accessibility) click did not crash the app, but its delivery to the image
  view could not be confirmed, so it proves nothing either way. Confirming
  the crash is the first step of the fix task.

### H2. `-finderCompareS:` stack buffer overflow

`UniChar buff1[MAXPATHLEN]`, `buff2[MAXPATHLEN]` (1024 units each) are filled
with `getCharacters:`, which copies the whole string. `COImageLoader` sorts
`"<book path>/<entry path>"` strings with it (`COImageLoader.m:514`, `:623`),
and `COCoverExtractor` sorts entry paths with it (`:60`, `:95`), so a long or
crafted entry name overruns the stack — in the app when the book opens, and in
the Thumbnail/Preview extensions when Finder shows the folder.
`NSString_Compare.m` is compiled into all three targets.

- **Reproduced:** a scratch program linking `Sources/NSString_Compare.m`
  compared two 1000-character strings normally and crashed with SIGSEGV
  (exit 139) on two 5000-character strings.
- **Fix (S):** heap buffers sized from `-length` (or
  `getCharacters:range:` into `malloc`'d memory); keep `UCCompareTextDefault`
  so the order is unchanged.

### H3. Nested-archive extraction can write outside the temp directory

Entry names come from archive headers unchanged; `COArchive`,
`COZipArchive` and `CORarArchive` only drop directories and `._*`. For an
entry whose extension is in `+fileTypes` (an archive type or `pdf`),
`-uncompressToTempDir:` joins it with `stringByAppendingPathComponent:`
(which does not resolve `..`), creates the missing directories, and
`-[COArchive uncompress:as:]` writes the bytes there. An entry named like
`../../../../../Users/Shared/x.pdf` is written outside the temp directory,
at book-open time, overwriting any file of that name the user can write. The
main app is not sandboxed.

- **Partly reproduced:** a scratch `.cbz` with an entry named
  `../../../../tmp/…zip`, read through `COArchive`, returns that name
  unchanged, so it reaches `-uncompressToTempDir:` as is. The write itself
  (`COImageLoader`, AppKit) was not run.

- **Fix (S–M):** reject absolute names and names with a `..` component (or
  standardise the joined path and require it to stay under `tempDir`); or
  write nested archives under a generated name such as the entry index plus
  its extension. Fix L10 in the same place.
- Related, speculative: an archive that contains itself recurses without
  limit; a depth cap would close it.

### H4. `BookmarkController` releases `bookName` twice

`-editBookmark:` retains `bookName` (`:57`); `-sheetDidEnd:returnCode:contextInfo:`
releases it on both OK and Cancel (`:83`, `:87`) without setting it to nil;
`-dealloc` (`:33`) releases it again. Since MW-7 the controller is deallocated
with its window, so: edit bookmarks in a window, close the sheet, close that
window → over-release (a crash or heap corruption for non-tagged strings).

- **Fix (S):** set `bookName = nil` after each release.
- The MW-7 dealloc verification recorded in KNOWN_ISSUES #26 closed windows
  without first using Edit Bookmark…, so it did not reach this path.

### H5. Slideshow timer freed before `-dealloc` invalidates it

`timer` holds the autoreleased result of
`scheduledTimerWithTimeInterval:…` (`BookWindowController_input.m:2829`) and
is never retained. Every stop site calls `[timer invalidate]` and leaves the
ivar set; once invalidated, the run loop drops the last reference. MW-7's
`-dealloc` (`BookWindowController.m:133`) then messages the freed timer.

- **Trigger:** close a window (not the last) that ran a slideshow at any
  point while it was open.
- **Fix (S):** `timer = nil` after each invalidate, or retain it while
  scheduled.

### M1. Save Image… onto its own source deletes the original

`-saveCurrentImage:` removes an existing destination
(`removeItemAtPath:`, permanent) before `copyItemAtPath:`. Saving a page of a
folder book into its own folder under the suggested name and confirming
"Replace" deletes the source, and the copy then fails.

- **Fix (S):** do nothing when source and destination are the same file
  (compare standardised paths or file resource identifiers); otherwise use
  `replaceItemAtURL:…` instead of remove-then-copy.

### M2. Thumbnail fill chain outlives its window

`setImageCellWithInfo:` and its siblings re-schedule themselves with
`performSelector:afterDelay:0.001` (`ThumbnailController.m:389`, `:492`,
`:550`, `:676`, `:706`, `:743`, `:777`, `:1136`, `:1193`). Each pending
request retains the `ThumbnailController` but not its unretained
`controller`, `panel` or `matrix`. `-closePanel` (`:1000`) only orders the
panel out, so closing a window while its thumbnail panel is still filling
leaves a chain that later messages the freed window controller or panel.

- **Fix (S):** in `-closePanel`, `[NSObject
  cancelPreviousPerformRequestsWithTarget:self]`, reset the fill counter and
  invalidate the wheel timers.

### M3. Menu opens during a password sheet cross book settings

The busy gate (`isBookLoadInFlight` / `isWaitingForUserInput`) covers only
`-openFiles:preferringWindow:entry:` (Finder opens and drops). ⌘O, Open the
Last Page, Open Recent and Open from Same Folder still reach a window whose
window-modal password sheet is up. Then `-setOldBookPath` overwrites the saved
"old book" without releasing it (leak), the new book's open records the
previous book's page and settings under the pending book's path, and
answering the stale sheet later installs that book under the new book's
title.

- **Fix (S–M):** refuse or redirect those entry points while the window is
  busy, mirroring the Finder gate, or disable the items in validation.

### M4. Next/previous folder reads a lazily built submenu

`-nextFolder`, `-backFolder` and `-backFolderLast` walk the shared "Open from
same folder" submenu, which since #5b is built only in `-menuNeedsUpdate:`. If
the submenu was never opened for this book, next-folder silently does nothing;
if it was built for another folder or window, it opens that folder's sibling
into this window. The check-mark update path is dead (`oldBookPath` is always
nil after a successful open).

- **Fix (S):** build the submenu on demand at the top of those methods (an
  explicit user request, compatible with #5b), and fix the check-mark test.

### M5. Lookahead synchronisation gaps

- `-switchSingle:` detaches `lookahead` / `lookaheadAndCompose` directly
  instead of the counted `…Thread` wrappers, so `-joinLookaheadThreads` does
  not wait for them.
- The ad-hoc `threadStop` / `[lock lock]` barriers in the input code do not
  see a thread that is detached but not yet running (the gap MW-7 fixed only
  for teardown); `-lockedImageDisplay`, `-setPreferences` and `-setSortMode:`
  mutate `imageMutableArray` / `cacheArray` without `lock`.
- When the 2 s join times out, the callers release `imageLoader` while the
  thread may still be inside `-[COImageLoader itemAtIndex:]`. A solid-RAR
  backward read can take longer than 2 s (see the CBR performance report), so
  the "safe because detach retains the target" argument in DECISIONS MW-7 #5
  covers `self` but not the loader.
- **Fix (M):** route every detach through the counted wrappers, replace the
  ad-hoc barriers with one helper, take `lock` around main-thread array
  mutation, and let the thread keep its own reference to the loader.

### M6. RAR link entries are counted differently by the two passes

`CORarHeaderIndex` and the libarchive cursor in `CORarArchive` must agree on
which headers count as pages. They do not for links. `CORarArchive.m:456-458`
assumes the landing header always matches.

**Reproduced** with scratch archives of four entries `a1.jpg`, `a2.jpg`
(Unix symlink to `a1.jpg`), `a3.jpg`, `a4.jpg` (`rar -ol`; RAR5 with rar
7.23, RAR4 with rar 6.24 `-ma4`), read through `COArchive` in entry order:

| format | page `a1` | page `a2` | page `a3` | page `a4` |
|---|---|---|---|---|
| RAR5 | a1 ✓ | (not listed) | **0 bytes** | **a3's bytes** |
| RAR4 | a1 ✓ | **0 bytes** (broken page) | a3 ✓ | a4 ✓ |

- RAR5: the header index skips the link (unpacked size 0), but libarchive
  leaves its size unset, so the cursor counts it; every page after the link
  shows the previous entry's data, and the last page is lost.
- RAR4: both passes count the link, which then shows as an empty, broken page;
  later pages are correct.
- **Fix (M):** align both filters (skip RAR5 redirection records and RAR4
  `S_IFLNK` in the header index; skip `AE_IFLNK` and hard links in the
  cursor), and verify the landed header's name or size against the indexed
  entry, failing closed on a mismatch.

### M7. Mislabelled archives are fully extracted into memory

The reader is chosen by extension. A `.cbr` that is really ZIP/7z (or a
`.cbz` that is RAR) fails both lazy readers and falls back to the base
libarchive path, which decodes every entry into RAM with no size cap. In the
app it is slow but works; in the Thumbnail/Preview extensions a large
mislabelled file can exceed the extension's budget.

- **Fix (S–M):** choose the reader by magic bytes (`PK\3\4`, `Rar!\x1a\x07`),
  extension only as a fallback; refuse the full-extraction path in
  `COCoverExtractor`.

### M8 – L11

Details are as summarised in the table. Notes:

- **M8** needs a non-zero `ImageCache` preference (not registered; 0 on the
  machine used here).
- **M9:** libzip's PKWARE check byte passes about 2/256 wrong passwords, and
  the resulting CRC/compressed-data error is classified as OK, so the book
  opens with every page broken and no new prompt. Treat those errors as
  `WrongPassword` for the validation entry.
- **M10:** the spread path stores `(int)[image size]` and uses it as
  `fromRect`; images with fractional point sizes (high-DPI scans with
  `IgnoreImageDpi` off, A4 PDFs at 595.28 pt) lose up to 1 pt at the right and
  top edges in spreads only. The fix changes output pixels on purpose and must
  be verified with `tools/spread_diff.py` per `CLAUDE.md`.
- **L6:** whether filter settings are meant to be shared between windows is
  an owner decision.
- **L11** collects small items (each S): `ThumbnailMatrix.m:41-46` removes
  while indexing forward (stale bookmark icons); `AccessoryView.m:250-252`,
  `:375-377` leave `white` uninitialised when the colour cannot be converted;
  a negative `ImageCache` makes `cacheSize+4` compare as a huge unsigned value;
  `char buf[256 * 1024]` on GCD/NSThread stacks of 512 KB.

### Checked and found sound

- `CORarArchive`: every libarchive call after indexing runs on `readQueue`;
  prefetch blocks retain what they use; NSCache use is correct; `-dealloc`
  cannot race a pending block; the #37 recovery invalidates the cursor in
  every case.
- `CORarHeaderIndex`: both parse loops move strictly forward; name lengths and
  extra-record loops are bounded (apart from L9).
- QuickLook providers: reply blocks retain what they capture.
- `AppController` routing and restoration bookkeeping, `CustomWindow`,
  `COApplication`, `main.m`, `NewWindowHelper/main.m`, `CONewWindowURL.m`,
  `LoupeView` lifetime, the `AccessoryView` #25/#36 fixes.

### Already recorded (not repeated)

#16 (analyzer survey), #26 (dealloc coverage — see H4, H5, L7), #28
(`deleteFilter:` KVO), #29 (Alias Manager leaks), #30 (one-page placeholder —
see L2), #33 (load modality — see M3), #36 (`CustomImageView` unretained
`target`; M2 is the same shape in `ThumbnailController`), #37 (RAR5 final-block
recovery).

## Dead code

Every candidate was checked against each item of `CLAUDE.md` ▸ Dead Code:
references in sources; XIB outlets, actions and `selector=` entries in
`Resources/Base.lproj/MainMenu.xib` and `BookWindow.xib`; every target's
`Info.plist`; build settings; `@selector` / `NSSelectorFromString` /
`performSelector` / `setAction:` / `respondsToSelector:`; KVC/KVO key paths and
XIB bindings; notification names; `NSClassFromString`; plug-in and QuickLook
entry points; responder-chain actions. The project has no
`NSSelectorFromString`, `NSClassFromString`, XIB bindings or `sdef`. All 45
`Sources/*.m` files are compiled into the app and none is unused as a whole.
The deployment target is 12.0 in every configuration (`project.pbxproj`).

### Proven unreachable

| # | Location | What is dead | Evidence | Size |
|---|---|---|---|---|
| C1 | `FilterPanelController.m:50-54` | `@available(macOS 10.13, *)` check and its `else` (`unarchiveObjectWithData:`) | Always true with a 12.0 minimum; the only `@available` in scope | −4 (keep the if-body) |
| C2 | `AppleRemote.m:135-147` | `NSAppKitVersionNumber <= 10_4` cookie table | AppKit ≥ 2113 on 12.0 | −13 |
| C3a | `AppleRemote.m:148` | only the `floor(NSAppKitVersionNumber) <= 10_5` subexpression | Always false on 12.0; the branch itself stays (see C3b) | condition edit |
| C4 | `AppleRemote.m:42-48` | `#ifndef NSAppKitVersionNumber10_4/10_5` defines | Unused once C2 and C3a are gone | −7 |
| C5 | `AppleRemote.m:110-119` | `-[AppleRemote finalize]` | GC-only; the app is MRC and nothing sends it | −10 |
| C9 | `CustomImageView.m:1471-1485` (the "~1406" of the follow-up list) | `respondsToSelector:@selector(finalize)` block | Inside a `/* … */` comment; not compiled | −15 comment lines |
| C10 | `COZipArchive.m:57-61`, `CORarArchive.m:110-114` | `#else dispatch_release(readQueue)` | `OS_OBJECT_USE_OBJC` is 1 for ObjC on macOS ≥ 10.8 | −4 ×2 (optional) |
| U1 | `BookWindowController.m:3477-3481`, `.h:460` | `-showFilterPanel:` | No XIB `selector=`, no `@selector`/`setAction:` (the menu uses `openFilterPanel:`) | −6 |
| U2 | `BookWindowController.m:2054-2057` | `-pathAtIndex:` | Undeclared, no callers, takes an argument (no KVC) | −4 |
| U3 | `ThumbnailController.m:974-984`, `.h:72`; ivar `pathDic` `.h:26` | `-clearAll` and the never-assigned `pathDic` | No callers or XIB use; the comment at `:52` already says so | ≈ −25 |
| U4 | `FullImageView.m:180-191` | `-spaceBarAction` | Only caller is commented out (`FullImagePanel.m:73`) | −12 |
| U5 | `NSAttributedString_Adding.m:72-75` (+ `.h`) | `-drawAtPoint:bg:` | All callers use `…bg:border:` or `drawInRect:bg:` | −5 |
| U6 | `BookWindowController.h:93` | `IBOutlet id normalWindow` | In neither XIB, no code use (already noted in the MW-5 task record) | −1 |
| U7 | `PreferenceController.h:36-37`, `.m:1013-1022`, `:1520-1529` | `changeOpenWithCheck` / `changeCreatorCheck` and their defaults | Outlets connected in no XIB; the only readers are in the commented-out block at `BookWindowController.m:1573-1631` | ≈ −20 code, −60 comment |
| U8 | `BookWindowController.h:136` | ivar `fitMode` | No use in `BookWindowController*.m` | −1 |
| U9 | `AccessoryView.h:37`, `AllBookmarkController.h:36`, `COImageLoader.h:9`, `CustomImageView.h:10`, `:29`, `:37` | ivars `pageMoverNum`, `completeAll`, `thumbnailArray`, `needFirstScroll`, `lensRect`, `rightPage` | Only the declaration matches anywhere | −6 |
| U10 | `AccessoryView.h:19`, `.m:59` | `pageBarCursor`, always nil | Only assigned inside the commented-out `-resetCursorRects` | −2 |
| U11 | `ThumbnailMatrix.h:9`, `.m:10`, `:174` | `mouseDownPoint` | Written, never read | −3 |
| U12 | `BookmarkController.h:19`, `ThumbnailController.h:34` | outlets `contextMenuItem`, `contextMenu` | Connected in `BookWindow.xib` but unused in code; removal needs an XIB edit (#2) | −2 + 2 XIB lines |
| R2 | `KeyspanFrontRowControl.[mh]` | whole class | Never instantiated (only `#import`ed in `AppController.h:18`); no reflective lookup in the project | owner decision (see below) |

### Not provable (recorded in `docs/KNOWN_ISSUES.md` #40)

| # | Location | Why it cannot be closed |
|---|---|---|
| C3b | `AppleRemote.m:148` branch | Still entered when `leopardEmulation` is set from the IORegistry property `RemoteBuddyEmulationV2` (third-party Remote Buddy driver); its absence cannot be proven |
| C6 | `PreferenceController.m:2005-2011` | The `MAC_OS_X_VERSION_MAX_ALLOWED >= 1040` / `respondsToSelector:@selector(finalize)` guard and its fallback `return NSFontPanelStandardModesMask;`: `+[NSObject respondsToSelector:@selector(finalize)]` returned YES on macOS 26.6 (checked through the Objective-C runtime) and `-finalize` is declared deprecated, not unavailable, so the guarded body is **live** and only the fallback looks dead — but macOS 12–15 were not run |
| C7 | `COPDFImageRep.m:46-47`, `:89-90` | Same guard around PDF link extraction (body live, consumed at `CustomImageView.m:1902`, `:1944`) |
| C8 | `COImageLoader.m:433-436`, `:483` | Same guard around `.savedSearch` support (body live; `savedSearch` is a declared document type) |
| S1 | `Resources/{en,ja}.lproj/Localizable.strings` | Key "The parent folder of current book was changed. Do you want to follow?" has no `NSLocalizedString` use; key-format variants (`…**`) make other apparent orphans unprovable without more work |

Important for C6–C8: removing the guard means **keeping its body**. Deleting
the guarded block would remove live features (savedSearch books, PDF links,
the font-panel mode mask).

### Keep

- `GlobalKeyboardDevice` and the unused RemoteControlWrapper API
  (`MultiClickRemoteBehavior.m:70-93`, `HIDRemoteControlDevice.m:129`,
  `:156-161`): already decided "keep" (KNOWN_ISSUES #16).
- `CORarHeaderEntry->compressedSize` (`CORarHeaderIndex.h:90`): write-only
  but documents the format at no cost.
- About 45 methods with no in-project caller are AppKit callbacks or
  overrides (delegates, `menuNeedsUpdate:`, drag and drop, gesture handlers,
  `validModesForFontPanel:`, QuickLook `provide…ForFileRequest:`), and
  `NSNumberFormatter(Adding) -isPartialStringValid:…` overrides an AppKit
  method. Live.
- About 418 lines of commented-out code in blocks of eight or more lines
  (largest: `CustomImageView.m` ≈ 171, `BookWindowController.m` ≈ 115). Not
  compiled; removal is optional cleanup.

### Owner decision

R2 (`KeyspanFrontRowControl`) is a new unreachable class in the
RemoteControlWrapper library. The 2026-07-25 "keep" decision named only
`GlobalKeyboardDevice`, on the grounds of not diverging from upstream;
`AGENTS.md` now says there is no upstream to track. Removing it needs
`project.pbxproj` and `AppController.h` edits.

## Proposed follow-up tasks (recommended order)

1. **Crash fixes (S, one task).** H1, H4, H5, plus M2's cancel-on-close and
   L7. All small, all in teardown or input guards. Verify with a ⌘N empty
   window (click, wheel, keys), bookmark edit + window close, slideshow +
   window close, thumbnail panel filling + window close.
2. **Untrusted-input hardening (S–M, one task).** H2, H3 (with L10), L9, M7,
   L1. Add engine-suite fixtures: a long entry name, a `../` entry with a
   `.zip` extension, a mislabelled `.cbr`.
3. **Data-loss and book-state fixes (S–M).** M1, M3, M4, L2, L5, M11, M12.
4. **Lookahead synchronisation (M, own task).** M5 and M8. Higher regression
   risk; needs a stress pass (key-repeat paging, slideshow, window close
   during load).
5. **RAR consistency (M).** M6, ideally together with the CBR performance
   follow-ups (`docs/cbr-performance-20261003.md`).
6. **Spread geometry (S, own task).** M10 — changes output pixels; verify with
   the spread capture method.
7. **Dead-code removal E1 (S).** C1, C2, C3a, C4, C5, C10. `AppleRemote.m`
   edits need the owner's OK; AppleRemote cannot be exercised on Apple
   Silicon (no IR receiver).
8. **Dead-code removal E2 (S).** U1–U11 (U7 is the largest).
9. **Dead-code removal E3 (S, XIB edit).** U12.
10. **Owner decisions:** R2; L6 (shared filters); the GC-era guards C6–C8
    (simplify, keeping their bodies, once the owner accepts the inference
    for macOS 12–15); optional commented-out code purge.
