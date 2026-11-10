import SwiftUI
import UIKit

/// Fixed story canvas; the page scales this same view that is rendered for export.
struct StarShareCard: View {
    let content: StarShareContent
    let layout: ShareCardLayout
    let photo: UIImage?
    static let size = CGSize(width: 330, height: CGFloat(330) * 16 / 9)

    var body: some View {
        Group {
            if layout == .polaroid { polaroid }
            else { fullPhoto }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 19.556, style: .continuous))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("share-card-\(layout.rawValue)")
        .accessibilityValue(content.collectionNumber.map { "Star \($0)" } ?? "")
        .accessibilityLabel("\(layout.title) share card for \(content.item.star.title). \(content.item.albumLocation). \(content.date). Light Pollution \(content.lightPollution). \(content.note)")
    }

    private var polaroid: some View {
        VStack(spacing: 20) {
            header.frame(width: 290.888, height: 58, alignment: .leading).padding(.top, 19.556)
            VStack(spacing: 7.293) {
                ShareCapturePhoto(photo: photo)
                    .frame(width: 278.747, height: 209.06)
                    .overlay(alignment: .bottomLeading) { captureCaption }
                    .clipShape(RoundedRectangle(cornerRadius: 7.293))
                notePaper.frame(height: 92)
            }
            .padding(.horizontal, 7.293).padding(.top, 7.293).padding(.bottom, 9.778)
            .background(.white, in: RoundedRectangle(cornerRadius: 10.939))
            .compositingGroup()
            .shadow(color: .black.opacity(0.45), radius: 15, y: 8)
            VStack(spacing: 24) {
                HStack(spacing: 13) {
                    if let number = content.collectionNumber { ShareCollectionBadge(number: number) }
                    metadata("Light Pollution", value: content.lightPollution)
                }
                wordmark
            }
            Spacer(minLength: 0)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background { StarAlbumSurface(cornerRadius: 19.556) }
    }

    private var header: some View {
        HStack(spacing: 8.162) {
            StarPortraitView(star: content.item.star).frame(width: 54, height: 54)
                .shadow(color: .white.opacity(0.5), radius: 5)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4.081) {
                    Text(content.item.star.title).font(.system(size: 16.325, weight: .bold))
                        .tracking(0.298).lineLimit(1).minimumScaleFactor(0.5)
                    Text(content.item.albumSubtitle).font(.system(size: 10.203))
                        .tracking(-0.306).lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.horizontal, 6.122).padding(.vertical, 2.041)
                        .background(.white.opacity(0.12), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white, lineWidth: 0.612))
                        .layoutPriority(1)
                }.frame(height: 26.669)
                Text(content.lightTravel).font(.system(size: 10.203)).tracking(-0.1804)
                    .foregroundStyle(Color.white.opacity(0.62)).lineSpacing(3)
                    .lineLimit(2).frame(maxWidth: 183, alignment: .leading)
            }
        }
        .foregroundStyle(.white)
    }

    private var captureCaption: some View {
        HStack(spacing: 7.289) {
            Image("asterra-telescope").resizable().frame(width: 25.51, height: 25.51)
            VStack(alignment: .leading, spacing: 3.644) {
                Text(content.item.albumLocation).font(.system(size: 11.844, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(content.item.albumDateLine).font(.system(size: 10.022))
                    .foregroundStyle(.white.opacity(0.5)).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10.933).padding(.bottom, 14.577).padding(.top, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
    }

    private var notePaper: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3.646).strokeBorder(Color(white: 0.85), lineWidth: 0.912)
                .padding(.top, 7)
            Text(content.note).font(.system(size: 10.939)).italic()
                .underline(color: Color(white: 0.75)).foregroundStyle(Color(white: 0.45))
                .lineSpacing(2).lineLimit(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 10.939).padding(.top, 20).padding(.bottom, 8)
            Text("About This Event").font(.system(size: 10.939, weight: .semibold))
                .foregroundStyle(.black).padding(.horizontal, 3.646).background(.white)
                .padding(.leading, 7.293)
        }.frame(width: 278.747)
    }

    private var wordmark: some View {
        HStack(spacing: 3.778) {
            ZStack {
                Image("asterra-logo-orbit").resizable().frame(width: 23.728, height: 23.728)
                Image("asterra-logo-symbol").resizable().frame(width: 19.8324, height: 38.1302)
                    .rotationEffect(.degrees(45)).offset(x: -6.36, y: 6.39)
            }
            .frame(width: 23.728, height: 23.728).clipped()
            Text("Asterra").font(.system(size: 15.11, weight: .bold)).tracking(-0.6044)
                .foregroundStyle(.white).fixedSize()
        }
        .frame(width: 82, height: 24)
        .accessibilityElement(children: .ignore).accessibilityLabel("Asterra")
    }

    private var fullPhoto: some View {
        ZStack(alignment: .topLeading) {
            ShareCapturePhoto(photo: photo).frame(width: Self.size.width, height: Self.size.height)
                .overlay(.black.opacity(0.5))
            // Match Figma's sRGB interpolation, including the fade to transparency.
            Rectangle().fill(.linearGradient(Gradient(stops: [
                .init(color: Color(hex: 0xA7A4E9), location: 0.002744),
                .init(color: Color(hex: 0x5057CF), location: 0.16446),
                .init(color: Color(hex: 0x14377A).opacity(0.7), location: 0.42087),
                .init(color: Color(hex: 0x0A1C3D).opacity(0), location: 0.77894)
            ]).colorSpace(.device), startPoint: .top, endPoint: .bottom))
            .frame(width: 330.574, height: 190.794).position(x: 164.27, y: 93.357)
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: Color(hex: 0x7783E4).opacity(0.67), location: 0.67308),
                .init(color: Color(hex: 0x5057CF).opacity(0.87), location: 0.81731),
                .init(color: Color(hex: 0x253C86), location: 1)
            ], startPoint: .top, endPoint: .bottom)
            .frame(width: 330.574, height: 257.113).position(x: 165.29, y: 458.1065)
            Image("asterra-card-light").resizable().frame(width: 462, height: 319.177)
                .scaleEffect(x: 1, y: -1).blendMode(.overlay).position(x: 320.5715, y: 58.07)
            HStack(spacing: 20.406) {
                header.frame(width: 215.281, height: 61.111)
                if let number = content.collectionNumber { ShareCollectionBadge(number: number) }
            }
            .frame(width: 296.798, height: 61.111, alignment: .leading).position(x: 165.29, y: 48.5855)
            wordmark.opacity(0.5).position(x: 57.81, y: 338.94)
            VStack(alignment: .leading, spacing: 12.243) {
                HStack(alignment: .top) {
                    metadata("Location", value: content.item.albumLocation)
                    Spacer(minLength: 0)
                    metadata("Light Pollution", value: content.lightPollution)
                        .frame(width: 120.394, alignment: .leading)
                }.frame(height: 40.502)
                HStack(alignment: .top) {
                    metadata("Date", value: content.date)
                    Spacer(minLength: 0)
                    metadata("Time", value: content.time).frame(width: 120.394, alignment: .leading)
                }
            }
            .frame(width: 291.194, height: 94, alignment: .topLeading).position(x: 167.287, y: 412.44)
            Text(content.note).font(.system(size: 12.257)).tracking(-0.0754).lineSpacing(3.2)
                .foregroundStyle(.white).lineLimit(5)
                .frame(maxWidth: .infinity, minHeight: 85, maxHeight: 85, alignment: .topLeading)
                .padding(11.314)
                .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 11.314))
                .overlay(RoundedRectangle(cornerRadius: 11.314).strokeBorder(.white.opacity(0.08), lineWidth: 1))
                .padding([.horizontal, .bottom], 17)
                .frame(width: Self.size.width, height: Self.size.height, alignment: .bottom)
        }
    }

    private func metadata(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3.771) {
            Text(label).font(.system(size: 11.314)).foregroundStyle(.white.opacity(0.5))
            Text(value).font(.system(size: 14.667, weight: .semibold)).tracking(-0.4054)
                .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

private struct ShareCapturePhoto: View {
    let photo: UIImage?
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    Color(white: 0.43).overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "photo").font(.system(size: 23, weight: .light))
                            Text("Photo unavailable").font(.system(size: 10))
                        }.foregroundStyle(.white.opacity(0.65))
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
    }
}
