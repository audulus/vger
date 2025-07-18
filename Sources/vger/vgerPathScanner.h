// Copyright © 2021 Audulus LLC. All rights reserved.

#pragma once

#include <simd/simd.h>
#include <vector>
#include <set>
#include "Interval.h"
#import <CoreGraphics/CoreGraphics.h>

struct vgerPathScanner {

    struct Segment {
        vector_float2 cvs[3];
        int next = -1;
        int previous = -1;

        Interval yInterval() const {
            return {
                // Fatten the interval slightly to prevent artifacts by
                // slightly missing a curve in a band.
                std::min(cvs[0].y, std::min(cvs[1].y, cvs[2].y)) - 1,
                std::max(cvs[0].y, std::max(cvs[1].y, cvs[2].y)) + 1
            };
        }

        Interval xInterval() const {
            return {
                // Fatten the interval slightly to prevent artifacts by
                // slightly missing a curve in a band.
                std::min(cvs[0].x, std::min(cvs[1].x, cvs[2].x)) - 1,
                std::max(cvs[0].x, std::max(cvs[1].x, cvs[2].x)) + 1
            };
        }
    };

    struct Node {
        float coord;
        int seg;
        bool end;
    };

    std::vector<Segment> segments;
    std::vector<Node> nodes;
    int index = 0; // current node index
    Interval interval;
    int first = -1; // first active segment
    int activeCount = 0;
    vector_float2 start{0,0};
    vector_float2 p{0,0};

    void _init();
    void begin(vector_float2* cvs, int count);

    // In case we want to render glphs with paths.
    void begin(CGPathRef path);
    
    bool next();

};
