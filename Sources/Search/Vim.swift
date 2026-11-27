import AppKit
import SwiftUI
import WebKit

// Vim keys, as Vimium has them, but read by Search itself rather than by a
// script in every page (docs/VIM.md). Off unless turned on (Settings ›
// Keyboard & Mouse › Vim keys); while off, the window's key monitor asks
// one Bool and nothing here runs.
//
// The keys come through ContentView.take, the one place every key of a
// browser window passes before WebKit, SwiftUI and the menus. Nothing is
// injected into pages: a command that needs the page (scrolling) runs one
// call in Search's own world when it is pressed, and whether the caret is in
// a field is what Forms.swift already tells the tab (Tab.typing).
//
// A key is read as the character the layout types, so on a Finnish keyboard
// / is ⇧7 and [ is ⌥8, as in Vimium. Never with ⌘ held: every shortcut of
// Search's and the Mac's stays as it was.

/// A command a key can run. The raw values are Vimium's names, so a line of
/// a Vimium mapping means the same here.
enum VimCommand: String, CaseIterable {
    case scrollDown, scrollUp, scrollLeft, scrollRight
    case scrollPageDown, scrollPageUp, scrollToTop, scrollToBottom
    case nextTab, previousTab, firstTab, lastTab
    case removeTab, restoreTab, createTab, duplicateTab
    case goBack, goForward, reload
    case enterFindMode, performFind, performBackwardsFind
    case copyCurrentUrl
    case enterInsertMode
    case showHelp

    /// Vimium's own keys for them, made for a row of tabs across the top:
    /// K goes right, J left.
    static let defaults: [String: VimCommand] = [
        "j": .scrollDown, "k": .scrollUp, "h": .scrollLeft, "l": .scrollRight,
        "d": .scrollPageDown, "u": .scrollPageUp, "gg": .scrollToTop, "G": .scrollToBottom,
        "K": .nextTab, "gt": .nextTab, "J": .previousTab, "gT": .previousTab,
        "g0": .firstTab, "g$": .lastTab,
        "x": .removeTab, "X": .restoreTab, "t": .createTab, "yt": .duplicateTab,
        "H": .goBack, "L": .goForward, "r": .reload,
        "/": .enterFindMode, "n": .performFind, "N": .performBackwardsFind,
        "yy": .copyCurrentUrl,
        "i": .enterInsertMode,
        "?": .showHelp,
    ]

    /// The keys for the way the tabs run. Down a column, J goes down to
    /// the tab below and K up to the one above, as j and k move in Vim;
    /// Vimium's K-is-right only reads that way in a row across the top.
    /// gt and gT stay next and previous either way.
    static func defaults(column: Bool) -> [String: VimCommand] {
        guard column else { return defaults }
        var map = defaults
        map["J"] = .nextTab
        map["K"] = .previousTab
        return map
    }

    /// Held down, the key runs again: scrolling and walking the tabs. The
    /// others run once, so a held x doesn't close the window's every tab.
    var repeats: Bool {
        switch self {
        case .scrollDown, .scrollUp, .scrollLeft, .scrollRight, .scrollPageDown, .scrollPageUp,
             .nextTab, .previousTab, .performFind, .performBackwardsFind: true
        default: false
        }
    }

    /// What it does, in the help's words.
    var title: String {
        switch self {
        case .scrollDown: "Scroll down"
        case .scrollUp: "Scroll up"
        case .scrollLeft: "Scroll left"
        case .scrollRight: "Scroll right"
        case .scrollPageDown: "Scroll half a page down"
        case .scrollPageUp: "Scroll half a page up"
        case .scrollToTop: "Go to the top"
        case .scrollToBottom: "Go to the bottom"
        case .nextTab: "Next tab"
        case .previousTab: "Previous tab"
        case .firstTab: "First tab"
        case .lastTab: "Last tab"
        case .removeTab: "Close tab"
        case .restoreTab: "Reopen closed tab"
        case .createTab: "New tab"
        case .duplicateTab: "Duplicate tab"
        case .goBack: "Back"
        case .goForward: "Forward"
        case .reload: "Reload"
        case .enterFindMode: "Find in page"
        case .performFind: "Next match"
        case .performBackwardsFind: "Previous match"
        case .copyCurrentUrl: "Copy the page's address"
        case .enterInsertMode: "Keys to the page until Escape"
        case .showHelp: "Show these keys"
        }
    }

    enum Group: String, CaseIterable {
        case page = "Page", tabs = "Tabs", find = "Find", other = "Other"
    }

    var group: Group {
        switch self {
        case .scrollDown, .scrollUp, .scrollLeft, .scrollRight, .scrollPageDown, .scrollPageUp,
             .scrollToTop, .scrollToBottom, .goBack, .goForward, .reload, .copyCurrentUrl: .page
        case .nextTab, .previousTab, .firstTab, .lastTab, .removeTab, .restoreTab, .createTab, .duplicateTab: .tabs
        case .enterFindMode, .performFind, .performBackwardsFind: .find
        case .enterInsertMode, .showHelp: .other
        }
    }
}

/// The keys typed so far, and what they come to. Nothing of a window in it,
/// so the tests feed it keys alone.
struct VimSequence {
    enum Outcome: Equatable {
        /// The keys make this command.
        case run(VimCommand)
        /// The start of a longer key (g of gg): waiting for the next.
        case pending
        /// Nothing of Vim's: the key goes on to the page.
        case pass
    }

    var map: [String: VimCommand]
    private(set) var typed = ""

    init(map: [String: VimCommand] = VimCommand.defaults) {
        self.map = map
    }

    mutating func feed(_ key: String) -> Outcome {
        let keys = typed + key
        if let command = map[keys] {
            typed = ""
            return .run(command)
        }
        if map.keys.contains(where: { $0.count > keys.count && $0.hasPrefix(keys) }) {
            typed = keys
            return .pending
        }
        // g then something that follows no g: forget the g, and the key
        // counts on its own, as it does in Vimium.
        guard !typed.isEmpty else { return .pass }
        typed = ""
        return feed(key)
    }

    mutating func reset() { typed = "" }
}

@MainActor
final class VimKeys: ObservableObject {
    /// The keys of a longer key typed so far, for the badge.
    @Published private(set) var pending = ""
    /// The tab whose page has every key until Escape (i). Only that tab's:
    /// another tab is in the usual keys, and coming back finds it as left.
    @Published private(set) var insertTab: Tab.ID?
    /// The list of keys (?) is up.
    @Published var helping = false

    private weak var browser: Browser?
    private var sequence = VimSequence()
    /// Whether `sequence`'s keys are those for tabs down a column.
    private var column = false

    /// The keys as they are now, for the list of keys.
    var map: [String: VimCommand] { sequence.map }
    private var expiry: DispatchWorkItem?

    init(browser: Browser) {
        self.browser = browser
    }

    /// Whether the page in front has every key (i).
    var inserting: Bool {
        guard let id = insertTab else { return false }
        return browser?.activeID == id
    }

    /// The key as Vim names it: what the layout types, or <esc>, <c-j>.
    /// Nil for a key Vim has no word for (arrows, function keys), which
    /// then goes on as it came.
    static func name(of event: NSEvent) -> String? {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if flags.contains(.command) { return nil }
        if event.keyCode == 53 { return "<esc>" }
        if flags.contains(.control) {
            guard let letter = event.charactersIgnoringModifiers?.lowercased(), letter.count == 1,
                  letter.unicodeScalars.allSatisfy({ $0.isASCII && $0.properties.isAlphabetic })
            else { return nil }
            return "<c-\(letter)>"
        }
        guard let typed = event.characters, typed.count == 1, let scalar = typed.unicodeScalars.first,
              // Return, Tab, Space, ⌫ and the private-use range AppKit puts
              // arrows and function keys in stay the page's.
              scalar.value > 0x20, scalar.value != 0x7F, !(0xF700...0xF8FF).contains(scalar.value)
        else { return nil }
        return typed
    }

    /// A key of the window's, before Search's own keys and the page's.
    /// True when it was Vim's and goes no further. `typing`: the caret is
    /// in a field, the page's or Search's, and every key but Escape is the
    /// field's (Escape is `leaveField`'s, after Search's own Escapes).
    func take(_ event: NSEvent, typing: Bool) -> Bool {
        guard let browser else { return false }
        let name = VimKeys.name(of: event)
        if browser.prefs.sidebar != column {
            column = browser.prefs.sidebar
            sequence = VimSequence(map: VimCommand.defaults(column: column))
            pending = ""
        }

        if helping {
            helping = false
            return name == "<esc>" || name == "?" || name == "q"
        }
        if inserting {
            guard name == "<esc>" else { return false }
            insertTab = nil
            return true
        }
        if typing || name == nil {
            clear()
            return false
        }
        if name == "<esc>" {
            // A half-typed key is let go of; otherwise Escape is Search's
            // and the page's as ever.
            guard !sequence.typed.isEmpty else { return false }
            clear()
            return true
        }
        switch sequence.feed(name!) {
        case .pass:
            clear()
            return false
        case .pending:
            pending = sequence.typed
            expire()
            return true
        case .run(let command):
            clear()
            if event.isARepeat, !command.repeats { return true }
            run(command, in: browser, repeating: event.isARepeat)
            return true
        }
    }

    /// Escape with the caret in a box on the page: the box lets it go and
    /// the keys are Vim's again, as in Vimium. Search's own fields (the
    /// address field, the find bar) keep their Escape.
    func leaveField(_ event: NSEvent) -> Bool {
        guard let browser, event.keyCode == 53, let tab = browser.active, let page = tab.built,
              event.window?.firstResponder === page, tab.typing || page.inputContext != nil
        else { return false }
        page.evaluateInSearch(VimPage.blur)
        tab.typing = false
        return true
    }

    private func clear() {
        expiry?.cancel()
        expiry = nil
        sequence.reset()
        if !pending.isEmpty { pending = "" }
    }

    /// A key half typed is forgotten after a second, as Vim's timeoutlen.
    private func expire() {
        expiry?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.clear() }
        expiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func run(_ command: VimCommand, in browser: Browser, repeating: Bool) {
        let step = VimPage.step
        switch command {
        case .scrollDown: VimPage.scroll(browser, .by(dx: 0, dy: step), smooth: !repeating)
        case .scrollUp: VimPage.scroll(browser, .by(dx: 0, dy: -step), smooth: !repeating)
        case .scrollLeft: VimPage.scroll(browser, .by(dx: -step, dy: 0), smooth: !repeating)
        case .scrollRight: VimPage.scroll(browser, .by(dx: step, dy: 0), smooth: !repeating)
        case .scrollPageDown: VimPage.scroll(browser, .half(1), smooth: !repeating)
        case .scrollPageUp: VimPage.scroll(browser, .half(-1), smooth: !repeating)
        case .scrollToTop: VimPage.scroll(browser, .top, smooth: true)
        case .scrollToBottom: VimPage.scroll(browser, .bottom, smooth: true)
        case .nextTab: browser.step(1)
        case .previousTab: browser.step(-1)
        case .firstTab: browser.select(index: 0)
        case .lastTab: browser.select(index: browser.tabShortcutTargets.count - 1)
        case .removeTab: browser.closeFront()
        case .restoreTab: browser.reopen()
        case .createTab: browser.launch()
        case .duplicateTab: browser.duplicate()
        case .goBack: browser.back()
        case .goForward: browser.forward()
        case .reload: browser.reload()
        case .enterFindMode: browser.openFind()
        case .performFind: browser.look(forward: true)
        case .performBackwardsFind: browser.look(forward: false)
        case .copyCurrentUrl: browser.copyAddress()
        case .enterInsertMode: insertTab = browser.activeID
        case .showHelp: helping = true
        }
    }
}

// MARK: - the page

/// What Vim does to a page, one call at a time, in Search's own world.
@MainActor
enum VimPage {
    /// One press of j, in points: Vimium's.
    static let step: Double = 60

    enum Scroll {
        case by(dx: Double, dy: Double)
        /// Half of what shows, down (1) or up (-1).
        case half(Double)
        case top, bottom
    }

    /// The page the keys act on: a peek in front, as ⌘R reloads it, or the
    /// tab's (in Split View, the pane that has the keys).
    static func page(_ browser: Browser) -> PageView? {
        if browser.peekInFront, let peek = browser.peekTab?.built { return peek }
        return browser.active?.built
    }

    static func scroll(_ browser: Browser, _ scroll: Scroll, smooth: Bool) {
        guard let page = page(browser) else {
            scrollNatively(browser, scroll)
            return
        }
        var arguments: [String: Any] = ["dx": 0, "dy": 0, "half": 0, "to": "", "smooth": smooth]
        switch scroll {
        case .by(let dx, let dy): arguments["dx"] = dx; arguments["dy"] = dy
        case .half(let sign): arguments["half"] = sign
        case .top: arguments["to"] = "top"
        case .bottom: arguments["to"] = "bottom"
        }
        page.callInSearch(scrollBody, arguments: arguments)
    }

    /// The thing to scroll is the one Vimium would pick: what holds the
    /// focus, if it scrolls; else the page, if it scrolls; else whatever
    /// scrolls under the middle of the window, as in a web app whose page
    /// stands still and whose panes scroll (Gmail, Slack).
    static let scrollBody = #"""
    const vertical = dy !== 0 || half !== 0 || to !== '';
    const root = document.scrollingElement || document.documentElement;
    if (!root) return;
    const scrolls = (el) => {
      if (!el || el.nodeType !== 1) return false;
      if (el === root) return vertical ? root.scrollHeight > innerHeight + 1 : root.scrollWidth > innerWidth + 1;
      const style = getComputedStyle(el);
      const overflow = vertical ? style.overflowY : style.overflowX;
      if (!/(auto|scroll|overlay)/.test(overflow)) return false;
      return vertical ? el.scrollHeight > el.clientHeight + 1 : el.scrollWidth > el.clientWidth + 1;
    };
    const up = (el) => {
      while (el) {
        if (el === document.body || el === root) return null;
        if (scrolls(el)) return el;
        el = el.parentElement || (el.getRootNode && el.getRootNode().host) || null;
      }
      return null;
    };
    const focused = document.activeElement && document.activeElement !== document.body ? document.activeElement : null;
    const target = up(focused) || (scrolls(root) ? root : null)
      || up(document.elementFromPoint(innerWidth / 2, innerHeight / 2)) || root;
    const behavior = smooth ? 'smooth' : 'instant';
    const height = target === root ? innerHeight : target.clientHeight;
    const scroller = target === root ? window : target;
    if (to === 'top') scroller.scrollTo({ top: 0, behavior });
    else if (to === 'bottom') scroller.scrollTo({ top: target.scrollHeight, behavior });
    else scroller.scrollBy({ left: dx, top: half !== 0 ? half * height / 2 : dy, behavior });
    """#

    /// Escape in a box on the page: the box, or the one inside a frame of
    /// the same site, lets the caret go.
    static let blur = #"""
    (function () {
      let el = document.activeElement;
      while (el && el.tagName === 'IFRAME') {
        try { el = el.contentDocument && el.contentDocument.activeElement; } catch (e) { break; }
      }
      if (el && el.blur) el.blur();
      if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
    })(); void 0
    """#

    /// A tab with no web page (Settings, History and the rest): the
    /// scroll view under the middle of the page scrolls instead.
    private static func scrollNatively(_ browser: Browser, _ scroll: Scroll) {
        guard let window = browser.window, let content = window.contentView else { return }
        let middle = NSPoint(x: content.bounds.midX, y: content.bounds.midY)
        guard let hit = content.hitTest(middle) else { return }
        var view: NSView? = hit
        var found: NSScrollView?
        while let current = view {
            if let scroller = current as? NSScrollView ?? current.enclosingScrollView,
               let document = scroller.documentView, document.frame.height > scroller.contentSize.height + 1 {
                found = scroller
                break
            }
            view = current.superview
        }
        guard let scroller = found, let document = scroller.documentView else { return }
        let clip = scroller.contentView
        let visible = clip.bounds.height
        let top: CGFloat = document.isFlipped ? 0 : max(0, document.frame.height - visible)
        let bottom: CGFloat = document.isFlipped ? max(0, document.frame.height - visible) : 0
        let down: CGFloat = document.isFlipped ? 1 : -1
        var origin = clip.bounds.origin
        switch scroll {
        case .by(let dx, let dy): origin.x += dx; origin.y += dy * down
        case .half(let sign): origin.y += sign * visible / 2 * down
        case .top: origin.y = top
        case .bottom: origin.y = bottom
        }
        origin.y = min(max(origin.y, min(top, bottom)), max(top, bottom))
        origin.x = max(0, min(origin.x, max(0, document.frame.width - clip.bounds.width)))
        clip.scroll(to: origin)
        scroller.reflectScrolledClipView(clip)
    }
}

// MARK: - what shows

/// The mode in the page's corner while it isn't the usual one, and the
/// list of keys (?) over the page.
struct VimLayer: View {
    @ObservedObject var vim: VimKeys
    /// The tab in front, so the badge follows a tab change (i is per tab).
    let activeID: Tab.ID?

    var body: some View {
        ZStack {
            if vim.helping {
                VimHelp(map: vim.map) { vim.helping = false }
                    .transition(.opacity)
            }
            if let words = badge {
                Text(words)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: badge)
        .animation(.easeOut(duration: 0.12), value: vim.helping)
    }

    private var badge: String? {
        if vim.insertTab != nil, vim.insertTab == activeID { return "-- INSERT --" }
        if !vim.pending.isEmpty { return vim.pending }
        return nil
    }
}

/// Every key, by what it is for (?). Any key puts it away.
struct VimHelp: View {
    let map: [String: VimCommand]
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Vim keys").font(.headline)
                Spacer()
                Text("Esc to close").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 28) {
                ForEach(VimCommand.Group.allCases, id: \.self) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.rawValue).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(rows(group), id: \.command) { row in
                            HStack(spacing: 10) {
                                Text(row.keys)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .frame(minWidth: 44, alignment: .leading)
                                Text(row.command.title).font(.system(size: 12))
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: close)
    }

    private struct Row { let keys: String; let command: VimCommand }

    /// A command's keys together (K, gt), in the order Vimium lists them.
    private func rows(_ group: VimCommand.Group) -> [Row] {
        VimCommand.allCases.filter { $0.group == group }.compactMap { command in
            let keys = map.filter { $0.value == command }.keys.sorted { ($0.count, $0) < ($1.count, $1) }
            return keys.isEmpty ? nil : Row(keys: keys.joined(separator: " "), command: command)
        }
    }
}
