//  MacFilmApplyCheck.swift — a debug build's proof of Apply Film over a selection, in the running app.
//
//      CFFIXED_USER_HOME=<scratch>/home SpektraLab --film-apply-check <dir> \
//          --film-apply-check-files <a.jpg> <b.jpg> <c.jpg> [--library-check-exit]
//
//  The one-act batch (the Windows fork's 应用此胶片到选中), through the Mac's own act
//  (`MacLibraryActions.applyFilm`) and against the real engine, writes `<dir>/report.json`:
//
//  1. a scratch SpektraLab catalog of the three files copied in, plus a fourth never-opened copy,
//     none of them ever opened;
//  2. the first three given frames of their own: the default pair, a Tri-X one with its exposure
//     set, and a Portra one on a paper it chose;
//  3. all three chosen, Pro 400H applied: every frame's emulsion moves, each keeps the paper that
//     prints it (Tri-X's silver one cannot print Pro 400H and gives way to the film's own), the
//     Tri-X one's exposure is untouched, the notice says how many and that previews are developing,
//     each frame's preview is developed again of the new film, and each has one step of history —
//     origin `filmApply`, named *Film: Pro 400H*;
//  4. Undo on a frame with no page (`goToStep`, as the history page undoes it): the Tri-X frame is
//     back on Tri-X and its silver paper;
//  5. one frame open in 冲洗 and chosen beside another: the film goes through the open page's
//     session — the page moves with it, one Undo takes it back, and no preview develop of the
//     library's is queued for it (its page develops it); the other frame still takes its step;
//  6. the film a frame already has, applied to it alone: the notice says so, and no step is made;
//  7. the fourth picture, never opened, chosen alone: a frame is made for it with the film on it
//     (the making path, `carryLimit` at a time, shared with a paste's).
//
//  Not in a release build.

#if DEBUG
import Foundation

@MainActor
enum MacFilmApplyCheck {
    static func startIfAsked(model: AppServices, arguments: [String] = CommandLine.arguments) {
        guard let i = arguments.firstIndex(of: "--film-apply-check"), i + 1 < arguments.count else { return }
        let out = URL(fileURLWithPath: arguments[i + 1])
        let files = arguments.firstIndex(of: "--film-apply-check-files").map { arguments[($0 + 1)...].prefix { !$0.hasPrefix("--") }.map { URL(fileURLWithPath: $0) } } ?? []
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
            print("film-apply-check: wrote \(out.appending(path: "report.json").path), \(r.failures.count) failures")
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
            print("film-apply-check: \(name) \(facts)")
        }
        func check(_ ok: Bool, _ what: String) {
            if !ok { failures.append(what); print("film-apply-check: FAIL \(what)") }
        }
    }

    private static func settle(_ seconds: Double = 0.6) async { try? await Task.sleep(for: .seconds(seconds)) }

    private static func wait(_ seconds: Double, _ done: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { if done() { return true }; try? await Task.sleep(for: .milliseconds(200)) }
        return done()
    }

    private static func choose(_ rows: [MacImage]) {
        let browser = MacLibraryBrowser.shared
        browser.selection = Set(rows.map(\.id))
        browser.focus = rows.first?.id
    }

    /// The steps a frame's history holds, with their origins and names, after every call sent before.
    private static func listing(_ model: AppServices, _ id: LibraryFrame.ID) async -> HistoryListing? {
        try? await model.history.ask("film apply check") { try await $0.listing(id) }
    }

    private static func run(_ model: AppServices, _ r: Report, out: URL, files: [URL]) async {
        let store = model.macLibrary
        let library = model.library
        let fm = FileManager.default
        guard files.count == 3 else { r.check(false, "three files: the default pair, the Tri-X one, the chosen paper one (\(files.count))"); return }
        await store.start()
        do {
            // 1. A catalog of three pictures nobody has opened, and a fourth copy of the first that
            //    stays never-opened until the last step.
            let work = out.appending(path: "work")
            try? fm.removeItem(at: work)
            let card = work.appending(path: "Card")
            try fm.createDirectory(at: card, withIntermediateDirectories: true)
            let names = files.enumerated().map { "\($0.offset + 1)-\($0.element.lastPathComponent)" }
            for (u, n) in zip(files, names) { try fm.copyItem(at: u, to: card.appending(path: n)) }
            try fm.copyItem(at: files[0], to: card.appending(path: "4-\(files[0].lastPathComponent)"))
            let cat = try await store.newCatalog(named: "Film Apply", in: work)
            try await store.addFolder(card, to: cat.id)
            let all = 4
            _ = await wait(60) { store.images.count == all }
            await store.select(collection: store.tree.defaultSelection)
            _ = await wait(30) { store.images.count == all }
            let rows = names.compactMap { n in store.images.first { $0.fileName == n } }
            let neverOpened = store.images.first { $0.fileName.hasPrefix("4-") }
            r.note("catalog", ["rows": rows.map(\.fileName), "never_opened": neverOpened?.fileName ?? "-", "listed": store.images.count])
            r.check(rows.count == 3 && neverOpened != nil && rows.allSatisfy { $0.develop == nil } && neverOpened?.develop == nil,
                    "four pictures, none with a frame")
            guard rows.count == 3, let neverOpened else { return }

            // 2. Frames of their own: the default pair, Tri-X with an exposure of its own, Portra on a
            //    paper it chose.
            let made = try await store.frames(for: rows.map(\.id), focus: rows[0].id).frames
            let frameIDs = rows.compactMap { made[$0.id] }
            guard frameIDs.count == 3 else { r.check(false, "the three pictures have their frames"); return }
            library.update(frameIDs[1]) { f in
                f.edit.params.load(film: "kodak_tri_x_400")
                f.edit.params.exposureCompensationEV = 1.25
            }
            library.update(frameIDs[2]) { $0.edit.params.print(on: "kodak_supra_endura") }
            await model.history.drained()
            let before = await listing(model, frameIDs[1])
            r.note("the frames", ["films": frameIDs.map { library.frame($0)?.edit.params.filmStock },
                                   "papers": frameIDs.map { library.frame($0)?.edit.params.printStock },
                                   "tri_x_steps": before?.steps.count ?? -1])

            // 3. All three chosen, Pro 400H applied.
            choose(rows)
            await settle()
            let actions = MacLibraryActions.shared
            actions.applyFilm("fujifilm_pro_400h", onto: rows, store: store, model: model)
            await actions.pastesLanded()
            await settle()
            let after = frameIDs.map { library.frame($0)?.edit }
            r.note("Pro 400H applied", ["films": after.map { $0?.params.filmStock }, "papers": after.map { $0?.params.printStock },
                                         "exposure": after.map { $0?.params.exposureCompensationEV },
                                         "notice": actions.notice?.line ?? "-"])
            r.check(after.allSatisfy { $0?.params.filmStock == "fujifilm_pro_400h" && $0?.params.scanFilm == false },
                    "every frame's emulsion moved, and Pro 400H prints")
            r.check(after[0]?.params.printStock == "kodak_portra_endura" && after[2]?.params.printStock == "kodak_supra_endura",
                    "the frames' own colour papers are kept where Pro 400H prints on them")
            r.check(after[1]?.params.printStock == "fujifilm_crystal_archive_typeii",
                    "Tri-X's silver paper cannot print Pro 400H: the film's own colour one came with it (\(after[1]?.params.printStock ?? "-"))")
            r.check(after[1]?.params.exposureCompensationEV == 1.25, "the Tri-X frame's exposure is its own")
            let pro400h = StockCatalog.shared.stock("fujifilm_pro_400h")?.shortName ?? ""
            r.check(actions.notice?.said == L("\(pro400h) applied onto \(3) pictures. The rest of their settings are their own."),
                    "the notice says what moved (\(actions.notice?.said ?? "nothing"))")
            r.check(actions.notice?.more == L("Their previews are developing."), "and that their previews are developing (\(actions.notice?.more ?? "nothing"))")
            let fresh = await wait(90) { frameIDs.allSatisfy { id in library.frame(id).map { !$0.develop.isBusy && !model.darkroom.needsDevelop($0) } ?? false } }
            r.note("the previews", ["fresh": fresh, "states": frameIDs.map { library.frame($0).map { "\($0.develop)" } ?? "-" }])
            r.check(fresh, "each frame's preview is developed again, of the new film, with nothing opened")
            await model.history.drained()
            for id in frameIDs {
                let steps = await listing(model, id)
                let last = steps?.steps.last
                r.check(last?.origin == .filmApply && last?.label.key == "Film" && last?.label.value == "Pro 400H",
                        "one step of history names the film (\(String(describing: last?.origin)) \(String(describing: last?.label.key)))")
            }
            library.flush()
            let saved = (try? Data(contentsOf: LibraryPersistence().url)).map { String(decoding: $0, as: UTF8.self) } ?? ""
            r.check(frameIDs.allSatisfy { saved.contains($0.uuidString) }, "the frames are in the saved library")

            // 4. Undo on the Tri-X frame, with no page: the history page's way back (`goToStep`).
            let listing2 = await listing(model, frameIDs[1])
            var undone = false
            if let listing2 { undone = await model.goToStep(frameIDs[1], listing2.cursorSeq - 1) }
            await settle()
            let back = library.frame(frameIDs[1])?.edit.params
            r.note("Undo on the Tri-X frame", ["undone": undone, "film": back?.filmStock ?? "-", "paper": back?.printStock ?? "-"])
            r.check(undone && back?.filmStock == "kodak_tri_x_400" && back?.printStock == "ilford_multigrade_iv_rc",
                    "the step takes the frame back to Tri-X and its silver paper")

            // 5. One frame open in 冲洗, chosen beside another: through the open page's session.
            try await store.openInDevelop([rows[0].id], focus: rows[0].id)
            let opened = await wait(20) { MacShellBar.shared.develop.flatMap { model.openSession($0.frameID) } != nil }
            guard opened, let bar = MacShellBar.shared.develop, let session = model.openSession(bar.frameID) else {
                r.check(false, "the first picture opens in 冲洗"); return
            }
            await settle(1.5)
            choose([rows[0], rows[2]])
            await settle()
            actions.applyFilm("kodak_ektar_100", onto: [rows[0], rows[2]], store: store, model: model)
            await actions.pastesLanded()
            await settle()
            r.note("Ektar 100 through the open page", ["session_film": session.edit.params.filmStock,
                                                        "other_film": library.frame(frameIDs[2])?.edit.params.filmStock,
                                                        "can_undo": session.canUndo])
            r.check(session.edit.params.filmStock == "kodak_ektar_100", "the page moved with the film")
            r.check(library.frame(frameIDs[2])?.edit.params.filmStock == "kodak_ektar_100", "the other frame took it too")
            r.check(model.scheduler.snapshot(frameID: session.frameID, where: { $0.kind == .importDevelop && $0.tier != .full }) == nil,
                    "the open frame gets no preview develop of the library's: its page develops it")
            r.check(session.canUndo, "and one Undo takes it back")
            _ = session.undo()
            await settle()
            r.check(session.edit.params.filmStock == "fujifilm_pro_400h", "Undo put the page back on Pro 400H")

            // 6. The film a frame already has, applied to it alone: nothing moves, nothing is made.
            await model.history.drained()
            let steps3 = (await listing(model, frameIDs[2]))?.steps.count ?? -1
            actions.applyFilm("kodak_ektar_100", onto: [rows[2]], store: store, model: model)
            await actions.pastesLanded()
            await settle()
            let steps3after = (await listing(model, frameIDs[2]))?.steps.count ?? -2
            r.note("the film it already has", ["notice": actions.notice?.line ?? "-", "steps": [steps3, steps3after]])
            r.check(actions.notice?.said == L("Every chosen picture is already on \(StockCatalog.shared.stock("kodak_ektar_100")?.shortName ?? "")."),
                    "the notice says every chosen picture is already on the film (\(actions.notice?.said ?? "nothing"))")
            r.check(steps3 == steps3after, "and no step of history is made for a frame that took nothing")

            // 7. The never-opened fourth, chosen alone: its frame is made with the film on it.
            actions.applyFilm("kodak_tri_x_400", onto: [neverOpened], store: store, model: model)
            await actions.pastesLanded()
            // The row is re-read as it lands: the MacImage taken at the catalog's making is a value
            // copy whose develop never joins (the store's rows are patched in place).
            let fourth = { store.images.first { $0.id == neverOpened.id } }
            let framed = await wait(30) { fourth()?.develop.flatMap { library.frame($0.frameID) } != nil }
            let madeFilm = fourth()?.develop.flatMap { library.frame($0.frameID) }.map { $0.edit.params.filmStock }
            r.note("the never-opened fourth", ["framed": framed, "film": madeFilm ?? "-"])
            r.check(framed && madeFilm == "kodak_tri_x_400", "a frame is made for a picture never opened, with the film on it")
        } catch {
            r.check(false, "the check threw: \(error.localizedDescription)")
        }
    }
}
#endif
