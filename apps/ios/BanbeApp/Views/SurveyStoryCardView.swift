import SwiftUI

/// Section 4 redesign — ONE shared renderer for a survey story's card
/// content, used by BOTH the host's publish-preview
/// (SurveysHostingView.swift's ShareSurveyToStoryConfirmView) and the real
/// in-story card (StoryViewerView.swift's SurveyShareCard), so the preview
/// is never a different layout from what viewers actually see. `fill`
/// switches between the preview's full-bleed canvas (large typography, no
/// outer shadow) and the real story viewer's smaller floating card
/// (unchanged visual size).
///
/// The gradient is the SAME dusty-rose/sage/sand gradient Banbe Pulse's own
/// ring already uses (HomeView's `PulseRingGlyph`) — this app's one
/// existing "branded placeholder" gradient, reused here rather than
/// inventing a new palette or requiring new uploaded artwork.
enum SurveyStoryCardStyle {
    static let gradient = LinearGradient(
        colors: [Color(hex: 0xE7C9C2), Color(hex: 0xE3CFA6), Color(hex: 0xC8CBB2)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

struct SurveyStoryCardView: View {
    @EnvironmentObject private var app: AppState
    let hostName: String
    var hostAvatarURL: URL? = nil
    let title: String
    let description: String?
    let closesAt: Date?
    let status: String?
    /// nil = not tappable at all (a real in-story card always has one; the
    /// publish preview deliberately passes nil — "a visual preview, not an
    /// accidental submit/navigation action").
    var onAnswerSurvey: (() -> Void)? = nil
    var fill: Bool = false

    private var closed: Bool { (status ?? "active") != "active" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let url = hostAvatarURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() } else { Color.white.opacity(0.5) }
                    }
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.5)).frame(width: 34, height: 34)
                }
                Text(hostName.isEmpty ? app.T("Người tổ chức", "Organizer") : hostName)
                    .font(.system(size: 12.5, weight: .bold)).foregroundStyle(app.palette.ink).lineLimit(1)
            }

            Spacer(minLength: 18)
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(BanbeTheme.display(fill ? 25 : 18)).foregroundStyle(app.palette.ink).lineLimit(fill ? 4 : 3)
                if let description, !description.isEmpty {
                    Text(description).font(.system(size: fill ? 14 : 12.5)).foregroundStyle(app.palette.ink.opacity(0.85)).lineLimit(fill ? 6 : 4)
                }
            }
            Spacer(minLength: 18)

            if let closesAt {
                Text("\(app.T("Hạn trả lời", "Deadline")): \(closesAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 12)).foregroundStyle(app.palette.ink.opacity(0.75))
                    .padding(.bottom, 12)
            }
            Button {
                onAnswerSurvey?()
            } label: {
                Text(closed ? app.T("Khảo sát đã đóng", "Survey closed") : app.T("Trả lời khảo sát", "Answer Survey"))
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(closed ? app.palette.ink : app.palette.paper)
                    .background(closed ? Color.clear : app.palette.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(closed ? app.palette.ink : .clear, lineWidth: 1.5))
                    .opacity(closed ? 0.7 : 1)
            }
            .buttonStyle(.plain)
            .disabled(onAnswerSurvey == nil)
        }
        .padding(fill ? 22 : 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SurveyStoryCardStyle.gradient)
        .clipShape(RoundedRectangle(cornerRadius: fill ? 26 : 18, style: .continuous))
        .shadow(radius: fill ? 0 : 24)
        .accessibilityIdentifier("survey.storyCard")
    }
}
