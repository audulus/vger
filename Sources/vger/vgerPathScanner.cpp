// Copyright © 2021 Audulus LLC. All rights reserved.

#include "vgerPathScanner.h"
#include <cmath>
#include <cfloat>

vgerPathScanner::BezierSegment::BezierSegment(vector_float2 a, vector_float2 b, vector_float2 c) {
    cvs[0] = a; cvs[1] = b; cvs[2] = c;
    yMin = std::min(a.y, std::min(b.y, c.y));
    yMax = std::max(a.y, std::max(b.y, c.y));
}

bool operator<(const vgerPathScanner::BezierSegment& a, const vgerPathScanner::BezierSegment& b) {
    return a.yMin < b.yMin;
}

void vgerPathScanner::begin(vector_float2 *cvs, int count) {

    segments.clear();

    for(int i=0;i<count-2;i+=2) {
        segments.push_back({cvs[i], cvs[i+1], cvs[i+2]});
    }

    std::sort(segments.begin(), segments.end());

    index = -1;
}

bool vgerPathScanner::next() {

    if(++index >= segments.size()) {
        return false;
    }

    active.clear();

    // Find segments which intersect.
    for(int i = index; i < segments.size() and segments[i].yMin < segments[index].yMax; ++i) {
        active.push_back(i);
    }

    return true;
}
