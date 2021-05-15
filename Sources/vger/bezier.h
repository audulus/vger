// Copyright © 2021 Audulus LLC. All rights reserved.

#ifndef bezier_h
#define bezier_h

#include <simd/simd.h>
using namespace simd;

// See https://ttnghia.github.io/pdf/QuadraticApproximation.pdf

// Approximate cubic bezier with two quadratics.
void approx_cubic(float2 b[4], float2 q[6]) {

    q[0] = b[0];
    q[5] = b[3];

    q[1] = simd_mix(0.75, b[0], b[1]);
    q[4] = simd_mix(0.25, b[2], b[3]);

    q[2] = q[3] = simd_mix(0.5, q[1], q[4]);

}

#endif /* bezier_h */
