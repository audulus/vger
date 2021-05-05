//  Copyright © 2021 Audulus LLC. All rights reserved.

import SwiftUI

struct ContentView: View {
    var body: some View {
        DemoView().frame(width: 512, height: 512, alignment: .center)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
