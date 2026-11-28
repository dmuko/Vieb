import SwiftUI

/// Everywhere you have been, and everything you have kept. Two lists in the
/// same white-and-hairline panel as the rest, and in both cases the point is
/// as much being able to remove a line as to read one.

enum When {
    private static let ago: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func said(_ date: Date) -> String {
        ago.localizedString(for: date, relativeTo: Date())
    }

    private static let hour: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let plain: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM"
        return formatter
    }()

    /// The time of day. Once a list is grouped by day, that is all a row needs.
    static func clock(_ date: Date) -> String { hour.string(from: date) }

    static func day(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return plain.string(from: date)
    }
}

struct HistoryPanel: View {
    @ObservedObject var browser: Browser
    /// The tab it is drawn in, for Vim's keys (Vim.swift).
    var tabID: UUID? = nil

    @FocusState private var hunting: Bool
    /// Its pages for Vim's keys to walk, when they are on.
    // Held, not watched: each row watches it (vimRow), so a key redraws
    // two rows rather than the whole page.
    @State private var vim = VimList()
    @State private var traces: [History.Trace] = []
    /// The list as drawn: each day's name, then its pages. Worked out when
    /// the history or the search changes, not each time the panel is drawn.
    @State private var lines: [Listed] = []
    /// Which history Clear takes: nil for every space's, as Safari's All
    /// Profiles; shown only when a signed-out space keeps one of its own.
    @State private var clearsIn: UUID?
    private var clearing: Bool { browser.recallMode == .clearing }

    var body: some View {
        Plate("History", width: 600, close: { browser.recalling = false }) {
            VStack(alignment: .leading, spacing: 14) {
                Hunt(text: $browser.recallHunt, prompt: "Search everywhere you have been", focus: $hunting)
                    // With Vim's keys: Return gives them back, at the first page found.
                    .onSubmit {
                        guard browser.prefs.vimKeys else { return }
                        hunting = false
                        vim.selected = vim.rows().first
                    }

                if traces.isEmpty {
                    Card { Nothing(browser.recallHunt.isEmpty ? "Nothing yet." : "Nothing matches.") }
                } else {
                    // Lazy: only the lines in view are made. Two thousand of
                    // them, each with its icon, took the panel a third of a
                    // second to open, and scrolling redrew them all.
                    ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(lines) { line in
                                switch line.kind {
                                case .day(let day):
                                    Caption(day)
                                        .padding(.top, line.id == lines.first?.id ? 0 : 14)
                                        .padding(.bottom, 6)
                                case .trace(let trace, let first, let last):
                                    VStack(spacing: 0) {
                                        if !first { Rule() }
                                        Row(
                                            trace: trace,
                                            go: {
                                                // In this tab, as Chrome's
                                                // history does: Back returns here.
                                                (browser.pageTab(.history) ?? browser.active)?.go(to: trace.url)
                                            },
                                            forget: {
                                                browser.history.forget(trace.key)
                                                refresh()
                                            }
                                        )
                                    }
                                    .vimRow(trace.id, in: vim)
                                    // A day's card, drawn a line at a time.
                                    .background(Palette.ground)
                                    .clipShape(Slice(first: first, last: last))
                                    // The card's outline, reaching a point past the lines it
                                    // shares with its neighbours and cut to its own: only
                                    // its sides, and its rounded top or bottom, remain.
                                    .overlay(
                                        Slice(first: first, last: last)
                                            .strokeBorder(Palette.hairline, lineWidth: 1)
                                            .padding(.top, first ? 0 : -1)
                                            .padding(.bottom, last ? 0 : -1)
                                            .clipped()
                                    )
                                }
                            }
                        }
                        .padding(.bottom, 2)
                    }
                    .listHeight(420)
                    .onReceive(vim.$selected) { id in
                        guard let id else { return }
                        withAnimation(Motion.quick) { reader.scrollTo(id) }
                    }
                    }
                }
            }
        } foot: {
            if clearing {
                sweeps
            } else {
                HStack {
                    Text(traces.count == 1 ? "1 page" : "\(traces.count) pages")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                    Spacer()
                    Pill("Clear…") { withAnimation(Motion.settle) { browser.recallMode = .clearing } }
                }
            }
        }
        .animation(Motion.settle, value: clearing)
        .onAppear {
            // With Vim's keys on, the keys are theirs; / finds.
            if !browser.prefs.vimKeys { hunting = true }
            refresh()
            walkable()
        }
        .onDisappear { vim.letGo() }
        .onChange(of: browser.recallHunt) { _, _ in refresh() }
        // Another space may keep a history of its own (Spaces.history).
        .onChange(of: browser.spaceID) { _, _ in refresh() }
    }

    /// The pages as Vim's keys walk them (Vim.swift): Return opens one here,
    /// O in a new tab, yy copies its address, dd forgets it.
    private func walkable() {
        vim.tab = tabID
        func trace(_ id: String) -> History.Trace? { traces.first { $0.id == id } }
        vim.rows = { clearing ? [] : traces.isEmpty ? [] : lines.compactMap { line in
            if case .trace(let trace, _, _) = line.kind { return trace.id }
            return nil
        } }
        vim.activate = { id in
            guard let trace = trace(id) else { return false }
            (browser.pageTab(.history) ?? browser.active)?.go(to: trace.url)
            return true
        }
        vim.openInNewTab = { id in
            guard let trace = trace(id) else { return }
            browser.open(trace.url, foreground: true, from: browser.active)
        }
        vim.address = { trace($0)?.url }
        vim.remove = { id in
            guard let trace = trace(id) else { return }
            // The next row picked in its place, as a list does.
            let rows = vim.rows()
            let next = rows.firstIndex(of: id).flatMap { rows.indices.contains($0 + 1) ? rows[$0 + 1] : rows.dropLast().last }
            browser.history.forget(trace.key)
            refresh()
            vim.selected = next
        }
        vim.find = { hunting = true }
        browser.vim.register(vim)
    }

    /// Three separate things, worded so nobody has to guess which one signs
    /// them out of their bank.
    private var sweeps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Card {
                Line("History", historyDetail) {
                    let scopes = browser.historyScopes
                    if !scopes.isEmpty {
                        Picker("", selection: $clearsIn) {
                            Text("All Spaces").tag(UUID?.none)
                            ForEach(scopes, id: \.space) { Text($0.name).tag(UUID?.some($0.space)) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    Pill("Clear") {
                        browser.clearHistory(in: scopes.contains { $0.space == clearsIn } ? clearsIn : nil)
                        clearsIn = nil
                        refresh()
                        withAnimation(Motion.settle) { browser.recallMode = .history }
                    }
                }
                Rule()
                Line("Cookies and sign-ins", "Signs you out of every site") {
                    Pill("Sign out of everything") { browser.clearSites() }
                }
                Rule()
                Line("Cache", "Only what was fetched to draw pages") {
                    Pill("Clear") { browser.clearCache() }
                }
            }
            HStack {
                Spacer()
                Pill("Back") { withAnimation(Motion.settle) { browser.recallMode = .history } }
            }
        }
        .transition(.opacity)
    }

    private var historyDetail: String {
        guard let clearsIn, let scope = browser.historyScopes.first(where: { $0.space == clearsIn }) else {
            return "Everywhere you have been"
        }
        return "Where you have been in \(scope.name)"
    }

    private func refresh() {
        traces = browser.history.everything(matching: browser.recallHunt)
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: traces) { calendar.startOfDay(for: $0.last) }
        var made: [Listed] = []
        for day in grouped.keys.sorted(by: >) {
            let rows = grouped[day]!.sorted { $0.last > $1.last }
            made.append(Listed(id: "day " + day.description, kind: .day(When.day(day))))
            for (index, trace) in rows.enumerated() {
                made.append(Listed(id: trace.id, kind: .trace(trace, first: index == 0, last: index == rows.count - 1)))
            }
        }
        lines = made
    }

    /// One line of the list: a day's name, or a page under it.
    struct Listed: Identifiable {
        enum Kind {
            case day(String)
            case trace(History.Trace, first: Bool, last: Bool)
        }
        let id: String
        let kind: Kind
    }

    /// A slice of a card: rounded at the top on its first line and at the
    /// bottom on its last, as the whole card would be.
    struct Slice: InsettableShape {
        let first: Bool
        let last: Bool
        var inset: CGFloat = 0

        func path(in rect: CGRect) -> Path {
            let radius: CGFloat = 11 - inset
            let top = first ? radius : 0, bottom = last ? radius : 0
            return UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom, bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)
                .path(in: rect.insetBy(dx: inset, dy: inset))
        }

        func inset(by amount: CGFloat) -> Slice {
            var copy = self
            copy.inset += amount
            return copy
        }
    }

    /// One line. A title, where it came from, and when — the three things you
    /// scan for, in the order you scan them.
    private struct Row: View {
        let trace: History.Trace
        let go: () -> Void
        let forget: () -> Void

        @State private var hovering = false

        var body: some View {
            HStack(spacing: 12) {
                Mark(icon: Favicons.shared.cached(for: trace.url),
                     letter: trace.address.first.map { String($0).uppercased() } ?? "•", size: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(trace.title.isEmpty ? Address.withoutWWW(trace.address) : trace.title)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(Address.withoutWWW(trace.address))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if hovering {
                    Quick("Remove", tint: .red.opacity(0.75), act: forget)
                } else {
                    Text(When.clock(trace.last))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(hovering ? Palette.hover : .clear)
            .contentShape(Rectangle())
            .onTapGesture(perform: go)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
        }
    }
}

struct DownloadsPanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var loot: Loot
    @ObservedObject var fetches: Fetches
    /// Under the downloads button or in the side panel (Settings ›
    /// Downloads › Open Downloads): the same list in a narrower place, with
    /// its own title line and cross instead of the plate's.
    let compact: Bool
    let close: (() -> Void)?
    /// The tab it is drawn in, for Vim's keys (Vim.swift); none under the
    /// button or in the side panel.
    let tabID: UUID?
    /// Its downloads for Vim's keys to walk, when they are on.
    // Held, not watched: each row watches it (vimRow), so a key redraws
    // two rows rather than the whole page.
    @State private var vim = VimList()

    init(browser: Browser, loot: Loot, compact: Bool = false, close: (() -> Void)? = nil, tabID: UUID? = nil) {
        self.browser = browser
        self.loot = loot
        self.fetches = browser.fetches
        self.compact = compact
        self.close = close
        self.tabID = tabID
    }

    var body: some View {
        Group { if compact { small } else { plate } }
            .onAppear { if tabID != nil { walkable() } }
            .onDisappear { vim.letGo() }
    }

    /// The downloads as Vim's keys walk them (Vim.swift). One under way:
    /// Return pauses, resumes or tries it again, dd stops it. One done:
    /// Return opens the file, O shows it in the Finder, yy copies where it
    /// came from, dd takes it off the list (the file stays).
    private func walkable() {
        vim.tab = tabID
        vim.rows = { fetches.entries.map { "fetch:\($0.id)" } + loot.kept.map { "kept:" + $0.id } }
        func entry(_ id: String) -> FetchEntry? { fetches.entries.first { "fetch:\($0.id)" == id } }
        func keep(_ id: String) -> Keep? { loot.kept.first { "kept:" + $0.id == id } }
        vim.activate = { id in
            if let keep = keep(id) {
                if keep.stillThere { loot.open(keep) }
                return true
            }
            guard let entry = entry(id) else { return false }
            switch entry.state {
            case .paused: browser.resumeDownload(entry)
            case .failed: browser.retryDownload(entry)
            default: browser.pauseDownload(entry)
            }
            return true
        }
        vim.openInNewTab = { id in if let keep = keep(id) { loot.reveal(keep) } }
        vim.address = { id in keep(id)?.address.flatMap(URL.init(string:)) }
        vim.remove = { id in
            let rows = vim.rows()
            let next = rows.firstIndex(of: id).flatMap { rows.indices.contains($0 + 1) ? rows[$0 + 1] : rows.dropLast().last }
            if let keep = keep(id) { loot.forget(keep) } else if let entry = entry(id) { browser.cancelDownload(entry) }
            vim.selected = next
        }
        browser.vim.register(vim)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Downloads")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                Door(icon: "folder", help: "Open the Downloads Folder") {
                    NSWorkspace.shared.open(browser.downloadsFolder)
                }
                if let close { Door(icon: "xmark", help: "Close", act: close) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Rectangle().fill(Palette.hairline).frame(height: 1)
            list
                .padding(12)
            if !loot.kept.isEmpty {
                Spacer(minLength: 0)
                Rectangle().fill(Palette.hairline).frame(height: 1)
                HStack {
                    Spacer()
                    Pill("Clear list") { loot.forgetAll() }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var plate: some View {
        Plate("Downloads", width: 560, close: close ?? { browser.hoarding = false }) {
            list
        } foot: {
            HStack {
                Text(loot.kept.isEmpty ? "Files land in \(browser.downloadsFolder.lastPathComponent)"
                     : "Clearing the list leaves the files where they are")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                Spacer()
                if !loot.kept.isEmpty {
                    Pill("Clear list") { loot.forgetAll() }
                }
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if fetches.entries.isEmpty && loot.kept.isEmpty {
            Card { Nothing("Nothing downloaded yet.") }
        } else {
            ScrollViewReader { reader in
            FadingScroll {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if !fetches.entries.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Caption("Current downloads")
                            Card {
                                ForEach(Array(fetches.entries.enumerated()), id: \.element.id) { index, entry in
                                    if index > 0 { Rule() }
                                    FetchRow(
                                        entry: entry,
                                        pause: { browser.pauseDownload(entry) },
                                        resume: { browser.resumeDownload(entry) },
                                        retry: { browser.retryDownload(entry) },
                                        cancel: { browser.cancelDownload(entry) }
                                    )
                                    .vimRow("fetch:\(entry.id)", in: vim)
                                    .id("fetch:\(entry.id)")
                                }
                            }
                        }
                    }

                    if !loot.kept.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Caption("Completed")
                            Card {
                                ForEach(Array(loot.kept.enumerated()), id: \.element.id) { index, keep in
                                    if index > 0 { Rule() }
                                    KeptRow(
                                        keep: keep,
                                        open: { loot.open(keep) },
                                        reveal: { loot.reveal(keep) },
                                        forget: { loot.forget(keep) }
                                    )
                                    .vimRow("kept:" + keep.id, in: vim)
                                    .id("kept:" + keep.id)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 2)
            }
            // Hairlines from edge to edge, as Settings' are: the cards hold
            // icons, not text, at the inset a rule would start from.
            .environment(\.ruleInset, 0)
            .listHeight(420)
            .onReceive(vim.$selected) { id in
                guard let id else { return }
                withAnimation(Motion.quick) { reader.scrollTo(id) }
            }
            }
        }
    }

    /// The list's scroll, fading out at its foot while more lies below
    /// rather than cutting a line in half; less as the end comes up, and
    /// not at all once it is in view. Its head does the same once scrolled,
    /// so a caption going under the title line isn't sliced across. A mask,
    /// so it is the same in light and dark and over whatever the list is
    /// drawn on.
    private struct FadingScroll<Content: View>: View {
        @ViewBuilder let content: () -> Content
        /// Where the list ends, and how tall the scroll is: the end lies
        /// below the foot by the difference.
        @State private var end: CGFloat = 0
        /// Where the list starts: above the scroll's top by as much as it
        /// has been scrolled.
        @State private var start: CGFloat = 0
        @State private var height: CGFloat = 0
        private let fade: CGFloat = 24
        private static var space: String { "downloads.list" }

        var body: some View {
            ScrollView {
                content()
                    // Read where it is rather than sent up as a preference:
                    // one from inside the scroll never came out of it here.
                    .background(GeometryReader { list in
                        let frame = list.frame(in: .named(Self.space))
                        Color.clear
                            .onAppear { end = frame.maxY; start = frame.minY }
                            .onChange(of: frame.maxY) { _, new in end = new }
                            .onChange(of: frame.minY) { _, new in start = new }
                    })
            }
            .coordinateSpace(name: Self.space)
            // Measured beside the scroll, not around it, so it sizes itself
            // as it always has.
            .background(GeometryReader { view in
                Color.clear
                    .onAppear { height = view.size.height }
                    .onChange(of: view.size.height) { _, new in height = new }
            })
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(1 - min(1, max(0, -start) / fade)), .black],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: fade)
                    Rectangle()
                    LinearGradient(colors: [.black, .black.opacity(1 - min(1, max(0, end - height) / fade))],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: fade)
                }
            }
        }
    }

    private struct FetchRow: View {
        @ObservedObject var entry: FetchEntry
        let pause: () -> Void
        let resume: () -> Void
        let retry: () -> Void
        let cancel: () -> Void

        private var received: String {
            ByteCountFormatter.string(fromByteCount: entry.completedBytes, countStyle: .file)
        }

        private var bytes: String {
            guard entry.totalBytes > 0 else { return received + " downloaded" }
            let total = ByteCountFormatter.string(fromByteCount: entry.totalBytes, countStyle: .file)
            return "\(received) of \(total)"
        }

        private var stateLabel: String {
            switch entry.state {
            case .downloading: return entry.stalled ? "Stalled" : "Downloading"
            case .pausing: return entry.stopping
            case .paused: return "Paused"
            case .resuming: return "Resuming…"
            case .failed: return "Failed"
            }
        }

        private func status(_ text: String) -> some View {
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.muted)
                .monospacedDigit()
                .lineLimit(1)
        }

        private var icon: String {
            switch entry.state {
            case .downloading, .pausing, .resuming: return "arrow.down.circle"
            case .paused: return "pause.circle"
            case .failed: return "exclamationmark.circle"
            }
        }

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 18)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 7) {
                        if let fraction = entry.fraction {
                            // Grey, as the ring in the chrome is.
                            Capsule()
                                .fill(Palette.hairline)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(Palette.ink.opacity(0.6))
                                        .frame(width: 68 * min(1, max(0, fraction)))
                                }
                                .frame(width: 68, height: 3)
                        }
                        // A row with three buttons has little room left: say
                        // less rather than cut the amount out of the middle.
                        ViewThatFits(in: .horizontal) {
                            status("\(stateLabel) · \(bytes)")
                            status("\(stateLabel) · \(received)")
                            status(stateLabel)
                        }
                    }
                    if case .failed = entry.state {
                        Text(entry.errorDescription ?? "The download failed.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    // Beside the text, the buttons left it a few letters
                    // wide; under it, the name and status read whole.
                    controls
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .contextMenu { if let address = entry.address { CopyAddress(address: address) } }
        }

        @ViewBuilder
        private var controls: some View {
            switch entry.state {
            case .downloading:
                HStack(spacing: 4) {
                    if entry.canPause { Quick("Pause", act: pause) }
                    Quick("Cancel", act: cancel)
                }
            case .pausing:
                HStack(spacing: 4) {
                    Quick(entry.stopping, act: {})
                        .disabled(true)
                    Quick("Cancel", act: cancel)
                }
            case .paused:
                HStack(spacing: 4) {
                    if entry.canResume {
                        Quick("Resume", act: resume)
                    } else if entry.canRetry {
                        Quick("Retry", act: retry)
                            .help("Start the download again from the beginning")
                    }
                    Quick("Remove", act: cancel)
                }
            case .resuming:
                HStack(spacing: 4) {
                    Quick("Resuming…", act: {})
                        .disabled(true)
                    Quick("Cancel", act: cancel)
                }
            case .failed:
                HStack(spacing: 4) {
                    if entry.canResume { Quick("Resume", act: resume) }
                    if entry.canRetry {
                        Quick("Retry", act: retry)
                            .help("Start the download again from the beginning")
                    }
                    Quick("Remove", act: cancel)
                }
            }
        }
    }

    private struct KeptRow: View {
        let keep: Keep
        let open: () -> Void
        let reveal: () -> Void
        let forget: () -> Void

        @State private var hovering = false

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: keep.stillThere ? "doc" : "doc.badge.ellipsis")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(keep.stillThere ? Palette.muted : Palette.faint)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(keep.name)
                        .font(.system(size: 13))
                        .foregroundStyle(keep.stillThere ? Palette.ink : Palette.faint)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(keep.from.isEmpty ? When.said(keep.date) : "\(keep.from) · \(When.said(keep.date))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if hovering {
                    if keep.stillThere { Quick("Show in Finder", act: reveal) }
                    Quick("Remove", tint: .red.opacity(0.75), act: forget)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(hovering ? Palette.hover : .clear)
            .contentShape(Rectangle())
            .contextMenu { if let address = keep.address { CopyAddress(address: address) } }
            .modifier(DragOut(keep: keep))
            .onTapGesture { if keep.stillThere { open() } }
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
        }
    }

    /// A finished download dragged out of the list as its file, onto a page
    /// or into another app, with the file's own icon under the pointer. A
    /// row whose file has gone has nothing to drag. The drag starts only
    /// once the pointer moves, so a click still opens the file.
    private struct DragOut: ViewModifier {
        let keep: Keep

        func body(content: Content) -> some View {
            if keep.stillThere {
                content.onDrag {
                    keep.dragged ?? NSItemProvider()
                } preview: {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: keep.path))
                        .resizable()
                        .frame(width: 32, height: 32)
                }
            } else {
                content
            }
        }
    }

    /// A row's right-click, for handing the download to another app.
    private struct CopyAddress: View {
        let address: String

        var body: some View {
            Button("Copy Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(address, forType: .string)
            }
        }
    }
}
