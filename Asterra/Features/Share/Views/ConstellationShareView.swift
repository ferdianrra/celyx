//
//  ConstellationShareView.swift
//  Asterra
//
//  Created by Ahmad Zaki on 18/11/26.
//

import SwiftUI
import UIKit

struct ConstellationShareView: View {
    let entry: ZodiacBookEntry
    let collected: Set<Int>

    @State private var sharedAt = Date()
    @State private var artwork: GardenZodiacArtwork?
    @State private var bounds: CGRect?
    @State private var isPreparing = false
    @State private var activity: ShareCardFile?
    @State private var message: String?
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private var isReady: Bool { artwork != nil && bounds != nil }

    private var card: some View {
        ConstellationShareCard(
            entry: entry,
            collected: collected,
            sharedAt: sharedAt,
            artwork: artwork,
            bounds: bounds
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)

            GeometryReader { geometry in
                let scale = max(
                    0.1,
                    min(
                        (geometry.size.width - 64) / StarShareCard.size.width,
                        (geometry.size.height - 12) / StarShareCard.size.height
                    )
                )

                card
                    .scaleEffect(scale)
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
                    .overlay {
                        if !isReady {
                            ProgressView().tint(.white)
                        }
                    }
            }

            if let message {
                Text(message).font(.footnote)
            }
        }
        .foregroundStyle(.white)
        .background {
            GeometryReader { geometry in
                Image("asterra-share-background")
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
                    .clipped()
                    .overlay(.black.opacity(0.56))
            }
            .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            destinations
        }
        .preferredColorScheme(.dark)
        .task {
            await prepareArtwork()
        }
        .task(id: message) {
            guard message != nil else { return }
            do {
                try await Task.sleep(for: .seconds(2.5))
            } catch { return }
            message = nil
        }
        .sheet(item: $activity) { file in
            StarShareActivitySheet(fileURL: file.url) {
                errorMessage = $0.localizedDescription
            }
        }
        .alert(
            "Couldn’t share constellation",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            if !isReady {
                Button("Retry") {
                    Task { await prepareArtwork() }
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func prepareArtwork() async {
        guard !isReady else { return }

        guard let loaded = await GardenZodiacArtworkStore.shared.load(
            assetNamed: entry.assetName
        ) else {
            errorMessage = "The constellation artwork couldn’t be loaded."
            return
        }

        let points = entry.members.map(\.point)
        let found = await Task.detached(priority: .userInitiated) {
            ZodiacArtBounds.bounds(of: loaded.image, including: points)
        }.value

        guard !Task.isCancelled else { return }
        bounds = found
        artwork = loaded
    }

    private func perform(_ destination: ShareDestination) {
        guard isReady, !isPreparing else { return }
        isPreparing = true

        Task { @MainActor in
            defer { isPreparing = false }

            let renderer = ImageRenderer(content: card)
            renderer.scale = 1080 / StarShareCard.size.width
            renderer.isOpaque = false
            
            guard let image = renderer.uiImage else {
                errorMessage = "The card couldn’t be created. Please try again."
                return
            }

            do {
                switch destination {
                case .copy:
                    UIPasteboard.general.image = image
                    message = "Card copied"
                case .save:
                    try await StarSharePhotoSaver.save(image, title: entry.name)
                    message = "Saved to Photos"
                case .instagram:
                    try await StarSocialShare.instagram(image)
                case .more:
                    activity = try StarSocialShare.pngFile(image)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var destinations: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(ShareDestination.allCases) { destination in
                Button {
                    perform(destination)
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle().fill(Color(hex: 0x141C2A))

                            if destination == .instagram {
                                Image("asterra-instagram")
                                    .resizable()
                                    .frame(width: 51, height: 51)
                                    .offset(x: -0.5, y: -0.5)
                            } else {
                                Image(systemName: destination.symbol)
                                    .font(.system(size: 17))
                            }
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())

                        Text(destination.title)
                            .font(.system(size: 12))
                            .multilineTextAlignment(.center)
                            .frame(height: 30, alignment: .top)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(!isReady || isPreparing)
                .accessibilityLabel(destination.accessibilityTitle)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .background(Color.black.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(height: 0.5)
        }
    }
}

private struct ConstellationShareCard: View {
    let entry: ZodiacBookEntry
    let collected: Set<Int>
    let sharedAt: Date
    let artwork: GardenZodiacArtwork?
    let bounds: CGRect?

    private var count: Int { entry.collectedCount(collected) }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text(entry.name)
                    .font(.system(size: 27, weight: .bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text("Constellation")
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay {
                        Capsule().strokeBorder(.white.opacity(0.6))
                    }
            }

            ZodiacBookArt(
                entry: entry,
                collected: collected,
                revealsAroundStars: true,
                inset: 18,
                preparedArtwork: artwork,
                preparedBounds: bounds,
                isStatic: true
            )
            .frame(height: 285)

            VStack(spacing: 8) {
                Text("\(count)/\(entry.members.count) stars collected")
                    .font(.system(size: 20, weight: .semibold))

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.15))

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: 0xDBD4F7),
                                        Color(hex: 0x7459DF)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: geometry.size.width * CGFloat(
                                    min(1, max(0, entry.progress(collected)))
                                )
                            )
                    }
                }
                .frame(width: 210, height: 5)

                Text(
                    sharedAt.formatted(
                        .dateTime.month(.abbreviated).day().year()
                            .locale(Locale(identifier: "en_US"))
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.65))
            }

            Spacer(minLength: 0)

            HStack(spacing: 3.778) {
                ZStack {
                    Image("asterra-logo-orbit")
                        .resizable()
                        .frame(width: 23.728, height: 23.728)

                    Image("asterra-logo-symbol")
                        .resizable()
                        .frame(width: 19.8324, height: 38.1302)
                        .rotationEffect(.degrees(45))
                        .offset(x: -6.36, y: 6.39)
                }
                .frame(width: 23.728, height: 23.728)
                .clipped()

                Text("Asterra")
                    .font(.system(size: 15.11, weight: .bold))
                    .tracking(-0.6044)
                    .foregroundStyle(.white)
                    .fixedSize()
            }
            .frame(width: 82, height: 24)
        }
        .padding(24)
        .frame(
            width: StarShareCard.size.width,
            height: StarShareCard.size.height
        )
        .foregroundStyle(.white)
        .background {
            StarAlbumSurface(cornerRadius: 19.556)
        }
        .clipShape(RoundedRectangle(cornerRadius: 19.556))
        .environment(\.colorScheme, .dark)
    }
}
