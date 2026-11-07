#if DEBUG
import SwiftUI
import UserNotifications
import Supabase

/// DEBUG BUILDS ONLY (never in Release / TestFlight / App Store): lets a developer try notifications on the simulator
/// before the paid Apple account, the APNs key and the `push_enabled` switch exist (docs/apple-setup-checklist.md).
///   1. "Allow notifications" asks iOS for permission directly (the real app only asks through the Q6 sheet, and only
///      while push_enabled is on).
///   2. "Send a sample reminder" schedules a LOCAL notification shaped exactly like a server push (nid / kind / data,
///      Lib/PushRouting.swift), using this account's latest confirmed ticket when there is one, so tapping it goes
///      through the same routing as a real push. Nothing is sent to or stored on the server.
/// The terminal alternative stays available: `xcrun simctl push booted com.banbe.ios push.json`.
struct DebugPushTestSection: View {
    @EnvironmentObject private var app: AppState
    @State private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Debug · Notifications test")
                .font(.system(size: 11.5, weight: .semibold))
                .padding(.top, 24)
            VStack(alignment: .leading, spacing: 10) {
                Text("Debug builds only. Lets you try notifications on the simulator without the Apple account or the push switch. Nothing reaches the server.")
                    .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.7))
                HStack(spacing: 10) {
                    Button("Allow notifications") { Task { await allow() } }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("debug.push.allow")
                    Button("Send a sample reminder") { Task { await sendSample() } }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("debug.push.sample")
                }
                if !status.isEmpty {
                    Text(status).font(.system(size: 12.5)).accessibilityIdentifier("debug.push.status")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .foregroundStyle(app.palette.ink)
        .task { await refreshStatus() }
    }

    private func refreshStatus() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        status = "Permission: " + label(s.authorizationStatus)
    }

    private func label(_ s: UNAuthorizationStatus) -> String {
        switch s {
        case .authorized: return "allowed"
        case .denied: return "denied (turn it on in Settings › banbe › Notifications)"
        case .notDetermined: return "not asked yet"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown"
        }
    }

    private func allow() async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        status = granted ? "Permission: allowed" : "Permission: not allowed"
        await refreshStatus()
    }

    private func sendSample() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        guard s.authorizationStatus == .authorized || s.authorizationStatus == .provisional else {
            status = "Tap \"Allow notifications\" first."
            return
        }
        struct Row: Decodable { let id: UUID; let event_id: String }
        var data: [String: String] = [:]
        if let uid = app.userID,
           let rows: [Row] = try? await SupabaseService.client.from("bookings").select("id,event_id")
               .eq("user_id", value: uid.uuidString).eq("status", value: "confirmed")
               .order("created_at", ascending: false).limit(1).execute().value,
           let row = rows.first {
            data = ["event_id": row.event_id, "booking_id": row.id.uuidString.lowercased()]
        }
        let content = UNMutableNotificationContent()
        content.title = app.T("Sự kiện ngày mai", "Your event is tomorrow")
        content.body = app.T("Đây là lời nhắc mẫu (chỉ bản Debug). Chạm để mở vé.",
                             "This is a sample reminder (Debug build only). Tap to open the ticket.")
        content.sound = .default
        content.userInfo = ["nid": UUID().uuidString.lowercased(), "kind": "event_reminder_day", "data": data,
                            "debug_test": true]
        let request = UNNotificationRequest(identifier: "debug-sample-\(UUID().uuidString)", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false))
        do {
            try await UNUserNotificationCenter.current().add(request)
            status = data.isEmpty
                ? "Sample arrives in 3 s. No confirmed ticket on this account, so tapping it opens nothing specific."
                : "Sample arrives in 3 s. Tapping it opens your latest ticket."
        } catch {
            status = "Could not schedule: \(error.localizedDescription)"
        }
    }
}
#endif
