// Copyright © 2021 Audulus LLC. All rights reserved.

#include <metal_stdlib>
using namespace metal;

#include "include/vger.h"
#include "sdf.h"
#include "paint.h"

#define SQRT_2 1.414213562373095

struct VertexOut {
    float4 position  [[ position ]];
    float2 t;
    int primIndex;
};

/// Calculates bounds for prims.
kernel void vger_bounds(uint gid [[thread_position_in_grid]],
                        device vgerPrim* prims,
                        const device float2* cvs,
                        constant uint& primCount) {

    if(gid < primCount) {
        device auto& p = prims[gid];

        if(p.type != vgerGlyph and p.type != vgerPathFill) {

            auto bounds = sdPrimBounds(p, cvs).inset(-1);
            p.quadBounds[0] = p.texBounds[0] = bounds.min;
            p.quadBounds[1] = p.texBounds[1] = bounds.max;

        }
    }
}

/// Removes a prim if its texture region is outside the rendered geometry.
kernel void vger_prune(uint gid [[thread_position_in_grid]],
                       device vgerPrim* prims,
                       const device float2* cvs,
                       constant uint& primCount) {

    if(gid < primCount) {
        device auto& prim = prims[gid];

        auto center = 0.5 * (prim.texBounds[0] + prim.texBounds[1]);
        auto tile_size = prim.texBounds[1] - prim.texBounds[0];

        if(sdPrim(prim, cvs, center) > max(tile_size.x, tile_size.y) * 0.5 * SQRT_2) {
            float2 big = {FLT_MAX, FLT_MAX};
            prim.quadBounds[0] = big;
            prim.quadBounds[1] = big;
        }

    }
}

vertex VertexOut vger_vertex(uint vid [[vertex_id]],
                             uint iid [[instance_id]],
                             const device vgerPrim* prims,
                             const device float3x3* xforms,
                             constant float2& viewSize) {
    
    device auto& prim = prims[iid];
    
    VertexOut out;
    out.primIndex = iid;
    out.t = float2(prim.texBounds[vid & 1].x, prim.texBounds[vid >> 1].y);

    auto q = xforms[prim.xform] * float3(float2(prim.quadBounds[vid & 1].x,
                                                prim.quadBounds[vid >> 1].y),
                                         1.0);

    auto p = float2{q.x/q.z, q.y/q.z};
    out.position = float4(2.0 * p / viewSize - 1.0, 0, 1);
    
    return out;
}

float gridAlpha(float3 pos) {
    float aa = length(fwidth(pos));
    auto toGrid = abs(pos - round(pos));
    auto dist = min(toGrid.x, toGrid.y);
    return 0.5 * smoothstep(aa, 0, dist);
}

// Adapted from https://www.shadertoy.com/view/MtlcWX
inline float4 applyGrid(const device vgerPaint& paint, float2 p) {

    auto pos = paint.xform * float3{p.x, p.y, 1.0};
    float alpha = gridAlpha(pos);

    auto color = paint.innerColor;
    color.a *= alpha;
    return color;

}

fragment float4 vger_fragment(VertexOut in [[ stage_in ]],
                              const device vgerPrim* prims,
                              const device float2* cvs,
                              const device vgerPaint* paints,
                              constant bool& glow,
                              texture2d<float, access::sample> tex,
                              texture2d<float, access::sample> glyphs) {

    device auto& prim = prims[in.primIndex];
    device auto& paint = paints[prim.paint];

    if(prim.type == vgerGlyph) {

        constexpr sampler glyphSampler (mag_filter::linear,
                                          min_filter::linear,
                                          coord::pixel);

        auto c = paint.innerColor;
        auto color = float4(c.rgb, c.a * glyphs.sample(glyphSampler, in.t).a);

        if(glow) {
            color.a *= paint.glow;
        }

        return color;
    }

    float fw = length(fwidth(in.t));
    float d = sdPrim(prim, cvs, in.t, fw);

    //if(d > 2*sw) {
    //    discard_fragment();
    //}

    float4 color;

    if(paint.image == -1) {
        color = applyPaint(paint, in.t);
    } else if(paint.image == -2) {
        color = applyGrid(paint, in.t);
    } else {

        constexpr sampler textureSampler (mag_filter::linear,
                                          min_filter::linear);

        auto t = (paint.xform * float3(in.t,1)).xy;
        if(!paint.flipY) {
            t.y = 1.0 - t.y;
        }
        color = tex.sample(textureSampler, t);
        color.a *= paint.innerColor.a;
    }

    if(glow) {
        color.a *= paint.glow;
    }

    return mix(float4(color.rgb,0.0), color, 1.0-smoothstep(-fw/2,fw/2,d) );

}
