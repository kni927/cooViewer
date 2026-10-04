// gen_pages.m — synthetic greyscale JPEG "scan" pages for tools/cbr_bench.
//
// usage: gen_pages <out-dir> <count> <width> <height> <quality 0..1> <seed>
//
// Each page is noise over a few gradients inside white margins, so like a
// real scan it is nearly incompressible and RAR stores it at close to its
// own size, but with -m3 compression rather than as a stored (-m0) entry. Deterministic
// for a given seed. Files are named p0001.jpg, p0002.jpg, ...

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    if (argc != 7) {
        fprintf(stderr, "usage: %s <out-dir> <count> <width> <height> <quality> <seed>\n", argv[0]);
        return 64;
    }
    @autoreleasepool {
        NSString *outDir = [NSString stringWithUTF8String:argv[1]];
        int count = atoi(argv[2]), width = atoi(argv[3]), height = atoi(argv[4]);
        double quality = atof(argv[5]);
        unsigned int seed = (unsigned int)strtoul(argv[6], NULL, 10);
        [[NSFileManager defaultManager] createDirectoryAtPath:outDir
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        srandom(seed);
        uint8_t *pixels = malloc((size_t)width * height);
        CGColorSpaceRef grey = CGColorSpaceCreateDeviceGray();
        for (int n = 1; n <= count; n++) {
            int band = 8 + (int)(random() % 24);
            for (int y = 0; y < height; y++) {
                for (int x = 0; x < width; x++) {
                    int base = 128 + (int)(96.0 * ((x / band + y / band) % 2 ? 1 : -1) * ((double)y / height));
                    int v = base + (int)(random() % 129) - 64;
                    // white margins, as on a scanned page: the only part RAR
                    // can compress, so entries use -m3 rather than -m0
                    if (x < width / 8 || x >= width - width / 8 || y < height / 10 || y >= height - height / 10)
                        v = 250;
                    pixels[(size_t)y * width + x] = (uint8_t)(v < 0 ? 0 : v > 255 ? 255 : v);
                }
            }
            CGContextRef ctx = CGBitmapContextCreate(pixels, width, height, 8, width, grey, (CGBitmapInfo)kCGImageAlphaNone);
            CGImageRef image = CGBitmapContextCreateImage(ctx);
            NSString *path = [outDir stringByAppendingPathComponent:
                              [NSString stringWithFormat:@"p%04d.jpg", n]];
            CGImageDestinationRef dest = CGImageDestinationCreateWithURL(
                (CFURLRef)[NSURL fileURLWithPath:path], CFSTR("public.jpeg"), 1, NULL);
            NSDictionary *props = @{ (id)kCGImageDestinationLossyCompressionQuality: @(quality) };
            CGImageDestinationAddImage(dest, image, (CFDictionaryRef)props);
            if (!CGImageDestinationFinalize(dest)) {
                fprintf(stderr, "cannot write %s\n", [path UTF8String]);
                return 1;
            }
            CFRelease(dest);
            CGImageRelease(image);
            CGContextRelease(ctx);
        }
        CGColorSpaceRelease(grey);
        free(pixels);
    }
    return 0;
}
