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

    XCTAssertEqual(lineTest(0, i-j, i+j), 1);
    XCTAssertEqual(lineTest(2*j, i-j, i+j), 0);
}

static void printBezierTest(float2 A, float2 B, float2 C) {
    for(float y=2; y>=0; y-=.1) {
        for(float x=0; x<2; x+=.1) {
            putchar( bezierTest(float2{x,y}, A, B, C) ? '*' : ' ');
        }
        putchar('\n');
    }
}

- (void) testBezierTest {

    float2 i{1,0};
    float2 j{0,1};

    XCTAssertEqual(bezierTest(i+.1*j, 0, i+j, 2*i), 1);
    XCTAssertEqual(bezierTest(i+.9*j, 0, i+j, 2*i), 0);
    XCTAssertEqual(bezierTest(i+2*j, 0, i+j, 2*i), 0);

    XCTAssertEqual(bezierTest(i-.9*j, 0, i-j, 2*i), 0);


    printBezierTest(0, i+j, 2*i);

    printBezierTest(0, i+2*j, 2*i);

    printBezierTest(j, i, 2*i+j);

    printBezierTest(2*j, i, 2*i+2*j);


}

@end
