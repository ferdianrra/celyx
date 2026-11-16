import SwiftUI

// Design tokens and shared building blocks taken from the Figma file "PAI - Celyx" (section "Flow sementara").
extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,red:Double((hex >> 16) & 0xFF)/255,green:Double((hex >> 8) & 0xFF)/255,blue:Double(hex & 0xFF)/255,opacity:opacity)
    }
}

enum CelyxColor {
    static let night = Color(hex:0x07091E)
    static let screen = Color(hex:0x1C1C1E)
    static let panelBase = Color(hex:0x222222)
    static let accent = Color(hex:0x4E58C9)
    /// Body colour of the primary "Start Collecting" button (its 0066E2 inner shadow over the navy floor).
    static let primary = Color(hex:0x1F4FD0)
    static let ready = Color(hex:0x30D158)
    static let secondaryLabel = Color(hex:0xEBEBF5,opacity:0.7)
    static let subtitle = Color(hex:0x8A8A8A)
    static let primaryLabel = Color(hex:0xF5F5F5)
    static let disabledButton = Color(hex:0x5A5A5A)
    static let bellInk = Color(hex:0x181D2E)
}

/// The purple → blue → charcoal "Liquid Glass" surface used by sheets and event cards.
/// The glow is measured in points from the top edge, exactly like the inner shadows in Figma,
/// so short cards and tall sheets get the same band.
struct CelyxBluePanel: View {
    /// Omit the radius to follow the enclosing system sheet's shape.
    var cornerRadius: CGFloat? = nil

    var body: some View {
        if let cornerRadius {
            surface(in:RoundedRectangle(cornerRadius:cornerRadius,style:.continuous))
        } else {
            surface(in:ContainerRelativeShape())
        }
    }

    private func surface<S: InsettableShape>(in shape: S) -> some View {
        shape.fill(CelyxColor.panelBase)
            .overlay(alignment:.top) {
                LinearGradient(stops:[
                    .init(color:Color(hex:0xC6C0FA),location:0),
                    .init(color:Color(hex:0x6272D6),location:0.03),
                    .init(color:Color(hex:0x6474D7),location:0.085),
                    .init(color:Color(hex:0x4C68CB),location:0.13),
                    .init(color:Color(hex:0x2C5BB5),location:0.17),
                    .init(color:Color(hex:0x0F4B9A),location:0.215),
                    .init(color:Color(hex:0x0D3C7F),location:0.26),
                    .init(color:Color(hex:0x11316B),location:0.30),
                    .init(color:Color(hex:0x142B5D),location:0.345),
                    .init(color:Color(hex:0x162852),location:0.385),
                    .init(color:Color(hex:0x19284B),location:0.43),
                    .init(color:Color(hex:0x1C263D),location:0.515),
                    .init(color:Color(hex:0x1F2432),location:0.64),
                    .init(color:Color(hex:0x212429),location:0.77),
                    .init(color:CelyxColor.panelBase,location:1)
                ],startPoint:.top,endPoint:.bottom)
                .frame(height:140)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(LinearGradient(colors:[.white.opacity(0.35),.white.opacity(0.04),.white.opacity(0.14)],startPoint:.top,endPoint:.bottom),lineWidth:1))
            .shadow(color:.black.opacity(0.45),radius:24,x:0,y:8)
    }
}

// MARK: Tinted Liquid Glass (Figma "Fill + Shadow" inner-shadow stacks over the native glass)

/// One Figma inner shadow: colour pulled in from the edge, `y` down, blurred by `blur`, grown by `spread`.
struct CelyxInnerShadow {
    var color: Color
    var y: CGFloat
    var blur: CGFloat
    var spread: CGFloat = 0
}

extension [CelyxInnerShadow] {
    /// "Start Collecting" (998:2696): deep navy floor, blue body, violet rim, white lip.
    static let celyxPrimary: Self = [
        .init(color:Color(hex:0x062277),y:40,blur:96),
        .init(color:Color(hex:0x0066E2),y:24,blur:24),
        .init(color:Color(hex:0x7459DF),y:12,blur:4.5,spread:6),
        .init(color:.white,y:4,blur:4)
    ]
    /// Selected segment of the List / Calendar control (998:2108).
    static let celyxSegment: Self = [
        .init(color:Color(hex:0x062277,opacity:0.4),y:24,blur:96,spread:12),
        .init(color:Color(hex:0x0066E2,opacity:0.6),y:12,blur:24,spread:8),
        .init(color:Color(hex:0x7459DF,opacity:0.8),y:8,blur:6,spread:6),
        .init(color:.white,y:4,blur:4,spread:2)
    ]
    /// Large surfaces: the Sky Events top section and the collected-star card (998:2109, 1001:4101).
    static let celyxSheet: Self = [
        .init(color:Color(hex:0x062277,opacity:0.6),y:40,blur:120,spread:48),
        .init(color:Color(hex:0x0066E2,opacity:0.8),y:24,blur:80,spread:24),
        .init(color:Color(hex:0x7459DF,opacity:0.9),y:12,blur:48,spread:16),
        .init(color:.white.opacity(0.64),y:4,blur:12,spread:2)
    ]
    /// Sky event card background (998:2116 "Rectangle 43").
    static let celyxCard: Self = [
        .init(color:Color(hex:0x062277,opacity:0.6),y:60,blur:60,spread:20),
        .init(color:Color(hex:0x0066E2,opacity:0.8),y:40,blur:40,spread:8),
        .init(color:Color(hex:0x7459DF),y:20,blur:20,spread:4),
        .init(color:.white,y:8,blur:8,spread:2)
    ]
    /// Green "Collect Rigel" pill (1000:3473).
    static let celyxCollect: Self = [
        .init(color:Color(hex:0x0B3215),y:32,blur:40),
        .init(color:Color(hex:0x30D158),y:20,blur:24),
        .init(color:.white,y:6,blur:2)
    ]
}

/// Paints a stack of Figma inner shadows inside `shape`, in order. Works in `ImageRenderer` too.
struct CelyxInnerGlow<S: InsettableShape>: View {
    let shape: S
    let layers: [CelyxInnerShadow]
    var base: Color? = nil

    var body: some View {
        Canvas { context,size in
            let rect = CGRect(origin:.zero,size:size)
            context.clip(to:shape.path(in:rect))
            if let base { context.fill(Path(rect),with:.color(base)) }
            for layer in layers {
                context.drawLayer { layerContext in
                    // Figma blur radius ≈ 2σ.
                    layerContext.addFilter(.blur(radius:layer.blur/2))
                    let pad = layer.blur*2+abs(layer.y)+layer.spread+4
                    var path = Path(rect.insetBy(dx:-pad,dy:-pad))
                    path.addPath(shape.inset(by:layer.spread).path(in:rect).offsetBy(dx:0,dy:layer.y))
                    layerContext.fill(path,with:.color(layer.color),style:FillStyle(eoFill:true))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Figma's two layers, in Figma's order: "Fill + Shadow" (the inner-shadow gradient) underneath, and the
    /// native Liquid Glass "Glass Effect" on top of it, so the glass refracts and softens the colour.
    func celyxGlass<S: InsettableShape>(_ glow: [CelyxInnerShadow],in shape: S) -> some View {
        glassEffect(.regular,in:shape)
            .background { CelyxInnerGlow(shape:shape,layers:glow) }
    }
}

/// The primary gradient under Apple's interactive Liquid Glass.
struct CelyxTintedGlassButtonStyle: ButtonStyle {
    var glow: [CelyxInnerShadow] = .celyxPrimary
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassEffect(.clear.interactive(), in: Capsule())
            .background { CelyxInnerGlow(shape: Capsule(), layers: glow) }
            .environment(\.colorScheme,.dark)
    }
}

/// Segmented control from Figma (998:2108): grey track, tinted-glass thumb, SF Symbol + title per segment.
/// The system segmented picker can't show a symbol next to its title or take this thumb, so it is drawn here;
/// VoiceOver still gets the native segmented control through `accessibilityRepresentation`.
struct CelyxSegmentedControl<Value: Hashable>: View {
    struct Segment {
        let value: Value
        let title: String
        let systemImage: String
    }
    @Binding var selection: Value
    let segments: [Segment]
    @Namespace private var thumb

    var body: some View {
        HStack(spacing:4) {
            ForEach(segments,id:\.value) { segment in
                let isOn = segment.value == selection
                Button {
                    guard !isOn else { return }
                    withAnimation(.spring(duration:0.42,bounce:0.2)) { selection = segment.value }
                } label: {
                    Label(segment.title,systemImage:segment.systemImage)
                        .font(.system(size:13.33,weight:isOn ? .semibold : .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth:.infinity).frame(height:34)
                        .contentShape(Capsule())
                }
                .accessibilityLabel(segment.title)
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .buttonStyle(.plain)
                .background {
                    if isOn {
                        // Figma export "SegmentedControlActive" (glass over the segment gradient), incl. its rim glow.
                        Image("celyx-segment-active").resizable()
                            .padding(.horizontal,-8.5).padding(.vertical,-2)
                            .matchedGeometryEffect(id:"thumb",in:thumb)
                    }
                }
            }
        }
        .padding(2)
        .sensoryFeedback(.selection,trigger:selection)
        .background(Capsule().fill(Color(hex:0x767680,opacity:0.24)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("View")
    }
}

/// Subtle frosted box (`Action Group` in Figma): 1% white fill with an 8% white inner glow.
struct CelyxInfoBox: View {
    var cornerRadius: CGFloat = 16
    var body: some View {
        let shape = RoundedRectangle(cornerRadius:cornerRadius,style:.continuous)
        shape.fill(Color(hex:0x2A2A2D))
            .overlay(shape.strokeBorder(.white.opacity(0.07),lineWidth:1).blur(radius:2).clipShape(shape))
    }
}

/// Circular / capsule Liquid Glass control used for every icon button in the design.
struct CelyxGlassButton<Label: View>: View {
    var width: CGFloat = 48
    var height: CGFloat = 48
    var tint: Color? = nil
    let action: () -> Void
    @ViewBuilder var label: Label
    var body: some View {
        Button(action:action) {
            label.frame(width:width,height:height).contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(tint.map { Glass.regular.tint($0).interactive() } ?? .regular.interactive(),in:Capsule())
    }
}

/// Large pill button (`Button` component 520:3061): 48pt tall, 17pt semibold label.
struct CelyxPillButton: View {
    enum Style { case primary, collected, disabled }
    let title: String
    var systemImage: String? = nil
    var style: Style = .primary
    let action: () -> Void
    var body: some View {
        Button(action:action) {
            HStack(spacing:4) {
                if let systemImage { Image(systemName:systemImage).font(.system(size:17,weight:.semibold)) }
                Text(title).font(.system(size:17,weight:.semibold)).tracking(-0.43)
            }
            .foregroundStyle(style == .primary ? .black : .white)
            .frame(maxWidth:.infinity).frame(height:48)
            .background(Capsule().fill(style == .primary ? .white : style == .collected ? CelyxColor.accent : CelyxColor.disabledButton))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(style == .disabled)
    }
}

/// 60×4 sheet grabber.
struct CelyxGrabber: View {
    var body: some View {
        Capsule().fill(.white.opacity(0.4)).frame(width:60,height:4).padding(.top,6).frame(maxWidth:.infinity)
    }
}

/// Glass "xmark" button used on every bottom sheet (44pt).
struct CelyxCloseButton: View {
    let action: () -> Void
    var body: some View {
        CelyxGlassButton(width:44,height:44,action:action) {
            Image(systemName:"xmark").font(.system(size:17,weight:.medium)).foregroundStyle(CelyxColor.primaryLabel)
        }
        .accessibilityLabel("Close")
    }
}

/// Glass back chevron used on the calendar, event and camera screens (48pt).
struct CelyxBackButton: View {
    let action: () -> Void
    var body: some View {
        CelyxGlassButton(action:action) {
            Image(systemName:"chevron.left").font(.system(size:20,weight:.regular)).foregroundStyle(.white)
        }
        .accessibilityLabel("Back")
    }
}

/// Background of the calendar and event screens: #1C1C1E with the purple/blue wash at 50%.
struct CelyxScreenWash: View {
    var body: some View {
        CelyxColor.screen.overlay(alignment:.top) {
            LinearGradient(stops:[
                .init(color:Color(hex:0x5F54D5),location:0),
                .init(color:Color(hex:0x254FC0),location:0.322),
                .init(color:.black.opacity(0),location:0.644)
            ],startPoint:.top,endPoint:.bottom)
            .opacity(0.5)
            .frame(height:874)
        }
        .ignoresSafeArea()
    }
}

/// Scrolls the artwork with the content and holds its top edge in place during pull-down bounce.
struct CelyxSheetScrollView<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var topBounce: CGFloat = 0

    var body: some View {
        ScrollView {
            content.background(alignment: .top) {
                artwork.offset(y: -topBounce)
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
        } action: { _, bounce in
            topBounce = bounce
        }
    }

    private var artwork: some View {
        GeometryReader { geometry in
            Image("background/background-sheet")
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .clipped()
                .overlay {
                    Color.clear
                        .glassEffect(.identity, in: .rect(cornerRadius: 32))
                }
        }
        .frame(height: 230)
        .mask {
            LinearGradient(
                stops: [.init(color: .white, location: 0),
                        .init(color: .white, location: 0.5),
                        .init(color: .clear, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Native presentation with the calibration sheet's existing grabber.
    func celyxSheet(detents: Set<PresentationDetent> = [.medium,.large]) -> some View {
        safeAreaInset(edge:.top,spacing:0) {
            CelyxGrabber().frame(height:10,alignment:.top).padding(.bottom,14)
        }
        .presentationDetents(detents)
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(.dark)
    }
}

#Preview("Blue panel") {
    CelyxBluePanel(cornerRadius:34).frame(height:240).padding().background(.black)
        .preferredColorScheme(.dark)
}

#Preview("Info box") {
    CelyxInfoBox().frame(height:120).padding().background(.black)
        .preferredColorScheme(.dark)
}

#Preview("Glass button") {
    CelyxGlassButton(action:{}) { Image(systemName:"scope").foregroundStyle(.white) }.padding().background(.black)
        .preferredColorScheme(.dark)
}

#Preview("Pill buttons") {
    VStack { CelyxPillButton(title:"Continue",style:.primary) {}; CelyxPillButton(title:"Collected",style:.collected) {}; CelyxPillButton(title:"Waiting",style:.disabled) {} }.padding().background(.black)
        .preferredColorScheme(.dark)
}

#Preview("Grabber") {
    CelyxGrabber().padding().background(.black)
        .preferredColorScheme(.dark)
}

#Preview("Close button") {
    CelyxCloseButton {}.padding().background(.black)
        .preferredColorScheme(.dark)
}

#Preview("Back button") {
    CelyxBackButton {}.padding().background(.black)
        .preferredColorScheme(.dark)
}

#Preview("Screen wash") {
    CelyxScreenWash()
        .preferredColorScheme(.dark)
}
