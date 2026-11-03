import SwiftUI

struct CameraCollectionFlow: View {
    let model: HomeViewModel
    let star: CatalogStar
    let capture: CameraObservationDraft?
    let identificationNote: String?
    let onClose: () -> Void
    @State private var draft: CameraObservationDraft?
    @State private var showsJournal = false
    @State private var captureError = false
    @State private var savedItem: GardenCollectionItem?

    var body: some View {
        NavigationStack {
            StarDetailView(model:model,onClose:onClose,identificationNote:identificationNote,showsFindAction:false,onCameraCollect:{
                if let record = model.collected[star.id], record.photoFilename != nil {
                    savedItem = GardenCollectionItem(star:star,record:record)
                } else if let capture {
                    draft = capture; showsJournal = true
                } else { captureError = true }
            },cameraCollectTitle:model.collected[star.id]?.photoFilename == nil ? "Collect" : "View Your Note")
            .sheet(item:$savedItem) { item in SavedStarNoteView(item:item) }
            .navigationDestination(isPresented:$showsJournal) {
                if let draft { NewStarNoteView(model:model,draft:draft,onSaved:onClose) }
            }
            .alert("Couldn’t capture that",isPresented:$captureError) {
                Button("OK",role:.cancel) {}
            } message: { Text("Close this sheet and tap the light again to capture a new photo.") }
        }
        .tint(.white).preferredColorScheme(.dark)
    }
}

private struct NewStarNoteView: View {
    let model: HomeViewModel
    let draft: CameraObservationDraft
    let onSaved: () -> Void
    @State private var note = ""
    @State private var saveError = false
    @State private var saved = false
    var body: some View {
        StarJournalPage(star:draft.star,date:draft.date,location:draft.location,image:draft.image,
                        identificationNote:draft.identificationNote,note:$note,isEditing:true)
            .navigationTitle("New sky note")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge:.bottom) {
                Button {
                    do { try model.saveCameraObservation(draft,note:note); saved = true }
                    catch { saveError = true }
                } label: {
                    Text("Save Your Star").font(.headline).frame(maxWidth:.infinity).padding(.vertical,16)
                }
                .buttonStyle(.plain).foregroundStyle(.black)
                .background(.white,in:Capsule()).padding(.horizontal,20).padding(.vertical,12)
                .background(.ultraThinMaterial)
            }
            .alert("Saved to Your Galaxy",isPresented:$saved) {
                Button("Done") { onSaved() }
            } message: { Text("Your photo and note are there whenever you want to look back.") }
            .alert("Couldn’t save your star",isPresented:$saveError) {
                Button("Try Again",role:.cancel) {}
            } message: { Text("Your photo is still here. Free up some space and try saving again.") }
    }
}

struct SavedStarNoteView: View {
    let item: GardenCollectionItem
    @State private var note = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            StarJournalPage(star:item.star,date:item.record.date,
                location:ObserverLocation(latitude:item.record.latitude,longitude:item.record.longitude),
                image:StarPhotoStore.load(item.record.photoFilename),identificationNote:item.record.identificationNote,
                note:$note,isEditing:false)
                .navigationTitle("Your sky notes").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear { note = item.record.note ?? "" }
        .tint(.white).preferredColorScheme(.dark)
    }
}

private struct StarJournalPage: View {
    let star: CatalogStar
    let date: Date
    let location: ObserverLocation
    let image: UIImage?
    let identificationNote: String?
    @Binding var note: String
    let isEditing: Bool
    var body: some View {
        ScrollView {
            VStack(spacing:20) {
                StarPortraitView(star:star).frame(width:152,height:152).padding(.top,8)
                VStack(spacing:8) {
                    Label(date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute().locale(Locale(identifier:"en"))),systemImage:"location")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(star.title).font(.title2.bold())
                    Label(star.kind,systemImage:star.isMoon ? "moon.fill" : star.isSun ? "sun.max.fill" : "sparkle")
                        .font(.caption).padding(.horizontal,12).padding(.vertical,5)
                        .background(.white.opacity(0.08),in:Capsule())
                }
                if let image {
                    VStack(alignment:.leading,spacing:12) {
                        Text("Captured Picture").font(.caption).foregroundStyle(.secondary)
                        Text("The circle marks the light you tapped.").font(.caption2).foregroundStyle(.secondary)
                        Image(uiImage:image).resizable().scaledToFit()
                            .frame(maxWidth:.infinity).clipShape(RoundedRectangle(cornerRadius:16))
                    }.journalCard()
                } else {
                    Label("No photo for this memory",systemImage:"photo").font(.subheadline).foregroundStyle(.secondary).journalCard()
                }
                HStack(alignment:.top,spacing:12) {
                    VStack(alignment:.leading,spacing:8) {
                        Text("Where you found it").font(.caption).foregroundStyle(.secondary)
                        Text(location.coordinateLabel).font(.footnote.monospacedDigit())
                    }.frame(maxWidth:.infinity,alignment:.leading).journalCard()
                    VStack(alignment:.leading,spacing:8) {
                        Text("When you saw it").font(.caption).foregroundStyle(.secondary)
                        Text(date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute().locale(Locale(identifier:"en")))).font(.footnote)
                    }.frame(maxWidth:.infinity,alignment:.leading).journalCard()
                }
                VStack(alignment:.leading,spacing:12) {
                    Text("Your notes").font(.subheadline.weight(.medium))
                    if isEditing {
                        TextField("Anything you’d like to remember?",text:$note,axis:.vertical)
                            .lineLimit(3...8).font(.subheadline)
                    } else {
                        Text(note.isEmpty ? "No notes added." : note).font(.subheadline).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth:.infinity,alignment:.leading).journalCard()
                if let identificationNote {
                    Text(identificationNote).font(.caption).foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth:.infinity,alignment:.leading)
                }
            }.padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background {
            ZStack {
                Color(red:0.055,green:0.065,blue:0.10)
                LinearGradient(stops:[.init(color:Color(red:0.34,green:0.33,blue:0.96),location:0),
                    .init(color:Color(red:0.07,green:0.20,blue:0.43),location:0.15),
                    .init(color:.clear,location:0.55)],startPoint:.top,endPoint:.bottom)
            }.ignoresSafeArea()
        }
        .foregroundStyle(.white)
    }
}

private extension View {
    func journalCard() -> some View {
        padding(14).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:20))
            .overlay(RoundedRectangle(cornerRadius:20).stroke(.white.opacity(0.07),lineWidth:0.7))
    }
}
