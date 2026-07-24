/*
 * test_zip_encryption — standalone check that the vendored libzip can
 * decrypt password-protected ZIP archives (WinZip AES-256 and traditional
 * PKWARE ZipCrypto). This exercises the crypto backend enabled in
 * vendor/build-libs.sh (CommonCrypto); it does NOT touch application code.
 *
 * For each encryption method the test:
 *   1. creates a small archive containing a known entry, encrypted with a
 *      known password, using the rebuilt libzip;
 *   2. reopens it, supplies the correct password, reads the entry back and
 *      compares it byte-for-byte to the expected content;
 *   3. reopens it, supplies a WRONG password, and confirms the read fails
 *      cleanly (open or read returns an error) instead of yielding garbage.
 *
 * The runner (run_encryption_test.sh) additionally creates a traditional
 * ZipCrypto archive with the system `zip -e` tool and passes its path as an
 * optional third argument, so decryption is also verified against a fixture
 * produced by an independent tool.
 *
 * usage: test_zip_encryption <out-dir> [ext-trad-zip] [ext-password]
 * exit code: number of failed checks (0 = all pass)
 */

#include <zip.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char  *kEntry    = "secret.txt";
static const char  *kPassword = "cooViewer-secret-42";
static const char  *kWrongPw  = "not-the-password";

/* Known payload: large enough to span multiple AES blocks and force a
 * non-trivial deflate/stored stream. */
#define PAYLOAD_LEN 512
static unsigned char g_payload[PAYLOAD_LEN];

static void fill_payload(void) {
    for (int i = 0; i < PAYLOAD_LEN; i++)
        g_payload[i] = (unsigned char)((i * 37 + 11) & 0xff);
}

static int fail(const char *msg) { fprintf(stderr, "FAIL: %s\n", msg); return 1; }
static void pass(const char *msg) { fprintf(stdout, "ok: %s\n", msg); }

/* Create <dir>/<name> with a single entry encrypted using `method`. */
static int make_encrypted(const char *path, zip_uint16_t method) {
    int err = 0;
    zip_t *za = zip_open(path, ZIP_CREATE | ZIP_TRUNCATE, &err);
    if (!za) { fprintf(stderr, "zip_open(create) failed: %d\n", err); return -1; }

    zip_source_t *src = zip_source_buffer(za, g_payload, PAYLOAD_LEN, 0);
    if (!src) { fprintf(stderr, "zip_source_buffer failed\n"); zip_discard(za); return -1; }

    zip_int64_t idx = zip_file_add(za, kEntry, src, ZIP_FL_ENC_UTF_8);
    if (idx < 0) { fprintf(stderr, "zip_file_add failed: %s\n", zip_strerror(za)); zip_source_free(src); zip_discard(za); return -1; }

    if (zip_file_set_encryption(za, (zip_uint64_t)idx, method, kPassword) != 0) {
        fprintf(stderr, "zip_file_set_encryption failed: %s\n", zip_strerror(za));
        zip_discard(za);
        return -1;
    }
    if (zip_close(za) != 0) { fprintf(stderr, "zip_close failed: %s\n", zip_strerror(za)); return -1; }
    return 0;
}

/* Read <path>!<kEntry> with `password`. Returns:
 *   0  read succeeded and payload matched expected
 *   1  read succeeded but payload did NOT match (garbage / silent wrong)
 *  -1  open or read reported an error (the expected outcome for a wrong pw)
 */
static int read_and_check(const char *path, const char *password) {
    int err = 0;
    zip_t *za = zip_open(path, ZIP_RDONLY, &err);
    if (!za) { fprintf(stderr, "  zip_open(read) failed: %d\n", err); return -1; }
    zip_set_default_password(za, password);

    zip_file_t *f = zip_fopen(za, kEntry, 0);
    if (!f) { zip_close(za); return -1; }   /* traditional: wrong pw rejected at open */

    unsigned char buf[PAYLOAD_LEN + 16];
    zip_int64_t n = zip_fread(f, buf, sizeof(buf));
    zip_fclose(f);
    zip_close(za);

    if (n < 0) return -1;                    /* AES: wrong pw fails HMAC at read */
    if (n != PAYLOAD_LEN) return 1;
    if (memcmp(buf, g_payload, PAYLOAD_LEN) != 0) return 1;
    return 0;
}

/* Read an externally-created archive whose entry name may differ. */
static int read_external(const char *path, const char *entry, const char *password,
                         const unsigned char *expect, size_t expect_len) {
    int err = 0;
    zip_t *za = zip_open(path, ZIP_RDONLY, &err);
    if (!za) { fprintf(stderr, "  zip_open(read ext) failed: %d\n", err); return -1; }
    zip_set_default_password(za, password);
    zip_file_t *f = zip_fopen(za, entry, 0);
    if (!f) { zip_close(za); return -1; }
    unsigned char buf[4096];
    zip_int64_t n = zip_fread(f, buf, sizeof(buf));
    zip_fclose(f);
    zip_close(za);
    if (n < 0) return -1;
    if ((size_t)n != expect_len) return 1;
    if (memcmp(buf, expect, expect_len) != 0) return 1;
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s <out-dir> [ext-trad-zip] [ext-password]\n", argv[0]); return 2; }
    const char *out = argv[1];
    fill_payload();

    int failures = 0;
    char path[4096];

    struct { const char *label; zip_uint16_t method; } cases[] = {
        { "AES-256",  ZIP_EM_AES_256 },
        { "TRAD_PKWARE", ZIP_EM_TRAD_PKWARE },
    };

    for (int i = 0; i < 2; i++) {
        snprintf(path, sizeof(path), "%s/enc_%s.zip", out,
                 cases[i].method == ZIP_EM_AES_256 ? "aes" : "trad");
        if (make_encrypted(path, cases[i].method) != 0) {
            failures += fail(cases[i].label);
            failures += 1;   /* count creation failure */
            continue;
        }

        int r = read_and_check(path, kPassword);
        if (r == 0) pass(cases[i].label);
        else if (r == 1) failures += fail("correct password produced WRONG content (garbage)");
        else            failures += fail("correct password could not be read");

        int w = read_and_check(path, kWrongPw);
        if (w == -1) { char m[128]; snprintf(m, sizeof m, "%s wrong-password rejected", cases[i].label); pass(m); }
        else if (w == 1) failures += fail("wrong password produced garbage instead of an error");
        else            failures += fail("wrong password was accepted");
    }

    /* Optional: externally-created traditional ZipCrypto fixture. */
    if (argc >= 4) {
        const char *ext = argv[2], *extpw = argv[3];
        /* The runner stores the same payload as g_payload under kEntry. */
        int r = read_external(ext, kEntry, extpw, g_payload, PAYLOAD_LEN);
        if (r == 0) pass("external `zip -e` traditional fixture decrypted");
        else if (r == 1) failures += fail("external fixture correct pw -> wrong content");
        else            failures += fail("external fixture correct pw -> read error");

        int w = read_external(ext, kEntry, kWrongPw, g_payload, PAYLOAD_LEN);
        if (w == -1) pass("external fixture wrong-password rejected");
        else if (w == 1) failures += fail("external fixture wrong pw -> garbage");
        else            failures += fail("external fixture wrong pw accepted");
    }

    fprintf(stdout, "\n%s (%d failure%s)\n", failures ? "FAILED" : "PASSED",
            failures, failures == 1 ? "" : "s");
    return failures;
}
