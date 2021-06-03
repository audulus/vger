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

#ifndef __METAL_VERSION__
#include <simd/simd.h>
#endif

/// Text alignment.
enum vgerAlign {
    // Horizontal align
    VGER_ALIGN_LEFT      = 1<<0, // Default, align text horizontally to left.
    VGER_ALIGN_CENTER    = 1<<1, // Align text horizontally to center.
    VGER_ALIGN_RIGHT     = 1<<2, // Align text horizontally to right.
    // Vertical align
    VGER_ALIGN_TOP       = 1<<3, // Align text vertically to top.
    VGER_ALIGN_MIDDLE    = 1<<4, // Align text vertically to middle.
    VGER_ALIGN_BOTTOM    = 1<<5, // Align text vertically to bottom.
    VGER_ALIGN_BASELINE  = 1<<6, // Default, align text vertically to baseline.
};

/// Type safety for paint indices.
typedef struct { uint16_t index; } vgerPaintIndex;

/// Type safety for image indices.
typedef struct { uint32_t index; } vgerImageIndex;

#ifndef __METAL_VERSION__

#ifdef __OBJC__
#import <Metal/Metal.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct vger *vgerContext;

#pragma mark - Context

enum vgerCreateFlags {
    // Flag indicating if double buffering scheme is used.
    VGER_DOUBLE_BUFFER = 1 << 0,

    // Flag indicating if triple buffering scheme is used.
    VGER_TRIPLE_BUFFER = 1 << 1,
};

/// Create a new state object.
vgerContext vgerNew(int flags);

/// Deallocate state object.
void vgerDelete(vgerContext);

/// Begin rendering a frame.
void vgerBegin(vgerContext, float windowWidth, float windowHeight, float devicePxRatio);

#pragma mark - Textures

/// Load an image from a file.
vgerImageIndex vgerCreateImage(vgerContext, const char* filename);

/// Create a texture to sample from.
vgerImageIndex  vgerAddTexture(vgerContext, const uint8_t* data, int width, int height);

#ifdef __OBJC__
/// Add a MTLTexture. This references the texture, so you can render to it, etc.
vgerImageIndex vgerAddMTLTexture(vgerContext, id<MTLTexture>);
#endif

/// Remove a texture.
void vgerDeleteTexture(vgerContext, vgerImageIndex texID);

/// Get the size of a texture.
vector_int2 vgerTextureSize(vgerContext, vgerImageIndex texID);

#pragma mark - Primitives

void vgerFillCircle(vgerContext, vector_float2 center, float radius, vgerPaintIndex paint);

void vgerStrokeArc(vgerContext, vector_float2 center, float radius, float width, float rotation, float aperture, vgerPaintIndex paint);

void vgerFillRect(vgerContext, vector_float2 min, vector_float2 max, float radius, vgerPaintIndex paint);

void vgerStrokeRect(vgerContext, vector_float2 min, vector_float2 max, float radius, float width, vgerPaintIndex paint);

typedef struct { vector_float2 a, b, c; } vgerBezierSegment;

void vgerStrokeBezier(vgerContext, vgerBezierSegment, float width, vgerPaintIndex paint);

void vgerStrokeSegment(vgerContext, vector_float2 a, vector_float2 b, float width, vgerPaintIndex paint);

void vgerStrokeWire(vgerContext, vector_float2 a, vector_float2 b, float width, vgerPaintIndex paint);

#pragma mark - Text

/// Render text.
void vgerText(vgerContext, const char* str, vector_float4 color, int align);

/// Return bounds for text in local coordinates.
void vgerTextBounds(vgerContext, const char* str, vector_float2* min, vector_float2* max, int align);

/// Renders multi-line text.
void vgerTextBox(vgerContext, const char* str, float breakRowWidth, vector_float4 color, int align);

/// Returns bounds of multi-line text.
void vgerTextBoxBounds(vgerContext, const char* str, float breakRowWidth, vector_float2* min, vector_float2* max, int align);

#pragma mark - Paths

/// Move the pen to a point.
void vgerMoveTo(vgerContext, vector_float2 pt);

/// Line.
void vgerLineTo(vgerContext, vector_float2 b);

/// Quadratic bezier.
void vgerQuadTo(vgerContext, vector_float2 b, vector_float2 c);

/// Crude approximation of cubic bezier with two quadratics.
void vgerCubicApproxTo(vgerContext vg, vector_float2 b, vector_float2 c, vector_float2 d);

/// Fills the current path (and clears the path).
void vgerFill(vgerContext, vgerPaintIndex paint);

/// Fills the current path (for experimental tile rendering).
void vgerFillForTile(vgerContext vg, vgerPaintIndex paint);

#pragma mark - Transforms

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

#pragma mark - Encoding

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

#pragma mark - Paints

/// Create a paint for a constant color. Returns paint index. Paints are cleared each frame.
vgerPaintIndex vgerColorPaint(vgerContext vg, vector_float4 color);

/// Create a paint for a linear gradient. Returns paint index. Paints are cleared each frame.
vgerPaintIndex vgerLinearGradient(vgerContext vg, vector_float2 start, vector_float2 end,
                                  vector_float4 innerColor, vector_float4 outerColor);

/// Create a paint using a texture image. Returns paint index. Paints are cleared each frame.
vgerPaintIndex vgerImagePattern(vgerContext vg, vector_float2 origin, vector_float2 size, float angle,
                                vgerImageIndex image, float alpha);

#ifdef __cplusplus
}
#endif

#endif // __METAL_VERSION__

#endif /* vger_h */
