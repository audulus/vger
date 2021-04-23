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
        ad.pixelFormat = MTLPixelFormatRGBA8Unorm;
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
    }
    return self;
}

- (void) encodeTo:(id<MTLCommandBuffer>) buffer
             pass:(MTLRenderPassDescriptor*) pass
            prims:(id<MTLBuffer>) primBuffer
            count:(int)n
          texture:(id<MTLTexture>)texture
     glyphTexture:(id<MTLTexture>)glyphTexture
{
    auto enc = [buffer renderCommandEncoderWithDescriptor:pass];
    
    [enc setRenderPipelineState:pipeline];
    [enc setVertexBuffer:primBuffer offset:0 atIndex:0];
    [enc setFragmentBuffer:primBuffer offset:0 atIndex:0];
    [enc setFragmentTexture:texture atIndex:0];
    [enc setFragmentTexture:glyphTexture atIndex:1];
    [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4 instanceCount:n];
    [enc endEncoding];
    
}

@end
