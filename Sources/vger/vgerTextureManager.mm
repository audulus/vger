// Copyright © 2021 Audulus LLC. All rights reserved.

#import "vgerTextureManager.h"
#define STB_RECT_PACK_IMPLEMENTATION 1
#include "stb_rect_pack.h"
#include <vector>

#define ATLAS_SIZE 2048

@interface vgerTextureManager() {
    id<MTLDevice> device;
    MTLTextureDescriptor* atlasDesc;
    std::vector<stbrp_node> nodes;
    std::vector<stbrp_rect> regions;
    stbrp_context ctx;
    NSMutableArray< id<MTLTexture> >* newTextures;
}
@end

@implementation vgerTextureManager

- (instancetype) initWithDevice:(id<MTLDevice>)device pixelFormat:(MTLPixelFormat)format {
    self = [super init];
    if (self) {
        self->device = device;
        atlasDesc = [MTLTextureDescriptor
                            texture2DDescriptorWithPixelFormat:format
                            width:ATLAS_SIZE
                            height:ATLAS_SIZE
                            mipmapped:NO];
        nodes.resize(2*ATLAS_SIZE);
        stbrp_init_target(&ctx, ATLAS_SIZE, ATLAS_SIZE, nodes.data(), 2*ATLAS_SIZE);

        atlasDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
        atlasDesc.storageMode = MTLStorageModeManaged;

        self.atlas = [device newTextureWithDescriptor:atlasDesc];
        assert(self.atlas);

        newTextures = [NSMutableArray<id<MTLTexture>> new];
    }
    return self;
}

- (int) addRegion:(const uint8_t *)data width:(int)width height:(int)height bytesPerRow:(NSUInteger)bytesPerRow {

    auto desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:width height:height mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead;
    desc.storageMode = MTLStorageModeManaged;
    auto tex = [device newTextureWithDescriptor:desc];
    assert(tex);

    [tex replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:data bytesPerRow:bytesPerRow];
    return [self addRegion:tex];

}

/// Add region for an already loaded texture.
- (int) addRegion:(id<MTLTexture>)texture {

    [newTextures addObject:texture];
    return regions.size() + newTextures.count;

}

// Add any new textures and repack if necessary.
- (void) update:(id<MTLCommandBuffer>) buffer {

    if(newTextures.count) {

        // Pack new regions.
        std::vector<stbrp_rect> newRegions;
        for(id<MTLTexture> tex in newTextures) {
            stbrp_rect r;
            r.w = tex.width;
            r.h = tex.height;
            newRegions.push_back(r);
        }
        stbrp_pack_rects(&ctx, newRegions.data(), newRegions.size());

        auto e = [buffer blitCommandEncoder];
        for(int i=0;i<newRegions.size();++i) {
            auto r = newRegions[i];
            auto tex = newTextures[i];
            assert(tex);
            [e copyFromTexture:tex
                   sourceSlice:0
                   sourceLevel:0
                  sourceOrigin:MTLOriginMake(0, 0, 0)
                    sourceSize:MTLSizeMake(tex.width, tex.height, 1)
                     toTexture:self.atlas
              destinationSlice:0
              destinationLevel:0
             destinationOrigin:MTLOriginMake(r.x, r.y, 0)];
            regions.push_back(r);
        }
        [e endEncoding];

        [newTextures removeAllObjects];
    }
}

@end
