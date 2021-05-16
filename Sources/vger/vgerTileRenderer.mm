// Copyright © 2021 Audulus LLC. All rights reserved.

#import "vgerTileRenderer.h"
#import "vgerBundleHelper.h"

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
    }
    return self;
}

@end
