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
    id<MTLComputePipelineState> encodePipeline;
    id<MTLComputePipelineState> renderPipeline;
    id<MTLBuffer> tileBuffer;
}
@end

@implementation vgerTileRenderer

- (instancetype)initWithDevice:(id<MTLDevice>) device
{
    self = [super init];
    if (self) {
        auto lib = GetMetalLibrary(device);

        NSError* error;
        auto encodeFunc = [lib newFunctionWithName:@"vger_tile_encode2"];
        encodePipeline = [device newComputePipelineStateWithFunction:encodeFunc error:&error];
        if(error) {
            NSLog(@"error creating pipline state: %@", error);
            abort();
        }

        auto renderFunc = [lib newFunctionWithName:@"vger_tile_render2"];
        renderPipeline = [device newComputePipelineStateWithFunction:renderFunc error:&error];
        if(error) {
            NSLog(@"error creating pipline state: %@", error);
            abort();
        }

        tileBuffer = [device newBufferWithLength:tileBufSize * maxTilesWidth * maxTilesWidth * sizeof(int) options:MTLResourceStorageModePrivate];
        printf("tile buffer size: %d MB\n", (int)(tileBuffer.length)/(1024*1024));
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

    auto encode = [buffer computeCommandEncoder];
    encode.label = @"tile encode encoder";
    [encode setComputePipelineState:encodePipeline];
    [encode setBuffer:primBuffer offset:0 atIndex:0];
    [encode setBuffer:cvBuffer offset:0 atIndex:1];
    [encode setBytes:&n length:sizeof(uint) atIndex:2];
    [encode setBuffer:tileBuffer offset:0 atIndex:3];
    [encode dispatchThreadgroups:MTLSizeMake(16, 16, 1)
           threadsPerThreadgroup:MTLSizeMake(16, 16, 1)];
    [encode endEncoding];

    auto render = [buffer computeCommandEncoder];
    render.label = @"tile render encoder";
    [render setComputePipelineState:renderPipeline];
    [render setTexture:renderTexture atIndex:0];
    [render setBuffer:primBuffer offset:0 atIndex:0];
    [render setBuffer:cvBuffer offset:0 atIndex:1];
    [render setBuffer:tileBuffer offset:0 atIndex:2];
    [render dispatchThreadgroups:MTLSizeMake(int(windowSize.x/16)+1, int(windowSize.y/16)+1, 1)
           threadsPerThreadgroup:MTLSizeMake(tileSize, tileSize, 1)];
    [render endEncoding];

}

@end
