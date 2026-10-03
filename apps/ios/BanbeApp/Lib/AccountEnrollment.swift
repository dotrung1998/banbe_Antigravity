import Foundation

/// Three separate Day / Month / Year fields -> a validated ISO DATE
/// ("YYYY-MM-DD"). Real calendar dates only (no Feb 30, Feb 29 only in leap
/// years), no future dates. The value is never logged or persisted by the
/// app; it is sent once to the server.
struct DateOfBirthInput: Equatable {
    var day = ""
    var month = ""
    var year = ""

    enum Problem: Error, Equatable { case incomplete, invalidDate, future, tooOld }

    static func digits(_ s: String, max: Int) -> String {
        String(s.filter(\.isASCII).filter(\.isNumber).prefix(max))
    }

    var isComplete: Bool { !day.isEmpty && !month.isEmpty && year.count == 4 }

    /// - Parameter today: injectable for tests (year, month, day of "today").
    func validate(today: (y: Int, m: Int, d: Int)? = nil) -> Result<String, Problem> {
        guard isComplete, let d = Int(day), let m = Int(month), let y = Int(year) else {
            return .failure(.incomplete)
        }
        guard y >= 1900 else { return .failure(.tooOld) }
        guard Self.isRealDate(year: y, month: m, day: d) else { return .failure(.invalidDate) }
        let now = today ?? {
            let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            return (c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }()
        if (y, m, d) > (now.y, now.m, now.d) { return .failure(.future) }
        return .success(String(format: "%04d-%02d-%02d", y, m, d))
    }

    static func isRealDate(year: Int, month: Int, day: Int) -> Bool {
        guard (1...12).contains(month), day >= 1 else { return false }
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return day <= days[month - 1]
    }
}

struct PhoneCountry: Identifiable, Hashable {
    let iso: String
    let dial: String
    let nameVi: String
    let nameEn: String
    /// National numbers are commonly typed with a leading trunk "0" that is
    /// dropped in international format (e.g. 090… -> +8490…).
    let trunkZero: Bool
    var id: String { iso }

    var flag: String {
        iso.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }
            .map { String($0) }.joined()
    }

    static let all: [PhoneCountry] = [
        .init(iso: "VN", dial: "84", nameVi: "Việt Nam", nameEn: "Vietnam", trunkZero: true),
        .init(iso: "US", dial: "1", nameVi: "Hoa Kỳ", nameEn: "United States", trunkZero: false),
        .init(iso: "CA", dial: "1", nameVi: "Canada", nameEn: "Canada", trunkZero: false),
        .init(iso: "GB", dial: "44", nameVi: "Vương quốc Anh", nameEn: "United Kingdom", trunkZero: true),
        .init(iso: "AU", dial: "61", nameVi: "Úc", nameEn: "Australia", trunkZero: true),
        .init(iso: "SG", dial: "65", nameVi: "Singapore", nameEn: "Singapore", trunkZero: false),
        .init(iso: "JP", dial: "81", nameVi: "Nhật Bản", nameEn: "Japan", trunkZero: true),
        .init(iso: "KR", dial: "82", nameVi: "Hàn Quốc", nameEn: "South Korea", trunkZero: true),
        .init(iso: "FR", dial: "33", nameVi: "Pháp", nameEn: "France", trunkZero: true),
        .init(iso: "DE", dial: "49", nameVi: "Đức", nameEn: "Germany", trunkZero: true),
        .init(iso: "TH", dial: "66", nameVi: "Thái Lan", nameEn: "Thailand", trunkZero: true),
        .init(iso: "MY", dial: "60", nameVi: "Malaysia", nameEn: "Malaysia", trunkZero: true),
        .init(iso: "PH", dial: "63", nameVi: "Philippines", nameEn: "Philippines", trunkZero: true),
        .init(iso: "TW", dial: "886", nameVi: "Đài Loan", nameEn: "Taiwan", trunkZero: true),
        .init(iso: "CN", dial: "86", nameVi: "Trung Quốc", nameEn: "China", trunkZero: false),
        .init(iso: "IN", dial: "91", nameVi: "Ấn Độ", nameEn: "India", trunkZero: false),
    ]

    static var vietnam: PhoneCountry { all[0] }

    /// E.164 ("+" and up to 15 digits) from a country and what the user typed,
    /// or nil when it cannot be a valid number. Accepts a number already typed
    /// in international form ("+1 415 …") regardless of the picker.
    func e164(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        var digits = trimmed.filter(\.isASCII).filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        if trimmed.hasPrefix("+") {
            return (8...15).contains(digits.count) ? "+" + digits : nil
        }
        if trunkZero, digits.hasPrefix("0") { digits.removeFirst() }
        guard digits.count >= 6, (dial.count + digits.count) <= 15, (dial.count + digits.count) >= 8 else { return nil }
        return "+" + dial + digits
    }

    /// Default picker choice from the device region.
    static func defaultCountry(regionCode: String?) -> PhoneCountry {
        all.first { $0.iso == regionCode } ?? vietnam
    }
}
