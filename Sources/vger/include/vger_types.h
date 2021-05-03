//  Copyright © 2021 Audulus LLC. All rights reserved.

#ifndef vger_types_h
#define vger_types_h

/// VGER supports simple primitive types.
typedef enum {
    
    /// Filled circle.
    vgerCircle,
    
    /// Stroked arc.
    vgerArc,
    
    /// Rounded corner rectangle.
    vgerRect,
    
    /// Single-segment quadratic bezier curve.
    vgerBezier,
    
    /// line segment
    vgerSegment,
    
    /// Multi-segment bezier curve.
    vgerCurve,

    /// Connection wire. See https://www.shadertoy.com/view/NdsXRl
    vgerWire,

    /// Text rendering.
    vgerGlyph,

    /// Path fills.
    vgerPathFill

} vgerPrimType;

typedef struct {

#ifdef __METAL_VERSION__
    float3x3 xform;
#else
    matrix_float3x3 xform;
#endif

    vector_float4 innerColor;

    vector_float4 outerColor;

    /// Image if we're texturing.
    int image;

} vgerPaint;

/// Primitive rendered by the GPU.
typedef struct {
    
    /// Type of primitive.
    vgerPrimType type;

    /// Stroke width.
    float width;
    
    /// Radius of circles. Corner radius for rounded rectangles.
    float radius;
    
    /// Control vertices.
    vector_float2 cvs[8];

    /// Start of the control vertices, if they're in a separate buffer.
    int start;
    
    /// Number of control vertices (only for vgerCurve)
    int count;

    /// How to shade the primitive.
    vgerPaint paint;
    
    /// Vertices of the quad we're rendering.
    vector_float2 verts[4];

    /// Transform applied to drawing region.
#ifdef __METAL_VERSION__
    float3x3 xform;
#else
    matrix_float3x3 xform;
#endif
    
    /// Texture coordinates of quad.
    vector_float2 texcoords[4];

} vgerPrim;

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

#endif /* vger_types_h */
