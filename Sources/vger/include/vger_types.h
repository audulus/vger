//  Copyright © 2021 Audulus LLC. All rights reserved.

#ifndef vger_types_h
#define vger_types_h

/// VGER supports simple primitive types.
enum vgerPrimType {
    
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
    vgerWire
};

/// Primitive rendered by the GPU.
struct vgerPrim {
    
    /// Type of primitive.
    vgerPrimType type;

    /// Transform applied to drawing region.
#ifdef __METAL_VERSION__
    float3x3 xform;
#else
    matrix_float3x3 xform;
#endif

    /// Stroke width.
    float width;
    
    /// Radius of circles. Corner radius for rounded rectangles.
    float radius;
    
    /// Control vertices.
    vector_float2 cvs[16];
    
    /// Number of control vertices (only for vgerCurve)
    int count;
    
    /// Colors for gradients.
    vector_float4 colors[3];

    /// Read from texture?
    bool texture;

    /// Transform into texture.
#ifdef __METAL_VERSION__
    float3x3 txform;
#else
    matrix_float3x3 txform;
#endif

};

#endif /* vger_types_h */
