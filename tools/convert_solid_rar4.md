# convert_solid_rar4.py

Converts solid RAR4 books, which cooViewer refuses (`docs/KNOWN_ISSUES.md`
#39), to ZIP with identical page bytes: `book.cbr` → `book.cbz`,
`book.rar` → `book.zip`, in the same folder. "Solid RAR4" means exactly what
`tools/rar_survey.py` reports; RAR5, non-solid RAR4, header-encrypted,
password-protected and multi-volume archives are skipped, and so is any book
whose target already exists.

## Requirements

- `/usr/bin/python3` (macOS Command Line Tools); standard library only.
- An extractor: `7zz` (`brew install sevenzip`, preferred) or `unar`
  (`brew install unar`, which also provides `lsar`). Only `--convert` needs
  one.
- Books whose RAR4 names are stored without Unicode (Shift_JIS bytes from
  old Japanese Windows archivers) need `unar`: 7zz on macOS cannot decode
  them. Their names are decoded from the header bytes with
  `--legacy-encoding` (default `cp932`). The dry run marks these books.

## Use

Run the three steps separately and look at the result in between.

```sh
tools/convert_solid_rar4.py FOLDER                                  # 1. dry run
tools/convert_solid_rar4.py --convert FOLDER                        # 2. convert
tools/convert_solid_rar4.py --convert --delete-originals FOLDER     # 3. trash originals
```

1. The dry run reads only the RAR headers and writes nothing. It lists
   `would convert: SOURCE -> TARGET` and `skip (REASON): SOURCE` lines and a
   summary. Only solid RAR4 books are listed; RAR5, non-solid RAR4 and
   non-RAR files are only counted in the summary unless `--list-all` is
   given. All three steps list the same way.
2. `--convert` writes the ZIPs and keeps the originals. Each book is
   extracted into a temporary folder (removed afterwards), written with
   ZIP_STORED and the UTF-8 name flag in archive order, verified (entry
   count, names, sizes and CRC-32s against the RAR headers and the
   extractor's listing, plus `zipfile.testzip()`), given the original's
   modification time, and renamed into place. A failure leaves no partial
   target. Directory entries and macOS metadata (`__MACOSX/`, `.DS_Store`)
   are left out and reported.
3. `--convert --delete-originals` moves each original to the Trash
   (`/usr/bin/trash`, else Finder) once its ZIP is verified in this run.
   Books still without a ZIP are converted first. A book whose `.cbz`/`.zip`
   already exists (from step 2) is extracted again and the existing ZIP is
   checked against it entry by entry (`verified existing:` lines); the ZIP is
   never modified, and if it does not match, the book is reported as failed
   and its original is kept. Skipped and failed books are never trashed.

A failed book is reported as `FAILED: SOURCE: REASON` and the run continues;
the exit status is 1 when any book failed or an original could not be
trashed.

Reading a Dropbox "online-only" file downloads it, even in the dry run;
`--skip-online-only` leaves such files alone. The new files sync like any
other file.

## Tests

```sh
/usr/bin/python3 tests/tools/test_convert_solid_rar4.py
```

Fixtures are generated in a temporary folder. The RAR4 ones are hand-written
STORE archives with the solid flags set, as `rar` 7.x cannot write RAR4, so
the tests do not exercise a real RAR4 compressor's solid stream; that
decoding is the extractor's.
