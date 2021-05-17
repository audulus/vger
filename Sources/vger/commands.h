// Copyright © 2021 Audulus LLC. All rights reserved.

#ifndef commands_h
#define commands_h

#include "include/vger_types.h"

#ifdef __METAL_VERSION__
#define DEVICE device
#else
#define DEVICE

#include <simd/simd.h>
using namespace simd;

#endif

// Rendering commands for experimental tile-based fine rendering.
// Not yet in use.

#define tileBufSize 32
#define maxTilesWidth 256
#define tileSize 16

enum vgerOp {
    vgerOpEnd,
    vgerOpLine,
    vgerOpBez,
    vgerOpSolid,
    vgerOpSegment,
};

/// Line segment.
struct vgerCmdSegment {
    vgerOp op;
    float2 a;
    float2 b;
};

/// Flip the sign of the df if ray intersects with line.
struct vgerCmdLineFill {
    vgerOp op;
    float2 a;
    float2 b;
};

/// Flip the sign of the df if point is inside the bezier.
struct vgerCmdBezFill {
    vgerOp op;
    float2 a;
    float2 b;
    float2 c;
};

/// Set the color.
struct vgerCmdSolid {
    vgerOp op;
    int color;
};

union vgerCmd {
    vgerOp op;
    vgerCmdLineFill line;
    vgerCmdBezFill bez;
    vgerCmdSolid solid;
};

struct TileEncoder {

    DEVICE char* dst;

    void segment(float2 a, float2 b) {
        DEVICE vgerCmdSegment* cmd = (DEVICE vgerCmdSegment*) dst;
        cmd->op = vgerOpSegment;
        cmd->a = a;
        cmd->b = b;
        dst += sizeof(vgerOpSegment);
    }

    void lineFill(float2 a, float2 b) {
        DEVICE vgerCmdLineFill* cmd = (DEVICE vgerCmdLineFill*) dst;
        cmd->op = vgerOpLine;
        cmd->a = a;
        cmd->b = b;
        dst += sizeof(vgerCmdLineFill);
    }

    void bezFill(float2 a, float2 b, float2 c) {
        DEVICE vgerCmdBezFill* cmd = (DEVICE vgerCmdBezFill*) dst;
        cmd->op = vgerOpBez;
        cmd->a = a;
        cmd->b = b;
        cmd->c = c;
        dst += sizeof(vgerCmdBezFill);
    }

    void solid(int color) {
        DEVICE vgerCmdSolid* cmd = (DEVICE vgerCmdSolid*) dst;
        cmd->op = vgerOpSolid;
        cmd->color = color;
        dst += sizeof(vgerCmdSolid);
    }

    void end() {
        DEVICE vgerCmd* cmd = (DEVICE vgerCmd*) dst;
        cmd->op = vgerOpEnd;
    }

};

#endif /* commands_h */
