import SwiftUI
import vger      // C/C++/ObjC interface.
import vgerSwift // Swift niceties.

struct HelloView: View {

    let cyan = SIMD4<Float>(0,1,1,1)

    var body: some View {
        VgerView(renderCallback: { vger in
            vgerText(vger, "Hello world. This is V'Ger.", cyan, 0)
        })
        .frame(width: 500, height: 500)
    }
}
import PlaygroundSupport
PlaygroundPage.current.needsIndefiniteExecution = true
PlaygroundPage.current.setLiveView(HelloView())
