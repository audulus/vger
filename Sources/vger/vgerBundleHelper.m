// Copyright © 2021 Audulus LLC. All rights reserved.

#import "vgerBundleHelper.h"
#import <Metal/Metal.h>
#import <CoreText/CoreText.h>
#import <MetalKit/MetalKit.h>

@implementation vgerBundleHelper

+ (NSBundle*) moduleBundle {
#ifdef SWIFTPM_MODULE_BUNDLE
    NSBundle* bundle = SWIFTPM_MODULE_BUNDLE;
#else
    NSBundle* bundle = [NSBundle mainBundle];
#endif
    assert(bundle);
    return bundle;
}

@end
