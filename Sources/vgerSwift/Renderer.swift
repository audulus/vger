//  Copyright © 2021 Audulus LLC. All rights reserved.

import Metal
import MetalKit
import vger

class Renderer: NSObject, MTKViewDelegate {

    var vg = vgerNew(0)
    var device: MTLDevice!
    var queue: MTLCommandQueue!
    var renderCallback : ((vgerContext, CGSize) -> Void)?

    static let MaxBuffers = 3
    private let inflightSemaphore = DispatchSemaphore(value: MaxBuffers)

    init(device: MTLDevice) {
        self.device = device
        queue = device.makeCommandQueue()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {

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

        renderCallback?(vg!, size)

        if let renderPassDescriptor = view.currentRenderPassDescriptor, let currentDrawable = view.currentDrawable {
            vgerEncode(vg, commandBuffer, renderPassDescriptor)
            commandBuffer.present(currentDrawable)
        }
        commandBuffer.commit()
    }

    deinit {
        vgerDelete(vg)
    }

}

