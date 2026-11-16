//  apply_film_selftest.swift — Apply Film over a selection: what one frame takes when a film is
//  applied to it, and what it keeps.
//
//      tools/selftest.sh                # with the other checks
//      tools/selftest.sh --self-test    # the check's own check: each broken rule below must be caught
//
//  The Mac's Apply Film (a film put onto every chosen picture, the Windows fork's one-button batch)
//  moves the emulsion alone. The rule it must hold is PAGES.md §4 rule 8 — a film is loaded with
//  `FilmParams.load(film:)`, never set by `filmStock` alone — with the paper the frame chose kept
//  where the new film can print on it (`recommendingPaper: false`, as a copied pair is validated):
//
//  - the frame's own paper is kept when it prints the new film, not replaced by the film's
//    recommendation;
//  - silver on silver, colour on colour: a film the frame's paper cannot print brings the film's
//    own paper, both ways;
//  - a slide is scanned: `scanFilm` set, the paper dormant but still held to the same rule (the
//    bundle has no black-and-white slide, so that one runs over a catalogue made up here);
//  - back on a negative, the dormant paper prints again;
//  - a frame the film is already on takes nothing — not even a scanned negative's scan is flipped
//    to a print, which is the Windows fork's skip and the reason the guard reads `filmStock` first;
//  - everything else is the frame's own: exposure, adjustments, geometry, the film edge, a digital
//    intermediate;
//  - the history step it records names the film (`HistoryLabel.film`), and its origin travels
//    (`HistoryOrigin.filmApply`; a newer build's unknown origin still reads as `elsewhere`).
//
//  Compiled with the model, over the bundle's own catalogue (Resources/StockCatalog.json). The
//  frames' edit history on disk and the pages are not here: those are the in-app checks'.
//
//  AGENTS.md: a check that cannot fire is not a check. `--self-test` runs the same checks against the
//  rule broken on purpose, one part at a time, and requires each run to fail.

import Foundation
import SwiftUI

// `Stock.color` is the app's (`Theme.swift`, which is not compiled here). Nothing below looks at a colour.
extension Color {
    init(hexString: String) { self = .gray }
}

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
    /// `filmStock` set alone (PAGES.md §4 rule 8's "never"): no scan, no paper brought.
    case filmAlone
    /// The film's recommendation replaces a paper the frame chose that prints it.
    case recommendsPaper
    /// No skip for the film the frame already has: a scanned negative is flipped to a print.
    case noSkip
    /// A digital intermediate the frame chose is cleared with the film.
    case clearsDI
}

/// The rule as the model holds it (`FrameEdit.applied(film:)`), or the broken variant `--self-test`
/// asks for. The checks below never call the model past this, so a broken rule is what they see.
func applied(_ film: String, to edit: FrameEdit, catalog: StockCatalog, broken: Broken = .none) -> FrameEdit {
    switch broken {
    case .none:
        return edit.applied(film: film, catalog: catalog)
    case .filmAlone:
        guard edit.params.filmStock != film else { return edit }
        var e = edit
        e.params.filmStock = film
        return e
    case .recommendsPaper:
        guard edit.params.filmStock != film else { return edit }
        var e = edit
        e.params.load(film: film, catalog: catalog, recommendingPaper: true)
        return e
    case .noSkip:
        var e = edit
        e.params.load(film: film, catalog: catalog, recommendingPaper: false)
        return e
    case .clearsDI:
        var e = edit.applied(film: film, catalog: catalog)
        e.params.digitalIntermediate = false
        return e
    }
}

func checks(_ c: inout Checker, _ broken: Broken, catalog: StockCatalog) {
    func on(_ film: String, paper: String? = nil) -> FrameEdit {
        var e = FrameEdit.default
        e.params.load(film: film, catalog: catalog)
        if let paper { e.params.print(on: paper, catalog: catalog) }
        return e
    }
    let portra = "kodak_portra_400", pro400h = "fujifilm_pro_400h", triX = "kodak_tri_x_400", velvia = "fujifilm_velvia_100"

    // The frame's own paper is kept where the new film prints on it — not the film's recommendation
    // (Pro 400H's own is Crystal Archive; the frame chose Supra Endura, and Supra prints it).
    let kept = applied(pro400h, to: on(portra, paper: "kodak_supra_endura"), catalog: catalog, broken: broken)
    c.expect(kept.params.filmStock == pro400h && !kept.params.scanFilm, "a colour negative applied: the emulsion moves, and it prints")
    c.expect(kept.params.printStock == "kodak_supra_endura", "the frame's own paper is kept where the new film prints on it, not replaced by its recommendation")

    // Silver on silver, colour on colour (the pick's rule, held by the same load): Tri-X cannot
    // print on Supra Endura and brings its silver paper; Portra cannot print on the silver paper
    // and brings its own colour one back.
    let silver = applied(triX, to: on(portra, paper: "kodak_supra_endura"), catalog: catalog, broken: broken)
    c.expect(silver.params.printStock == "ilford_multigrade_iv_rc", "a black-and-white film applied to a colour frame brings the silver paper")
    let colour = applied(portra, to: on(triX), catalog: catalog, broken: broken)
    c.expect(colour.params.printStock == "kodak_portra_endura", "a colour film applied to a silver pair brings a colour paper")

    // A slide is scanned, its paper dormant for the next negative — held to the same silver-on-silver
    // rule while it sleeps (the bundle has no black-and-white slide; this one is made up).
    let slide = applied(velvia, to: on(portra, paper: "kodak_supra_endura"), catalog: catalog, broken: broken)
    c.expect(slide.params.scanFilm, "a slide applied is scanned")
    c.expect(slide.params.printStock == "kodak_supra_endura", "its paper sleeps, kept: a colour slide on the frame's colour paper")
    let back = applied(portra, to: slide, catalog: catalog, broken: broken)
    c.expect(!back.params.scanFilm && back.params.printStock == "kodak_supra_endura", "back on a negative, the dormant paper prints again")

    let monoSlide = Stock(id: "check_mono_slide", name: "Check Slide", shortName: "Slide", kind: "slide (positive)", stage: "filming", type: "positive", monochrome: true)
    let silverPaper = Stock(id: "check_silver", name: "Check Silver", shortName: "Silver", kind: "b&w paper", stage: "printing", monochrome: true)
    let madeUp = StockCatalog(stocks: [
        Stock(id: "check_colour_film", name: "Check Colour", shortName: "Colour", kind: "colour negative", stage: "filming", targetPrint: "check_colour_paper"),
        Stock(id: "check_colour_paper", name: "Check Colour Paper", shortName: "Colour Paper", kind: "colour paper", stage: "printing"),
        monoSlide, silverPaper
    ])
    // The frame begins on the made-up catalogue's own colour pair (the default edit's stocks are
    // the bundle's, which a catalogue of four does not know — and a stock the catalogue does not
    // know rules nothing out, so the swap would never be asked for).
    var colourStart = FrameEdit.default
    colourStart.params.load(film: "check_colour_film", catalog: madeUp)
    let mono = applied(monoSlide.id, to: colourStart, catalog: madeUp, broken: broken)
    c.expect(mono.params.scanFilm && mono.params.printStock == silverPaper.id,
             "a black-and-white slide sleeps on the silver paper: dormant is still held to silver on silver")

    // The film the frame already has changes nothing — a scanned negative keeps its scan (the skip
    // reads the film first, as the Windows fork's does, so `load` cannot flip it to a print).
    var scanned = on(portra)
    scanned.params.scanFilm = true
    c.expect(applied(portra, to: scanned, catalog: catalog, broken: broken) == scanned,
             "the film the frame already has changes nothing, not even a scanned negative's scan")

    // Everything else is the frame's own.
    var rich = on(portra, paper: "kodak_supra_endura")
    rich.params.exposureCompensationEV = 1.5
    rich.params.digitalIntermediate = true
    rich.filmEdge.active = true
    let moved = applied(pro400h, to: rich, catalog: catalog, broken: broken)
    c.expect(moved != rich && moved.params.exposureCompensationEV == 1.5, "the frame's film exposure is its own")
    c.expect(moved.adjustments == rich.adjustments && moved.geometry == rich.geometry && moved.filmEdge == rich.filmEdge,
             "its adjustments, its geometry and its film edge are its own")
    c.expect(moved.params.digitalIntermediate, "a digital intermediate the frame chose stays")
}

func labelChecks(_ c: inout Checker) {
    c.expect(HistoryLabel.film("Portra 400").text == "Film: Portra 400", "the history step names the film")
    c.expect(HistoryLabel.film("Portra 400").key == "Film" && HistoryLabel.film("Portra 400").value == "Portra 400",
             "as a kept key and a value, so switching the language relabels it and the film's name never translates")
    c.expect(HistoryOrigin(stored: HistoryOrigin.filmApply.rawValue) == .filmApply, "the origin travels")
    c.expect(HistoryOrigin(stored: "a newer build's") == .elsewhere, "a newer build's origin reads as elsewhere, not as a crash")
}

@main
struct ApplyFilmSelfTest {
    static func main() {
        // The bundle's own catalogue, from the repository: tools/../Resources.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        guard let catalog = StockCatalog(contentsOf: root.appendingPathComponent("Resources/StockCatalog.json")) else {
            print("apply film checks: no catalogue at Resources/StockCatalog.json")
            exit(1)
        }
        if CommandLine.arguments.contains("--self-test") {
            var caught = 0
            for broken in Broken.allCases where broken != .none {
                var c = Checker(quiet: true)
                checks(&c, broken, catalog: catalog)
                if c.failed.isEmpty { print("apply film checks: --self-test broke nothing for \(broken)"); exit(1) }
                caught += 1
            }
            print("apply film checks: each broken rule caught (\(caught))")
            exit(0)
        }
        var c = Checker(quiet: false)
        checks(&c, .none, catalog: catalog)
        labelChecks(&c)
        print("apply film checks: \(c.passed) passed, \(c.failed.count) failed")
        exit(c.failed.isEmpty ? 0 : 1)
    }
}
