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

    std::vector<UInt8> imageBytes(4*w*h);
    [texture getBytes:imageBytes.data() bytesPerRow:w * 4 fromRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0];

    return getImage(imageBytes.data(), w, h);
}
