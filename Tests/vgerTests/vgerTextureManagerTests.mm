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

- (NSURL*) getImageURL:(NSString*)name {
    NSString* path = @"Contents/Resources/vger_vgerTests.bundle/Contents/Resources/images/";
    path = [path stringByAppendingString:name];
    NSBundle* bundle = [NSBundle bundleForClass:self.class];
    return [bundle.bundleURL URLByAppendingPathComponent:path];
}

- (id<MTLTexture>) getTexture:(NSString*)name {

    NSError* error;
    id<MTLTexture> tex = [loader newTextureWithContentsOfURL:[self getImageURL:name] options:nil error:&error];
    assert(error == nil);
    return tex;
}

- (void)testPackTextures {
    vgerTextureManager* mgr = [[vgerTextureManager alloc] initWithDevice:device];

    auto tex = [self getTexture:@"icon-mac-128.png"];

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
