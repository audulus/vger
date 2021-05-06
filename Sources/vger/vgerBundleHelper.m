// Copyright © 2021 Audulus LLC. All rights reserved.

#import "vgerBundleHelper.h"

@implementation vgerBundleHelper

+ (NSBundle*) moduleBundle {
    NSBundle* bundle = SWIFTPM_MODULE_BUNDLE;
    assert(bundle);
    return bundle;
}

@end
