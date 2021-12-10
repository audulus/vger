// Copyright © 2021 Audulus LLC. All rights reserved.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <simd/simd.h>
#include "vger.h"
#include "vgerScene.h"

NS_ASSUME_NONNULL_BEGIN

@interface vgerRenderer : NSObject

- (instancetype)initWithDevice:(id<MTLDevice>) device;

/// Render a buffer of prims.
/// @param buffer commnd buffer for encoding
/// @param pass render pass info
/// @param primBuffer buffer of vgerPrims
/// @param n number of vgerPrims in buffer
/// @param texture texture to sample for textured prims
- (void) encodeTo:(id<MTLCommandBuffer>) buffer
             pass:(MTLRenderPassDescriptor*) pass
            scene:(vgerScene) scene
            count:(int)n
            layer:(int)layer
         textures:(NSArray<id<MTLTexture>>*)textures
     glyphTexture:(id<MTLTexture>)glyphTexture
       windowSize:(vector_float2)windowSize;

@end

NS_ASSUME_NONNULL_END
