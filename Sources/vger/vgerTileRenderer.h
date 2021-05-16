// Copyright © 2021 Audulus LLC. All rights reserved.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <simd/simd.h>
#include "vger_types.h"

NS_ASSUME_NONNULL_BEGIN

@interface vgerTileRenderer : NSObject

- (instancetype)initWithDevice:(id<MTLDevice>) device;

@end

NS_ASSUME_NONNULL_END
