// Copyright © 2021 Audulus LLC. All rights reserved.

#import "vgerRenderer.h"
#import "vgerBundleHelper.h"
#import "accel.h"

static id<MTLLibrary> GetMetalLibrary(id<MTLDevice> device) {

    auto bundle = [vgerBundleHelper moduleBundle];
    assert(bundle);

    auto libraryURL = [bundle URLForResource:@"default" withExtension:@"metallib"];

    NSError* error;
    auto lib = [device newLibraryWithURL:libraryURL error:&error];
    if(error) {
        NSLog(@"error creating metal library: %@", lib);
    }

    assert(lib);
    return lib;
}

@interface vgerRenderer() {
    id<MTLRenderPipelineState> pipeline;
    id<MTLComputePipelineState> boundsPipeline;
}
@end

@implementation vgerRenderer

- (instancetype)initWithDevice:(id<MTLDevice>) device
{
    self = [super init];
    if (self) {
        auto lib = GetMetalLibrary(device);
        
        auto desc = [MTLRenderPipelineDescriptor new];
        desc.vertexFunction = [lib newFunctionWithName:@"vger_vertex"];
        desc.fragmentFunction = [lib newFunctionWithName:@"vger_fragment"];

        auto ad = desc.colorAttachments[0];
        ad.pixelFormat = MTLPixelFormatBGRA8Unorm;
        ad.blendingEnabled = true;
        ad.sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        ad.sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        ad.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        ad.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        
        NSError* error;
        pipeline = [device newRenderPipelineStateWithDescriptor:desc error:&error];
        if(error) {
            NSLog(@"error creating pipline state: %@", error);
            abort();
        }

        auto boundsFunc = [lib newFunctionWithName:@"vger_bounds"];
        boundsPipeline = [device newComputePipelineStateWithFunction:boundsFunc error:&error];
        if(error) {
            NSLog(@"error creating pipline state: %@", error);
            abort();
        }
    }
    return self;
}

- (void) encodeTo:(id<MTLCommandBuffer>) buffer
             pass:(MTLRenderPassDescriptor*) pass
            prims:(id<MTLBuffer>) primBuffer
              cvs:(id<MTLBuffer>) cvBuffer
           xforms:(id<MTLBuffer>) xformBuffer
            count:(int)n
         textures:(NSArray<id<MTLTexture>>*)textures
     glyphTexture:(id<MTLTexture>)glyphTexture
       windowSize:(vector_float2)windowSize
{
    if(n == 0) {
        return;
    }

    auto bounds = [buffer computeCommandEncoder];
    bounds.label = @"bounds encoder";
    [bounds setComputePipelineState:boundsPipeline];
    [bounds setBuffer:primBuffer offset:0 atIndex:0];
    [bounds setBuffer:cvBuffer offset:0 atIndex:1];
    [bounds setBytes:&n length:sizeof(uint) atIndex:2];
    [bounds dispatchThreadgroups:MTLSizeMake(n/128+1, 1, 1)
          threadsPerThreadgroup:MTLSizeMake(128, 1, 1)];
    [bounds endEncoding];

    auto enc = [buffer renderCommandEncoderWithDescriptor:pass];
    enc.label = @"render encoder";
    
    [enc setRenderPipelineState:pipeline];
    [enc setFragmentTexture:glyphTexture atIndex:1];
    [enc setVertexBuffer:primBuffer offset:0 atIndex:0];
    [enc setVertexBuffer:xformBuffer offset:0 atIndex:1];
    [enc setVertexBytes:&windowSize length:sizeof(windowSize) atIndex:2];
    [enc setFragmentBuffer:primBuffer offset:0 atIndex:0];
    [enc setFragmentBuffer:cvBuffer offset:0 atIndex:1];

    vgerPrim* p = (vgerPrim*) primBuffer.contents;
    int currentTexture = -1;
    int m = 0;
    int offset = 0;
    for(int i=0;i<n;++i) {

        int imageID = p->paint.image;

        // Texture ID changed, render.
        if(p->type != vgerGlyph and imageID != -1 and imageID != currentTexture) {

            if(m) {
                [enc setVertexBufferOffset:offset atIndex:0];
                [enc setFragmentBufferOffset:offset atIndex:0];
                [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip
                        vertexStart:0
                        vertexCount:4
                      instanceCount:m];
            }

            if(imageID == -1) {
                [enc setFragmentTexture:nil atIndex:0];
            } else {
                [enc setFragmentTexture:[textures objectAtIndex:imageID] atIndex:0];
            }
            
            currentTexture = imageID;
            offset = i*sizeof(vgerPrim);
            m = 0;
        }

        p++; m++;
    }

    if(m) {
        [enc setVertexBufferOffset:offset atIndex:0];
        [enc setFragmentBufferOffset:offset atIndex:0];
        [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip
                vertexStart:0
                vertexCount:4
              instanceCount:m];
    }

    [enc endEncoding];
    
}

@end
