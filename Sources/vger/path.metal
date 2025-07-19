// Copyright © 2025 Audulus LLC. All rights reserved.

#include <metal_stdlib>
using namespace metal;

// New experimental tile-buffer based path rendering.
// Draw paths by flipping in/out using a triangle fan
// then flipping using bezier regions.

struct GBufferData {

    /// Inside or outside the path?
    bool sign [[raster_order_group(0)]];

    /// Approx distance to path curve for AA.
    float distance [[raster_order_group(0)]];
};

struct GBufferStore {
    GBufferData data    [[imageblock_data]];
};

struct VertexOut {
    float4 position  [[ position ]];
    float2 uv;
};

void flip(thread bool& b) {
    b = !b;
}

fragment GBufferStore path_fragment(VertexOut in [[ stage_in ]],
                                    GBufferStore  fragmentValues [[imageblock_data]]) {

    GBufferStore result;
    result.data.sign = fragmentValues.data.sign;
    float u = in.uv.x;
    float v = in.uv.y;

    if (isnan(u)) {
        // If we're rendering the triangle fan, flip the
        // whole triangle.
        flip(result.data.sign);
    } else {
        // Flip the sign only for the interior pixels.
        if(u*u - v < 0) {
            flip(result.data.sign);
        }
    }

    return result;
}
