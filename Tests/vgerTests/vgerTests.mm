//  Copyright © 2021 Audulus LLC. All rights reserved.

#import <XCTest/XCTest.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <MetalKit/MetalKit.h>
#import "../../Sources/vger/vgerRenderer.h"
#import "testUtils.h"
#import "vger.h"
#include "nanovg_mtl.h"
#include <vector>

#define NANOSVG_IMPLEMENTATION
#include "nanosvg.h"

#import "../../Sources/vger/sdf.h"
#import "../../Sources/vger/commands.h"
#import "../../Sources/vger/vger_private.h"
#import "../../Sources/vger/vgerTileRenderer.h"

using namespace simd;

@interface vgerTests : XCTestCase {
    id<MTLDevice> device;
    id<MTLCommandQueue> queue;
    id<MTLTexture> texture;
    MTLRenderPassDescriptor* pass;
    MTKTextureLoader* loader;
}

@end

@implementation vgerTests

- (void)setUp {
    device = MTLCreateSystemDefaultDevice();
    queue = [device newCommandQueue];
    loader = [[MTKTextureLoader alloc] initWithDevice: device];

    int w = 512;
    int h = 512;

    auto textureDesc = [MTLTextureDescriptor
                        texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                        width:w
                        height:h
                        mipmapped:NO];

    textureDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    textureDesc.storageMode = MTLStorageModeShared;

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

- (void) render:(vgerContext)vg name:(NSString*) name {

    auto commandBuffer = [queue commandBuffer];

    vgerEncode(vg, commandBuffer, pass);

    // Sync texture on macOS
    #if TARGET_OS_OSX
    auto blitEncoder = [commandBuffer blitCommandEncoder];
    [blitEncoder synchronizeResource:texture];
    [blitEncoder endEncoding];
    #endif

    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    showTexture(texture, name);

}

- (void) checkRender:(vgerContext)vg name:(NSString*) name {

    auto commandBuffer = [queue commandBuffer];

    vgerEncode(vg, commandBuffer, pass);

    // Sync texture on macOS
    #if TARGET_OS_OSX
    auto blitEncoder = [commandBuffer blitCommandEncoder];
    [blitEncoder synchronizeResource:texture];
    [blitEncoder endEncoding];
    #endif

    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    XCTAssertTrue(checkTexture(texture, name));

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

- (void) testSizes {
    XCTAssertEqual(sizeof(vgerPaint), 96);
    XCTAssertEqual(sizeof(vgerPrim), 88);
}

- (void) testBasic {

    float theta = 0;
    float ap = .5 * M_PI;

    auto vg = vgerNew(0);

    vgerBegin(vg, 512, 512, 1.0);

    auto white = vgerColorPaint(vg, float4{1,1,1,1});
    auto cyan = vgerColorPaint(vg, float4{0,1,1,1});
    auto magenta = vgerColorPaint(vg, float4{1,0,1,1});

    vgerFillCircle(vg, float2{256, 256}, 40, cyan);
    vgerStrokeBezier(vg, {{256,256}, {256,384}, {384,384}}, 1, white);
    vgerFillRect(vg, float2{400,100}, float2{450,150}, 10, vgerLinearGradient(vg, float2{400,100}, float2{450, 150}, float4{0,1,1,1}, float4{1,0,1,1}));
    vgerStrokeArc(vg, float2{100,400}, 30, 3, theta, ap, white);
    vgerStrokeSegment(vg, float2{100,100}, float2{200,200}, 10, magenta);
    vgerStrokeRect(vg, float2{400,100}, float2{450,150}, 10, 2.0, magenta);
    vgerStrokeWire(vg, float2{200,100}, float2{300,200}, 3, white);

    vgerSave(vg);
    vgerScale(vg, float2{100, 100});
    float2 cvs2[] = {0, {1,0}, {1,1}, {0,1}, {0, 2}, {0,1} };
    vgerMoveTo(vg, cvs2[0]);
    vgerQuadTo(vg, cvs2[1], cvs2[2]);
    vgerQuadTo(vg, cvs2[3], cvs2[4]);
    vgerQuadTo(vg, cvs2[5], cvs2[0]);
    vgerFill(vg, white);
    vgerRestore(vg);

    [self checkRender:vg name:@"vger_basics.png"];

    vgerDelete(vg);

}

- (void) testTransformStack {

    auto vger = vgerNew(0);

    vgerBegin(vger, 512, 512, 1.0);

    XCTAssertTrue(equal(vgerTransform(vger, float2{0,0}), float2{0, 0}));

    auto cyan = vgerColorPaint(vger, float4{0,1,1,1});
    vgerFillCircle(vger, float2{20,20}, 10, cyan);

    vgerSave(vger);
    vgerTranslate(vger, float2{100,0.0f});
    vgerTranslate(vger, float2{0.0f,100});
    vgerScale(vger, float2{4.0f, 4.0f});
    vgerFillCircle(vger, float2{20,20}, 10, cyan);

    vgerRestore(vger);

    [self render:vger name:@"xform.png"];

    vgerDelete(vger);
}

- (void) testRects {

    auto vger = vgerNew(0);
    assert(vger);

    vgerBegin(vger, 512, 512, 1.0);

    vgerSave(vger);

    auto white = vgerColorPaint(vger, float4(1));

    for(float i=0;i<10;++i) {
        float2 p = {20+i*40,20};
        vgerFillRect(vger, p, p + float2(20), 0.3, white);
    }

    vgerRestore(vger);

    [self render:vger name:@"rects.png"];

    vgerDelete(vger);
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

- (void) testRenderTexture {

    auto vger = vgerNew(0);

    vgerBegin(vger, 512, 512, 1.0);

    auto tex = [self getTexture:@"icon-mac-256.png"];
    auto idx = vgerAddMTLTexture(vger, tex);

    auto sz = vgerTextureSize(vger, idx);
    XCTAssert(equal(sz, simd_int2(256)));

    vgerFillRect(vger, float2{0,0}, float2{256,256}, 0.3, vgerImagePattern(vger, float2{0,0}, float2{256,256}, 0, idx, 1));

    auto commandBuffer = [queue commandBuffer];

    vgerEncode(vger, commandBuffer, pass);

    [self render:vger name:@"texture.png"];

    vgerDelete(vger);
}

- (void) testText {

    auto vger = vgerNew(0);

    vgerBegin(vger, 512, 512, 1.0);

    vgerSave(vger);
    vgerTranslate(vger, float2{100,100});
    vgerText(vger, "This is a test.", float4{0,1,1,1}, VGER_ALIGN_LEFT);
    vgerRestore(vger);

    auto commandBuffer = [queue commandBuffer];

    vgerEncode(vger, commandBuffer, pass);
    auto atlas = vgerGetGlyphAtlas(vger);

    // Sync texture on macOS
    #if TARGET_OS_OSX
    auto blitEncoder = [commandBuffer blitCommandEncoder];
    [blitEncoder synchronizeResource:texture];
    [blitEncoder synchronizeResource:atlas];
    [blitEncoder endEncoding];
    #endif

    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    showTexture(atlas, @"glyph_atlas.png");
    showTexture(texture, @"text.png");

    vgerDelete(vger);

}

- (void) testScaleText {

    auto vger = vgerNew(0);

    vgerBegin(vger, 512, 512, 1.0);

    vgerSave(vger);
    vgerTranslate(vger, float2{100,100});
    vgerScale(vger, float2{10,10});
    vgerText(vger, "This is a test.", float4{0,1,1,1}, VGER_ALIGN_LEFT);
    vgerRestore(vger);

    auto commandBuffer = [queue commandBuffer];

    vgerEncode(vger, commandBuffer, pass);
    auto atlas = vgerGetGlyphAtlas(vger);

    // Sync texture on macOS
    #if TARGET_OS_OSX
    auto blitEncoder = [commandBuffer blitCommandEncoder];
    [blitEncoder synchronizeResource:texture];
    [blitEncoder synchronizeResource:atlas];
    [blitEncoder endEncoding];
    #endif

    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    showTexture(atlas, @"glyph_atlas.png");
    showTexture(texture, @"text.png");

    vgerDelete(vger);

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

    int N = 10000;

    auto vger = vgerNew(0);

    [self measureBlock:^{

        vgerBegin(vger, 512, 512, 1.0);

        for(int i=0;i<N;++i) {

            auto paint = vgerColorPaint(vger, rand_color());
            vgerStrokeBezier(vger, { 512*rand2(), 512*rand2(), 512*rand2() }, 1, paint);
        }

        auto commandBuffer = [queue commandBuffer];

        vgerEncode(vger, commandBuffer, pass);

        // Sync texture on macOS
        #if TARGET_OS_OSX
        auto blitEncoder = [commandBuffer blitCommandEncoder];
        [blitEncoder synchronizeResource:texture];
        [blitEncoder endEncoding];
        #endif

        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];

    }];

    showTexture(texture, @"vger_bezier_perf.png");
}

- (void) testBezierPerfSplit {

    auto vger = vgerNew(0);

    [self measureBlock:^{

        vgerBegin(vger, 512, 512, 1.0);

        int N = 10000;

        for(int i=0;i<N;++i) {
            simd_float2 cvs[3] = { 512*rand2(), 512*rand2(), 512*rand2() };
            auto paint = vgerColorPaint(vger, rand_color());
            simd_float2 a[3], b[3];
            SplitBezier(.5, cvs, a, b);

            vgerStrokeBezier(vger, {a[0], a[1], a[2]}, 1, paint);
            vgerStrokeBezier(vger, {b[0], b[1], b[2]}, 1, paint);
        }

        auto commandBuffer = [queue commandBuffer];
        vgerEncode(vger, commandBuffer, pass);

        // Sync texture on macOS
        #if TARGET_OS_OSX
        auto blitEncoder = [commandBuffer blitCommandEncoder];
        [blitEncoder synchronizeResource:texture];
        [blitEncoder endEncoding];
        #endif

        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];
    }];

    showTexture(texture, @"vger_bezier_split_perf.png");
}

/*
void renderPaths(NVGcontext* vg, const std::vector<vgerPrim>& primArray) {

    for(auto& prim : primArray) {
        nvgStrokeWidth(vg, prim.width);
        auto c = prim.paint.innerColor;
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
        auto c = vgerColorPaint(rand_color());
        vgerPrim p = {
            .type = vgerBezier,
            .width = 0.01f*w,
            .cvs ={ rand2()*sz, rand2()*sz, rand2()*sz },
            .paint = c
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

    writeCGImage(createImage(imageBits.data(), w, h), (__bridge CFURLRef)tmpURL);

#if TARGET_OS_OSX
    system([NSString stringWithFormat:@"open %@", tmpURL.path].UTF8String);
#endif
}
*/

static void textAt(vgerContext vger, float x, float y, const char* str) {
    vgerSave(vger);
    vgerTranslate(vger, float2{x, y});
    vgerScale(vger, float2{2,2});
    vgerText(vger, str, float4{0,1,1,1}, VGER_ALIGN_LEFT);
    vgerRestore(vger);
}

- (void) testPrimDemo {

    auto cyan = float4{0,1,1,1};
    auto magenta = float4{1,0,1,1};

    auto vger = vgerNew(0);

    vgerBegin(vger, 512, 512, 1.0);

    vgerSave(vger);

    vgerStrokeBezier(vger, {{50,450}, {100,450}, {100,500}}, 2.0, vgerLinearGradient(vger, float2{50,450}, float2{100,450}, cyan, magenta));
    textAt(vger, 150, 450, "Quadratic Bezier stroke");

    vgerFillRect(vger, float2{50,350}, float2{100,400}, 10, vgerLinearGradient(vger, float2{50,350}, float2{100,400}, cyan, magenta));
    textAt(vger, 150, 350, "Rounded rectangle");

    vgerFillCircle(vger, float2{75, 275}, 25, vgerLinearGradient(vger, float2{50,250}, float2{100,300}, cyan, magenta));
    textAt(vger, 150, 250, "Circle");

    vgerStrokeSegment(vger, float2{50,150}, float2{100,200}, 2.0, vgerLinearGradient(vger, float2{50,150}, float2{100,200}, cyan, magenta));
    textAt(vger, 150, 150, "Line segment");

    float theta = 0;      // orientation
    float ap = .5 * M_PI; // aperture size
    vgerStrokeArc(vger, float2{75,75}, 25, 2.0, theta, ap, vgerLinearGradient(vger, float2{50,50}, float2{100,100}, cyan, magenta));
    textAt(vger, 150, 050, "Arc");

    vgerRestore(vger);

    [self render:vger name:@"demo.png"];

    vgerDelete(vger);

}

- (void) testPaint {

    auto p = makeLinearGradient(float2{0,0}, float2{1,0}, float4(0), float4(1));

    XCTAssertTrue(equal(applyPaint(p, float2{0,0}), float4(0)));
    XCTAssertTrue(equal(applyPaint(p, float2{.5,0}), float4(.5)));
    XCTAssertTrue(equal(applyPaint(p, float2{1,0}), float4(1)));

    p = makeLinearGradient(float2{0,0}, float2{0,1}, float4(0), float4(1));

    XCTAssertTrue(equal(applyPaint(p, float2{0,0}), float4(0)));
    XCTAssertTrue(equal(applyPaint(p, float2{0,1}), float4(1)));

    p = makeLinearGradient(float2{1,0}, float2{2,0}, float4(0), float4(1));
    XCTAssertTrue(equal(applyPaint(p, float2{0,0}), float4(0)));
    XCTAssertTrue(equal(applyPaint(p, float2{1,0}), float4(0)));
    XCTAssertTrue(equal(applyPaint(p, float2{1.5,0}), float4(.5)));
    XCTAssertTrue(equal(applyPaint(p, float2{2,0}), float4(1)));
    XCTAssertTrue(equal(applyPaint(p, float2{3,0}), float4(1)));

    p = makeLinearGradient(float2{1,2}, float2{2,3}, float4(0), float4(1));
    XCTAssertTrue(equal(applyPaint(p, float2{1,2}), float4(0)));
    XCTAssertTrue(equal(applyPaint(p, float2{2,3}), float4(1)));

    p = makeLinearGradient(float2{400,100}, float2{450, 150}, float4{0,1,1,1}, float4{1,0,1,1});
    XCTAssertTrue(simd_length(applyPaint(p, float2{400,100}) - float4{0,1,1,1}) < 0.001f);

    auto c = applyPaint(p, float2{425,125});
    XCTAssertTrue(simd_length(c - float4{.5,.5,1,1}) < 0.001f);
    XCTAssertTrue(equal(applyPaint(p, float2{450,150}), float4{1,0,1,1}));

    p = makeImagePattern(float2{10,10}, float2{10,10}, 0, {1}, 1.0);

    auto v = p.xform * float3{10,10,1};
    XCTAssertTrue(equal(v, float3{0,0,1}));

    v = p.xform * float3{20,20,1};
    XCTAssertTrue(equal(v, float3{1,1,1}));

}

- (void) testTextAlgin {

    auto vger = vgerNew(0);

    vgerBegin(vger, 512, 512, 1.0);

    auto str = "This is center middle aligned.";

    auto commandBuffer = [queue commandBuffer];

    vgerSave(vger);
    vgerTranslate(vger, float2{256, 256});
    vgerScale(vger, float2{2,2});

    float2 cvs[2];
    vgerTextBounds(vger, str, cvs, cvs+1, VGER_ALIGN_CENTER | VGER_ALIGN_MIDDLE);
    vgerFillRect(vger, cvs[0], cvs[1], 0, vgerColorPaint(vger, float4{.2,.2,.2,1.0}));

    auto magenta = vgerColorPaint(vger, float4{1,0,1,1.0});
    vgerFillCircle(vger, float2{0,0}, 1, magenta);

    vgerText(vger, str, float4(1), VGER_ALIGN_CENTER | VGER_ALIGN_MIDDLE);
    vgerRestore(vger);

    [self render:vger name:@"test_align.png"];

    vgerDelete(vger);

}

- (void) testPathFill {

    int w = 512, h = 512;
    float2 sz = {float(w),float(h)};

    auto vger = vgerNew(0);

    vgerBegin(vger, w, h, 1.0);

    auto paint = vgerLinearGradient(vger, 0, sz, float4{0,1,1,1}, float4{1,0,1,1});
    auto start = sz * rand2();
    vgerMoveTo(vger, start);
    for(int i=0;i<10;++i) {
        vgerQuadTo(vger, sz * rand2(), sz * rand2());
    }
    vgerQuadTo(vger, sz * rand2(), start);
    vgerFill(vger, paint);

    [self render:vger name:@"path_fill.png"];

    vgerDelete(vger);

}

float2 circle(float theta) {
    return float2{cosf(theta), sinf(theta)};
}

void makeCircle(vgerContext vger, float2 center, float radius) {

    constexpr float n = 50;

    float step = 2*M_PI/float(n);
    float2 start = center + radius * float2{1,0};
    vgerMoveTo(vger, start);
    for(float i=1;i<n;++i) {
        vgerQuadTo(vger, center+radius*circle((i+.5)*step), center+radius*circle((i+1)*step));
    }

}

- (void) testPathFillCircle {

    int w = 512, h = 512;
    float2 sz = {float(w),float(h)};

    auto vger = vgerNew(0);

    vgerBegin(vger, w, h, 1.0);

    auto paint = vgerLinearGradient(vger, 0, sz, float4{0,1,1,1}, float4{1,0,1,1});

    makeCircle(vger, sz/2, 128);

    makeCircle(vger, sz/2, 64);

    vgerFill(vger, paint);

    [self render:vger name:@"path_fill_circle.png"];

    vgerDelete(vger);

}

- (void) testTextBox {

    auto vger = vgerNew(0);

    vgerBegin(vger, 512, 512, 1.0);

    auto str = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.";

    auto commandBuffer = [queue commandBuffer];

    vgerSave(vger);
    vgerTranslate(vger, float2{256, 256});

    float breakWidth = 200;

    float2 cvs[2];
    vgerTextBoxBounds(vger, str, breakWidth, cvs, cvs+1, 0);
    vgerFillRect(vger, cvs[0], cvs[1], 0, vgerColorPaint(vger, float4{.2,.2,.2,1.0}));

    vgerTextBox(vger, str, breakWidth, float4(1), 0);
    vgerRestore(vger);

    [self render:vger name:@"text_box.png"];

    vgerDelete(vger);

}

- (void) testTiger {

    auto tigerURL = [self getImageURL:@"Ghostscript_Tiger.svg"];

    auto image = nsvgParseFromFile(tigerURL.path.UTF8String, "px", 96);

    printf("size: %f x %f\n", image->width, image->height);

    auto vger = vgerNew(0);

    vgerBegin(vger, 512, 512, 1.0);

    vgerSave(vger);
    vgerTranslate(vger, float2{0, 512});
    vgerScale(vger, float2{0.5, -0.5});

    for (NSVGshape *shape = image->shapes; shape; shape = shape->next) {

        auto c = shape->fill.color;
        auto fcolor = float4{
            float((c >> 0) & 0xff),
            float((c >> 8) & 0xff),
            float((c >> 16) & 0xff),
            float((c >> 24) & 0xff)
        } * 1.0/255.0;

        auto paint = vgerColorPaint(vger, fcolor);

        for (NSVGpath *path = shape->paths; path; path = path->next) {
            float2* pts = (float2*) path->pts;
            vgerMoveTo(vger, pts[0]);
            for(int i=1; i<path->npts-2; i+=3) {
                vgerCubicApproxTo(vger, pts[i], pts[i+1], pts[i+2]);
            }
        }

        vgerFill(vger, paint);
    }
    vgerRestore(vger);
    // Delete
    nsvgDelete(image);

    [self render:vger name:@"tiger.png"];

    vgerDelete(vger);
}

- (void) testTigerPerf {

    auto tigerURL = [self getImageURL:@"Ghostscript_Tiger.svg"];

    auto image = nsvgParseFromFile(tigerURL.path.UTF8String, "px", 96);

    printf("size: %f x %f\n", image->width, image->height);

    auto vger = vgerNew(0);

    [self measureBlock:^{

        vgerBegin(vger, 512, 512, 1.0);

        vgerSave(vger);
        vgerTranslate(vger, float2{0, 512});
        vgerScale(vger, float2{0.5, -0.5});

        for (NSVGshape *shape = image->shapes; shape; shape = shape->next) {

            auto c = shape->fill.color;
            auto fcolor = float4{
                float((c >> 0) & 0xff),
                float((c >> 8) & 0xff),
                float((c >> 16) & 0xff),
                float((c >> 24) & 0xff)
            } * 1.0/255.0;

            auto paint = vgerColorPaint(vger, fcolor);

            for (NSVGpath *path = shape->paths; path; path = path->next) {
                float2* pts = (float2*) path->pts;
                vgerMoveTo(vger, pts[0]);
                for(int i=1; i<path->npts-2; i+=3) {
                    vgerCubicApproxTo(vger, pts[i], pts[i+1], pts[i+2]);
                }
            }

            vgerFill(vger, paint);
        }

        vgerRestore(vger);

        auto commandBuffer = [queue commandBuffer];

        vgerEncode(vger, commandBuffer, pass);

        // Sync texture on macOS
        #if TARGET_OS_OSX
        auto blitEncoder = [commandBuffer blitCommandEncoder];
        [blitEncoder synchronizeResource:texture];
        [blitEncoder endEncoding];
        #endif

        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];
    }];

    // Delete
    nsvgDelete(image);

    vgerDelete(vger);
}

static void printTileBuf(const Tile* tileBuf, const uint* tileLengthBuf) {

    assert(tileBuf);
    // Print out tile buffer contents.
    for(int y=31;y>=0;--y) {
        printf("%2d: ", y);
        for(int x=0;x<32;++x) {
            // printf("tile (%d, %d):\n", x, y);

            uint tileIx = y * MAX_TILES_WIDTH + x;
            const Tile& tile = tileBuf[tileIx];
            uint len = tileLengthBuf[tileIx];

            vgerOp op = *(vgerOp*) tile.commands;

            if(len == 0) {
                printf("      ");
            } else {
                printf(" %4d ", len);
            }
        }
        printf("\n");
    }
}

- (void) testBasicTileRender {

    XCTAssertEqual(sizeof(vgerCmdSegment), 24);
    XCTAssertEqual(sizeof(vgerCmdSolid), 8);

    auto vger = vgerNew(0);

    vgerBegin(vger, 512, 512, 1.0);

    vgerStrokeSegment(vger, float2{0,0}, float2{512,512}, 5, vgerColorPaint(vger, float4{1,0,1,1}));

    auto commandBuffer = [queue commandBuffer];

    vgerEncodeTileRender(vger, commandBuffer, texture);

    auto debugTexture = vgerGetCoarseDebugTexture(vger);

    // Sync texture on macOS
    #if TARGET_OS_OSX
    auto blitEncoder = [commandBuffer blitCommandEncoder];
    [blitEncoder synchronizeResource:texture];
    [blitEncoder synchronizeResource:debugTexture];
    [blitEncoder endEncoding];
    #endif

    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    showTexture(debugTexture, @"tile_debug.png");
    showTexture(texture, @"tile_render.png");

    printTileBuf((Tile*) [vger->tileRenderer getTileBuffer],
                 [vger->tileRenderer getTileLengthBuffer]);

}

- (void) testTileBlend {

    auto vger = vgerNew(0);

    vgerBegin(vger, 512, 512, 1.0);

    vgerStrokeSegment(vger, float2{128,128}, float2{384,384}, 5, vgerColorPaint(vger, float4{0,1,1,1}));
    vgerStrokeSegment(vger, float2{128,384}, float2{384,128}, 5, vgerColorPaint(vger, float4{1,1,0,1}));

    auto commandBuffer = [queue commandBuffer];

    vgerEncodeTileRender(vger, commandBuffer, texture);

    // Sync texture on macOS
    #if TARGET_OS_OSX
    auto blitEncoder = [commandBuffer blitCommandEncoder];
    [blitEncoder synchronizeResource:texture];
    [blitEncoder endEncoding];
    #endif

    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    showTexture(texture, @"tile_blend.png");

    printTileBuf((Tile*) [vger->tileRenderer getTileBuffer],
                 [vger->tileRenderer getTileLengthBuffer]);

}

- (void) testTileRoundRect {

    XCTAssertEqual(sizeof(vgerCmdSegment), 24);
    XCTAssertEqual(sizeof(vgerCmdSolid), 8);

    auto vger = vgerNew(0);

    vgerBegin(vger, 512, 512, 1.0);

    vgerFillRect(vger, float2{128,128}, float2{384,384}, 32, vgerColorPaint(vger, float4{1,0,1,1}));

    auto commandBuffer = [queue commandBuffer];

    vgerEncodeTileRender(vger, commandBuffer, texture);

    auto debugTexture = vgerGetCoarseDebugTexture(vger);

    // Sync texture on macOS
    #if TARGET_OS_OSX
    auto blitEncoder = [commandBuffer blitCommandEncoder];
    [blitEncoder synchronizeResource:texture];
    [blitEncoder synchronizeResource:debugTexture];
    [blitEncoder endEncoding];
    #endif

    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    showTexture(debugTexture, @"tile_debug.png");
    showTexture(texture, @"tile_render.png");

    printTileBuf((Tile*) [vger->tileRenderer getTileBuffer],
                 [vger->tileRenderer getTileLengthBuffer]);

}

- (void) testTilePath {

    XCTAssertEqual(sizeof(vgerCmdBezFill), 28);
    XCTAssertEqual(sizeof(vgerCmdLineFill), 20);

    int w = 512, h = 512;
    float2 sz = {float(w),float(h)};

    constexpr int n = 15;
    float2 cvs[n];
    for(int i=0;i<n-1;++i) {
        cvs[i] = sz * rand2();
    }
    cvs[n-1] = cvs[0];

    auto vger = vgerNew(0);

    vgerBegin(vger, w, h, 1.0);

    auto paint = vgerLinearGradient(vger, 0, sz, float4{0,1,1,1}, float4{1,0,1,1});

    auto start = sz * rand2();
    vgerMoveTo(vger, start);
    for(int i=0;i<10;++i) {
        vgerQuadTo(vger, sz * rand2(), sz * rand2());
    }
    vgerQuadTo(vger, sz * rand2(), start);
    vgerFillForTile(vger, paint);

    auto commandBuffer = [queue commandBuffer];

    vgerEncodeTileRender(vger, commandBuffer, texture);

    // Sync texture on macOS
    #if TARGET_OS_OSX
    auto blitEncoder = [commandBuffer blitCommandEncoder];
    [blitEncoder synchronizeResource:texture];
    [blitEncoder endEncoding];
    #endif

    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    printTileBuf((Tile*) [vger->tileRenderer getTileBuffer],
                 [vger->tileRenderer getTileLengthBuffer]);

    vgerDelete(vger);

    showTexture(texture, @"tile_path.png");

}

@end
