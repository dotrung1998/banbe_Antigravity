import XCTest
@testable import BanbeApp

/// Push pre-setup (migration 194): the APNs payload → AppNotification mapping a push tap routes through, and the
/// provisioning-profile parser that decides which APNs gateway a token belongs to.
final class PushRoutingTests: XCTestCase {
    private let nid = UUID(uuidString: "8E1F6C2A-4B7D-4E59-9C3A-2F1D0B6A7E55")!
    private let me = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private func payload(_ extra: [String: Any] = [:]) -> [AnyHashable: Any] {
        var p: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Vé đã xác nhận", "body": "Host đã xác nhận thanh toán."], "sound": "default", "badge": 3,
                    "thread-id": "payment_confirmed"],
            "nid": nid.uuidString.lowercased(),
            "kind": "payment_confirmed",
            "data": ["booking_id": "b-1", "event_id": "ev-9", "qty": 2, "had_payment": true, "amount": 12.5, "nested": ["x": 1],
                     "gone": NSNull()],
        ]
        for (k, v) in extra { p[k] = v }
        return p
    }

    func testMapsTheServerPayloadToAnAppNotification() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let n = try XCTUnwrap(PushRouting.notification(from: payload(), recipientID: me, now: now))
        XCTAssertEqual(n.id, nid)
        XCTAssertEqual(n.recipientId, me)
        XCTAssertEqual(n.kind, "payment_confirmed")
        XCTAssertEqual(n.title, "Vé đã xác nhận")
        XCTAssertEqual(n.body, "Host đã xác nhận thanh toán.")
        XCTAssertNil(n.readAt)
        XCTAssertEqual(n.createdAt, now)
        XCTAssertEqual(n.data["booking_id"], .string("b-1"))
        XCTAssertEqual(n.data["event_id"]?.stringValue, "ev-9")
        XCTAssertEqual(n.data["qty"], .int(2))
        XCTAssertEqual(n.data["had_payment"], .bool(true))
        XCTAssertEqual(n.data["amount"], .double(12.5))
        XCTAssertEqual(n.data["nested"], .null)
        XCTAssertEqual(n.data["gone"], .null)
    }

    func testFoundationTypesFromAPNsKeepTheirJSONType() {
        // APNs userInfo comes from JSON: booleans are CFBoolean NSNumbers, integers plain NSNumbers.
        let json = try! JSONSerialization.jsonObject(with: Data(#"{"a":true,"b":1,"c":2.0,"d":"x","e":null}"#.utf8)) as! [String: Any]
        XCTAssertEqual(PushRouting.value(json["a"]!), .bool(true))
        XCTAssertEqual(PushRouting.value(json["b"]!), .int(1))
        XCTAssertEqual(PushRouting.value(json["c"]!), .int(2))
        XCTAssertEqual(PushRouting.value(json["d"]!), .string("x"))
        XCTAssertEqual(PushRouting.value(json["e"]!), .null)
    }

    func testFallsBackToTheSystemTitleAndAStringAlert() throws {
        var p = payload()
        p["aps"] = ["alert": "Just a body"]
        let n = try XCTUnwrap(PushRouting.notification(from: p, title: "System title", body: "ignored", recipientID: nil))
        XCTAssertEqual(n.title, "System title")
        XCTAssertEqual(n.body, "Just a body")
        p["aps"] = nil
        let bare = try XCTUnwrap(PushRouting.notification(from: p, title: "T", body: "B", recipientID: nil))
        XCTAssertEqual(bare.title, "T")
        XCTAssertEqual(bare.body, "B")
        XCTAssertTrue(PushRouting.notification(from: ["nid": nid.uuidString, "kind": "new_message"], recipientID: nil)?.data.isEmpty ?? false)
    }

    func testRejectsPayloadsThatAreNotOurs() {
        XCTAssertNil(PushRouting.notification(from: payload(["nid": "not-a-uuid"]), recipientID: me))
        XCTAssertNil(PushRouting.notification(from: payload(["kind": ""]), recipientID: me))
        var noKind = payload(); noKind["kind"] = nil
        XCTAssertNil(PushRouting.notification(from: noKind, recipientID: me))
        XCTAssertNil(PushRouting.notification(from: ["aps": ["alert": "hi"]], recipientID: me))
    }

    // MARK: PushEnvironment

    private func provision(aps: String?) -> Data {
        let ent = aps.map { "<key>aps-environment</key><string>\($0)</string>" } ?? ""
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>Name</key><string>banbe dev</string>
        <key>Entitlements</key><dict>\(ent)<key>application-identifier</key><string>TEAM.com.banbe.ios</string></dict>
        </dict></plist>
        """
        // The real file is CMS-signed binary around the plist.
        return Data([0x30, 0x82, 0x1F, 0x00, 0x06, 0x09]) + Data(plist.utf8) + Data([0xA0, 0x82, 0x0B, 0x00, 0xFF])
    }

    func testDevelopmentProfileMeansSandbox() {
        XCTAssertEqual(PushEnvironment.environment(fromProvisionData: provision(aps: "development")), "sandbox")
    }

    func testProductionProfileMeansProduction() {
        XCTAssertEqual(PushEnvironment.environment(fromProvisionData: provision(aps: "production")), "production")
        // A profile without push at all is not a sandbox build either.
        XCTAssertEqual(PushEnvironment.environment(fromProvisionData: provision(aps: nil)), "production")
    }

    func testMissingProfileMeansProduction() {
        // App Store installs carry no embedded.mobileprovision.
        XCTAssertEqual(PushEnvironment.environment(fromProvisionData: nil), "production")
    }

    func testGarbageMeansProduction() {
        XCTAssertEqual(PushEnvironment.environment(fromProvisionData: Data([0x00, 0xFF, 0x10, 0x42])), "production")
        XCTAssertEqual(PushEnvironment.environment(fromProvisionData: Data("<?xml not really a plist".utf8)), "production")
        XCTAssertEqual(PushEnvironment.environment(fromProvisionData: Data("<?xml <broken></plist>".utf8)), "production")
    }
}
