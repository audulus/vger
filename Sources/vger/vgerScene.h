//  Copyright © 2021 Audulus LLC. All rights reserved.

#ifndef scene_h
#define scene_h

#import <Metal/Metal.h>
#define VGER_MAX_LAYERS 4

template<class T>
struct GPUVec {
    id<MTLBuffer> buffer;
    T* ptr;
    size_t count = 0;
    size_t capacity = 65536;

    GPUVec(id<MTLDevice> device) {
        buffer = [device newBufferWithLength:capacity * sizeof(T)
                                     options:MTLResourceStorageModeShared];
        ptr = buffer.contents;
    }

    void allocate(id<MTLDevice> device, size_t cap) {
        capacity = cap;
        buffer = [device newBufferWithLength:capacity * sizeof(T)
                                     options:MTLResourceStorageModeShared];
        memcpy(buffer.contents, ptr, count * sizeof(T));
        ptr = buffer.contents;
    }

    void append(const T& value) {

        if(count >= capacity) {
            allocate(buffer.device, capacity*2);
        }
        ptr[count++] = value;
    }

    void reset() {
        count = 0;
    }
};

struct vgerScene {
    id<MTLBuffer> prims[VGER_MAX_LAYERS];  // vgerPrim
    id<MTLBuffer> cvs;    // float2
    id<MTLBuffer> xforms; // float3x3
    id<MTLBuffer> paints; // vgerPaint
};

#endif /* scene_h */
