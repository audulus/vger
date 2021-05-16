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
        while shape != nil {

            let c = shape!.pointee.fill.color

            let fcolor = 1.0/255.0 * SIMD4<Float>( Float(c & 0xff), Float( (c>>8) & 0xff),
                                       Float( (c>>16) & 0xff), Float( (c>>24) & 0xff ))

            let paint = vgerColorPaint(fcolor)

            var path = shape?.pointee.paths
            while path != nil {
                path?.pointee.pts.withMemoryRebound(to: SIMD2<Float>.self, capacity: Int(path!.pointee.npts), { cvs in
                    vgerFillCubicPath(vger, cvs, path!.pointee.npts, paint)
                })
                path = path?.pointee.next
            }

            shape = shape?.pointee.next
        }

        vgerRestore(vger)
    }
}

struct TigerView: View {

    var model: TigerModel

    var body: some View {
        GeometryReader { geom in
            VgerView(renderCallback: { vger in model.draw(vger: vger, size: geom.size)})
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
