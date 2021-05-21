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

typedef struct vger *vgerContext;

/// Create a new state object.
vgerContext vgerNew();

/// Deallocate state object.
void vgerDelete(vgerContext);

/// Begin rendering a frame.
void vgerBegin(vgerContext, float windowWidth, float windowHeight, float devicePxRatio);

/// Create a texture to sample from.
int  vgerAddTexture(vgerContext, const uint8_t* data, int width, int height);

#ifdef __OBJC__
/// Add a texture from a MTLTexture. This copies image data from the texture instead of referencing
/// the texture.
int vgerAddMTLTexture(vgerContext, id<MTLTexture>);
#endif

/// Remove a texture.
void vgerDeleteTexture(vgerContext, int texID);

/// Get the size of a texture.
vector_int2 vgerTextureSize(vgerContext, int texID);

/// Render a prim.
void vgerRender(vgerContext, const vgerPrim* prim);

/// Render text.
void vgerText(vgerContext, const char* str, vector_float4 color, int align);

/// Return bounds for text in local coordinates.
void vgerTextBounds(vgerContext, const char* str, vector_float2* min, vector_float2* max, int align);

/// Renders multi-line text.
void vgerTextBox(vgerContext, const char* str, float breakRowWidth, vector_float4 color, int align);

/// Returns bounds of multi-line text.
void vgerTextBoxBounds(vgerContext, const char* str, float breakRowWidth, vector_float2* min, vector_float2* max, int align);

/// Fill a path bounded by quadratic bezier segments.
void vgerFillPath(vgerContext, vector_float2* cvs, int count, uint16_t paint, bool scan);

/// Fill a path bounded by cubic bezier segments (crude approximation)).
void vgerFillCubicPath(vgerContext vg, vector_float2* cvs, int count, uint16_t paint, bool scan);

/// Translates current coordinate system.
void vgerTranslate(vgerContext, vector_float2 t);

/// Scales current coordinate system.
void vgerScale(vgerContext, vector_float2 s);

/// Transforms a point according to the current transformation.
vector_float2 vgerTransform(vgerContext, vector_float2 p);

/// Returns current transformation matrix.
simd_float3x2 vgerCurrentTransform(vgerContext);

/// Pushes and saves the current transform onto a transform stack. A matching vgerRestore must
/// be used to restore the state.
void vgerSave(vgerContext);

/// Pops and restores the current transform.
void vgerRestore(vgerContext);

#ifdef __OBJC__
/// Encode drawing commands to a metal command buffer.
void vgerEncode(vgerContext, id<MTLCommandBuffer> buf, MTLRenderPassDescriptor* pass);

/// Experimental!
void vgerEncodeTileRender(vgerContext vg, id<MTLCommandBuffer> buf, id<MTLTexture> renderTexture);

/// For debugging.
id<MTLTexture> vgerGetGlyphAtlas(vgerContext);

/// For debugging.
id<MTLTexture> vgerGetCoarseDebugTexture(vgerContext);
#endif

/// Create a paint for a constant color. Returns paint index. Paints are cleared each frame.
uint16_t vgerColorPaint(vgerContext vg, vector_float4 color);

/// Create a paint for a linear gradient. Returns paint index. Paints are cleared each frame.
uint16_t vgerLinearGradient(vgerContext vg, vector_float2 start, vector_float2 end,
                             vector_float4 innerColor, vector_float4 outerColor);

/// Create a paint using a texture image. Returns paint index. Paints are cleared each frame.
uint16_t vgerImagePattern(vgerContext vg, vector_float2 origin, vector_float2 size, float angle,
                           int image, float alpha);

#ifdef __cplusplus
}
#endif

#endif /* vger_h */
