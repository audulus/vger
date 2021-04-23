// Copyright © 2021 Audulus LLC. All rights reserved.

#import <XCTest/XCTest.h>
#import "../../Sources/vger/vgerTextureManager.h"
#import <MetalKit/MetalKit.h>
#import "testUtils.h"

@interface vgerTextureManagerTests : XCTestCase {
    id<MTLDevice> device;
    id<MTLCommandQueue> queue;
    MTKTextureLoader* loader;
}

@end

@implementation vgerTextureManagerTests

- (void)setUp {
    device = MTLCreateSystemDefaultDevice();
    loader = [[MTKTextureLoader alloc] initWithDevice: device];
    queue = [device newCommandQueue];
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (void)testPackTextures {
    vgerTextureManager* mgr = [[vgerTextureManager alloc] initWithDevice:device];

    NSBundle* bundle = [NSBundle bundleForClass:self.class];
    NSURL* imageURL = [bundle.bundleURL URLByAppendingPathComponent:@"Contents/Resources/vger_vgerTests.bundle/Contents/Resources/images/icon-mac-16.png"];

    NSLog(@"url: %@", imageURL);

    NSError* error;
    id<MTLTexture> tex = [loader newTextureWithContentsOfURL:imageURL options:nil error:&error];
    assert(error == nil);

    showTexture(tex, @"icon.png");

    [mgr addRegion:tex];
    [mgr addRegion:tex];
    [mgr addRegion:tex];
    [mgr addRegion:tex];

    id<MTLCommandBuffer> buf = [queue commandBuffer];
    [mgr update:buf];

    // Sync texture on macOS
    #if TARGET_OS_OSX
    auto blitEncoder = [buf blitCommandEncoder];
    [blitEncoder synchronizeResource:mgr.atlas];
    [blitEncoder endEncoding];
    #endif

    [buf commit];
    [buf waitUntilCompleted];

    assert(buf.error == nil);

    showTexture(mgr.atlas, @"atlas.png");
}



@end
