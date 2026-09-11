import CoreLocation

/// One-shot location lookup, used only to turn the feed's placeholder
/// distances into real ones — the same promise the web app's location sheet
/// makes ("only to show how far each event is; not stored, not shared with
/// organizers"). Nothing here is persisted; only the yes/no decision is,
/// and a fresh position is requested each launch.
final class LocationService: NSObject, CLLocationManagerDelegate {
    var onUpdate: ((Coordinates) -> Void)?

    private let manager = CLLocationManager()

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

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
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
