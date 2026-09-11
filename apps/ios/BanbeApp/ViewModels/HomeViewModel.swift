import Foundation

/// Fetches the public event feed — the iOS equivalent of the "All" section
/// on the web Home screen (src/screens/Home.jsx), which reads live events
/// via `events_select_public` RLS (status = 'live', or owned by the caller).
@MainActor
final class HomeViewModel: ObservableObject {
    @Published var events: [Event] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadLiveEvents() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let events: [Event] = try await SupabaseService.client
                .from("events")
                .select()
                .eq("status", value: "live")
                .order("starts_at", ascending: true)
                .execute()
                .value
            self.events = events
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
