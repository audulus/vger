//  Copyright © 2021 Audulus LLC. All rights reserved.

#ifndef paint_h
#define paint_h

#include "metal_compat.h"

struct vgerPaint {

#ifdef __METAL_VERSION__
    float3x3 xform;
#else
    matrix_float3x3 xform;
#endif

    float4 innerColor;

    float4 outerColor;

    /// Render into the glow layer?
    float glow;

    /// Image if we're texturing.
    int32_t image;

};

inline float4 applyPaint(const DEVICE vgerPaint& paint, float2 p) {

    float d = clamp((paint.xform * float3{p.x, p.y, 1.0}).x, 0.0, 1.0);

#ifdef __METAL_VERSION__
    return mix(paint.innerColor, paint.outerColor, d);
#else
    return simd_mix(paint.innerColor, paint.outerColor, d);
#endif

}

#endif /* paint_h */
