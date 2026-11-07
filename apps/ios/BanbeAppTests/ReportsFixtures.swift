import Foundation
@testable import BanbeApp

/// Representative `get_account_kpis` payloads (migration 097 shape) shared by
/// the presentation and export tests. Values are fixtures for tests only.
enum ReportsFixtures {
    static let hostJSON = """
    {"success":true,"scope":"host","organizer_id":"org_1",
     "range":{"start":"2026-10-01T02:15:30.25+00:00","end":"2026-10-03T16:59:59.999+00:00"},
     "metrics":[
      {"key":"published_events","label":"Sự kiện đã công khai","unit":"count","value":4},
      {"key":"upcoming_events","label":"Sắp diễn ra","unit":"count","value":2},
      {"key":"confirmed_seats","label":"Chỗ đã xác nhận","unit":"count","value":5,
       "series":[{"d":"2026-10-01","v":0},{"d":"2026-10-02","v":3},{"d":"2026-10-03","v":2}],
       "rows":[{"id":"b1","event_name":"=SUM(A1), Phở","qty":3,"at":"2026-10-02T03:04:05.123+00:00"},
               {"id":"b2","event_name":"Supper \\"club\\"","qty":2,"at":"2026-10-03T20:00:00+00:00"}]},
      {"key":"check_ins","label":"Đã check-in","unit":"count","value":0,
       "series":[{"d":"2026-10-01","v":0},{"d":"2026-10-02","v":0},{"d":"2026-10-03","v":0}]},
      {"key":"confirmed_payment_amount","label":"Số tiền thanh toán đã xác nhận","unit":"vnd","value":1250000,
       "series":[{"d":"2026-10-01","v":0},{"d":"2026-10-02","v":750000},{"d":"2026-10-03","v":500000}]},
      {"key":"refunds_owed","label":"Hoàn tiền còn nợ","unit":"vnd","value":300000,
       "rows":[{"id":"r1","event_name":"Gallery night","amount_vnd":300000,"due_at":"2026-09-30T00:00:00+00:00","overdue":true}]},
      {"key":"refunds_overdue","label":"Hoàn tiền quá hạn","unit":"count","value":1}
     ]}
    """

    static let personalJSON = """
    {"success":true,"scope":"personal",
     "range":{"start":"2026-10-01T02:15:30.25+00:00","end":"2026-10-03T16:59:59.999+00:00"},
     "metrics":[
      {"key":"saved_events","label":"Sự kiện đã lưu","unit":"count","value":0,"rows":[]},
      {"key":"confirmed_bookings","label":"Đặt chỗ đã xác nhận","unit":"count","value":1,
       "series":[{"d":"2026-10-01","v":1},{"d":"2026-10-02","v":0},{"d":"2026-10-03","v":0}],
       "rows":[{"id":"b9","event_name":"Music","qty":1,"at":"2026-10-01T10:00:00+00:00"}]},
      {"key":"attended_events","label":"Đã tham dự","unit":"count","value":0,
       "series":[{"d":"2026-10-01","v":0},{"d":"2026-10-02","v":0},{"d":"2026-10-03","v":0}],"rows":[]},
      {"key":"upcoming_events","label":"Sắp diễn ra","unit":"count","value":1,
       "rows":[{"id":"b9","event_name":"Music","starts_at":"2026-10-20T12:00:00+00:00"}]},
      {"key":"outstanding_refunds","label":"Hoàn tiền đang chờ","unit":"vnd","value":0,"rows":[]}
     ]}
    """

    static let adminJSON = """
    {"success":true,"scope":"admin",
     "range":{"start":"2026-10-01T02:15:30.25+00:00","end":"2026-10-03T16:59:59.999+00:00"},
     "metrics":[
      {"key":"pending_event_reviews","label":"Sự kiện chờ duyệt","unit":"count","value":2,
       "rows":[{"id":"e1","event_name":"A","submitted_at":"2026-10-01T00:00:00+00:00","age_days":2.5}]},
      {"key":"unresolved_disputes","label":"Tranh chấp chưa xử lý","unit":"count","value":0,"rows":[]},
      {"key":"backlog_avg_age_days","label":"Tuổi trung bình hàng chờ (ngày)","unit":"days","value":2.5},
      {"key":"platform_new_events","label":"Sự kiện mới toàn nền tảng","unit":"count","value":3,
       "series":[{"d":"2026-10-01","v":1},{"d":"2026-10-02","v":2},{"d":"2026-10-03","v":0}]},
      {"key":"platform_new_bookings","label":"Đặt chỗ mới toàn nền tảng","unit":"count","value":0,
       "series":[{"d":"2026-10-01","v":0},{"d":"2026-10-02","v":0},{"d":"2026-10-03","v":0}]}
     ]}
    """

    static func decode(_ json: String) -> AccountKpiReport {
        // Fixture JSON is a compile-time literal; a decode failure is a test bug.
        try! JSONDecoder().decode(AccountKpiReport.self, from: Data(json.utf8))
    }
}
