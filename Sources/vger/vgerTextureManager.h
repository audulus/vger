// Copyright © 2021 Audulus LLC. All rights reserved.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "stb_rect_pack.h"

NS_ASSUME_NONNULL_BEGIN

@interface vgerTextureManager : NSObject

@property (nonatomic, retain, readonly) id<MTLTexture> atlas;
@property (nonatomic, readonly) float usage;

- (instancetype)initWithDevice:(id<MTLDevice>) device pixelFormat:(MTLPixelFormat)format;

/// Creates a new region in the texture.
/// @param data RGBA texture data (8-bits per component)
/// @param width texture width
/// @param height texture height
/// @returns region index
- (int) addRegion: (const uint8_t*) data width:(int)width height:(int)height bytesPerRow:(NSUInteger)bytesPerRow;

/// Add region for an already loaded texture.
- (int) addRegion:(id<MTLTexture>)texture;

/// Updates the atlas texture.
/// @param buffer to encode blit commands
- (void) update:(id<MTLCommandBuffer>) buffer;

/// Get a pointer to the first rectangle.
- (stbrp_rect*) getRects;

@end

NS_ASSUME_NONNULL_END
