//
//  main.m
//  «PROJECTNAME»
//
//  Created by «FULLUSERNAME» on «DATE».
//  Copyright «ORGANIZATIONNAME» «YEAR». All rights reserved.
//

#import <Cocoa/Cocoa.h>
#include <locale.h>

int main(int argc, char *argv[])
{
    // GUI apps start in the C locale. libarchive's zip reader corrupts
    // CP932 raw filenames under the C locale (backslash normalization
    // eats 0x5C trail bytes), so a UTF-8 locale must be active before
    // any COArchive/libarchive use. See docs/spike-libarchive-20260711.md.
    // The libzip path (COZipArchive, zip/cbz) is locale-independent
    // (verified under LC_ALL=C in tests/engine), but libarchive still
    // reads zips as the corrupt-central-directory fallback and all
    // non-zip formats, so this must stay.
    setlocale(LC_ALL, "en_US.UTF-8");

    return NSApplicationMain(argc,  (const char **) argv);
}
