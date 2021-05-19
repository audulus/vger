//  Copyright © 2021 Audulus LLC. All rights reserved.

import Metal
import MetalKit
import vger

/// Renderer for experimental tile-based rendering.
class TileRenderer: NSObject, MTKViewDelegate {

    var vg = vgerNew()
    var device: MTLDevice!
    var queue: MTLCommandQueue!
    var renderCallback : ((OpaquePointer) -> Void)?
    var textureRenderer: TextureRenderer!
    var renderTexture: MTLTexture!

    static let MaxBuffers = 3
    private let inflightSemaphore = DispatchSemaphore(value: MaxBuffers)

    init(device: MTLDevice) {
        self.device = device
        queue = device.makeCommandQueue()
        textureRenderer = TextureRenderer(device: device, pixelFormat: .bgra8Unorm)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Int(size.width), height: Int(size.height), mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        renderTexture = device.makeTexture(descriptor: desc)
    }

    func draw(in view: MTKView) {

        let size = view.frame.size
        let w = Float(size.width)
        let h = Float(size.height)
        let scale = Float(view.contentScaleFactor)

        if w == 0 || h == 0 {
            return
        }

        vgerBegin(vg, w, h, scale)

        // use semaphore to encode 3 frames ahead
        _ = inflightSemaphore.wait(timeout: DispatchTime.distantFuture)

        let commandBuffer = queue.makeCommandBuffer()!

        let semaphore = inflightSemaphore
        commandBuffer.addCompletedHandler { _ in
            semaphore.signal()
        }

        renderCallback?(vg!)

        if let renderPassDescriptor = view.currentRenderPassDescriptor, let currentDrawable = view.currentDrawable {

            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

            vgerEncodeTileRender(vg!, commandBuffer, renderTexture)

            textureRenderer.encode(to: commandBuffer, pass: renderPassDescriptor, texture: renderTexture)

            commandBuffer.present(currentDrawable)
        }
        commandBuffer.commit()
    }

    deinit {
        vgerDelete(vg)
    }

}

