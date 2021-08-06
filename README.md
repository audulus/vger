# vger

![build status](https://github.com/audulus/vger/actions/workflows/build.yml/badge.svg)
<img src="https://img.shields.io/badge/SPM-5.3-blue.svg?style=flat"
     alt="Swift Package Manager (SPM) compatible" />

vger is a vector graphics renderer which renders a limited set of primitives, but does so almost entirely on the GPU. Works on iOS and macOS. API is plain C.

<img src="demo.png" alt="demo" width="256" height="256">

Each primitive can be filled with a solid color, gradient, or texture. vger renders primitives as instanced quads, with most of the calculations done in the fragment shader.

Here's an early screenshot from vger in use for Audulus:

<img src="bootstrap.png">

Here's it rendering that svg tiger (the cubic curves are converted to quadratic by a lousy method, and I've omitted the strokes):

<img src="tiger.png">

## Why?

I was previously using nanovg for Audulus, which was consuming too much CPU for the immediate-mode UI. nanovg is certainly more full featured, but for Audulus, vger maintains 120fps while nanovg falls to 30fps on my 120Hz iPad because of CPU-side path tessellation, and other overhead. vger renders analytically without tessellation, leaning heavily on the fragment shader.

vger isn't cross-platform (just iOS and macOS), but the API is simple enough that it could be ported fairly easily. If Audulus goes cross-platform again, I will port vger to vulkan or wgpu.

## How it works

vger draws a quad for each primitive and computes the actual primitive shape in the fragment function. For path fills, vger splits paths into horizontal slabs (see `vgerPathScanner`) to reduce the number of tests in the fragment function.

The bezier path fill case is somewhat original. To avoid having to solve quadratic equations (which has numerical issues), the fragment function uses a sort-of reverse Loop-Blinn. To determine if a point is inside or outside, vger tests against the lines formed between the endpoints of each bezier curve, flipping inside/outside for each intersection with a +x ray from the point. Then vger tests the point against the area between the bezier segment and the line, flipping inside/outside again if inside. This avoids the pre-computation of [Loop-Blinn](https://www.microsoft.com/en-us/research/wp-content/uploads/2005/01/p1000-loop.pdf), and the AA issues of [Kokojima](https://dl.acm.org/doi/10.1145/1179849.1179997).

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

See [`vger.h`](https://github.com/audulus/vger/blob/main/Sources/vger/include/vger.h) for the complete API. You can get a good sense of the usage by looking at [these tests](https://github.com/audulus/vger/blob/main/Tests/vgerTests/vgerTests.mm).

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
