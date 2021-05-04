# vger (WIP)

vger is a vector graphics renderer which renders a limited set of primitives, but does so almost entirely on the GPU. Works on iOS and macOS.

<img src="demo.png" alt="demo" width="256" height="256">

Each primitive can be filled with a solid color, gradient, or texture.

Here's an early screenshot from vger in use for Audulus:

<img src="bootstrap.png">

The rectangles around primitives are for debugging drawing areas.

## Installation

To add vger to your Xcode project, select File -> Swift Packages -> Add Package Depedancy. Enter https://github.com/audulus/vger for the URL. Check the use branch option and enter `main`.

## Usage

Create a rendering context using `vgerNew()`.

Then call `vgerRenderPrim` and `vgerRenderText` to store drawing commands. See `vger.h` for transformation functions.

Finally, call `vgerEncode` to encode rendering commands to a `MTLCommandBuffer`.
