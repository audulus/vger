//  Copyright © 2021 Audulus LLC. All rights reserved.

#ifndef scene_h
#define scene_h

#import <Metal/Metal.h>
#define VGER_MAX_LAYERS 4

#import "prim.h"
#import "paint.h"
#import <simd/simd.h>

using namespace simd;

template<class T>
struct GPUVec {
    id<MTLBuffer> buffer;
    T* ptr = nullptr;
    size_t count = 0;
    size_t capacity = 1024;
    static constexpr size_t MaxBufferSizeBytes = 1024 * 1024 * 256;

    GPUVec() { }

    GPUVec(id<MTLDevice> device) {
        buffer = [device newBufferWithLength:capacity * sizeof(T)
                                     options:MTLResourceStorageModeShared];
        ptr = static_cast<T*>(buffer.contents);
    }

    void allocate(id<MTLDevice> device, size_t cap) {
        capacity = cap;
        auto oldBuffer = buffer;
        buffer = [device newBufferWithLength:capacity * sizeof(T)
                                     options:MTLResourceStorageModeShared];
        memcpy(buffer.contents, oldBuffer.contents, count * sizeof(T));
        ptr = static_cast<T*>(buffer.contents);
    }

    void append(const T& value) {

        if(count >= capacity && capacity*2*sizeof(T) <= MaxBufferSizeBytes) {
            allocate(buffer.device, capacity*2);
        }

        if(count < capacity) {
            ptr[count++] = value;
        }
    }

    void clear() {
        count = 0;
    }
};

struct vgerScene {
    GPUVec<vgerPrim>  prims[VGER_MAX_LAYERS];
    GPUVec<float2>    cvs;
    GPUVec<float4x4>  xforms;
    GPUVec<vgerPaint> paints;

    void clear() {
        for(int layer=0;layer<VGER_MAX_LAYERS;++layer) {
            prims[layer].clear();
        }
        cvs.clear();
        xforms.clear();
        paints.clear();
    }
};

#endif /* scene_h */
