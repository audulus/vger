//  Copyright © 2021 Audulus LLC. All rights reserved.

#import <XCTest/XCTest.h>
#import <simd/simd.h>
#include "vger.h"

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

    XCTAssertFalse(lineTest( float2{13.5, 13.5}, float2{60.0, 60.0}, float2{35.0, 35.0} )); // XXX: GPU seems to return true
    XCTAssertFalse(lineTest( float2{36.5, 36.5}, float2{60.0, 60.0}, float2{35.0, 35.0} ));
    XCTAssertTrue(lineTest( float2{36.4999961853, 36.5}, float2{60.0, 60.0}, float2{35.0, 35.0} ));

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

- (void) testSdLine {

    float2 a{0,0};
    float2 b{1,0};
    float2 c{2,0};

    auto d = sdLine(float2{1,1}, a, b);
    XCTAssertEqualWithAccuracy(d, 1.0, 0.001);

    d = sdLine(float2{1,-1}, a, b);
    XCTAssertEqualWithAccuracy(d, -1.0, 0.001);

    d = sdLine(float2{1,1}, a, c);
    XCTAssertEqualWithAccuracy(d, 1.0, 0.001);
}

- (void) testBezierCollinear {

    float2 a{0,0};
    float2 b{1,0};
    float2 c{2,0};

    auto d = udBezier(float2{1,1}, a, b, c);
    XCTAssertEqualWithAccuracy(d, 1.0, 0.001);

    d = udBezier(float2{1,-1}, a, b, c);
    XCTAssertEqualWithAccuracy(d, 1.0, 0.001);
}

@end
