// Copyright © 2021 Audulus LLC. All rights reserved.

#include <metal_stdlib>
using namespace metal;

#include "include/vger_types.h"
#include "sdf.h"
#include "commands.h"

#define SQRT_2 1.414213562373095

struct VertexOut {
    float4 position  [[ position ]];
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

            if(sdPrim(prim, nullptr, center) > max(tile_size.x, tile_size.y) * 0.5 * SQRT_2) {
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

        if(p.type != vgerGlyph and p.type != vgerPathFill) {

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

    auto p = float2{q.x/q.z, q.y/q.z};
    out.t = prim.texcoords[vid];
    out.position = float4(2.0 * p / viewSize - 1.0, 0, 1);
    
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
    
    float d = sdPrim(prim, cvs, in.t);

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

    float fw = length(fwidth(in.t));
    return mix(float4(color.rgb,0.0), color, 1.0-smoothstep(-fw/2,fw/2,d) );

}


fragment float4 vger_tile_fragment(VertexOut in [[ stage_in ]],
                              const device vgerPrim* prims,
                              const device float2* cvs,
                              device char *tiles,
                              texture2d<float, access::sample> tex,
                              texture2d<float, access::sample> glyphs) {

    device auto& prim = prims[in.primIndex];

    float d = sdPrim(prim, cvs, in.t);

    // Are we close enough to output data for the prim?
    if(d < 2) {

        uint x = (uint) in.position.x;
        uint y = (uint) in.position.y;
        uint tileIx = y * maxTilesWidth + x;

        TileEncoder encoder{tiles + tileIx * tileBufSize};

        if(prim.type == vgerPathFill) {
            for(int i=0; i<prim.count; i++) {
                int j = prim.start + 3*i;
                auto a = cvs[j];
                auto b = cvs[j+1];
                auto c = cvs[j+2];
                encoder.bezFill(a,b,c);
            }
        }

        encoder.end();
    }

    // This is just for debugging so we can see what was rendered
    // in the coarse rasterization.
    return float4(1,0,1,1);

}

kernel void vger_tile_encode(const device vgerPrim* prims,
                             const device float2* cvs,
                             constant uint& primCount,
                             device char *tiles,
                             uint2 gid [[thread_position_in_grid]]) {

    uint tileIx = gid.y * maxTilesWidth + gid.x;
    device char *dst = tiles + tileIx * tileBufSize;
    TileEncoder encoder{dst};

    float2 p = float2(gid * tileSize + tileSize/2);

    for(uint i=0;i<primCount;++i) {
        device auto& prim = prims[i];

        float d = sdPrim(prim, cvs, p);

        if(d < tileSize * SQRT_2 * 0.5) {

            if(prim.type == vgerSegment) {
                encoder.segment(prim.cvs[0], prim.cvs[1]);
            }

            if(prim.type == vgerPathFill) {
                for(int i=0; i<prim.count; i++) {
                    int j = prim.start + 3*i;
                    auto a = cvs[j];
                    auto b = cvs[j+1];
                    auto c = cvs[j+2];

                    auto m = p.y - tileSize/2;
                    if(a.y < m and b.y < m and c.y < m) {
                        continue;
                    }
                    m = p.y + tileSize/2;
                    if(a.y > m and b.y > m and c.y > m) {
                        continue;
                    }

                    m = p.x - tileSize/2;
                    if(a.x < m and b.x < m and c.x < m) {
                        continue;
                    }

                    m = p.x + tileSize/2;
                    if(a.x > m and b.x > m and c.x > m) {
                        encoder.lineFill(a,c);
                    } else {
                        encoder.bezFill(a,b,c);
                    }
                }
            }

            encoder.solid(pack_float_to_srgb_unorm4x8(prim.paint.innerColor));
        }
    }

    encoder.end();

}

// Not yet used.
kernel void vger_tile_render(texture2d<half, access::write> outTexture [[texture(0)]],
                             const device char *tiles [[buffer(0)]],
                             uint2 gid [[thread_position_in_grid]],
                             uint2 tgid [[threadgroup_position_in_grid]]) {

    uint tileIx = tgid.y * maxTilesWidth + tgid.x;
    const device char *src = tiles + tileIx * tileBufSize;
    uint x = gid.x;
    uint y = gid.y;
    float2 xy = float2(x, y);

    half3 rgb = half3(1.0);
    float d = 1e9;

    while(true) {
        vgerOp op = *(device vgerOp*) src;

        if(op == vgerOpEnd) {
            break;
        }

        switch(op) {
            case vgerOpSegment: {
                vgerCmdSegment cmd = *(device vgerCmdSegment*) src;

                d = sdSegment(xy, cmd.a, cmd.b);

                src += sizeof(vgerCmdSegment);
                break;
            }

            case vgerOpLine: {
                vgerCmdLineFill cmd = *(device vgerCmdLineFill*) src;

                if(lineTest(xy, cmd.a, cmd.b)) {
                    d = -d;
                }

                src += sizeof(vgerCmdLineFill);
                break;
            }

            case vgerOpBez: {
                vgerCmdBezFill cmd = *(device vgerCmdBezFill*) src;

                if(lineTest(xy, cmd.a, cmd.c)) {
                    d = -d;
                }

                if(bezierTest(xy, cmd.a, cmd.b, cmd.c)) {
                    d = -d;
                }

                src += sizeof(vgerCmdBezFill);
                break;
            }

            case vgerOpSolid: {
                vgerCmdSolid cmd = *(device vgerCmdSolid*) src;
                half4 c = unpack_unorm4x8_srgb_to_half(cmd.color);
                rgb = mix(rgb, c.rgb, 1.0-smoothstep(-.5,.5,d) );
                d = 1e9;
                src += sizeof(vgerCmdSolid);
                break;
            }

            default:
                outTexture.write(half4(1.0, 0.0, 1.0, 1.0), gid);
                return;

        }
    }

    // Linear to sRGB conversion. Note that if we had writable sRGB textures
    // we could let this be done in the write call.
    rgb = select(1.055 * pow(rgb, 1/2.4) - 0.055, 12.92 * rgb, rgb < 0.0031308);
    half4 rgba = half4(rgb, 1.0);
    outTexture.write(rgba, gid);

}

kernel void vger_tile_encode2(const device vgerPrim* prims,
                             const device float2* cvs,
                             constant uint& primCount,
                             device int *tiles,
                             uint2 gid [[thread_position_in_grid]]) {

    uint tileIx = gid.y * maxTilesWidth + gid.x;
    device int *dst = tiles + tileIx * tileBufSize;

    float2 p = float2(gid * tileSize + tileSize/2);

    for(uint i=0;i<primCount;++i) {
        device auto& prim = prims[i];

        float d = sdPrim(prim, cvs, p);

        if(d < tileSize * SQRT_2 * 0.5) {
            *dst++ = i;
        }
    }

    *dst = -1; // end

}

kernel void vger_tile_render2(texture2d<half, access::write> outTexture [[texture(0)]],
                              const device vgerPrim* prims,
                              const device float2* cvs,
                              const device int *tiles,
                              uint2 gid [[thread_position_in_grid]],
                              uint2 tgid [[threadgroup_position_in_grid]]) {

    uint tileIx = tgid.y * maxTilesWidth + tgid.x;
    const device int *src = tiles + tileIx * tileBufSize;
    uint x = gid.x;
    uint y = gid.y;
    float2 xy = float2(x, y);

    half3 rgb = half3(0.0);

    for(; *src != -1; ++src) {
        device auto& prim = prims[*src];
        float d = sdPrim(prim, cvs, xy);
        auto c = half4(applyPaint(prim.paint, xy));
        rgb = mix(rgb, c.rgb, 1.0-smoothstep(-.5,.5,d) );
    }

    // Linear to sRGB conversion. Note that if we had writable sRGB textures
    // we could let this be done in the write call.
    rgb = select(1.055 * pow(rgb, 1/2.4) - 0.055, 12.92 * rgb, rgb < 0.0031308);
    half4 rgba = half4(rgb, 1.0);
    outTexture.write(rgba, gid);

}
