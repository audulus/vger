// Copyright © 2021 Audulus LLC. All rights reserved.

#import <Foundation/Foundation.h>
#include <simd/simd.h>
#import <Metal/Metal.h>
#include "stb_rect_pack.h"

NS_ASSUME_NONNULL_BEGIN

#define GLYPH_MARGIN 2

struct GlyphInfo {
    float size = 0.0;
    int regionIndex = -1;
    CGSize glyphSize = CGSizeZero;
};

@interface vgerGlyphCache : NSObject

- (instancetype)initWithDevice:(id<MTLDevice>) device;

- (GlyphInfo) getGlyph:(CGGlyph)glyph size:(float)size;

- (void) update:(id<MTLCommandBuffer>) buffer;

- (id<MTLTexture>) getAltas;

/// Get a pointer to the first rectangle.
- (stbrp_rect*) getRects;

- (CTFontRef) getFont;

@end

NS_ASSUME_NONNULL_END
