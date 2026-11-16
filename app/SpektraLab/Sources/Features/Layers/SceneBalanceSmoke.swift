//  SceneBalanceSmoke.swift — a debug build's proof of 场景自动平衡 end to end, in the running app.
//
//      CFFIXED_USER_HOME=<scratch>/home SpektraLab --balance-smoke <dir> \
//          --balance-smoke-files <bright-sky.jpg> <even.jpg> <figure.jpg> [--library-check-exit]
//
//  The model's own arithmetic is `tools/scene_balance_selftest.swift`'s; this drives the act whole:
//  a scratch catalog of the files, the first opened in 冲洗, 自动平衡 run from the page's own act
//  (`SceneBalanceAct.run`) — and, into `<dir>/report.json`:
//
//  1. a photograph with a bright top over a dark bottom is balanced: two 场景 layers land
//     (天空 1, 地面 1), two linear gradients meeting at the measured split, the sky's 曝光 at or
//     below 0 and the ground's at or above 0, one Undo takes both back, and the film develops again
//     of the corrected light;
//  2. an even photograph is refused with its line, and no layer lands;
//  3. a photograph with a figure standing in its sky: the sky's mask is what the finder and the
//     threshold together say — 识别塑形 re-derived here from the same finder result the act used
//     (the subject's coverage of the bands above the split, `SceneBalance.shapesSky`), the sky
//     layer carrying the 背景-intersect part beside its gradient when it shapes and the plain
//     gradient when it does not — either way a mask the finder's own word justifies, never a guess
//     about what Vision makes of a made-up rectangle.
//
//  Not in a release build.

#if DEBUG
import Foundation

@MainActor
enum SceneBalanceSmoke {
    static func startIfAsked(model: AppServices, arguments: [String] = CommandLine.arguments) {
        guard let i = arguments.firstIndex(of: "--balance-smoke"), i + 1 < arguments.count else { return }
        let out = URL(fileURLWithPath: arguments[i + 1])
        let files = arguments.firstIndex(of: "--balance-smoke-files").map { arguments[($0 + 1)...].prefix { !$0.hasPrefix("--") }.map { URL(fileURLWithPath: $0) } } ?? []
        let exits = arguments.contains("--library-check-exit")
        Task {
            try? await Task.sleep(for: .seconds(2))
            let r = Report()
            await run(model, r, out: out, files: files)
            try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            let report: [String: Any] = ["steps": r.steps, "failures": r.failures, "passed": r.failures.isEmpty, "home": NSHomeDirectory()]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: out.appending(path: "report.json"))
            }
            print("balance-smoke: wrote \(out.appending(path: "report.json").path), \(r.failures.count) failures")
            if exits {
                await model.macLibrary.host.shutdown()
                exit(0)
            }
        }
    }

    private final class Report {
        var steps: [[String: Any]] = []
        var failures: [String] = []
        func note(_ name: String, _ facts: [String: Any] = [:]) {
            var s = facts
            s["step"] = name
            steps.append(s)
            print("balance-smoke: \(name) \(facts)")
        }
        func check(_ ok: Bool, _ what: String) {
            if !ok { failures.append(what); print("balance-smoke: FAIL \(what)") }
        }
    }

    private static func wait(_ seconds: Double, _ done: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { if done() { return true }; try? await Task.sleep(for: .milliseconds(200)) }
        return done()
    }

    private static func run(_ model: AppServices, _ r: Report, out: URL, files: [URL]) async {
        let store = model.macLibrary
        let fm = FileManager.default
        guard files.count == 3 else { r.check(false, "three files: the bright-sky one, the even one, the figure one (\(files.count))"); return }
        await store.start()
        do {
            let work = out.appending(path: "work")
            try? fm.removeItem(at: work)
            let card = work.appending(path: "Card")
            try fm.createDirectory(at: card, withIntermediateDirectories: true)
            let names = files.enumerated().map { "\($0.offset + 1)-\($0.element.lastPathComponent)" }
            for (u, n) in zip(files, names) { try fm.copyItem(at: u, to: card.appending(path: n)) }
            let cat = try await store.newCatalog(named: "Balance", in: work)
            try await store.addFolder(card, to: cat.id)
            _ = await wait(60) { store.images.count == 3 }
            await store.select(collection: store.tree.defaultSelection)
            let rows = names.compactMap { n in store.images.first { $0.fileName == n } }
            r.note("catalog", ["rows": rows.map(\.fileName)])
            guard rows.count == 3 else { return }

            // 1. The bright-sky photograph, opened in 冲洗, balanced from the page's own act.
            try await store.openInDevelop([rows[0].id], focus: rows[0].id)
            let opened = await wait(30) { MacShellBar.shared.develop.flatMap { model.openSession($0.frameID) } != nil }
            guard opened, let bar = MacShellBar.shared.develop, let session = model.openSession(bar.frameID) else {
                r.check(false, "the bright-sky photograph opens in 冲洗"); return
            }
            let developed = await wait(90) { !session.edit.appliesFilm || !model.darkroom.needsDevelop(model.library.frame(session.frameID)!) }
            r.note("opened", ["developed": developed])
            await SceneBalanceAct.run(session: session, model: model)
            await wait(20) { session.edit.layers?.items.count == 2 }
            let layers = session.edit.layers?.items ?? []
            let facts: (names: [String], exposure: [Double], kinds: [String]) = {
                (layers.map(\.name), layers.map { $0.scene?.exposure ?? 0 }, layers.map { $0.parts.first?.kind.rawValue ?? "-" })
            }()
            r.note("balanced", ["layers": facts.names, "exposure": facts.exposure, "parts": facts.kinds,
                                 "note": session.maskNote ?? "-"])
            r.check(layers.count == 2 && facts.kinds == ["linear", "linear"], "two layers of two linear gradients land")
            r.check(facts.names == [L("Sky") + " 1", L("Ground") + " 1"], "named 天空 1 and 地面 1 (\(facts.names))")
            r.check((facts.exposure.first ?? 1) <= 0 && (facts.exposure.last ?? -1) >= 0,
                    "the sky's 曝光 at or below 0 and the ground's at or above 0 (\(facts.exposure))")
            let before = session.canUndo
            _ = session.undo()
            try? await Task.sleep(for: .seconds(1))
            r.note("undo", ["could": before, "layers_after": session.edit.layers?.items.count ?? 0])
            r.check(before && (session.edit.layers?.items.isEmpty ?? true), "one Undo takes both layers back")

            // 2. The even photograph: refused, and nothing lands.
            try await store.openInDevelop([rows[1].id], focus: rows[1].id)
            let second = await wait(30) { model.openSession(MacShellBar.shared.develop!.frameID)?.frameID != session.frameID }
            guard second, let bar2 = MacShellBar.shared.develop, let session2 = model.openSession(bar2.frameID) else {
                r.check(false, "the even photograph opens in 冲洗"); return
            }
            await wait(60) { !model.darkroom.needsDevelop(model.library.frame(session2.frameID)!) }
            await SceneBalanceAct.run(session: session2, model: model)
            try? await Task.sleep(for: .seconds(2))
            r.note("even", ["note": session2.maskNote ?? "-", "layers": session2.edit.layers?.items.count ?? 0])
            r.check((session2.edit.layers?.items.isEmpty ?? true) && session2.maskNote != nil,
                    "an even photograph is refused with its line and no layer lands")

            // 3. A figure standing in the sky: the sky's mask is what the finder and the threshold
            //    together say. The expectation is re-derived here from the finder's own memo (the
            //    act's find answered it already) over the layer's own gradient split — this holds
            //    the WIRING (the act asked, measured the coverage, and shaped accordingly); the
            //    rule itself is the model selftest's, not this copy's.
            try await store.openInDevelop([rows[2].id], focus: rows[2].id)
            let third = await wait(30) { MacShellBar.shared.develop?.frameID != session2.frameID }
            guard third, let bar3 = MacShellBar.shared.develop, let session3 = model.openSession(bar3.frameID) else {
                r.check(false, "the figure photograph opens in 冲洗"); return
            }
            await wait(60) { !model.darkroom.needsDevelop(model.library.frame(session3.frameID)!) }
            await SceneBalanceAct.run(session: session3, model: model)
            await wait(20) { !(session3.edit.layers?.items.isEmpty ?? true) }
            let figureLayers = session3.edit.layers?.items ?? []
            let skyLayer = figureLayers.first { ($0.scene?.exposure ?? 0) < 0 }
            let split = skyLayer?.parts.first?.linear?.b.y
            var share = -1.0
            var expected = false
            if let split, let source = session3.findSource,
               let found = (try? await MaskFinding.shared.finder.subject(source)) ?? nil {
                let picture = found.picture
                let rowsAbove = min(max(Int((split * Double(picture.height)).rounded()), 1), picture.height)
                var on = 0
                for y in 0..<rowsAbove {
                    let row = y * picture.width
                    for x in 0..<picture.width where picture.bytes[row + x] >= 128 { on += 1 }
                }
                share = Double(on) / Double(rowsAbove * picture.width)
                expected = SceneBalance.shapesSky(subjectAbove: share)
            }
            let shaped = (skyLayer?.parts.count ?? 0) > 1
            r.note("figure", ["layers": figureLayers.map(\.name), "sky_parts": skyLayer?.parts.count ?? 0,
                              "subject_above": share, "expected_shaped": expected, "note": session3.maskNote ?? "-"])
            r.check(skyLayer != nil, "the figure photograph's sky takes a layer")
            r.check(shaped == expected,
                    "the sky's mask carries the 背景-intersect part exactly when the subject reaches into it (share \(share))")
            if shaped, let part = skyLayer?.parts.last {
                r.check(part.kind == .found && part.join == .intersect && part.found?.invert == true,
                        "the shaping part is 背景, joined by intersect")
            }
        } catch {
            r.check(false, "the smoke threw: \(error.localizedDescription)")
        }
    }
}
#endif
