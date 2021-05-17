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

auto white = vgerColorPaint(float4{1,1,1,1});
auto cyan = vgerColorPaint(float4{0,1,1,1});
auto magenta = vgerColorPaint(float4{1,0,1,1});

- (void) testBasic {

    float theta = 0;
    float ap = .5 * M_PI;

    vgerPrim primArray[] = {
        // { .type = vgerBezier, .cvs = {0, {0,0.5}, {0.5,0.5}}, .colors = {{1,1,1,.5}, 0, 0}},
        {
            .type = vgerCircle,
            .width = 10,
            .radius = 40,
            .cvs = {256, 256},
            .paint = cyan
        },
        {
            .type = vgerBezier,
            .width = 1,
            .cvs = {{256,256}, {256,384}, {384,384}},
            .paint = white,
        },
        {
            .type = vgerSegment,
            .width = 10,
            .cvs = {{100,100}, {200,200}},
            .paint = magenta,
        },
        {
            .type = vgerRect,
            .width = 0.01,
            .cvs = {{400,100}, {450,150}},
            .radius= 10,
            .paint = vgerLinearGradient(float2{400,100}, float2{450, 150}, float4{0,1,1,1}, float4{1,0,1,1})
        },
        {
            .type = vgerRectStroke,
            .width = 2.0,
            .cvs = {{400,100}, {450,150}},
            .radius= 10,
            .paint = magenta
        },
        {
            .type = vgerArc,
            .width = 3,
            .cvs = {{100, 400}, {sin(theta), cos(theta)}, {sin(ap), cos(ap)}},
            .radius= 30,
            .paint = white
        },
        {
            .type = vgerWire,
            .width = 3,
            .cvs = {{200, 100}, {300, 200}},
            .paint = white
        }
    };

    auto vg = vgerNew();

    vgerBegin(vg, 512, 512, 1.0);

    for(int i=0;i< (sizeof(primArray)/sizeof(vgerPrim)); ++i) {
        vgerRender(vg, primArray+i);
    }

    vgerSave(vg);
    vgerScale(vg, float2{100, 100});
    float2 cvs2[] = {0, {1,0}, {1,1}, {0,1}, {0, 2} };
    vgerFillPath(vg, cvs2, 5, white);
    vgerRestore(vg);

    [self checkRender:vg name:@"vger_basics.png"];

    vgerDelete(vg);

}

- (void) testTransformStack {

    auto vger = vgerNew();

    vgerBegin(vger, 512, 512, 1.0);

    vgerPrim p = {
        .type = vgerCircle,
        .width = 0.00,
        .radius = 10,
        .cvs = { {20, 20}},
        .paint = cyan
    };

    XCTAssertTrue(simd_equal(vgerTransform(vger, float2{0,0}), float2{0, 0}));

    vgerRender(vger, &p);

    vgerSave(vger);
    vgerTranslate(vger, float2{100,0.0f});
    vgerTranslate(vger, float2{0.0f,100});
    vgerScale(vger, float2{4.0f, 4.0f});
    vgerRender(vger, &p);

    vgerRestore(vger);

    [self render:vger name:@"xform.png"];

    vgerDelete(vger);
}

- (void) testRects {

    auto vger = vgerNew();
    assert(vger);

    vgerBegin(vger, 512, 512, 1.0);

    vgerSave(vger);

    vgerPrim p = {
        .type = vgerRect,
        .width = 0.01,
        .cvs = { {20,20}, {40,40}},
        .radius=0.3,
        .paint = white
    };

    for(int i=0;i<10;++i) {
        vgerRender(vger, &p);
        p.cvs[0].x += 40;
        p.cvs[1].x += 40;
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

    auto vger = vgerNew();

    vgerBegin(vger, 512, 512, 1.0);

    auto tex = [self getTexture:@"icon-mac-256.png"];
    auto idx = vgerAddMTLTexture(vger, tex);

    auto sz = vgerTextureSize(vger, idx);
    XCTAssert(simd_equal(sz, simd_int2(256)));

    vgerPrim p = {
        .type = vgerRect,
        .width = 0.01,
        .cvs = { {0,0}, {256,256}},
        .radius=0.3,
        .paint = vgerImagePattern(float2{0,0}, float2{256,256}, 0, idx, 1),
    };

    vgerRender(vger, &p);

    auto commandBuffer = [queue commandBuffer];

    vgerEncode(vger, commandBuffer, pass);

    [self render:vger name:@"texture.png"];

    vgerDelete(vger);
}

- (void) testText {

    auto vger = vgerNew();

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

    auto vger = vgerNew();

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

    std::vector<vgerPrim> primArray;

    int N = 10000;

    for(int i=0;i<N;++i) {
        vgerPrim p = {
            .type = vgerBezier,
            .width = 1,
            .cvs ={ 512*rand2(), 512*rand2(), 512*rand2() },
            .paint = vgerColorPaint(rand_color()),
        };
        primArray.push_back(p);
    }

    auto vger = vgerNew();

    [self measureBlock:^{

        vgerBegin(vger, 512, 512, 1.0);

        for(int i=0;i<primArray.size();++i) {
           vgerRender(vger, &primArray[i]);
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

    std::vector<vgerPrim> primArray;

    int N = 10000;

    for(int i=0;i<N;++i) {
        simd_float2 cvs[3] = { 512*rand2(), 512*rand2(), 512*rand2() };
        auto c = vgerColorPaint(rand_color());
        vgerPrim p[2] = {
            {
                .type = vgerBezier,
                .width = 0.01,
                .paint = c
            },
            {
                .type = vgerBezier,
                .width = 0.01,
                .paint = c
            }
        };
        SplitBezier(.5, cvs, p[0].cvs, p[1].cvs);
        primArray.push_back(p[0]);
        primArray.push_back(p[1]);
    }

    auto vger = vgerNew();

    [self measureBlock:^{

        vgerBegin(vger, 512, 512, 1.0);

        for(int i=0;i<2*N;++i) {
            vgerRender(vger, &primArray[i]);
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

    system([NSString stringWithFormat:@"open %@", tmpURL.path].UTF8String);
}

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

    auto vger = vgerNew();

    vgerBegin(vger, 512, 512, 1.0);

    vgerSave(vger);

    vgerPrim bez = {
        .type = vgerBezier,
        .width = 1.0,
        .cvs = {{50, 450}, {100,450}, {100,500}},
        .paint = vgerLinearGradient(float2{50,450}, float2{100,450}, cyan, magenta)
    };

    vgerRender(vger, &bez);
    textAt(vger, 150, 450, "Quadratic Bezier stroke");

    vgerPrim rect = {
        .type = vgerRect,
        .width = 0.0,
        .radius = 10,
        .cvs = {{50, 350}, {100,400}},
        .paint = vgerLinearGradient(float2{50,350}, float2{100,400}, cyan, magenta)
    };
    vgerRender(vger, &rect);
    textAt(vger, 150, 350, "Rounded rectangle");

    vgerPrim circle = {
        .type = vgerCircle,
        .width = 0.0,
        .radius = 25,
        .cvs = {{75, 275}},
        .paint = vgerLinearGradient(float2{50,250}, float2{100,300}, cyan, magenta)
    };
    vgerRender(vger, &circle);
    textAt(vger, 150, 250, "Circle");

    vgerPrim line = {
        .type = vgerSegment,
        .width = 2.0,
        .cvs = {{50, 150}, {100,200}},
        .paint = vgerLinearGradient(float2{50,150}, float2{100,200}, cyan, magenta)
    };
    vgerRender(vger, &line);
    textAt(vger, 150, 150, "Line segment");

    float theta = 0;      // orientation
    float ap = .5 * M_PI; // aperture size
    vgerPrim arc = {
        .type = vgerArc,
        .width = 1.0,
        .cvs = {{75, 75}, {sin(theta), cos(theta)}, {sin(ap), cos(ap)}},
        .radius=25,
        .paint = vgerLinearGradient(float2{50,50}, float2{100,100}, cyan, magenta)
    };
    vgerRender(vger, &arc);
    textAt(vger, 150, 050, "Arc");

    vgerRestore(vger);

    [self render:vger name:@"demo.png"];

    vgerDelete(vger);

}

- (void) testPaint {

    auto p = vgerColorPaint(float4{.1,.2,.3,.4});

    auto c = applyPaint(p, float2{5,7});

    XCTAssertTrue(simd_equal(c, float4{.1,.2,.3,.4}));

    p = vgerLinearGradient(float2{0,0}, float2{1,0}, float4(0), float4(1));

    XCTAssertTrue(simd_equal(applyPaint(p, float2{0,0}), float4(0)));
    XCTAssertTrue(simd_equal(applyPaint(p, float2{.5,0}), float4(.5)));
    XCTAssertTrue(simd_equal(applyPaint(p, float2{1,0}), float4(1)));

    p = vgerLinearGradient(float2{0,0}, float2{0,1}, float4(0), float4(1));

    XCTAssertTrue(simd_equal(applyPaint(p, float2{0,0}), float4(0)));
    XCTAssertTrue(simd_equal(applyPaint(p, float2{0,1}), float4(1)));

    p = vgerLinearGradient(float2{1,0}, float2{2,0}, float4(0), float4(1));
    XCTAssertTrue(simd_equal(applyPaint(p, float2{0,0}), float4(0)));
    XCTAssertTrue(simd_equal(applyPaint(p, float2{1,0}), float4(0)));
    XCTAssertTrue(simd_equal(applyPaint(p, float2{1.5,0}), float4(.5)));
    XCTAssertTrue(simd_equal(applyPaint(p, float2{2,0}), float4(1)));
    XCTAssertTrue(simd_equal(applyPaint(p, float2{3,0}), float4(1)));

    p = vgerLinearGradient(float2{1,2}, float2{2,3}, float4(0), float4(1));
    XCTAssertTrue(simd_equal(applyPaint(p, float2{1,2}), float4(0)));
    XCTAssertTrue(simd_equal(applyPaint(p, float2{2,3}), float4(1)));

    p = vgerLinearGradient(float2{400,100}, float2{450, 150}, float4{0,1,1,1}, float4{1,0,1,1});
    XCTAssertTrue(simd_length(applyPaint(p, float2{400,100}) - float4{0,1,1,1}) < 0.001f);

    c = applyPaint(p, float2{425,125});
    XCTAssertTrue(simd_length(c - float4{.5,.5,1,1}) < 0.001f);
    XCTAssertTrue(simd_equal(applyPaint(p, float2{450,150}), float4{1,0,1,1}));
}

- (void) testTextAlgin {

    auto vger = vgerNew();

    vgerBegin(vger, 512, 512, 1.0);

    auto str = "This is center middle aligned.";

    auto commandBuffer = [queue commandBuffer];

    vgerSave(vger);
    vgerTranslate(vger, float2{256, 256});
    vgerScale(vger, float2{2,2});

    float2 cvs[2];
    vgerTextBounds(vger, str, cvs, cvs+1, VGER_ALIGN_CENTER | VGER_ALIGN_MIDDLE);
    vgerPrim rect = {
        .type = vgerRect,
        .width = 0.0,
        .radius = 0,
        .cvs = {cvs[0], cvs[1]},
        .paint = vgerColorPaint(float4{.2,.2,.2,1.0})
    };
    vgerRender(vger, &rect);

    vgerPrim dot = {
        .type = vgerCircle,
        .radius = 1,
        .cvs = { {0,0} },
        .paint = magenta
    };
    vgerRender(vger, &dot);

    vgerText(vger, str, float4(1), VGER_ALIGN_CENTER | VGER_ALIGN_MIDDLE);
    vgerRestore(vger);

    [self render:vger name:@"test_align.png"];

    vgerDelete(vger);

}

- (void) testPathFill {

    int w = 512, h = 512;
    float2 sz = {float(w),float(h)};

    constexpr int n = 15;
    float2 cvs[n];
    for(int i=0;i<n-1;++i) {
        cvs[i] = sz * rand2();
    }
    cvs[n-1] = cvs[0];

    auto vger = vgerNew();

    vgerBegin(vger, w, h, 1.0);

    auto paint = vgerLinearGradient(0, sz, float4{0,1,1,1}, float4{1,0,1,1});
    vgerFillPath(vger, cvs, n, paint);

    [self render:vger name:@"path_fill.png"];

    vgerDelete(vger);

}

- (void) testPathFillCircle {

    int w = 512, h = 512;
    float2 sz = {float(w),float(h)};

    constexpr int n = 50;
    float2 cvs[n];
    for(int i=0;i<n;++i) {
        float theta = 2*M_PI*float(i)/float(n);
        cvs[i] = sz/2 + 128 * float2{cosf(theta), sinf(theta)};
    }

    auto vger = vgerNew();

    vgerBegin(vger, w, h, 1.0);

    auto paint = vgerLinearGradient(0, sz, float4{0,1,1,1}, float4{1,0,1,1});
    vgerFillPath(vger, cvs, n, paint);

    [self render:vger name:@"path_fill_circle.png"];

    vgerDelete(vger);

}

- (void) testTextBox {

    auto vger = vgerNew();

    vgerBegin(vger, 512, 512, 1.0);

    auto str = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.";

    auto commandBuffer = [queue commandBuffer];

    vgerSave(vger);
    vgerTranslate(vger, float2{256, 256});

    float breakWidth = 200;

    float2 cvs[2];
    vgerTextBoxBounds(vger, str, breakWidth, cvs, cvs+1, 0);
    vgerPrim rect = {
        .type = vgerRect,
        .width = 0.0,
        .radius = 0,
        .cvs = {cvs[0], cvs[1]},
        .paint = vgerColorPaint(float4{.2,.2,.2,1.0})
    };
    vgerRender(vger, &rect);

    vgerTextBox(vger, str, breakWidth, float4(1), 0);
    vgerRestore(vger);

    [self render:vger name:@"text_box.png"];

    vgerDelete(vger);

}

- (void) testTiger {

    auto tigerURL = [self getImageURL:@"Ghostscript_Tiger.svg"];

    auto image = nsvgParseFromFile(tigerURL.path.UTF8String, "px", 96);

    printf("size: %f x %f\n", image->width, image->height);

    auto vger = vgerNew();

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

        auto paint = vgerColorPaint(fcolor);

        for (NSVGpath *path = shape->paths; path; path = path->next) {
            vgerFillCubicPath(vger, (float2*) path->pts, path->npts, paint);
        }
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

    auto vger = vgerNew();

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

            auto paint = vgerColorPaint(fcolor);

            for (NSVGpath *path = shape->paths; path; path = path->next) {
                vgerFillCubicPath(vger, (float2*) path->pts, path->npts, paint);
            }
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

- (void) testBasicTileRender {

    auto vger = vgerNew();

    vgerBegin(vger, 512, 512, 1.0);

    vgerPrim segment {
        .type = vgerSegment,
        .cvs = { {10, 10}, {100, 100} },
        .width = 5,
        .paint = vgerColorPaint(float4{1,0,1,1})
    };

    vgerRender(vger, &segment);

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

    showTexture(texture, @"tile_render.png");
}

@end
