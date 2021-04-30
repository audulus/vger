//  Copyright © 2021 Audulus LLC.
//
// This software is provided 'as-is', without any express or implied
// warranty.  In no event will the authors be held liable for any damages
// arising from the use of this software.
// Permission is granted to anyone to use this software for any purpose,
// including commercial applications, and to alter it and redistribute it
// freely, subject to the following restrictions:
// 1. The origin of this software must not be misrepresented; you must not
//    claim that you wrote the original software. If you use this software
//    in a product, an acknowledgment in the product documentation would be
//    appreciated but is not required.
// 2. Altered source versions must be plainly marked as such, and must not be
//    misrepresented as being the original software.
// 3. This notice may not be removed or altered from any source distribution.
//

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
void vgerBegin(vger*, float windowWidth, float windowHeight, float devicePxRatio);

/// Create a texture to sample from.
int  vgerAddTexture(vger*, const uint8_t* data, int width, int height);

#ifdef __OBJC__
/// Add a texture from a MTLTexture. This copies image data from the texture instead of referencing
/// the texture.
int vgerAddMTLTexture(vger*, id<MTLTexture>);
#endif

/// Remove a texture.
void vgerDeleteTexture(vger* vg, int texID);

/// Get the size of a texture.
vector_int2 vgerTextureSize(vger* vg, int texID);

/// Render a prim.
void vgerRender(vger*, const vgerPrim* prim);

/// Render text.
void vgerRenderText(vger*, const char* str, vector_float4 color);

/// Return bounds for text in local coordinates.
void vgerTextBounds(vger* vg, const char* str, vector_float2* min, vector_float2* max);

/// Translates current coordinate system.
void vgerTranslate(vger*, vector_float2 t);

/// Scales current coordinate system.
void vgerScale(vger*, vector_float2 s);

/// Transforms a point according to the current transformation.
vector_float2 vgerTransform(vger*, vector_float2 p);

/// Returns current transformation matrix.
simd_float3x2 vgerCurrentTransform(vger*);

/// Pushes and saves the current transform onto a transform stack. A matching vgerRestore must
/// be used to restore the state.
void vgerSave(vger*);

/// Pops and restores the current transform.
void vgerRestore(vger*);

#ifdef __OBJC__
/// Encode drawing commands to a metal command buffer.
void vgerEncode(vger*, id<MTLCommandBuffer> buf, MTLRenderPassDescriptor* pass);

/// For debugging.
id<MTLTexture> vgerGetGlyphAtlas(vger*);
#endif

/// Create a paint for a constant color.
vgerPaint vgerColorPaint(vector_float4 color);

/// Create a paint for a linear gradient.
vgerPaint vgerLinearGradient(vector_float2 start, vector_float2 end,
                             vector_float4 innerColor, vector_float4 outerColor);

/// Create a paint using a texture image.
vgerPaint vgerImagePattern(vector_float2 origin, vector_float2 size, float angle,
                           int image, float alpha);

#ifdef __cplusplus
}
#endif

#endif /* vger_h */
