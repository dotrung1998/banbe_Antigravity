import UIKit
import CoreImage

/// Renders the gift ticket as a downloadable PDF and the accompanying
/// RFC 5545 calendar file.
///
/// Two credentials live on one ticket and are kept strictly apart:
///   * the ADMISSION credential (`admissionToken`) is printed and scanned at
///     the door, and
///   * the ACCOUNT-CLAIM credential (`claimCode`) opens the in-app import,
///     and is never printed in the visible page.
///
/// Only destinations that actually exist are linked. `banbe://` is the custom
/// scheme this app itself registers (project.yml / Info.plist
/// CFBundleURLSchemes), so tapping it opens the installed app; there is no
/// public banbe.app domain and no App Store listing yet, so neither is
/// invented here. When a destination is missing the page says so in plain
/// words instead of showing a button that goes nowhere.
enum GiftTicketPDFGenerator {

    /// The app's own registered custom scheme. The gift PDF's import link and
    /// the share text both use it, and AppState.handleDeepLink is what reads
    /// it back.
    static let appScheme = "banbe"

    static func claimURL(for claimCode: String) -> URL? {
        guard !claimCode.isEmpty,
              var components = URLComponents(string: "\(appScheme)://gift/claim")
        else { return nil }
        components.queryItems = [URLQueryItem(name: "code", value: claimCode)]
        return components.url
    }

    /// Generates high-res QR code image for the ticket's admission token.
    static func generateQRCodeImage(_ value: String, size: CGFloat = 160) -> UIImage? {
        let context = CIContext()
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(value.utf8), forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale = size / output.extent.width
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Renders the gift ticket as a polished A4 PDF document.
    static func renderPDF(document doc: GiftTicketDocument, isEN: Bool = false) -> Data {
        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842 // A4 standard
        let margin: CGFloat = 46
        let contentWidth = pageWidth - (margin * 2)

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        return renderer.pdfData { ctx in
            ctx.beginPage()

            let ink = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
            let muted = UIColor(red: 0.45, green: 0.45, blue: 0.48, alpha: 1.0)
            let rule = UIColor(red: 0.87, green: 0.87, blue: 0.89, alpha: 1.0)
            let accent = UIColor(red: 0.79, green: 0.35, blue: 0.20, alpha: 1.0)
            let surface = UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1.0)

            var y: CGFloat = margin

            // Header: the same wordmark artwork the app and the web app draw.
            if let logo = UIImage(named: "banbe-wordmark") {
                let logoWidth: CGFloat = 92
                let logoHeight = logoWidth * logo.size.height / logo.size.width
                logo.draw(in: CGRect(x: margin, y: y, width: logoWidth, height: logoHeight))
                y += logoHeight
            } else {
                "banbe".draw(at: CGPoint(x: margin, y: y), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                    .foregroundColor: ink,
                ])
                y += 26
            }

            let badgeText = isEN ? "GIFT TICKET" : "VÉ TẶNG"
            drawBadge(badgeText, at: CGPoint(x: pageWidth - margin - 104, y: y - 2),
                      font: UIFont.systemFont(ofSize: 9, weight: .bold),
                      fill: surface, border: rule, textColor: accent)

            y += 18
            drawRule(from: margin, to: pageWidth - margin, at: y, color: rule, width: 1)
            y += 30

            // Recipient
            let toLabel = isEN ? "GIFTED TO" : "TẶNG CHO"
            toLabel.draw(at: CGPoint(x: margin, y: y), withAttributes: [
                .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: muted,
                .kern: 1.4,
            ])
            y += 16
            let recipient = doc.recipientName.isEmpty ? (isEN ? "Friend" : "Bạn bè") : doc.recipientName
            recipient.draw(at: CGPoint(x: margin, y: y), withAttributes: [
                .font: UIFont.systemFont(ofSize: 25, weight: .bold),
                .foregroundColor: ink,
            ])
            y += 38

            // Event card
            let cardHeight: CGFloat = 156
            let card = UIBezierPath(roundedRect: CGRect(x: margin, y: y, width: contentWidth, height: cardHeight), cornerRadius: 14)
            surface.setFill()
            card.fill()
            rule.setStroke()
            card.lineWidth = 1
            card.stroke()

            var cy = y + 18
            let cx = margin + 20
            let cWidth = contentWidth - 40

            (doc.eventName as NSString).draw(
                with: CGRect(x: cx, y: cy, width: cWidth, height: 46),
                options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin],
                attributes: [.font: UIFont.systemFont(ofSize: 17, weight: .bold), .foregroundColor: ink],
                context: nil)
            cy += 30

            if !doc.organizer.isEmpty {
                drawLabelValue(label: isEN ? "Organized by " : "Người tổ chức: ",
                               value: doc.organizer, at: CGPoint(x: cx, y: cy),
                               width: cWidth, labelFont: UIFont.systemFont(ofSize: 11), valueFont: UIFont.systemFont(ofSize: 11),
                               labelColor: muted, valueColor: ink)
                cy += 21
            }

            let whenText = formattedWhen(startDate: doc.startDate, fallback: doc.whenText, isEN: isEN)
            drawLabelValue(label: isEN ? "Date & time " : "Thời gian: ",
                           value: whenText, at: CGPoint(x: cx, y: cy),
                           width: cWidth, labelFont: UIFont.systemFont(ofSize: 11), valueFont: UIFont.systemFont(ofSize: 11, weight: .semibold),
                           labelColor: muted, valueColor: ink)
            cy += 21

            let venueLine = (isEN ? "Venue: " : "Địa điểm: ") + doc.venue
            (venueLine as NSString).draw(
                with: CGRect(x: cx, y: cy, width: cWidth, height: 40),
                options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin],
                attributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: ink],
                context: nil)

            y += cardHeight + 34

            // Admission QR — the prominent element.
            let qrSize: CGFloat = 152
            let qrX = (pageWidth - qrSize) / 2
            if let qrImage = generateQRCodeImage(doc.admissionToken.uuidString, size: qrSize) {
                let box = UIBezierPath(roundedRect: CGRect(x: qrX - 9, y: y - 9, width: qrSize + 18, height: qrSize + 18), cornerRadius: 10)
                UIColor.white.setFill()
                box.fill()
                rule.setStroke()
                box.lineWidth = 1
                box.stroke()
                qrImage.draw(in: CGRect(x: qrX, y: y, width: qrSize, height: qrSize))
            }
            y += qrSize + 22

            let codeText = doc.ticketCode.isEmpty ? "" : doc.ticketCode
            if !codeText.isEmpty {
                let codeLabel = isEN ? "ENTRY CODE  " : "MÃ VÀO CỬA  "
                let labelFont = UIFont.systemFont(ofSize: 9, weight: .semibold)
                let codeFont = UIFont.monospacedSystemFont(ofSize: 13, weight: .bold)
                let labelSize = (codeLabel as NSString).size(withAttributes: [.font: labelFont])
                let codeSize = (codeText as NSString).size(withAttributes: [.font: codeFont])
                let total = labelSize.width + codeSize.width
                let startX = (pageWidth - total) / 2
                codeLabel.draw(at: CGPoint(x: startX, y: y + 2), withAttributes: [
                    .font: labelFont, .foregroundColor: muted, .kern: 1.2,
                ])
                codeText.draw(at: CGPoint(x: startX + labelSize.width, y: y), withAttributes: [
                    .font: codeFont, .foregroundColor: ink,
                ])
                y += 26
            }

            // Entry instructions. No email, no date of birth, no claim code:
            // none of those are needed to walk through the door.
            let instructions = isEN
                ? "Show this QR code at the door to be checked in. No banbe account is needed to attend."
                : "Xuất trình mã QR này ở cửa để điểm danh. Bạn không cần tài khoản banbe để tham dự."
            let centered = NSMutableParagraphStyle()
            centered.alignment = .center
            (instructions as NSString).draw(
                with: CGRect(x: margin + 24, y: y, width: contentWidth - 48, height: 34),
                options: [.usesLineFragmentOrigin],
                attributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: muted, .paragraphStyle: centered],
                context: nil)
            y += 44

            drawRule(from: margin, to: pageWidth - margin, at: y, color: rule, width: 0.5)
            y += 18

            // Two REAL actions, side by side. Each is either a working link or
            // honest plain text — never a button that pretends to work.
            let buttonHeight: CGFloat = 40
            let gap: CGFloat = 14
            let buttonWidth = (contentWidth - gap) / 2
            let importRect = CGRect(x: margin, y: y, width: buttonWidth, height: buttonHeight)
            let calendarRect = CGRect(x: margin + buttonWidth + gap, y: y, width: buttonWidth, height: buttonHeight)

            let importURL = claimURL(for: doc.claimCode ?? "")
            let calendarURL = googleCalendarURL(document: doc)

            drawActionButton(
                rect: importRect,
                title: isEN ? "Open banbe · Register & import" : "Mở banbe · Đăng ký & Nhập vé",
                filled: true, ink: ink, ruleColor: rule)
            if let importURL {
                ctx.setURL(importURL, for: importRect)
            }

            drawActionButton(
                rect: calendarRect,
                title: isEN ? "Add to Google Calendar" : "Thêm vào Google Calendar",
                filled: false, ink: ink, ruleColor: rule)
            if let calendarURL {
                ctx.setURL(calendarURL, for: calendarRect)
            }

            y += buttonHeight + 8

            let importNote = importURL == nil
                ? (isEN
                    ? "No import link on this ticket. Enter the claim code from your message in banbe, or send it to us and we will reissue the PDF."
                    : "Vé này không có liên kết nhận vé. Hãy nhập mã nhận vé trong tin nhắn vào banbe, hoặc gửi lại cho banbe để cấp lại PDF.")
                : (isEN
                    ? "Opens the installed banbe app. Register or sign in with the email this ticket was sent to; you can still attend without an account."
                    : "Mở ứng dụng banbe đã cài. Đăng ký hoặc đăng nhập bằng email nhận vé; bạn vẫn có thể tham dự mà không cần tài khoản.")
            (importNote as NSString).draw(
                with: CGRect(x: importRect.origin.x, y: y, width: importRect.width, height: 46),
                options: [.usesLineFragmentOrigin],
                attributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: muted],
                context: nil)

            let calendarNote = isEN
                ? "Opens Google's calendar page in your browser. The .ics file shared with this ticket adds it to Apple Calendar."
                : "Mở trang lịch Google trong trình duyệt. Tệp .ics đi kèm vé để thêm vào Lịch Apple."
            (calendarNote as NSString).draw(
                with: CGRect(x: calendarRect.origin.x, y: y, width: calendarRect.width, height: 46),
                options: [.usesLineFragmentOrigin],
                attributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: muted],
                context: nil)

            // Footer
            let footerY = pageHeight - margin - 18
            drawRule(from: margin, to: pageWidth - margin, at: footerY - 10, color: rule, width: 0.5)
            let footer = isEN
                ? "banbe · Ticket \(doc.reference)"
                : "banbe · Mã vé \(doc.reference)"
            footer.draw(at: CGPoint(x: margin, y: footerY), withAttributes: [
                .font: UIFont.systemFont(ofSize: 8), .foregroundColor: muted,
            ])
        }
    }

    /// A destination that genuinely works for anyone, signed in or not: the
    /// public Google Calendar "new event" page. The accompanying .ics covers
    /// Apple Calendar, which no single web URL can do.
    static func googleCalendarURL(document doc: GiftTicketDocument) -> URL? {
        let start = doc.startDate ?? Date()
        let end = start.addingTimeInterval(2 * 3600)
        var components = URLComponents(string: "https://calendar.google.com/calendar/render")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "TEMPLATE"),
            URLQueryItem(name: "text", value: doc.eventName),
            URLQueryItem(name: "dates", value: "\(icsDate(start))/\(icsDate(end))"),
            URLQueryItem(name: "details", value: doc.details),
            URLQueryItem(name: "location", value: doc.venue),
        ]
        return components?.url
    }

    /// Generates an accompanying RFC 5545 .ics calendar file. Works with no
    /// account and no app install, which is what makes it the honest calendar
    /// offer for a plain PDF recipient.
    static func renderICS(document doc: GiftTicketDocument) -> Data {
        let start = doc.startDate ?? Date()
        let end = start.addingTimeInterval(2 * 3600)
        let stamp = icsDate(Date())

        func escape(_ str: String) -> String {
            str.replacingOccurrences(of: "\\", with: "\\\\")
               .replacingOccurrences(of: ";", with: "\\;")
               .replacingOccurrences(of: ",", with: "\\,")
               .replacingOccurrences(of: "\n", with: "\\n")
        }

        let uidSeed = doc.admissionToken.uuidString
        let description = escape([
            doc.details,
            doc.ticketCode.isEmpty ? "" : "Ticket \(doc.ticketCode)",
        ].filter { !$0.isEmpty }.joined(separator: "\n\n"))

        let ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//banbe//banbe iOS//EN
        CALSCALE:GREGORIAN
        METHOD:PUBLISH
        BEGIN:VEVENT
        UID:\(uidSeed)@banbe
        DTSTAMP:\(stamp)
        DTSTART:\(icsDate(start))
        DTEND:\(icsDate(end))
        SUMMARY:\(escape(doc.eventName))
        DESCRIPTION:\(description)
        LOCATION:\(escape(doc.venue))
        STATUS:CONFIRMED
        END:VEVENT
        END:VCALENDAR

        """
        return Data(ics.utf8)
    }

    // MARK: - Drawing helpers

    private static func icsDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: d)
    }

    /// Event times are shown in the event's own timezone rather than the
    /// reader's, so a printed ticket reads the same on both sides of the door.
    private static func formattedWhen(startDate: Date?, fallback: String, isEN: Bool) -> String {
        guard let startDate else { return fallback }
        let f = DateFormatter()
        f.locale = Locale(identifier: isEN ? "en_US" : "vi_VN")
        f.dateFormat = isEN ? "EEEE dd/MM/yyyy · HH:mm" : "EEEE dd/MM/yyyy · HH:mm"
        f.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        return f.string(from: startDate) + " (GMT+7)"
    }

    private static func drawRule(from x1: CGFloat, to x2: CGFloat, at y: CGFloat, color: UIColor, width: CGFloat) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: x1, y: y))
        path.addLine(to: CGPoint(x: x2, y: y))
        color.setStroke()
        path.lineWidth = width
        path.stroke()
    }

    private static func drawBadge(_ text: String, at point: CGPoint, font: UIFont,
                                  fill: UIColor, border: UIColor, textColor: UIColor) {
        let padding: CGFloat = 11
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let rect = CGRect(x: point.x, y: point.y, width: textSize.width + padding * 2, height: 22)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 11)
        fill.setFill()
        path.fill()
        border.setStroke()
        path.lineWidth = 1
        path.stroke()
        text.draw(at: CGPoint(x: rect.origin.x + padding, y: rect.origin.y + 5), withAttributes: [
            .font: font, .foregroundColor: textColor, .kern: 1.1,
        ])
    }

    private static func drawActionButton(rect: CGRect, title: String, filled: Bool,
                                         ink: UIColor, ruleColor: UIColor) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 9)
        if filled {
            ink.setFill()
            path.fill()
        } else {
            UIColor.white.setFill()
            path.fill()
            ruleColor.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        let font = UIFont.systemFont(ofSize: 10, weight: .semibold)
        let size = (title as NSString).size(withAttributes: [.font: font])
        title.draw(at: CGPoint(x: rect.origin.x + (rect.width - size.width) / 2,
                               y: rect.origin.y + (rect.height - size.height) / 2),
                   withAttributes: [.font: font, .foregroundColor: filled ? .white : ink])
    }

    private static func drawLabelValue(label: String, value: String, at point: CGPoint, width: CGFloat,
                                       labelFont: UIFont, valueFont: UIFont,
                                       labelColor: UIColor, valueColor: UIColor) {
        let attributed = NSMutableAttributedString(
            string: label, attributes: [.font: labelFont, .foregroundColor: labelColor])
        attributed.append(NSAttributedString(
            string: value, attributes: [.font: valueFont, .foregroundColor: valueColor]))
        attributed.draw(with: CGRect(x: point.x, y: point.y, width: width, height: 20),
                        options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin],
                        context: nil)
    }
}