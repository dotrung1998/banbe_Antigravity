import Foundation

/// Dynamic VietQR payload builder — the Swift port of src/lib/vietqr.js.
///
/// Ported rather than fetched from a service for the same reasons as the web
/// side: the payload carries the organizer's account number and the buyer's
/// exact amount, it must work with no network, and being deterministic makes
/// it testable. The two implementations are verified against the same EMVCo
/// CRC check value (0x29B1 for "123456789"), which is what keeps them honest
/// about producing byte-identical output.
enum VietQR {

    /// NAPAS acquirer BINs — mirrors BANK_BINS in the JS module.
    static let bankBins: [String: String] = [
        "vietcombank": "970436", "vcb": "970436",
        "techcombank": "970407", "tcb": "970407",
        "mbbank": "970422", "mb": "970422",
        "vietinbank": "970415", "ctg": "970415",
        "bidv": "970418", "agribank": "970405", "acb": "970416",
        "vpbank": "970432", "tpbank": "970423", "sacombank": "970403",
        "vib": "970441", "shb": "970443", "eximbank": "970431",
        "msb": "970426", "ocb": "970448", "seabank": "970440",
        "hdbank": "970437", "scb": "970429", "namabank": "970428",
        "bacabank": "970409", "pvcombank": "970412",
        "lpbank": "970449", "lienvietpostbank": "970449",
        "kienlongbank": "970452", "abbank": "970425",
        "bvbank": "970454", "vietcapitalbank": "970454",
        "saigonbank": "970400", "pgbank": "970430", "baovietbank": "970438",
        "ncb": "970419", "vietabank": "970427", "vietbank": "970433",
        "dongabank": "970406", "gpbank": "970408", "oceanbank": "970414",
        "cake": "546034", "ubank": "546035", "timo": "963388",
        "viettelmoney": "971005", "vnptmoney": "971011",
    ]

    static func resolveBankBin(_ bank: String) -> String? {
        let raw = bank.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.count == 6, raw.allSatisfy(\.isNumber) { return raw }
        let key = raw.lowercased().filter { $0.isLetter || $0.isNumber }
        return bankBins[key]
    }

    /// CRC-16/CCITT-FALSE: poly 0x1021, init 0xFFFF, no reflection, no final
    /// XOR. The other common CRC-16 variants all yield a QR that banking apps
    /// silently refuse.
    static func crc16ccitt(_ input: String) -> String {
        var crc: UInt16 = 0xFFFF
        for byte in Array(input.utf8) {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return String(format: "%04X", crc)
    }

    private static func tlv(_ tag: String, _ value: String) -> String {
        String(format: "%@%02d%@", tag, value.count, value)
    }

    /// Strips a memo down to what survives a Vietnamese bank's description
    /// field, so the reference we encode is the reference the webhook sees.
    static func sanitizeMemo(_ memo: String) -> String {
        let folded = memo.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en"))
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "D")
        let cleaned = folded.map { ch -> Character in
            (ch.isLetter && ch.isASCII) || ch.isNumber ? ch : " "
        }
        let collapsed = String(cleaned).split(separator: " ").joined(separator: " ")
        return String(collapsed.uppercased().prefix(25))
    }

    enum QRError: Error { case unknownBank(String), invalidAccount }

    static func payload(bank: String, accountNumber: String,
                        amountVnd: Int = 0, memo: String = "") throws -> String {
        guard let bin = resolveBankBin(bank) else { throw QRError.unknownBank(bank) }
        let account = accountNumber.filter { !$0.isWhitespace }
        guard account.count >= 4, account.count <= 19, account.allSatisfy(\.isNumber) else {
            throw QRError.invalidAccount
        }

        let beneficiary = tlv("00", bin) + tlv("01", account)
        let merchant = tlv("00", "A000000727") + tlv("01", beneficiary) + tlv("02", "QRIBFTTA")

        var out = tlv("00", "01") + tlv("01", "12") + tlv("38", merchant) + tlv("53", "704")
        // Zero must omit tag 54 entirely — a present-but-zero amount is
        // rejected outright by some banking apps.
        if amountVnd > 0 { out += tlv("54", String(amountVnd)) }
        out += tlv("58", "VN")

        let cleanMemo = sanitizeMemo(memo)
        if !cleanMemo.isEmpty { out += tlv("62", tlv("08", cleanMemo)) }

        let withTag = out + "6304"
        return withTag + crc16ccitt(withTag)
    }

    /// Convenience for a booking whose organizer details came back with it.
    static func payload(for booking: PayableBooking) -> String? {
        guard !booking.bankAccountNo.isEmpty, !booking.bankName.isEmpty else { return nil }
        return try? payload(bank: booking.bankName,
                            accountNumber: booking.bankAccountNo,
                            amountVnd: booking.totalVnd,
                            memo: booking.paymentRef.isEmpty ? booking.code : booking.paymentRef)
    }
}
