// Copyright © 2021 Audulus LLC. All rights reserved.

#pragma once

#include <simd/simd.h>
using namespace simd;

// See https://ttnghia.github.io/pdf/QuadraticApproximation.pdf

// Approximate cubic bezier with two quadratics.
void approx_cubic(float2 b[4], float2 q[6]) {

    q[0] = b[0];
    q[5] = b[3];

    q[1] = simd_mix(b[0], b[1], 0.75);
    q[4] = simd_mix(b[2], b[3], 0.25);

    q[2] = q[3] = simd_mix(q[1], q[4], 0.5);

}
