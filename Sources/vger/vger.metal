// Copyright © 2021 Audulus LLC. All rights reserved.

#include <metal_stdlib>
using namespace metal;

#include "include/vger_types.h"
#include "sdf.h"

#define SQRT_2 1.414213562373095

struct VertexOut {
    float4 position  [[ position ]];
    float2 p;
    float2 t;
    int primIndex;
};

kernel void vger_prune(uint gid [[thread_position_in_grid]],
                       device vgerPrim* prims,
                       constant uint& primCount) {

    if(gid < primCount) {
        device auto& prim = prims[gid];

        if(prim.type == vgerBezier or prim.type == vgerCurve) {

            auto center = 0.5 * (prim.texcoords[0] + prim.texcoords[3]);
            auto tile_size = prim.texcoords[3] - prim.texcoords[0];

            if(sdPrim(prim, center) > max(tile_size.x, tile_size.y) * 0.5 * SQRT_2) {
                float2 big = {FLT_MAX, FLT_MAX};
                prim.verts[0] = big;
                prim.verts[1] = big;
                prim.verts[2] = big;
                prim.verts[3] = big;
            }

        }
    }
}

kernel void vger_bounds(uint gid [[thread_position_in_grid]],
                        device vgerPrim* prims,
                        const device float2* cvs,
                        constant uint& primCount) {

    if(gid < primCount) {
        device auto& p = prims[gid];

        if(p.type != vgerGlyph) {

            auto bounds = sdPrimBounds(p, cvs).inset(-1);
            p.texcoords[0] = bounds.min;
            p.texcoords[1] = float2{bounds.max.x, bounds.min.y};
            p.texcoords[2] = float2{bounds.min.x, bounds.max.y};
            p.texcoords[3] = bounds.max;

            for(int i=0;i<4;++i) {
                p.verts[i] = p.texcoords[i];
            }

        }
    }
}

vertex VertexOut vger_vertex(uint vid [[vertex_id]],
                             uint iid [[instance_id]],
                             const device vgerPrim* prims,
                             constant float2& viewSize) {
    
    device auto& prim = prims[iid];
    
    VertexOut out;
    out.primIndex = iid;

    auto q = prim.xform * float3(prim.verts[vid], 1.0);

    out.p = float2{q.x/q.z, q.y/q.z};
    out.t = prim.texcoords[vid];
    out.position = float4(2.0 * out.p / viewSize - 1.0, 0, 1);
    
    return out;
}

fragment float4 vger_fragment(VertexOut in [[ stage_in ]],
                              const device vgerPrim* prims,
                              const device float2* cvs,
                              texture2d<float, access::sample> tex,
                              texture2d<float, access::sample> glyphs) {

    device auto& prim = prims[in.primIndex];



    if(prim.type == vgerGlyph) {

        constexpr sampler glyphSampler (mag_filter::linear,
                                          min_filter::linear,
                                          coord::pixel);

        auto c = prim.paint.innerColor;
        return float4(c.rgb, c.a * glyphs.sample(glyphSampler, in.t).a);
    }
    
    float d = sdPrim(prim, in.t);

    //if(d > 2*sw) {
    //    discard_fragment();
    //}

    float4 color;

    if(prim.paint.image == -1) {
        color = applyPaint(prim.paint, in.t);
    } else {

        constexpr sampler textureSampler (mag_filter::linear,
                                          min_filter::linear);

        auto t = (prim.paint.xform * float3(in.t,1)).xy;
        t.y = 1.0 - t.y;
        color = tex.sample(textureSampler, t);
    }

    if(prim.type == vgerPathFill) {
        int n = 0;
        for(int i=0; i<prim.count; i++) {
            int j = prim.start + 3*i;
            n += bezierTest(cvs[j], cvs[j+1], cvs[j+2], in.t);
        }
        // XXX: no AA!
        return n % 2 ? color : 0;
    }

    float fw = length(fwidth(in.t));
    return mix(float4(color.rgb,0.1), color, 1.0-smoothstep(0,fw,d) );

}
