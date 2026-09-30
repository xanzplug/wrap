import Foundation
import SwiftData
import Observation

/// Keeps this Mac's projects, shots and workspace items in step with the
/// signed-in account on Supabase. Uploads local changes, then downloads
/// anything changed on other Macs. Runs every 30 seconds and on demand.
@Observable
final class SyncEngine {
    static let shared = SyncEngine()

    enum Status: Equatable {
        case idle
        case syncing
        case synced(Date)
        case failed(String)
    }

    enum Table: String, CaseIterable {
        case projects
        case shots
        case workspaceItems = "workspace_items"
    }

    private(set) var status: Status = .idle

    private var accountID: String?
    private var container: ModelContainer?
    private var auth: AuthService?
    private var loop: Task<Void, Never>?
    private var isSyncing = false

    // MARK: Start and stop

    func start(accountID: String, container: ModelContainer, auth: AuthService) {
        guard self.accountID != accountID || loop == nil else { return }
        stop()
        self.accountID = accountID
        self.container = container
        self.auth = auth
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncNow()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        accountID = nil
        container = nil
        auth = nil
        status = .idle
    }

    // MARK: Sync

    func syncNow() async {
        guard !isSyncing, let container, auth != nil, SupabaseConfig.isConfigured else { return }
        isSyncing = true
        status = .syncing
        defer { isSyncing = false }

        let context = container.mainContext
        do {
            try ensureUniqueIDs(context)
            try await pushDeletions()
            try await pushChanges(context)
            try await pullChanges(context)
            try context.save()
            status = .synced(Date())
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Remember that something was deleted here, so it's deleted on other Macs too.
    func recordDeletion(_ table: Table, id: UUID) {
        guard let key = deletionsKey(table) else { return }
        var ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        ids.append(id.uuidString.lowercased())
        UserDefaults.standard.set(ids, forKey: key)
    }

    // MARK: Upload

    private func pushDeletions() async throws {
        for table in Table.allCases {
            guard let key = deletionsKey(table),
                  let ids = UserDefaults.standard.stringArray(forKey: key), !ids.isEmpty
            else { continue }
            let list = ids.joined(separator: ",")
            _ = try await request("PATCH", "/rest/v1/\(table.rawValue)?id=in.(\(list))",
                                  body: ["deleted": true], prefer: "return=minimal")
            // Keep any deletions recorded while we were uploading.
            let remaining = (UserDefaults.standard.stringArray(forKey: key) ?? []).filter { !ids.contains($0) }
            UserDefaults.standard.set(remaining, forKey: key)
        }
    }

    private func pushChanges(_ context: ModelContext) async throws {
        let projects = try context.fetch(FetchDescriptor<Project>())
            .filter { $0.snapshot != $0.syncedSnapshot }
            .map { ($0, $0.snapshot) }
        if !projects.isEmpty {
            let rows: [[String: Any]] = projects.map { project, _ in [
                "id": id(project.remoteID),
                "name": project.name,
                "client_name": project.clientName,
                "is_wrapped": project.isWrapped,
                "created_at": Self.isoFormatter.string(from: project.createdAt),
                "deleted": false,
            ] }
            try await upsert(.projects, rows)
            for (project, snapshot) in projects { project.syncedSnapshot = snapshot }
        }

        let shots = try context.fetch(FetchDescriptor<Shot>())
            .filter { $0.project != nil && $0.snapshot != $0.syncedSnapshot }
            .map { ($0, $0.snapshot) }
        if !shots.isEmpty {
            let rows: [[String: Any]] = shots.map { shot, _ in [
                "id": id(shot.remoteID),
                "project_id": id(shot.project!.remoteID),
                "title": shot.title,
                "is_done": shot.isDone,
                "sort_order": shot.order,
                "outfit": shot.outfit,
                "location": shot.location,
                "notes": shot.notes,
                "deleted": false,
            ] }
            try await upsert(.shots, rows)
            for (shot, snapshot) in shots { shot.syncedSnapshot = snapshot }
        }

        let items = try context.fetch(FetchDescriptor<WorkspaceItem>())
            .filter { $0.project != nil && $0.snapshot != $0.syncedSnapshot }
            .map { ($0, $0.snapshot) }
        if !items.isEmpty {
            let rows: [[String: Any]] = items.map { item, _ in [
                "id": id(item.remoteID),
                "project_id": id(item.project!.remoteID),
                "kind": item.kindRaw,
                "name": item.name,
                "location": item.location,
                "sort_order": item.order,
                "deleted": false,
            ] }
            try await upsert(.workspaceItems, rows)
            for (item, snapshot) in items { item.syncedSnapshot = snapshot }
        }
    }

    private func upsert(_ table: Table, _ rows: [[String: Any]]) async throws {
        _ = try await request("POST", "/rest/v1/\(table.rawValue)", body: rows,
                              prefer: "resolution=merge-duplicates,return=minimal")
    }

    // MARK: Download

    private func pullChanges(_ context: ModelContext) async throws {
        // Projects first, so shots and items can find the project they belong to.
        for table in Table.allCases {
            var path = "/rest/v1/\(table.rawValue)?select=*&order=updated_at.asc"
            if let since = lastPull(table) {
                path += "&updated_at=gt." + encode(since)
            }
            let data = try await request("GET", path)
            let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
            guard !rows.isEmpty else { continue }

            switch table {
            case .projects: try applyProjects(rows, context)
            case .shots: try applyShots(rows, context)
            case .workspaceItems: try applyItems(rows, context)
            }
            if let last = rows.last?["updated_at"] as? String {
                setLastPull(table, last)
            }
        }
    }

    private func applyProjects(_ rows: [[String: Any]], _ context: ModelContext) throws {
        var byID = index(try context.fetch(FetchDescriptor<Project>()))
        for row in rows {
            guard let rid = uuid(row["id"]) else { continue }
            let deleted = row["deleted"] as? Bool ?? false
            let name = row["name"] as? String ?? ""
            let client = row["client_name"] as? String ?? ""
            let wrapped = row["is_wrapped"] as? Bool ?? false

            if let local = byID[rid] {
                if deleted {
                    context.delete(local)
                    byID[rid] = nil
                    continue
                }
                let incoming = [name, client, String(wrapped)].joined(separator: "\u{1F}")
                // Unsent edits here win; they'll upload on the next sync.
                if local.snapshot != local.syncedSnapshot && local.snapshot != incoming { continue }
                local.name = name
                local.clientName = client
                local.isWrapped = wrapped
                local.syncedSnapshot = local.snapshot
            } else if !deleted {
                let created = Self.parseDate(row["created_at"] as? String) ?? Date()
                let project = Project(name: name, clientName: client, createdAt: created, isWrapped: wrapped)
                project.remoteID = rid
                context.insert(project)
                project.syncedSnapshot = project.snapshot
                byID[rid] = project
            }
        }
    }

    private func applyShots(_ rows: [[String: Any]], _ context: ModelContext) throws {
        let projects = index(try context.fetch(FetchDescriptor<Project>()))
        var byID = index(try context.fetch(FetchDescriptor<Shot>()))
        for row in rows {
            guard let rid = uuid(row["id"]) else { continue }
            let deleted = row["deleted"] as? Bool ?? false
            if let local = byID[rid] {
                if deleted {
                    context.delete(local)
                    byID[rid] = nil
                    continue
                }
                if local.snapshot != local.syncedSnapshot { continue }
                apply(row, to: local, projects: projects)
                local.syncedSnapshot = local.snapshot
            } else if !deleted, let pid = uuid(row["project_id"]), projects[pid] != nil {
                let shot = Shot(title: "", order: 0)
                shot.remoteID = rid
                context.insert(shot)
                apply(row, to: shot, projects: projects)
                shot.syncedSnapshot = shot.snapshot
                byID[rid] = shot
            }
        }
    }

    private func apply(_ row: [String: Any], to shot: Shot, projects: [UUID: Project]) {
        shot.title = row["title"] as? String ?? ""
        shot.isDone = row["is_done"] as? Bool ?? false
        shot.order = row["sort_order"] as? Int ?? 0
        shot.outfit = row["outfit"] as? String ?? ""
        shot.location = row["location"] as? String ?? ""
        shot.notes = row["notes"] as? String ?? ""
        if let pid = uuid(row["project_id"]) { shot.project = projects[pid] }
    }

    private func applyItems(_ rows: [[String: Any]], _ context: ModelContext) throws {
        let projects = index(try context.fetch(FetchDescriptor<Project>()))
        var byID = index(try context.fetch(FetchDescriptor<WorkspaceItem>()))
        for row in rows {
            guard let rid = uuid(row["id"]) else { continue }
            let deleted = row["deleted"] as? Bool ?? false
            if let local = byID[rid] {
                if deleted {
                    context.delete(local)
                    byID[rid] = nil
                    continue
                }
                if local.snapshot != local.syncedSnapshot { continue }
                apply(row, to: local, projects: projects)
                local.syncedSnapshot = local.snapshot
            } else if !deleted, let pid = uuid(row["project_id"]), projects[pid] != nil {
                let item = WorkspaceItem(kind: .file, name: "", location: "", order: 0)
                item.remoteID = rid
                context.insert(item)
                apply(row, to: item, projects: projects)
                item.syncedSnapshot = item.snapshot
                byID[rid] = item
            }
        }
    }

    private func apply(_ row: [String: Any], to item: WorkspaceItem, projects: [UUID: Project]) {
        item.kindRaw = row["kind"] as? String ?? WorkspaceItem.Kind.file.rawValue
        item.name = row["name"] as? String ?? ""
        item.location = row["location"] as? String ?? ""
        item.order = row["sort_order"] as? Int ?? 0
        if let pid = uuid(row["project_id"]) { item.project = projects[pid] }
    }

    // MARK: IDs

    /// Items made before sync existed can share the same ID. Give each its own.
    private func ensureUniqueIDs(_ context: ModelContext) throws {
        var seen = Set<UUID>()
        for project in try context.fetch(FetchDescriptor<Project>()) {
            if !seen.insert(project.remoteID).inserted {
                project.remoteID = UUID()
                project.syncedSnapshot = ""
                seen.insert(project.remoteID)
            }
        }
        for shot in try context.fetch(FetchDescriptor<Shot>()) {
            if !seen.insert(shot.remoteID).inserted {
                shot.remoteID = UUID()
                shot.syncedSnapshot = ""
                seen.insert(shot.remoteID)
            }
        }
        for item in try context.fetch(FetchDescriptor<WorkspaceItem>()) {
            if !seen.insert(item.remoteID).inserted {
                item.remoteID = UUID()
                item.syncedSnapshot = ""
                seen.insert(item.remoteID)
            }
        }
    }

    private func index(_ projects: [Project]) -> [UUID: Project] {
        Dictionary(projects.map { ($0.remoteID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func index(_ shots: [Shot]) -> [UUID: Shot] {
        Dictionary(shots.map { ($0.remoteID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func index(_ items: [WorkspaceItem]) -> [UUID: WorkspaceItem] {
        Dictionary(items.map { ($0.remoteID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func id(_ uuid: UUID) -> String { uuid.uuidString.lowercased() }

    private func uuid(_ value: Any?) -> UUID? {
        (value as? String).flatMap(UUID.init(uuidString:))
    }

    // MARK: Saved progress (per account)

    private func deletionsKey(_ table: Table) -> String? {
        accountID.map { "sync.\($0).pendingDeletes.\(table.rawValue)" }
    }

    private func lastPull(_ table: Table) -> String? {
        guard let accountID else { return nil }
        return UserDefaults.standard.string(forKey: "sync.\(accountID).lastPull.\(table.rawValue)")
    }

    private func setLastPull(_ table: Table, _ value: String) {
        guard let accountID else { return }
        UserDefaults.standard.set(value, forKey: "sync.\(accountID).lastPull.\(table.rawValue)")
    }

    // MARK: Network

    private func request(_ method: String, _ path: String, body: Any? = nil, prefer: String? = nil) async throws -> Data {
        guard let auth, let url = URL(string: SupabaseConfig.projectURL + path) else {
            throw AuthError(message: "Sync isn't set up.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(try await auth.validAccessToken())", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthError(message: "Can't reach the server. Changes will sync when you're back online.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = json?["message"] as? String ?? "Sync failed (error \(status))."
            throw AuthError(message: message)
        }
        return data
    }

    private func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._:")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: Dates

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func parseDate(_ string: String?) -> Date? {
        guard var string else { return nil }
        if let date = isoFormatter.date(from: string) { return date }
        // The server sends up to 6 decimal places; trim to 3.
        if let dot = string.firstIndex(of: "."),
           let zone = string[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            let fraction = string[string.index(after: dot)..<zone]
            string.replaceSubrange(string.index(after: dot)..<zone, with: String(fraction.prefix(3)))
            if let date = isoFormatter.date(from: string) { return date }
        }
        let plain = ISO8601DateFormatter()
        return plain.date(from: string)
    }
}
