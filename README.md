# vger

![build status](https://github.com/audulus/vger/actions/workflows/build.yml/badge.svg)

vger is a vector graphics renderer which renders a limited set of primitives, but does so almost entirely on the GPU. Works on iOS and macOS.

<img src="demo.png" alt="demo" width="256" height="256">

Each primitive can be filled with a solid color, gradient, or texture. vger renders primitives as instanced quads, with most of the calculations done in the fragment shader.

Here's an early screenshot from vger in use for Audulus:

<img src="bootstrap.png">

## Why?

I was previously using nanovg for Audulus, which was consuming too much CPU for the immediate-mode UI. nanovg is certainly more full featured, but for Audulus, vger maintains 120fps while nanovg falls to 30fps on my 120Hz iPad because of CPU-side path tessellation, and other overhead. vger renders analytically without tessellation, leaning heavily on the fragment shader.

vger isn't cross-platform (just iOS and macOS), but the API is simple enough that it could be ported fairly easily. If Audulus goes cross-platform again, I will port vger to vulkan or wgpu.

## Status

- ✅ Quadratic bezier strokes 
- ✅ Round Rectangles
- ✅ Circles
- ✅ Line segments (need square ends for Audulus)
- ✅ Arcs
- ✅ Text (Audulus only uses one font, but could add support for more if anyone is interested)
- ✅ Multi-line text
- ✅ Path Fills.

## Installation

To add vger to your Xcode project, select File -> Swift Packages -> Add Package Depedancy. Enter https://github.com/audulus/vger for the URL. Check the use branch option and enter `main`.

## Usage

Create a rendering context using `vgerNew()`.

Then call `vgerRenderPrim` and `vgerText` to store drawing commands. vger doesn't support arbitrary path fills and strokes, instead focusing on primitives that can be easily rendered on the GPU.

See [`vger.h`](https://github.com/audulus/vger/blob/main/Sources/vger/include/vger.h) for the complete API. You can get a good sense of the usage by looking at [these tests](https://github.com/audulus/vger/blob/main/Tests/vgerTests/vgerTests.mm).

Finally, call `vgerEncode` to encode rendering commands to a `MTLCommandBuffer`.

Vger has a C interface and can be used from C, C++, ObjC, or Swift. `vgerEncode` must be called from either ObjC or Swift since it takes a `MTLCommandBuffer`.

See [the demo app](https://github.com/audulus/vger-demo) for an example of using vger in a iOS/macOS SwiftUI app. vger includes `VgerView` to make it really easy to use Vger within SwiftUI:

```swift
import SwiftUI
import vger      // C/C++/ObjC interface.
import vgerSwift // Swift nicities.

struct HelloView: View {

    let cyan = SIMD4<Float>(0,1,1,1)

    var body: some View {
        VgerView(renderCallback: { vger in
            vgerText(vger, "Hello world. This is V'Ger.", cyan, 0)
        })
    }
}
```
