import SwiftUI

/// Calibration owns these filters; changing them never changes Visible Now.
struct CalibrationCatalogView: View {
    @Bindable var engine: SkyPatternCalibrationService
    let onChoose: (CalibrationCandidate) -> Void
    let onViewAR: () -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var results: [CalibrationCandidate] {
        engine.candidates.filter {
            query.isEmpty || $0.star.title.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        CelyxSheetScrollView {
            VStack(alignment: .leading, spacing: 24) {
                introduction
                filters
                if query.isEmpty, !engine.suggestions.isEmpty { suggestions }
                catalog
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .foregroundStyle(CelyxColor.primaryLabel)
        .preferredColorScheme(.dark)
        .tint(CelyxColor.accent)
    }

    // MARK: Header and filters

    private var navigationBar: some View {
        HStack {
            Color.clear.frame(width: 44, height: 44)
            Spacer()
            Text("Calibration Stars").font(.system(size: 20)).tracking(-0.45)
            Spacer()
            CelyxCloseButton { dismiss() }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose a reference for calibration")
                .font(.system(size: 17, weight: .semibold))
            Text(
                "This list is separate from Visible Now. Positions are predictions, not camera detections. Choose a star you recognize before confirming a single-light calibration."
            )
            .font(.system(size: 13)).foregroundStyle(CelyxColor.secondaryLabel)
            .fixedSize(horizontal: false, vertical: true)
            CelyxPillButton(
                title: "Map this list in AR", systemImage: "camera.viewfinder",
                style: engine.candidates.isEmpty ? .disabled : .primary, action: onViewAR)
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Calibration filters")
            VStack(spacing: 16) {
                filterLabel(
                    "Faintest magnitude", value: String(format: "%.1f", engine.filters.maximumMagnitude))
                Slider(value: $engine.filters.maximumMagnitude, in: 0...5.5, step: 0.5)
                    .accessibilityLabel("Calibration magnitude limit")
                Divider().overlay(.white.opacity(0.07))
                filterLabel(
                    "Minimum altitude", value: String(format: "%.0f°", engine.filters.minimumAltitude))
                Slider(value: $engine.filters.minimumAltitude, in: 0...30, step: 1)
                    .accessibilityLabel("Calibration minimum altitude")
            }
            .padding(16).background(CelyxInfoBox())
            Text(
                "Smaller magnitude numbers mean brighter stars. Daylight and weather do not hide catalog positions here. Calibration still requires a real, steady camera light."
            )
            .font(.system(size: 12)).foregroundStyle(CelyxColor.secondaryLabel)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func filterLabel(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            Text(value).monospacedDigit().foregroundStyle(CelyxColor.secondaryLabel)
        }.font(.system(size: 15))
    }

    // MARK: Catalog

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Possible references near the reticle")
            ForEach(engine.suggestions) { suggestion in
                candidateRow(suggestion.candidate, separation: suggestion.separation)
            }
        }
    }

    private var catalog: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Filtered stars · \(results.count)")
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(CelyxColor.secondaryLabel)
                TextField("Search calibration stars", text: $query)
                    .font(.system(size: 15)).autocorrectionDisabled()
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(CelyxColor.secondaryLabel)
                    }.buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }
            .padding(14).background(CelyxInfoBox())
            if results.isEmpty {
                Text(
                    engine.location == nil
                        ? "Waiting for your location." : "No matching stars. Try another search or filter."
                )
                .font(.system(size: 15)).foregroundStyle(CelyxColor.secondaryLabel)
                .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(results) { candidate in candidateRow(candidate) }
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(
            CelyxColor.secondaryLabel)
    }

    private func candidateRow(_ candidate: CalibrationCandidate, separation: Double? = nil)
        -> some View
    {
        Button {
            onChoose(candidate)
        } label: {
            HStack(spacing: 14) {
                StarPortraitView(star: candidate.star).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.star.title).font(.system(size: 17, weight: .semibold))
                    Text(
                        String(
                            format: "%.1f mag · %.0f° up · %.0f° azimuth", candidate.star.mag,
                            candidate.altitude,
                            candidate.azimuth)
                    )
                    .font(.system(size: 12)).foregroundStyle(CelyxColor.secondaryLabel)
                    if let separation {
                        Text(String(format: "%.1f° from aim · possible identity", separation))
                            .font(.system(size: 12)).foregroundStyle(CelyxColor.secondaryLabel)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "scope").font(.system(size: 17)).foregroundStyle(
                    CelyxColor.secondaryLabel)
            }
            .padding(14).background(CelyxInfoBox()).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Choose as a reference, then confirm its identity in the camera")
    }
}

#Preview("Calibration Stars · filtered list") {
    CalibrationCatalogView(
        engine: SkyPatternCalibrationService(
            catalogue: AppPreviewData.model.stars,
            alignment: AppPreviewData.model.cameraAlignment, preview: true), onChoose: { _ in },
        onViewAR: {}
    )
    .background(CelyxBluePanel(cornerRadius: 34))
}
