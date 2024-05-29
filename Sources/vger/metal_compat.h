//  Copyright © 2021 Audulus LLC. All rights reserved.

#pragma once

#ifdef __METAL_VERSION__
#define DEVICE device

#else
#define DEVICE

#include <simd/simd.h>
using namespace simd;

inline float min(float a, float b) {
    return a > b ? b : a;
}

inline float max(float a, float b) {
    return a > b ? a : b;
}

inline float2 max(float2 a, float b) {
    return simd_max(a, float2{b,b});
}

inline float clamp(float x, float a, float b) {
    if(x > b) x = b;
    if(x < a) x = a;
    return x;
}

inline float3 clamp(float3 x, float a, float b) {
    return simd_clamp(x, a, b);
}

inline float mix(float a, float b, float t) {
    return (1-t)*a + t*b;
}

inline float2 mix(float2 a, float2 b, float t) {
    return (1-t)*a + t*b;
}

#endif
