//  Copyright © 2021 Audulus LLC. All rights reserved.

import SwiftUI
import MetalKit
import vger

#if os(macOS)

public struct VgerTileView: NSViewRepresentable {

    var renderCallback : (OpaquePointer) -> Void

    public init(renderCallback: @escaping (OpaquePointer) -> Void) {
        self.renderCallback = renderCallback
    }

    public class Coordinator {
        var renderer = TileRenderer(device: MTLCreateSystemDefaultDevice()!)
    }

    public func makeCoordinator() -> Coordinator {
        return Coordinator()
    }

    public func makeNSView(context: Context) -> some NSView {
        let metalView = MTKView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768),
                                device: MTLCreateSystemDefaultDevice()!)
        metalView.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
        metalView.delegate = context.coordinator.renderer
        context.coordinator.renderer.renderCallback = renderCallback
        return metalView
    }

    public func updateNSView(_ nsView: NSViewType, context: Context) {
        context.coordinator.renderer.renderCallback = renderCallback
    }
}

#else

public struct VgerTileView: UIViewRepresentable {

    var renderCallback : (OpaquePointer) -> Void

    public init(renderCallback: @escaping (OpaquePointer) -> Void) {
        self.renderCallback = renderCallback
    }

    public class Coordinator {
        var renderer = TileRenderer(device: MTLCreateSystemDefaultDevice()!)
    }

    public func makeCoordinator() -> Coordinator {
        return Coordinator()
    }

    public func makeUIView(context: Context) -> some UIView {
        let metalView = MTKView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768),
                                device: MTLCreateSystemDefaultDevice()!)
        metalView.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
        metalView.delegate = context.coordinator.renderer
        context.coordinator.renderer.renderCallback = renderCallback
        return metalView
    }

    public func updateUIView(_ nsView: UIViewType, context: Context) {
        context.coordinator.renderer.renderCallback = renderCallback
    }
}

#endif

