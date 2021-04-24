//  Copyright © 2021 Audulus LLC. All rights reserved.

#ifndef vger_h
#define vger_h

#include <simd/simd.h>
#include "vger_types.h"

#ifdef __OBJC__
#import <Metal/Metal.h>
#endif

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
int  vgerAddTexture(vger*, const uint8_t* data, int width, int height);

#ifdef __OBJC__
int vgerAddMTLTexture(vger*, id<MTLTexture>);
#endif

/// Render a prim.
void vgerRender(vger*, const vgerPrim* prim);

/// Render text.
void vgerRenderText(vger*, const char* str, vector_float4 color);

/// Translates current coordinate system.
void vgerTranslate(vger*, vector_float2 t);

/// Scales current coordinate system.
void vgerScale(vger*, vector_float2 s);

/// Transforms a point according to the current transformation.
vector_float2 vgerTransform(vger*, vector_float2 p);

/// Saves the render state.
void vgerSave(vger*);

/// Restores the render state.
void vgerRestore(vger*);

#ifdef __OBJC__
/// Encode drawing commands to a metal command buffer.
void vgerEncode(vger*, id<MTLCommandBuffer> buf, MTLRenderPassDescriptor* pass);

/// For debugging.
id<MTLTexture> vgerGetGlyphAtlas(vger*);
#endif

#ifdef __cplusplus
}
#endif

#endif /* vger_h */
