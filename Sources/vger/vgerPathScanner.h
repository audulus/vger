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

        Interval yInterval() const;
    };

    struct Node {
        float y;
        int seg;
        bool end;
    };

    std::vector<Segment> segments;
    std::vector<Node> nodes;
    std::set<int> active; // active segments
    int index = 0; // current node index
    Interval yInterval;

    void begin(vector_float2* cvs, int count);
    bool next();

};

#endif /* vgerPathScanner_h */
