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

- (void) testSolveQuadratic {

    float epsilon = 1e-5;

    float2 x = solve_quadratic(-1, 0, 1);
    XCTAssertTrue(simd_equal(x, float2{-1, 1}));

    x = solve_quadratic(0, 0, 1);
    XCTAssertEqual(x[0], 0);
    XCTAssert(isnan(x[1]));

    x = solve_quadratic(-5.0, 0.0, 1.0);
    XCTAssertEqualWithAccuracy(x[0], -sqrtf(5.0), epsilon);
    XCTAssertEqualWithAccuracy(x[1], sqrtf(5.0), epsilon);

    x = solve_quadratic(5.0, 0.0, 1.0);
    XCTAssert(isnan(x[0]));
    XCTAssert(isnan(x[1]));

    x = solve_quadratic(5.0, 1.0, 0.0);
    XCTAssertEqualWithAccuracy(x[0], -5.0, epsilon);
    XCTAssert(isnan(x[1]));

    x = solve_quadratic(1.0, 2.0, 1.0);
    XCTAssertEqualWithAccuracy(x[0], -1.0, epsilon);
    XCTAssert(isnan(x[1]));

}

- (void) testBezierTest {

    XCTAssertEqual(bezierTest(float2{0,0}, float2{1,0}, float2{1,1}, float2{0, .5}), 1);
    XCTAssertEqual(bezierTest(float2{0,0}, float2{1,0}, float2{1,1}, float2{0, -1}), 0);
    XCTAssertEqual(bezierTest(float2{0,0}, float2{1,0}, float2{1,1}, float2{0, 2}), 0);
    XCTAssertEqual(bezierTest(float2{0,0}, float2{1,1}, float2{2,0}, float2{0, .1}), 2);

    XCTAssertEqual(bezierTest(float2{0,-1}, float2{1,0.1}, float2{2,-1}, float2{0, 0}), 0);

    // Vertical line, right of point.
    XCTAssertEqual(bezierTest(float2{1,-1}, float2{1,0}, float2{1,1}, float2{0, 0}), 1);

    // Vertical line, left of point.
    XCTAssertEqual(bezierTest(float2{-1,-1}, float2{-1,0}, float2{-1,1}, float2{0, 0}), 0);

    // Diagonal line, right of point.
    XCTAssertEqual(bezierTest(float2{1, -1}, float2{2,0}, float2{3,1}, float2{0, 0}), 1);

}

- (void) testIntersectionOutsideInterval {
    XCTAssertEqual(bezierTest(float2{0,1}, float2{0,-1}, float2{1,-1}, float2{0,0}), 1);
}

- (void) testAbove {
    XCTAssertEqual(bezierTest(float2{-1,0}, float2{0,-1}, float2{1,0}, float2{-100,1}), 0);
}

- (void) testDiagonalZ {
    // Diagonal in Z
    XCTAssertEqual(bezierTest(float2{0, 1.308}, float2{2.19, 4.374}, float2{4.38, 7.44}, float2{0,5.0}), 1);
}

- (void) testPCurve {
    int n = bezierTest(float2{4.968, 7.728}, float2{5.748, 7.02}, float2{5.748, 5.796},
                       float2{0,6.0});
    XCTAssertEqual(n, 1);
}

- (void) testLineTest {

    float2 i{1,0};
    float2 j{0,1};

    XCTAssertEqual(lineTest(i-j, i+j, 0), 1);
    XCTAssertEqual(lineTest(i-j, i+j, 2*j), 0);
}

@end
