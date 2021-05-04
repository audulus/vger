// Copyright © 2021 Audulus LLC. All rights reserved.

#include "vgerPathScanner.h"
#include <cmath>
#include <cfloat>

vgerPathScanner::Segment::Segment(vector_float2 a, vector_float2 b, vector_float2 c) {
    cvs[0] = a; cvs[1] = b; cvs[2] = c;
    yInterval.a = std::min(a.y, std::min(b.y, c.y));
    yInterval.b = std::max(a.y, std::max(b.y, c.y));
}

bool operator<(const vgerPathScanner::Segment& a, const vgerPathScanner::Segment& b) {
    return a.yInterval.a < b.yInterval.a;
}

bool operator<(const vgerPathScanner::Node& a, const vgerPathScanner::Node& b) {
    return a.y < b.y;
}

void vgerPathScanner::begin(vector_float2 *cvs, int count) {

    segments.clear();
    index = 0;

    for(int i=0;i<count-2;i+=2) {
        segments.push_back({cvs[i], cvs[i+1], cvs[i+2]});
    }

    for(int i=0;i<segments.size();++i) {
        nodes.push_back({segments[i].yInterval.a, i, 0});
        nodes.push_back({segments[i].yInterval.b, i, 1});
    }

    std::sort(nodes.begin(), nodes.end());

}

bool vgerPathScanner::next() {

    float y = nodes[index].y;
    yInterval.a = y;

    // Activate and deactivate segments.
    for(;index < nodes.size() && nodes[index].y == y; ++index) {
        auto& node = nodes[index];
        if(node.end) {
            active.erase(node.seg);
        } else {
            active.insert(node.seg);
        }
    }

    if(index < nodes.size()) {
        yInterval.b = nodes[index].y;
    }

    return active.size() > 0;
}
