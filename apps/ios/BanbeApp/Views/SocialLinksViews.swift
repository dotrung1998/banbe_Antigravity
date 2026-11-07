import SwiftUI

// Organizer Team pass (2026-09-27, Stage 3) — shared between personal and
// organizer profile screens (edit + public display alike).

let socialLinkPlatforms: [(key: String, label: String)] = [
    ("website", "Website"), ("instagram", "Instagram"), ("facebook", "Facebook"),
    ("tiktok", "TikTok"), ("youtube", "YouTube"), ("twitter", "Twitter/X"),
]

private let socialLinkPlatformLabels: [String: String] = Dictionary(uniqueKeysWithValues: socialLinkPlatforms.map { ($0.key, $0.label) })

/// A concise preview of the separate long-form intro with "Đọc thêm" —
/// renders nothing when there's no long intro to show.
struct LongIntroPreview: View {
    @EnvironmentObject private var app: AppState
    let text: String?
    @State private var expanded = false
    private let previewLength = 160

    var body: some View {
        if let text, !text.isEmpty {
            let isLong = text.count > previewLength
            let shown = expanded || !isLong ? text : String(text.prefix(previewLength)) + "…"
            VStack(alignment: .leading, spacing: 4) {
                Text(shown).font(.system(size: 12.5)).multilineTextAlignment(.leading)
                if isLong {
                    Button(expanded ? app.T("Thu gọn", "Show less") : app.T("Đọc thêm", "Read more")) {
                        expanded.toggle()
                    }
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(app.palette.ink.opacity(0.7))
                    .accessibilityIdentifier("longIntro.toggle")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("longIntro.preview")
        }
    }
}

/// Icons/buttons ONLY for saved public links — never a placeholder for a
/// platform the profile didn't add.
struct SocialLinksRow: View {
    @EnvironmentObject private var app: AppState
    let links: [SocialLink]?

    var body: some View {
        if let links, !links.isEmpty {
            HStack(spacing: 8) {
                ForEach(links) { link in
                    if let url = URL(string: link.url) {
                        Link(destination: url) {
                            Text(socialLinkPlatformLabels[link.platform] ?? link.platform)
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .overlay(Capsule().stroke(app.palette.rule))
                                .foregroundStyle(app.palette.ink)
                        }
                        .accessibilityIdentifier("socialLink.\(link.platform)")
                    }
                }
            }
        }
    }
}

/// One obvious "Thêm liên kết" control; only on tap does it reveal
/// platform choice + URL field per link. Server-side validation
/// (sanitize_social_links, migration 102) is the real boundary.
struct SocialLinksEditorView: View {
    @EnvironmentObject private var app: AppState
    @Binding var links: [SocialLink]
    @Binding var open: Bool
    let testPrefix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                open.toggle()
            } label: {
                Text("\(app.T("Thêm liên kết", "Add links")) \(open ? "▾" : "▸")")
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(app.palette.ink)
            }
            .accessibilityIdentifier("\(testPrefix).toggle")

            if open {
                ForEach(Array(links.enumerated()), id: \.offset) { index, _ in
                    HStack(spacing: 8) {
                        Picker("", selection: Binding(
                            get: { links[index].platform },
                            set: { links[index].platform = $0 }
                        )) {
                            ForEach(socialLinkPlatforms, id: \.key) { p in Text(p.label).tag(p.key) }
                        }
                        .labelsHidden()
                        TextField("https://…", text: Binding(
                            get: { links[index].url },
                            set: { links[index].url = $0 }
                        ))
                        .font(.system(size: 12.5))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("\(testPrefix).url.\(index)")
                        Button {
                            links.remove(at: index)
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.6))
                        }
                        .accessibilityIdentifier("\(testPrefix).remove.\(index)")
                    }
                }
                Button {
                    links.append(SocialLink(platform: "website", url: ""))
                } label: {
                    Text("+ \(app.T("Thêm một liên kết", "Add another link"))")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(app.palette.rule))
                }
                .foregroundStyle(app.palette.ink)
                .accessibilityIdentifier("\(testPrefix).add")
            }
        }
    }
}
