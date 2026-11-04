import SwiftUI
import CoreText

@MainActor
enum EventTypography {
    private static let registered: Bool = {
        guard let url = try? SkyAssets.url("MinecartLCD",extension:"ttf") else { return false }
        CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil)
        return true
    }()
    static func date(size: CGFloat,relativeTo style: Font.TextStyle = .body) -> Font {
        _ = registered
        return .custom("MinecartLCD",size:size,relativeTo:style)
    }
}

struct AstronomyEventCard: View {
    let event: AstronomyEvent
    @ScaledMetric(relativeTo:.body) private var cardHeight: CGFloat = 132
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment:.leading) {
                RoundedRectangle(cornerRadius:27).fill(LinearGradient(stops:[
                    .init(color:Color(red:0.33,green:0.36,blue:0.95),location:0),
                    .init(color:Color(red:0.05,green:0.17,blue:0.43),location:0.30),
                    .init(color:Color(red:0.045,green:0.055,blue:0.10),location:1)
                ],startPoint:.top,endPoint:.bottom))
                if let name = event.artwork, let url = try? SkyAssets.url(name,extension:"png"), let image = UIImage(contentsOfFile:url.path) {
                    Image(uiImage:image).resizable().scaledToFill()
                        .frame(width:geometry.size.width*0.58,height:geometry.size.height)
                        .clipped()
                        .mask(LinearGradient(stops:[.init(color:.white,location:0),.init(color:.white,location:0.7),.init(color:.clear,location:1)],startPoint:.leading,endPoint:.trailing))
                        .accessibilityHidden(true)
                } else {
                    Image(systemName:event.symbol).font(.system(size:64,weight:.ultraLight))
                        .foregroundStyle(.white.opacity(0.7)).frame(width:geometry.size.width*0.46)
                        .shadow(color:.blue.opacity(0.7),radius:20).accessibilityHidden(true)
                }
                HStack(spacing:0) {
                    Spacer().frame(width:geometry.size.width*0.52)
                    VStack(alignment:.leading,spacing:10) {
                        Text(event.cardTitle).font(.system(size:16,weight:.semibold)).lineLimit(2).minimumScaleFactor(0.8)
                        HStack(alignment:.center,spacing:6) {
                            Text(event.time.formatted(.dateTime.day(.twoDigits))).font(EventTypography.date(size:43,relativeTo:.largeTitle))
                                .minimumScaleFactor(0.7).lineLimit(1)
                            VStack(alignment:.leading,spacing:1) {
                                Text(event.time.formatted(.dateTime.month(.wide).locale(Locale(identifier:"en"))))
                                Text(event.time.formatted(.dateTime.year()))
                            }.font(EventTypography.date(size:16)).lineLimit(1).minimumScaleFactor(0.65)
                        }
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(.trailing,12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius:27))
            .overlay(RoundedRectangle(cornerRadius:27).strokeBorder(LinearGradient(colors:[.white.opacity(0.5),.white.opacity(0.06)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:0.8))
        }
        .frame(height:cardHeight)
        .foregroundStyle(.white)
        .shadow(color:.black.opacity(0.4),radius:13,x:0,y:8)
        .contentShape(RoundedRectangle(cornerRadius:27))
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(event.title+", "+event.time.formatted(date:.complete,time:.shortened))
    }
}
