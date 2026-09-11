import Foundation
import Supabase

/// Single shared Supabase client for the app — mirrors src/lib/supabase.js
/// on the web side: same project, same anon (public) key. The anon key is
/// safe to ship in the client; it only ever acts under RLS as `anon` or
/// `authenticated`, exactly like the web app's bundled copy.
///
/// The web app additionally posts to custom /api/auth/* Vercel functions
/// for sign-in/sign-up (a typed 6-digit code by email, or a chosen
/// password — see api/auth/send-email-code.js and signup-password.js).
/// Those server routes have no iOS equivalent yet — this client instead
/// uses Supabase's own built-in email-OTP endpoint directly
/// (`signInWithOTP` to request a code, `verifyOTP(type: .email)` to
/// redeem it — no redirect link involved), which talks to the same
/// `auth.users` table and is fully interoperable with accounts created via
/// the web app. If the web app's code/password flows need to be matched
/// exactly here too (its own branded email, a chosen password), route auth
/// through those same endpoints instead.
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
}
