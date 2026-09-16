import CoreLocation
import UIKit

/// One-shot location lookup, used only to turn the feed's placeholder
/// distances into real ones — the same promise the web app's location sheet
/// makes ("only to show how far each event is; not stored, not shared with
/// organizers"). Nothing here is persisted; only the yes/no decision is,
/// and a fresh position is requested each launch.
///
/// Also backs the map explore screen's compass button (11-realtime-map.md):
/// `onAuthorizationChange` lets that button flip between full/dimmed opacity
/// the moment permission changes, and `isPermanentlyDenied` distinguishes
/// "never asked yet" (re-prompt via `request()`) from "user said no in
/// Settings" (no OS dialog will ever show again — must deep-link instead).
final class LocationService: NSObject, CLLocationManagerDelegate {
    var onUpdate: ((Coordinates) -> Void)?
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?

    private let manager = CLLocationManager()

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    /// `.denied` only ever means "the user explicitly said no" (either in
    /// the OS dialog, or beforehand in Settings) — CoreLocation never
    /// returns `.denied` for "not asked yet" (that's `.notDetermined`), so
    /// this is exactly the permanently-denied case the compass button must
    /// route to a Settings deep-link instead of a fresh `request()` call.
    var isPermanentlyDenied: Bool { manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break // denied at the OS level — the feed just keeps its km segment hidden
        }
    }

    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorizationChange?(manager.authorizationStatus)
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coords = Coordinates(lat: location.coordinate.latitude, lng: location.coordinate.longitude)
        Task { @MainActor in self.onUpdate?(coords) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient failure — the placeholder distance stays, silently.
    }
}
