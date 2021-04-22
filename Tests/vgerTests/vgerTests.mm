//  Copyright © 2021 Audulus LLC. All rights reserved.

#import <XCTest/XCTest.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import "vgerRenderer.h"
#include "nanovg_mtl.h"
#include <vector>

using namespace simd;

@interface vgerTests : XCTestCase {
    id<MTLDevice> device;
    id<MTLCommandQueue> queue;
    vgerRenderer* renderer;
    id<MTLTexture> texture;
    MTLRenderPassDescriptor* pass;
}

@end

@implementation vgerTests

- (void)setUp {
    device = MTLCreateSystemDefaultDevice();
    queue = [device newCommandQueue];
    renderer = [[vgerRenderer alloc] initWithDevice:device];

    int w = 512;
    int h = 512;

    auto textureDesc = [MTLTextureDescriptor
                        texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                        width:w
                        height:h
                        mipmapped:NO];

    textureDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    textureDesc.storageMode = MTLStorageModeManaged;

    texture = [device newTextureWithDescriptor:textureDesc];
    assert(texture);

    pass = [MTLRenderPassDescriptor new];
    pass.colorAttachments[0].texture = texture;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

void writeCGImage(CGImageRef image, CFURLRef url) {
    auto dest = CGImageDestinationCreateWithURL(url, kUTTypePNG, 1, nil);
    CGImageDestinationAddImage(dest, image, nil);
    assert(CGImageDestinationFinalize(dest));
}

CGImageRef getImage(UInt8* data, int w, int h) {

    auto provider = CGDataProviderCreateWithData(nullptr,
                                                 data,
                                                 4*w*h,
                                                 nullptr);

    return CGImageCreate(w, h,
                         8, 32,
                         w*4,
                         CGColorSpaceCreateDeviceRGB(),
                         kCGImageAlphaNoneSkipLast,
                         provider,
                         nil,
                         true,
                         kCGRenderingIntentDefault);

}

CGImageRef getTextureImage(id<MTLTexture> texture) {

    int w = texture.width;
    int h = texture.height;

    std::vector<UInt8> imageBytes(4*w*h);
    [texture getBytes:imageBytes.data() bytesPerRow:w * 4 fromRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0];

    return getImage(imageBytes.data(), w, h);
}

static void SplitBezier(float t,
                        simd_float2 cv[3],
                        simd_float2 a[3],
                        simd_float2 b[3]) {

    a[0] = cv[0];
    b[2] = cv[2];

    a[1] = simd_mix(cv[0], cv[1], t);
    b[1] = simd_mix(cv[1], cv[2], t);

    a[2] = b[0] = simd_mix(a[1], b[1], t);

}

- (void) testBasic {

    simd_float2 cvs[3] = {0, {0,0.5}, {0.5,0.5}};
    simd_float2 cvs_l[3];
    simd_float2 cvs_r[3];
    SplitBezier(0.5, cvs, cvs_l, cvs_r);

    simd_float4 white = {1,1,1,1};
    simd_float4 cyan = {0,1,1,1};
    simd_float4 magenta = {1,0,1,1};

    float theta = 0;
    float ap = .5 * M_PI;

    vgerPrim primArray[] = {
        // { .type = vgerBezier, .cvs = {0, {0,0.5}, {0.5,0.5}}, .colors = {{1,1,1,.5}, 0, 0}},
        {
            .type = vgerCircle,
            .xform=matrix_identity_float3x3,
            .width = 0.01,
            .radius = 0.2,
            .cvs = {0, {0,0.5}, {0.5,0.5}},
            .colors = {cyan, 0, 0},
            .texture = -1
        },
        {
            .type = vgerCurve,
            .xform=matrix_identity_float3x3,
            .width = 0.01,
            .count = 5,
            .colors = {white, 0, 0},
            .texture = -1
        },
        {
            .type = vgerSegment,
            .xform=matrix_identity_float3x3,
            .width = 0.01,
            .cvs = {{-.6,-.6}, {-.4,-.5}},
            .colors = {magenta, 0, 0},
            .texture = -1
        },
        {
            .type = vgerRect,
            .xform=matrix_identity_float3x3,
            .width = 0.01,
            .cvs = {{-.8,-.8}, {.1,.1}},
            .radius=0.02,
            .colors = {{1,1,1,.5}, 0, 0},
            .texture = -1
        },
        {
            .type = vgerArc,
            .xform=matrix_identity_float3x3,
            .width = 0.01,
            .cvs = {{-.5, 0.5}, {sin(theta), cos(theta)}, {sin(ap), cos(ap)}},
            .radius=0.1,
            .colors = {white},
            .texture = -1
        }
    };
    
    simd_float2* pts = primArray[1].cvs;
    pts[0] = cvs_l[0];
    pts[1] = cvs_l[1];
    pts[2] = cvs_l[2];
    pts[3] = cvs_r[1];
    pts[4] = cvs_r[2];

    auto prims = [device newBufferWithBytes:primArray length:sizeof(primArray) options:MTLResourceStorageModeShared];
    assert(prims);

    auto commandBuffer = [queue commandBuffer];

    [renderer encodeTo:commandBuffer pass:pass prims:prims count:sizeof(primArray)/sizeof(vgerPrim)];

    // Sync texture on macOS
    #if TARGET_OS_OSX
    auto blitEncoder = [commandBuffer blitCommandEncoder];
    [blitEncoder synchronizeResource:texture];
    [blitEncoder endEncoding];
    #endif

    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    auto tmpURL = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:@"vger.png"];

    NSLog(@"saving to %@", tmpURL);

    writeCGImage(getTextureImage(texture), (__bridge CFURLRef)tmpURL);

    system([NSString stringWithFormat:@"open %@", tmpURL.path].UTF8String);

}

static
vector_float2 rand2() {
    return float2{float(rand()) / RAND_MAX, float(rand()) / RAND_MAX};
}

static
vector_float2 rand_box() {
    return 2*rand2()-1;
}

static
vector_float4 rand_color() {
    return {float(rand()) / RAND_MAX, float(rand()) / RAND_MAX, float(rand()) / RAND_MAX, 1.0};
}

- (void) testBezierPerf {

    std::vector<vgerPrim> primArray;

    int N = 10000;

    for(int i=0;i<N;++i) {
        vgerPrim p = {
            .type = vgerBezier,
            .xform = matrix_identity_float3x3,
            .width = 0.01,
            .cvs ={ rand_box(), rand_box(), rand_box() },
            .colors = {rand_color(), 0, 0},
            .texture = -1
        };
        primArray.push_back(p);
    }

    auto prims = [device newBufferWithBytes:primArray.data() length:primArray.size()*sizeof(vgerPrim) options:MTLResourceStorageModeShared];
    assert(prims);

    [self measureMetrics:@[XCTPerformanceMetric_WallClockTime] automaticallyStartMeasuring:NO forBlock:^{

        [self startMeasuring];
        auto commandBuffer = [queue commandBuffer];

        [renderer encodeTo:commandBuffer pass:pass prims:prims count:primArray.size()];

        // Sync texture on macOS
        #if TARGET_OS_OSX
        auto blitEncoder = [commandBuffer blitCommandEncoder];
        [blitEncoder synchronizeResource:texture];
        [blitEncoder endEncoding];
        #endif

        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];
        [self stopMeasuring];
    }];

    auto tmpURL = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:@"vger_bezier_perf.png"];

    NSLog(@"saving to %@", tmpURL);

    writeCGImage(getTextureImage(texture), (__bridge CFURLRef)tmpURL);

    system([NSString stringWithFormat:@"open %@", tmpURL.path].UTF8String);
}

- (void) testBezierPerfSplit {

    std::vector<vgerPrim> primArray;

    int N = 10000;

    for(int i=0;i<N;++i) {
        simd_float2 cvs[3] = { rand_box(), rand_box(), rand_box() };
        auto c = rand_color();
        vgerPrim p[2] = {
            {
                .type = vgerBezier,
                .xform = matrix_identity_float3x3,
                .width = 0.01,
                .colors = {c, 0, 0},
                .texture = -1
            },
            {
                .type = vgerBezier,
                .xform = matrix_identity_float3x3,
                .width = 0.01,
                .colors = {c, 0, 0},
                .texture = -1
            }
        };
        SplitBezier(.5, cvs, p[0].cvs, p[1].cvs);
        primArray.push_back(p[0]);
        primArray.push_back(p[1]);
    }

    auto prims = [device newBufferWithBytes:primArray.data() length:primArray.size()*sizeof(vgerPrim) options:MTLResourceStorageModeShared];
    assert(prims);

    [self measureMetrics:@[XCTPerformanceMetric_WallClockTime] automaticallyStartMeasuring:NO forBlock:^{

        [self startMeasuring];
        auto commandBuffer = [queue commandBuffer];

        [renderer encodeTo:commandBuffer pass:pass prims:prims count:primArray.size()];

        // Sync texture on macOS
        #if TARGET_OS_OSX
        auto blitEncoder = [commandBuffer blitCommandEncoder];
        [blitEncoder synchronizeResource:texture];
        [blitEncoder endEncoding];
        #endif

        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];
        [self stopMeasuring];
    }];

    auto tmpURL = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:@"vger_bezier_perf.png"];

    NSLog(@"saving to %@", tmpURL);

    writeCGImage(getTextureImage(texture), (__bridge CFURLRef)tmpURL);

    system([NSString stringWithFormat:@"open %@", tmpURL.path].UTF8String);
}

void renderPaths(NVGcontext* vg, const std::vector<vgerPrim>& primArray) {

    for(auto& prim : primArray) {
        nvgStrokeWidth(vg, prim.width);
        auto c = prim.colors[0];
        nvgStrokeColor(vg, nvgRGBAf(c.x, c.y, c.z, c.w));
        nvgBeginPath(vg);
        auto& cvs = prim.cvs;
        nvgMoveTo(vg, cvs[0].x, cvs[0].y);
        nvgQuadTo(vg, cvs[1].x, cvs[1].y, cvs[2].x, cvs[2].y);
        nvgStroke(vg);
    }

}

- (void) testNanovgPerf {

    int w = 512, h = 512;
    float2 sz = {float(w),float(h)};

    std::vector<vgerPrim> primArray;

    int N = 10000;

    for(int i=0;i<N;++i) {
        auto c = rand_color();
        vgerPrim p = {
            .type = vgerBezier,
            .xform = matrix_identity_float3x3,
            .width = 0.01f*w,
            .cvs ={ rand2()*sz, rand2()*sz, rand2()*sz },
            .colors = {c, 0, 0}
        };
        primArray.push_back(p);
    }

    auto layer = [CAMetalLayer new];
    auto vg = nvgCreateMTL( (__bridge void*) layer, NVG_ANTIALIAS);

    auto fb = mnvgCreateFramebuffer(vg, w, h, 0);
    mnvgBindFramebuffer(fb);

    // Warm up:
    mnvgClearWithColor(vg, nvgRGBAf(0.0, 0.0, 0.0, 1.0));
    nvgBeginFrame(vg, w, h, 1.0);
    renderPaths(vg, primArray);
    nvgEndFrame(vg);

    [self measureMetrics:@[XCTPerformanceMetric_WallClockTime] automaticallyStartMeasuring:NO forBlock:^{

        [self startMeasuring];
        mnvgClearWithColor(vg, nvgRGBAf(0.0, 0.0, 0.0, 1.0));
        nvgBeginFrame(vg, w, h, 1.0);
        renderPaths(vg, primArray);
        nvgEndFrame(vg);
        [self stopMeasuring];

    }];

    // RGBA.
    int componentsPerPixel = 4;

    // 8-bit.
    int bitsPerComponent = 8;

    int imageLength = w * h * componentsPerPixel;
    std::vector<UInt8> imageBits(imageLength);
    mnvgReadPixels(vg, fb->image, 0, 0, w, h, imageBits.data());

    auto tmpURL = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:@"nvg_bezier_perf.png"];

    NSLog(@"saving to %@", tmpURL);

    writeCGImage(getImage(imageBits.data(), w, h), (__bridge CFURLRef)tmpURL);

    system([NSString stringWithFormat:@"open %@", tmpURL.path].UTF8String);
}

@end
