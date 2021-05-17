// Copyright © 2021 Audulus LLC. All rights reserved.

#import "vgerTileRenderer.h"
#import "vgerBundleHelper.h"
#import "commands.h"

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

@interface vgerTileRenderer() {
    id<MTLRenderPipelineState> coarsePipeline;
    id<MTLComputePipelineState> renderPipeline;
    id<MTLBuffer> tileBuffer;
    id<MTLTexture> coarseDebugTexture;
    MTLRenderPassDescriptor* pass;
}
@end

@implementation vgerTileRenderer

- (instancetype)initWithDevice:(id<MTLDevice>) device
{
    self = [super init];
    if (self) {
        auto lib = GetMetalLibrary(device);

        auto desc = [MTLRenderPipelineDescriptor new];
        desc.vertexFunction = [lib newFunctionWithName:@"vger_vertex"];
        desc.fragmentFunction = [lib newFunctionWithName:@"vger_tile_fragment"];

        auto ad = desc.colorAttachments[0];
        ad.pixelFormat = MTLPixelFormatBGRA8Unorm;

        NSError* error;
        coarsePipeline = [device newRenderPipelineStateWithDescriptor:desc error:&error];
        if(error) {
            NSLog(@"error creating pipline state: %@", error);
            abort();
        }

        auto renderFunc = [lib newFunctionWithName:@"vger_tile_render"];
        renderPipeline = [device newComputePipelineStateWithFunction:renderFunc error:&error];
        if(error) {
            NSLog(@"error creating pipline state: %@", error);
            abort();
        }

        tileBuffer = [device newBufferWithLength:tileBufSize * maxTilesWidth * maxTilesWidth * sizeof(int) options:MTLResourceStorageModePrivate];
        printf("tile buffer size: %d MB\n", (int)(tileBuffer.length)/(1024*1024));

        int w = 256;
        int h = 256;

        auto textureDesc = [MTLTextureDescriptor
                            texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                            width:w
                            height:h
                            mipmapped:NO];

        textureDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
        textureDesc.storageMode = MTLStorageModeManaged;

        coarseDebugTexture = [device newTextureWithDescriptor:textureDesc];
        assert(coarseDebugTexture);

        pass = [MTLRenderPassDescriptor new];
        pass.colorAttachments[0].texture = coarseDebugTexture;
        pass.colorAttachments[0].storeAction = MTLStoreActionStore;
        pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    }
    return self;
}

- (void) encodeTo:(id<MTLCommandBuffer>) buffer
            prims:(id<MTLBuffer>) primBuffer
              cvs:(id<MTLBuffer>) cvBuffer
            count:(int)n
         textures:(NSArray<id<MTLTexture>>*)textures
     glyphTexture:(id<MTLTexture>)glyphTexture
    renderTexture:(id<MTLTexture>)renderTexture
       windowSize:(vector_float2)windowSize
{
    if(n == 0) {
        return;
    }

    auto enc = [buffer renderCommandEncoderWithDescriptor:pass];
    enc.label = @"render encoder";

    float2 coarseSize{maxTilesWidth, maxTilesWidth};

    [enc setRenderPipelineState:coarsePipeline];
    [enc setVertexBytes:&coarseSize length:sizeof(coarseSize) atIndex:1];
    [enc setFragmentTexture:glyphTexture atIndex:1];
    [enc setVertexBuffer:primBuffer offset:0 atIndex:0];
    [enc setFragmentBuffer:primBuffer offset:0 atIndex:0];
    [enc setFragmentBuffer:cvBuffer offset:0 atIndex:1];
    [enc setFragmentBuffer:tileBuffer offset:0 atIndex:2];

    // XXX: how do we deal with rendering from textures?
    [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip
            vertexStart:0
            vertexCount:4
          instanceCount:n];
    [enc endEncoding];

    auto render = [buffer computeCommandEncoder];
    render.label = @"tile render encoder";
    [render setComputePipelineState:renderPipeline];
    [render setTexture:renderTexture atIndex:0];
    [render setBuffer:tileBuffer offset:0 atIndex:2];
    [render dispatchThreadgroups:MTLSizeMake(int(windowSize.x/tileSize)+1, int(windowSize.y/tileSize)+1, 1)
           threadsPerThreadgroup:MTLSizeMake(tileSize, tileSize, 1)];
    [render endEncoding];

}

@end
