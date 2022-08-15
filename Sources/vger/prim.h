// Copyright © 2021 Audulus LLC. All rights reserved.

#ifndef prim_h
#define prim_h

/// VGER supports simple primitive types.
typedef enum {

    /// Filled circle.
    vgerCircle,

    /// Stroked arc.
    vgerArc,

    /// Rounded corner rectangle.
    vgerRect,

    /// Stroked rounded rectangle.
    vgerRectStroke,

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

/// Primitive rendered by the GPU.
typedef struct {

    /// Type of primitive.
    vgerPrimType type;

    /// Stroke width.
    float width;

    /// Radius of circles. Corner radius for rounded rectangles.
    float radius;

    /// Control vertices.
    vector_float2 cvs[3];

    /// Start of the control vertices, if they're in a separate buffer.
    uint32_t start;

    /// Number of control vertices (vgerCurve and vgerPathFill)
    uint16_t count;

    /// Index of paint applied to drawing region.
    uint32_t paint;

    /// Glyph region index. (used internally)
    uint32_t glyph;

    /// Index of transform applied to drawing region. (used internally)
    uint32_t xform;

    /// Min and max coordinates of the quad we're rendering. (used internally)
    vector_float2 quadBounds[2];

    /// Min and max coordinates in texture space. (used internally)
    vector_float2 texBounds[2];

} vgerPrim;

#endif /* prim_h */
