//  Copyright © 2021 Audulus LLC. All rights reserved.

#ifndef TestUtils_h
#define TestUtils_h

#include <Foundation/Foundation.h>
#include <Metal/Metal.h>

void writeCGImage(CGImageRef image, CFURLRef url);
CGImageRef makeImage(UInt8* data, int w, int h);
CGImageRef textureImage(id<MTLTexture> texture);
void showTexture(id<MTLTexture> texture, NSString* name);
bool checkTexture(id<MTLTexture> texture, NSString* name);

#endif /* TestUtils_h */
