// Copyright © 2021 Audulus LLC. All rights reserved.

#include <metal_stdlib>
using namespace metal;

#include "include/vger_types.h"
#include "sdf.h"
#include "commands.h"
#include "accel.h"

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

/// Removes a prim if its texture region is outside the rendered geometry.
kernel void vger_prune(uint gid [[thread_position_in_grid]],
                       device vgerPrim* prims,
                       const device float2* cvs,
                       constant uint& primCount) {

    if(gid < primCount) {
        device auto& prim = prims[gid];

        auto center = 0.5 * (prim.texcoords[0] + prim.texcoords[3]);
        auto tile_size = prim.texcoords[3] - prim.texcoords[0];

        if(sdPrim(prim, cvs, center) > max(tile_size.x, tile_size.y) * 0.5 * SQRT_2) {
            float2 big = {FLT_MAX, FLT_MAX};
            prim.verts[0] = big;
            prim.verts[1] = big;
            prim.verts[2] = big;
            prim.verts[3] = big;
        }

    }
}

/// Computes an 8x8 acceleration structure for a primitive.
kernel void vger_accel(uint2 gid [[thread_position_in_threadgroup]],
                       uint2 tgid [[threadgroup_position_in_grid]],
                       const device vgerPrim* prims,
                       const device float2* cvs,
                       device Accel* accel) {

    device auto& prim = prims[tgid.x];

    float2 primMin = prim.texcoords[0];
    float2 primMax = prim.texcoords[3];
    float2 sz = (primMax - primMin)/ACCEL_SIZE;
    float l = length_squared(sz);

    float2 t = (float2(gid)+.5) * sz + primMin;

    float d = sdPrim(prim, cvs, t, /*exact*/true);

    char r = 0;
    if(d*d > l) {
        r = sign(d);
    }

    accel[tgid.x].s[gid.x][gid.y] = r;

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

    float fw = length(fwidth(in.t));
    float d = sdPrim(prim, cvs, in.t, /*exact*/false, fw);

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

    return mix(float4(color.rgb,0.0), color, 1.0-smoothstep(-fw/2,fw/2,d) );

}

kernel void vger_tile_clear(device uint *tileLengths [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]]) {

    tileLengths[gid.y * MAX_TILES_WIDTH + gid.x] = 0;
}

fragment float4 vger_tile_fragment(VertexOut in [[ stage_in ]],
                              const device vgerPrim* prims,
                              const device float2* cvs,
                              device Tile *tiles,
                              device uint *tileLengths [[ raster_order_group(0) ]]) {

    device auto& prim = prims[in.primIndex];
    uint x = (uint) in.position.x;
    uint y = MAX_TILES_WIDTH - (uint) in.position.y - 1;
    uint tileIx = y * MAX_TILES_WIDTH + x;

    // Always accessing tileLengths seems to work around the compiler bug.
    uint length = tileLengths[tileIx];

    float d = sdPrim(prim, cvs, in.t, /*exact*/true);

    device Tile& tile = tiles[tileIx];

    // Are we close enough to output data for the prim?

    if(d > TILE_SIZE_PIXELS * SQRT_2 * 0.5) {
        tile.append(vgerCmdSolid{vgerOpFillTile, pack_float_to_srgb_unorm4x8(float4(0,1,0,1))}, length);
        //tile.append(vgerOpEnd, length);
    }

    switch(prim.type) {
        case vgerRect:
            tile.append(vgerCmdRect{vgerOpRect, prim.cvs[0], prim.cvs[1], prim.radius}, length);
            break;
        case vgerPathFill:
            for(int i=0; i<prim.count; i++) {
                int j = prim.start + 3*i;
                auto a = cvs[j];
                auto b = cvs[j+1];
                auto c = cvs[j+2];

                auto m = in.t.y - TILE_SIZE_PIXELS/2;
                if(a.y < m and b.y < m and c.y < m) {
                    continue;
                }
                m = in.t.y + TILE_SIZE_PIXELS/2;
                if(a.y > m and b.y > m and c.y > m) {
                    continue;
                }

                m = in.t.x - TILE_SIZE_PIXELS/2;
                if(a.x < m and b.x < m and c.x < m) {
                    continue;
                }

                m = in.t.x + TILE_SIZE_PIXELS/2;
                if(a.x > m and b.x > m and c.x > m) {
                    tile.append(vgerCmdLineFill{vgerOpLine,a,c}, length);
                } else {
                    tile.append(vgerCmdBezFill{vgerOpBez,a,b,c}, length);
                }
            }
            break;
        case vgerSegment:
            tile.append(vgerCmdSegment{vgerOpSegment, prim.cvs[0], prim.cvs[1], prim.width}, length);
            break;
        case vgerCircle:
            tile.append(vgerCmdCircle{vgerOpCircle, prim.cvs[0], prim.radius}, length);
            break;
        case vgerBezier:
            tile.append(vgerCmdBezStroke{vgerOpBezStroke, prim.cvs[0], prim.cvs[1], prim.cvs[2], prim.width}, length);
        default:
            break;
    }

    tile.append(vgerCmdSolid{vgerOpSolid,
        pack_float_to_srgb_unorm4x8(prim.paint.innerColor)},
                length);

    //}

    if(d < -TILE_SIZE_PIXELS * SQRT_2 * 0.5 ) {
        tile.append(vgerCmdSolid{vgerOpFillTile, pack_float_to_srgb_unorm4x8(float4(0,0,1,1))}, length);
        //tile.append(vgerOpEnd, length);
    }

    tileLengths[tileIx] = length;

    // This is just for debugging so we can see what was rendered
    // in the coarse rasterization.
    return float4(in.position.x/32, 0, (MAX_TILES_WIDTH-in.position.y)/32, 1);

}

// Not yet used.
kernel void vger_tile_render(texture2d<half, access::write> outTexture [[texture(0)]],
                             const device Tile *tiles [[buffer(0)]],
                             device uint *tileLengths [[buffer(1)]],
                             uint2 gid [[thread_position_in_grid]],
                             uint2 tgid [[threadgroup_position_in_grid]]) {

    uint tileIx = tgid.y * MAX_TILES_WIDTH + tgid.x;
    const device char *src = tiles[tileIx].commands;
    const device char *end = src + tileLengths[tileIx];
    uint x = gid.x;
    uint y = gid.y;
    float2 xy = float2(x, y);

    if(x >= outTexture.get_width() || y >= outTexture.get_height()) {
        return;
    }

    half3 rgb = half3(0.0);
    float d = 1e9;

    while(src < end) {
        vgerOp op = *(device vgerOp*) src;

        if(op == vgerOpEnd) {
            break;
        }

        switch(op) {
            case vgerOpSegment: {
                vgerCmdSegment cmd = *(device vgerCmdSegment*) src;

                d = sdSegment2(xy, cmd.a, cmd.b, cmd.width);

                src += sizeof(vgerCmdSegment);
                break;
            }

            case vgerOpRect: {
                vgerCmdRect cmd = *(device vgerCmdRect*) src;
                auto center = .5*(cmd.a + cmd.b);
                auto size = cmd.b - cmd.a;
                d = sdBox(xy - center, .5*size, cmd.radius);

                src += sizeof(vgerCmdRect);
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
                d = copysign(min(abs(d), sdBezierApprox2(xy, cmd.a, cmd.b, cmd.c)), d);

                if(lineTest(xy, cmd.a, cmd.c)) {
                    d = -d;
                }

                if(bezierTest(xy, cmd.a, cmd.b, cmd.c)) {
                    d = -d;
                }

                src += sizeof(vgerCmdBezFill);
                break;
            }

            case vgerOpFillTile: {
                vgerCmdSolid cmd = *(device vgerCmdSolid*) src;
                half4 c = unpack_unorm4x8_srgb_to_half(cmd.color);
                rgb = c.rgb;
                d = 1e9;
                src += sizeof(vgerCmdSolid);
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
    outTexture.write(rgba, uint2{gid.x, outTexture.get_height() - gid.y - 1});

}
