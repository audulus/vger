//  Copyright © 2017 Halfspace LLC. All rights reserved.

import Metal

/// Renders a texture to the entire screen.
final class TextureRenderer {

    private var pipelineState: MTLRenderPipelineState!
    private var depthState: MTLDepthStencilState!

    init(device: MTLDevice, pixelFormat: MTLPixelFormat) {

        do {

            let lib = try device.makeDefaultLibrary(bundle: Bundle.module)
            let fragmentProgram = lib.makeFunction(name: "textureFragment")!
            let vertexProgram = lib.makeFunction(name: "textureVertex")!

            let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
            pipelineStateDescriptor.vertexFunction = vertexProgram
            pipelineStateDescriptor.fragmentFunction = fragmentProgram
            pipelineStateDescriptor.colorAttachments[0].pixelFormat = pixelFormat

            try pipelineState = device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
        } catch let error {
            print("Failed to create pipeline state, error \(error)")
        }

    }

    func encode(to commandBuffer: MTLCommandBuffer,
                pass: MTLRenderPassDescriptor,
                texture: MTLTexture) {

        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
        renderEncoder?.label = "texture render"
        renderEncoder?.setRenderPipelineState(pipelineState)

        renderEncoder?.pushDebugGroup("texture")

        renderEncoder?.setFragmentTexture(texture, index: 0)
        renderEncoder?.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        renderEncoder?.popDebugGroup()
        renderEncoder?.endEncoding()

    }

}
