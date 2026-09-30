import Foundation

/// Where the delivery service (the Cloudflare Worker) lives.
/// Filled in once the Worker is set up.
enum DeliveryConfig {
    static let serviceURL = "https://YOUR-WORKER.workers.dev"

    static var isConfigured: Bool { !serviceURL.contains("YOUR-WORKER") }
}
