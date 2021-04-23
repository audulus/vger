// Copyright © 2021 Audulus LLC. All rights reserved.

#import "vgerGlyphCache.h"
#import "vgerTextureManager.h"
#include <vector>

@interface vgerGlyphCache() {
    vgerTextureManager* mgr;
    std::vector< std::vector<GlyphInfo> > glyphs;
    CTFontRef ctFont;
}
@end

@implementation vgerGlyphCache

- (instancetype) initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        mgr = [[vgerTextureManager alloc] initWithDevice:device pixelFormat:MTLPixelFormatA8Unorm];
        ctFont = CTFontCreateWithName((__bridge CFStringRef)@"Avenir-light", /*fontPointSize*/12, NULL);
    }
    return self;
}

- (GlyphInfo) getGlyph:(CGGlyph)glyph size:(float) size {

    if(glyph >= glyphs.size()) {
        glyphs.resize(glyph+1);
    }

    auto& v = glyphs[glyph];

    for(auto& info : v) {
        if(info.size == size) {
            return info;
        }
    }

    CGFloat fontAscent = CTFontGetAscent(ctFont);
    CGFloat fontDescent = CTFontGetDescent(ctFont);

    // Render the glyph with CoreText.
    CGRect boundingRect;
    CTFontGetBoundingRectsForGlyphs(ctFont, kCTFontOrientationHorizontal, &glyph, &boundingRect, 1);

    CGAffineTransform glyphTransform = CGAffineTransformMake(1, 0, 0, -1, -boundingRect.origin.x, -boundingRect.origin.y);
    CGPathRef path = CTFontCreatePathForGlyph(ctFont, glyph, &glyphTransform);

    int width = ceilf(boundingRect.size.width);
    int height = ceilf(boundingRect.size.height);

    std::vector<uint8_t> imageData(width*height);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
    CGBitmapInfo bitmapInfo = (kCGBitmapAlphaInfoMask & kCGImageAlphaNone);
    CGContextRef context = CGBitmapContextCreate(imageData.data(),
                                                 width,
                                                 height,
                                                 8,
                                                 width,
                                                 colorSpace,
                                                 bitmapInfo);

    CGContextAddPath(context, path);
    CGContextFillPath(context);

    auto region = [mgr addRegion:imageData.data() width:width height:height bytesPerRow:width];

    GlyphInfo info = {size, region};

    v.push_back(info);

    CGPathRelease(path);
    CGContextRelease(context);

    return info;

}

- (void) update:(id<MTLCommandBuffer>) buffer {
    [mgr update:buffer];
}

@end
