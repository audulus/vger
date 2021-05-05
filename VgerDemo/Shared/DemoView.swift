//  Copyright © 2021 Audulus LLC. All rights reserved.

import SwiftUI
import vger

struct DemoView: View {

    let cyan = SIMD4<Float>(0,1,1,1)
    let magenta = SIMD4<Float>(1,0,1,1)

    func textAt(_ vger: OpaquePointer, _ x: Float, _ y: Float, _ string: String) {
        vgerSave(vger)
        vgerTranslate(vger, .init(x: x, y: y))
        vgerRenderText(vger, string, cyan, 0)
        vgerRestore(vger)
    }

    func draw(vger: OpaquePointer) {
        vgerSave(vger)

        var bez = vgerPrim()
        bez.type = vgerBezier
        bez.width = 1.0
        bez.cvs.0 = .init(x: 50, y: 450)
        bez.cvs.1 = .init(x: 100, y: 450)
        bez.cvs.2 = .init(x: 100, y: 500)
        bez.paint = vgerLinearGradient(.init(x: 50, y: 450), .init(x: 100, y: 450), cyan, magenta)

        vgerRender(vger, &bez)

        textAt(vger, 150, 450, "Quadratic Bezier stroke")

        var rect = vgerPrim()
        rect.type = vgerRect
        rect.width = 0.0
        rect.radius = 10
        rect.cvs.0 = .init(x: 50, y: 350)
        rect.cvs.1 = .init(x: 100, y: 400)
        rect.paint = vgerLinearGradient(.init(x: 50, y: 350), .init(x: 100, y: 400), cyan, magenta)

        vgerRender(vger, &rect);
        textAt(vger, 150, 350, "Rounded rectangle")

        var circle = vgerPrim()
        circle.type = vgerCircle
        circle.width = 0.0
        circle.radius = 25
        circle.cvs.0 = .init(x: 75, y: 275)
        circle.paint = vgerLinearGradient(.init(x: 50, y: 250), .init(x: 100, y: 300), cyan, magenta)

        vgerRender(vger, &circle)
        textAt(vger, 150, 250, "Circle")

        /*

        vgerPrim line = {
            .type = vgerSegment,
            .width = 2.0,
            .cvs = {{50, 150}, {100,200}},
            .paint = vgerLinearGradient(float2{50,150}, float2{100,200}, cyan, magenta)
        };
        vgerRender(vger, &line);
        textAt(vger, 150, 150, "Line segment");

        float theta = 0;      // orientation
        float ap = .5 * M_PI; // aperture size
        vgerPrim arc = {
            .type = vgerArc,
            .width = 1.0,
            .cvs = {{75, 75}, {sin(theta), cos(theta)}, {sin(ap), cos(ap)}},
            .radius=25,
            .paint = vgerLinearGradient(float2{50,50}, float2{100,100}, cyan, magenta)
        };
        vgerRender(vger, &arc);
        textAt(vger, 150, 050, "Arc");
        */

        vgerRestore(vger);
    }

    var body: some View {
        VgerView(renderCallback: draw)
    }
}

struct DemoView_Previews: PreviewProvider {
    static var previews: some View {
        DemoView()
    }
}
