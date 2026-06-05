//  Copyright © 2021 Audulus LLC. All rights reserved.

#include "testUtils.h"
#include <algorithm>
#include <cstdlib>
#include <vector>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static constexpr int kMaxPixelDifference = 2;

void writeCGImage(CGImageRef image, CFURLRef url) {
    auto dest = CGImageDestinationCreateWithURL(url, (CFStringRef) UTTypePNG.identifier, 1, nil);
    CGImageDestinationAddImage(dest, image, nil);
    assert(CGImageDestinationFinalize(dest));
    CFRelease(dest);
}

void releaseImageData(void * __nullable info,
                      const void *  data, size_t size) {
    free((void*)data);
}

CGImageRef createImage(UInt8* data, NSUInteger w, NSUInteger h) {

    UInt8* newData = (UInt8*) malloc(4*w*h);
    memcpy(newData, data, 4*w*h);

    auto provider = CGDataProviderCreateWithData(nullptr,
                                                 newData,
                                                 4*w*h,
                                                 releaseImageData);

    auto colorSpace = CGColorSpaceCreateDeviceRGB();

    auto image = CGImageCreate(w, h,
                         8, 32,
                         w*4,
                         colorSpace,
                         kCGImageAlphaNoneSkipLast,
                         provider,
                         nil,
                         true,
                         kCGRenderingIntentDefault);

    CGColorSpaceRelease(colorSpace);
    return image;

}

CGImageRef createImage(id<MTLTexture> texture) {

    auto w = texture.width;
    auto h = texture.height;

    std::vector<UInt8> imageBytes(4*w*h, 0);

    switch(texture.pixelFormat) {
        case MTLPixelFormatRGBA8Unorm:
            [texture getBytes:imageBytes.data() bytesPerRow:w * 4 fromRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0];
            break;
        case MTLPixelFormatBGRA8Unorm:
            [texture getBytes:imageBytes.data() bytesPerRow:w * 4 fromRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0];
            for(auto i=0;i<imageBytes.size()/4;++i) {
                std::swap(imageBytes[4*i], imageBytes[4*i+2]);
            }
            break;
        case MTLPixelFormatA8Unorm: {
            std::vector<UInt8> tmpBytes(w*h);
            [texture getBytes:tmpBytes.data() bytesPerRow:w fromRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0];
            for(auto i=0;i<tmpBytes.size();++i) {
                imageBytes[4*i] = tmpBytes[i];
            }
        }
            break;

        default:
            assert(false && "unsupported pixel format");
    }

    return createImage(imageBytes.data(), w, h);
}

void showTexture(id<MTLTexture> texture, NSString* name) {

    auto tmpURL = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:name];
    NSLog(@"saving to %@", tmpURL);
    CGImageRef image = createImage(texture);
    writeCGImage(image, (__bridge CFURLRef)tmpURL);
#if TARGET_OS_OSX
    // system([NSString stringWithFormat:@"open %@", tmpURL.path].UTF8String);
    auto task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/open";
    task.arguments = @[tmpURL.path];
    [task launch];
#endif
    CGImageRelease(image);

}

@interface checkTextureBundleFinder : NSObject

@end

@implementation checkTextureBundleFinder

@end

static CGImageRef createImage(NSURL* url) {
    auto source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, nil);
    if(!source) {
        return nil;
    }

    auto image = CGImageSourceCreateImageAtIndex(source, 0, nil);
    CFRelease(source);
    return image;
}

static bool getImagePixels(CGImageRef image, std::vector<UInt8>& pixels) {
    if(!image) {
        return false;
    }

    auto w = CGImageGetWidth(image);
    auto h = CGImageGetHeight(image);
    pixels.assign(4*w*h, 0);

    auto colorSpace = CGColorSpaceCreateDeviceRGB();
    auto bitmapInfo = static_cast<CGBitmapInfo>(kCGBitmapByteOrder32Big) |
                      static_cast<CGBitmapInfo>(kCGImageAlphaPremultipliedLast);
    auto context = CGBitmapContextCreate(pixels.data(),
                                         w,
                                         h,
                                         8,
                                         4*w,
                                         colorSpace,
                                         bitmapInfo);
    CGColorSpaceRelease(colorSpace);

    if(!context) {
        return false;
    }

    CGContextDrawImage(context, CGRectMake(0, 0, w, h), image);
    CGContextRelease(context);
    return true;
}

bool checkTexture(id<MTLTexture> texture, NSString* name) {

    auto tmpURL = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:name];
    NSLog(@"saving to %@", tmpURL);
    CGImageRef image = createImage(texture);
    writeCGImage(image, (__bridge CFURLRef)tmpURL);

    // Get URL for baseline.
    NSString* path = @"Contents/Resources/vger_vgerTests.bundle/Contents/Resources/images/";
    path = [path stringByAppendingString:name];
    NSBundle* bundle = [NSBundle bundleForClass:checkTextureBundleFinder.class];
    auto baselineURL = [bundle.bundleURL URLByAppendingPathComponent:path];
    NSLog(@"checking against baseline %@", baselineURL);

    CGImageRef baselineImage = createImage(baselineURL);
    bool equal = false;

    if(!baselineImage) {
        NSLog(@"missing or unreadable baseline image %@", baselineURL);
    } else if(CGImageGetWidth(image) != CGImageGetWidth(baselineImage) ||
              CGImageGetHeight(image) != CGImageGetHeight(baselineImage)) {
        NSLog(@"image size mismatch: got %zux%zu, expected %zux%zu",
              CGImageGetWidth(image),
              CGImageGetHeight(image),
              CGImageGetWidth(baselineImage),
              CGImageGetHeight(baselineImage));
    } else {
        std::vector<UInt8> actualPixels;
        std::vector<UInt8> baselinePixels;

        if(getImagePixels(image, actualPixels) && getImagePixels(baselineImage, baselinePixels)) {
            int maxDifference = 0;
            size_t maxDifferenceIndex = 0;

            for(size_t i=0;i<actualPixels.size();++i) {
                int difference = std::abs(int(actualPixels[i]) - int(baselinePixels[i]));
                if(difference > maxDifference) {
                    maxDifference = difference;
                    maxDifferenceIndex = i;
                }
            }

            equal = maxDifference <= kMaxPixelDifference;
            if(!equal) {
                auto pixelIndex = maxDifferenceIndex / 4;
                NSLog(@"maximum pixel difference %d exceeds epsilon %d at (%zu, %zu), channel %zu",
                      maxDifference,
                      kMaxPixelDifference,
                      pixelIndex % CGImageGetWidth(image),
                      pixelIndex / CGImageGetWidth(image),
                      maxDifferenceIndex % 4);
            }
        } else {
            NSLog(@"could not decode images for comparison");
        }
    }

    if(!equal) {
#if TARGET_OS_OSX
        system([NSString stringWithFormat:@"open %@", tmpURL.path].UTF8String);
#endif
    }

    if(baselineImage) {
        CGImageRelease(baselineImage);
    }
    CGImageRelease(image);

    return equal;
}
