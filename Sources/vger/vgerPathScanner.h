// Copyright © 2021 Audulus LLC. All rights reserved.

#ifndef vgerPathScanner_h
#define vgerPathScanner_h

#include <simd/simd.h>
#include <vector>

struct vgerPathScanner {

    struct BezierSegment {
        vector_float2 cvs[3];
        float yMin;
        float yMax;

        BezierSegment(vector_float2 a, vector_float2 b, vector_float2 c);
    };

    std::vector<BezierSegment> segments;
    std::vector<int> active;
    int index;

    void begin(vector_float2* cvs, int count);
    bool next();

};

#endif /* vgerPathScanner_h */
