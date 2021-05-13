// Copyright © 2021 Audulus LLC. All rights reserved.

#ifndef vgerGlyphPathCache_hpp
#define vgerGlyphPathCache_hpp

#include "vger.h"
#include "vgerPathScanner.h"
#include <vector>
#include <unordered_map>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>

struct vgerGlyphPathCache {
    
    struct Info {
        std::vector<simd::float2> cvs;
        std::vector<vgerPrim> prims;
    };
    
    std::unordered_map<CGGlyph, Info> _cache;
    
    CTFontRef ctFont;
    
    vgerPathScanner scan;
    
    vgerGlyphPathCache();
    ~vgerGlyphPathCache();
    
    Info& getInfo(CGGlyph);
};

#endif /* vgerGlyphPathCache_hpp */
