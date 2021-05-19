//  Copyright © 2017 Halfspace LLC. All rights reserved.

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position  [[ position ]];
    float2 t;
};

constant float2 verts[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };

vertex VertexOut textureVertex(uint vid [[ vertex_id ]]) {
    
    VertexOut out;
    out.position = float4(verts[vid], 0.0, 1.0);
    out.t = (verts[vid] + float2(1)) * .5;
    out.t.y = 1.0 - out.t.y;
    return out;
    
}

constexpr sampler s(coord::normalized,
                    filter::nearest);

fragment half4 textureFragment(VertexOut in [[ stage_in ]],
                               texture2d<float, access::sample> tex) {

    return half4(tex.sample(s, in.t));
    
}
