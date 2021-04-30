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
                              texture2d<float, access::sample> tex,
                              texture2d<float, access::sample> glyphs) {

    device auto& prim = prims[in.primIndex];

    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear,
                                      coord::pixel);

    if(prim.type == vgerGlyph) {
        auto c = prim.paint.innerColor;
        return float4(c.rgb, c.a * glyphs.sample(textureSampler, in.t).a);
    }
    
    float d = sdPrim(prim, in.t);

    //if(d > 2*sw) {
    //    discard_fragment();
    //}

    float fw = length(fwidth(in.t));

    float4 color;

    if(prim.paint.image == -1) {
        color = applyPaint(prim.paint, in.t);
    } else {
        auto h = tex.get_height();
        auto t = (prim.paint.xform * float3(in.t,1)).xy;
        t.y = h - t.y;
        color = tex.sample(textureSampler, t);
    }

    return mix(float4(color.rgb,0.1), color, 1.0-smoothstep(0,fw,d) );

}

#define TILE_BUF_SIZE 4096
#define MAX_TILES_WIDTH 256
#define TILE_PIXEL_SIZE 16

enum vgerCmdType {
    vgerCmdEnd,
    vgerCmdBezier,
    vgerCmdRect,
    vgerCmdCircle,
    vgerCmdSegment
};

struct vgerCmd {
    vgerCmdType type;
    float radius;
    float2 cvs[3];
    float4 rgba;
};

kernel void vger_tile(const device vgerPrim* prims,
                      constant int& primCount,
                      device vgerCmd* tiles,
                      uint2 gid [[thread_position_in_grid]]) {

    uint tileIndex = gid.y * MAX_TILES_WIDTH + gid.x;
    float2 center = float2(gid * TILE_PIXEL_SIZE + TILE_PIXEL_SIZE/2);

    device auto *dst = tiles + tileIndex * TILE_BUF_SIZE;

    // Go backwards through prims (front to back).
    for(int i=primCount-1;i>=0;--i) {
        const device vgerPrim& prim = prims[i];
        device vgerCmd& cmd = *dst;

        if(sdPrim(prim, center) < TILE_PIXEL_SIZE * 0.5 * SQRT_2) {
            // Tile intersects the primitive, output command.
            switch(prim.type) {
                case vgerBezier:
                    cmd.type = vgerCmdBezier;
                    cmd.cvs[0] = prim.cvs[0];
                    cmd.cvs[1] = prim.cvs[1];
                    cmd.cvs[2] = prim.cvs[2];
                    ++dst;
                    break;
                case vgerCircle:
                    cmd.type = vgerCmdCircle;
                    cmd.cvs[0] = prim.cvs[0];
                    cmd.radius = prim.radius;
                    ++dst;
                    break;
                default:
                    break;
            }
        }
    }

    dst->type = vgerCmdEnd;

}

kernel void vger_render(texture2d<float, access::write> outTexture [[texture(0)]],
                        const device vgerCmd *tiles [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]],
                        uint2 tgid [[threadgroup_position_in_grid]])
{
    uint tileIndex = tgid.y * 256 + tgid.x;
    float2 pos = float2(gid.x, gid.y);
    float3 rgb = 0.0;

    const device auto *src = tiles + tileIndex * TILE_BUF_SIZE;
    for(;src->type != vgerCmdEnd;++src) {
        float d;
        switch(src->type) {
            case vgerCmdBezier:
                d = sdBezier(pos, src->cvs[0], src->cvs[1], src->cvs[2]);
                break;
            case vgerCmdCircle:
                d = sdCircle(pos - src->cvs[0], src->radius);
                break;
            default:
                d = FLT_MAX;
                break;
        }
        float alpha = src->rgba.a * (1.0-smoothstep(0,1,d));
        rgb = mix(rgb, src->rgba.rgb, alpha);
    }

    outTexture.write(float4(rgb, 1.0), gid);

}
