// Copyright © 2021 Audulus LLC. All rights reserved.

#import "vgerRenderer.h"

static id<MTLLibrary> GetMetalLibrary(id<MTLDevice> device) {

    auto bundle = [NSBundle bundleForClass:vgerRenderer.class];

    assert(bundle);

#if TARGET_OS_OSX
    auto libraryURL = [bundle.bundleURL URLByAppendingPathComponent:@"Contents/Resources/vger_vger.bundle/Contents/Resources/default.metallib"];
#else
    auto libraryURL = [bundle.bundleURL URLByAppendingPathComponent:@"vger_vger.bundle/default.metallib"];
#endif

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
    id<MTLComputePipelineState> prunePipeline;
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

        auto pruneFunc = [lib newFunctionWithName:@"vger_prune"];
        prunePipeline = [device newComputePipelineStateWithFunction:pruneFunc error:&error];
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
            count:(int)n
         textures:(NSArray<id<MTLTexture>>*)textures
     glyphTexture:(id<MTLTexture>)glyphTexture
       windowSize:(vector_float2)windowSize
{
    if(n == 0) {
        return;
    }

    auto prune = [buffer computeCommandEncoder];
    [prune setComputePipelineState:prunePipeline];
    [prune setBuffer:primBuffer offset:0 atIndex:0];
    [prune setBytes:&n length:sizeof(uint) atIndex:1];
    [prune dispatchThreadgroups:MTLSizeMake(n/128+1, 1, 1)
          threadsPerThreadgroup:MTLSizeMake(128, 1, 1)];
    [prune endEncoding];

    auto enc = [buffer renderCommandEncoderWithDescriptor:pass];
    
    [enc setRenderPipelineState:pipeline];
    [enc setVertexBuffer:primBuffer offset:0 atIndex:0];
    [enc setVertexBytes:&windowSize length:sizeof(windowSize) atIndex:1];
    [enc setFragmentBuffer:primBuffer offset:0 atIndex:0];
    [enc setFragmentTexture:glyphTexture atIndex:1];

    vgerPrim* p = (vgerPrim*) primBuffer.contents;
    int currentTexture = -1;
    int m = 0;
    for(int i=0;i<n;++i) {

        // Texture ID changed, render.
        if(p->type != vgerGlyph and p->texture != currentTexture) {

            if(m) {
                [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip
                        vertexStart:0
                        vertexCount:4
                      instanceCount:m];
            }

            [enc setFragmentTexture:[textures objectAtIndex:p->texture] atIndex:0];
            currentTexture = p->texture;
            m = 0;
        }

        p++; m++;
    }

    if(m) {
        [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip
                vertexStart:0
                vertexCount:4
              instanceCount:m];
    }

    [enc endEncoding];
    
}

@end
