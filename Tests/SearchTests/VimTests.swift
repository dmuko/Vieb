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
