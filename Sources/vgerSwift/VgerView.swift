//  Copyright © 2021 Audulus LLC. All rights reserved.

import SwiftUI
import MetalKit
import vger

#if os(macOS)

public struct VgerView: NSViewRepresentable {

    var renderCallback : (vgerContext, CGSize) -> Void

    public init(renderCallback: @escaping (vgerContext, CGSize) -> Void) {
        self.renderCallback = renderCallback
    }

    public class Coordinator {
        var renderer = Renderer(device: MTLCreateSystemDefaultDevice()!)
    }

    public func makeCoordinator() -> Coordinator {
        return Coordinator()
    }

    public func makeNSView(context: Context) -> MTKView {
        let metalView = MTKView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768),
                                device: MTLCreateSystemDefaultDevice()!)
        metalView.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
        metalView.delegate = context.coordinator.renderer
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = true
        context.coordinator.renderer.renderCallback = renderCallback
        return metalView
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.renderer.renderCallback = renderCallback
        nsView.setNeedsDisplay()
    }
}

#else

public struct VgerView: UIViewRepresentable {

    var renderCallback : (vgerContext, CGSize) -> Void

    public init(renderCallback: @escaping (vgerContext, CGSize) -> Void) {
        self.renderCallback = renderCallback
    }

    public class Coordinator {
        var renderer = Renderer(device: MTLCreateSystemDefaultDevice()!)
    }

    public func makeCoordinator() -> Coordinator {
        return Coordinator()
    }

    public func makeUIView(context: Context) -> MTKView {
        let metalView = MTKView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768),
                                device: MTLCreateSystemDefaultDevice()!)
        metalView.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
        metalView.delegate = context.coordinator.renderer
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = true
        context.coordinator.renderer.renderCallback = renderCallback
        return metalView
    }

    public func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.renderer.renderCallback = renderCallback
        uiView.setNeedsDisplay()
    }
}

#endif

struct VgerView_Previews: PreviewProvider {
    static var previews: some View {
        VgerView(renderCallback: { vger, _ in
            vgerText(vger, "hello world", .init(repeating: 1), 0)
        })
    }
}
