//  AppMenuCommands.swift — the app's places in the operating system's menu bar, and their keys.
//
//  PAGES.md §6: in the operating system 26's menu bar, the desktop's keys where it has them. These are the
//  app-wide ones — places, not edits; a page's own keys (Develop's ⌘Z, ⌘B, ← →) are the page's.
//  ⌘1 and ⌘2 are the Library's own (Icons, List: Finder's keys), so the Go menu's places are ⌥⌘1, ⌥⌘2.
//  A host has no menu bar, and a hardware keyboard on one lists these under ⌘ held, which is
//  harmless.

import SwiftUI

struct AppMenuCommands: Commands {
    let model: AppServices

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            // 打开文件夹 first (the owner, 2026-11-17: "我来打开指定的目录，而不是帮我 import 文件"):
            // the pictures are referenced where they are and the folder joins the sources, selected.
            // Import — the page, ⌘⇧I — stays, the way in for files that have no folder to be read from.
            Button(L("Open Folder…")) {
                guard model.router.cover == nil, model.router.sheets.isEmpty else { return }
                guard !MacLibraryBrowser.shared.modal, MacShellPath.split(model.router.path).stacked.isEmpty else { return }
                Task { await Self.openPickedFolder(model) }
            }
                .keyboardShortcut("o", modifiers: .command)
                .accessibilityIdentifier("menu.open-folder")
            Button(L("Import")) {
                guard model.router.cover == nil, model.router.sheets.isEmpty else { return }
                guard !MacLibraryBrowser.shared.modal, MacShellPath.split(model.router.path).stacked.isEmpty else { return }
                MacLibraryBrowser.shared.importAsked = true
            }
                .keyboardShortcut(MacShortcut.importKey, modifiers: MacShortcut.importModifiers)
        }
        CommandGroup(replacing: .appSettings) {
            Button(L("Settings")) { SettingsRequest.openFromMenu(model.router) }
            .keyboardShortcut(",", modifiers: .command)
        }
        CommandMenu(L("Go")) {
            Button(L("Library")) {
                model.router.dismissAllSheets()
                model.router.dismissCover()
                model.router.home()
            }
            Button(L("Light Table")) {
                guard model.router.path.last != .lightTable, model.router.cover == nil else { return }
                model.router.open(.lightTable)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            Divider()
            Button(L("Back")) { if model.router.cover == nil, model.router.sheets.isEmpty { model.router.back() } }
                .keyboardShortcut("[", modifiers: .command)
        }
    }

    /// 打开文件夹…: the person picks a folder (or a library document — `store.open` reads which it was),
    /// it joins the sources and is selected, its pictures referenced where they are. The sidebar's own
    /// "Open Catalog or Folder…" is this same act (`MacLibrarySidebar.openSource`); the menu is the way
    /// in that needs no sidebar. A folder that cannot be read says so where the library's refusals say
    /// so (`MacLibraryActions.refusal`).
    static func openPickedFolder(_ model: AppServices) async {
        guard let url = await MacOpenPanel.choose(multiple: false)?.first else { return }
        let store = MacLibraryUI.store(model)
        do {
            _ = try await store.open(url)
        } catch {
            MacLibraryActions.shared.refusal = error.localizedDescription
        }
    }
}
