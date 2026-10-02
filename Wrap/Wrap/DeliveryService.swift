import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers
import UserNotifications

/// A file sent to a client, as the server sees it.
struct Delivery: Identifiable, Equatable {
    let id: String
    let projectID: String?
    let fileName: String
    let sizeBytes: Int64
    let token: String
    let status: String          // uploading, ready, downloaded, expired, cancelled
    let createdAt: Date?
    let expiresAt: Date?
    let downloadedAt: Date?

    var link: URL? { URL(string: "\(DeliveryConfig.serviceURL)/d/\(token)") }
    var isActive: Bool { status == "ready" || status == "downloaded" }
}

/// A file on its way up.
struct UploadProgress: Identifiable, Equatable {
    let id = UUID()
    let fileName: String
    let projectID: String
    var fraction: Double = 0
    var error: String?
}

/// Sends files to clients: uploads them through the delivery service,
/// hands back a link, and keeps the list of deliveries up to date.
@Observable
final class DeliveryService {
    static let shared = DeliveryService()

    private(set) var deliveries: [Delivery] = []
    private(set) var uploads: [UploadProgress] = []
    private(set) var lastError: String?

    var auth: AuthService?

    // MARK: Lists

    func deliveries(for project: Project) -> [Delivery] {
        let id = project.remoteID.uuidString.lowercased()
        return deliveries.filter { $0.projectID == id }
    }

    func uploads(for project: Project) -> [UploadProgress] {
        let id = project.remoteID.uuidString.lowercased()
        return uploads.filter { $0.projectID == id }
    }

    /// Reload the list from the server, and notify about new downloads.
    func refresh() async {
        guard SupabaseConfig.isConfigured, let auth, auth.account != nil else { return }
        do {
            let path = "/rest/v1/deliveries?select=id,project_id,file_name,size_bytes,token,status,created_at,expires_at,downloaded_at"
                + "&status=neq.cancelled&order=created_at.desc&limit=200"
            var request = URLRequest(url: URL(string: SupabaseConfig.projectURL + path)!)
            request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(try await auth.validAccessToken())", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
            let fresh = rows.compactMap(Self.delivery(from:))

            // Tell the user when a client has just downloaded something.
            let before = Dictionary(deliveries.map { ($0.id, $0.status) }, uniquingKeysWith: { a, _ in a })
            for delivery in fresh where AppSettings.downloadAlertsOn
                && delivery.status == "downloaded" && before[delivery.id] == "ready" {
                notify(title: "Your client downloaded it", body: delivery.fileName)
            }
            deliveries = fresh
        } catch {
            // Try again on the next refresh.
        }
    }

    // MARK: Send

    /// Upload a file for this project and copy its link when done.
    func send(_ fileURL: URL, for project: Project) {
        let projectID = project.remoteID.uuidString.lowercased()
        let progress = UploadProgress(fileName: fileURL.lastPathComponent, projectID: projectID)
        uploads.insert(progress, at: 0)
        requestNotificationPermission()

        Task {
            do {
                let link = try await upload(fileURL, projectID: projectID, progressID: progress.id)
                uploads.removeAll { $0.id == progress.id }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link, forType: .string)
                notify(title: "Link ready, and copied", body: fileURL.lastPathComponent)
                await refresh()
            } catch {
                update(progress.id) { $0.error = error.localizedDescription }
            }
        }
    }

    func dismissUpload(_ upload: UploadProgress) {
        uploads.removeAll { $0.id == upload.id }
    }

    func copyLink(_ delivery: Delivery) {
        guard let link = delivery.link else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.absoluteString, forType: .string)
    }

    /// Stop sharing: the link stops working and the file is deleted.
    func cancel(_ delivery: Delivery) async {
        _ = try? await service("DELETE", "/deliveries/\(delivery.id)")
        await refresh()
    }

    /// Supabase's free plan stores files up to 50 MB.
    static let maxFileBytes: Int64 = 50 * 1024 * 1024

    private func upload(_ fileURL: URL, projectID: String, progressID: UUID) async throws -> String {
        guard DeliveryConfig.isConfigured, let auth, let url = URL(string: DeliveryConfig.serviceURL + "/deliveries") else {
            throw AuthError(message: "Delivery isn't connected yet.")
        }
        let hasAccess = fileURL.startAccessingSecurityScopedResource()
        defer { if hasAccess { fileURL.stopAccessingSecurityScopedResource() } }

        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .contentTypeKey])
        if values.isDirectory == true {
            throw AuthError(message: "That's a folder. Zip it first (right-click > Compress), then send the zip.")
        }
        let size = Int64(values.fileSize ?? 0)
        if size > Self.maxFileBytes {
            let readable = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            throw AuthError(message: "That file is \(readable). Files can be up to 50 MB on the free plan.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("Bearer \(try await auth.validAccessToken())", forHTTPHeaderField: "Authorization")
        request.setValue(values.contentType?.preferredMIMEType ?? "application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(fileURL.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "file",
                         forHTTPHeaderField: "X-File-Name")
        request.setValue(projectID, forHTTPHeaderField: "X-Project-Id")
        request.setValue(String(AppSettings.expiryHours), forHTTPHeaderField: "X-Expiry-Hours")

        let tracker = UploadTracker { [weak self] fraction in
            Task { @MainActor in self?.update(progressID) { $0.fraction = fraction } }
        }
        let (body, response): (Data, URLResponse)
        do {
            (body, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL, delegate: tracker)
        } catch {
            throw AuthError(message: "Can't reach the delivery service. Check your internet connection.")
        }
        let result = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status), let link = result["link"] as? String else {
            throw AuthError(message: result["error"] as? String ?? "Upload failed (error \(status)).")
        }
        return link
    }

    // MARK: Network

    private func service(_ method: String, _ path: String, json: [String: Any]? = nil, data: Data? = nil) async throws -> [String: Any] {
        guard let auth, let url = URL(string: DeliveryConfig.serviceURL + path) else {
            throw AuthError(message: "Please log in again.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 600
        request.setValue("Bearer \(try await auth.validAccessToken())", forHTTPHeaderField: "Authorization")
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if let data {
            request.httpBody = data
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        }

        let (body, response): (Data, URLResponse)
        do {
            (body, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthError(message: "Can't reach the delivery service. Check your internet connection.")
        }
        let result = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AuthError(message: result["error"] as? String ?? "Upload failed (error \(status)).")
        }
        return result
    }

    private func update(_ id: UUID, _ change: (inout UploadProgress) -> Void) {
        guard let index = uploads.firstIndex(where: { $0.id == id }) else { return }
        change(&uploads[index])
    }

    // MARK: Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: Parsing

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func date(_ value: Any?) -> Date? {
        guard var string = value as? String else { return nil }
        if let date = isoFormatter.date(from: string) { return date }
        // Trim the server's 6 decimal places to 3.
        if let dot = string.firstIndex(of: "."),
           let zone = string[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            let fraction = String(string[string.index(after: dot)..<zone].prefix(3))
            string.replaceSubrange(string.index(after: dot)..<zone, with: fraction)
            if let date = isoFormatter.date(from: string) { return date }
        }
        return ISO8601DateFormatter().date(from: string)
    }

    private static func delivery(from row: [String: Any]) -> Delivery? {
        guard let id = row["id"] as? String, let token = row["token"] as? String else { return nil }
        let size = (row["size_bytes"] as? NSNumber)?.int64Value ?? 0
        return Delivery(
            id: id,
            projectID: row["project_id"] as? String,
            fileName: row["file_name"] as? String ?? "File",
            sizeBytes: size,
            token: token,
            status: row["status"] as? String ?? "ready",
            createdAt: date(row["created_at"]),
            expiresAt: date(row["expires_at"]),
            downloadedAt: date(row["downloaded_at"])
        )
    }
}

/// Reports how much of an upload has been sent.
private final class UploadTracker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                                totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}
