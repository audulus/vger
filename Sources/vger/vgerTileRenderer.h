// Copyright © 2021 Audulus LLC. All rights reserved.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <simd/simd.h>
#include "vger_types.h"

NS_ASSUME_NONNULL_BEGIN

@interface vgerTileRenderer : NSObject

- (instancetype)initWithDevice:(id<MTLDevice>) device;

- (void) encodeTo:(id<MTLCommandBuffer>) buffer
            prims:(id<MTLBuffer>) primBuffer
              cvs:(id<MTLBuffer>) cvBuffer
            count:(int)n
         textures:(NSArray<id<MTLTexture>>*)textures
     glyphTexture:(id<MTLTexture>)glyphTexture
    renderTexture:(id<MTLTexture>)renderTexture
       windowSize:(vector_float2)windowSize;

@end

NS_ASSUME_NONNULL_END
