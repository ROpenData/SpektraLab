//  MacApplyFilmSheet.swift — Apply Film's picker, over a selection of the browser's pictures.
//
//  A cell's menu among several chosen opens it (`MacLibraryActions.applyFilmAsk`, presented by
//  `MacLibraryDialogs`): every film the catalogue has, shelf by shelf as the develop page's strips
//  are (`StockShelf`), a slide named scanned. Pick, then Apply; a double click does both (the
//  picker's rule, `MacPhotoPicker`). What the film does to each picture — its own paper, exposure
//  and adjustments kept, previews developed again, one Undo each — is `MacLibraryActions.applyFilm`'s;
//  the sheet only chooses the emulsion, by the catalogue's short names (never a profile id).
//
//  Mac only: the window's browser is the Mac's.

import SwiftUI

struct MacApplyFilmSheet: View {
    /// The chosen pictures the picked film goes onto, in the browser's order.
    let images: [MacImage]

    @Environment(AppServices.self) private var model
    private var actions: MacLibraryActions { MacLibraryActions.shared }
    @State private var picked: String?

    private var catalog: StockCatalog { .shared }
    /// The shelves the sheet lists, each a section: the film strip's own order, All left out (every
    /// film is on one shelf beside it).
    private static let shelves: [StockShelf] = [.negative, .positive, .cine, .mono]

    private func close() { actions.applyFilmAsk = nil }

    private func apply() {
        guard let picked else { return }
        close()
        actions.applyFilm(picked, onto: images, store: MacLibraryUI.store(model), model: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: L("Apply Film"),
                        subtitle: images.count == 1 ? L("Onto 1 picture. Each keeps its own exposure, paper and crop.")
                                                    : L("Onto \(images.count) pictures. Each keeps its own exposure, paper and crop."),
                        onClose: close)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Self.shelves, id: \.id) { shelf in
                        let films = catalog.films.filter(shelf.holds)
                        guard !films.isEmpty else { continue }
                        Text(shelf.title).font(Theme.Font.ui(12.5, .semibold)).foregroundStyle(Theme.secondaryText)
                            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
                        ForEach(films) { film in
                            row(film)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            FoldRule()
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                CapsuleButton(title: L("Cancel"), primary: false, height: 34, width: 110, action: close)
                CapsuleButton(title: L("Apply Film"), height: 34, width: 130, enabled: picked != nil, action: apply)
                    .accessibilityIdentifier("apply-film.confirm")
            }
            .padding(.horizontal, 16).frame(height: 58)
        }
        .accessibilityIdentifier("apply-film.sheet")
    }

    /// A film's row: its short name, its ISO, and a slide named scanned (`pairText`'s word). The
    /// chosen one wears the selection frame, as the photo picker's tile does.
    private func row(_ film: Stock) -> some View {
        let isPicked = picked == film.id
        return HStack(spacing: 10) {
            StockDot(color: film.color)
            Text(film.shortName).font(Theme.Font.ui(13.5, isPicked ? .semibold : .regular))
                .foregroundStyle(Theme.text).lineLimit(1)
            Spacer(minLength: 8)
            Text([film.isoText, catalog.isSlide(film.id) ? L(shown: StockCatalog.scannedWord) : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                .font(Theme.Font.ui(12, .regular)).foregroundStyle(Theme.dim).lineLimit(1)
        }
        .padding(.horizontal, 16).frame(height: 40)
        .background {
            if isPicked { Capsule().fill(Theme.selection).frame(maxWidth: .infinity).padding(.horizontal, 8) }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { picked = film.id; apply() }
        .onTapGesture { picked = film.id }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(film.shortName)
        .accessibilityAddTraits(isPicked ? [.isButton, .isSelected] : [.isButton])
    }
}
