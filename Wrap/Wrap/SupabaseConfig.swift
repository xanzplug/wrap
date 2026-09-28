import Foundation

/// Where Wrap's accounts live. Fill these in from your Supabase project:
/// Project Settings > API (or "Connect") in the Supabase dashboard.
/// The publishable key is meant to be public, so it's fine in the code.
enum SupabaseConfig {
    static let projectURL = "https://xmgurucjbupltfekuyji.supabase.co"
    static let publishableKey = "sb_publishable_LE0_5ce5q4es_Gaz5SzYzQ_HthZXyrl"

    static var isConfigured: Bool {
        !projectURL.contains("YOUR-PROJECT") && !publishableKey.hasPrefix("YOUR-")
    }
}
