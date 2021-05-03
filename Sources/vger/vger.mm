//  Copyright © 2021 Audulus LLC. All rights reserved.

#import "vger.h"
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#if TARGET_OS_OSX
#import <Cocoa/Cocoa.h>
#else
#import <UIKit/UIKit.h>
#endif

#import "vgerRenderer.h"
#import "vgerTextureManager.h"
#import "vgerGlyphCache.h"
#include <vector>
#include <unordered_map>
#include <string>

using namespace simd;
#import "sdf.h"

/// For caching the layout of strings.
struct TextLayoutInfo {
    /// The frame in which the string was last rendered. If not the current frame,
    /// then the string is pruned from the cache.
    uint64_t lastFrame = 0;

    /// Prims are copied to output.
    std::vector<vgerPrim> prims;
};

struct TextLayoutKey {
    std::string str;
    float size;
    int align;
};

inline void hash_combine(size_t& seed) { }

template <typename T, typename... Rest>
inline void hash_combine(size_t& seed, const T& v, Rest... rest) {
    std::hash<T> hasher;
    seed ^= hasher(v) + 0x9e3779b9 + (seed<<6) + (seed>>2);
    hash_combine(seed, rest...);
}

#define MAKE_HASHABLE(Type, ...) \
inline auto __tie(const Type& t) { return std::tie(__VA_ARGS__); }                              \
inline bool operator==(const Type& lhs, const Type& rhs) { return __tie(lhs) == __tie(rhs); } \
inline bool operator!=(const Type& lhs, const Type& rhs) { return __tie(lhs) != __tie(rhs); } \
namespace std {\
    template<> struct hash<Type> {\
        size_t operator()(const Type &t) const {\
            size_t ret = 0;\
            hash_combine(ret, __VA_ARGS__);\
            return ret;\
        }\
    };\
}

MAKE_HASHABLE(TextLayoutKey, t.str, t.size, t.align);

/// Main state object. This is not ObjC to avoid call overhead for each prim.
struct vger {

    id<MTLDevice> device;
    vgerRenderer* renderer;

    /// Transform matrix stack.
    std::vector<matrix_float3x3> txStack;

    /// We cycle through three prim buffers for streaming.
    id<MTLBuffer> primBuffers[3];

    /// The prim buffer we're currently using.
    int curPrimBuffer = 0;

    /// Pointer to the next prim to be saved in the buffer.
    vgerPrim* p;

    /// Number of prims we've saved in the buffer.
    int primCount = 0;

    /// Prim buffer capacity.
    int maxPrims = 16384;

    /// Atlas for finding glyph images.
    vgerGlyphCache* glyphCache;

    /// Size of rendering window (for conversion from pixel to NDC)
    float2 windowSize;

    /// Glyph scratch space (avoid malloc).
    std::vector<CGGlyph> glyphs;

    /// Cache of text layout by strings.
    std::unordered_map< TextLayoutKey, TextLayoutInfo > textCache;

    /// Determines whether we prune cached text.
    uint64_t currentFrame = 1;

    /// User-created textures.
    NSMutableArray< id<MTLTexture> >* textures;

    /// We can't insert nil into textures, so use a tiny texture instead.
    id<MTLTexture> nullTexture;

    /// Content scale factor.
    float devicePxRatio = 1.0;

    vger() {
        device = MTLCreateSystemDefaultDevice();
        renderer = [[vgerRenderer alloc] initWithDevice:device];
        glyphCache = [[vgerGlyphCache alloc] initWithDevice:device];
        for(int i=0;i<3;++i) {
            primBuffers[i] = [device newBufferWithLength:maxPrims * sizeof(vgerPrim)
                                           options:MTLResourceStorageModeShared];
            primBuffers[i].label = @"prim buffer";
        }
        txStack.push_back(matrix_identity_float3x3);

        auto desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:1 height:1 mipmapped:NO];
        nullTexture = [device newTextureWithDescriptor:desc];

        textures = [NSMutableArray new];

        assert(device.argumentBuffersSupport == MTLArgumentBuffersTier2);
    }
};

vger* vgerNew() {
    return new vger;
}

void vgerDelete(vger* vg) {
    delete vg;
}

void vgerBegin(vger* vg, float windowWidth, float windowHeight, float devicePxRatio) {
    vg->curPrimBuffer = (vg->curPrimBuffer+1)%3;
    vg->p = (vgerPrim*) vg->primBuffers[vg->curPrimBuffer].contents;
    vg->primCount = 0;
    vg->windowSize = {windowWidth, windowHeight};
    vg->devicePxRatio = devicePxRatio;
}

int  vgerAddTexture(vger* vg, const uint8_t* data, int width, int height) {
    assert(data);

    auto desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:width height:height mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead;
#if TARGET_OS_OSX
    desc.storageMode = MTLStorageModeManaged;
#else
    desc.storageMode = MTLStorageModeShared;
#endif
    auto tex = [vg->device newTextureWithDescriptor:desc];
    assert(tex);
    tex.label = @"user texture";

    [tex replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:data bytesPerRow:width*sizeof(uint32_t)];

    return vgerAddMTLTexture(vg, tex);
}

int vgerAddMTLTexture(vger* vg, id<MTLTexture> tex) {
    assert(tex);
    [vg->textures addObject:tex];
    return int(vg->textures.count)-1;
}

void vgerDeleteTexture(vger* vg, int texID) {
    assert(vg);
    [vg->textures setObject:vg->nullTexture atIndexedSubscript:texID];
}


vector_int2 vgerTextureSize(vger* vg, int texID) {
    auto tex = [vg->textures objectAtIndex:texID];
    return {int(tex.width), int(tex.height)};
}

void vgerRender(vger* vg, const vgerPrim* prim) {

    if(vg->primCount < vg->maxPrims) {
        *vg->p = *prim;
        vg->p->xform = vg->txStack.back();
        vg->p++;
        vg->primCount++;
    }

}

static float averageScale(const float3x3& M)
{
    return 0.5f * (length(M.columns[0].xy) + length(M.columns[1].xy));
}

static float2 alignOffset(CTLineRef line, int align) {

    float2 t = {0,0};
    auto lineBounds = CTLineGetImageBounds(line, nil);

    if(align & VGER_ALIGN_RIGHT) {
        t.x = -lineBounds.size.width;
    } else if(align & VGER_ALIGN_CENTER) {
        t.x = -0.5 * lineBounds.size.width;
    }

    CGFloat ascent, descent;
    CTLineGetTypographicBounds(line, &ascent, &descent, nullptr);
    if(align & VGER_ALIGN_TOP) {
        t.y = -ascent;
    } else if(align & VGER_ALIGN_MIDDLE) {
        t.y = 0.5 * (descent - ascent);
    } else if(align & VGER_ALIGN_BOTTOM) {
        t.y = descent;
    }

    return t;
}

void vgerRenderText(vger* vg, const char* str, float4 color, int align) {

    auto paint = vgerColorPaint(color);
    auto scale = averageScale(vg->txStack.back()) * vg->devicePxRatio;
    auto key = TextLayoutKey{std::string(str), scale, align};

    // Do we already have text in the cache?
    auto iter = vg->textCache.find(key);
    if(iter != vg->textCache.end()) {
        // Copy prims to output.
        auto& info = iter->second;
        info.lastFrame = vg->currentFrame;
        for(auto& prim : info.prims) {
            if(vg->primCount < vg->maxPrims) {
                *vg->p = prim;
                vg->p->xform = vg->txStack.back();
                vg->p++;
                vg->primCount++;
            }
        }
        return;
    }

    // Text cache miss, do more expensive typesetting.

    CFRange entire = CFRangeMake(0, 0);

    auto attributes = @{ NSFontAttributeName : (__bridge id)[vg->glyphCache getFont] };
    auto string = [NSString stringWithUTF8String:str];
    auto attrString = [[NSAttributedString alloc] initWithString:string attributes:attributes];
    auto typesetter = CTTypesetterCreateWithAttributedString((__bridge CFAttributedStringRef)attrString);
    auto line = CTTypesetterCreateLine(typesetter, CFRangeMake(0, attrString.length));

    auto& textInfo = vg->textCache[key];
    textInfo.lastFrame = vg->currentFrame;

    auto offset = alignOffset(line, align);

    NSArray* runs = (__bridge id) CTLineGetGlyphRuns(line);
    for(id r in runs) {
        CTRunRef run = (__bridge CTRunRef)r;
        size_t glyphCount = CTRunGetGlyphCount(run);

        vg->glyphs.resize(glyphCount);
        CTRunGetGlyphs(run, entire, vg->glyphs.data());

        for(int i=0;i<glyphCount;++i) {

            auto info = [vg->glyphCache getGlyph:vg->glyphs[i] scale:scale];
            if(info.regionIndex != -1) {

                CGRect r = CTRunGetImageBounds(run, nil, CFRangeMake(i, 1));
                float2 p = {float(r.origin.x), float(r.origin.y)};
                float2 sz = {float(r.size.width), float(r.size.height)};

                float2 a = p+offset, b = a+sz;

                float w = info.glyphBounds.size.width;
                float h = info.glyphBounds.size.height;

                float originY = info.textureHeight-GLYPH_MARGIN;

                paint.image = info.regionIndex;

                vgerPrim prim = {
                    .type = vgerGlyph,
                    .paint = paint,
                    .verts = {
                        a,
                        float2{b.x, a.y},
                        float2{a.x, b.y},
                        b,
                    },
                    .texcoords = {
                        float2{GLYPH_MARGIN,   originY},
                        float2{GLYPH_MARGIN+w, originY},
                        float2{GLYPH_MARGIN,   originY-h},
                        float2{GLYPH_MARGIN+w, originY-h},
                    },
                    .xform = vg->txStack.back()
                };

                textInfo.prims.push_back(prim);

                if(vg->primCount < vg->maxPrims) {
                    *vg->p = prim;
                    vg->p++;
                    vg->primCount++;
                }
            }
        }
    }

    CFRelease(typesetter);
    CFRelease(line);

}

void vgerTextBounds(vger* vg, const char* str, float2* min, float2* max, int align) {

    CFRange entire = CFRangeMake(0, 0);

    auto attributes = @{ NSFontAttributeName : (__bridge id)[vg->glyphCache getFont] };
    auto string = [NSString stringWithUTF8String:str];
    auto attrString = [[NSAttributedString alloc] initWithString:string attributes:attributes];
    auto typesetter = CTTypesetterCreateWithAttributedString((__bridge CFAttributedStringRef)attrString);
    auto line = CTTypesetterCreateLine(typesetter, CFRangeMake(0, attrString.length));

    auto bounds = CTLineGetImageBounds(line, nil);
    min->x = bounds.origin.x;
    min->y = bounds.origin.y;
    max->x = bounds.origin.x + bounds.size.width;
    max->y = bounds.origin.y + bounds.size.height;

    auto offset = alignOffset(line, align);
    *min += offset;
    *max += offset;

    CFRelease(line);
    CFRelease(typesetter);

}

void vgerEncode(vger* vg, id<MTLCommandBuffer> buf, MTLRenderPassDescriptor* pass) {

    // Prune the text cache.
    for(auto it = begin(vg->textCache); it != end(vg->textCache);) {
        if (it->second.lastFrame != vg->currentFrame) {
            it = vg->textCache.erase(it);
        } else {
            ++it;
        }
    }
    
    [vg->glyphCache update:buf];

    auto glyphRects = [vg->glyphCache getRects];
    auto primp = (vgerPrim*) vg->primBuffers[vg->curPrimBuffer].contents;
    for(int i=0;i<vg->primCount;++i) {
        auto& prim = primp[i];
        if(prim.type == vgerGlyph) {
            auto r = glyphRects[prim.paint.image-1];
            for(int i=0;i<4;++i) {
                prim.texcoords[i] += float2{float(r.x), float(r.y)};
            }
        }
    }

    [vg->renderer encodeTo:buf
                      pass:pass
                     prims:vg->primBuffers[vg->curPrimBuffer]
                     count:vg->primCount
                  textures:vg->textures
              glyphTexture:[vg->glyphCache getAltas]
                windowSize:vg->windowSize];

    vg->currentFrame++;

    // Do we need to create a new glyph cache?
    if(vg->glyphCache.usage > 0.8f) {
        vg->glyphCache = [[vgerGlyphCache alloc] initWithDevice:vg->device];
        vg->textCache.clear();
    }
}

void vgerTranslate(vger* vg, vector_float2 t) {
    auto M = matrix_identity_float3x3;
    M.columns[2] = vector3(t, 1);

    auto& A = vg->txStack.back();
    A = matrix_multiply(A, M);
}

/// Scales current coordinate system.
void vgerScale(vger* vg, vector_float2 s) {
    auto M = matrix_identity_float3x3;
    M.columns[0].x = s.x;
    M.columns[1].y = s.y;

    auto& A = vg->txStack.back();
    A = matrix_multiply(A, M);
}

/// Transforms a point according to the current transformation.
vector_float2 vgerTransform(vger* vg, vector_float2 p) {
    auto& M = vg->txStack.back();
    auto q = matrix_multiply(M, float3{p.x,p.y,1.0});
    return {q.x/q.z, q.y/q.z};
}

simd_float3x2 vgerCurrentTransform(vger* vg) {
    auto& M = vg->txStack.back();
    return {
        M.columns[0].xy, M.columns[1].xy, M.columns[2].xy
    };
}

void vgerSave(vger* vg) {
    vg->txStack.push_back(vg->txStack.back());
}

void vgerRestore(vger* vg) {
    vg->txStack.pop_back();
    assert(!vg->txStack.empty());
}

id<MTLTexture> vgerGetGlyphAtlas(vger* vg) {
    return [vg->glyphCache getAltas];
}

vgerPaint vgerColorPaint(vector_float4 color) {

    vgerPaint p;
    p.xform = matrix_identity_float3x3;
    p.innerColor = color;
    p.outerColor = color;
    p.image = -1;

    return p;
}

vgerPaint vgerLinearGradient(vector_float2 start, vector_float2 end,
                             vector_float4 innerColor, vector_float4 outerColor) {

    vgerPaint p;

    // Calculate transform aligned to the line
    vector_float2 d = end - start;
    if(simd_length(d) < 0.0001f) {
        d = float2{0,1};
    }

    p.xform = simd_inverse(matrix_float3x3{
        float3{d.x, d.y, 0},
        float3{-d.y, d.x, 0},
        float3{start.x, start.y, 1}
    });

    p.innerColor = innerColor;
    p.outerColor = outerColor;
    p.image = -1;

    return p;

}

vgerPaint vgerImagePattern(vector_float2 origin, vector_float2 size, float angle,
                           int image, float alpha) {

    vgerPaint p;
    p.image = image;

    matrix_float3x3 R = {
        float3{ cosf(angle), sinf(angle), 0 },
        float3{ -sinf(angle), cosf(angle), 0 },
        float3{ -origin.x, -origin.y, 1}
    };

    matrix_float3x3 S = {
        float3{ 1/size.x, 0, 0 },
        float3{ 0, 1/size.y, 0},
        float3{ 0, 0, 1}
    };

    p.xform = matrix_multiply(R, S);

    p.innerColor = p.outerColor = float4{1,1,1,alpha};

    return p;
}
