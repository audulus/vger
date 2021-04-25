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
#import "sdf.h"

#define MAX_PRIMS 16384

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

void vgerBegin(vger* vg, float windowWidth, float windowHeight, float devicePxRatio) {
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

        auto bounds = sdPrimBounds(*prim).inset(-0.02);
        vg->p->verts[0] = vgerTransform(vg, bounds.min);
        vg->p->verts[1] = vgerTransform(vg, float2{bounds.max.x, bounds.min.y});
        vg->p->verts[2] = vgerTransform(vg, float2{bounds.min.x, bounds.max.y});
        vg->p->verts[3] = vgerTransform(vg, bounds.max);

        vg->p->cvs[0] = vgerTransform(vg, vg->p->cvs[0]);
        vg->p->cvs[1] = vgerTransform(vg, vg->p->cvs[1]);
        vg->p->cvs[2] = vgerTransform(vg, vg->p->cvs[2]);

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
                    .cvs = {p-1, p+sz+2},
                    .width = 0.01,
                    .radius = 0,
                    .colors = {color, 0, 0},
                };

                float w = info.glyphSize.width+2;
                float h = info.glyphSize.height+2;

                prim.texcoords[0] = float2{0,h};
                prim.texcoords[1] = float2{w,h};
                prim.texcoords[2] = float2{0,0};
                prim.texcoords[3] = float2{w,0};

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
            auto r = texRects[prim.texture-1];
            float w = r.w; float h = r.h;
            float2 t = float2{float(r.x), float(r.y)};

            prim.texcoords[0] = float2{0,h} + t;
            prim.texcoords[1] = float2{w,h} + t;
            prim.texcoords[2] = float2{0,0} + t;
            prim.texcoords[3] = float2{w,0} + t;

        } else if(prim.paint == vgerGlyph) {
            auto r = glyphRects[prim.texture-1];
            for(int i=0;i<4;++i) {
                prim.texcoords[i] += float2{float(r.x+GLYPH_MARGIN-1), float(r.y+GLYPH_MARGIN-1)};
            }
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
