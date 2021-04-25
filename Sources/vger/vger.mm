//  Copyright © 2021 Audulus LLC. All rights reserved.

#import "vger.h"
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <Cocoa/Cocoa.h>
#import "vgerRenderer.h"
#import "vgerTextureManager.h"
#import "vgerGlyphCache.h"
#include <vector>

using namespace simd;

#define MAX_PRIMS 4096

struct vger {

    id<MTLDevice> device;
    vgerRenderer* renderer;
    std::vector<matrix_float3x3> txStack;
    id<MTLBuffer> prims[3];
    int curPrims = 0;
    vgerPrim* p;
    int primCount = 0;
    vgerTextureManager* texMgr;
    vgerGlyphCache* glyphCache;

    vger() {
        device = MTLCreateSystemDefaultDevice();
        renderer = [[vgerRenderer alloc] initWithDevice:device];
        texMgr = [[vgerTextureManager alloc] initWithDevice:device pixelFormat:MTLPixelFormatRGBA8Unorm];
        glyphCache = [[vgerGlyphCache alloc] initWithDevice:device];
        for(int i=0;i<3;++i) {
            prims[i] = [device newBufferWithLength:MAX_PRIMS*sizeof(vgerPrim) options:MTLResourceStorageModeShared];
        }
        txStack.push_back(matrix_identity_float3x3);
    }
};

vger* vgerNew() {
    return new vger;
}

void vgerDelete(vger* vg) {
    delete vg;
}

void vgerBegin(vger* vg) {
    vg->curPrims = (vg->curPrims+1)%3;
    vg->p = (vgerPrim*) vg->prims[vg->curPrims].contents;
    vg->primCount = 0;
}

int  vgerAddTexture(vger* vg, const uint8_t* data, int width, int height) {
    assert(data);
    return [vg->texMgr addRegion:data width:width height:height bytesPerRow:width*sizeof(uint32)];
}

int vgerAddMTLTexture(vger* vg, id<MTLTexture> tex) {
    assert(tex);
    return [vg->texMgr addRegion:tex];
}

void vgerRender(vger* vg, const vgerPrim* prim) {
    if(vg->primCount < MAX_PRIMS) {
        *vg->p = *prim;
        vg->p->xform = vg->txStack.back();
        vg->p++;
        vg->primCount++;
    }
}

void vgerRenderText(vger* vg, const char* str, float4 color) {

    CFRange entire = CFRangeMake(0, 0);

    NSDictionary *attributes = @{ NSFontAttributeName : (__bridge id)[vg->glyphCache getFont] };
    NSString* string = [NSString stringWithUTF8String:str];
    NSAttributedString *attrString = [[NSAttributedString alloc] initWithString:string attributes:attributes];
    auto typesetter = CTTypesetterCreateWithAttributedString((__bridge CFAttributedStringRef)attrString);
    auto line = CTTypesetterCreateLine(typesetter, CFRangeMake(0, attrString.length));

    NSArray* runs = (__bridge id) CTLineGetGlyphRuns(line);
    for(id r in runs) {
        CTRunRef run = (__bridge CTRunRef)r;
        size_t glyphCount = CTRunGetGlyphCount(run);

        CGGlyph glyphs[glyphCount];
        CTRunGetGlyphs(run, entire, glyphs);

        CGPoint positions[glyphCount];
        CTRunGetPositions(run, entire, positions);

        for(int i=0;i<glyphCount;++i) {

            auto info = [vg->glyphCache getGlyph:glyphs[i] size:12];
            if(info.regionIndex != -1) {

                CGRect r = CTRunGetImageBounds(run, nil, CFRangeMake(i, 1));
                float2 p = {float(r.origin.x), float(r.origin.y)};
                float2 sz = {float(r.size.width), float(r.size.height)};

                vgerPrim prim = {
                    .type = vgerRect,
                    .paint = vgerGlyph,
                    .texture = info.regionIndex,
                    .cvs = {p, p+sz},
                    .xform=matrix_identity_float3x3,
                    .txform=matrix_identity_float3x3,
                    .width = 0.01,
                    .radius = 0,
                    .colors = {color, 0, 0},
                };

                prim.txform.columns[0].x = info.glyphSize.width;
                prim.txform.columns[1].y = info.glyphSize.height;

                vgerRender(vg, &prim);
            }
        }
    }

    CFRelease(typesetter);
    CFRelease(line);

}

void vgerEncode(vger* vg, id<MTLCommandBuffer> buf, MTLRenderPassDescriptor* pass) {
    
    [vg->texMgr update:buf];
    [vg->glyphCache update:buf];

    auto texRects = [vg->texMgr getRects];
    auto glyphRects = [vg->glyphCache getRects];
    auto primp = (vgerPrim*) vg->prims[vg->curPrims].contents;
    for(int i=0;i<vg->primCount;++i) {
        auto& prim = primp[i];
        if(prim.paint == vgerTexture) {
            auto M = matrix_identity_float3x3;
            auto r = texRects[prim.texture-1];
            M.columns[0].x = r.w;
            M.columns[1].y = r.h;
            M.columns[2] = float3{float(r.x), float(r.y), 1.0f};
            prim.txform = M;
        } else if(prim.paint == vgerGlyph) {
            auto r = glyphRects[prim.texture-1];
            prim.txform.columns[2] = float3{float(r.x+GLYPH_MARGIN), float(r.y+GLYPH_MARGIN), 1.0f};
        }
    }

    [vg->renderer encodeTo:buf
                      pass:pass
                     prims:vg->prims[vg->curPrims]
                     count:vg->primCount
                   texture:vg->texMgr.atlas
              glyphTexture:[vg->glyphCache getAltas]];
}

void vgerTranslate(vger* vg, vector_float2 t) {
    auto M = matrix_identity_float3x3;
    M.columns[2] = vector3(t, 1);

    auto& A = vg->txStack.back();
    A = matrix_multiply(A, M);
}

/// Scales current coordinate system.
void vgerScale(vger* vg, vector_float2 s) {
    auto M = matrix_identity_float3x3;
    M.columns[0].x = s.x;
    M.columns[1].y = s.y;

    auto& A = vg->txStack.back();
    A = matrix_multiply(A, M);
}

/// Transforms a point according to the current transformation.
vector_float2 vgerTransform(vger* vg, vector_float2 p) {
    auto& M = vg->txStack.back();
    auto q = matrix_multiply(M, float3{p.x,p.y,1.0});
    return {q.x/q.z, q.y/q.z};
}

void vgerSave(vger* vg) {
    vg->txStack.push_back(vg->txStack.back());
}

void vgerRestore(vger* vg) {
    vg->txStack.pop_back();
    assert(!vg->txStack.empty());
}

id<MTLTexture> vgerGetGlyphAtlas(vger* vg) {
    return [vg->glyphCache getAltas];
}
