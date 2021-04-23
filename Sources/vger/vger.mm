//  Copyright © 2021 Audulus LLC. All rights reserved.

#import "vger.h"
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "vgerRenderer.h"
#import "vgerTextureManager.h"
#include <vector>

#define MAX_PRIMS 4096

struct vger {

    id<MTLDevice> device;
    vgerRenderer* renderer;
    std::vector<matrix_float3x3> txStack;
    id<MTLBuffer> prims[3];
    int curPrims = 0;
    vgerPrim* p;
    int primCount = 0;
    vgerTextureManager* txMgr;

    vger() {
        device = MTLCreateSystemDefaultDevice();
        renderer = [[vgerRenderer alloc] initWithDevice:device];
        txMgr = [[vgerTextureManager alloc] initWithDevice:device pixelFormat:MTLPixelFormatRGBA8Unorm];
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
    vg->curPrims++;
    vg->p = (vgerPrim*) vg->prims[vg->curPrims].contents;
    vg->primCount = 0;
}

int  vgerAddTexture(vger* vg, uint8_t* data, int width, int height) {
    assert(data);
    return [vg->txMgr addRegion:data width:width height:height bytesPerRow:width*sizeof(uint32)];
}

void vgerRender(vger* vg, const vgerPrim* prim) {
    if(vg->primCount < MAX_PRIMS) {
        *vg->p = *prim;
        vg->p->xform = vg->txStack.back();
        vg->p++;
        vg->primCount++;
    }
}

void vgerEncode(vger* vg, id<MTLCommandBuffer> buf, MTLRenderPassDescriptor* pass) {
    [vg->txMgr update:buf];
    [vg->renderer encodeTo:buf
                      pass:pass
                     prims:vg->prims[vg->curPrims]
                     count:vg->primCount
                   texture:vg->txMgr.atlas];
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

void vgerSave(vger* vg) {
    vg->txStack.push_back(vg->txStack.back());
}

void vgerRestore(vger* vg) {
    vg->txStack.pop_back();
    assert(!vg->txStack.empty());
}
