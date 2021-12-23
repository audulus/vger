//  Copyright © 2021 Audulus LLC. All rights reserved.

import vger

public class TextureHandle {
    public let vger: vgerContext
    public let textureIndex: vgerImageIndex

    public init(vger: vgerContext, index: vgerImageIndex) {
        self.vger = vger
        self.textureIndex = index
    }

    deinit {
        vgerDeleteTexture(vger, textureIndex)
    }
}
