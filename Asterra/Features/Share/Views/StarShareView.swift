import SwiftUI
import UIKit

struct StarShareView: View {
    let item: GardenCollectionItem
    var collection: HomeViewModel? = nil
    var capturedPhoto: UIImage? = nil
    @State private var photo: UIImage?
    @State private var isPreparing = false
    @State private var isLoadingPhoto = true
    @State private var activity: ShareActivity?
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var layout: ShareCardLayout = .polaroid
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button("Close", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
                .accessibilityLabel("Close share")
                .accessibilityIdentifier("close-star-share")
                Spacer()
            }.padding(.horizontal, 28).padding(.top, 8)

            GeometryReader { geometry in
                let scale = max(0.1, min((geometry.size.width - 64) / StarShareCard.size.width,
                                        (geometry.size.height - 12) / StarShareCard.size.height))
                TabView(selection: $layout) {
                    ForEach(ShareCardLayout.allCases) { option in
                        StarShareCard(content: content, layout: option, photo: photo)
                            .scaleEffect(scale)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .tag(option)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .accessibilityIdentifier("share-layout-pager")
            }

        }
        .foregroundStyle(.white)
        .background {
            GeometryReader { geometry in
                Image("asterra-share-background").resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    .overlay(.black.opacity(0.56))
            }.ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            destinations.overlay(alignment: .top) {
                if isPreparing || message != nil {
                    HStack(spacing: 8) {
                        if isPreparing { ProgressView().tint(.white) }
                        Text(isPreparing ? "Preparing card…" : message ?? "").font(.footnote)
                    }
                    .foregroundStyle(.white).padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .fixedSize().offset(y: -44)
                    .allowsHitTesting(false)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task(id: item.record.photoFilename) {
            isLoadingPhoto = true
            photo = capturedPhoto ?? StarPhotoStore.load(item.record.photoFilename)
            isLoadingPhoto = false
        }
        .task(id: message) {
            guard message != nil else { return }
            do { try await Task.sleep(for: .seconds(2.5)) } catch { return }
            message = nil
        }
        .sheet(item: $activity) { activity in
            StarShareActivitySheet(image: activity.image, fileURL: activity.file?.url)
        }
        .alert("Couldn’t share card", isPresented: Binding(get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private var content: StarShareContent {
        StarShareContent(item: item, collectionNumber: ShareCollectionOrder.number(
            for: item.id, in: collection?.collectionItems ?? []))
    }

    private func perform(_ destination: ShareDestination) {
        guard !isPreparing else { return }
        isPreparing = true
        Task { @MainActor in
            defer { isPreparing = false }
            guard let image = StarShareRenderer.image(content: content, layout: layout, photo: photo) else {
                errorMessage = "The share card couldn’t be created. Please try again."
                return
            }
            switch destination {
            case .copy:
                UIPasteboard.general.image = image
                message = "Card copied"
            case .save:
                do {
                    try await StarSharePhotoSaver.save(image, title: item.star.title)
                    message = "Saved to Photos"
                } catch { errorMessage = error.localizedDescription }
            case .instagram:
                do { try await StarSocialShare.instagram(image) }
                catch { errorMessage = error.localizedDescription }
            case .whatsapp:
                do { activity = ShareActivity(image: image, file: try StarSocialShare.whatsappFile(image)) }
                catch { errorMessage = error.localizedDescription }
            case .more:
                activity = ShareActivity(image: image)
            }
        }
    }

    private var destinations: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(ShareDestination.allCases) { destination in
                Button { perform(destination) } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle().fill(Color(hex: 0x141C2A))
                            if destination == .instagram {
                                Image("asterra-instagram").resizable().frame(width: 51, height: 51).offset(x: -0.5, y: -0.5)
                            } else if destination == .whatsapp {
                                Image("asterra-whatsapp").resizable().frame(width: 44, height: 44).offset(x: -0.5)
                            } else {
                                Image(systemName: destination.symbol).font(.system(size: 17, weight: .regular))
                            }
                        }
                        .frame(width: 44, height: 44).clipShape(Circle())
                        Text(destination.title).font(.system(size: 12, weight: .regular))
                            .multilineTextAlignment(.center).lineLimit(2).frame(height: 30, alignment: .top)
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(isPreparing || isLoadingPhoto)
                .accessibilityLabel(destination.accessibilityTitle)
                .accessibilityIdentifier("share-destination-\(destination.rawValue)")
            }
        }
        .padding(.horizontal, 20).padding(.top, 16)
        .background(Color.black.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.12)).frame(height: 0.5) }
        .padding(.top, 16)
    }
}

private struct ShareActivity: Identifiable {
    let id = UUID()
    let image: UIImage
    var file: WhatsAppShareRequest? = nil
}

private enum ShareDestination: String, CaseIterable, Identifiable {
    case instagram, whatsapp, copy, save, more
    var id: String { rawValue }
    var title: String {
        switch self {
        case .instagram: "Instagram\nStory"
        case .whatsapp: "Send to\nWhatsApp"
        case .copy: "Copy"
        case .save: "Save"
        case .more: "More"
        }
    }
    var accessibilityTitle: String { title.replacingOccurrences(of: "\n", with: " ") }
    var symbol: String {
        switch self {
        case .instagram: "camera"
        case .whatsapp: "phone.bubble"
        case .copy: "document.on.document"
        case .save: "square.and.arrow.down"
        case .more: "square.and.arrow.up"
        }
    }
}

#Preview { StarShareView(item: AppPreviewData.item, collection: AppPreviewData.collectedModel) }
