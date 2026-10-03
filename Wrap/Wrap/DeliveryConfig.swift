import Foundation

enum DeliveryConfig {
    static let serviceURL = "https://wrap-delivery.wrapfiles.workers.dev"

    static let maxActiveBytes: Int64 = 900 * 1024 * 1024

    static var isConfigured: Bool { !serviceURL.contains("YOUR-WORKER") }
}
