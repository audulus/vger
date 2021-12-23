//  Copyright © 2021 Audulus LLC. All rights reserved.

import vger

public class TextureHandle {
    var vger: vgerContext
    var textureIndex: vgerImageIndex

    public init(vger: vgerContext, index: vgerImageIndex) {
        self.vger = vger
        self.textureIndex = index
    }

    deinit {
        vgerDeleteTexture(vger, textureIndex)
    }
}
