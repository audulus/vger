// Copyright © 2021 Audulus LLC. All rights reserved.

#include "vgerPathScanner.h"
#include <cmath>
#include <cfloat>

using namespace simd;

bool operator<(const vgerPathScanner::Node& a, const vgerPathScanner::Node& b) {
    return std::tie(a.coord, a.seg, a.end) < std::tie(b.coord, b.seg, b.end);
}

void vgerPathScanner::_init() {

    nodes.clear();
    index = 0;

    for(int i=0;i<segments.size();++i) {
        auto yInterval = segments[i].yInterval();
        nodes.push_back({yInterval.a, i, 0});
        nodes.push_back({yInterval.b, i, 1});
    }

    // Note: using qsort is significantly slower according to profiling.
    std::sort(nodes.begin(), nodes.end());

}

void vgerPathScanner::begin(vector_float2 *cvs, int count) {

    segments.clear();

    for(int i=0;i<count-2;i+=2) {
        segments.push_back({cvs[i], cvs[i+1], cvs[i+2]});
    }

    // Close the path if necessary.
    auto start = segments.front().cvs[0];
    auto end = segments.back().cvs[2];
    if(!equal(start, end)) {
        segments.push_back({end, (start+end)/2, start});
    }

    _init();

}

float2 tof2(CGPoint p) {
    return float2{(float)p.x, (float)p.y};
}

static void pathElement(void *info, const CGPathElement *element) {

    auto scan = (vgerPathScanner*) info;

    float2& p = scan->p;
    float2& start = scan->start;

    switch(element->type) {
        case kCGPathElementMoveToPoint:
            p = start = tof2(element->points[0]);
            break;

        case kCGPathElementAddLineToPoint: {
            float2 b = tof2(element->points[0]);
            scan->segments.push_back({p, (p+b)/2, b});
            p = b;
        }
            break;

        case kCGPathElementAddQuadCurveToPoint:
            scan->segments.push_back({
                p, tof2(element->points[0]), tof2(element->points[1])
            });

            p = tof2(element->points[1]);
            break;

        case kCGPathElementAddCurveToPoint:
            assert(false); // can't handle cubic curves yet.
            break;

        case kCGPathElementCloseSubpath:
            if(!equal(p, start)) {
                scan->segments.push_back({p, (p+start)/2, start});
            }
            p = start;
            break;

        default:
            break;
    }

}

void vgerPathScanner::begin(CGPathRef path) {

    segments.clear();
    p = float2{0,0};
    start = float2{0,0};

    CGPathApply(path, this, pathElement);

    _init();

}

bool vgerPathScanner::next() {

    float y = nodes[index].coord;
    interval.a = y;
    auto n = nodes.size();

    // Activate and deactivate segments.
    for(;index < n && nodes[index].coord == y; ++index) {
        assert(index < n);
        auto& node = nodes[index];
        assert(node.seg < segments.size());
        if(node.end) {
            --activeCount;
            auto& prev = segments[node.seg].previous;
            auto& next = segments[node.seg].next;
            if(prev != -1) {
                assert(prev < segments.size());
                segments[prev].next = next;
            }
            if(next != -1) {
                assert(next < segments.size());
                segments[next].previous = prev;
            }
            if(first == node.seg) {
                first = next;
            }
            next = prev = -1;
        } else {
            ++activeCount;
            segments[node.seg].next = first;
            if(first != -1) {
                assert(first < segments.size());
                segments[first].previous = node.seg;
            }
            first = node.seg;
        }
    }

    if(index < n) {
        interval.b = nodes[index].coord;
    }

    return index < n;
}
