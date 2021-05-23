// Copyright © 2021 Audulus LLC. All rights reserved.

#import "vgerGlyphPathCache.h"
#import "vgerBundleHelper.h"
#import "sdf.h"

using namespace simd;

vgerGlyphPathCache::vgerGlyphPathCache() {
    
    auto bundle = [vgerBundleHelper moduleBundle];
    assert(bundle);

    auto fontURL = [bundle URLForResource:@"Anodina-Regular" withExtension:@"ttf" subdirectory:@"fonts"];

    auto fd = CTFontManagerCreateFontDescriptorsFromURL( (__bridge CFURLRef) fontURL);
    ctFont = CTFontCreateWithFontDescriptor( (CTFontDescriptorRef) CFArrayGetValueAtIndex(fd, 0), 12.0, nil);
    assert(ctFont);
    CFRelease(fd);
    
}

vgerGlyphPathCache::~vgerGlyphPathCache() {
    CFRelease(ctFont);
}

static bool scanGlyphs = true;

vgerGlyphPathCache::Info& vgerGlyphPathCache::getInfo(CGGlyph glyph) {
    
    auto iter = _cache.find(glyph);
    if(iter != _cache.end()) {
        return iter->second;
    }
    
    // Add a glyph to the cache.
    CGRect boundingRect;
    CTFontGetBoundingRectsForGlyphs(ctFont, kCTFontOrientationHorizontal, &glyph, &boundingRect, 1);
    
    auto glyphTransform = CGAffineTransformMake(1, 0, 0, 1,
                                                -boundingRect.origin.x,
                                                -boundingRect.origin.y);
    auto path = CTFontCreatePathForGlyph(ctFont, glyph, &glyphTransform);
    
    auto& info = _cache[glyph];
    scan.begin(path);
    
    if(scanGlyphs) {
    
        while(scan.next()) {
            int n = scan.activeCount;
            
            vgerPrim prim = {
                .type = vgerPathFill,
                .start = (uint32_t) info.cvs.size(),
                .count = uint16_t(n)
            };
            
            Interval xInt{FLT_MAX, -FLT_MAX};
            
            for(int a = scan.first; a != -1; a = scan.segments[a].next) {
                
                assert(a < scan.segments.size());
                for(int i=0;i<3;++i) {
                    auto p = scan.segments[a].cvs[i];
                    info.cvs.push_back(p);
                    xInt.a = std::min(xInt.a, p.x);
                    xInt.b = std::max(xInt.b, p.x);
                }
                
            }
            
            BBox bounds;
            bounds.min.x = xInt.a;
            bounds.max.x = xInt.b;
            bounds.min.y = scan.interval.a;
            bounds.max.y = scan.interval.b;
            
            // Calculate the prim vertices at this stage,
            // as we do for glyphs.
            prim.quadBounds[0] = prim.texBounds[0] = bounds.min;
            prim.quadBounds[1] = prim.texBounds[1] = bounds.max;
            
            info.prims.push_back(prim);
        }
        
    } else {
        
        vgerPrim prim = {
            .type = vgerPathFill,
            .start = (uint32_t) info.cvs.size(),
            .count = (uint16_t) scan.segments.size()
        };
        
        for(auto& seg : scan.segments) {
            for(int i=0;i<3;++i) {
                info.cvs.push_back(seg.cvs[i]);
            }
        }
        
        BBox bounds = sdPrimBounds(prim, info.cvs.data());
        
        // Calculate the prim vertices at this stage,
        // as we do for glyphs.
        prim.quadBounds[0] = prim.texBounds[0] = bounds.min;
        prim.quadBounds[1] = prim.texBounds[1] = bounds.max;
        
        info.prims.push_back(prim);
    }
    
    CGPathRelease(path);
    
    return info;
}
