//  Copyright © 2021 Audulus LLC. All rights reserved.

#include "testUtils.h"
#include <vector>

void writeCGImage(CGImageRef image, CFURLRef url) {
    auto dest = CGImageDestinationCreateWithURL(url, kUTTypePNG, 1, nil);
    CGImageDestinationAddImage(dest, image, nil);
    assert(CGImageDestinationFinalize(dest));
}

CGImageRef getImage(UInt8* data, int w, int h) {

    auto provider = CGDataProviderCreateWithData(nullptr,
                                                 data,
                                                 4*w*h,
                                                 nullptr);

    return CGImageCreate(w, h,
                         8, 32,
                         w*4,
                         CGColorSpaceCreateDeviceRGB(),
                         kCGImageAlphaNoneSkipLast,
                         provider,
                         nil,
                         true,
                         kCGRenderingIntentDefault);

}

CGImageRef getTextureImage(id<MTLTexture> texture) {

    int w = texture.width;
    int h = texture.height;

    std::vector<UInt8> imageBytes(4*w*h, 0);

    switch(texture.pixelFormat) {
        case MTLPixelFormatRGBA8Unorm:
            [texture getBytes:imageBytes.data() bytesPerRow:w * 4 fromRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0];
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

    return getImage(imageBytes.data(), w, h);
}

void showTexture(id<MTLTexture> texture, NSString* name) {

    auto tmpURL = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:name];
    NSLog(@"saving to %@", tmpURL);
    writeCGImage(getTextureImage(texture), (__bridge CFURLRef)tmpURL);
    system([NSString stringWithFormat:@"open %@", tmpURL.path].UTF8String);

}

@interface checkTextureBundleFinder : NSObject

@end

@implementation checkTextureBundleFinder

@end

bool checkTexture(id<MTLTexture> texture, NSString* name) {

    auto tmpURL = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:name];
    NSLog(@"saving to %@", tmpURL);
    writeCGImage(getTextureImage(texture), (__bridge CFURLRef)tmpURL);

    // Get URL for baseline.
    NSString* path = @"Contents/Resources/vger_vgerTests.bundle/Contents/Resources/images/";
    path = [path stringByAppendingString:name];
    NSBundle* bundle = [NSBundle bundleForClass:checkTextureBundleFinder.class];
    auto baselineURL = [bundle.bundleURL URLByAppendingPathComponent:path];

    bool equal = [NSFileManager.defaultManager contentsEqualAtPath:baselineURL.path andPath:tmpURL.path];

    if(!equal) {
        system([NSString stringWithFormat:@"open %@", tmpURL.path].UTF8String);
    }

    return equal;
}
