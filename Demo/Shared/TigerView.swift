//  Copyright © 2021 Audulus LLC. All rights reserved.

import SwiftUI
import vger
import vgerSwift

class TigerModel : ObservableObject {

    var image: UnsafeMutablePointer<NSVGimage>
    var scale = CGFloat(1.0)

    init() {
        let path = Bundle.main.path(forResource: "Ghostscript_Tiger", ofType: "svg")
        image = nsvgParseFromFile(path, "px", 96)!
    }

    func draw(vger: vgerContext, size: CGSize) {
        vgerSave(vger)

        vgerTranslate(vger, .init(0, Float(size.height)))
        vgerScale(vger, .init(0.5, -0.5))
        vgerScale(vger, .init(repeating: Float(scale)))

        var shape = image.pointee.shapes
        while let s = shape {

            let c = s.pointee.fill.color

            let fcolor = 1.0/255.0 * SIMD4<Float>( Float(c & 0xff), Float( (c>>8) & 0xff),
                                       Float( (c>>16) & 0xff), Float( (c>>24) & 0xff ))

            let paint = vgerColorPaint(vger, fcolor)

            var path = s.pointee.paths
            while let p = path {
                let n = Int(p.pointee.npts)
                p.pointee.pts.withMemoryRebound(to: SIMD2<Float>.self, capacity:n) { cvs in
                    vgerMoveTo(vger, cvs[0])
                    var i = 1
                    while i < n-2 {
                        vgerCubicApproxTo(vger, cvs[i], cvs[i+1], cvs[i+2])
                        i += 3
                    }
                }
                path = p.pointee.next
            }
            vgerFill(vger, paint)

            shape = s.pointee.next
        }

        vgerRestore(vger)
    }
}

struct TigerView: View {

    var model: TigerModel

    var body: some View {
        GeometryReader { geom in
            VgerView { vger in
                model.draw(vger: vger, size: geom.size)
            }
            .gesture(MagnificationGesture().onChanged({ scale in
                model.scale = scale
            }))
        }

    }
}

struct TigerView_Previews: PreviewProvider {
    static var previews: some View {
        TigerView(model: TigerModel())
    }
}
