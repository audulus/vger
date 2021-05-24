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
#import "vgerTileRenderer.h"

using namespace simd;
#import "sdf.h"
#import "bezier.h"
#import "vger_private.h"

vger::vger() {
    device = MTLCreateSystemDefaultDevice();
    renderer = [[vgerRenderer alloc] initWithDevice:device];
    glyphCache = [[vgerGlyphCache alloc] initWithDevice:device];
    printf("prim buffer size: %d MB\n", (int)(maxPrims * sizeof(vgerPrim))/(1024*1024));
    printf("cv buffer size: %d MB\n", (int)(maxCvs * sizeof(float2))/(1024*1024));
    printf("xform buffer size: %d MB\n", (int)(maxPrims * sizeof(simd_float3x3))/(1024*1024));
    printf("paints buffer size: %d MB\n", (int)(maxPrims * sizeof(vgerPaint))/(1024*1024));
    for(int i=0;i<3;++i) {
        auto prims = [device newBufferWithLength:maxPrims * sizeof(vgerPrim)
                                       options:MTLResourceStorageModeShared];
        prims.label = @"prim buffer";
        auto cvs = [device newBufferWithLength:maxCvs * sizeof(float2)
                                       options:MTLResourceStorageModeShared];
        cvs.label = @"cv buffer";
        auto xforms = [device newBufferWithLength:maxPrims * sizeof(simd_float3x3) options:MTLResourceStorageModeShared];
        xforms.label = @"xform buffer";

        auto paints = [device newBufferWithLength:maxPrims * sizeof(vgerPaint) options:MTLResourceStorageModeShared];
        paints.label = @"paints buffer";

        scenes[i] = {prims, cvs, xforms, paints};
    }
    txStack.push_back(matrix_identity_float3x3);

    auto desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:1 height:1 mipmapped:NO];
    nullTexture = [device newTextureWithDescriptor:desc];

    textures = [NSMutableArray new];
}

vgerContext vgerNew() {
    return new vger;
}

void vgerDelete(vgerContext vg) {
    delete vg;
}

void vgerBegin(vgerContext vg, float windowWidth, float windowHeight, float devicePxRatio) {
    vg->curBuffer = (vg->curBuffer+1)%3;
    auto& scene = vg->scenes[vg->curBuffer];
    vg->primPtr = (vgerPrim*) scene.prims.contents;
    vg->primCount = 0;
    vg->cvPtr = (float2*) scene.cvs.contents;
    vg->cvCount = 0;
    vg->xformPtr = (float3x3*) scene.xforms.contents;
    vg->xformCount = 0;
    vg->paintPtr = (vgerPaint*) scene.paints.contents;
    vg->paintCount = 0;
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
        *vg->primPtr = *prim;
        vg->primPtr->xform = vg->addxform(vg->txStack.back());
        vg->primPtr++;
        vg->primCount++;
    }

}

void vgerFillCircle(vgerContext vg, vector_float2 center, float radius, uint16_t paint) {

    vgerPrim prim {
        .type = vgerCircle,
        .cvs = { center },
        .radius = radius,
        .paint = paint
    };

    vgerRender(vg, &prim);
}

void vgerStrokeArc(vgerContext vg, vector_float2 center, float radius, float width, float rotation, float aperture, uint16_t paint) {

    vgerPrim prim {
        .type = vgerArc,
        .radius = radius,
        .cvs = { center, {sin(rotation), cos(rotation)}, {sin(aperture), cos(aperture)} },
        .width = width,
        .paint = paint
    };

    vgerRender(vg, &prim);
}

void vgerFillRect(vgerContext vg, vector_float2 min, vector_float2 max, float radius, uint16_t paint) {

    vgerPrim prim {
        .type = vgerRect,
        .radius = radius,
        .cvs = { min, max },
        .paint = paint
    };

    vgerRender(vg, &prim);
}

void vgerStrokeRect(vgerContext vg, vector_float2 min, vector_float2 max, float radius, float width, uint16_t paint) {

    vgerPrim prim {
        .type = vgerRectStroke,
        .radius = radius,
        .width = width,
        .cvs = { min, max },
        .paint = paint
    };

    vgerRender(vg, &prim);

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

bool vger::renderCachedText(const TextLayoutKey& key, uint16_t paint, uint16_t xform) {

    // Do we already have text in the cache?
    auto iter = textCache.find(key);
    if(iter != textCache.end()) {
        // Copy prims to output.
        auto& info = iter->second;
        info.lastFrame = currentFrame;
        for(auto& prim : info.prims) {
            if(primCount < maxPrims) {
                *primPtr = prim;
                primPtr->paint = paint;
                // Keep the old image index.
                // primPtr->paint.image = prim.paint.image;
                primPtr->xform = xform;
                primPtr++;
                primCount++;
            }
        }
        return true;
    }

    return false;
}

void vger::renderTextLine(CTLineRef line, TextLayoutInfo& textInfo, uint16_t paint, float2 offset, float scale, uint16_t xform) {

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
                    .quadBounds = { a, b },
                    .texBounds = {
                        float2{GLYPH_MARGIN,   originY},
                        float2{GLYPH_MARGIN+w, originY-h}
                    },
                    .xform = xform
                };

                prim.glyph = info.regionIndex;

                textInfo.prims.push_back(prim);

                if(primCount < maxPrims) {
                    *this->primPtr = prim;
                    this->primPtr++;
                    primCount++;
                }
            }
        }
    }

}

void vger::renderGlyphPath(CGGlyph glyph, uint16_t paint, float2 position, uint16_t xform) {

    auto& info = glyphPathCache.getInfo(glyph);
    auto n = cvCount;
    
    vgerSave(this);
    vgerTranslate(this, position);
    
    for(auto& prim : info.prims) {
        if(primCount < maxPrims) {
            *primPtr = prim;
            primPtr->xform = xform;
            primPtr->paint = paint;
            primPtr->start += n;
            primPtr++;
            primCount++;
        }
    }
    
    for(auto cv : info.cvs) {
        addCV(cv);
    }
    
    vgerRestore(this);
}

CTLineRef vger::createCTLine(const char* str) {

    assert(str);

    auto attributes = @{ NSFontAttributeName : (__bridge id)glyphPathCache.ctFont };
    auto string = [NSString stringWithUTF8String:str];
    auto attrString = [[NSAttributedString alloc] initWithString:string attributes:attributes];
    auto typesetter = CTTypesetterCreateWithAttributedString((__bridge CFAttributedStringRef)attrString);
    auto line = CTTypesetterCreateLine(typesetter, CFRangeMake(0, attrString.length));

    CFRelease(typesetter);
    return line;

}

bool glyphPaths = false;

void vger::renderText(const char* str, float4 color, int align) {

    assert(str);

    if(str[0] == 0) {
        return;
    }
    
    auto paint = vgerColorPaint(this, color);
    auto xform = addxform(txStack.back());
    
    if(glyphPaths) {

        auto line = createCTLine(str);
        auto offset = alignOffset(line, align);

        NSArray* runs = (__bridge id) CTLineGetGlyphRuns(line);
        for(id r in runs) {
            CTRunRef run = (__bridge CTRunRef)r;
            size_t glyphCount = CTRunGetGlyphCount(run);

            glyphs.resize(glyphCount);
            CFRange entire = CFRangeMake(0, 0);
            CTRunGetGlyphs(run, entire, glyphs.data());

            for(int i=0;i<glyphCount;++i) {

                CGRect r = CTRunGetImageBounds(run, nil, CFRangeMake(i, 1));
                float2 p = float2{float(r.origin.x), float(r.origin.y)} + offset;

                renderGlyphPath(glyphs[i], paint, p, xform);
            }
        }

        CFRelease(line);
        
    } else {

        auto scale = averageScale(txStack.back()) * devicePxRatio;
        auto key = TextLayoutKey{std::string(str), scale, align};
        
        if(renderCachedText(key, paint, xform)) {
            return;
        }

        // Text cache miss, do more expensive typesetting.
        auto line = createCTLine(str);

        auto& textInfo = textCache[key];
        textInfo.lastFrame = currentFrame;

        renderTextLine(line, textInfo, paint, alignOffset(line, align), scale, xform);

        CFRelease(line);
        
    }

}

void vgerTextBounds(vgerContext vg, const char* str, float2* min, float2* max, int align) {

    assert(str);
    assert(min);
    assert(max);

    if(str[0] == 0) {
        *min = *max = float2{0,0};
        return;
    }

    auto line = vg->createCTLine(str);

    auto bounds = CTLineGetImageBounds(line, nil);
    min->x = bounds.origin.x;
    min->y = bounds.origin.y;
    max->x = bounds.origin.x + bounds.size.width;
    max->y = bounds.origin.y + bounds.size.height;

    auto offset = alignOffset(line, align);
    *min += offset;
    *max += offset;

    CFRelease(line);

}

void vgerTextBox(vgerContext vg, const char* str, float breakRowWidth, float4 color, int align) {
    vg->renderTextBox(str, breakRowWidth, color, align);
}

static constexpr float big = 10000;

CTFrameRef vger::createCTFrame(const char* str, float breakRowWidth) {

    assert(str);

    auto attributes = @{ NSFontAttributeName : (__bridge id)[glyphCache getFont] };
    auto string = [NSString stringWithUTF8String:str];
    auto attrString = [[NSAttributedString alloc] initWithString:string attributes:attributes];
    auto framesetter = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)attrString);

    auto rectPath = CGPathCreateWithRect(CGRectMake(0, 0, breakRowWidth, big), NULL);
    auto frame = CTFramesetterCreateFrame(framesetter,
                                          CFRangeMake(0, attrString.length),
                                          rectPath,
                                          NULL);

    CFRelease(rectPath);
    CFRelease(framesetter);
    return frame;
}

void vger::renderTextBox(const char* str, float breakRowWidth, float4 color, int align) {

    assert(str);

    if(str[0] == 0) {
        return;
    }

    auto paint = vgerColorPaint(this, color);
    auto scale = averageScale(txStack.back()) * devicePxRatio;
    auto key = TextLayoutKey{std::string(str), scale, align, breakRowWidth};
    auto xform = addxform(txStack.back());

    if(renderCachedText(key, paint, xform)) {
        return;
    }

    auto frame = createCTFrame(str, breakRowWidth);

    NSArray *lines = (__bridge id)CTFrameGetLines(frame);

    std::vector<CGPoint> lineOrigins(lines.count);
    CTFrameGetLineOrigins(frame, CFRangeMake(0, 0), lineOrigins.data());

    auto& textInfo = textCache[key];
    textInfo.lastFrame = currentFrame;

    int lineIndex = 0;
    for(id obj in lines) {
        CTLineRef line = (__bridge CTLineRef)obj;
        auto o = lineOrigins[lineIndex++];
        renderTextLine(line, textInfo, paint, float2{float(o.x),float(o.y)-big}, scale, xform);
    }

    CFRelease(frame);
}

void vgerTextBoxBounds(vgerContext vg, const char* str, float breakRowWidth, float2* min, float2* max, int align) {

    assert(str);
    assert(min);
    assert(max);

    if(str[0] == 0) {
        *min = *max = float2{0,0};
        return;
    }

    CFRange entire = CFRangeMake(0, 0);

    auto frame = vg->createCTFrame(str, breakRowWidth);

    NSArray *lines = (__bridge id)CTFrameGetLines(frame);
    assert(lines);

    CGPoint lastOrigin;
    CTFrameGetLineOrigins(frame, CFRangeMake(lines.count-1, 1), &lastOrigin);
    min->x = 0;
    min->y = lastOrigin.y-big;
    max->x = breakRowWidth;
    max->y = 0;

    CFRelease(frame);

}

void vgerFillPath(vgerContext vg, float2* cvs, int count, uint16_t paint, bool scan) {
    vg->fillPath(cvs, count, paint, scan);
}

void vger::fill(uint16_t paint) {

    if(primCount == maxPrims) {
        return;
    }

    auto xform = addxform(txStack.back());

    yScanner._init();

    while(yScanner.next()) {

        int n = yScanner.activeCount;

        vgerPrim prim = {
            .type = vgerPathFill,
            .paint = paint,
            .xform = xform,
            .start = cvCount,
            .count = uint16_t(n)
        };

        if(primCount < maxPrims and cvCount+n*3 < maxCvs) {

            Interval xInt{FLT_MAX, -FLT_MAX};

            for(int a = yScanner.first; a != -1; a = yScanner.segments[a].next) {

                assert(a < yScanner.segments.size());
                for(int i=0;i<3;++i) {
                    auto p = yScanner.segments[a].cvs[i];
                    addCV(p);
                    xInt.a = std::min(xInt.a, p.x);
                    xInt.b = std::max(xInt.b, p.x);
                }

            }

            BBox bounds;
            bounds.min.x = xInt.a;
            bounds.max.x = xInt.b;
            bounds.min.y = yScanner.interval.a;
            bounds.max.y = yScanner.interval.b;

            // Calculate the prim vertices at this stage,
            // as we do for glyphs.
            prim.quadBounds[0] = prim.texBounds[0] = bounds.min;
            prim.quadBounds[1] = prim.texBounds[1] = bounds.max;

            *(primPtr++) = prim;
            primCount++;
        }
    }

    assert(yScanner.activeCount == 0);

    yScanner.segments.clear();

}

void vger::fillPath(float2* cvs, int count, uint16_t paint, bool scan) {

    if(count < 3) {
        return;
    }

    if(primCount == maxPrims) {
        return;
    }

    auto xform = addxform(txStack.back());

    if(scan) {

        yScanner.begin(cvs, count);

        while(yScanner.next()) {

            int n = yScanner.activeCount;

            vgerPrim prim = {
                .type = vgerPathFill,
                .paint = paint,
                .xform = xform,
                .start = cvCount,
                .count = uint16_t(n)
            };

            if(primCount < maxPrims and cvCount+n*3 < maxCvs) {

                Interval xInt{FLT_MAX, -FLT_MAX};

                for(int a = yScanner.first; a != -1; a = yScanner.segments[a].next) {

                    assert(a < yScanner.segments.size());
                    for(int i=0;i<3;++i) {
                        auto p = yScanner.segments[a].cvs[i];
                        addCV(p);
                        xInt.a = std::min(xInt.a, p.x);
                        xInt.b = std::max(xInt.b, p.x);
                    }

                }

                BBox bounds;
                bounds.min.x = xInt.a;
                bounds.max.x = xInt.b;
                bounds.min.y = yScanner.interval.a;
                bounds.max.y = yScanner.interval.b;

                // Calculate the prim vertices at this stage,
                // as we do for glyphs.
                prim.quadBounds[0] = prim.texBounds[0] = bounds.min;
                prim.quadBounds[1] = prim.texBounds[1] = bounds.max;

                *(primPtr++) = prim;
                primCount++;
            }
        }

        assert(yScanner.activeCount == 0);

    } else {

        bool closed = equal(cvs[0], cvs[count-1]);

        vgerPrim prim = {
            .type = vgerPathFill,
            .paint = paint,
            .xform = xform,
            .start = cvCount,
            .count = uint16_t((count-1)/2 + !closed),
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

            auto bounds = sdPrimBounds(prim, (float2*) scenes[curBuffer].cvs.contents).inset(-1);
            prim.quadBounds[0] = prim.texBounds[0] = bounds.min;
            prim.quadBounds[1] = prim.texBounds[1] = bounds.max;

            *(primPtr++) = prim;
            primCount++;
        }
    }
}

void vgerFillCubicPath(vgerContext vg, float2* cvs, int count, uint16_t paint, bool scan) {
    vg->fillCubicPath(cvs, count, paint, scan);
}

void vger::fillCubicPath(float2* cvs, int count, uint16_t paint, bool scan) {

    points.resize(0);

    for (int i = 0; i < count-2; i += 3) {
        float2 q[6];
        approx_cubic(cvs+i, q);
        if(i==0) { points.push_back(q[0]); }
        points.push_back(q[1]);
        points.push_back(q[2]);
        points.push_back(q[4]);
        points.push_back(q[5]);
    }

    fillPath(points.data(), points.size(), paint, scan);

}

void vgerMoveTo(vgerContext vg, float2 pt) {
    vg->pen = pt;
}

void vgerQuadTo(vgerContext vg, float2 b, float2 c) {
    vg->yScanner.segments.push_back({vg->pen, b, c});
    vg->pen = c;
}

void vgerCubicApproxTo(vgerContext vg, float2 b, float2 c, float2 d) {
    float2 cubic[4] = {vg->pen, b, c, d};
    float2 q[6];
    approx_cubic(cubic, q);
    vgerQuadTo(vg, q[1], q[2]);
    vgerQuadTo(vg, q[4], q[5]);
}

void vgerFill(vgerContext vg, uint16_t paint) {
    vg->fill(paint);
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
    auto& scene = scenes[curBuffer];
    auto primp = (vgerPrim*) scene.prims.contents;
    for(int i=0;i<primCount;++i) {
        auto& prim = primp[i];
        if(prim.type == vgerGlyph) {
            auto r = glyphRects[prim.glyph-1];
            for(int i=0;i<2;++i) {
                prim.texBounds[i] += float2{float(r.x), float(r.y)};
            }
        }
    }

    [renderer encodeTo:buf
                  pass:pass
                 scene:scene
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

void vgerEncodeTileRender(vgerContext vg, id<MTLCommandBuffer> buf, id<MTLTexture> renderTexture) {
    vg->encodeTileRender(buf, renderTexture);
}

void vger::encodeTileRender(id<MTLCommandBuffer> buf, id<MTLTexture> renderTexture) {

    // Create tile renderer on demand, since it uses a lot of RAM.
    if(tileRenderer == nil) {
        tileRenderer = [[vgerTileRenderer alloc] initWithDevice:device];
    }

    [tileRenderer encodeTo:buf
                     scene:scenes[curBuffer]
                     count:primCount
                  textures:textures
              glyphTexture:[glyphCache getAltas]
             renderTexture:renderTexture
                windowSize:windowSize];

}

void vgerTranslate(vgerContext vg, float2 t) {
    auto M = matrix_identity_float3x3;
    M.columns[2] = vector3(t, 1);

    auto& A = vg->txStack.back();
    A = matrix_multiply(A, M);
}

/// Scales current coordinate system.
void vgerScale(vgerContext vg, float2 s) {
    auto M = matrix_identity_float3x3;
    M.columns[0].x = s.x;
    M.columns[1].y = s.y;

    auto& A = vg->txStack.back();
    A = matrix_multiply(A, M);
}

/// Transforms a point according to the current transformation.
float2 vgerTransform(vgerContext vg, float2 p) {
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

id<MTLTexture> vgerGetCoarseDebugTexture(vgerContext vg) {
    return [vg->tileRenderer getDebugTexture];
}

uint16_t vgerColorPaint(vgerContext vg, float4 color) {

    vgerPaint p;
    p.xform = matrix_identity_float3x3;
    p.innerColor = color;
    p.outerColor = color;
    p.image = -1;

    return vg->addPaint(p);
}

uint16_t vgerLinearGradient(vgerContext vg, float2 start, float2 end,
                             float4 innerColor, float4 outerColor) {

    return vg->addPaint(makeLinearGradient(start, end, innerColor, outerColor));

}

uint16_t vgerImagePattern(vgerContext vg, float2 origin, float2 size, float angle,
                           int image, float alpha) {

    vgerPaint p;
    p.image = image;

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

    p.xform = matrix_multiply(R, S);

    p.innerColor = p.outerColor = float4{1,1,1,alpha};

    return vg->addPaint(p);
}
