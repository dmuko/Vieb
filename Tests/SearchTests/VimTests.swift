import AppKit
import XCTest
@testable import Search

/// Vim keys (Vim.swift, docs/VIM.md): what a key is called, what keys in a
/// row come to, and the modes a window's keys pass through.
@MainActor
final class VimTests: XCTestCase {
    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    override func setUp() {
        _ = NSApplication.shared
    }

    private func key(_ characters: String, code: UInt16 = 0, flags: NSEvent.ModifierFlags = [],
                     ignoring: String? = nil, repeating: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                         windowNumber: 0, context: nil, characters: characters,
                         charactersIgnoringModifiers: ignoring ?? characters,
                         isARepeat: repeating, keyCode: code)!
    }

    // MARK: names

    func testAKeyIsWhatTheLayoutTypes() {
        XCTAssertEqual(VimKeys.name(of: key("j", code: 38)), "j")
        XCTAssertEqual(VimKeys.name(of: key("G", code: 5, flags: .shift, ignoring: "g")), "G")
        // Finnish: ⇧7 types /, ⌥8 types [.
        XCTAssertEqual(VimKeys.name(of: key("/", code: 26, flags: .shift, ignoring: "7")), "/")
        XCTAssertEqual(VimKeys.name(of: key("[", code: 28, flags: .option, ignoring: "8")), "[")
        XCTAssertEqual(VimKeys.name(of: key("$", code: 21, flags: .shift, ignoring: "4")), "$")
    }

    func testCommandIsNeverVims() {
        XCTAssertNil(VimKeys.name(of: key("j", code: 38, flags: .command)))
        XCTAssertNil(VimKeys.name(of: key("J", code: 38, flags: [.command, .shift], ignoring: "j")))
    }

    func testControlAndEscapeHaveTheirNames() {
        XCTAssertEqual(VimKeys.name(of: key("\u{1b}", code: 53)), "<esc>")
        XCTAssertEqual(VimKeys.name(of: key("\n", code: 38, flags: .control, ignoring: "j")), "<c-j>")
    }

    func testKeysVimHasNoWordForGoOn() {
        XCTAssertNil(VimKeys.name(of: key("\r", code: 36)), "Return")
        XCTAssertNil(VimKeys.name(of: key(" ", code: 49)), "Space")
        XCTAssertNil(VimKeys.name(of: key("\t", code: 48)), "Tab")
        XCTAssertNil(VimKeys.name(of: key("\u{7f}", code: 51)), "⌫")
        XCTAssertNil(VimKeys.name(of: key(String(UnicodeScalar(NSDownArrowFunctionKey)!), code: 125)), "↓")
    }

    // MARK: sequences

    func testOneKeyRunsAtOnce() {
        var sequence = VimSequence()
        XCTAssertEqual(sequence.feed("j"), .run(.scrollDown))
        XCTAssertEqual(sequence.feed("K"), .run(.nextTab))
        XCTAssertEqual(sequence.feed("/"), .run(.enterFindMode))
    }

    func testTwoKeysWaitForTheSecond() {
        var sequence = VimSequence()
        XCTAssertEqual(sequence.feed("g"), .pending)
        XCTAssertEqual(sequence.typed, "g")
        XCTAssertEqual(sequence.feed("g"), .run(.scrollToTop))
        XCTAssertEqual(sequence.typed, "")
        XCTAssertEqual(sequence.feed("g"), .pending)
        XCTAssertEqual(sequence.feed("T"), .run(.previousTab))
        XCTAssertEqual(sequence.feed("y"), .pending)
        XCTAssertEqual(sequence.feed("y"), .run(.copyCurrentUrl))
        XCTAssertEqual(sequence.feed("g"), .pending)
        XCTAssertEqual(sequence.feed("$"), .run(.lastTab))
    }

    func testAKeyNoPrefixWantsCountsAlone() {
        var sequence = VimSequence()
        XCTAssertEqual(sequence.feed("g"), .pending)
        XCTAssertEqual(sequence.feed("j"), .run(.scrollDown), "g then j: the g forgotten, j itself")
        XCTAssertEqual(sequence.feed("y"), .pending)
        XCTAssertEqual(sequence.feed("q"), .pass, "y then q: neither is anything")
        XCTAssertEqual(sequence.typed, "")
    }

    func testUnmappedKeysPass() {
        var sequence = VimSequence()
        XCTAssertEqual(sequence.feed("z"), .pass)
        XCTAssertEqual(sequence.feed("ä"), .pass)
    }

    func testAMapOfOnesOwn() {
        var sequence = VimSequence(map: ["ö": .previousTab, "ä": .nextTab])
        XCTAssertEqual(sequence.feed("ä"), .run(.nextTab))
        XCTAssertEqual(sequence.feed("j"), .pass)
    }

    func testJAndKFollowTheTabs() {
        var across = VimSequence(map: VimCommand.defaults(column: false))
        XCTAssertEqual(across.feed("K"), .run(.nextTab), "a row across the top: K is the tab to the right")
        XCTAssertEqual(across.feed("J"), .run(.previousTab))
        var column = VimSequence(map: VimCommand.defaults(column: true))
        XCTAssertEqual(column.feed("J"), .run(.nextTab), "a column: J is the tab below")
        XCTAssertEqual(column.feed("K"), .run(.previousTab))
        XCTAssertEqual(column.feed("g"), .pending)
        XCTAssertEqual(column.feed("t"), .run(.nextTab), "gt is next either way")
    }

    // MARK: hints

    func testHintsAreShortAndNoneStartsAnother() {
        for count in [1, 2, 3, 14, 15, 60, 196, 197, 500] {
            let labels = VimKeys.labels(count, alphabet: Preferences.vimHintDefault)
            XCTAssertEqual(labels.count, count)
            XCTAssertEqual(Set(labels).count, count, "none twice")
            for a in labels { for b in labels where a != b { XCTAssertFalse(b.hasPrefix(a), "\(a) starts \(b)") } }
            let longest = labels.map(\.count).max() ?? 0
            XCTAssertLessThanOrEqual(longest, count <= 14 ? 1 : count <= 196 ? 2 : 3, "\(count) links")
        }
    }

    func testTheHomeRowFirst() {
        XCTAssertEqual(VimKeys.labels(3, alphabet: Preferences.vimHintDefault), ["a", "d", "s"])
        XCTAssertEqual(VimKeys.labels(3, alphabet: "ab"), ["aa", "b", "ab"])
        XCTAssertEqual(VimKeys.labels(0, alphabet: "ab"), [])
    }

    func testHintLettersAreKeptUsable() {
        XCTAssertEqual(VimKeys.alphabet("asdfjklö"), "asdfjklö")
        XCTAssertEqual(VimKeys.alphabet("AaSs"), "as", "lower case, none twice")
        XCTAssertEqual(VimKeys.alphabet("a"), Preferences.vimHintDefault, "one letter can't make hints")
        XCTAssertEqual(VimKeys.alphabet(" ,.-"), Preferences.vimHintDefault)
    }

    func testFAndGiAreTheirs() {
        var sequence = VimSequence()
        XCTAssertEqual(sequence.feed("f"), .run(.linkHints))
        XCTAssertEqual(sequence.feed("F"), .run(.linkHintsNewTab))
        XCTAssertEqual(sequence.feed("g"), .pending)
        XCTAssertEqual(sequence.feed("i"), .run(.focusInput))
        XCTAssertEqual(VimCommand.linkHints.rawValue, "LinkHints.activateMode", "Vimium's name")
    }

    // MARK: opening

    func testOpeningKeysAreVimiums() {
        var sequence = VimSequence()
        XCTAssertEqual(sequence.feed("o"), .run(.openField))
        XCTAssertEqual(sequence.feed("O"), .run(.openFieldNewTab))
        XCTAssertEqual(sequence.feed("b"), .run(.openBookmarks))
        XCTAssertEqual(sequence.feed("B"), .run(.openBookmarksNewTab))
        XCTAssertEqual(sequence.feed("T"), .run(.openTabs))
        XCTAssertEqual(sequence.feed("g"), .pending)
        XCTAssertEqual(sequence.feed("e"), .run(.editAddress))
        XCTAssertEqual(sequence.feed("g"), .pending)
        XCTAssertEqual(sequence.feed("E"), .run(.editAddressNewTab))
        XCTAssertEqual(VimCommand.openTabs.rawValue, "Vomnibar.activateTabSelection", "Vimium's name")
    }

    func testControlWalksAList() {
        XCTAssertEqual(VimCommand.listSteps[VimKeys.name(of: key("\n", code: 38, flags: .control, ignoring: "j"))!], 1)
        XCTAssertEqual(VimCommand.listSteps[VimKeys.name(of: key("\u{0b}", code: 40, flags: .control, ignoring: "k"))!], -1)
        XCTAssertEqual(VimCommand.listSteps["<c-n>"], 1)
        XCTAssertEqual(VimCommand.listSteps["<c-p>"], -1)
        XCTAssertNil(VimCommand.defaults["<c-j>"], "not a command: only a list's")
    }

    func testControlLeavesAFieldWithNoListAlone() {
        let browser = browser()
        defer { browser.closeAll() }
        // No field up: ⌃K is the field's or the page's (the rest of the line).
        XCTAssertFalse(browser.vim.take(key("\u{0b}", code: 40, flags: .control, ignoring: "k"), typing: true))
    }

    func testBookmarksAloneInTheirOrderThenAsFound() {
        let bookmarks = Bookmarks(file: "bookmarks-vim-\(UUID().uuidString).json")
        defer { bookmarks.retire() }
        _ = bookmarks.add(URL(string: "https://zebra.example/")!, title: "Zebra")
        _ = bookmarks.add(URL(string: "https://apple.example/")!, title: "Apple")
        _ = bookmarks.add(URL(string: "https://mango.example/")!, title: "Mango")
        _ = bookmarks.add(URL(string: "javascript:alert(1)")!, title: "A bookmarklet")
        XCTAssertEqual(bookmarks.places(matching: "", limit: 10).map(\.title), ["Zebra", "Apple", "Mango"],
                       "nothing typed: as they are kept, no bookmarklet")
        XCTAssertEqual(bookmarks.places(matching: "", limit: 2).count, 2)
        XCTAssertEqual(bookmarks.places(matching: "m", limit: 10).map(\.title), ["Mango"])
        XCTAssertEqual(bookmarks.places(matching: "appl", limit: 10).map(\.title), ["Apple"])
        XCTAssertTrue(bookmarks.places(matching: "", limit: 10).allSatisfy { $0.kind == .bookmark })
    }

    func testBookmarksAloneGoWithTheField() {
        let browser = browser()
        defer { browser.closeAll() }
        browser.openBookmarksField(newTab: false)
        XCTAssertTrue(browser.editing)
        XCTAssertTrue(browser.onlyBookmarks)
        XCTAssertEqual(browser.typed, "")
        browser.summon()
        XCTAssertFalse(browser.onlyBookmarks, "⌘K over it offers its own")
        browser.openBookmarksField(newTab: false)
        browser.editing = false
        XCTAssertFalse(browser.onlyBookmarks, "and the next field is as ever")
    }

    // MARK: lists

    func testAListIsWalkedRowByRow() {
        let list = VimList()
        list.rows = { ["a", "b", "c"] }
        list.move(-1)
        XCTAssertEqual(list.selected, "c", "k from none: the last")
        list.selected = nil
        list.move(1)
        XCTAssertEqual(list.selected, "a", "j from none: the first")
        list.move(1); list.move(1); list.move(1)
        XCTAssertEqual(list.selected, "c", "and no further than the last")
        list.move(-5)
        XCTAssertEqual(list.selected, "a")
        list.toEnd(true)
        XCTAssertEqual(list.selected, "c")
        list.rows = { ["a", "b"] }
        list.move(1)
        XCTAssertEqual(list.selected, "a", "a row gone from the page counts as none")
    }

    func testAPressIsThePickedRowsAlone() {
        let list = VimList()
        list.rows = { ["a", "b"] }
        XCTAssertFalse(list.press(), "nothing picked: the key goes on")
        XCTAssertNil(list.press(for: "a"))
        list.selected = "a"
        let before = list.press(for: "a")
        XCTAssertTrue(list.press())
        XCTAssertNotEqual(list.press(for: "a"), before, "the row's controls hear it")
        XCTAssertNil(list.press(for: "b"), "another row's don't")
        list.activate = { $0 == "a" }
        let held = list.press(for: "a")
        XCTAssertTrue(list.press())
        XCTAssertEqual(list.press(for: "a"), held, "a row the page did itself is no control's press")
    }

    func testTheTabInFrontHasItsList() {
        let browser = browser()
        defer { browser.closeAll() }
        let mine = VimList(), other = VimList()
        mine.tab = browser.activeID
        other.tab = UUID()
        browser.vim.register(mine)
        browser.vim.register(other)
        XCTAssertTrue(browser.vim.list === mine)
        let again = VimList()
        again.tab = browser.activeID
        browser.vim.register(again)
        XCTAssertTrue(browser.vim.list === again, "the page drawn again takes its tab's place")
        again.letGo()
        XCTAssertNil(browser.vim.list, "gone, it has no tab")
    }

    func testListKeysWalkInsteadOfScrolling() {
        let browser = browser()
        defer { browser.closeAll() }
        let list = VimList()
        list.tab = browser.activeID
        list.rows = { ["a", "b", "c"] }
        var sections: [Int] = []
        list.section = { sections.append($0) }
        browser.vim.register(list)
        XCTAssertTrue(browser.vim.take(key("j", code: 38), typing: false))
        XCTAssertEqual(list.selected, "a")
        _ = browser.vim.take(key("G", code: 5, flags: .shift, ignoring: "g"), typing: false)
        XCTAssertEqual(list.selected, "c")
        _ = browser.vim.take(key("l", code: 37), typing: false)
        _ = browser.vim.take(key("h", code: 4), typing: false)
        XCTAssertEqual(sections, [1, -1])
        XCTAssertTrue(browser.vim.take(key("\r", code: 36), typing: false), "Return presses the row")
        XCTAssertFalse(browser.vim.take(key("\r", code: 36, flags: .command), typing: false), "⌘Return is Search's")
        XCTAssertTrue(browser.vim.take(key("\u{1b}", code: 53), typing: false))
        XCTAssertNil(list.selected, "Escape lets go of the row")
        XCTAssertFalse(browser.vim.take(key("\r", code: 36), typing: false), "no row: Return goes on")
        XCTAssertFalse(browser.vim.take(key("j", code: 38), typing: true), "in Find a setting, j is typed")
    }

    func testSettingsRowsAreWhatThePageDraws() {
        let prefs = Preferences()
        let rows = SettingsPanel.vimRows(page: .keyboard, query: "", advancedOpen: [], prefs: prefs)
        XCTAssertTrue(rows.contains("vim.keys"))
        XCTAssertEqual(rows.last, SettingsPanel.advancedRow, "Advanced folded: its fold, last")
        XCTAssertFalse(rows.contains("keys.backspaceBack"), "under the fold")
        let open = SettingsPanel.vimRows(page: .keyboard, query: "", advancedOpen: [.keyboard], prefs: prefs)
        XCTAssertTrue(open.contains("keys.backspaceBack"))
        XCTAssertEqual(Set(rows).count, rows.count, "no row twice")
        prefs.vimKeys = false
        XCTAssertFalse(SettingsPanel.vimRows(page: .keyboard, query: "", advancedOpen: [], prefs: prefs).contains("vim.hints"),
                       "a row that doesn't count isn't drawn")
        prefs.vimKeys = true
        XCTAssertTrue(SettingsPanel.vimRows(page: .keyboard, query: "", advancedOpen: [], prefs: prefs).contains("vim.hints"))
        prefs.vimKeys = false
        XCTAssertEqual(SettingsPanel.vimRows(page: .extensions, query: "", advancedOpen: [], prefs: prefs), [],
                       "a section drawn its own way: none, j and k scroll it")
        XCTAssertTrue(SettingsPanel.vimRows(page: .general, query: "vimium", advancedOpen: [], prefs: prefs).contains("vim.keys"),
                      "searching: the rows found, whatever the page")
    }

    func testEveryCommandHasADefaultKey() {
        XCTAssertEqual(Set(VimCommand.defaults.values), Set(VimCommand.allCases))
    }

    // MARK: modes

    private func browser() -> Browser {
        let browser = Browser(record: WindowRecord())
        browser.activeID = UUID()
        return browser
    }

    func testIHandsTheTabEveryKeyUntilEscape() {
        let browser = browser()
        defer { browser.closeAll() }
        let vim = browser.vim
        XCTAssertTrue(vim.take(key("i", code: 34), typing: false))
        XCTAssertTrue(vim.inserting)
        XCTAssertFalse(vim.take(key("j", code: 38), typing: false), "j is the page's")
        XCTAssertFalse(vim.take(key("x", code: 7), typing: false), "x too")
        XCTAssertTrue(vim.take(key("\u{1b}", code: 53), typing: false), "Escape is Vim's: back to its keys")
        XCTAssertFalse(vim.inserting)
    }

    func testInsertIsTheTabsOwn() {
        let browser = browser()
        defer { browser.closeAll() }
        let vim = browser.vim
        let first = browser.activeID
        _ = vim.take(key("i", code: 34), typing: false)
        browser.activeID = UUID()
        XCTAssertFalse(vim.inserting, "another tab has Vim's keys")
        browser.activeID = first
        XCTAssertTrue(vim.inserting, "and coming back finds it as it was left")
    }

    func testTypingLeavesEveryKeyToTheField() {
        let browser = browser()
        defer { browser.closeAll() }
        let vim = browser.vim
        XCTAssertFalse(vim.take(key("j", code: 38), typing: true))
        XCTAssertFalse(vim.take(key("i", code: 34), typing: true))
        XCTAssertFalse(vim.inserting)
        XCTAssertFalse(vim.take(key("\u{1b}", code: 53), typing: true), "Escape is leaveField's, later")
    }

    func testAHalfTypedKeyShowsAndEscapeLetsItGo() {
        let browser = browser()
        defer { browser.closeAll() }
        let vim = browser.vim
        XCTAssertTrue(vim.take(key("g", code: 5), typing: false))
        XCTAssertEqual(vim.pending, "g")
        XCTAssertTrue(vim.take(key("\u{1b}", code: 53), typing: false))
        XCTAssertEqual(vim.pending, "")
        XCTAssertFalse(vim.take(key("\u{1b}", code: 53), typing: false), "a second Escape is Search's as ever")
    }

    func testTheListOfKeysGoesAtAnyKey() {
        let browser = browser()
        defer { browser.closeAll() }
        let vim = browser.vim
        XCTAssertTrue(vim.take(key("?", code: 27, flags: .shift, ignoring: "+"), typing: false))
        XCTAssertTrue(vim.helping)
        XCTAssertTrue(vim.take(key("\u{1b}", code: 53), typing: false))
        XCTAssertFalse(vim.helping)
        _ = vim.take(key("?", code: 27, flags: .shift, ignoring: "+"), typing: false)
        XCTAssertFalse(vim.take(key("z", code: 6), typing: false), "a key of the page's puts it away and goes on")
        XCTAssertFalse(vim.helping)
    }

    func testKeysWithCommandGoOn() {
        let browser = browser()
        defer { browser.closeAll() }
        XCTAssertFalse(browser.vim.take(key("x", code: 7, flags: .command), typing: false))
        XCTAssertFalse(browser.vim.take(key("i", code: 34, flags: .command), typing: false))
        XCTAssertFalse(browser.vim.inserting)
    }

    func testOffUntilTurnedOn() {
        Store.settings.removeObject(forKey: "vim.keys")
        XCTAssertFalse(Preferences().vimKeys)
    }
}
