import SwiftUI
import UniformTypeIdentifiers

/// The panel on the right of the Shots tab: everything about one shot.
struct ShotDetailView: View {
    @Bindable var shot: Shot
    @State private var choosingImage = false

    var body: some View {
        Form {
            Section("Shot") {
                TextField("Name", text: $shot.title)
                Toggle("Got it", isOn: $shot.isDone)
            }

            Section("Reference") {
                referenceArea
                HStack {
                    Button("Choose Image…") { choosingImage = true }
                    if shot.referenceImage != nil {
                        Button("Remove", role: .destructive) { shot.referenceImage = nil }
                    }
                }
            }

            Section("Details") {
                TextField("Outfit", text: $shot.outfit, prompt: Text("e.g. Black hoodie"))
                TextField("Location", text: $shot.location, prompt: Text("e.g. Football field"))
                TextField("Notes", text: $shot.notes, axis: .vertical)
                    .lineLimit(3...8)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $choosingImage, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                loadImage(from: url)
            }
        }
    }

    /// Shows the reference image, or a box you can drop one onto.
    private var referenceArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                .foregroundStyle(.secondary)

            if let data = shot.referenceImage, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(4)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.title2)
                    Text("Drop a reference image here")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(height: 160)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            return loadImage(from: url)
        }
    }

    @discardableResult
    private func loadImage(from url: URL) -> Bool {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), NSImage(data: data) != nil else {
            return false
        }
        shot.referenceImage = data
        return true
    }
}
