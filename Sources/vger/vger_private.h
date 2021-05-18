//  Copyright © 2021 Audulus LLC. All rights reserved.

#ifndef vger_private_h
#define vger_private_h

#include <string>
#include <vector>
#include <unordered_map>
#include "vgerPathScanner.h"
#include "vgerGlyphPathCache.h"

@class vgerRenderer;
@class vgerTileRenderer;
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

MAKE_HASHABLE(TextLayoutKey, t.str, t.size, t.align, t.breakRowWidth);

/// Main state object. This is not ObjC to avoid call overhead for each prim.
struct vger {

    id<MTLDevice> device;
    vgerRenderer* renderer;

    /// New experimental tile renderer.
    vgerTileRenderer* tileRenderer;

    /// Transform matrix stack.
    std::vector<matrix_float3x3> txStack;

    /// We cycle through three prim buffers for streaming.
    id<MTLBuffer> primBuffers[3];

    /// The prim buffer we're currently using.
    int curBuffer = 0;

    /// Pointer to the next prim to be saved in the buffer.
    vgerPrim* p;

    /// Number of prims we've saved in the buffer.
    int primCount = 0;

    /// Prim buffer capacity.
    int maxPrims = 65536;

    /// Cycle through 3 cv buffers for streaming.
    id<MTLBuffer> cvBuffers[3];

    /// Pointer to the next cv to be saved in the buffer.
    float2* cv;

    /// Number of cvs we've saved in the current cv buffer.
    int cvCount = 0;

    /// CV buffer capacity.
    int maxCvs = 1024*1024;

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
    vgerPathScanner scanner;

    /// For generating glyph paths.
    vgerGlyphPathCache glyphPathCache;

    vger();

    void addCV(float2 p) {
        if(cvCount < maxCvs) {
            *(cv++) = p;
            cvCount++;
        }
    }

    CTLineRef createCTLine(const char* str);
    CTFrameRef createCTFrame(const char* str, float breakRowWidth);

    void fillPath(float2* cvs, int count, vgerPaint paint, bool scan);

    void fillCubicPath(float2* cvs, int count, vgerPaint paint, bool scan);

    void encode(id<MTLCommandBuffer> buf, MTLRenderPassDescriptor* pass);

    void encodeTileRender(id<MTLCommandBuffer> buf, id<MTLTexture> renderTexture);

    bool renderCachedText(const TextLayoutKey& key, const vgerPaint& paint);

    void renderTextLine(CTLineRef line, TextLayoutInfo& textInfo, const vgerPaint& paint, float2 offset, float scale);

    void renderText(const char* str, float4 color, int align);

    void renderTextBox(const char* str, float breakRowWidth, float4 color, int align);

    void renderGlyphPath(CGGlyph glyph, const vgerPaint& paint, float2 position);
};

#endif /* vger_private_h */
