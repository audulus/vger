//  Copyright © 2021 Audulus LLC. All rights reserved.

#import <XCTest/XCTest.h>
#import <simd/simd.h>
#include "vger_types.h"

#import "../../Sources/vger/sdf.h"

@interface sdfTests : XCTestCase

@end

@implementation sdfTests

- (void) testWire {

    float d = sdWire(float2{0,0}, float2{0,0}, float2{1,1});
    XCTAssertEqualWithAccuracy(d, 0, 0.1);
    
    d = sdWire(float2{1,1}, float2{0,0}, float2{1,1});
    XCTAssertEqualWithAccuracy(d, 0, 0.1);

    d = sdWire(float2{0.5,0.5}, float2{0,0}, float2{1,1});
    XCTAssertEqualWithAccuracy(d, 0, 0.1);

}

- (void) testLineTest {

    float2 i{1,0};
    float2 j{0,1};

    XCTAssertEqual(lineTest(i-j, i+j, 0), 1);
    XCTAssertEqual(lineTest(i-j, i+j, 2*j), 0);
}

@end
