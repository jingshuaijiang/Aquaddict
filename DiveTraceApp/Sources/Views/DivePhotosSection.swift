import SwiftUI
import PhotosUI
import DiveKit

// Photo strip on the dive detail page: take a photo or pick from the library,
// tap a thumbnail to view fullscreen, long-press to delete.
struct DivePhotosSection: View {
    let diveID: UInt32

    @State private var photoStore = PhotoStore.shared
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var viewing: URL?

    private var photos: [URL] { photoStore.photos(for: diveID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(photos, id: \.self) { url in
                        thumb(url)
                    }
                    addButton
                }
            }
        }
        .fullScreenCover(item: $viewing) { url in
            PhotoViewer(url: url) {
                photoStore.delete(url)
                viewing = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                if let image { photoStore.add(image, to: diveID) }
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        photoStore.add(image, to: diveID)
                    }
                }
                pickerItems = []
            }
        }
    }

    private func thumb(_ url: URL) -> some View {
        Button { viewing = url } label: {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Theme.panel2
                }
            }
            .frame(width: 92, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        Menu {
            Button {
                showCamera = true
            } label: {
                Label(loc("拍照", "Take Photo"), systemImage: "camera")
            }
            // PhotosPicker can't live inside Menu directly; overlay trick below
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                Text(loc("添加", "Add")).font(.system(size: 10))
            }
            .foregroundStyle(Theme.accent)
            .frame(width: 92, height: 92)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        } primaryAction: {
            // no-op; the Menu opens on tap
        }
        .overlay(alignment: .bottomTrailing) {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 10,
                         matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.abyss)
                    .padding(7)
                    .background(Theme.accent, in: Circle())
            }
            .offset(x: 6, y: 6)
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// Fullscreen viewer with zoom + delete.
struct PhotoViewer: View {
    let url: URL
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                        .scaleEffect(scale)
                        .gesture(MagnifyGesture()
                            .onChanged { scale = max(1, $0.magnification) }
                            .onEnded { _ in withAnimation { scale = 1 } })
                }
            }
        }
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(16)
        }
        .overlay(alignment: .topTrailing) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.danger)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(16)
        }
    }
}

// UIImagePickerController wrapper for the camera.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera)
            ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
                             UINavigationControllerDelegate {
        let onImage: (UIImage?) -> Void
        init(onImage: @escaping (UIImage?) -> Void) { self.onImage = onImage }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info:
                                   [UIImagePickerController.InfoKey: Any]) {
            onImage(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onImage(nil)
        }
    }
}
