//  Copyright © 2021 Audulus LLC. All rights reserved.

#ifndef scene_h
#define scene_h

#import <Metal/Metal.h>
#define VGER_MAX_LAYERS 4

struct vgerScene {
    id<MTLBuffer> prims[VGER_MAX_LAYERS];  // vgerPrim
    id<MTLBuffer> cvs;    // float2
    id<MTLBuffer> xforms; // float3x3
    id<MTLBuffer> paints; // vgerPaint
};

#endif /* scene_h */
