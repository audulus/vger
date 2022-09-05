import SwiftUI
import vger
import vgerSwift

struct HelloView: View {
    let cyan = SIMD4<Float>(0,1,1,1)

    var body: some View {
        VgerView { vger in
            vgerText(vger, "Hello world. This is V'Ger.", cyan, 0)
        }
    }
}

struct HelloView_Previews: PreviewProvider {
    static var previews: some View {
        HelloView()
    }
}
