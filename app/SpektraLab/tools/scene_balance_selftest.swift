//  scene_balance_selftest.swift — 场景自动平衡's own arithmetic: what the measured bands say, and
// what the two layers should hold.
//
//      tools/selftest.sh                # with the other checks
//      tools/selftest.sh --self-test    # the check's own check: each broken rule below must be caught
//
//  The engine measures any rectangle of the scene in stops (`spk_scene_latitude`, RFC-023) and the
//  film and paper's own window beside it; 自动平衡 asks it for six horizontal bands and holds:
//
//  - the split where the light steps — the boundary of the six whose sides differ most in their
//    medians, refused as nothing to balance where the two sides are close (under a stop);
//  - the sky pulled down to sit `margin` stops inside the medium's highlight end and the ground
//    lifted to its shadow end — each as a stop of light on the film, clamped to what a layer's
//    曝光 slider holds (±3 of its ±4, for a first pass nobody has to undo), a side that already
//    sits inside the window left alone, and both inside refused as nothing to pull back;
//  - Film Exposure's axis (`exposureEV`): the scene's stops are before it, the medium's after it,
//    so a stop of it moves what each side needs by exactly a stop.
//
//  Compiled with `Model/SceneBalance.swift` over the same model the latitude card's check sits on.
//  No engine, no UIKit, no page: the bands here are made up, sky-shaped and ground-shaped.
//
//  AGENTS.md: a check that cannot fire is not a check. `--self-test` runs the same checks against
//  the rule broken on purpose, one part at a time, and requires each run to fail.

import Foundation

struct Checker {
    var passed = 0
    var failed: [String] = []
    let quiet: Bool
    mutating func expect(_ ok: Bool, _ what: String) {
        if ok { passed += 1 } else { failed.append(what); if !quiet { print("  FAIL  \(what)") } }
    }
}

/// One part of the rule broken at a time: the check that should catch it.
enum Broken: CaseIterable {
    case none
    /// No least gap asked: any difference in the bands splits.
    case noGap
    /// The margin forgotten: the sky is pulled to the medium's very end, not inside it.
    case noMargin
    /// The clamp gone: a hard sky asks for more than the slider's tasteful first pass.
    case noClamp
    /// Film Exposure's axis ignored.
    case noExposureAxis
    /// The shaping threshold gone: any subject texel above the split reshapes the sky.
    case noShape
}

func solve(_ bands: [SceneBalance.Band], shadowEV: Double, highlightEV: Double, exposureEV: Double, broken: Broken = .none) -> SceneBalance.Solved {
    var margin = SceneBalance.margin, gap = SceneBalance.gap, clamp = SceneBalance.clamp
    var exposure = exposureEV
    if broken == .noMargin { margin = 0 }
    if broken == .noGap { gap = 0 }
    if broken == .noClamp { clamp = 4 }
    if broken == .noExposureAxis { exposure = 0 }
    return SceneBalance.solve(bands: bands, medium: .init(shadowEV: shadowEV, highlightEV: highlightEV),
                              exposureEV: exposure, margin: margin, gap: gap, clamp: clamp)
}

func shapesSky(_ subjectAbove: Double, broken: Broken) -> Bool {
    SceneBalance.shapesSky(subjectAbove: subjectAbove, threshold: broken == .noShape ? 0 : SceneBalance.skyShape)
}

func checks(_ c: inout Checker, _ broken: Broken) {
    // A sky-shaped top over a ground-shaped bottom: six bands, the light stepping between the
    // third and the fourth (the boundary 3/6 = half way down).
    let sky = [SceneBalance.Band(1.2, 4.6, 5.8), SceneBalance.Band(1.0, 4.4, 5.6), SceneBalance.Band(0.2, 3.8, 5.0),
               SceneBalance.Band(-4.8, -1.6, 1.4), SceneBalance.Band(-5.4, -2.2, 0.8), SceneBalance.Band(-5.8, -2.6, 0.4)]
    let medium = (shadowEV: -5.2, highlightEV: 4.4)

    let balanced = solve(sky, shadowEV: medium.shadowEV, highlightEV: medium.highlightEV, exposureEV: 0, broken: broken)
    guard case .balanced(let a) = balanced else {
        c.expect(false, "a sky over a ground is balanced, not refused")
        return
    }
    c.expect(abs(a.split - 0.5) < 1e-9, "the split is where the light steps, half way down (\(a.split))")
    // The sky's mean p99 (5.466…) pulled to the medium's 4.4 less the margin: −1.37 stops.
    c.expect(abs(a.skyEV - ((4.4 - SceneBalance.margin) - (5.8 + 5.6 + 5.0) / 3)) < 1e-9,
             "the sky is pulled to sit inside the medium's highlight end (\(a.skyEV))")
    // The ground's mean p1 (−5.333…) lifted to the medium's −5.2 plus the margin: +0.43 stops.
    c.expect(abs(a.groundEV - ((-5.2 + SceneBalance.margin) - (-4.8 - 5.4 - 5.8) / 3)) < 1e-9,
             "the ground is lifted to sit inside the medium's shadow end (\(a.groundEV))")
    c.expect(a.skyEV < 0 && a.groundEV > 0, "the sky comes down and the ground goes up")

    // Film Exposure's axis: a stop of it is a stop more either side needs — the light is a stop
    // brighter on the film, so the sky's pull grows by the whole stop (RFC-035 §5.3); the ground's
    // need grows by a stop too, held at 0 where it then needs none — a side inside the window is
    // left alone, not pushed the other way.
    let shifted = solve(sky, shadowEV: medium.shadowEV, highlightEV: medium.highlightEV, exposureEV: 1, broken: broken)
    if case .balanced(let b) = shifted {
        c.expect(abs(b.skyEV - (a.skyEV - 1)) < 1e-9,
                 "a stop of Film Exposure grows the sky's pull by exactly a stop (\(b.skyEV))")
        c.expect(abs(b.groundEV - max(0, a.groundEV - 1)) < 1e-9,
                 "and the ground's need by as much, held at 0 where it needs none (\(b.groundEV))")
    } else { c.expect(false, "a stop of Film Exposure does not refuse the balance") }

    // A flat photograph: the two sides are close in light, and there is nothing to balance — even
    // where its extremes sit outside the window (a contrasty evenness), for then the whole-frame
    // Scene Placement is the act that fits it, not a split the light does not step at.
    let flat = [SceneBalance.Band(-9.1, 0.2, 9.0), SceneBalance.Band(-9.2, 0.1, 8.8), SceneBalance.Band(-9.0, 0.0, 9.1),
                SceneBalance.Band(-9.1, 0.1, 8.9), SceneBalance.Band(-9.2, 0.2, 9.0), SceneBalance.Band(-9.0, 0.1, 8.8)]
    let refused = solve(flat, shadowEV: medium.shadowEV, highlightEV: medium.highlightEV, exposureEV: 0, broken: broken)
    if case .refused = refused {
        c.expect(true, "a flat photograph is refused")
    } else if case .balanced(let f) = refused {
        c.expect(false, "a flat photograph is refused, not balanced at \(f.split)")
    }

    // A hard sky asks for more than the slider's tasteful first pass and is held at the clamp.
    let hard = [SceneBalance.Band(2.0, 8.0, 10.5), SceneBalance.Band(1.8, 7.6, 10.0), SceneBalance.Band(0.6, 6.4, 9.0),
                SceneBalance.Band(-4.8, -1.6, 1.4), SceneBalance.Band(-5.4, -2.2, 0.8), SceneBalance.Band(-5.8, -2.6, 0.4)]
    if case .balanced(let h) = solve(hard, shadowEV: medium.shadowEV, highlightEV: medium.highlightEV, exposureEV: 0, broken: broken) {
        c.expect(h.skyEV >= -SceneBalance.clamp - 1e-9, "the sky's pull is held at the clamp (\(h.skyEV))")
    } else { c.expect(false, "a hard sky is balanced, not refused") }

    // Both sides already inside the window: nothing to pull back, said so.
    let inside = [SceneBalance.Band(0.0, 2.0, 3.4), SceneBalance.Band(-0.1, 1.9, 3.3), SceneBalance.Band(-0.2, 1.8, 3.2),
                  SceneBalance.Band(-3.8, -1.4, 0.6), SceneBalance.Band(-3.9, -1.5, 0.5), SceneBalance.Band(-4.0, -1.6, 0.4)]
    let nothing = solve(inside, shadowEV: -5.2, highlightEV: 4.4, exposureEV: 0, broken: broken)
    if case .refused = nothing {
        c.expect(true, "both sides inside the window are refused as nothing to pull back")
    } else if case .balanced(let n) = nothing {
        c.expect(false, "both sides inside the window make no layers (sky \(n.skyEV), ground \(n.groundEV))")
    }

    // 识别塑形 (v2): a subject that reaches into the sky reshapes the sky's gradient as 背景 ∩ —
    // a head against a bright sky is not dimmed with the sky it stands against. A share of the
    // bands above the split at the threshold or above shapes; under it (a stray detection, not a
    // subject) the plain gradient is the better mask, and none of one is none at all.
    c.expect(shapesSky(0.05, broken: broken), "a subject 5 % of the sky's bands shapes the sky's mask")
    c.expect(shapesSky(SceneBalance.skyShape, broken: broken), "the threshold itself shapes (>=, not >)")
    c.expect(!shapesSky(SceneBalance.skyShape - 0.001, broken: broken), "just under the threshold does not")
    c.expect(!shapesSky(0, broken: broken), "no subject above the split does not")
}

@main
struct SceneBalanceSelfTest {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            var caught = 0
            for broken in Broken.allCases where broken != .none {
                var c = Checker(quiet: true)
                checks(&c, broken)
                if c.failed.isEmpty { print("scene balance checks: --self-test broke nothing for \(broken)"); exit(1) }
                caught += 1
            }
            print("scene balance checks: each broken rule caught (\(caught))")
            exit(0)
        }
        var c = Checker(quiet: false)
        checks(&c, .none)
        print("scene balance checks: \(c.passed) passed, \(c.failed.count) failed")
        exit(c.failed.isEmpty ? 0 : 1)
    }
}
