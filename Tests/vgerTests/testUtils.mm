//  Copyright © 2021 Audulus LLC. All rights reserved.

#include "testUtils.h"
#include <vector>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

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

CGImageRef createImage(UInt8* data, int w, int h) {

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

    int w = texture.width;
    int h = texture.height;

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
    system([NSString stringWithFormat:@"open %@", tmpURL.path].UTF8String);
#endif
    CGImageRelease(image);

}

@interface checkTextureBundleFinder : NSObject

@end

@implementation checkTextureBundleFinder

@end

bool checkTexture(id<MTLTexture> texture, NSString* name) {

    auto tmpURL = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:name];
    NSLog(@"saving to %@", tmpURL);
    CGImageRef image = createImage(texture);
    writeCGImage(image, (__bridge CFURLRef)tmpURL);
    CGImageRelease(image);

    // Get URL for baseline.
    NSString* path = @"Contents/Resources/vger_vgerTests.bundle/Contents/Resources/images/";
    path = [path stringByAppendingString:name];
    NSBundle* bundle = [NSBundle bundleForClass:checkTextureBundleFinder.class];
    auto baselineURL = [bundle.bundleURL URLByAppendingPathComponent:path];

    bool equal = [NSFileManager.defaultManager contentsEqualAtPath:baselineURL.path andPath:tmpURL.path];

    if(!equal) {
#if TARGET_OS_OSX
        system([NSString stringWithFormat:@"open %@", tmpURL.path].UTF8String);
#endif
    }

    return equal;
}
