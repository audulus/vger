//  Copyright © 2021 Audulus LLC. All rights reserved.

#import <XCTest/XCTest.h>
#import <simd/simd.h>
#include "vger_types.h"

using namespace simd;

float min(float a, float b) {
    return a > b ? b : a;
}

float clamp(float x, float a, float b) {
    if(x > b) x = b;
    if(x < a) x = a;
    return x;
}

float3 clamp(float3 x, float a, float b) {
    return simd_clamp(x, a, b);
}

float mix(float a, float b, float t) {
    return (1-t)*a + t*b;
}

float2 mix(float2 a, float2 b, float t) {
    return (1-t)*a + t*b;
}

#import "../../Sources/vger/sdf.h"

@interface sdfTests : XCTestCase

@end

@implementation sdfTests

@end
