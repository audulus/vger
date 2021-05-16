// Copyright © 2021 Audulus LLC. All rights reserved.

#ifndef commands_h
#define commands_h

#include "include/vger_types.h"

// Rendering commands for experimental tile-based fine rendering.
// Not yet in use.

#define tileBufSize 4096
#define maxTilesWidth 256

enum vgerOp {
    vgerOpLine,
    vgerOpBez,
    vgerOpSolid,
    vgerOpEnd
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

    device char* dst;

    void lineFill(float2 a, float2 b) {
        device vgerCmdLineFill* cmd = (device vgerCmdLineFill*) dst;
        cmd->op = vgerOpLine;
        cmd->a = a;
        cmd->b = b;
        dst += sizeof(vgerCmdLineFill);
    }

    void bezFill(float2 a, float2 b, float2 c) {
        device vgerCmdBezFill* cmd = (device vgerCmdBezFill*) dst;
        cmd->op = vgerOpBez;
        cmd->a = a;
        cmd->b = b;
        cmd->c = c;
        dst += sizeof(vgerCmdBezFill);
    }

    void solid(int color) {
        device vgerCmdSolid* cmd = (device vgerCmdSolid*) dst;
        cmd->op = vgerOpSolid;
        cmd->color = color;
        dst += sizeof(vgerCmdSolid);
    }

    void end() {
        device vgerCmd* cmd = (device vgerCmd*) dst;
        cmd->op = vgerOpEnd;
    }

};

#endif /* commands_h */
