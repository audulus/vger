// Copyright © 2021 Audulus LLC. All rights reserved.

#import "vgerGlyphCache.h"
#import "vgerTextureManager.h"
#import "vgerBundleHelper.h"
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

        auto bundle = [vgerBundleHelper moduleBundle];
        assert(bundle);

        auto fontURL = [bundle URLForResource:@"Anodina-Regular" withExtension:@"ttf" subdirectory:@"fonts"];

        auto fd = CTFontManagerCreateFontDescriptorsFromURL( (__bridge CFURLRef) fontURL);
        ctFont = CTFontCreateWithFontDescriptor( (CTFontDescriptorRef) CFArrayGetValueAtIndex(fd, 0), 12.0, nil);
        assert(ctFont);
        CFRelease(fd);
        //ctFont = CTFontCreateWithName((__bridge CFStringRef)@"Avenir-light", /*fontPointSize*/24, NULL);
    }
    return self;
}

- (void) dealloc {
    CFRelease(ctFont);
}

- (GlyphInfo) getGlyph:(CGGlyph)glyph scale:(float) scale {

    if(glyph >= glyphs.size()) {
        glyphs.resize(glyph+1);
    }

    auto& v = glyphs[glyph];

    for(auto& info : v) {
        if(info.size == scale) {
            return info;
        }
    }

    // Render the glyph with CoreText.
    CGRect boundingRect;
    CTFontGetBoundingRectsForGlyphs(ctFont, kCTFontOrientationHorizontal, &glyph, &boundingRect, 1);

    auto glyphTransform = CGAffineTransformMake(1, 0, 0, 1,
                                                -boundingRect.origin.x,
                                                -boundingRect.origin.y);
    auto path = CTFontCreatePathForGlyph(ctFont, glyph, &glyphTransform);

    if(path == 0) {
        //NSLog(@"no path for glyph index %d\n", (int)glyph);
        return GlyphInfo();
    }

    boundingRect.size.width *= scale;
    boundingRect.size.height *= scale;

    int width = ceilf(boundingRect.size.width) + 2*GLYPH_MARGIN;
    int height = ceilf(boundingRect.size.height) + 2*GLYPH_MARGIN;

    //NSLog(@"glyph size: %d %d\n", width, height);

    std::vector<uint8_t> imageData(width*height);

    auto colorSpace = CGColorSpaceCreateDeviceGray();
    auto bitmapInfo = (kCGBitmapAlphaInfoMask & kCGImageAlphaNone);
    auto context = CGBitmapContextCreate(imageData.data(),
                                                 width,
                                                 height,
                                                 8,
                                                 width,
                                                 colorSpace,
                                                 bitmapInfo);

    CGContextTranslateCTM(context, GLYPH_MARGIN, GLYPH_MARGIN);
    CGContextScaleCTM(context, scale, scale);

    // Fill the context with an opaque black color
    CGContextSetRGBFillColor(context, 0, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));

    // Set fill color so that glyphs are solid white
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);

    CGContextAddPath(context, path);
    CGContextFillPath(context);

    auto region = [mgr addRegion:imageData.data() width:width height:height bytesPerRow:width];

    GlyphInfo info = {
        .size=scale,
        .regionIndex=region,
        .textureWidth=width,
        .textureHeight=height,
        .glyphBounds=boundingRect
    };

    v.push_back(info);

    CGPathRelease(path);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);

    return info;

}

- (void) update:(id<MTLCommandBuffer>) buffer {
    [mgr update:buffer];
}

- (id<MTLTexture>) getAltas {
    return mgr.atlas;
}

- (stbrp_rect*) getRects {
    return [mgr getRects];
}

- (CTFontRef) getFont {
    return ctFont;
}

- (float) usage {
    return mgr.usage;
}

@end
