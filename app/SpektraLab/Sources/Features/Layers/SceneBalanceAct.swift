//  SceneBalanceAct.swift — 场景自动平衡 in the running app: the act behind the menus' word.
//
//  The develop page's ⋯ menu, on the Mac and on the host (`MacDevelopActions`, `DevelopWorkspace.moreMenu`),
//  offers 自动平衡天空与地面 for the photograph open in front. What it does, in one press and one step
//  of Undo:
//
//  - **it measures** — six horizontal bands of the scene through the engine's own measure
//    (`spk_scene_latitude`, asked on the canvas's open session, so it never runs beside a render),
//    each band's percentiles and the film and paper's own window beside them;
//  - **it decides** — `SceneBalance.solve`, the same arithmetic `tools/scene_balance_selftest.swift`
//    holds: the split where the light steps, each side pulled to sit inside the film's window as a
//    stop of light on the film, the flat and the already-inside refused with their lines;
//  - **it lands** — two 场景 mask layers, 天空 n and 地面 n, two linear gradients meeting at the split
//    with a soft seam, each holding its side's stop of 曝光 (`SceneDeltas`) — the film develops again
//    through the corrected light, and every number stays a person's to tune: the layers are the
//    panel's own, and Undo takes both back as one act.
//
//  Not here: the finding of 主体 and 背景 (`MaskFinding`) — the gradients come from the measurement
//    and cover every photograph, and a found part joins a layer by hand (组合蒙版) where the ground
//    is a subject and not a half.
//
//  Mac and host: the asking is the engine's, the landing the session's — nothing of the window's.

import Foundation

@MainActor
enum SceneBalanceAct {
    /// How many bands the act measures. Six is a split to the sixth of the photograph and a reply
    /// each (0.2 ms a call once the medium and the scene are cached; a first call probes the film
    /// and paper's ramp, 48 ms on the Mac).
    static let bands = 6

    /// The act, from either menu. Says what it did at the panel's foot (`session.maskNote`).
    static func run(session: OpenFrameSession, model: AppServices) async {
        var bands: [SceneBalance.Band] = []
        var medium: SceneBalance.Medium?
        var exposureEV = 0.0
        for i in 0..<Self.bands {
            var request = SceneLatitudeRequest()
            request.region = [0, Double(i) / Double(Self.bands), 1, Double(i + 1) / Double(Self.bands)]
            guard case .success(let reply) = await model.darkroom.sceneLatitude(session.frameID, request: request) else {
                session.maskNote = L("Auto Balance needs the photograph developed first.")
                return
            }
            let s = reply.scene
            bands.append(SceneBalance.Band(s.p1, s.p50, s.p99))
            medium = SceneBalance.Medium(shadowEV: reply.medium.shadowEV, highlightEV: reply.medium.highlightEV)
            exposureEV = s.histogram.exposureEV ?? 0
            #if DEBUG
            NSLog("[balance] band %d p1 %.3f p50 %.3f p99 %.3f samples %.0f exposureEV %.3f medium %.3f…%.3f",
                  i, s.p1, s.p50, s.p99, s.samples, s.histogram.exposureEV ?? 0, reply.medium.shadowEV, reply.medium.highlightEV)
            #endif
        }
        guard let medium else { return }
        switch SceneBalance.solve(bands: bands, medium: medium, exposureEV: exposureEV) {
        case .refused(let line):
            session.maskNote = line
        case .balanced(let answer):
            // Only the side that moves makes a layer: a side already inside the film's window
            // needs none, and an empty layer beside the working one is clutter, not a start.
            var layers: [LocalLayer] = []
            if answer.skyEV < 0 {
                var sky = LocalLayer(name: Self.freeName(L("Sky"), among: session.edit.layers), stage: .scene,
                                     parts: [.linear(MaskLinear(a: MaskPoint(0, 0), b: MaskPoint(0, answer.split)))]
                                         + (await Self.skyShapeParts(answer: answer, session: session)))
                sky.scene?.exposure = answer.skyEV
                // A soft seam where the gradients meet: the split is a sixth of the picture wide
                // at most, and a hard one would draw a line the eye then cannot unsee.
                sky.feather = 0.04
                layers.append(sky)
            }
            if answer.groundEV > 0 {
                var ground = LocalLayer(name: Self.freeName(L("Ground"), among: session.edit.layers), stage: .scene,
                                        parts: [.linear(MaskLinear(a: MaskPoint(0, 1), b: MaskPoint(0, answer.split)))])
                ground.scene?.exposure = answer.groundEV
                ground.feather = 0.04
                layers.append(ground)
            }
            guard session.makeLayers(layers, label: HistoryLabel("Auto Balance")) else { return }
            session.maskNote = L("Balanced: the sky \(Fmt.signed(answer.skyEV)) stops, the ground \(Fmt.signed(answer.groundEV)) stops, as layers to tune.")
        }
    }

    /// 识别塑形 (v2): the parts that take the found subject out of the sky's pull — the gradient
    /// ∩ 背景, where the found subject reaches into the bands above the split (a head against a
    /// bright sky is not dimmed with the sky it stands against). None where it does not (the
    /// finder's word is not asked for its own sake: a stray detection under `SceneBalance.skyShape`
    /// buys an intersect that changes nothing, and a finder that is away or finds nothing leaves
    /// the gradient alone — the measurement's mask is still a mask).
    ///
    /// The share is the found subject's coverage of the rows above the split, the finder's own
    /// in-subject reading of a texel (`box`'s ≥ 128 of 255) over its rendition's own pixels, at
    /// most 2048 of the long edge: some milliseconds of arithmetic, beside the find's own
    /// 0.1–0.5 s warm.
    private static func skyShapeParts(answer: SceneBalance.Answer, session: OpenFrameSession) async -> [MaskPart] {
        guard let source = session.findSource else { return [] }
        let finder = MaskFinding.shared.finder
        let found: FoundResult?
        do { found = try await finder.subject(source) } catch { return [] }
        guard let found else { return [] }
        let picture = found.picture
        let rows = min(max(Int((answer.split * Double(picture.height)).rounded()), 1), picture.height)
        var on = 0
        for y in 0..<rows {
            let row = y * picture.width
            for x in 0..<picture.width where picture.bytes[row + x] >= 128 { on += 1 }
        }
        let share = Double(on) / Double(rows * picture.width)
        #if DEBUG
        NSLog("[balance] the subject covers %.1f%% of the bands above the split", share * 100)
        #endif
        guard SceneBalance.shapesSky(subjectAbove: share) else { return [] }
        let part: MaskPart
        do { part = try await finder.part(found, background: true, join: .intersect) } catch { return [] }
        return [part]
    }

    /// 天空 n with the smallest number no layer is called by (`MaskRules.name`'s rule, for a word of
    /// the act's own).
    private static func freeName(_ word: String, among layers: LocalLayers?) -> String {
        let taken = Set((layers?.items ?? []).map(\.name))
        var n = 1
        while taken.contains("\(word) \(n)") { n += 1 }
        return "\(word) \(n)"
    }
}
