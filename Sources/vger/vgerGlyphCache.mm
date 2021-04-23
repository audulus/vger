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
        ctFont = CTFontCreateWithName((__bridge CFStringRef)@"Avenir-light", /*fontPointSize*/48, NULL);
    }
    return self;
}

- (void) dealloc {
    CFRelease(ctFont);
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
    CGSize advance;
    CTFontGetAdvancesForGlyphs(ctFont, kCTFontOrientationHorizontal, &glyph, &advance, 1);

    // Render the glyph with CoreText.
    CGRect boundingRect;
    CTFontGetBoundingRectsForGlyphs(ctFont, kCTFontOrientationHorizontal, &glyph, &boundingRect, 1);

    CGAffineTransform glyphTransform = CGAffineTransformMake(1, 0, 0, 1, -boundingRect.origin.x, -boundingRect.origin.y);
    CGPathRef path = CTFontCreatePathForGlyph(ctFont, glyph, &glyphTransform);

    if(path == 0) {
        NSLog(@"no path for glyph index %d\n", (int)glyph);
        return;
    }

    int width = ceilf(boundingRect.size.width);
    int height = ceilf(boundingRect.size.height);

    NSLog(@"glyph size: %d %d\n", width, height);

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

    // Fill the context with an opaque black color
    CGContextSetRGBFillColor(context, 0, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));

    // Set fill color so that glyphs are solid white
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);

    CGContextAddPath(context, path);
    CGContextFillPath(context);

    printf("GLYPH %d\n", (int) glyph);
    for(int i=0;i<width*height;++i) {
        if(i % width == 0) {
            printf("\n");
        }
        if(imageData[i] == 0) {
            printf(".");
        } else {
            printf("*");
        }
        //printf("%d ", (int) imageData[i]);
    }
    printf("\n");

    auto region = [mgr addRegion:imageData.data() width:width height:height bytesPerRow:width];

    GlyphInfo info = {size, region, advance, .glyphSize=boundingRect.size};

    v.push_back(info);

    CGPathRelease(path);
    CGContextRelease(context);

    return info;

}

- (void) update:(id<MTLCommandBuffer>) buffer {
    [mgr update:buffer];
}

- (id<MTLTexture>) getAltas {
    return mgr.atlas;
}

@end