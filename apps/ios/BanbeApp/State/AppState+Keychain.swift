import SwiftUI
import Supabase

/// Session cache for profile keychains. A separate ObservableObject (not
/// @Published fields on AppState) so a charm repaint never invalidates the
/// whole app state. Reset on sign-out via `AppState.resetKeychainState()`.
@MainActor
final class KeychainStore: ObservableObject {
    static let shared = KeychainStore()
    /// Set by the profile's "Edit charm" button; EditProfileView scrolls to the Keychain section once.
    var focusKeychainOnEdit = false

    @Published private(set) var mine: KeychainConfig?
    @Published private(set) var mineLoaded = false
    /// false once an RPC reported "function missing" -> feature hidden, never crashes.
    @Published private(set) var featureAvailable = true
    @Published private(set) var byHandle: [String: KeychainConfig?] = [:]
    @Published private(set) var customImages: [String: UIImage] = [:]
    private var inflightImages = Set<String>()

    static func key(_ handle: String) -> String { handle.lowercased() }

    func reset() {
        mine = nil; mineLoaded = false; featureAvailable = true
        byHandle = [:]; customImages = [:]; inflightImages = []
    }
    func setMine(_ c: KeychainConfig?) { mine = c; mineLoaded = true }
    func setFeatureUnavailable() { featureAvailable = false; mineLoaded = true }
    func setProfile(_ handle: String, _ c: KeychainConfig?) { byHandle[Self.key(handle)] = .some(c) }
    func cached(_ handle: String) -> KeychainConfig?? { byHandle[Self.key(handle)] }

    /// Loads (once per path) the custom art through a signed URL. No user-supplied URL is ever fetched.
    func loadCustomImage(path: String) async {
        guard customImages[path] == nil, !inflightImages.contains(path) else { return }
        inflightImages.insert(path)
        defer { inflightImages.remove(path) }
        guard let url = await KeychainArtService.signedURL(path: path),
              let img = await PhotoLoader.load(path: url.absoluteString, maxPixel: 512) else { return }
        customImages[path] = img
    }
}

private struct SaveKeychainParams: Encodable { let p_config: [String: AnyJSONValue] }
private struct HandleParams: Encodable { let p_handle: String }

extension AppState {

    private static func keychainFunctionMissing(_ error: Error) -> Bool {
        if let pg = error as? PostgrestError {
            return pg.code == "PGRST202" || pg.code == "42883"
                || pg.message.localizedCaseInsensitiveContains("could not find the function")
        }
        return false
    }

    func resetKeychainState() { KeychainStore.shared.reset() }

    /// Owner's own config (defaults when no row). Missing RPC => feature off.
    func loadMyKeychain() async {
        guard userID != nil else { resetKeychainState(); return }
        do {
            let env: KeychainEnvelope = try await SupabaseService.client.rpc("get_my_keychain").execute().value
            if env.success == true {
                KeychainStore.shared.setMine(env.keychain ?? .default)
                if let h = user?.handle, !h.isEmpty { KeychainStore.shared.setProfile(h, (env.keychain?.enabled ?? false) ? env.keychain : nil) }
            }
        } catch {
            if Self.keychainFunctionMissing(error) { KeychainStore.shared.setFeatureUnavailable() }
            else { print("loadMyKeychain failed:", error) }
        }
    }

    /// Visitor / owner view of a handle's keychain. nil = none or disabled. Cached per session.
    @discardableResult
    func loadProfileKeychain(handle: String) async -> KeychainConfig? {
        let store = KeychainStore.shared
        guard store.featureAvailable, !handle.isEmpty else { return nil }
        if let hit = store.cached(handle) { return hit }
        do {
            let env: KeychainEnvelope = try await SupabaseService.client
                .rpc("get_profile_keychain", params: HandleParams(p_handle: handle)).execute().value
            let cfg = (env.success == true && env.keychain?.enabled == true) ? env.keychain : nil
            store.setProfile(handle, cfg)
            return cfg
        } catch {
            if Self.keychainFunctionMissing(error) { store.setFeatureUnavailable() }
            return nil          // transient failure: not cached, retried next appearance
        }
    }

    /// Persists a draft. `pendingArt` is uploaded first (replace = new asset, save, then delete old).
    /// `removeCustomArt` deletes the current custom asset after saving a built-in design.
    /// Returns nil on success or a localized error message.
    func saveMyKeychain(_ draft: KeychainConfig, pendingArt: KeychainPreparedArt?, removeCustomArt: Bool) async -> String? {
        let store = KeychainStore.shared
        var cfg = draft
        let oldAsset = store.mine?.customAsset?.id
        var newAssetId: String?
        do {
            if let art = pendingArt {
                let up = try await KeychainArtService.upload(art)
                newAssetId = up.assetId
                cfg.designId = KeychainConfig.customDesignID
                cfg.customAsset = .init(id: up.assetId, path: up.path, width: up.width, height: up.height)
            } else if removeCustomArt, cfg.designId == KeychainConfig.customDesignID {
                cfg.designId = KeychainConfig.defaultDesignID
                cfg.customAsset = nil
            }
            let env: KeychainEnvelope = try await SupabaseService.client
                .rpc("save_my_keychain", params: SaveKeychainParams(p_config: cfg.savePayload())).execute().value
            guard env.success == true else {
                if let n = newAssetId { _ = await KeychainArtService.delete(assetId: n) }
                return keychainServerMessage(env.error)
            }
            let saved = env.keychain ?? cfg
            store.setMine(saved)
            if let h = user?.handle, !h.isEmpty { store.setProfile(h, saved.enabled ? saved : nil) }
            if let old = oldAsset, old != saved.customAsset?.id, (newAssetId != nil || removeCustomArt) {
                _ = await KeychainArtService.delete(assetId: old)
            }
            if removeCustomArt, newAssetId == nil, saved.customAsset == nil { await loadMyKeychain() }
            return nil
        } catch let e as KeychainArtError {
            return e.message(T)
        } catch {
            if Self.keychainFunctionMissing(error) { store.setFeatureUnavailable() }
            if let n = newAssetId { _ = await KeychainArtService.delete(assetId: n) }
            return keychainServerMessage(nil)
        }
    }

    func keychainServerMessage(_ code: String?) -> String {
        switch (code ?? "").lowercased() {
        case "quota_exceeded", "quota": return KeychainArtError.quotaExceeded.message(T)
        case "rate_limited": return KeychainArtError.rateLimited.message(T)
        case "design_locked":
            return T("Mẫu này chưa được mở khoá. Mở khoá trong Phần thưởng & huy hiệu.", "This design is not unlocked yet. Unlock it in Rewards & badges.")
        case "custom_asset_not_ready", "custom_asset_required", "invalid_asset":
            return T("Ảnh tuỳ chỉnh chưa sẵn sàng. Hãy tải lại.", "Your custom art isn't ready. Please upload it again.")
        default: return T("Không lưu được móc khoá. Vui lòng thử lại.", "Couldn't save the keychain. Please try again.")
        }
    }
}
