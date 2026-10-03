import Foundation

enum SupabaseConfig {
    static let projectURL = "https://xmgurucjbupltfekuyji.supabase.co"
    static let publishableKey = "sb_publishable_LE0_5ce5q4es_Gaz5SzYzQ_HthZXyrl"

    static var isConfigured: Bool {
        !projectURL.contains("YOUR-PROJECT") && !publishableKey.hasPrefix("YOUR-")
    }
}
