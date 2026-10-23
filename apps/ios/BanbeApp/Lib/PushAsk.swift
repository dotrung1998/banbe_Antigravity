import Foundation

/// Q6 (docs/retention-delight-plan.md): when banbe offers push reminders. Pure, so the rule is unit-tested.
/// Offered once per account per device, right after the person has a confirmed ticket (the moment a reminder is
/// actually useful), only while the `push_enabled` switch is on and iOS has never asked. The system prompt itself
/// only ever follows the person's own tap on Continue.
enum PushAsk {
    static func shouldOffer(pushEnabled: Bool, hasConfirmedTicket: Bool, alreadyOffered: Bool, systemNotDetermined: Bool) -> Bool {
        pushEnabled && hasConfirmedTicket && !alreadyOffered && systemNotDetermined
    }
}
