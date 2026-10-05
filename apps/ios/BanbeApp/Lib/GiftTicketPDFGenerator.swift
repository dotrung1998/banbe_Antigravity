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

            // Plain right-aligned label: no pill, no border.
            let badgeText = isEN ? "GIFT TICKET" : "VÉ TẶNG"
            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .bold),
                .foregroundColor: accent,
                .kern: 1.1,
            ]
            let badgeWidth = ceil((badgeText as NSString).size(withAttributes: badgeAttrs).width)
            badgeText.draw(at: CGPoint(x: pageWidth - margin - badgeWidth, y: y + 3), withAttributes: badgeAttrs)

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
            let cardHeight: CGFloat = 128
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

            y += cardHeight + 28

            // Admission QR — the prominent element.
            let qrSize: CGFloat = 128
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
                let labelSize = (codeLabel as NSString).size(withAttributes: [.font: labelFont, .kern: 1.2])
                let codeSize = (codeText as NSString).size(withAttributes: [.font: codeFont])
                let total = ceil(labelSize.width) + 4 + ceil(codeSize.width)
                let startX = (pageWidth - total) / 2
                codeLabel.draw(at: CGPoint(x: startX, y: y + 2), withAttributes: [
                    .font: labelFont, .foregroundColor: muted, .kern: 1.2,
                ])
                codeText.draw(at: CGPoint(x: startX + ceil(labelSize.width) + 4, y: y), withAttributes: [
                    .font: codeFont, .foregroundColor: ink,
                ])
                y += 26
            }

            // Entry instructions. No email, no date of birth, no claim code:
            // none of those are needed to walk through the door.
            let instructions = isEN
                ? "Show this QR code at the door to check in. No banbe account needed."
                : "Xuất trình mã QR này ở cửa để vào. Không cần tài khoản banbe."
            let centered = NSMutableParagraphStyle()
            centered.alignment = .center
            (instructions as NSString).draw(
                with: CGRect(x: margin + 24, y: y, width: contentWidth - 48, height: 28),
                options: [.usesLineFragmentOrigin],
                attributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: muted, .paragraphStyle: centered],
                context: nil)
            y += 38

            drawRule(from: margin, to: pageWidth - margin, at: y, color: rule, width: 0.5)
            y += 18

            // Four REAL actions in three tidy groups. Each is either a working
            // link or honest plain text — never a button that pretends to work.
            //   1. Wallet  — the hero: the one most people want on a phone.
            //   2. Calendar — Apple and Google as an equal pair.
            //   3. banbe app — for recipients who want the ticket in an account.
            let gap: CGFloat = 12
            let halfWidth = (contentWidth - gap) / 2
            let walletRect = CGRect(x: margin, y: y, width: contentWidth, height: 44)
            let appleCalRect = CGRect(x: margin, y: walletRect.maxY + 6 + 11 + 12, width: halfWidth, height: 36)
            let googleCalRect = CGRect(x: margin + halfWidth + gap, y: appleCalRect.minY, width: halfWidth, height: 36)
            let importRect = CGRect(x: margin, y: appleCalRect.maxY + 12, width: contentWidth, height: 36)

            let walletURL = appleWalletURL(document: doc)
            let appleCalURL = appleCalendarURL(document: doc)
            let googleCalURL = googleCalendarURL(document: doc)
            let importURL = claimURL(for: doc.claimCode ?? "")

            drawActionButton(rect: walletRect, title: isEN ? "Add to Apple Wallet" : "Thêm vào Apple Wallet",
                             symbol: "wallet.pass.fill", style: .filled, ink: ink, ruleColor: rule, fontSize: 11.5)
            if let walletURL { ctx.setURL(walletURL, for: pdfLinkRect(walletRect, pageHeight: pageHeight)) }
            drawCentered(isEN ? "Open this PDF on your iPhone and tap to add the ticket to Wallet."
                              : "Mở PDF này trên iPhone và chạm để thêm vé vào Wallet.",
                         in: CGRect(x: margin, y: walletRect.maxY + 6, width: contentWidth, height: 11),
                         font: UIFont.systemFont(ofSize: 8), color: muted)

            drawActionButton(rect: appleCalRect, title: isEN ? "Apple Calendar" : "Lịch Apple",
                             symbol: "calendar.badge.plus", style: .outlined, ink: ink, ruleColor: rule, fontSize: 10)
            if let appleCalURL { ctx.setURL(appleCalURL, for: pdfLinkRect(appleCalRect, pageHeight: pageHeight)) }
            drawActionButton(rect: googleCalRect, title: isEN ? "Google Calendar" : "Google Calendar",
                             symbol: "calendar", style: .outlined, ink: ink, ruleColor: rule, fontSize: 10)
            if let googleCalURL { ctx.setURL(googleCalURL, for: pdfLinkRect(googleCalRect, pageHeight: pageHeight)) }

            drawActionButton(rect: importRect,
                             title: isEN ? "Open in banbe · Register & import" : "Mở trong banbe · Đăng ký & nhập vé",
                             symbol: "arrow.up.forward.app", style: .outlined, ink: ink, ruleColor: rule, fontSize: 10)
            if let importURL { ctx.setURL(importURL, for: pdfLinkRect(importRect, pageHeight: pageHeight)) }

            let importNote = importURL == nil
                ? (isEN
                    ? "No import link on this ticket. Enter the claim code from your message in banbe, or send it to us and we will reissue the PDF."
                    : "Vé này không có liên kết nhận vé. Hãy nhập mã nhận vé trong tin nhắn vào banbe, hoặc gửi lại cho banbe để cấp lại PDF.")
                : (isEN
                    ? "Opens the installed banbe app. You can attend with just this QR — no account needed."
                    : "Mở ứng dụng banbe đã cài. Bạn vẫn có thể vào cửa chỉ với mã QR này, không cần tài khoản.")
            drawCentered(importNote,
                         in: CGRect(x: margin, y: importRect.maxY + 6, width: contentWidth, height: 24),
                         font: UIFont.systemFont(ofSize: 8), color: muted)

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

    /// Apple Wallet: opens api/wallet-pass in Safari, which answers with a signed
    /// .pkpass and so shows iOS's own "Add to Wallet" sheet. The recipient may
    /// have no banbe account, so the credential is the ticket's admission token —
    /// the same secret this PDF's QR already carries.
    static func appleWalletURL(document doc: GiftTicketDocument) -> URL? {
        var components = URLComponents(string: AppConfig.apiBaseURL + "/api/wallet-pass")
        components?.queryItems = [URLQueryItem(name: "gift", value: doc.admissionToken.uuidString.lowercased())]
        return components?.url
    }

    /// Apple Calendar: a `webcal://` link to api/calendar, which serves the event
    /// as an .ics. iOS and macOS hand webcal links to Calendar, which offers to
    /// add the event; a PDF cannot embed a downloadable .ics itself.
    static func appleCalendarURL(document doc: GiftTicketDocument) -> URL? {
        guard let start = doc.startDate,
              var components = URLComponents(string: AppConfig.apiBaseURL + "/api/calendar")
        else { return nil }
        components.scheme = "webcal"
        components.queryItems = [
            URLQueryItem(name: "title", value: doc.eventName),
            URLQueryItem(name: "start", value: String(Int(start.timeIntervalSince1970))),
            URLQueryItem(name: "end", value: String(Int(start.addingTimeInterval(2 * 3600).timeIntervalSince1970))),
            URLQueryItem(name: "loc", value: doc.venue),
            URLQueryItem(name: "desc", value: doc.details),
            URLQueryItem(name: "uid", value: doc.admissionToken.uuidString),
        ]
        return components.url
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

    /// `UIGraphicsPDFRendererContext.setURL(_:for:)` takes the rect in raw PDF
    /// space (origin bottom-left), not the flipped UIKit space everything else on
    /// the page is drawn in. Passing the drawn rect straight through puts the link
    /// at the mirrored spot at the bottom of the page, so the buttons look
    /// right but do nothing when tapped.
    private static func pdfLinkRect(_ rect: CGRect, pageHeight: CGFloat) -> CGRect {
        CGRect(x: rect.origin.x, y: pageHeight - rect.origin.y - rect.height,
               width: rect.width, height: rect.height)
    }

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

    private enum ButtonStyle { case filled, outlined }

    /// Rounded button with an optional leading symbol, title and symbol centred
    /// together as one group.
    private static func drawActionButton(rect: CGRect, title: String, symbol: String? = nil, style: ButtonStyle,
                                         ink: UIColor, ruleColor: UIColor, fontSize: CGFloat) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height > 40 ? 12 : 10)
        let textColor: UIColor
        switch style {
        case .filled:
            ink.setFill()
            path.fill()
            textColor = .white
        case .outlined:
            UIColor.white.setFill()
            path.fill()
            ruleColor.setStroke()
            path.lineWidth = 1
            path.stroke()
            textColor = ink
        }
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let titleSize = (title as NSString).size(withAttributes: [.font: font])

        var icon: UIImage?
        if let symbol {
            let config = UIImage.SymbolConfiguration(pointSize: fontSize + 1.5, weight: .semibold)
            // Rasterise the symbol first: drawn straight into the PDF context it
            // comes out as a solid block instead of the glyph.
            if let glyph = UIImage(systemName: symbol, withConfiguration: config)?
                .withTintColor(textColor, renderingMode: .alwaysOriginal) {
                let format = UIGraphicsImageRendererFormat()
                format.scale = 4
                icon = UIGraphicsImageRenderer(size: glyph.size, format: format).image { _ in
                    glyph.draw(at: .zero)
                }
            }
        }
        let spacing: CGFloat = 7
        let iconWidth = icon.map { $0.size.width + spacing } ?? 0
        var x = rect.midX - (iconWidth + titleSize.width) / 2
        if let icon {
            icon.draw(in: CGRect(x: x, y: rect.midY - icon.size.height / 2, width: icon.size.width, height: icon.size.height))
            x += iconWidth
        }
        title.draw(at: CGPoint(x: x, y: rect.midY - titleSize.height / 2),
                   withAttributes: [.font: font, .foregroundColor: textColor])
    }

    private static func drawCentered(_ text: String, in rect: CGRect, font: UIFont, color: UIColor) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin],
                                attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style],
                                context: nil)
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