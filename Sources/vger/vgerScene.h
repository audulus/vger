//  Copyright © 2021 Audulus LLC. All rights reserved.

#ifndef scene_h
#define scene_h

#import <Metal/Metal.h>

struct vgerScene {
    id<MTLBuffer> prims;  // vgerPrim
    id<MTLBuffer> cvs;    // float2
    id<MTLBuffer> xforms; // float3x3
};

#endif /* scene_h */
