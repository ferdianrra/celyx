import SwiftUI

/// Figma "Detail Event still not available" (900:7510) and "Detail Event available" (900:8805).
struct SkyEventDetailView: View {
    let event: SkyEvent
    let store: SkyEventStore
    let onCollect: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TimelineView(.everyMinute) { context in
            ScrollView {
                VStack(spacing:0) {
                    navigationBar
                    VStack(spacing:12) {
                        header
                        infoRow(symbol:"calendar",label:"Date",value:event.detailDate)
                        infoRow(symbol:"eye",label:"Best Viewing",value:event.viewingTime)
                        infoRow(symbol:"safari",label:"Direction",value:event.direction)
                        aboutBox
                        tipsBox
                        actionButton(isOpen:event.isOpen(at:context.date))
                    }
                    .padding(.horizontal,20).padding(.top,10).padding(.bottom,49)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(CelyxScreenWash())
        .toolbar(.hidden,for:.navigationBar)
        .preferredColorScheme(.dark)
    }

    private var navigationBar: some View {
        HStack {
            CelyxBackButton { dismiss() }
            Spacer()
            Text("Events").font(.system(size:20)).tracking(-0.45).foregroundStyle(.white)
            Spacer()
            CelyxGlassButton(action:{ store.toggleReminder(event) }) {
                Image(systemName:store.reminders.contains(event.id) ? "bell.fill" : "bell").font(.system(size:20)).foregroundStyle(.white)
            }
            .accessibilityLabel(store.reminders.contains(event.id) ? "Turn off reminder" : "Remind me")
        }
        .padding(.horizontal,20).padding(.vertical,12)
    }

    private var header: some View {
        VStack(spacing:12) {
            Image(event.hero).resizable().scaledToFit()
                .frame(width:152,height:132)
                .padding(12)
                .accessibilityHidden(true)
            VStack(spacing:4) {
                SkyEventKindLabel(kind:event.kind)
                Text(event.title).font(.system(size:17,weight:.semibold)).tracking(-0.43).foregroundStyle(.white).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth:.infinity)
    }

    private func infoRow(symbol: String,label: String,value: String) -> some View {
        HStack(spacing:12) {
            Image(systemName:symbol).font(.system(size:15)).foregroundStyle(.white).frame(width:30,height:20)
            VStack(alignment:.leading,spacing:6) {
                Text(label).font(.system(size:12)).foregroundStyle(.white.opacity(0.5)).frame(height:16)
                Text(value).font(.system(size:15,weight:.semibold)).tracking(-0.23).foregroundStyle(.white).frame(height:20)
            }
            Spacer(minLength:0)
        }
        .padding(16)
        .frame(height:74)
        .background(CelyxInfoBox())
        .accessibilityElement(children:.combine)
    }

    private var aboutBox: some View {
        VStack(alignment:.leading,spacing:6) {
            Text("About This Event").font(.system(size:12)).foregroundStyle(.white.opacity(0.5)).frame(height:16)
            Text(event.about).font(.system(size:15)).tracking(-0.23).lineSpacing(2).foregroundStyle(.white)
                .fixedSize(horizontal:false,vertical:true)
        }
        .frame(maxWidth:.infinity,alignment:.leading)
        .padding(16)
        .background(CelyxInfoBox())
    }

    private var tipsBox: some View {
        VStack(spacing:8) {
            HStack(spacing:4) {
                Image(systemName:"lightbulb.max")
                Text("Viewing Tips")
            }
            .font(.system(size:12)).foregroundStyle(.white.opacity(0.5)).frame(height:16)
            Text(event.tips).font(.system(size:15)).tracking(-0.23).lineSpacing(2).foregroundStyle(.white)
                .fixedSize(horizontal:false,vertical:true)
                .frame(maxWidth:.infinity,alignment:.leading)
                .padding(16)
                .background {
                    let shape = RoundedRectangle(cornerRadius:16,style:.continuous)
                    shape.fill(.white.opacity(0.05))
                        .overlay(shape.strokeBorder(Color(hex:0x747480,opacity:0.08),lineWidth:1))
                        .overlay(shape.strokeBorder(Color(hex:0x0066E2,opacity:0.26),lineWidth:6).blur(radius:8).clipShape(shape))
                }
        }
        .padding(.top,12).padding([.horizontal,.bottom],4)
        .background(
            LinearGradient(stops:[
                .init(color:Color(hex:0x4F59CB),location:0),
                .init(color:Color(hex:0x173F98),location:0.29),
                .init(color:Color(hex:0x151C3F),location:1)
            ],startPoint:.top,endPoint:.bottom),
            in:RoundedRectangle(cornerRadius:16,style:.continuous))
    }

    @ViewBuilder private func actionButton(isOpen: Bool) -> some View {
        if store.collected.contains(event.id) {
            CelyxPillButton(title:"Collected",systemImage:"checkmark",style:.collected) {}
                .allowsHitTesting(false)
        } else if isOpen {
            CelyxPillButton(title:"Collect this event",action:onCollect)
        } else {
            CelyxPillButton(title:event.opensLabel,style:.disabled) {}
        }
    }
}

#Preview("Not open yet") {
    SkyEventDetailView(event:SkyEvent.catalogue[0],store:SkyEventStore()) {}
}
