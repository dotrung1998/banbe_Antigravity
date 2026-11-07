import SwiftUI

/// Q6 pre-permission sheet: banbe explains what it would send before iOS asks. Neutral choices, no pressure:
/// "Not now" is a real answer and is never asked again automatically.
struct PushAskSheet: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("🔔").font(.system(size: 40)).accessibilityHidden(true)
            Text(app.T("Nhận lời nhắc cho sự kiện của bạn?", "Get reminders for your events?"))
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(app.T("banbe có thể gửi thông báo một ngày trước và vài giờ trước sự kiện, cùng các cập nhật về vé của bạn. Không gửi trong 22:00–07:00. Bạn có thể tắt bất cứ lúc nào trong Cài đặt của iPhone.",
                       "banbe can notify you the day before and a few hours before your event, plus updates about your tickets. Nothing between 22:00 and 07:00. You can turn this off anytime in iPhone Settings."))
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(app.T("Tiếp tục", "Continue")) { app.acceptPushAsk() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("pushAsk.continue")
            Button(app.T("Để sau", "Not now")) { app.declinePushAsk() }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("pushAsk.notNow")
        }
        .padding(24)
        .presentationDetents([.medium])
        .accessibilityIdentifier("pushAsk.sheet")
    }
}
