// Copyright © 2021 Audulus LLC. All rights reserved.

#ifndef vgerPathScanner_h
#define vgerPathScanner_h

#include <simd/simd.h>
#include <vector>
#include <set>
#include "Interval.h"

struct vgerPathScanner {

    struct Segment {
        vector_float2 cvs[3];
        int next = -1;
        int previous = -1;

        Interval yInterval() const;
    };

    struct Node {
        float y;
        int seg;
        bool end;
    };

    std::vector<Segment> segments;
    std::vector<Node> nodes;
    int index = 0; // current node index
    Interval yInterval;
    int first = -1; // first active segment
    int activeCount = 0;

    void begin(vector_float2* cvs, int count);
    bool next();

};

#endif /* vgerPathScanner_h */
