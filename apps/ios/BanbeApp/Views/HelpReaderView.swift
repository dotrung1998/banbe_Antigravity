import SwiftUI

/// Port of src/screens/HelpReader.jsx — the shared reader for Help & Legal's
/// Guides and Q&A: clickable table of contents, jump-to-top/bottom buttons,
/// and a diacritic-insensitive search that filters sections and highlights
/// matches. Content is `HelpContent` (generated from the web's
/// src/data/help/*.js by scripts/gen-help-content-ios.mjs).
struct HelpReaderView: View {
    @EnvironmentObject var app: AppState
    let doc: HelpDoc
    let idPrefix: String
    let onBack: () -> Void

    /// "Account" for the admin guide (opened from the Admin tab), else Help & Legal.
    private var backLabel: String { doc.adminOnly ? app.T("Tài khoản", "Account") : app.accountGroupTitle(for: "helpLegal") }

    @State private var query = ""
    @State private var tocOpen = true

    private var isEN: Bool { app.lang == "en" }
    private func pick(_ vi: String, _ en: String) -> String { isEN ? en : vi }

    /// Lowercase, strip accents, đ -> d; one output Character per input
    /// Character so match positions map straight back onto the original.
    private static func foldChar(_ c: Character) -> String {
        String(c).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "d")
    }
    private static func fold(_ s: String) -> String { s.map { foldChar($0) }.joined() }

    private var tokens: [String] {
        Self.fold(query).split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
    }

    private func blockText(_ b: HelpBlock) -> String {
        switch b {
        case .p(let vi, let en), .h(let vi, let en), .tip(let vi, let en): return pick(vi, en)
        case .ul(let items), .ol(let items): return items.map { pick($0[0], $0[1]) }.joined(separator: " ")
        case .q(let qv, let qe, let av, let ae): return pick(qv, qe) + " " + pick(av, ae)
        }
    }

    private var visible: [HelpSection] {
        let t = tokens
        if t.isEmpty { return doc.sections }
        return doc.sections.filter { sec in
            let hay = Self.fold(([pick(sec.vi, sec.en)] + sec.blocks.map(blockText)).joined(separator: " "))
            return t.allSatisfy { hay.contains($0) }
        }
    }

    /// `text` with every token occurrence highlighted.
    private func highlighted(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        let t = tokens
        guard !t.isEmpty else { return attr }
        let chars = Array(text)
        var folded = ""
        var map: [Int] = []
        for (i, c) in chars.enumerated() { for u in Self.foldChar(c) { folded.append(u); map.append(i) } }
        let fchars = Array(folded)
        var mask = [Bool](repeating: false, count: chars.count)
        for tok in t {
            let tc = Array(tok)
            guard !tc.isEmpty, fchars.count >= tc.count else { continue }
            var i = 0
            while i <= fchars.count - tc.count {
                if Array(fchars[i..<(i + tc.count)]) == tc {
                    for k in map[i]...map[i + tc.count - 1] { mask[k] = true }
                    i += tc.count
                } else { i += 1 }
            }
        }
        var idx = attr.startIndex
        for (i, _) in chars.enumerated() {
            let next = attr.index(afterCharacter: idx)
            if mask[i] { attr[idx..<next].backgroundColor = Color(red: 0.84, green: 0.67, blue: 0.24).opacity(0.4) }
            idx = next
        }
        return attr
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScreenScaffold {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 1).id("helpTop")
                    BackLink(label: backLabel, action: onBack)
                        .accessibilityIdentifier("\(idPrefix).back")
                    Text(pick(doc.vi, doc.en)).font(BanbeTheme.display(26)).padding(.top, 14)
                    Text(pick(doc.introVi, doc.introEn)).font(.system(size: 13)).opacity(0.75).padding(.top, 8)

                    TextField(app.T("Tìm trong tài liệu…", "Search this page…"), text: $query)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.system(size: 14))
                        .padding(14)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.top, 16)
                        .accessibilityIdentifier("\(idPrefix).search")
                    if !tokens.isEmpty {
                        Text(visible.isEmpty ? app.T("Không có kết quả. Thử từ khóa khác.", "No results. Try different words.")
                             : app.T("\(visible.count) mục khớp", "\(visible.count) matching section\(visible.count == 1 ? "" : "s")"))
                            .font(.system(size: 12)).opacity(0.65).padding(.top, 8)
                            .accessibilityIdentifier("\(idPrefix).resultCount")
                    }

                    if !visible.isEmpty { toc(proxy) }

                    ForEach(Array(visible.enumerated()), id: \.element.id) { n, sec in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(highlighted((tokens.isEmpty ? "\(n + 1). " : "") + pick(sec.vi, sec.en)))
                                .font(.system(size: 17, weight: .semibold))
                            ForEach(Array(sec.blocks.enumerated()), id: \.offset) { _, b in blockView(b) }
                        }
                        .padding(.top, 26)
                        .id("sec-\(sec.id)")
                    }
                    Color.clear.frame(height: 1).id("helpBottom")
                }
                .foregroundStyle(app.palette.ink)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .overlay(alignment: .bottomTrailing) {
                VStack(spacing: 8) {
                    floatButton("arrow.up", label: app.T("Lên đầu trang", "Jump to top"), id: "\(idPrefix).toTop") {
                        withAnimation { proxy.scrollTo("helpTop", anchor: .top) }
                    }
                    floatButton("arrow.down", label: app.T("Xuống cuối trang", "Jump to bottom"), id: "\(idPrefix).toBottom") {
                        withAnimation { proxy.scrollTo("helpBottom", anchor: .bottom) }
                    }
                }
                .padding(.trailing, 16).padding(.bottom, 96)
            }
        }
    }

    private func floatButton(_ icon: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(app.palette.paper)
                .frame(width: 40, height: 40)
                .background(app.palette.ink, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func toc(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { tocOpen.toggle() } label: {
                HStack {
                    Text(app.T("Mục lục", "Contents")).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(tocOpen ? "▾" : "▸")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(idPrefix).tocToggle")
            if tocOpen {
                ForEach(Array(visible.enumerated()), id: \.element.id) { n, sec in
                    Button { withAnimation { proxy.scrollTo("sec-\(sec.id)", anchor: .top) } } label: {
                        Text("\(n + 1). \(pick(sec.vi, sec.en))")
                            .font(.system(size: 13.5)).underline()
                            .multilineTextAlignment(.leading)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(idPrefix).toc.\(sec.id)")
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 16)
    }

    @ViewBuilder
    private func blockView(_ b: HelpBlock) -> some View {
        switch b {
        case .p(let vi, let en):
            Text(highlighted(pick(vi, en))).font(.system(size: 13.5)).lineSpacing(4).padding(.top, 8)
        case .h(let vi, let en):
            Text(highlighted(pick(vi, en))).font(.system(size: 13.5, weight: .semibold)).padding(.top, 16)
        case .tip(let vi, let en):
            Text(highlighted("💡 " + pick(vi, en)))
                .font(.system(size: 13)).lineSpacing(3)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 10)
        case .ul(let items):
            list(items, ordered: false)
        case .ol(let items):
            list(items, ordered: true)
        case .q(let qv, let qe, let av, let ae):
            VStack(alignment: .leading, spacing: 4) {
                Text(highlighted(pick(qv, qe))).font(.system(size: 14, weight: .semibold))
                Text(highlighted(pick(av, ae))).font(.system(size: 13.5)).lineSpacing(3).opacity(0.88)
                Divider().overlay(app.palette.rule).padding(.top, 8)
            }
            .padding(.top, 12)
        }
    }

    private func list(_ items: [[String]], ordered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ordered ? "\(i + 1)." : "•").font(.system(size: 13.5)).frame(width: 18, alignment: .trailing)
                    Text(highlighted(pick(it[0], it[1]))).font(.system(size: 13.5)).lineSpacing(3)
                }
            }
        }
        .padding(.top, 8)
    }
}

/// Help & Legal > Guides (personal | host | admin). The admin guide is only
/// for admin accounts; anyone else is sent back to Help & Legal.
struct HelpGuideView: View {
    @EnvironmentObject var app: AppState
    private var doc: HelpDoc? {
        guard let d = HelpContent.guide(app.helpGuideKey), !d.adminOnly || app.isAdmin else { return nil }
        return d
    }
    var body: some View {
        Group {
            if let doc {
                HelpReaderView(doc: doc, idPrefix: "help.guide.\(app.helpGuideKey)") { app.goBack() }
            } else {
                Color.clear.onAppear { app.accountGroupKey = "helpLegal"; app.screen = .accountGroup }
            }
        }
    }
}

/// Help & Legal > Q&A.
struct HelpFaqView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        HelpReaderView(doc: HelpContent.faq, idPrefix: "help.faq") { app.goBack() }
    }
}
