import Foundation
import Supabase

/// What the host sees after scanning a goer's ticket: name and date of birth,
/// so door staff can verify age. Comes from `get_checkin_guest_info`
/// (migration 125): host-only, ticket-only, audited. `dobISO` is nil for an
/// account that has no DOB on file.
struct CheckInGuestInfo: Equatable {
    let bookingID: UUID
    let name: String
    let dobISO: String?
    let alreadyCheckedIn: Bool
}

enum CheckInLookupFailure: Equatable {
    /// Not a banbe ticket / not for an event this host runs / not a valid ticket.
    case invalidTicket
    case wrongEvent
    case rateLimited
    case network
}

extension AppState {

    private struct GuestInfoResult: Decodable {
        let success: Bool?
        let error: String?
        let status: String?
        let name: String?
        let dateOfBirth: String?
        enum CodingKeys: String, CodingKey {
            case success, error, status, name, dateOfBirth = "date_of_birth"
        }
    }

    /// Looks up the scanned booking. Never logs the date of birth.
    func lookupCheckInGuest(code: String) async -> (CheckInGuestInfo?, CheckInLookupFailure?) {
        guard let id = UUID(uuidString: code.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return (nil, .invalidTicket)
        }
        // A ticket for a different event of this host must not be checked in
        // here. (Only enforced once this event's guest list has loaded.)
        let guests = attendanceGuests
        if !guests.isEmpty, !guests.contains(where: { $0.id == id }) { return (nil, .wrongEvent) }

        do {
            let r: GuestInfoResult = try await SupabaseService.client
                .rpc("get_checkin_guest_info", params: ["p_booking_id": id.uuidString]).execute().value
            if r.success == true {
                return (CheckInGuestInfo(bookingID: id, name: r.name ?? "", dobISO: r.dateOfBirth,
                                         alreadyCheckedIn: r.status == "attended"), nil)
            }
            return (nil, r.error == "RATE_LIMITED" ? .rateLimited : .invalidTicket)
        } catch {
            // Migration 125 not deployed yet: fall back to what the guest list
            // already knows (no DOB), so check-in itself keeps working.
            if let pg = error as? PostgrestError,
               pg.code == "PGRST202" || pg.code == "42883"
                || pg.message.localizedCaseInsensitiveContains("could not find the function"),
               let guest = guests.first(where: { $0.id == id }) {
                return (CheckInGuestInfo(bookingID: id, name: guest.name, dobISO: nil, alreadyCheckedIn: guest.checkedIn), nil)
            }
            return (nil, .network)
        }
    }
}
