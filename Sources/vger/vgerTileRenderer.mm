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
    id<MTLComputePipelineState> boundsPipeline;
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
        ad.blendingEnabled = true;
        ad.sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        ad.sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        ad.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        ad.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

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

        auto boundsFunc = [lib newFunctionWithName:@"vger_bounds"];
        boundsPipeline = [device newComputePipelineStateWithFunction:boundsFunc error:&error];
        if(error) {
            NSLog(@"error creating pipline state: %@", error);
            abort();
        }

        tileBuffer = [device newBufferWithLength:sizeof(Tile) * maxTilesWidth * maxTilesWidth
                                         options:MTLResourceStorageModeShared];
        printf("tile buffer size: %d MB\n", (int)(tileBuffer.length)/(1024*1024));

        int w = maxTilesWidth;
        int h = maxTilesWidth;

        auto textureDesc = [MTLTextureDescriptor
                            texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                            width:w
                            height:h
                            mipmapped:NO];

        textureDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
#if TARGET_OS_OSX
        textureDesc.storageMode = MTLStorageModeManaged;
#else
        textureDesc.storageMode = MTLStorageModeShared;
#endif

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

    [enc setRenderPipelineState:coarsePipeline];
    [enc setVertexBuffer:primBuffer offset:0 atIndex:0];
    float2 maxWindowSize{maxTilesWidth * tileSize, maxTilesWidth * tileSize};
    [enc setVertexBytes:&maxWindowSize length:sizeof(maxWindowSize) atIndex:1];
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
    [render setBuffer:tileBuffer offset:0 atIndex:0];
    [render dispatchThreadgroups:MTLSizeMake(int(windowSize.x/tileSize)+1, int(windowSize.y/tileSize)+1, 1)
           threadsPerThreadgroup:MTLSizeMake(tileSize, tileSize, 1)];
    [render endEncoding];

}

- (id<MTLTexture>) getDebugTexture {
    return coarseDebugTexture;
}

- (const char*) getTileBuffer {
    return (const char*) tileBuffer.contents;
}

@end
