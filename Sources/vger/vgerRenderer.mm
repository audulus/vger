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

    auto enc = [buffer renderCommandEncoderWithDescriptor:pass];
    
    [enc setRenderPipelineState:pipeline];
    [enc setVertexBytes:&windowSize length:sizeof(windowSize) atIndex:1];
    [enc setFragmentTexture:glyphTexture atIndex:1];

    vgerPrim* p = (vgerPrim*) primBuffer.contents;
    int currentTexture = -1;
    int m = 0;
    int offset = 0;
    for(int i=0;i<n;++i) {

        int imageID = p->paint.image;

        // Texture ID changed, render.
        if(p->type != vgerGlyph and imageID != -1 and imageID != currentTexture) {

            if(m) {
                [enc setVertexBuffer:primBuffer offset:offset atIndex:0];
                [enc setFragmentBuffer:primBuffer offset:offset atIndex:0];
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
        [enc setVertexBuffer:primBuffer offset:offset atIndex:0];
        [enc setFragmentBuffer:primBuffer offset:offset atIndex:0];
        [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip
                vertexStart:0
                vertexCount:4
              instanceCount:m];
    }

    [enc endEncoding];
    
}

@end
