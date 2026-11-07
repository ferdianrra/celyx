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

extension View {
    /// A native SwiftUI sheet dressed as Figma "Liquid Glass – Regular – Medium" (node 936:1794):
    /// the blue/charcoal glass surface with its 34pt corners, the design's 60×4 grabber instead of the
    /// system drag indicator, and content starting 24pt from the top like the in-app sheets.
    /// It stays a real sheet: detents, swipe-to-dismiss and the floating medium detent are system behaviour.
    func celyxSheet(detents: Set<PresentationDetent> = [.medium,.large]) -> some View {
        safeAreaInset(edge:.top,spacing:0) {
            CelyxGrabber().frame(height:10,alignment:.top).padding(.bottom,14)
        }
        .presentationDetents(detents)
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(34)
        .presentationBackground { CelyxBluePanel(cornerRadius:34) }
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
