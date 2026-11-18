import SwiftUI

struct StarAlbumView: View {
    let item: GardenCollectionItem
    var onSaveNote: ((String) -> Void)? = nil
    var onSavePlace: ((String) -> Void)? = nil
    /// Where the collected star sits on screen behind the card, and how to finish once the card has flown there.
    struct FlyHome {
        let target: UnitPoint
        let finish: () -> Void
    }
    var flyHome: FlyHome? = nil
    @State private var flying = false
    @State private var flyX = false
    @State private var flyY = false
    @State private var cardFrame: CGRect = .zero
    @State private var screenSize: CGSize = .zero
    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    @State private var placeName: String?
    @State private var showsExport = false
    @State private var showsInfo = false
    @State private var tilt = CardTilt()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let capturedPhoto: UIImage?
    private var photo: UIImage? { capturedPhoto ?? StarPhotoStore.load(item.record.photoFilename) }
    private var displayedItem: GardenCollectionItem {
        var record = item.record; record.note = note; record.placeName = placeName
        return GardenCollectionItem(star:item.star,record:record)
    }
    init(item: GardenCollectionItem,photo: UIImage? = nil,onSaveNote: ((String) -> Void)? = nil,
         onSavePlace: ((String) -> Void)? = nil,flyHome: FlyHome? = nil) {
        self.item = item; self.onSaveNote = onSaveNote
        self.onSavePlace = onSavePlace; self.flyHome = flyHome
        capturedPhoto = photo
        _note = State(initialValue:item.record.note ?? "")
        _placeName = State(initialValue:item.record.placeName)
    }
    // Figma "Home - Star Preview" (1001:4101 / 1001:3513): the sky stays visible behind a dimmed scrim, a native
    // toolbar (close, info) on top, and one glass card holding the title, the polaroid and Share.
    var body: some View {
        NavigationStack {
            flyingCard
                .padding(.horizontal,20).padding(.top,24).padding(.bottom,14)
                // Scrim: blur the sky (and the home controls) behind, then dim it.
                .background {
                    ZStack { Rectangle().fill(.ultraThinMaterial); Color.black.opacity(0.55) }.ignoresSafeArea()
                        .opacity(flying ? 0 : 1)
                        .onGeometryChange(for:CGSize.self) { $0.size } action:{ screenSize = $0 }
                }
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) {
                        Button("Close",systemImage:"xmark") { close() }
                    }
                    ToolbarItem(placement:.topBarTrailing) {
                        Button("Observation info",systemImage:"info") { showsInfo = true }
                    }
                }
                .toolbarBackgroundVisibility(.hidden,for:.navigationBar)
                .toolbar(flying ? .hidden : .automatic,for:.navigationBar)
        }
        .presentationBackground(.clear)
        .preferredColorScheme(.dark)
        .task {
            guard placeName == nil else { return }
            if let name = await ObservationPlaceName.shared.resolve(latitude:item.record.latitude,longitude:item.record.longitude) {
                placeName = name; onSavePlace?(name)
            }
        }
        .sheet(isPresented:$showsExport) {
            // X on the share screen closes the card too, back to the sky in one tap.
            StarStoryExportView(item:displayedItem,photo:photo) { commitNote(); dismiss() }
        }
        .sheet(isPresented:$showsInfo) {
            NavigationStack {
                Form {
                    LabeledContent("Captured",value:item.albumDate)
                    LabeledContent("Location",value:displayedItem.albumLocation)
                    LabeledContent("Coordinates",value:item.coordinates)
                    if let identification = item.record.identificationNote {
                        Section("Identification") { Text(identification).font(.callout) }
                    }
                }
                .navigationTitle("Observation").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { showsInfo = false } } }
            }.presentationDetents([.medium,.large])
        }
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius:34,style:.continuous)
        return VStack(spacing:0) {
            HStack(spacing:0) {
                StarPortraitView(star:item.star)
                    .frame(width:64,height:64)
                    .shadow(color:Color(red:item.star.rgb.x,green:item.star.rgb.y,blue:item.star.rgb.z).opacity(0.7),radius:11)
                    .accessibilityHidden(true)
                VStack(alignment:.leading,spacing:0) {
                    Text(item.star.title).font(.system(size:28,weight:.bold)).foregroundStyle(CelyxColor.primaryLabel)
                        .lineLimit(1).minimumScaleFactor(0.6).frame(height:34)
                    Text(item.albumSubtitle).font(.system(size:15,weight:.medium)).foregroundStyle(CelyxColor.subtitle).frame(height:20)
                }
                .padding(.horizontal,16)
                Spacer(minLength:0)
            }
            .padding(.horizontal,16).padding(.top,24).padding(.bottom,8)
            .accessibilityElement(children:.combine)

            ScrollView {
                StarAlbumPaper(item:displayedItem,photo:photo,
                               note:onSaveNote == nil ? nil : $note,onCommitNote:commitNote)
                    .padding(20)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft,for:.all)

            Button { commitNote(); showsExport = true } label: {
                Text("Share").font(.system(size:17,weight:.semibold)).foregroundStyle(.black)
                    .frame(maxWidth:.infinity).frame(height:48)
                    .background(Capsule().fill(.white))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal,16).padding(.vertical,8).padding(.bottom,8)
            .accessibilityIdentifier("export-star-story")
        }
        .background {
            ZStack {
                MorphingCardGradient()
                CelyxInnerGlow(shape:shape,layers:.celyxSheet).opacity(0.75)
                HoloFoil(tilt:tilt)
                HoloGlare(tilt:tilt)
            }
            // Figma "background" group: a lavender light rising from the card's floor.
            .overlay(alignment:.bottom) {
                LinearGradient(colors:[.clear,Color(hex:0xC9C2FF,opacity:0.55)],startPoint:.top,endPoint:.bottom)
                    .frame(height:72).blur(radius:10).blendMode(.plusLighter)
            }
            .clipShape(shape)
        }
        // Holographic card (Framer "holographic 3D cards"): flattened into one layer first, so every part
        // (gradient, polaroid, Share, shadow) turns together and nothing lags or ghosts behind it.
        .compositingGroup()
        .shadow(color:.black.opacity(0.45),radius:24,y:8)
        // Lifts a touch toward you while held, like picking the card up.
        .scaleEffect(tilt.touch == nil ? 1 : 1.015)
        .animation(.spring(duration:0.45,bounce:0.12),value:tilt.touch == nil)
        .rotation3DEffect(.degrees(tilt.x*CardTilt.maxAngle),axis:(x:0,y:1,z:0),perspective:0.5)
        .rotation3DEffect(.degrees(-tilt.y*CardTilt.maxAngle),axis:(x:1,y:0,z:0),perspective:0.5)
        // Touch: the card tips toward your finger like a real card pressed at that spot, and springs back.
        .simultaneousGesture(
            DragGesture(minimumDistance:0,coordinateSpace:.local)
                .onChanged { value in
                    guard !reduceMotion, cardFrame.width > 0 else { return }
                    let p = CGPoint(x:(value.location.x/cardFrame.width)*2-1,y:(value.location.y/cardFrame.height)*2-1)
                    tilt.touch = p
                }
                .onEnded { _ in
                    tilt.touch = nil
                }
        )
        .onAppear { if !reduceMotion { tilt.start() } }
        .onDisappear { tilt.stop() }
    }

    /// The card, plus the point of light it turns into when it flies home. The x and y offsets run on
    /// different curves (x eases out, y eases in), which bends the straight move into an arc.
    private var flyingCard: some View {
        let target = flyHome.map { CGPoint(x:$0.target.x*screenSize.width,y:$0.target.y*screenSize.height) } ?? .zero
        let dx = target.x-cardFrame.midX, dy = target.y-cardFrame.midY
        let glow = Color(red:item.star.rgb.x,green:item.star.rgb.y,blue:item.star.rgb.z)
        return ZStack {
            card
                .scaleEffect(flying ? 0.04 : 1)
                .opacity(flying ? 0 : 1)
                .blur(radius:flying ? 12 : 0)
            Circle()
                .fill(RadialGradient(colors:[.white,glow.opacity(0.9),glow.opacity(0)],center:.center,startRadius:0,endRadius:30))
                .frame(width:60,height:60)
                .scaleEffect(flying ? 0.28 : 1.6)
                .opacity(flying ? 1 : 0)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
        .onGeometryChange(for:CGRect.self) { $0.frame(in:.global) } action:{ if !flying { cardFrame = $0 } }
        .offset(x:flyX ? dx : 0)
        .offset(y:flyY ? dy : 0)
    }

    private func close() {
        commitNote()
        guard let flyHome, !flying else { dismiss(); return }
        withAnimation(.easeIn(duration:0.28)) { flying = true }
        withAnimation(.timingCurve(0.2,0.7,0.4,1,duration:0.62)) { flyX = true }
        withAnimation(.timingCurve(0.55,0,0.85,0.4,duration:0.62)) { flyY = true }
        Task {
            try? await Task.sleep(for:.milliseconds(620))
            flyHome.finish()
        }
    }

    private func commitNote() {
        let trimmed = note.trimmingCharacters(in:.whitespacesAndNewlines)
        guard trimmed != (item.record.note ?? "") else { return }
        note = trimmed
        onSaveNote?(trimmed)
    }
}

#Preview("Sky album") { StarAlbumView(item:AppPreviewData.item,onSaveNote:{ _ in }) }
