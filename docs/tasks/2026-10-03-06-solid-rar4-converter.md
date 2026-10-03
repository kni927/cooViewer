# TASK: Tool to convert solid RAR4 books to ZIP/CBZ

## Background

cooViewer cannot read solid RAR4 (libarchive has no support; since
`68aa629` it refuses them with a clear message, `docs/KNOWN_ISSUES.md` #39).
The owner surveyed their books with `tools/rar_survey.py --solid-only` and
found about 90 solid RAR4 books, all old. The owner decided to convert them
to ZIP/CBZ instead of adding a second RAR4 decoder to the app.

## Goal

`tools/convert_solid_rar4.py` converts every solid RAR4 `.cbr`/`.rar` under
the given folders to `.cbz`/`.zip` with identical page content, verifies the
result, and can move the originals to the Trash.

## Scope

### In scope

- The tool, its tests, and a short usage note in `tools/` or
  `tests/fixtures/README.md` style (no README.md change).

### Out of scope

- Any change to the app (`Sources/`, project, vendored code).
- Converting RAR5 or non-solid RAR4 (the app reads them).
- Running the tool on the owner's folders unless the owner asks in chat.

### Parts

1. The tool and its tests. One commit.

## Implementation notes

- Python 3 from the macOS Command Line Tools, standard library only, except
  the external extractor below. Reuse the header detection of
  `tools/rar_survey.py` (import or share a small module) so "solid RAR4"
  means exactly what the survey reported.
- **Extractor:** use `7zz` (Homebrew `sevenzip`) or `unar` (Homebrew `unar`),
  whichever is installed; prefer `7zz`. If neither is installed, ask the
  owner in chat to install one (`brew install sevenzip`) and wait. Do not
  install anything yourself. Do not use or bundle unrar code.
- **Default is a dry run:** list what would be converted (source → target)
  and what is skipped and why (not RAR, RAR5, not solid, header-encrypted,
  multi-volume, target exists). Nothing is written.
- `--convert` performs the conversion:
  - Extract into a temporary directory (per book, removed afterwards).
  - Write the ZIP with `ZIP_STORED` (no recompression; page bytes unchanged),
    entries in the archive's original relative paths, UTF-8 names (set the
    UTF-8 flag). Skip directory entries and macOS metadata (`__MACOSX`,
    `.DS_Store`) only if the source has them; report what was skipped.
  - `.cbr` → `.cbz`, `.rar` → `.zip`, same folder, same base name. Never
    overwrite an existing target; write to a temporary name in the same
    folder and rename at the end so a failure leaves no partial target.
  - Preserve the original's modification time on the new file.
  - **Verify** before declaring success: the number of files and, for each
    file, the size and CRC-32 match the source archive's listing (from the
    extractor's listing or by hashing the extracted files against the
    extractor's test result), and the ZIP passes `zipfile.testzip()`.
- `--delete-originals` (only together with `--convert`): after a book is
  converted and verified, move its original to the Trash (recoverable), not
  `rm`. Use `/usr/bin/trash` if present, else Finder via `osascript`; if
  neither works, keep the original and report it. Never delete anything that
  was not converted and verified in this run.
- Errors on one book (password, corrupt data, extractor failure) are reported
  and the run continues; exit status non-zero if any book failed. End with a
  summary: converted, skipped by reason, failed.
- Note in `--help` that Dropbox "online-only" files are downloaded when read
  and that the new files will sync.

## Verification

- Tests with generated fixtures: a solid RAR4 `.cbr` (with a Japanese file
  name inside, if `rar` is available to make one; see
  `tests/fixtures/make_rar4_fixture.py`), a non-solid RAR4, a RAR5, a ZIP
  named `.cbr`, and an existing-target case. Check dry run writes nothing,
  conversion is byte-identical per page, verification catches a tampered
  output, and `--delete-originals` moves only verified originals (test with a
  scratch Trash substitute or by mocking the trash step).
- Open one converted test `.cbz` in `build/cooViewer.app` only if a build
  already exists and the owner agrees; otherwise the engine-level check is
  enough.
- Show the owner the exact commands: a dry run on their folder first, then
  `--convert`, then (separately, after they have looked) `--convert
  --delete-originals`.
- Before pushing: `git fetch`, merge `origin/main` if it moved (another TF may
  be preparing the v1.6.6 release in parallel). Push with the owner's
  approval in chat.
- The Permission / Sandbox field is counted from
  `~/Library/Logs/claude-permission-requests.log` since the task started.

## Progress

- Last completed step: implementation, tests, documentation; archived.
- Current partial state: none.
- Exact next step: none (push awaits the owner's approval).

## Implementation Result

**Status:** Completed

### Changes

- `tools/convert_solid_rar4.py` (new). Finds solid RAR4 `.cbr`/`.rar` with
  `rar_survey.survey_file()` / `iter_candidates()` (imported, so "solid RAR4"
  is exactly the survey's classification), then walks every RAR4 file header
  itself (names, flags, sizes, CRC-32s). Dry run by default; `--convert`;
  `--delete-originals`; `--extractor auto|7zz|unar`; `--legacy-encoding`
  (default `cp932`); `--skip-online-only`. Skip reasons: not RAR, RAR5, not
  solid, RAR4 header error, header-encrypted, multi-volume, no files,
  password-protected, target exists, online-only (with the flag).
  Per book: pair the RAR headers with the extractor's listing (count, order,
  directory flag, size, CRC-32, and the name wherever the header name can be
  decoded), extract to a temporary folder outside the book's folder, check
  every extracted file (regular file, size, CRC-32, nothing extra), write
  ZIP_STORED in archive order with the UTF-8 flag on every name (a
  `ZipInfo` subclass; zipfile sets it only for non-ASCII names), verify
  (entry count, names, STORED, UTF-8 flag, sizes and CRC-32s against the
  archive, `testzip()`), apply the original's permissions and mtime, and
  rename a hidden `.partial` file into place only if the target still does
  not exist. Failures are reported per book and the run continues; exit 1
  when a book failed or an original could not be trashed.
- `tests/tools/test_convert_solid_rar4.py` (new), 14 tests.
- `tools/convert_solid_rar4.md` (new): usage note.
- `docs/DECISIONS.md`: new entry "Solid RAR4 books are converted to ZIP, not
  decoded in the app". `docs/KNOWN_ISSUES.md` #39: workaround bullet.

Decisions beyond the TASK text (both made with the owner in chat or forced
by the extractors):

- **Legacy names need unar.** RAR4 names stored without `LHD_UNICODE`
  (Shift_JIS bytes from old Japanese Windows archivers) cannot be decoded by
  `7zz` on macOS: a generated `表紙.jpg` came out as `/.jpg` (the `0x5C`
  trail byte becomes a path separator; `-mcp=932` does not help). `unar`
  handles them. So 7zz stays preferred, but a book with any such name is
  extracted with unar (`-e cp932`) and its ZIP names are decoded from the
  header bytes with Python's `cp932` (the Microsoft table, as Windows wrote
  them). With only 7zz installed such a book fails with a message to install
  unar; the dry run marks it `[legacy names, cp932, needs unar]`.
- **`--delete-originals` after an earlier `--convert`** (owner's choice in
  chat). The TASK's sequence (dry run → `--convert` → `--convert
  --delete-originals`) would otherwise trash nothing, because step 3 skips
  every book whose target exists. With `--delete-originals`, an existing
  target is verified in this run instead: the original is extracted again
  and the existing ZIP checked with the same verification as a new one; it
  is never modified. On a match the original goes to the Trash; otherwise
  the book is reported as failed and the original kept. Without
  `--delete-originals`, an existing target is still a skip.
- Password-protected entries (`LHD_PASSWORD`) are a dry-run skip reason,
  since the tool never has a password; extractors also run with stdin closed
  so they cannot prompt.

### Verification

- Build: not applicable (no app change).
- Automated verification:
  - `/usr/bin/python3 tests/tools/test_convert_solid_rar4.py`: 14 tests, OK
    (7zz 26.03, unar/lsar 1.10.7, rar 7.23 installed). Fixtures: solid
    RAR4 with UTF-8 `LHD_UNICODE` names (Japanese, a sub-folder, a directory
    entry, `__MACOSX/._*` and `.DS_Store`), a WinRAR 3.x-style name (OEM
    cp932 + NUL + compressed Unicode, encoded per the technote), legacy
    Shift_JIS names with `0x5C` trail bytes, ASCII `.rar` → `.zip`,
    upper-case `.CBR` → `.CBZ`, a stored-CRC mismatch, non-solid RAR4, RAR5
    (`rar -s`), ZIP named `.cbr`, existing target, header-encrypted,
    multi-volume, password-protected. Checked: dry run leaves the tree
    byte-for-byte unchanged (mode/size/mtime of every path) and lists every
    reason; conversion with 7zz, with unar, and auto gives page bytes equal
    to the source images, STORED, UTF-8 flag, original mtime, no
    `.partial` left; the corrupt book fails and the run continues (exit 1);
    `verify_zip` catches a flipped data byte, a replaced entry and a missing
    entry; a tampered output (injected after writing) fails the book, leaves
    no target and is not trashed; `--delete-originals` (trash step replaced
    by a recorder) trashes exactly the converted books, keeps skipped and
    failed ones, keeps the original when trashing fails, and after an
    earlier `--convert` trashes only originals whose existing ZIP verifies
    (a tampered one is kept) without rewriting any existing ZIP;
    `--delete-originals` without `--convert` is a usage error; `--help`
    mentions online-only download and sync.
  - `/usr/bin/python3 tests/tools/test_rar_survey.py`: 10 tests, OK
    (rar_survey.py unchanged).
- Manual verification: a scratch run (dry run and `--convert`) on the
  generated fixtures plus `tests/fixtures/generated/*.cbr`; `unzip -t`
  passes on a converted `.cbz` with Japanese names.
- Not performed:
  - Real compressed solid RAR4 data: `rar` 7.23 cannot write RAR4, so every
    fixture is STORE data with the solid flags. Decoding a real solid stream
    is the extractor's job; the tool's per-entry size/CRC-32 checks guard
    it. The owner's dry run and first `--convert` are the first real test.
  - The real Trash step (`/usr/bin/trash`, Finder fallback) was not run:
    tests replace it, so the owner's Trash was not touched.
  - Opening a converted `.cbz` in `build/cooViewer.app`: the owner declined
    in chat; the output format (ZIP_STORED, UTF-8 flag) is that of the
    existing `test_utf8.zip` fixture.
  - Running on the owner's folders (out of scope).

### Remaining Issues

None.

### Follow-up Suggestions

- If a book fails with "names are not valid cp932" or shows wrong names, it
  was made in another code page; rerun that book with
  `--legacy-encoding CODEC`.

## Post-completion fixes (2026-10-04, owner's requests in chat)

Found when the owner ran the tool on their library (an external SSD):

- **Listing:** RAR5, non-solid RAR4 and non-RAR files are counted in the
  summary but no longer listed per file (`--list-all` lists them), so a dry
  run over a whole library shows the books that matter (commit `c719a60`).
- **Dry run stalled on every solid book.** The dry run walked every RAR4 file
  header, i.e. a few hundred to ~2300 reads spread over each book (0.1–1.6 s
  cold per book, 5–11 s for some), where `rar_survey.py` reads only the start.
  A timing script (kept out of the repository) showed the walk itself was
  correct (blocks = files + 1–2). The dry run now reads only what the survey
  reads; the full walk runs only with `--convert`. Passwords on entries after
  the first and legacy non-Unicode names are therefore reported by the
  `--convert` run, not the dry run. The walk also reads unbuffered and stops
  after 1,000,000 file headers.
- **Homebrew's 7zz cannot decompress RAR.** Its build has no RAR codecs
  (`7zz i` lists no Rar1–Rar5), so every compressed entry failed with
  "Unsupported Method"; the STORE-only fixtures had hidden this. The tool now
  checks `7zz i` for the `Rar3` codec and otherwise uses unar, saying so on
  stderr. Each book prints `converting: PATH ...` before it starts.
- Result: the owner converted all of their solid RAR4 books with unar.
