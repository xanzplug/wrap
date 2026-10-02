import SwiftUI
import UniformTypeIdentifiers

/// The Deliveries tab: send a finished file, get a link for your client.
struct DeliveriesView: View {
    let project: Project

    @State private var choosingFile = false
    @State private var dropTargeted = false
    @State private var confirmingCancel: Delivery?

    private var service: DeliveryService { DeliveryService.shared }
    private var deliveries: [Delivery] { service.deliveries(for: project) }
    private var uploads: [UploadProgress] { service.uploads(for: project) }
    private var active: [Delivery] { deliveries.filter(\.isActive) }
    private var past: [Delivery] { deliveries.filter { !$0.isActive && $0.status != "uploading" } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if !DeliveryConfig.isConfigured {
                    HintText("Delivery isn't connected yet. It needs the delivery service set up first.")
                }

                dropZone

                ForEach(uploads) { upload in
                    uploadRow(upload)
                }

                if !active.isEmpty {
                    Eyebrow("Waiting for your client")
                        .padding(.top, 8)
                    VStack(spacing: 0) {
                        ForEach(active) { delivery in
                            deliveryRow(delivery)
                        }
                    }
                }

                if !past.isEmpty {
                    Eyebrow("Finished")
                        .padding(.top, 8)
                    VStack(spacing: 0) {
                        ForEach(past) { delivery in
                            deliveryRow(delivery)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.wrapBackground)
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result {
                service.send(url, for: project)
            }
        }
        .confirmationDialog(
            "Stop sharing \(confirmingCancel?.fileName ?? "this file")?",
            isPresented: Binding(get: { confirmingCancel != nil }, set: { if !$0 { confirmingCancel = nil } })
        ) {
            Button("Stop Sharing and Delete", role: .destructive) {
                if let delivery = confirmingCancel {
                    Task { await service.cancel(delivery) }
                }
            }
        } message: {
            Text("The link stops working and the file is deleted from the server. The file on your Mac isn't touched.")
        }
        .task {
            await service.refresh()
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow("Deliveries")
                Heading(active.isEmpty ? "Nothing waiting" : "\(active.count) link\(active.count == 1 ? "" : "s") out")
                Text("Files delete themselves an hour after your client downloads them, or after \(AppSettings.expiryLabel(AppSettings.expiryHours)).")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.wrapSecondary)
            }
            Spacer()
            Button("Send a File…", systemImage: "paperplane.fill") { choosingFile = true }
                .buttonStyle(.wrapPrimary)
                .disabled(!DeliveryConfig.isConfigured)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.up.doc")
                .font(.system(size: 22))
            Text("Drop a finished export here")
                .font(.system(size: 13, weight: .medium))
            Text("Up to \(ByteCountFormatter.string(fromByteCount: DeliveryService.shared.freeBytes, countStyle: .file)) right now, the space you have free. You'll get a link to send your client, with no account needed on their side.")
                .font(.system(size: 12))
                .foregroundStyle(Color.wrapSecondary)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(dropTargeted ? 0.06 : 0.02)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                .foregroundStyle(dropTargeted ? Color.white.opacity(0.5) : Color.wrapBorder)
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard DeliveryConfig.isConfigured else { return false }
            urls.forEach { service.send($0, for: project) }
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
    }

    private func uploadRow(_ upload: UploadProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(upload.fileName)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Spacer()
                if upload.error == nil {
                    Text("Uploading \(Int(upload.fraction * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.wrapSecondary)
                } else {
                    Button("Dismiss") { service.dismissUpload(upload) }
                        .buttonStyle(.wrapSecondary)
                }
            }
            if let error = upload.error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            } else {
                ThinProgressBar(value: upload.fraction)
            }
        }
        .wrapCard(padding: 14)
    }

    private func deliveryRow(_ delivery: Delivery) -> some View {
        HStack(spacing: 12) {
            Image(systemName: delivery.status == "downloaded" ? "checkmark.circle.fill" : "doc")
                .foregroundStyle(delivery.status == "downloaded" ? Color.white : Color.wrapSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(delivery.fileName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(delivery.isActive ? Color.white : Color.wrapSecondary)
                    .lineLimit(1)
                Text(detail(delivery))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.wrapSecondary)
            }
            Spacer()
            if delivery.isActive {
                Button("Copy Link") { service.copyLink(delivery) }
                    .buttonStyle(.wrapSecondary)
                Button {
                    confirmingCancel = delivery
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.wrapSecondary)
                .help("Stop sharing and delete")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }

    private func detail(_ delivery: Delivery) -> String {
        let size = ByteCountFormatter.string(fromByteCount: delivery.sizeBytes, countStyle: .file)
        switch delivery.status {
        case "ready":
            return "\(size) · link ready · \(expiry(delivery))"
        case "downloaded":
            return "\(size) · downloaded \(relative(delivery.downloadedAt)) · deleting soon"
        case "expired":
            return "\(size) · deleted"
        case "uploading":
            return "\(size) · upload didn't finish"
        default:
            return size
        }
    }

    private func expiry(_ delivery: Delivery) -> String {
        guard let expires = delivery.expiresAt else { return "expires in \(AppSettings.expiryLabel(AppSettings.expiryHours))" }
        let hours = max(0, Int(expires.timeIntervalSinceNow / 3600))
        return hours >= 1 ? "expires in \(hours)h" : "expires soon"
    }

    private func relative(_ date: Date?) -> String {
        guard let date else { return "" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
    }
}
