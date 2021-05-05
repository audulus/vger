//  Copyright © 2021 Audulus LLC. All rights reserved.

import Foundation
import MetalKit

/// Shim contentScaleFactor into MTKView on macOS.
extension MTKView {
    
    var contentScaleFactor: CGFloat {
        get {
            return layer!.contentsScale
        }
        set {
            if let metalLayer = layer as? CAMetalLayer {
                metalLayer.contentsScale = newValue
                drawableSize =
                    CGSize(width: metalLayer.bounds.size.width * newValue,
                           height: metalLayer.bounds.size.height * newValue)
            }
        }
    }
    
    func setNeedsDisplay() {
        super.setNeedsDisplay(self.frame)
    }
    
}
