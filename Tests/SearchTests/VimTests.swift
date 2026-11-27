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
