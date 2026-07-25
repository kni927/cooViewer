/*
 * test_zip_password — COZipArchive-level check for password-protected ZIP.
 *
 * Opens encrypted fixtures through COArchive (which dispatches .zip to
 * COZipArchive) and verifies the reader's password behaviour:
 *   - no password:   -crypted = YES, -cryptoStatus = NeedsPassword,
 *                    no entries, a distinguishable -lastError
 *   - wrong password: -cryptoStatus = WrongPassword, distinguishable
 *                    -lastError, no readable entries, no crash/garbage
 *   - correct password: -cryptoStatus = OK, the entry appears and its
 *                    -data matches the known payload
 * and that a non-encrypted archive is read exactly as before
 *   - -crypted = NO, -cryptoStatus = None, entry present, -data matches.
 *
 * Fixtures (created by run_password_test.sh in <out-dir>):
 *   enc_aes.zip, enc_trad.zip  — one entry "secret.txt", AES-256 /
 *                                traditional PKWARE, password below
 *   plain.zip                  — same entry, not encrypted
 *
 * usage: test_zip_password <out-dir>
 * exit code: number of failed checks (0 = all pass)
 */

#import <Foundation/Foundation.h>
#import "COArchive.h"
#import "COZipArchive.h"

static const char *kTestPassword = "cooViewer-secret-42";
static const char *kTestWrongPw  = "not-the-password";
#define PAYLOAD_LEN 512

static NSData *expectedPayload(void) {
	unsigned char b[PAYLOAD_LEN];
	for (int i = 0; i < PAYLOAD_LEN; i++) b[i] = (unsigned char)((i * 37 + 11) & 0xff);
	return [NSData dataWithBytes:b length:PAYLOAD_LEN];
}

static int g_failures = 0;
static void ok(const char *m)   { fprintf(stdout, "ok: %s\n", m); }
static void bad(const char *m)  { fprintf(stderr, "FAIL: %s\n", m); g_failures++; }
static void check(int cond, const char *m) { if (cond) ok(m); else bad(m); }

/* Open <dir>/<name> and return the COZipArchive (or nil). */
static COZipArchive *openZip(NSString *dir, NSString *name) {
	NSString *path = [dir stringByAppendingPathComponent:name];
	COArchive *a = [[COArchive alloc] initWithPath:path];
	if (![a isKindOfClass:[COZipArchive class]]) {
		fprintf(stderr, "  %s did not dispatch to COZipArchive\n", [name UTF8String]);
		[a release];
		return nil;
	}
	return (COZipArchive *)a;
}

static void testEncrypted(NSString *dir, NSString *name, const char *label) {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSData *want = expectedPayload();
	char msg[160];

	// 1. no password
	COZipArchive *z = openZip(dir, name);
	if (!z) { bad(label); [pool drain]; return; }
	snprintf(msg, sizeof msg, "%s: crypted before password", label);
	check([z crypted], msg);
	snprintf(msg, sizeof msg, "%s: status NeedsPassword before password", label);
	check([z cryptoStatus] == COArchiveCryptoNeedsPassword, msg);
	snprintf(msg, sizeof msg, "%s: no entries before password", label);
	check([z itemCount] == 0, msg);
	snprintf(msg, sizeof msg, "%s: lastError set before password", label);
	check([z lastError] != nil, msg);

	// 2. wrong password
	[z setPassword:[NSString stringWithUTF8String:kTestWrongPw]];
	snprintf(msg, sizeof msg, "%s: status WrongPassword after wrong pw", label);
	check([z cryptoStatus] == COArchiveCryptoWrongPassword, msg);
	snprintf(msg, sizeof msg, "%s: no readable entries after wrong pw", label);
	check([z itemCount] == 0, msg);
	snprintf(msg, sizeof msg, "%s: lastError distinguishes wrong pw", label);
	check([z lastError] != nil, msg);

	// 3. correct password
	[z setPassword:[NSString stringWithUTF8String:kTestPassword]];
	snprintf(msg, sizeof msg, "%s: status OK after correct pw", label);
	check([z cryptoStatus] == COArchiveCryptoOK, msg);
	snprintf(msg, sizeof msg, "%s: one entry after correct pw", label);
	check([z itemCount] == 1, msg);
	if ([z itemCount] == 1) {
		COArchiveEntry *e = [[z contents] objectAtIndex:0];
		snprintf(msg, sizeof msg, "%s: entry name is secret.txt", label);
		check([[e path] isEqualToString:@"secret.txt"], msg);
		snprintf(msg, sizeof msg, "%s: decrypted content matches", label);
		check([[e data] isEqualToData:want], msg);
	}
	snprintf(msg, sizeof msg, "%s: lastError nil after correct pw", label);
	check([z lastError] == nil, msg);

	[z release];
	[pool drain];
}

static void testPlain(NSString *dir, NSString *name) {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSData *want = expectedPayload();
	COZipArchive *z = openZip(dir, name);
	if (!z) { bad("plain: open"); [pool drain]; return; }
	check(![z crypted], "plain: not crypted");
	check([z cryptoStatus] == COArchiveCryptoNone, "plain: status None");
	check([z itemCount] == 1, "plain: one entry");
	if ([z itemCount] == 1) {
		COArchiveEntry *e = [[z contents] objectAtIndex:0];
		check([[e path] isEqualToString:@"secret.txt"], "plain: entry name");
		check([[e data] isEqualToData:want], "plain: content matches");
	}
	check([z lastError] == nil, "plain: lastError nil");
	[z release];
	[pool drain];
}

int main(int argc, char **argv) {
	if (argc < 2) { fprintf(stderr, "usage: %s <out-dir>\n", argv[0]); return 2; }
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString *dir = [NSString stringWithUTF8String:argv[1]];

	testEncrypted(dir, @"enc_aes.zip",  "AES-256");
	testEncrypted(dir, @"enc_trad.zip", "TRAD_PKWARE");
	testPlain(dir, @"plain.zip");

	fprintf(stdout, "\n%s (%d failure%s)\n", g_failures ? "FAILED" : "PASSED",
	        g_failures, g_failures == 1 ? "" : "s");
	[pool drain];
	return g_failures;
}
