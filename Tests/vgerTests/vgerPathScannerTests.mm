// Copyright © 2021 Audulus LLC. All rights reserved.

#import <XCTest/XCTest.h>
#import "../../Sources/vger/vgerPathScanner.h"

@interface vgerPathScannerTests : XCTestCase

@end

@implementation vgerPathScannerTests

- (void)setUp {
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (void)testScan {

    vgerPathScanner scan;

    // circle-ish
    vector_float2 cvs[] = { {1,0}, {1,1}, {0,1}, {-1, 1}, {-1,0}, {-1, -1}, {0,-1}, {1,-1}, {1,0}};
    scan.begin(cvs, sizeof(cvs)/sizeof(vector_float2));

    XCTAssertEqual(scan.segments.size(), 4);

    while(scan.next()) {
        printf("interval %f %f, active: ", scan.interval.a, scan.interval.b);
        for(int a = scan.first; a != -1; a = scan.segments[a].next) {
            printf("%d ", a);
        }
        printf("\n");
    }

    printf("done\n");
}

- (void)testScanCGPath {
 
    auto path = CGPathCreateMutable();
    
    vector_float2 cvs[] = { {1,0}, {1,1}, {0,1}, {-1, 1}, {-1,0}, {-1, -1}, {0,-1}, {1,-1}, {1,0}};
    
    int n = sizeof(cvs)/sizeof(vector_float2);
    CGPathMoveToPoint(path, nullptr, cvs[0].x, cvs[0].y);
    for(int i=1;i<n-1;i+=2) {
        CGPathAddQuadCurveToPoint(path, nullptr, cvs[i].x, cvs[i].y, cvs[i+1].x, cvs[i+1].y);
    }
    CGPathCloseSubpath(path);
    
    vgerPathScanner scan;
    scan.begin(path);
    
    while(scan.next()) {
        printf("interval %f %f, active: ", scan.interval.a, scan.interval.b);
        for(int a = scan.first; a != -1; a = scan.segments[a].next) {
            printf("%d ", a);
        }
        printf("\n");
    }

    printf("done\n");
    
    CGPathRelease(path);
}

@end
