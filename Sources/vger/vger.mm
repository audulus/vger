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
#import "vgerPathScanner.h"
#import "vgerGlyphPathCache.h"
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
    int maxPrims = 16384;

    /// Cycle through 3 cv buffers for streaming.
    id<MTLBuffer> cvBuffers[3];

    /// Pointer to the next cv to be saved in the buffer.
    float2* cv;

    /// Number of cvs we've saved in the current cv buffer.
    int cvCount = 0;

    /// CV buffer capacity.
    int maxCvs = 16384;

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

    /// For speeding up path rendering.
    vgerPathScanner scan;
    
    /// For generating glyph paths.
    vgerGlyphPathCache glyphPathCache;

    vger() {
        device = MTLCreateSystemDefaultDevice();
        renderer = [[vgerRenderer alloc] initWithDevice:device];
        glyphCache = [[vgerGlyphCache alloc] initWithDevice:device];
        for(int i=0;i<3;++i) {
            primBuffers[i] = [device newBufferWithLength:maxPrims * sizeof(vgerPrim)
                                           options:MTLResourceStorageModeShared];
            primBuffers[i].label = @"prim buffer";
            cvBuffers[i] = [device newBufferWithLength:maxCvs * sizeof(float2)
                                           options:MTLResourceStorageModeShared];
            cvBuffers[i].label = @"cv buffer";
        }
        txStack.push_back(matrix_identity_float3x3);

        auto desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:1 height:1 mipmapped:NO];
        nullTexture = [device newTextureWithDescriptor:desc];

        textures = [NSMutableArray new];
    }

    void addCV(float2 p) {
        if(cvCount < maxCvs) {
            *(cv++) = p;
            cvCount++;
        }
    }

    void fillPath(float2* cvs, int count, vgerPaint paint);

    void encode(id<MTLCommandBuffer> buf, MTLRenderPassDescriptor* pass);

    bool renderCachedText(const TextLayoutKey& key, const vgerPaint& paint);

    void renderTextLine(CTLineRef line, TextLayoutInfo& textInfo, const vgerPaint& paint, float2 offset, float scale);

    void renderText(const char* str, float4 color, int align);

    void renderTextBox(const char* str, float breakRowWidth, float4 color, int align);
    
    void renderGlyphPath(CGGlyph glyph, const vgerPaint& paint, float2 position);
};

vgerContext vgerNew() {
    return new vger;
}

void vgerDelete(vgerContext vg) {
    delete vg;
}

void vgerBegin(vgerContext vg, float windowWidth, float windowHeight, float devicePxRatio) {
    vg->curBuffer = (vg->curBuffer+1)%3;
    vg->p = (vgerPrim*) vg->primBuffers[vg->curBuffer].contents;
    vg->primCount = 0;
    vg->cv = (float2*) vg->cvBuffers[vg->curBuffer].contents;
    vg->cvCount = 0;
    vg->windowSize = {windowWidth, windowHeight};
    vg->devicePxRatio = devicePxRatio;
}

int  vgerAddTexture(vgerContext vg, const uint8_t* data, int width, int height) {
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

int vgerAddMTLTexture(vgerContext vg, id<MTLTexture> tex) {
    assert(tex);
    [vg->textures addObject:tex];
    return int(vg->textures.count)-1;
}

void vgerDeleteTexture(vgerContext vg, int texID) {
    assert(vg);
    [vg->textures setObject:vg->nullTexture atIndexedSubscript:texID];
}


vector_int2 vgerTextureSize(vgerContext vg, int texID) {
    auto tex = [vg->textures objectAtIndex:texID];
    return {int(tex.width), int(tex.height)};
}

void vgerRender(vgerContext vg, const vgerPrim* prim) {

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

void vgerText(vgerContext vg, const char* str, float4 color, int align) {
    vg->renderText(str, color, align);
}

bool vger::renderCachedText(const TextLayoutKey& key, const vgerPaint& paint) {

    // Do we already have text in the cache?
    auto iter = textCache.find(key);
    if(iter != textCache.end()) {
        // Copy prims to output.
        auto& info = iter->second;
        info.lastFrame = currentFrame;
        for(auto& prim : info.prims) {
            if(primCount < maxPrims) {
                *p = prim;
                p->paint = paint;
                // Keep the old image index.
                p->paint.image = prim.paint.image;
                p->xform = txStack.back();
                p++;
                primCount++;
            }
        }
        return true;
    }

    return false;
}

void vger::renderTextLine(CTLineRef line, TextLayoutInfo& textInfo, const vgerPaint& paint, float2 offset, float scale) {

    CFRange entire = CFRangeMake(0, 0);

    NSArray* runs = (__bridge id) CTLineGetGlyphRuns(line);
    for(id r in runs) {
        CTRunRef run = (__bridge CTRunRef)r;
        size_t glyphCount = CTRunGetGlyphCount(run);

        glyphs.resize(glyphCount);
        CTRunGetGlyphs(run, entire, glyphs.data());

        for(int i=0;i<glyphCount;++i) {

            auto info = [glyphCache getGlyph:glyphs[i] scale:scale];
            if(info.regionIndex != -1) {

                CGRect r = CTRunGetImageBounds(run, nil, CFRangeMake(i, 1));
                float2 p = {float(r.origin.x), float(r.origin.y)};
                float2 sz = {float(r.size.width), float(r.size.height)};

                float2 a = p+offset, b = a+sz;

                float w = info.glyphBounds.size.width;
                float h = info.glyphBounds.size.height;

                float originY = info.textureHeight-GLYPH_MARGIN;

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
                    .xform = txStack.back()
                };

                prim.paint.image = info.regionIndex;

                textInfo.prims.push_back(prim);

                if(primCount < maxPrims) {
                    *this->p = prim;
                    this->p++;
                    primCount++;
                }
            }
        }
    }

}

void vger::renderGlyphPath(CGGlyph glyph, const vgerPaint& paint, float2 position) {

    auto& info = glyphPathCache.getInfo(glyph);
    auto n = cvCount;
    
    vgerSave(this);
    vgerTranslate(this, position);
    
    for(auto& prim : info.prims) {
        if(primCount < maxPrims) {
            *p = prim;
            p->xform = txStack.back();
            p->paint = paint;
            p->start += n;
            p++;
            primCount++;
        }
    }
    
    for(auto cv : info.cvs) {
        addCV(cv);
    }
    
    vgerRestore(this);
}

bool glyphPaths = false;

void vger::renderText(const char* str, float4 color, int align) {
    
    auto paint = vgerColorPaint(color);
    
    if(glyphPaths) {
        
        CFRange entire = CFRangeMake(0, 0);
        
        auto attributes = @{ NSFontAttributeName : (__bridge id)glyphPathCache.ctFont };
        auto string = [NSString stringWithUTF8String:str];
        auto attrString = [[NSAttributedString alloc] initWithString:string attributes:attributes];
        auto typesetter = CTTypesetterCreateWithAttributedString((__bridge CFAttributedStringRef)attrString);
        auto line = CTTypesetterCreateLine(typesetter, CFRangeMake(0, attrString.length));
        
        NSArray* runs = (__bridge id) CTLineGetGlyphRuns(line);
        for(id r in runs) {
            CTRunRef run = (__bridge CTRunRef)r;
            size_t glyphCount = CTRunGetGlyphCount(run);

            glyphs.resize(glyphCount);
            CTRunGetGlyphs(run, entire, glyphs.data());

            for(int i=0;i<glyphCount;++i) {
                
                CGRect r = CTRunGetImageBounds(run, nil, CFRangeMake(i, 1));
                float2 p = {float(r.origin.x), float(r.origin.y)};
                
                renderGlyphPath(glyphs[i], paint, p);
            }
        }
        
        CFRelease(typesetter);
        CFRelease(line);
        
    } else {

        auto scale = averageScale(txStack.back()) * devicePxRatio;
        auto key = TextLayoutKey{std::string(str), scale, align};
        
        if(renderCachedText(key, paint)) {
            return;
        }
        
        // Text cache miss, do more expensive typesetting.
        
        auto attributes = @{ NSFontAttributeName : (__bridge id)[glyphCache getFont] };
        auto string = [NSString stringWithUTF8String:str];
        auto attrString = [[NSAttributedString alloc] initWithString:string attributes:attributes];
        auto typesetter = CTTypesetterCreateWithAttributedString((__bridge CFAttributedStringRef)attrString);
        auto line = CTTypesetterCreateLine(typesetter, CFRangeMake(0, attrString.length));
        
        auto& textInfo = textCache[key];
        textInfo.lastFrame = currentFrame;
        
        renderTextLine(line, textInfo, paint, alignOffset(line, align), scale);
        
        CFRelease(typesetter);
        CFRelease(line);
        
    }

}

void vgerTextBounds(vgerContext vg, const char* str, float2* min, float2* max, int align) {

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

void vgerTextBox(vgerContext vg, const char* str, float breakRowWidth, float4 color, int align) {
    vg->renderTextBox(str, breakRowWidth, color, align);
}

void vger::renderTextBox(const char* str, float breakRowWidth, float4 color, int align) {

    auto paint = vgerColorPaint(color);
    auto scale = averageScale(txStack.back()) * devicePxRatio;
    auto key = TextLayoutKey{std::string(str), scale, align, breakRowWidth};

    if(renderCachedText(key, paint)) {
        return;
    }

    auto attributes = @{ NSFontAttributeName : (__bridge id)[glyphCache getFont] };
    auto string = [NSString stringWithUTF8String:str];
    auto attrString = [[NSAttributedString alloc] initWithString:string attributes:attributes];
    auto framesetter = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)attrString);
    float big = 10000;
    auto rectPath = CGPathCreateWithRect(CGRectMake(0, 0, breakRowWidth, big), NULL);
    auto frame = CTFramesetterCreateFrame(framesetter,
                                          CFRangeMake(0, attrString.length),
                                          rectPath,
                                          NULL);

    NSArray *lines = (__bridge id)CTFrameGetLines(frame);

    std::vector<CGPoint> lineOrigins(lines.count);
    CTFrameGetLineOrigins(frame, CFRangeMake(0, 0), lineOrigins.data());

    auto& textInfo = textCache[key];
    textInfo.lastFrame = currentFrame;

    int lineIndex = 0;
    for(id obj in lines) {
        CTLineRef line = (__bridge CTLineRef)obj;
        auto o = lineOrigins[lineIndex++];
        renderTextLine(line, textInfo, paint, float2{float(o.x),float(o.y)-big}, scale);
    }

    CFRelease(frame);
    CFRelease(framesetter);
    CFRelease(rectPath);
}

void vgerTextBoxBounds(vgerContext vg, const char* str, float breakRowWidth, float2* min, float2* max, int align) {

    CFRange entire = CFRangeMake(0, 0);

    auto attributes = @{ NSFontAttributeName : (__bridge id)[vg->glyphCache getFont] };
    auto string = [NSString stringWithUTF8String:str];
    auto attrString = [[NSAttributedString alloc] initWithString:string attributes:attributes];
    auto framesetter = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)attrString);
    float big = 10000;
    auto rectPath = CGPathCreateWithRect(CGRectMake(0, 0, breakRowWidth, big), NULL);
    auto frame = CTFramesetterCreateFrame(framesetter,
                                          CFRangeMake(0, attrString.length),
                                          rectPath,
                                          NULL);

    NSArray *lines = (__bridge id)CTFrameGetLines(frame);

    CGPoint lastOrigin;
    CTFrameGetLineOrigins(frame, CFRangeMake(lines.count-1, 1), &lastOrigin);
    min->x = 0;
    min->y = lastOrigin.y-big;
    max->x = breakRowWidth;
    max->y = 0;

    CFRelease(frame);
    CFRelease(framesetter);
    CFRelease(rectPath);

}

bool scanPaths = true;

void vgerFillPath(vgerContext vg, float2* cvs, int count, vgerPaint paint) {
    vg->fillPath(cvs, count, paint);
}

void vger::fillPath(float2* cvs, int count, vgerPaint paint) {

    if(count < 3) {
        return;
    }

    if(scanPaths) {

        scan.begin(cvs, count);

        while(scan.next()) {

            int n = scan.activeCount;

            vgerPrim prim = {
                .type = vgerPathFill,
                .paint = paint,
                .xform = txStack.back(),
                .start = cvCount,
                .count = n
            };

            if(primCount < maxPrims and cvCount+n*3 < maxCvs) {

                Interval xInt{FLT_MAX, -FLT_MAX};

                for(int a = scan.first; a != -1; a = scan.segments[a].next) {

                    assert(a < scan.segments.size());
                    for(int i=0;i<3;++i) {
                        auto p = scan.segments[a].cvs[i];
                        addCV(p);
                        xInt.a = std::min(xInt.a, p.x);
                        xInt.b = std::max(xInt.b, p.x);
                    }

                }

                BBox bounds;
                bounds.min.x = xInt.a;
                bounds.max.x = xInt.b;
                bounds.min.y = scan.yInterval.a;
                bounds.max.y = scan.yInterval.b;

                // Calculate the prim vertices at this stage,
                // as we do for glyphs.
                prim.texcoords[0] = bounds.min;
                prim.texcoords[1] = float2{bounds.max.x, bounds.min.y};
                prim.texcoords[2] = float2{bounds.min.x, bounds.max.y};
                prim.texcoords[3] = bounds.max;

                for(int i=0;i<4;++i) {
                    prim.verts[i] = prim.texcoords[i];
                }

                *(p++) = prim;
                primCount++;
            }
        }

        assert(scan.activeCount == 0);

    } else {

        bool closed = simd_equal(cvs[0], cvs[count-1]);

        vgerPrim prim = {
            .type = vgerPathFill,
            .paint = paint,
            .xform = txStack.back(),
            .start = cvCount,
            .count = (count-1)/2 + !closed,
            .width = 0
        };

        if(primCount < maxPrims and cvCount+3*prim.count+3*(!closed) < maxCvs) {

            for(int i=0;i<count-2;i+=2) {
                addCV(cvs[i]);
                addCV(cvs[i+1]);
                addCV(cvs[i+2]);
            }

            if(!closed) {
                auto end = cvs[count-1];
                auto start = cvs[0];
                addCV(end);
                addCV((start+end)/2);
                addCV(start);
            }

            auto bounds = sdPrimBounds(prim, (float2*) cvBuffers[curBuffer].contents).inset(-1);
            prim.texcoords[0] = bounds.min;
            prim.texcoords[1] = float2{bounds.max.x, bounds.min.y};
            prim.texcoords[2] = float2{bounds.min.x, bounds.max.y};
            prim.texcoords[3] = bounds.max;

            for(int i=0;i<4;++i) {
                prim.verts[i] = prim.texcoords[i];
            }

            *(p++) = prim;
            primCount++;
        }
    }
}

void vgerEncode(vgerContext vg, id<MTLCommandBuffer> buf, MTLRenderPassDescriptor* pass) {
    vg->encode(buf, pass);
}

void vger::encode(id<MTLCommandBuffer> buf, MTLRenderPassDescriptor* pass) {

    // Prune the text cache.
    for(auto it = begin(textCache); it != end(textCache);) {
        if (it->second.lastFrame != currentFrame) {
            it = textCache.erase(it);
        } else {
            ++it;
        }
    }
    
    [glyphCache update:buf];

    auto glyphRects = [glyphCache getRects];
    auto primp = (vgerPrim*) primBuffers[curBuffer].contents;
    for(int i=0;i<primCount;++i) {
        auto& prim = primp[i];
        if(prim.type == vgerGlyph) {
            auto r = glyphRects[prim.paint.image-1];
            for(int i=0;i<4;++i) {
                prim.texcoords[i] += float2{float(r.x), float(r.y)};
            }
        }
    }

    [renderer encodeTo:buf
                  pass:pass
                 prims:primBuffers[curBuffer]
                   cvs:cvBuffers[curBuffer]
                 count:primCount
              textures:textures
          glyphTexture:[glyphCache getAltas]
            windowSize:windowSize];

    currentFrame++;

    // Do we need to create a new glyph cache?
    if(glyphCache.usage > 0.8f) {
        glyphCache = [[vgerGlyphCache alloc] initWithDevice:device];
        textCache.clear();
    }
}

void vgerTranslate(vgerContext vg, vector_float2 t) {
    auto M = matrix_identity_float3x3;
    M.columns[2] = vector3(t, 1);

    auto& A = vg->txStack.back();
    A = matrix_multiply(A, M);
}

/// Scales current coordinate system.
void vgerScale(vgerContext vg, vector_float2 s) {
    auto M = matrix_identity_float3x3;
    M.columns[0].x = s.x;
    M.columns[1].y = s.y;

    auto& A = vg->txStack.back();
    A = matrix_multiply(A, M);
}

/// Transforms a point according to the current transformation.
vector_float2 vgerTransform(vgerContext vg, vector_float2 p) {
    auto& M = vg->txStack.back();
    auto q = matrix_multiply(M, float3{p.x,p.y,1.0});
    return {q.x/q.z, q.y/q.z};
}

simd_float3x2 vgerCurrentTransform(vgerContext vg) {
    auto& M = vg->txStack.back();
    return {
        M.columns[0].xy, M.columns[1].xy, M.columns[2].xy
    };
}

void vgerSave(vgerContext vg) {
    vg->txStack.push_back(vg->txStack.back());
}

void vgerRestore(vgerContext vg) {
    vg->txStack.pop_back();
    assert(!vg->txStack.empty());
}

id<MTLTexture> vgerGetGlyphAtlas(vgerContext vg) {
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
