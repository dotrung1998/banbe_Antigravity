import Foundation
import Supabase

/// Single shared Supabase client for the app — mirrors src/lib/supabase.js
/// on the web side: same project, same anon (public) key. The anon key is
/// safe to ship in the client; it only ever acts under RLS as `anon` or
/// `authenticated`, exactly like the web app's bundled copy.
///
/// Requesting the sign-in code itself goes through the same
/// /api/auth/send-email-code Vercel function the web app uses (see
/// AuthAPIService) rather than Supabase's own `signInWithOTP` — that
/// function delivers via Gmail with no meaningful limit, where Supabase's
/// own built-in mailer is capped at a handful of emails per hour and
/// starts failing with "email rate limit exceeded" almost immediately.
/// Only *verifying* the code (`verifyOTP(type: .email)`) talks to Supabase
/// directly — that's just checking a token, not sending anything, so it
/// isn't subject to that limit and needs no server round trip.
enum SupabaseService {
    static let client: SupabaseClient = {
        guard let url = URL(string: AppConfig.supabaseURL) else {
            fatalError("Invalid Supabase URL: \(AppConfig.supabaseURL)")
        }
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: AppConfig.supabaseAnonKey
        )
    }()
}

/// Values copied from the web app's src/lib/supabase.js. In a real deployment,
/// prefer injecting these via an .xcconfig / Info.plist entry per build
/// configuration (Debug/Release) rather than hardcoding — see README.md.
///
/// Named AppConfig, not Environment — SwiftUI's own `Environment` property
/// wrapper lives in the same module namespace, and a same-named enum here
/// shadows it everywhere in the app (breaks `@Environment(\.dismiss)` etc.
/// with a confusing "cannot be used as an attribute" error).
enum AppConfig {
    static let supabaseURL = "https://ukchdgdnwytretvqjjqu.supabase.co"
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVrY2hkZ2Rud3l0cmV0dnFqanF1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg3MjMyMjYsImV4cCI6MjEwNDI5OTIyNn0.TgyEJLTXTZgCa6ulsseY3JlrdSmEfOgqVPNh0nSgu90"

    /// Base URL of the deployed web app's /api/* Vercel functions — the
    /// same origin AUTH_REDIRECT_URL points at in .env.example. A relative
    /// fetch('/api/...'), which is how the web app calls this, only works
    /// because the web app is served from that origin; iOS has no origin
    /// of its own, so this needs to be an absolute URL to wherever the API
    /// is actually deployed. Update this if that changes.
    static let apiBaseURL = "https://banbe-two.vercel.app"
}
