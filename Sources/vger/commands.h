// Copyright © 2021 Audulus LLC. All rights reserved.

#ifndef commands_h
#define commands_h

#include "include/vger_types.h"

#ifdef __METAL_VERSION__
#define DEVICE device
#define THREAD thread
#else
#define DEVICE
#define THREAD

#include <simd/simd.h>
using namespace simd;

#endif

// Rendering commands for experimental tile-based fine rendering.
// Not yet in use.

#define tileBufSize 256
#define maxTilesWidth 256
#define tileSize 16

enum vgerOp {
    vgerOpEnd,
    vgerOpLine,
    vgerOpBezStroke,
    vgerOpBez,
    vgerOpSolid,
    vgerOpSegment,
    vgerOpRect,
    vgerOpCircle
};

/// Line segment.
struct vgerCmdSegment {
    vgerOp op;
    packed_float2 a, b;
    float width;
};

struct vgerCmdBezStroke {
    vgerOp op;
    packed_float2 a, b, c;
    float width;
};

/// Round rect.
struct vgerCmdRect {
    vgerOp op;
    packed_float2 a, b;
    float radius;
};

/// Round rect.
struct vgerCmdCircle {
    vgerOp op;
    packed_float2 center;
    float radius;
};

/// Flip the sign of the df if ray intersects with line.
struct vgerCmdLineFill {
    vgerOp op;
    packed_float2 a, b;
};

/// Flip the sign of the df if point is inside the bezier.
struct vgerCmdBezFill {
    vgerOp op;
    packed_float2 a, b, c;
};

/// Set the color.
struct vgerCmdSolid {
    vgerOp op;
    uint color;
};

struct Tile {
    char commands[tileBufSize];

    template<class T>
    void append(const T cmd, THREAD uint& len) DEVICE {
        *(DEVICE T*) (commands + len) = cmd;
        len += sizeof(T);
    }

};

#endif /* commands_h */
