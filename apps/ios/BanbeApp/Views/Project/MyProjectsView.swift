import SwiftUI

/// Account > Projects I'm in (note 76): every event project where I am a Host or a member, soonest first.
struct MyProjectsView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Quay lại", "Back")) { app.screen = .profile }
                    .padding(.top, 16)
                Text(app.T("Dự án của tôi", "Projects I'm in")).font(BanbeTheme.display(24)).padding(.top, 10)
                    .accessibilityAddTraits(.isHeader)
                if !app.myProjectsLoaded {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else if app.myProjects.isEmpty {
                    Text(app.T("Bạn chưa ở trong dự án nào. Khi được mời, dự án sẽ hiện ở đây.",
                               "You're not in any project yet. When someone invites you, it shows up here."))
                        .font(.subheadline).foregroundStyle(app.palette.ink2)
                        .padding(.top, 24)
                } else {
                    VStack(spacing: 10) {
                        ForEach(app.myProjects) { p in row(p) }
                    }
                    .padding(.top, 18)
                }
                Button { app.openProjectJoinEntry(back: .myProjects) } label: {
                    Label(app.T("Có mã mời? Vào đội", "Have an invite code? Join a team"), systemImage: "person.badge.plus")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(app.palette.blockInset, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.top, 18)
                .accessibilityIdentifier("project.mine.join")
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .task { await app.loadMyProjects() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.mine")
    }

    private func row(_ p: MyProject) -> some View {
        Button { Task { await app.openProject(eventID: p.eventId, back: .myProjects) } } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.name).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text([app.projectRoleName(p.role), dateText(p), p.readOnly ? app.T("Chỉ xem", "Read only") : nil]
                            .compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(app.palette.ink2)
                }
                Spacer(minLength: 8)
                if p.myOpenTasks > 0 {
                    Text(app.T("\(p.myOpenTasks) việc", p.myOpenTasks == 1 ? "1 task" : "\(p.myOpenTasks) tasks"))
                        .font(.caption.weight(.bold)).padding(.horizontal, 9).padding(.vertical, 4)
                        .foregroundStyle(app.palette.clay).background(app.palette.clayBg, in: Capsule())
                }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(app.palette.ink3)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(app.palette.block, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("project.mine.\(p.eventId)")
    }

    private func dateText(_ p: MyProject) -> String? {
        let tz = p.tz.flatMap(TimeZone.init(identifier:)) ?? .current
        guard let day = p.eventDate, let date = ProjectPresentation.localDay(day, tz: tz) else { return nil }
        let f = DateFormatter()
        f.timeZone = tz
        f.locale = Locale(identifier: app.T("vi_VN", "en_US"))
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f.string(from: date)
    }
}
