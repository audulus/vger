// Copyright © 2021 Audulus LLC. All rights reserved.

#include "vgerPathScanner.h"
#include <cmath>
#include <cfloat>

Interval vgerPathScanner::Segment::yInterval() const {
    return { std::min(cvs[0].y, std::min(cvs[1].y, cvs[2].y)),
        std::max(cvs[0].y, std::max(cvs[1].y, cvs[2].y))
    };
}

bool operator<(const vgerPathScanner::Node& a, const vgerPathScanner::Node& b) {
    return std::tie(a.y, a.seg, a.end) < std::tie(b.y, b.seg, b.end);
}

void vgerPathScanner::begin(vector_float2 *cvs, int count) {

    segments.clear();
    nodes.clear();
    index = 0;
    active.clear();

    for(int i=0;i<count-2;i+=2) {
        segments.push_back({cvs[i], cvs[i+1], cvs[i+2]});
    }

    // Close the path if necessary.
    auto start = segments.front().cvs[0];
    auto end = segments.back().cvs[2];
    if(!simd_equal(start, end)) {
        segments.push_back({end, (start+end)/2, start});
    }

    for(int i=0;i<segments.size();++i) {
        auto yInterval = segments[i].yInterval();
        nodes.push_back({yInterval.a, i, 0});
        nodes.push_back({yInterval.b, i, 1});
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
