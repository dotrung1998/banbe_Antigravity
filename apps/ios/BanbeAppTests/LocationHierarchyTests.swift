import XCTest
@testable import BanbeApp

/// Map v6 (note 74): the city level in the location tree (cities.json via `MapDiscovery.cityFor`), the skip-duplicate
/// rules, and the migration of ids from before the city level. Web twin: tests/unit/locationTree*.test.mjs.
final class LocationHierarchyTests: XCTestCase {
    private func leaf(_ loc: EventLocation) -> String { LocationHierarchy.leafID(for: loc) }

    func testHCMCRowWithNoProvinceGetsItsCityFromThePosition() {
        let loc = EventLocation(countryCode: "VN", stateProvince: nil, city: nil, area: "Quận 1", neighborhood: nil,
                                lat: 10.776, lng: 106.70)
        XCTAssertEqual(leaf(loc), "c:VN|ci:TP. Hồ Chí Minh|a:Quận 1")
    }

    func testCityColumnNamesTheCityWithoutAPosition() {
        let loc = EventLocation(countryCode: "VN", stateProvince: nil, city: "Hồ Chí Minh", area: "Thảo Điền", neighborhood: nil)
        XCTAssertEqual(leaf(loc), "c:VN|ci:TP. Hồ Chí Minh|a:Thảo Điền")
    }

    func testProvinceThatIsTheCitySkipsTheCityLevel() {
        let loc = EventLocation(countryCode: "VN", stateProvince: "Thành phố Hà Nội", city: nil, area: "Hoàn Kiếm",
                                neighborhood: nil, lat: 21.03, lng: 105.85)
        XCTAssertEqual(leaf(loc), "c:VN|s:Thành phố Hà Nội|a:Hoàn Kiếm")
    }

    func testCityUnderAProvinceAndAnAreaThatRepeatsTheCityIsDropped() {
        let loc = EventLocation(countryCode: "VN", stateProvince: "Tỉnh Lâm Đồng", city: nil, area: "Đà Lạt",
                                neighborhood: nil, lat: 11.94, lng: 108.44)
        XCTAssertEqual(leaf(loc), "c:VN|s:Tỉnh Lâm Đồng|ci:Đà Lạt")
    }

    func testNoCityFoundKeepsTheOldPath() {
        let loc = EventLocation(countryCode: "VN", stateProvince: nil, city: nil, area: "Quận 1", neighborhood: nil)
        XCTAssertEqual(leaf(loc), "c:VN|a:Quận 1")
    }

    func testUSIsUnchanged() {
        let loc = EventLocation(countryCode: "US", stateProvince: "California", city: "San Francisco", area: nil,
                                neighborhood: "Mission", lat: 37.76, lng: -122.42)
        XCTAssertEqual(leaf(loc), "c:US|s:California|ci:San Francisco|n:Mission")
    }

    func testCityNodeLabelFollowsTheLanguage() {
        XCTAssertEqual(LocationHierarchy.label(kind: .city, raw: "TP. Hồ Chí Minh", T: { _, en in en }), "Ho Chi Minh City")
        XCTAssertEqual(LocationHierarchy.label(kind: .city, raw: "TP. Hồ Chí Minh", T: { vi, _ in vi }), "TP. Hồ Chí Minh")
        XCTAssertEqual(LocationHierarchy.label(kind: .city, raw: "Springfield", T: { _, en in en }), "Springfield")
    }

    private func tree() -> [LocationNode] {
        LocationHierarchy.build(from: [
            LocatedEvent(id: "a", location: EventLocation(countryCode: "VN", stateProvince: nil, city: nil, area: "Quận 1",
                                                         neighborhood: nil, lat: 10.776, lng: 106.70), isOpen: true),
            LocatedEvent(id: "b", location: EventLocation(countryCode: "VN", stateProvince: nil, city: nil, area: "Thảo Điền",
                                                         neighborhood: nil, lat: 10.80, lng: 106.73), isOpen: true),
        ])
    }

    func testTreeHasTheCityUnderVietnam() {
        let vn = LocationHierarchy.find("c:VN", in: tree())
        XCTAssertEqual(vn?.children.map(\.id), ["c:VN|ci:TP. Hồ Chí Minh"])
        XCTAssertEqual(vn?.children.first?.openCount, 2)
        XCTAssertEqual(vn?.children.first?.children.count, 2)
    }

    func testOldIdsWithoutTheCityMapToTheNodeWithTheSameTail() {
        let roots = tree()
        XCTAssertEqual(LocationHierarchy.migrateSelection("c:VN|a:Quận 1", roots: roots), "c:VN|ci:TP. Hồ Chí Minh|a:Quận 1")
        XCTAssertEqual(LocationHierarchy.migrateSelection("thaodien", roots: roots), "c:VN|ci:TP. Hồ Chí Minh|a:Thảo Điền")
        XCTAssertEqual(LocationHierarchy.migrateSelection("c:VN", roots: roots), "c:VN")
        XCTAssertEqual(LocationHierarchy.migrateSelection("c:VN|a:Nowhere", roots: roots), "c:VN|a:Nowhere", "unknown passes through")
        XCTAssertEqual(LocationHierarchy.migrateSelection("all", roots: roots), "all")
    }

    func testLegacyAccessibilityKeysSurviveTheCityLevel() {
        XCTAssertEqual(LocationHierarchy.legacyKey(forNodeID: "c:VN|ci:TP. Hồ Chí Minh|a:Thảo Điền"), "thaodien")
        XCTAssertNil(LocationHierarchy.legacyKey(forNodeID: "c:VN|ci:TP. Hồ Chí Minh"))
    }
}
