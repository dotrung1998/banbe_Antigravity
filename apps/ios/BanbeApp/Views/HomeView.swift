import SwiftUI

/// Matches the "All events" feed on src/screens/Home.jsx — a live list
/// fetched from Supabase rather than the web app's static
/// src/data/events.js demo catalogue.
struct HomeView: View {
    @EnvironmentObject var auth: AuthViewModel
    @StateObject private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            List {
                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
                ForEach(viewModel.events) { event in
                    EventRow(event: event)
                }
            }
            .navigationTitle("banbe")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sign out") { Task { await auth.signOut() } }
                }
            }
            .overlay {
                if viewModel.isLoading && viewModel.events.isEmpty {
                    ProgressView()
                } else if !viewModel.isLoading && viewModel.events.isEmpty {
                    ContentUnavailableView("No events yet", systemImage: "calendar")
                }
            }
            .refreshable { await viewModel.loadLiveEvents() }
            .task { await viewModel.loadLiveEvents() }
        }
    }
}

#Preview {
    HomeView().environmentObject(AuthViewModel())
}
