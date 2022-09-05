//  Copyright © 2021 Audulus LLC. All rights reserved.

import SwiftUI

struct ContentView: View {
    @StateObject var model = TigerModel()
    var body: some View {
        TigerView(model: model)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
