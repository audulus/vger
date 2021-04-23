//  Copyright © 2021 Audulus LLC. All rights reserved.

#ifndef vger_h
#define vger_h

#include <simd/simd.h>
#include "vger_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct vger vger;

/// Create a new state object.
vger* vgerNew();

/// Deallocate state object.
void vgerDelete(vger*);

/// Begin rendering a frame.
void vgerBegin(vger*);

/// Create a texture to sample from.
int  vgerAddTexture(vger*, uint8_t* data, int width, int height);

/// Render a prim.
void vgerRender(vger*, const vgerPrim* prim);

/// Translates current coordinate system.
void vgerTranslate(vger*, vector_float2 t);

/// Scales current coordinate system.
void vgerScale(vger*, float x, float y);

/// Saves the render state.
void vgerSave(vger*);

/// Restores the render state.
void vgerRestore(vger*);

#ifdef __objc
/// Encode drawing commands to a metal command buffer.
void vgerEncode(vger*, id<MTLCommandBuffer> buf, MTLRenderPassDescriptor* pass);
#endif

#ifdef __cplusplus
}
#endif

#endif /* vger_h */
