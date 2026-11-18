//  SmartMetering.swift — 智能测光's own rule: when a photograph's brightness is set automatically.
//  Foundation only; the act that reads it is the session's (`OpenFrameSession.smartMeter`), the
//  setting's the app's (`AppSettings.smartMetering`).
//
//  The owner, 2026-11-18: "每一次打开一个照片集，我都需要调整亮度" — Film Exposure and the Enlarger's
//  Brightness, by hand, on every photograph. The engine's own meter (`auto_exposure`, four intents —
//  `ExposureMethod`) already solves and applies the exposure inside every develop
//  (`pipeline.cpp`'s `node_auto_exposure`, the solved EV reported as `RunMeasurement.autoExposureEV`);
//  a new frame simply had it off. 智能测光 turns the meter on where a photograph is untouched:
//
//  - **untouched** is the whole gate: Film Exposure at rest (0) **and** the Enlarger's Brightness at
//    rest (0) **and** the meter off. The two brightness controls are one brightness judged twice —
//    the negative, then the print — so a person who set either has set the look, and the act leaves
//    their photograph alone, whatever the setting says. (The Enlarger's Brightness is not itself
//    solved: the engine meters the scene, and the film-and-paper medium is calibrated so film
//    mid-grey prints at paper mid-grey — with the meter on, the print follows. What a person still
//    sets by hand afterwards is taste, and taste is theirs.)
//  - **the intent is the frame's own**: the meter is asked with `autoExposureMethod` as it stands —
//    balanced for a new frame, whatever the person last chose, and **nil stays nil** (a legacy
//    frame's centre-weighted engine default is not the act's to invent). The act flips
//    `autoExposure` and nothing else; the pill (`AEMethod`) remains the way the intent is changed.

import Foundation

enum SmartMetering {
    /// Whether 智能测光 has something to do on this photograph: the meter off, and both brightness
    /// controls at their rest. A photograph the person has touched — either control, or the meter
    /// already on — is theirs.
    static func shouldAuto(autoExposure: Bool, exposureEV: Double, printStops: Double) -> Bool {
        !autoExposure && exposureEV == 0 && printStops == 0
    }
}
