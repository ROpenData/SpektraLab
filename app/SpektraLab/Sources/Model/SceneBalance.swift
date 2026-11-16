//  SceneBalance.swift — 场景自动平衡's own arithmetic: what the engine's measured bands of a scene
//  say, and what the two layers the act makes should hold. Foundation only, beside nothing that
//  draws — the asking (`SceneBalanceAct`, Features/Layers) and the layers (`LocalLayers`) are
//  another file's.
//
//  A sky too bright over a ground too dark is the oldest photograph there is; the darkroom's answer
//  was a graduated filter or a contrast mask, and the vendors' is a mask drawn by hand or by
//  segmentation with an exposure moved on the display. This one measures: the engine already
//  measures any rectangle of the scene in stops and the film and paper's own window beside it
//  (`spk_scene_latitude`, RFC-023), so the act asks it for six horizontal bands and this file asks
//  them:
//
//  - **the split** — the boundary of the bands whose two sides differ most in their medians. The
//    light steps there (the sky's floor, the ground's ceiling), and the two gradients the act makes
//    meet there. Where the two sides are close in light — under `gap` stops — there is nothing to
//    balance and the act says so rather than making two layers that move nothing.
//  - **the sky pulled, the ground lifted** — each side's robust extreme (the sky's p99, the
//    ground's p1) landed `margin` stops *inside* the medium's own end, as a stop of light on the
//    film: the layers this file's answer becomes are 场景 layers, whose 曝光 multiplies the light
//    before the film (`SceneDeltas`), so the film develops again through the corrected light, its
//    grain and halation and the paper's own range intact. A side already inside the window is left
//    alone; both inside is nothing to pull back and said so.
//  - **clamped to a first pass nobody has to undo** — the slider holds ±4; the act asks for at most
//    `clamp` (3), the measured whole of it: what moves past that is a photograph the meter never
//    had, and a person's hand on the layer's number does more for it than a bigger guess.
//
//  The axis: the scene's stops are before Film Exposure and the medium's after it (RFC-035 §5.3),
//  so `exposureEV` — the reply's own — is added to a side's extreme before the window is asked
//    about it. Scene Placement's curve between them is not followed to its ends; at the extremes
//  this measures, its departure from a stop-for-stop shift is the smaller term, and the layers it
//  lands are a person's to tune from there.

import Foundation

enum SceneBalance {
    /// One measured band: its percentiles in stops, on the scene's axis (before Film Exposure).
    /// The top of the photograph is the first band.
    struct Band: Equatable, Sendable {
        var p1: Double
        var p50: Double
        var p99: Double
        init(_ p1: Double, _ p50: Double, _ p99: Double) { self.p1 = p1; self.p50 = p50; self.p99 = p99 }
    }

    /// The film and paper's own window, as the engine's medium measures it (`SceneLatitudeReply.Medium`).
    struct Medium: Equatable, Sendable {
        var shadowEV: Double
        var highlightEV: Double
        init(shadowEV: Double, highlightEV: Double) { self.shadowEV = shadowEV; self.highlightEV = highlightEV }
    }

    /// What the act does: the two gradients' meeting place in S (0 the top edge, 1 the bottom), and
    /// the stop of light each side's layer holds (the sky's is 0 or below, the ground's 0 or above).
    struct Answer: Equatable, Sendable {
        var split: Double
        var skyEV: Double
        var groundEV: Double
    }

    enum Solved: Equatable, Sendable {
        case balanced(Answer)
        /// Why not, as a line the page says at the panel's foot.
        case refused(String)
    }

    /// The stops a side's extreme is landed inside the medium's end: enough of the window's end to
    /// hold the sky's own texture, not so much that a sunset becomes an overcast noon.
    static let margin = 0.3
    /// The least difference in the two sides' medians that is a photograph to balance and not a
    /// photograph already even.
    static let gap = 1.0
    /// The most the act asks of a side (the slider's own limit is 4): the measured whole, held to a
    /// first pass nobody has to undo.
    static let clamp = 3.0
    /// 识别塑形's least subject (v2): the share of the bands above the split the found subject must
    /// cover before the sky's gradient is reshaped as 背景 ∩. A head and shoulders against the sky
    /// is a few per cent of the sky's own area; a stray detection is less, and an intersect that
    /// changes almost nothing is a part on the page for nothing.
    static let skyShape = 0.02

    /// Whether the sky's mask is the gradient alone or the gradient ∩ 背景: the found subject,
    /// reaching into the bands above the split, is taken out of the sky's pull — a head against a
    /// bright sky is not dimmed with the sky it stands against. `subjectAbove` is the share of the
    /// bands above the split the subject's found mask covers.
    static func shapesSky(subjectAbove: Double, threshold: Double = skyShape) -> Bool {
        subjectAbove >= threshold
    }

    /// The bands' answer. `bands` are the scene top to bottom; fewer than two is nothing to split.
    static func solve(bands: [Band], medium: Medium, exposureEV: Double,
                      margin: Double = margin, gap: Double = gap, clamp: Double = clamp) -> Solved {
        guard bands.count >= 2 else { return .refused(L("The photograph has not been measured yet.")) }
        // The split: the boundary whose sides differ most in their medians. Ties go to the upper
        // boundary (the sky is the smaller share of a photograph more often than the larger).
        var best = 1, bestGap = -Double.infinity
        for k in 1..<bands.count {
            let above = bands[..<k], below = bands[k...]
            let difference = above.reduce(0.0) { $0 + $1.p50 } / Double(above.count)
                - below.reduce(0.0) { $0 + $1.p50 } / Double(below.count)
            if difference > bestGap { bestGap = difference; best = k }
        }
        guard bestGap >= gap else {
            return .refused(L("The top and the bottom of this photograph are close in light; there is nothing to balance."))
        }
        let above = bands[..<best], below = bands[best...]
        func mean(_ side: ArraySlice<Band>, _ field: KeyPath<Band, Double>) -> Double {
            side.reduce(0.0) { $0 + $1[keyPath: field] } / Double(side.count)
        }
        // Film Exposure's axis added before the window is asked (RFC-035 §5.3), each side clamped
        // to its own direction: the sky comes down and the ground goes up, never the other way.
        let skyEV = ((medium.highlightEV - margin) - (mean(above, \.p99) + exposureEV)).clamped(to: -clamp...0)
        let groundEV = ((medium.shadowEV + margin) - (mean(below, \.p1) + exposureEV)).clamped(to: 0...clamp)
        guard skyEV < 0 || groundEV > 0 else {
            return .refused(L("Both sides already sit inside the film’s window; there is nothing to pull back."))
        }
        return .balanced(Answer(split: Double(best) / Double(bands.count), skyEV: skyEV, groundEV: groundEV))
    }
}
