# vger (WIP)

vger is a vector graphics renderer which renders a limited set of primitives, but does so almost entirely on the GPU using a single draw call. Works on iOS and macOS.

<img src="demo.png" alt="demo" width="256" height="256">

Each primitive can be filled with a solid color, or a texture (gradients are forthcoming).

## Usage

Create a rendering context using `vgerNew()`.

Then call `vgerRenderPrim` and `vgerRenderText` to store drawing commands. See `vger.h` for transformation functions.

Finally, call `vgerEncode` to encode rendering commands to a `MTLCommandBuffer`.
