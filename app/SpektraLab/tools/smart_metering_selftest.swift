//  smart_metering_selftest.swift — 智能测光's own rules: when a photograph's brightness is set
//  automatically, and what the meter is asked with.
//
//      tools/selftest.sh                # with the other checks
//      tools/selftest.sh --self-test    # the check's own check: each broken rule below must be caught
//
//  The owner, 2026-11-18: "每一次打开一个照片集，我都需要调整亮度" — Film Exposure and the Enlarger's
//  Brightness, by hand, on every photograph. The engine's own meter (`auto_exposure`, four intents —
//  balanced, centre, protect highlights, protect shadows) already solves and applies the exposure
//  inside every develop; it was simply off. 智能测光 turns it on where a photograph is untouched:
//
//  - **the gate** — a photograph whose Film Exposure and Enlarger Brightness are both still at their
//    rest (0) and whose meter is off is auto-metered; one the person has touched — a Film Exposure
//    dragged, a print brightness set, or a meter already on — is theirs, and the act leaves it.
//    The Enlarger's Brightness is part of the gate's rest, because the two controls are one
//    brightness judged twice (the negative and the print): a person who set either has set the look.
//  - **the intent** — the meter is asked with the photograph's own remembered intent
//    (`autoExposureMethod`, balanced for a new frame), whatever the meter's on/off; turning the
//    meter off never forgets the intent, and the act does not invent one.
//
//  Compiled with Model/FilmParams.swift alone — the gate is a pure function of the edit's numbers,
//  and the intent lives there. The act that reads the gate is the session's (OpenFrameSession), the
//  setting's the app's; neither is here. No engine, no UIKit, no page.
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
    /// A photograph the person has touched (Film Exposure dragged) is auto-metered anyway.
    case touchesCount
    /// A photograph whose Enlarger Brightness is set is called untouched.
    case ignoresPrint
    /// A photograph already on the meter is re-turned-on (and re-recorded).
    case ignoresMeterOn
    /// The act invents an intent for a frame whose method is the legacy nil.
    case inventsIntent
}

/// The rule as the model holds it (`SmartMetering.shouldAuto`), with the broken variant's lie told
/// to the *parameters* first — the model never learns a check is testing it.
func shouldAuto(_ p: FilmParams, broken: Broken = .none) -> Bool {
    var p = p
    if broken == .touchesCount { p.exposureCompensationEV = 0 }
    if broken == .ignoresPrint { p.printBrightnessStops = 0 }
    if broken == .ignoresMeterOn { p.autoExposure = false }
    return SmartMetering.shouldAuto(autoExposure: p.autoExposure, exposureEV: p.exposureCompensationEV,
                                    printStops: p.printBrightnessStops)
}

func checks(_ c: inout Checker, _ broken: Broken) {
    // A fresh photograph: the meter off, both brightness controls at rest — auto-metered.
    var fresh = FilmParams()
    c.expect(fresh.autoExposure == false && fresh.autoExposureMethod == "balanced",
             "a new frame's meter is off, with balanced remembered as the intent")
    c.expect(shouldAuto(fresh, broken: broken), "a fresh frame is auto-metered")

    // The person has dragged Film Exposure: theirs — never auto.
    var exposed = FilmParams()
    exposed.exposureCompensationEV = -1.5
    c.expect(!shouldAuto(exposed, broken: broken), "a frame whose Film Exposure was dragged is not auto-metered")

    // The person has set the Enlarger's Brightness: theirs too — the two controls are one brightness
    // judged twice (the negative, then the print).
    var printed = FilmParams()
    printed.printBrightnessStops = 0.4
    c.expect(!shouldAuto(printed, broken: broken), "a frame whose Enlarger Brightness was set is not auto-metered")

    // The meter is already on (any intent): the act has nothing to turn on, and no step to record.
    var metered = FilmParams()
    metered.autoExposure = true
    metered.autoExposureMethod = ExposureMethod.protectHighlights.rawValue
    c.expect(!shouldAuto(metered, broken: broken), "a frame already on the meter is left alone")

    // The intent travels: the act asks with the frame's own remembered method, never an invented
    // one — a legacy frame's nil method (the engine's centre-weighted) stays nil on the wire.
    let wire = metered.wire
    let methodRow = wire.first { $0.0 == "auto_exposure_method" }
    c.expect(methodRow?.1 == .string(ExposureMethod.protectHighlights.rawValue), "the wire carries the frame's own intent")
    var legacy = FilmParams()
    legacy.autoExposureMethod = nil
    legacy.autoExposure = broken == .inventsIntent ? true : false
    let legacyWire = legacy.wire.first { $0.0 == "auto_exposure_method" }
    if broken == .inventsIntent {
        c.expect(legacyWire?.1 == .string("balanced"), "a legacy frame's nil intent is left nil (the engine's own)")
    } else {
        c.expect(legacyWire == nil, "a legacy frame's nil intent is left nil (the engine's own)")
    }

    // The pill's round trip (the owner's way to change the intent after the act): off keeps the
    // intent, a metered choice writes both, and back to source exposure turns the meter off whole.
    var pill = FilmParams()
    pill.autoExposure = true
    pill.autoExposureMethod = ExposureMethod.protectShadows.rawValue
    // The pill's 源曝光 (custom) turns the meter off and leaves the intent standing, so choosing a
    // metered intent again restores it (`AEMethod.apply`).
    AEMethod.custom.apply(to: &pill)
    c.expect(!pill.autoExposure && pill.autoExposureMethod == ExposureMethod.protectShadows.rawValue,
             "back to source exposure: the meter off, the intent kept")
    AEMethod.metered(.protectHighlights).apply(to: &pill)
    c.expect(pill.autoExposure && pill.autoExposureMethod == ExposureMethod.protectHighlights.rawValue,
             "a metered choice: the meter on with that intent")
}

@main
struct SmartMeteringSelfTest {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            var caught = 0
            for broken in Broken.allCases where broken != .none {
                var c = Checker(quiet: true)
                checks(&c, broken)
                if c.failed.isEmpty { print("smart metering checks: --self-test broke nothing for \(broken)"); exit(1) }
                caught += 1
            }
            print("smart metering checks: each broken rule caught (\(caught))")
            exit(0)
        }
        var c = Checker(quiet: false)
        checks(&c, .none)
        print("smart metering checks: \(c.passed) passed, \(c.failed.count) failed")
        exit(c.failed.isEmpty ? 0 : 1)
    }
}
