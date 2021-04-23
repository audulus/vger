// Copyright © 2021 Audulus LLC. All rights reserved.

#import <Foundation/Foundation.h>
#include <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

struct GlyphInfo {
    float size = 0.0;
    int regionIndex = -1;
};

@interface vgerGlyphCache : NSObject

- (instancetype)initWithDevice:(id<MTLDevice>) device;

- (GlyphInfo) getGlyph:(CGGlyph)glyph size:(float)size;

@end

NS_ASSUME_NONNULL_END
