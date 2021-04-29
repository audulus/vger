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
    vgerGlyph
} vgerPrimType;

typedef struct {

#ifdef __METAL_VERSION__
    float3x3 xform;
#else
    matrix_float3x3 xform;
#endif

    vector_float4 innerColor;

    vector_float4 outerColor;

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
    
    /// Number of control vertices (only for vgerCurve)
    int count;

    /// How to shade the primitive.
    vgerPaint paint;

    /// The texture region.
    int texture;
    
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

#endif /* vger_types_h */
