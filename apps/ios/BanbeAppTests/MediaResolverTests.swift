import XCTest
@testable import BanbeApp

final class MediaResolverTests: XCTestCase {
    private let id = "123e4567-e89b-12d3-a456-426614174000"
    private var on: MediaConfig { MediaConfig(publicBaseURL: "https://media.example.com/", readsEnabled: true) }
    private let legacy = URL(string: "https://x.supabase.co/storage/v1/object/public/event-photos/a.jpg")

    func testParsesValidRef() {
        let p = MediaResolver.parse("r2:ev-abc_1/\(id).webp")
        XCTAssertEqual(p?.scope, "ev-abc_1")
        XCTAssertEqual(p?.ext, "webp")
        XCTAssertNotNil(MediaResolver.parse("r2:org-9f/\(id).jpeg"))
    }

    func testRejectsBadRefs() {
        for bad in ["", "r2:ev-a/\(id).gif", "r2:evil/\(id).jpg", "r2:ev-a/../\(id).jpg",
                    "r2:ev-a/not-a-uuid.jpg", "r2:ev-a b/\(id).jpg", "r2:ev-a/\(id).jpg?x=1",
                    "https://e.com/a.jpg", "r2:ev-/\(id).jpg/extra", "r2:ev-a\n/\(id).jpg"] {
            XCTAssertNil(MediaResolver.parse(bad), bad)
        }
        XCTAssertNil(MediaResolver.parse(nil))
    }

    func testVariantURL() {
        XCTAssertEqual(MediaResolver.variantURL(ref: "r2:ev-a/\(id).png", variant: .card, config: on)?.absoluteString,
                       "https://media.example.com/v1/ev-a/\(id)/card.png")
    }

    func testResolveGating() {
        let ref = "r2:ev-a/\(id).jpg"
        XCTAssertEqual(MediaResolver.resolve(r2Ref: ref, legacyURL: legacy, variant: .thumb, config: on)?.lastPathComponent, "thumb.jpg")
        XCTAssertEqual(MediaResolver.resolve(r2Ref: ref, legacyURL: legacy, variant: .full,
            config: MediaConfig(publicBaseURL: "https://m.e.com", readsEnabled: false)), legacy)
        XCTAssertEqual(MediaResolver.resolve(r2Ref: ref, legacyURL: legacy, variant: .full,
            config: MediaConfig(publicBaseURL: "", readsEnabled: true)), legacy)
        XCTAssertEqual(MediaResolver.resolve(r2Ref: "junk", legacyURL: legacy, variant: .full, config: on), legacy)
        XCTAssertEqual(MediaResolver.resolve(r2Ref: nil, legacyURL: legacy, variant: .full, config: on), legacy)
        XCTAssertEqual(MediaResolver.resolve(r2Ref: ref, legacyURL: legacy, variant: .full,
            config: MediaConfig(publicBaseURL: "http://insecure.com", readsEnabled: true)), legacy)
    }
}
