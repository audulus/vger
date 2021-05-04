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
        printf("interval %f %f, active: ", scan.yInterval.a, scan.yInterval.b);
        for(int a : scan.active) {
            printf("%d ", a);
        }
        printf("\n");
    }

    printf("done\n");
}

@end
