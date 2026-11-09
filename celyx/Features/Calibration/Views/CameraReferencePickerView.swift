import SwiftUI

/// The first identity is explicitly supplied by the observer, never inferred from
/// a single bright pixel. The resulting yaw correction is shared by this AR session.
struct CameraReferencePickerView: View {
    let capture: CameraReferenceCapture
    let onConfirm: (CatalogStar) -> Bool
    @State private var query = ""
    @State private var selectedID: Int?
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    private var results: [CalibrationCandidate] {
        capture.candidates.filter {
            query.isEmpty || $0.star.title.localizedCaseInsensitiveContains(query)
                || ($0.star.designation?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Confirm reference star").font(.system(size: 22, weight: .bold))
                    Spacer()
                    CelyxCloseButton { dismiss() }
                }
                Text(
                    "Choose the star you recognize in the camera. Confirming its name restores sky alignment. A single light cannot identify itself automatically."
                )
                .font(.system(size: 15)).foregroundStyle(CelyxColor.secondaryLabel)
                Text(
                    "This uses the light captured when you opened this list. A confirmed reference improves matching for the rest of this camera session."
                )
                .font(.system(size: 13)).foregroundStyle(CelyxColor.secondaryLabel)
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Search reference stars", text: $query).autocorrectionDisabled()
                }.padding(14).background(CelyxInfoBox())
                Text("Candidates at the observed height").font(.system(size: 13, weight: .semibold))
                if results.isEmpty {
                    Text(
                        "No matching reference at this height. Check your location or aim at another known star."
                    )
                    .font(.system(size: 13)).foregroundStyle(CelyxColor.secondaryLabel)
                }
                LazyVStack(spacing: 10) {
                    ForEach(results) { candidate in
                        Button {
                            selectedID = candidate.id
                        } label: {
                            HStack(spacing: 12) {
                                StarPortraitView(star: candidate.star).frame(width: 40, height: 40)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(candidate.star.title).font(.system(size: 17, weight: .semibold))
                                    Text(
                                        String(
                                            format: "%@ · %.1f mag · %.0f° up",
                                            candidate.star.designation ?? "Star",
                                            candidate.star.mag, candidate.altitude)
                                    )
                                    .font(.system(size: 12)).foregroundStyle(CelyxColor.secondaryLabel)
                                }
                                Spacer()
                                Image(
                                    systemName: selectedID == candidate.id
                                        ? "checkmark.circle.fill" : "circle")
                            }.padding(12).background(CelyxInfoBox())
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            let selected = capture.candidates.first(where: { $0.id == selectedID })?.star
            CelyxPillButton(
                title: selected.map { "Confirm reference: \($0.title)" } ?? "Choose a known star",
                style: selected == nil ? .disabled : .primary
            ) {
                guard let selected else { return }
                if onConfirm(selected) { dismiss() } else { failed = true }
            }.padding(20)
        }
        .foregroundStyle(CelyxColor.primaryLabel).preferredColorScheme(.dark)
        .alert("Reference expired", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                "Close this list, aim at the light again, then choose its reference. Camera tracking must stay active."
            )
        }
    }
}

#Preview("First reference · one observed light") {
    let star = AppPreviewData.star
    CameraReferencePickerView(
        capture: .init(
            generation: 0, direction: SIMD3(0, 0.5, -0.866), date: AppPreviewData.date,
            location: AppPreviewData.location,
            candidates: [.init(star: star, direction: SIMD3(0, 0.5, -0.866))]), onConfirm: { _ in true }
    )
    .background(CelyxBluePanel(cornerRadius: 34))
}
