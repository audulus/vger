
import Foundation
import vger
import SwiftUI

class Vger {
    var cx: vgerContext

    init() {
        cx = vgerNew(0)
    }

    func text(_ str: String, color: Color, alignment: Alignment) {

    }

    deinit {
        vgerDelete(cx)
    }
}
