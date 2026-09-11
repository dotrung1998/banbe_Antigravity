import Foundation
import Supabase

/// Single shared Supabase client for the app — mirrors src/lib/supabase.js
/// on the web side: same project, same anon (public) key. The anon key is
/// safe to ship in the client; it only ever acts under RLS as `anon` or
/// `authenticated`, exactly like the web app's bundled copy.
///
/// The web app additionally posts to a custom `/api/auth/send-email-link`
/// Vercel function for sign-in/sign-up (so it can attach a nickname and a
/// branded email). That server route has no iOS equivalent yet — this
/// client instead uses Supabase's own built-in `signInWithOTP` magic-link
/// flow, which talks to the same `auth.users` table and is fully
/// interoperable with accounts created via the web app. If the web app's
/// custom link flow needs to be matched exactly (e.g. the same email
/// template), route auth through that same `/api/auth/send-email-link`
/// endpoint from here instead.
enum SupabaseService {
    static let client: SupabaseClient = {
        guard let url = URL(string: Environment.supabaseURL) else {
            fatalError("Invalid Supabase URL: \(Environment.supabaseURL)")
        }
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: Environment.supabaseAnonKey
        )
    }()
}

/// Values copied from the web app's src/lib/supabase.js. In a real deployment,
/// prefer injecting these via an .xcconfig / Info.plist entry per build
/// configuration (Debug/Release) rather than hardcoding — see README.md.
enum Environment {
    static let supabaseURL = "https://ukchdgdnwytretvqjjqu.supabase.co"
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVrY2hkZ2Rud3l0cmV0dnFqanF1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg3MjMyMjYsImV4cCI6MjEwNDI5OTIyNn0.TgyEJLTXTZgCa6ulsseY3JlrdSmEfOgqVPNh0nSgu90"
}
