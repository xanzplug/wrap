import Foundation

/// Where the delivery service (the Cloudflare Worker) lives.
/// Filled in once the Worker is set up.
enum DeliveryConfig {
    static let serviceURL = "https://wrap-delivery.wrapfiles.workers.dev"

    /// Space for files still waiting to be downloaded (matches the delivery service).
    static let maxActiveBytes: Int64 = 900 * 1024 * 1024

    static var isConfigured: Bool { !serviceURL.contains("YOUR-WORKER") }
}
