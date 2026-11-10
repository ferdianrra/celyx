import SwiftUI

extension GardenCollectionItem {
    var albumLocation: String {
        ObservationPlaceName.readableName(city:record.placeName,region:nil)
            ?? ObservationPlaceName.shared.cached(latitude:record.latitude,longitude:record.longitude)
            ?? "Location unavailable"
    }
    var albumSubtitle: String {
        if star.isSolarSystemBody { return star.kind }
        if let code = star.con, let name = ConstellationNames.name(for:code) { return "Star in \(name)" }
        return "Star"
    }
    var albumDate: String {
        record.date.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(Locale(identifier:"en_GB")))
    }
    /// "08 November 2026  · 21:00"
    var albumDateLine: String {
        let locale = Locale(identifier:"en_GB")
        return record.date.formatted(.dateTime.day(.twoDigits).month(.wide).year().locale(locale))+"  · "
            + record.date.formatted(Date.FormatStyle().hour(.twoDigits(amPM:.omitted)).minute(.twoDigits).locale(locale))
    }
    var albumNote: String {
        let note = record.note?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
        return note.isEmpty ? "A sky observation captured with Asterra." : note
    }
}

/// The reference palette: dark center, blue inner glow, violet and lavender rim.
struct StarAlbumSurface: View {
    var cornerRadius: CGFloat = 28
    var body: some View {
        GeometryReader { geometry in
            let shape = RoundedRectangle(cornerRadius:cornerRadius,style:.continuous)
            let scale = min(geometry.size.width/360,geometry.size.height/640)
            shape.fill(Color(hex:0x191820))
                .overlay(shape.stroke(Color(hex:0x062277),lineWidth:110*scale).blur(radius:38*scale))
                .overlay(shape.stroke(Color(hex:0x156BFC),lineWidth:45*scale).blur(radius:24*scale))
                .overlay(shape.stroke(Color(hex:0x7052FF),lineWidth:20*scale).blur(radius:13*scale))
                .overlay(shape.stroke(Color(hex:0xDFCFF8),lineWidth:5*scale).blur(radius:5*scale))
                .clipShape(shape)
                .overlay(shape.strokeBorder(.white.opacity(0.25),lineWidth:1))
        }
    }
}

/// Polaroid from Figma (1001:4101 empty note, 1001:3513 with a note): the photo with its place and time,
/// and the note written straight on the paper. Height follows the note.
struct StarAlbumPaper: View {
    let item: GardenCollectionItem
    let photo: UIImage?
    var limitsNote = false
    /// When set, the note is written on the paper itself: tap "Add notes for this moment" and type.
    var note: Binding<String>? = nil
    var onCommitNote: (() -> Void)? = nil
    @FocusState private var editing: Bool
    @State private var showsField = false

    private var noteText: String {
        (note?.wrappedValue ?? item.record.note ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
    }
    private var showsNoteBox: Bool { showsField || editing || !noteText.isEmpty }

    var body: some View {
        VStack(alignment:.leading,spacing:showsNoteBox ? 8 : 12) {
            photoBlock
            if showsNoteBox { noteBox.transition(.opacity.combined(with:.move(edge:.top))) }
            else if note != nil { addNoteRow.transition(.opacity) }
        }
        .padding(.horizontal,8).padding(.top,8).padding(.bottom,16)
        .background { CelyxPaper() }
        .environment(\.colorScheme,.light)
        .animation(.spring(duration:0.4,bounce:0.15),value:showsNoteBox)
        .onChange(of:editing) { _, isEditing in
            if !isEditing { showsField = false; onCommitNote?() }
        }
    }

    private var photoBlock: some View {
        Color.black
            .aspectRatio(306/230,contentMode:.fit)
            .overlay {
                if let photo {
                    Image(uiImage:photo).resizable().scaledToFill()
                    // Figma "Scroll Edge Effect - Soft / Bottom": the photo softens and darkens under the caption.
                    Image(uiImage:photo).resizable().scaledToFill().blur(radius:12)
                        .mask(LinearGradient(stops:[.init(color:.clear,location:0.55),.init(color:.black,location:0.9)],
                                             startPoint:.top,endPoint:.bottom))
                } else {
                    CelyxColor.night.overlay { Image(systemName:"photo").foregroundStyle(.white.opacity(0.4)) }
                }
            }
            .overlay(alignment:.bottom) {
                LinearGradient(colors:[.clear,.black.opacity(0.72)],startPoint:.top,endPoint:.bottom)
                    .frame(height:91)
            }
            .overlay(alignment:.bottomLeading) {
                HStack(spacing:8) {
                    Image("celyx-icon-telescope").resizable().frame(width:28,height:28)
                    VStack(alignment:.leading,spacing:4) {
                        Text(item.albumLocation).font(.system(size:13,weight:.semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(item.albumDateLine).font(.system(size:11)).foregroundStyle(Color(hex:0xEBEBF5,opacity:0.7))
                    }
                }
                .padding(.horizontal,12).padding(.bottom,16)
            }
            .clipShape(RoundedRectangle(cornerRadius:8,style:.continuous))
            .accessibilityElement(children:.combine)
            .accessibilityLabel("Your photo of \(item.star.title), \(item.albumLocation), \(item.albumDateLine)")
    }

    private var addNoteRow: some View {
        Button {
            showsField = true
            Task { try? await Task.sleep(for:.milliseconds(60)); editing = true }
        } label: {
            Label("Add notes for this moment",systemImage:"pencil")
                .font(.system(size:12,weight:.semibold)).foregroundStyle(.black)
                .frame(maxWidth:.infinity,alignment:.leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius:4).strokeBorder(Color(hex:0x767680,opacity:0.24),lineWidth:1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("add-note")
    }

    /// "About This Moment" tab sitting on the box's top line, then the note in italic.
    private var noteBox: some View {
        VStack(alignment:.leading,spacing:-10) {
            Text("About This Moment").font(.system(size:12,weight:.semibold)).foregroundStyle(.black)
                .padding(.horizontal,4).padding(.vertical,2)
                .background(Color.white)
                .padding(.horizontal,8)
                .zIndex(1)
            Group {
                if let note {
                    TextField("What made this moment special?",text:note,axis:.vertical)
                        .focused($editing)
                        .lineLimit(limitsNote ? 8 : nil)
                        .tint(CelyxColor.accent)
                        .toolbar {
                            ToolbarItemGroup(placement:.keyboard) {
                                Spacer()
                                Button("Done") { editing = false }
                                    .fontWeight(.semibold)
                                    .buttonStyle(.glassProminent)
                                    .tint(CelyxColor.primary)
                            }
                        }
                } else {
                    Text(noteText).lineLimit(limitsNote ? 8 : nil)
                }
            }
            .font(.system(size:12).italic()).lineSpacing(2)
            .foregroundStyle(Color(hex:0x3A3A3C))
            .frame(maxWidth:.infinity,alignment:.leading)
            .fixedSize(horizontal:false,vertical:true)
            .padding(12).padding(.top,4)
            .background(RoundedRectangle(cornerRadius:4).strokeBorder(Color(hex:0x767680,opacity:0.24),lineWidth:1))
        }
    }
}

/// The paper itself (Figma "Texture" effect): warm white with fine grain, a slightly hand-cut edge and the
/// Figma five-step drop shadow. Pure SwiftUI, so it renders the same on screen and in the exported image.
struct CelyxPaper: View {
    var cornerRadius: CGFloat = 12
    var body: some View {
        let shape = HandCutRoundedRectangle(cornerRadius:cornerRadius)
        shape.fill(Color(hex:0xFCFCFA))
            .overlay { PaperGrain().clipShape(shape) }
            .shadow(color:.black.opacity(0.20),radius:2,y:6)
            .shadow(color:.black.opacity(0.16),radius:11.5,y:11)
            .shadow(color:.black.opacity(0.14),radius:21,y:42)
            .shadow(color:.black.opacity(0.08),radius:28.5,y:95)
            .accessibilityHidden(true)
    }
}

/// A rounded rectangle whose outline wanders by about a point, like paper cut by hand.
/// Deterministic (same wobble every time) and resolution independent.
struct HandCutRoundedRectangle: Shape {
    var cornerRadius: CGFloat
    var amount: CGFloat = 0.8

    func path(in rect: CGRect) -> Path {
        let base = RoundedRectangle(cornerRadius:cornerRadius,style:.continuous).path(in:rect.insetBy(dx:amount,dy:amount))
        let center = CGPoint(x:rect.midX,y:rect.midY)
        var points: [CGPoint] = []
        // Sample the outline every ~2pt and push each point along its direction from the centre.
        var distance: CGFloat = 0
        var previous: CGPoint?
        base.forEach { element in
            let end: CGPoint?
            switch element {
            case .move(let p),.line(let p): end = p
            case .quadCurve(let p,_),.curve(let p,_,_): end = p
            case .closeSubpath: end = nil
            }
            guard let end else { return }
            if let start = previous {
                let length = hypot(end.x-start.x,end.y-start.y)
                let steps = max(1,Int(length/2))
                for i in 1...steps {
                    let t = CGFloat(i)/CGFloat(steps)
                    let p = CGPoint(x:start.x+(end.x-start.x)*t,y:start.y+(end.y-start.y)*t)
                    distance += length/CGFloat(steps)
                    points.append(push(p,from:center,by:wobble(distance)))
                }
            } else {
                points.append(push(end,from:center,by:wobble(0)))
            }
            previous = end
        }
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }

    private func push(_ p: CGPoint,from c: CGPoint,by offset: CGFloat) -> CGPoint {
        let dx = p.x-c.x, dy = p.y-c.y
        let length = max(0.001,hypot(dx,dy))
        return CGPoint(x:p.x+dx/length*offset,y:p.y+dy/length*offset)
    }
    /// Smooth noise along the perimeter: a broad drift plus a finer tremble, ±amount.
    private func wobble(_ s: CGFloat) -> CGFloat {
        let broad = sin(s*0.045+1.3)*0.55+sin(s*0.11+4.1)*0.3
        let fine = sin(s*0.63+0.7)*0.1+sin(s*1.37)*0.05
        return (broad+fine)*amount
    }
}

/// Fine paper tooth: a fixed scatter of faint light and dark specks.
private struct PaperGrain: View {
    var body: some View {
        Canvas(rendersAsynchronously:false) { context,size in
            var generator = SeededGenerator(seed:0xC31F)
            let count = Int(size.width*size.height/14)
            for _ in 0..<count {
                let x = CGFloat.random(in:0..<size.width,using:&generator)
                let y = CGFloat.random(in:0..<size.height,using:&generator)
                let dark = Bool.random(using:&generator)
                let alpha = Double.random(in:0.02...0.07,using:&generator)
                context.fill(Path(CGRect(x:x,y:y,width:0.7,height:0.7)),
                             with:.color(dark ? .black.opacity(alpha) : .white.opacity(alpha*1.6)))
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Share image (Figma 1001:3590), 402×874 like the frame (exports 1206×2622): the Figma background export,
/// the title, the polaroid with its note, and "Celyx" at the foot.
struct StarStoryTemplate: View {
    static let size = CGSize(width:402,height:874)
    let item: GardenCollectionItem
    let photo: UIImage?
    var body: some View {
        VStack(spacing:0) {
            VStack(spacing:0) {
                Text(item.star.title).font(.system(size:28,weight:.bold)).lineLimit(1).minimumScaleFactor(0.6)
                Text(item.albumSubtitle).font(.system(size:15,weight:.medium)).foregroundStyle(.white.opacity(0.72))
            }
            .foregroundStyle(Color(hex:0xF5F5F5))
            .padding(.top,164).padding(.bottom,20)
            StarAlbumPaper(item:item,photo:photo,limitsNote:true).padding(.horizontal,40)
            Spacer(minLength:16)
            Text("Asterra").font(.system(size:28,weight:.bold)).foregroundStyle(Color(hex:0xF5F5F5)).padding(.bottom,48)
        }
        .frame(width:Self.size.width,height:Self.size.height)
        .background { Image("celyx-share-bg").resizable() }
        .environment(\.colorScheme,.dark)
    }
}

#Preview("Album paper") {
    StarAlbumPaper(item:AppPreviewData.item,photo:nil).padding(30).background { StarAlbumSurface() }
}
#Preview("Story template") { StarStoryTemplate(item:AppPreviewData.item,photo:nil) }
#Preview("Album palette") { StarAlbumSurface().frame(width:330,height:540).padding() }
