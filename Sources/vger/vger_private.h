//  Copyright © 2021 Audulus LLC. All rights reserved.

#pragma once

#include <string>
#include <vector>
#include <unordered_map>
#include "vgerPathScanner.h"
#include "vgerGlyphPathCache.h"
#include "vgerScene.h"
#include "paint.h"

@class vgerRenderer;
@class vgerGlyphCache;

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
    float breakRowWidth = -1;

    friend bool operator==(const TextLayoutKey&, const TextLayoutKey&) = default;
    friend bool operator!=(const TextLayoutKey&, const TextLayoutKey&) = default;
};

inline void hash_combine(size_t& seed) { }

template <typename T, typename... Rest>
inline void hash_combine(size_t& seed, const T& v, Rest... rest) {
    std::hash<T> hasher;
    seed ^= hasher(v) + 0x9e3779b9 + (seed<<6) + (seed>>2);
    hash_combine(seed, rest...);
}

#define MAKE_HASHABLE(Type, ...) \
namespace std {\
    template<> struct hash<Type> {\
        size_t operator()(const Type &t) const {\
            size_t ret = 0;\
            hash_combine(ret, __VA_ARGS__);\
            return ret;\
        }\
    };\
}

MAKE_HASHABLE(TextLayoutKey, t.str, t.size, t.align, t.breakRowWidth);

/// Main state object. This is not ObjC to avoid call overhead for each prim.
struct vger {

    id<MTLDevice> device;
    vgerRenderer* renderer;

    vgerRenderer* glowRenderer;

    /// Transform matrix stack.
    std::vector<float3x3> txStack;

    /// Number of buffers.
    int maxBuffers = 1;

    /// We cycle through three scenes for streaming.
    vgerScene scenes[3];

    /// The current scene we're writing to.
    int currentScene = 0;

    /// Current layer we're rendering to.
    int currentLayer = 0;

    /// Number of layers.
    int layerCount = 1;

    /// Atlas for finding glyph images.
    vgerGlyphCache* glyphCache;

    /// Size of rendering window (for conversion from pixel to NDC)
    float2 windowSize;

    /// Glyph scratch space (avoid malloc).
    std::vector<CGGlyph> glyphs;

    /// Cache of text layout by strings.
    std::unordered_map< TextLayoutKey, TextLayoutInfo > textCache;

    /// Points scratch space (avoid malloc).
    std::vector<float2> points;

    /// Determines whether we prune cached text.
    uint64_t currentFrame = 1;

    /// User-created textures.
    NSMutableArray< id<MTLTexture> >* textures;

    /// We can't insert nil into textures, so use a tiny texture instead.
    id<MTLTexture> nullTexture;

    /// Content scale factor.
    float devicePxRatio = 1.0;

    /// For speeding up path rendering.
    vgerPathScanner yScanner;

    /// For generating glyph paths.
    vgerGlyphPathCache glyphPathCache;

    /// The current location when creating paths.
    float2 pen;

    /// For loading images from files.
    MTKTextureLoader* textureLoader;

    /// Have we already computed glyph bounds?
    bool computedGlyphBounds = false;

    /// Used in vgerTextBounds.
    std::vector<CGPoint> origins;

    /// Used in vgerStrokeBezier.
    std::vector<vgerBezierSegment> segments;

    vger(uint32_t flags, MTLPixelFormat pixelFormat);

    void addPrim(const vgerPrim& prim) {
        scenes[currentScene].prims[currentLayer].append(prim);
    }

    auto primCount() -> size_t {
        return scenes[currentScene].prims[currentLayer].count;
    }

    void addCV(float2 p) {
        scenes[currentScene].cvs.append(p);
    }

    uint32_t addxform(const matrix_float3x3& M) {
        uint32_t idx = (uint32_t) scenes[currentScene].xforms.count;
        scenes[currentScene].xforms.append(M);
        return idx;
    }

    vgerPaintIndex addPaint(const vgerPaint& paint) {
        uint32_t idx = (uint32_t) scenes[currentScene].paints.count;
        scenes[currentScene].paints.append(paint);
        return {idx};
    }

    /// Ensure a paint index is valid.
    auto checkPaint(vgerPaintIndex index) -> bool {
        return index.index < scenes[currentScene].paints.count;
    }

    CTLineRef createCTLine(const char* str);
    CTFrameRef createCTFrame(const char* str, int align, float breakRowWidth);

    void begin(float windowWidth, float windowHeight, float devicePxRatio);

    bool fill(vgerPaintIndex paint);

    void fillForTile(vgerPaintIndex paint);

    void encode(id<MTLCommandBuffer> buf, MTLRenderPassDescriptor* pass, bool glow);

    void encodeTileRender(id<MTLCommandBuffer> buf, id<MTLTexture> renderTexture);

    bool renderCachedText(const TextLayoutKey& key, vgerPaintIndex paint, uint32_t xform);

    void renderTextLine(CTLineRef line, TextLayoutInfo& textInfo, vgerPaintIndex paint, float2 offset, float scale, uint32_t xform);

    void renderText(const char* str, float4 color, int align);

    void renderTextBox(const char* str, float breakRowWidth, float4 color, int align);

    void renderGlyphPath(CGGlyph glyph, vgerPaintIndex paint, float2 position, uint32_t xform);
};

inline vgerPaint makeLinearGradient(float2 start,
                                    float2 end,
                                    float4 innerColor,
                                    float4 outerColor,
                                    float glow) {
    
    vgerPaint p;
    p.type = vgerPaintTypeLinearGradient;

    // Calculate transform aligned to the line
    float2 d = end - start;
    if(length(d) < 0.0001f) {
        d = float2{0,1};
    }

    p.xform = inverse(float3x3{
        float3{d.x, d.y, 0},
        float3{-d.y, d.x, 0},
        float3{start.x, start.y, 1}
    });

    p.innerColor = innerColor;
    p.outerColor = outerColor;
    p.image = -1;
    p.glow = glow;

    return p;
}

inline vgerPaint makeRadialGradient(float2 center,
                                    float  innerRadius,
                                    float  outerRadius,
                                    float4 innerColor,
                                    float4 outerColor,
                                    float glow) {

    vgerPaint p;
    p.type = vgerPaintTypeRadialGradient;

    p.xform = inverse(float3x3{
        float3{1, 0, 0},
        float3{0, 1, 0},
        float3{center.x, center.y, 1}
    });

    p.innerRadius = innerRadius;
    p.outerRadius = outerRadius;
    p.innerColor = innerColor;
    p.outerColor = outerColor;
    p.image = -1;
    p.glow = glow;

    return p;
}

inline vgerPaint makeImagePattern(float2 origin,
                                  float2 size,
                                  float angle,
                                  bool flipY,
                                  vgerImageIndex image,
                                  float alpha) {

    vgerPaint p;
    p.type  = vgerPaintTypeImagePattern;
    p.image = image.index;
    p.flipY = flipY;

    float3x3 R = {
        float3{ cosf(angle), sinf(angle), 0 },
        float3{ -sinf(angle), cosf(angle), 0 },
        float3{ -origin.x, -origin.y, 1}
    };

    float3x3 S = {
        float3{ 1/size.x, 0, 0 },
        float3{ 0, 1/size.y, 0},
        float3{ 0, 0, 1}
    };

    p.xform = matrix_multiply(S, R);

    p.innerColor = p.outerColor = float4{1,1,1,alpha};
    p.glow = 0;

    return p;
}
