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
    case linkHints = "LinkHints.activateMode"
    case linkHintsNewTab = "LinkHints.activateModeToOpenInNewTab"
    case focusInput

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
        "f": .linkHints, "F": .linkHintsNewTab, "gi": .focusInput,
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
        case .linkHints: "Click a link or button"
        case .linkHintsNewTab: "Open a link in a new tab"
        case .focusInput: "Type in the first field"
        }
    }

    enum Group: String, CaseIterable {
        case page = "Page", links = "Links", tabs = "Tabs", find = "Find", other = "Other"
    }

    var group: Group {
        switch self {
        case .scrollDown, .scrollUp, .scrollLeft, .scrollRight, .scrollPageDown, .scrollPageUp,
             .scrollToTop, .scrollToBottom, .goBack, .goForward, .reload, .copyCurrentUrl: .page
        case .nextTab, .previousTab, .firstTab, .lastTab, .removeTab, .restoreTab, .createTab, .duplicateTab: .tabs
        case .enterFindMode, .performFind, .performBackwardsFind: .find
        case .linkHints, .linkHintsNewTab, .focusInput: .links
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
    /// Hints are up on a page (f, F): the letters picking one.
    @Published private(set) var hinting: Hinting?

    struct Hinting: Equatable {
        /// The tab whose page has them: another tab in front ends them.
        let tab: Tab.ID?
        weak var page: PageView?
        /// F: the link opens in a tab behind this one.
        let newTab: Bool
        let alphabet: String
        var typed = ""
        /// Drawn on the page: until then letters wait in `typed`.
        var shown = false

        static func == (a: Hinting, b: Hinting) -> Bool {
            a.tab == b.tab && a.page === b.page && a.newTab == b.newTab && a.typed == b.typed && a.shown == b.shown
        }
    }

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
        if let hints = hinting {
            if let taken = hint(event, name: name, hints, in: browser) { return taken }
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
        case .linkHints: showHints(in: browser, newTab: false)
        case .linkHintsNewTab: showHints(in: browser, newTab: true)
        case .focusInput: VimPage.page(browser)?.evaluateInSearch(VimPage.focusInput)
        }
    }

    // MARK: hints

    /// The letters hints are made of (Settings › Vim keys), as typed there
    /// if they make sense: two or more, none twice; else Vimium's.
    static func alphabet(_ typed: String) -> String {
        var seen = Set<Character>()
        let letters = typed.lowercased().filter { ($0.isLetter || $0.isNumber) && seen.insert($0).inserted }
        return letters.count >= 2 ? letters : Preferences.vimHintDefault
    }

    /// Vimium's hints for so many links: as short as they can be, none the
    /// start of another, the first letters of the alphabet the most used.
    static func labels(_ count: Int, alphabet: String) -> [String] {
        let letters = Array(alphabet)
        guard count > 0, letters.count >= 2 else { return [] }
        var hints = [""]
        var offset = 0
        while hints.count - offset < count || hints.count == 1 {
            let hint = hints[offset]
            offset += 1
            for letter in letters { hints.append(String(letter) + hint) }
        }
        return hints[offset..<(offset + count)].sorted().map { String($0.reversed()) }
    }

    private func showHints(in browser: Browser, newTab: Bool) {
        guard let page = VimPage.page(browser) else { return }
        let alphabet = VimKeys.alphabet(browser.prefs.vimHintCharacters)
        let hints = Hinting(tab: browser.activeID, page: page, newTab: newTab, alphabet: alphabet)
        hinting = hints
        page.callInSearch(VimPage.collectHints, arguments: [:]) { [weak self, weak page] count in
            guard let self, let page, self.hinting?.page === page else { return }
            let labels = VimKeys.labels((count as? Int) ?? 0, alphabet: alphabet)
            guard !labels.isEmpty else {
                self.hinting = nil
                return
            }
            page.callInSearch(VimPage.drawHints, arguments: ["labels": labels]) { [weak self] _ in
                guard let self, self.hinting?.page === page else { return }
                self.hinting?.shown = true
                // Letters typed while they were being drawn.
                if let typed = self.hinting?.typed, !typed.isEmpty { self.filter(typed, in: browser) }
            }
        }
    }

    /// A key while hints are up. Nil when hints are over and the key is
    /// to be read as any other.
    private func hint(_ event: NSEvent, name: String?, _ hints: Hinting, in browser: Browser) -> Bool? {
        guard hints.page != nil, hints.tab == browser.activeID else {
            endHints()
            return nil
        }
        if event.modifierFlags.contains(.command) {
            endHints()
            return false
        }
        if name == "<esc>" {
            endHints()
            return true
        }
        if event.keyCode == 51 {  // ⌫: the last letter taken back
            guard !hints.typed.isEmpty else { return true }
            hinting?.typed.removeLast()
            if hints.shown { filter(hinting?.typed ?? "", in: browser) }
            return true
        }
        guard let letter = name?.lowercased(), letter.count == 1, hints.alphabet.contains(letter) else {
            return true  // anything else does nothing while they are up
        }
        hinting?.typed += letter
        if hints.shown { filter(hinting?.typed ?? "", in: browser) }
        return true
    }

    private func filter(_ typed: String, in browser: Browser) {
        guard let page = hinting?.page else { return }
        page.callInSearch(VimPage.filterHints, arguments: ["typed": typed]) { [weak self, weak page] answer in
            guard let self, let page, let hints = self.hinting, hints.page === page else { return }
            let answer = answer as? [String: Any] ?? [:]
            switch answer["state"] as? String {
            case "hit":
                self.hinting = nil
                self.follow(answer, on: page, newTab: hints.newTab, in: browser)
            case "none":
                // A letter no hint goes on with: not taken.
                if hints.typed == typed { self.hinting?.typed.removeLast() }
            case "more":
                break
            default:
                // Scrolled or gone with the page: nothing to pick from.
                self.hinting = nil
            }
        }
    }

    /// The hint picked: a click where it is, as the hand's would be; with
    /// F, its link in a tab behind this one, or a ⌘-click if it has none.
    private func follow(_ hit: [String: Any], on page: PageView, newTab: Bool, in browser: Browser) {
        guard let x = hit["x"] as? Double, let y = hit["y"] as? Double else { return }
        if newTab, let href = hit["href"] as? String, let url = URL(string: href),
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            let source = browser.tabs.first { $0.built === page }
            browser.open(url, foreground: false, from: source)
            return
        }
        PageHands.click(page, at: [x, y], held: newTab ? .command : [])
    }

    private func endHints() {
        guard let hints = hinting else { return }
        hinting = nil
        hints.page?.evaluateInSearch(VimPage.removeHints)
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

    /// Everything on the page a hint can go on, in sight and not under
    /// something else, in the page, its open shadow roots and its frames of
    /// the same site; kept in Search's world for drawHints. Answers how many.
    static let collectHints = #"""
    const old = globalThis.__vimHints;
    if (old) { old.end(); }
    const SEL = 'a[href],area[href],button:not([disabled]),input:not([type=hidden]):not([disabled]),' +
      'select:not([disabled]),textarea:not([disabled]),summary,[contenteditable]:not([contenteditable=false]),' +
      '[role=button],[role=link],[role=checkbox],[role=radio],[role=switch],[role=tab],[role=menuitem],' +
      '[role=menuitemcheckbox],[role=menuitemradio],[role=option],[role=treeitem],[role=combobox],' +
      '[onclick],[tabindex]:not([tabindex="-1"]),label[for]';
    const W = innerWidth, H = innerHeight;
    const found = [];
    const seen = new Set();
    const shown = (el) => {
      if (el.checkVisibility && !el.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true })) return false;
      return !el.closest('[aria-hidden=true],[inert]');
    };
    // The first box of it in sight (a link that wraps has several), and a
    // point in it nothing else covers.
    const spot = (el, dx, dy, root) => {
      for (const r of el.getClientRects()) {
        const left = Math.max(r.left + dx, 0), top = Math.max(r.top + dy, 0);
        const right = Math.min(r.right + dx, W), bottom = Math.min(r.bottom + dy, H);
        if (right - left < 3 || bottom - top < 3) continue;
        const points = [[(left + right) / 2, (top + bottom) / 2], [left + 2, top + 2], [right - 2, bottom - 2]];
        for (const [x, y] of points) {
          const hit = (root.elementFromPoint ? root : document).elementFromPoint(x - dx, y - dy);
          if (!hit || hit === el || el.contains(hit) || hit.contains(el) && hit.tagName !== 'BODY' && hit.tagName !== 'HTML') {
            return { left, top, x, y };
          }
        }
      }
      return null;
    };
    const walk = (root, dx, dy) => {
      for (const el of root.querySelectorAll(SEL)) {
        if (seen.has(el)) continue;
        seen.add(el);
        // A button inside a link (or a link's own icon) is the link's.
        const outer = el.parentElement && el.parentElement.closest('a[href],button');
        if (outer && seen.has(outer)) continue;
        if (!shown(el)) continue;
        const at = spot(el, dx, dy, root);
        if (!at) continue;
        const href = el.href && typeof el.href === 'string' ? el.href : (el.href && el.href.baseVal) || null;
        found.push({ el, href, ...at });
      }
      for (const host of root.querySelectorAll('*')) {
        if (host.shadowRoot) walk(host.shadowRoot, dx, dy);
      }
      for (const frame of root.querySelectorAll('iframe,frame')) {
        let inner = null;
        try { inner = frame.contentDocument; } catch (e) { inner = null; }
        if (!inner || !inner.documentElement) continue;
        const r = frame.getBoundingClientRect();
        if (r.bottom + dy < 0 || r.top + dy > H || r.right + dx < 0 || r.left + dx > W) continue;
        walk(inner, dx + r.left + frame.clientLeft, dy + r.top + frame.clientTop);
      }
    };
    walk(document, 0, 0);
    const state = { items: found.map((f) => ({ ...f })), host: null };
    state.end = () => {
      if (state.host) state.host.remove();
      removeEventListener('scroll', state.end, true);
      removeEventListener('resize', state.end, true);
      if (globalThis.__vimHints === state) globalThis.__vimHints = null;
    };
    globalThis.__vimHints = state;
    return found.length;
    """#

    /// The hints drawn over what they go on, in a closed root of their own
    /// the page can't style or see into. Scrolling takes them away, as the
    /// things under them have moved.
    static let drawHints = #"""
    const state = globalThis.__vimHints;
    if (!state) return false;
    const host = document.createElement('search-vim-hints');
    host.style.cssText = 'all:initial;position:fixed;inset:0;z-index:2147483647;pointer-events:none;';
    const shadow = host.attachShadow({ mode: 'closed' });
    const style = document.createElement('style');
    style.textContent = `
      .h { position: fixed; padding: 1px 4px; border-radius: 4px; font: 700 11px/14px ui-monospace, Menlo, monospace;
           letter-spacing: .02em; text-transform: uppercase; color: #2b2200; background: #ffd84d;
           border: 1px solid #c9a400; box-shadow: 0 1px 3px rgba(0,0,0,.3); white-space: nowrap; }
      .h b { font-weight: 700; color: #9a8100; }
      .h.gone { display: none; }`;
    shadow.appendChild(style);
    state.items.forEach((item, i) => {
      const node = document.createElement('div');
      node.className = 'h';
      node.style.left = Math.max(0, Math.min(item.left, innerWidth - 24)) + 'px';
      node.style.top = Math.max(0, Math.min(item.top, innerHeight - 16)) + 'px';
      node.textContent = labels[i];
      item.label = labels[i];
      item.node = node;
      shadow.appendChild(node);
    });
    (document.documentElement || document.body).appendChild(host);
    state.host = host;
    addEventListener('scroll', state.end, true);
    addEventListener('resize', state.end, true);
    return true;
    """#

    /// The hints that still go on with what is typed. "hit" with where to
    /// click when one is left; "none" when no hint goes on with it.
    static let filterHints = #"""
    const state = globalThis.__vimHints;
    if (!state || !state.host) return { state: 'gone' };
    const left = state.items.filter((item) => item.label.startsWith(typed));
    if (left.length === 0) return { state: 'none' };
    const hit = left.length === 1 && left[0].label === typed ? left[0] : null;
    if (hit) {
      state.end();
      return { state: 'hit', x: hit.x, y: hit.y, href: hit.href };
    }
    for (const item of state.items) {
      const on = item.label.startsWith(typed);
      item.node.classList.toggle('gone', !on);
      if (on) {
        item.node.textContent = '';
        const done = document.createElement('b');
        done.textContent = typed;
        item.node.append(done, item.label.slice(typed.length));
      }
    }
    return { state: 'more' };
    """#

    static let removeHints = "globalThis.__vimHints && globalThis.__vimHints.end(); void 0"

    /// gi: the first field in sight to type in, the caret at its end.
    static let focusInput = #"""
    (function () {
      const fields = document.querySelectorAll('input:not([type=hidden]):not([disabled]):not([readonly]),' +
        'textarea:not([disabled]):not([readonly]),[contenteditable]:not([contenteditable=false])');
      const text = /^(text|search|email|url|tel|password|number|)$/i;
      for (const el of fields) {
        if (el.tagName === 'INPUT' && !text.test(el.getAttribute('type') || '')) continue;
        const r = el.getBoundingClientRect();
        if (r.width < 2 || r.height < 2 || r.bottom < 0 || r.top > innerHeight) continue;
        if (el.checkVisibility && !el.checkVisibility({ checkVisibilityCSS: true })) continue;
        el.focus();
        if (typeof el.setSelectionRange === 'function' && typeof el.value === 'string') {
          try { el.setSelectionRange(el.value.length, el.value.length); } catch (e) {}
        }
        return true;
      }
      return false;
    })()
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
        if let hints = vim.hinting { return hints.typed.isEmpty ? "-- HINT --" : "-- HINT -- \(hints.typed.uppercased())" }
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

/// Settings › Vim keys › Hint letters: a short box, monospaced, which goes
/// back to Vimium's letters when emptied.
struct VimHintField: View {
    @Binding var text: String

    var body: some View {
        TextField("", text: $text, prompt: Text(Preferences.vimHintDefault))
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Palette.ink)
            .frame(width: 150)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Palette.wash, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .onSubmit { if text.isEmpty { text = Preferences.vimHintDefault } }
    }
}
