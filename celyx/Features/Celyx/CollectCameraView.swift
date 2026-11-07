import SwiftUI

/// Figma camera flow:
/// - Star: see `StarCollectCameraView`
/// - Event: "Camera scanning - events" (894:7031) → "Camera scaned - events" (900:8897) → "Screens" (900:9343)
///
/// Stars use the live detector (`StarCollectCameraView`). Events are still a UI prototype:
/// the background is the design's photo and the event is "found" after a short delay.
struct CollectCameraView: View {
    enum Mode: Identifiable, Hashable {
        case star
        case event(SkyEvent)
        var id: String {
            switch self {
            case .star: "star"
            case .event(let event): "event-"+event.id
            }
        }
    }
    private enum Phase { case scanning, found, collected }

    let mode: Mode
    let model: HomeViewModel
    let events: SkyEventStore
    /// `true` when the flow should return all the way to Home.
    let onFinish: (Bool) -> Void
    @State private var phase: Phase = .scanning
    @State private var detection: Task<Void,Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if case .star = mode {
            StarCollectCameraView(model:model) { onFinish(false) }
        } else {
            eventBody
        }
    }

    private var eventBody: some View {
        ZStack(alignment:.bottom) {
            VStack {
                HStack {
                    CelyxBackButton { finish(false) }
                    Spacer()
                }
                .padding(.leading,20)
                Spacer()
            }

            switch phase {
            case .scanning:
                CelyxHintPill(text:"Point your circle at a objects").padding(.bottom,59).transition(.opacity)
            case .found, .collected:
                sheet
                    .padding(.horizontal,6)
                    .padding(.bottom,15)
                    .ignoresSafeArea(edges:.bottom)
                    .transition(.move(edge:.bottom).combined(with:.opacity))
            }
        }
        .background {
            Color.clear
                .overlay { Image("celyx-camera-meteors").resizable().scaledToFill() }
                .clipped()
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        .background(CelyxColor.night)
        .preferredColorScheme(.dark)
        .onAppear(perform:scheduleDetection)
        .onDisappear { detection?.cancel() }
    }

    // MARK: Sheet

    private var sheet: some View {
        ZStack(alignment:.top) {
            CelyxBluePanel(cornerRadius:34)
            CelyxGrabber()
            if case .event(let event) = mode { eventContent(event) }
        }
        .frame(height:194)
    }

    private func eventContent(_ event: SkyEvent) -> some View {
        VStack(spacing:24) {
            HStack(spacing:0) {
                CameraThumbnail(asset:event.cameraThumbnail)
                VStack(alignment:.leading,spacing:4) {
                    HStack(spacing:6) {
                        Image(event.kind.icon).resizable().frame(width:15,height:15).opacity(0.56)
                        Text(event.kind.rawValue).font(.system(size:15)).tracking(-0.23).foregroundStyle(CelyxColor.subtitle)
                    }
                    .frame(height:20)
                    Text(event.title).font(.system(size:17,weight:.semibold)).tracking(-0.43).foregroundStyle(CelyxColor.primaryLabel)
                        .lineLimit(1).minimumScaleFactor(0.8).frame(height:22)
                }
                .padding(.horizontal,16)
                Spacer(minLength:0)
                CelyxCloseButton(action:closeSheet)
            }
            .padding(.horizontal,16).frame(height:64).padding(.top,24).padding(.bottom,8)
            collectButton(title:"Collect this star").padding(.horizontal,16)
        }
    }

    @ViewBuilder private func collectButton(title: String) -> some View {
        if phase == .collected {
            CelyxPillButton(title:"Collected",systemImage:"checkmark",style:.collected) {}
                .allowsHitTesting(false)
        } else {
            CelyxPillButton(title:title,action:collect)
        }
    }

    // MARK: Flow

    private func animate(_ change: @escaping () -> Void) {
        withAnimation(reduceMotion ? nil : .spring(duration:0.4),change)
    }
    private func scheduleDetection() {
        detection?.cancel()
        detection = Task {
            try? await Task.sleep(for:.seconds(1.6))
            guard !Task.isCancelled else { return }
            animate { phase = .found }
        }
    }
    private func collect() {
        if case .event(let event) = mode { events.collect(event) }
        animate { phase = .collected }
    }
    private func closeSheet() {
        switch (phase,mode) {
        case (.collected,.event):
            finish(true)
        default:
            animate { phase = .scanning }
            scheduleDetection()
        }
    }
    private func finish(_ toHome: Bool) {
        detection?.cancel()
        onFinish(toHome)
    }
}

/// Glowing thumbnail from the sheet ("Mask group" with a blurred ellipse mask).
private struct CameraThumbnail: View {
    let asset: String
    var body: some View {
        Color.clear.frame(width:64,height:64)
            .overlay(alignment:.topLeading) {
                Image(asset).resizable().frame(width:259/3,height:250/3).offset(x:-11,y:-10)
            }
            .accessibilityHidden(true)
    }
}

#Preview("Event") { CollectCameraView(mode:.event(SkyEvent.catalogue[0]),model:HomeViewModel(),events:SkyEventStore()) { _ in } }
