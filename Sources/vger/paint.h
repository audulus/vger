//  Copyright © 2021 Audulus LLC. All rights reserved.

#pragma once

#include "metal_compat.h"

enum vgerPaintType {
    vgerPaintTypeLinearGradient,
    vgerPaintTypeRadialGradient,
    vgerPaintTypeImagePattern,
};

struct vgerPaint {

    vgerPaintType type;

#ifdef __METAL_VERSION__
    float3x3 xform;
#else
    matrix_float3x3 xform;
#endif

    float4 innerColor;

    float4 outerColor;

    /// Inner radius for radial gradients.
    float innerRadius;

    /// Inner radius for radial gradients.
    float outerRadius;

    /// Render into the glow layer?
    float glow;

    /// Image if we're texturing.
    int32_t image;

    /// Flip Y coordinate?
    bool flipY;

};

inline float4 applyPaint(const DEVICE vgerPaint& paint, float2 p) {

    switch (paint.type) {
        case vgerPaintTypeLinearGradient:
        {
            float d = clamp((paint.xform * float3{p.x, p.y, 1.0}).x, 0.0, 1.0);
            return mix(paint.innerColor, paint.outerColor, d);
        }
        case vgerPaintTypeRadialGradient:
        {
            float d = clamp(length( (paint.xform * float3{p.x, p.y, 1.0}).xy), paint.innerRadius, paint.outerRadius);
            return mix(paint.innerColor, paint.outerColor, (d-paint.innerRadius) / (paint.outerRadius - paint.innerRadius));
        }
        default:
            return 0;
    }

}
