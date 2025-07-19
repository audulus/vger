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

float udBezierApproxGrad(float2 p, float2 A, float2 B, float2 C) {

    // Compute barycentric coordinates of p.
    // p = s * A + t * B + (1-s-t) * C
    float2 v0 = B - A, v1 = C - A, v2 = p - A;
    float det = v0.x * v1.y - v1.x * v0.y;
    float s = (v2.x * v1.y - v1.x * v2.y) / det;
    float t = (v0.x * v2.y - v2.x * v0.y) / det;

    // Transform to canonical coordinte space.
    float u = s * .5 + t;
    float v = t;

    float g = u*u - v;

    return abs(g / length(float2(dfdx(g), dfdy(g))));
}

float sdPrim(const DEVICE vgerPrim& prim, const DEVICE float2* cvs, float2 p, float filterWidth = 0) {
    float d = FLT_MAX;
    float s = 1;
    switch(prim.type) {
        case vgerBezier:
            d = sdBezierApprox(p, prim.cvs[0], prim.cvs[1], prim.cvs[2]) - prim.width;
            break;
        case vgerCircle:
            d = sdCircle(p - prim.cvs[0], prim.radius);
            break;
        case vgerArc:
            d = sdArc2(p - prim.cvs[0], prim.cvs[1], prim.cvs[2], prim.radius, prim.width/2);
            break;
        case vgerRect:
        case vgerGlyph: {
            auto center = .5*(prim.cvs[1] + prim.cvs[0]);
            auto size = prim.cvs[1] - prim.cvs[0];
            d = sdBox(p - center, .5*size, prim.radius);
        }
            break;
        case vgerRectStroke: {
            auto center = .5*(prim.cvs[1] + prim.cvs[0]);
            auto size = prim.cvs[1] - prim.cvs[0];
            d = abs(sdBox(p - center, .5*size, prim.radius)) - prim.width/2;
        }
            break;
        case vgerSegment:
            d = sdSegment2(p, prim.cvs[0], prim.cvs[1], prim.width);
            break;
        case vgerCurve:
            for(int i=0; i<prim.count; i++) {
                int j = prim.start + 3*i;
                d = min(d, sdBezierApprox(p, cvs[j], cvs[j+1], cvs[j+2]));
            }
            break;
        case vgerWire:
            d = sdWire(p, prim.cvs[0], prim.cvs[1]);
            break;
        case vgerPathFill:
            for(int i=0; i<prim.count; i++) {
                int j = prim.start + 3*i;
                auto a = cvs[j];
                auto b = cvs[j+1];
                auto c = cvs[j+2];

                d = min(d, udBezierApproxGrad(p, a, b, c));

                // Flip if inside area between curve and line.
                if(bezierTest(p, a, b, c)) {
                    s = -s;
                }

                if(lineTest(p, a, c)) {
                    s = -s;
                }

            }
            d *= s;
            break;
        default:
            break;
    }
    return d;
}

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
