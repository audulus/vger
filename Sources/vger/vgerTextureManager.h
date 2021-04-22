// Copyright © 2021 Audulus LLC. All rights reserved.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

@interface vgerTextureManager : NSObject

- (instancetype)initWithDevice:(id<MTLDevice>) device;

/// Creates a new region in the texture.
/// @param data RGBA texture data (8-bits per component)
/// @param width texture width
/// @param height texture height
/// @returns region index
- (int) addRegion: (uint8_t*) data width:(int)width height:(int)height;

@end

NS_ASSUME_NONNULL_END
