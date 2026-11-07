import SwiftUI

/// Organizer Team pass (2026-09-27, Stage 2) — a Banbe-styled, readable
/// Team page: large rounded member cards, grouped by their REAL public
/// role (display-only — never implies a management hierarchy the data
/// doesn't support; groups are just "people who share this same title,"
/// in the order those titles first appear). Real organizer/member
/// identity only (get_organizer_team, 098/101) — accepted AND
/// public_visible members alone; a member who opted out simply never
/// appears here, with no trace.
struct OrganizerTeamView: View {
    @EnvironmentObject private var app: AppState

    private struct RoleGroup: Identifiable {
        var id: String { role }
        let role: String
        var members: [OrganizerTeamMember]
    }

    private var groups: [RoleGroup] {
        var result: [RoleGroup] = []
        var indexByRole: [String: Int] = [:]
        for m in app.organizerTeam?.members ?? [] {
            if let idx = indexByRole[m.publicRole] {
                result[idx].members.append(m)
            } else {
                indexByRole[m.publicRole] = result.count
                result.append(RoleGroup(role: m.publicRole, members: [m]))
            }
        }
        return result
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Quay lại", "Back")) { app.backFromOrganizerTeam() }
                    .padding(.top, 16)

                if app.organizerTeamLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                } else if !app.organizerTeamError.isEmpty {
                    Text(app.organizerTeamError).font(.system(size: 13)).foregroundStyle(app.palette.ink)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                } else if let team = app.organizerTeam {
                    Text(app.T("Đội ngũ \(team.organizerName ?? "")", "The \(team.organizerName ?? "") Team"))
                        .font(BanbeTheme.display(24)).padding(.top, 10)

                    if (team.members ?? []).isEmpty {
                        Text(app.T("Đội ngũ này chưa công khai thành viên nào.", "This Team has no publicly shown members yet."))
                            .font(.system(size: 13)).foregroundStyle(app.palette.ink.opacity(0.6))
                            .frame(maxWidth: .infinity).padding(.top, 60)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            ForEach(groups) { group in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(group.role).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(app.palette.ink.opacity(0.7))
                                    ForEach(group.members) { member in
                                        Button {
                                            app.openPublicProfile(handle: member.handle, back: .organizerTeam)
                                        } label: {
                                            memberCard(member)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("team.member.\(member.handle)")
                                    }
                                }
                            }
                        }
                        .padding(.top, 18)
                    }
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func memberCard(_ member: OrganizerTeamMember) -> some View {
        HStack(spacing: 14) {
            if let urlStr = member.avatarUrl, let url = URL(string: urlStr) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(app.palette.ink)
                    .frame(width: 56, height: 56)
                    .overlay(Text(String((member.displayName ?? member.handle).prefix(1)).uppercased()).font(.system(size: 20, weight: .bold)).foregroundStyle(app.palette.paper))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName ?? member.handle).font(.system(size: 14, weight: .semibold))
                Text("@\(member.handle)").font(.system(size: 11.5)).opacity(0.65)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
