import Foundation

/// Ported verbatim from `LOCAL_PHOTOS` in src/data/events.js. The real
/// `events` table has no photo column of its own — the web app's feed
/// picks a "hero photo" for each card purely by its position in the list,
/// cycling through these files (served as static assets from
/// `public/photos/`). This gives the iOS feed the same real photos instead
/// of a blank row, without needing a schema change on either side.
enum PhotoCatalog {
    static let heroPhotos = [
        "DSCF4423.jpg", "DSCF5481.jpg", "DSCF6107.jpg", "DSCF5891.jpg", "DSCF2836.jpg",
        "DSCF4627.jpg", "DSCF2503.jpg", "DSCF4254.jpg", "DSCF5796.jpg", "DSCF5780.jpg",
        "DSCF2539.jpg", "DSCF4517.jpg", "DSCF6366.jpg", "DSCF4223.jpg", "DSCF5542.jpg",
        "DSCF2341.jpg", "DSCF4238.jpg", "DSCF7257.jpg", "DSCF6279.jpg", "DSCF4282.jpg",
        "DSCF4550.jpg", "DSCF4212.jpg", "DSCF4880.jpg", "DSCF4488.jpg", "DSCF4889.jpg",
        "DSCF7202.jpg", "DSCF7039.jpg", "DSCF6022.jpg", "DSCF4207.jpg", "DSCF6837.jpg",
        "DSCF2438.jpg", "DSCF4864.jpg", "DSCF4196.jpg", "DSCF6368.jpg", "DSCF2237.jpg",
        "DSCF5973.jpg", "DSCF4058.jpg", "DSCF4039.jpg", "DSCF4065.jpg",
        // black-and-white (measured zero saturation) — kept, but ordered last
        "DSCF7752.jpg", "DSCF7609.jpg", "DSCF7597.jpg", "DSCF7584.jpg", "DSCF7576.jpg",
        "DSCF7556.jpg", "DSCF7501.jpg", "DSCF7459.jpg", "DSCF5586.jpg", "DSCF2128.jpg",
        "DSCF2101.jpg", "DSCF2095.jpg", "DSCF2060.jpg", "DSCF2023.jpg", "DSCF1740.jpg",
        "DSCF1683.jpg",
    ]

    /// The web app builds this as `/photos/<file>` (relative to its own
    /// origin, since it's served from the same place); iOS has no origin
    /// of its own, so this points at the deployed app's origin instead —
    /// see the note on AppConfig.apiBaseURL.
    static func heroPhotoURL(forIndex index: Int) -> URL? {
        guard !heroPhotos.isEmpty else { return nil }
        let position = ((index % heroPhotos.count) + heroPhotos.count) % heroPhotos.count
        return URL(string: AppConfig.apiBaseURL + "/photos/" + heroPhotos[position])
    }
}
