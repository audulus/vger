// Copyright © 2021 Audulus LLC. All rights reserved.

#import <Foundation/Foundation.h>
#include <simd/simd.h>
#import <Metal/Metal.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#include "stb_rect_pack.h"

NS_ASSUME_NONNULL_BEGIN

#define GLYPH_MARGIN 4

struct GlyphInfo {
    float size = 0.0;
    int regionIndex = -1;
    int textureWidth = 0;
    int textureHeight = 0;
    CGRect glyphBounds = CGRectZero;
};

@interface vgerGlyphCache : NSObject

@property (nonatomic, readonly) float usage;

- (instancetype)initWithDevice:(id<MTLDevice>) device;

- (GlyphInfo) getGlyph:(CGGlyph)glyph scale:(float)scale;

- (void) update:(id<MTLCommandBuffer>) buffer;

- (id<MTLTexture>) getAltas;

/// Get a pointer to the first rectangle.
- (stbrp_rect*) getRects;

- (CTFontRef) getFont;

@end

NS_ASSUME_NONNULL_END
