# TASK: Record the decision to decline encrypted RAR support

## Scope

Documentation only. No code changes.

## Steps

1. Add an entry to `docs/DECISIONS.md` recording that encrypted RAR support
   is declined, with:
   - the technical finding: libarchive's RAR reader has no decryption
     implementation (it never consults `passphrase`), so this is not a
     build-flag issue
   - the options considered and why each was rejected: unrar (non-OSI
     licence terms), XADMaster subset (decryption inseparable from the
     CSHandle machinery, and contrary to the 2026-07-14 decision), libunarr
     (already spiked, no RAR5), 7-Zip codec (inherits unrar terms)
   - the current behaviour: both data-encrypted and header-encrypted RAR
     fail closed with the default icon and no prompt
   - that encrypted ZIP restores the documented feature in its most common
     form
   - reference to `docs/tasks/2026-07-25-11-investigate-encrypted-rar.md`
2. Confirm `docs/KNOWN_ISSUES.md` does not carry a conflicting entry
   implying encrypted RAR is pending work. Reconcile if it does.
3. Commit.

## Notes

- The purpose is to stop a future session from re-investigating a settled
  question. State it as a decision, not as an open item.
- Do not modify `docs/licenses/License_xadmaster.txt`; the investigation
  confirmed it is a live attribution for `CORarHeaderIndex.h/.m`, not stale.
## Implementation Result

**Status:** Completed

### Changes

Documentation only; no code changes.

- `docs/DECISIONS.md`: the entry **"Encrypted RAR support: declined
  (2026-07-25)"** was already present in the working tree as an uncommitted
  change when this task started (not in HEAD) — it was not re-created.
  Verified it against the required points and it already covered: the
  technical finding (libarchive's RAR readers contain no decryption and
  never consult `passphrase`, versus 17 mentions in the ZIP reader, so this
  is not a build-flag issue); each rejected option (unrar — non-OSI licence
  terms; an XADMaster subset — decryption inseparable from the
  `CSHandle`/`XADArchiveParser`/`XADPath` machinery and contrary to the
  2026-07-14 decision; libunarr — already spiked, no RAR5; 7-Zip's codec —
  inherits unrar's terms); that encrypted ZIP already restores the
  documented feature in its most common form; and the reference to
  `docs/tasks/2026-07-25-11-investigate-encrypted-rar.md`. It is phrased as
  a settled decision, not an open item.
- **Amended** that entry with the one required element it lacked: an
  explicit statement that **both variants** — data-only (`rar a -p`) and
  header-encrypted (`rar a -hp`) — fail closed with the default icon and no
  prompt, plus an "expected, not a bug" note that the two reach that state
  by different internal routes (data-only: `crypted = YES` /
  `COArchiveCryptoUnsupported`; header-encrypted: **`crypted = NO`**,
  because `CORarHeaderIndex` declines and the libarchive fallback fails
  before any entry exists). Recorded so a future session does not read that
  asymmetry as a defect to fix.

### Verification

- Build: Not performed (documentation only).
- Automated verification: checked the finished entry for every required
  element (`passphrase`, unrar, XADMaster, libunarr, 7-Zip, default icon,
  header encryption, AES-256, task-archive reference) — all present.
  Confirmed no source, test, vendor, or resource files were touched.
- Manual verification (step 2): scanned `docs/KNOWN_ISSUES.md` for anything
  implying encrypted RAR is pending work — **no conflicting entry exists**
  (no RAR/encryption headings, no password-RAR claims; the only "solid RAR"
  mention is an observation inside issue #15 about the Finder open
  investigation, unrelated to encryption). **Nothing to reconcile.**
- `docs/licenses/License_xadmaster.txt` left untouched, as instructed.

### Remaining Issues

None.

### Follow-up Suggestions

None. The question is settled; the decision entry exists to stop it being
re-opened without a new decision from the project owner.
