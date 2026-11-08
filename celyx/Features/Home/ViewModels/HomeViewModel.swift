//
//  HomeViewModel.swift
//  celyx
//
//  Created by Ferdiansyah Annora on 02/11/26.
//
import SwiftUI
import Observation
import simd

@MainActor @Observable
final class HomeViewModel {
    var scene = SkySceneState()
    let cameraAlignment: CameraSkyAlignment
    var mode: LookMode = .touch
    var activeSheet: HomeSheet?
    var query = ""
    var errorMessage: String?
    var selectedStar: CatalogStar?
    var finderTarget: CatalogStar?
    var showsStarCamera = false
    var showsVisibleSkyAR = false
    private var pendingVisibleSkyAR = false
    private(set) var showsGarden = false
    private(set) var gardenProgress: Double = 0
    private(set) var isGardenTransitioning = false
    private let gardenFlight = SkyCameraFlight()
    private var gardenReturnPose: SkyCameraPose?
    var collectionItems: [GardenCollectionItem] { GardenCollectionItem.resolve(records:collected,catalogue:stars) }
    private var pendingCollectionCamera = false
    private var pendingFinderTarget: CatalogStar?
    private var pendingDetailStar: CatalogStar?
    private var returnCameraPose: SkyCameraPose?
    private let cameraFlight = SkyCameraFlight()
    private(set) var detailVisualProgress: Double = 0
    private(set) var isCameraTransitioning = false
    var isInspectingStar: Bool { returnCameraPose != nil }
    var visibilityFilters = VisibilityFilters() { didSet { refreshVisibleObjects() } }
    var quality: SkyQuality = .city { didSet { refreshSky() } }
    var onlineConditions = false {
        didSet {
            defaults.set(onlineConditions,forKey:"onlineConditions")
            if onlineConditions { refreshAtmosphere(force:true) }
            else { weatherTask?.cancel(); atmosphere = Atmosphere(); refreshSky() }
        }
    }
    var manualLatitude = ""
    var manualLongitude = ""
    private(set) var location: ObserverLocation?
    private(set) var locationStatus = "Waiting for location access"
    private(set) var observations: [StarObservation] = []
    private(set) var stars: [CatalogStar] = []
    private(set) var constellationFigures: [ConstellationFigure] = []
    var visibleConstellationIDs: Set<String> { Set(displayedObservations.compactMap { $0.star.con }) }
    private(set) var snapshot: SkySnapshot?
    private(set) var atmosphere = Atmosphere()
    private(set) var isLoadingAtmosphere = false
    private(set) var collected: [Int:CollectedStar] = [:] {
        didSet { scene.collectedIDs = Set(collected.keys) }
    }
    private(set) var clock = Date()
    private(set) var motionStatus = "Touch"
    private(set) var isMotionCalibrating = false
    private(set) var motionCalibrationProgress: Double = 0
    private(set) var motionCalibrationStage: MotionCalibrationStage = .location
    private var constellationNames: [String:String] = [:]
    private let motion = MotionService()
    private let gps = LocationService()
    private let defaults: UserDefaults
    private let fixedDate: Date?
    private var clockTask: Task<Void,Never>?
    private var weatherTask: Task<Void,Never>?
    private var isRunning = false
    private var dragOrigin: (Double,Double)?
    private var zoomOrigin: Double?

    init(location: ObserverLocation? = nil, date: Date? = nil, defaults: UserDefaults = .standard) {
        cameraAlignment = CameraSkyAlignment(defaults:defaults)
        self.defaults = defaults; fixedDate = date ?? (ProcessInfo.processInfo.arguments.contains("-ui-testing") ? Date(timeIntervalSince1970:1793633400 - (ProcessInfo.processInfo.arguments.contains("-ui-testing-daytime") ? 10*3600 : 0)) : nil)
        self.location = location
        onlineConditions = defaults.bool(forKey:"onlineConditions")
        mode = .touch
        if let data = defaults.data(forKey:"collectedStars"), let values = try? JSONDecoder().decode([CollectedStar].self,from:data) {
            collected = Dictionary(values.map { ($0.id,$0) },uniquingKeysWith: { first,_ in first })
        }
        scene.collectedIDs = Set(collected.keys)
        scene.showsMilkyWay = false
        scene.showsConstellations = false
        scene.showsConstellationFigures = false
        do {
            stars = try SkyAssets.stars()
            constellationFigures = try ConstellationFigure.load()
            let data = try Data(contentsOf:SkyAssets.url("constellations",extension:"json"))
            let entries = try JSONDecoder().decode([String:Constellation].self,from:data)
            constellationNames = entries.compactMapValues(\.name)
        } catch { errorMessage = "We couldn’t load the star catalog: \(error.localizedDescription)" }
        if self.location == nil, ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            self.location = ObserverLocation(latitude:-6.1754,longitude:106.8272,isManual:true)
        }
        if let p = self.location { locationStatus = p.isManual ? "Custom coordinates" : "Location on" }
        gps.onLocation = { [weak self] value in
            guard let self, self.isRunning else { return }
            let changed = self.location.map { abs($0.latitude-value.latitude)+abs($0.longitude-value.longitude) > 0.01 } ?? true
            self.location = value; self.locationStatus = "GPS ±\(Int(value.accuracy)) m"
            if changed { self.atmosphere = Atmosphere() }
            self.refreshSky()
            if changed { self.refreshAtmosphere(force:true) }
        }
        gps.onStatus = { [weak self] in self?.locationStatus = $0 }
        motion.onCalibration = { [weak self] ready,progress,message,stage in
            guard let self, self.mode == .motion, !self.showsGarden, !self.showsStarCamera, self.finderTarget == nil, !self.isInspectingStar else { return }
            self.isMotionCalibrating = !ready
            self.motionCalibrationProgress = progress
            self.motionStatus = message
            self.motionCalibrationStage = stage
        }
        motion.onLocation = { [weak self] fix in
            guard let self, self.mode == .motion else { return }
            self.location = fix; self.locationStatus = "Location set for gyro"
            self.refreshSky()
        }
        refreshSky()
    }
    static func preview() -> HomeViewModel {
        let defaults = UserDefaults(suiteName:"celyx.preview")!
        defaults.removePersistentDomain(forName:"celyx.preview")
        return HomeViewModel(location:ObserverLocation(latitude:-6.1754,longitude:106.8272,isManual:true),
                             date:Date(timeIntervalSince1970:1793633400),defaults:defaults)
    }
    var results: [CatalogStar] { ([CatalogStar.sun,CatalogStar.moon]+(snapshot?.planets.map(\.star) ?? CatalogStar.planets)+stars).filter { $0.hasCommonName && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || ($0.isSun && "Sun".localizedCaseInsensitiveContains(query))) } }
    var nearby: [StarObservation] { (observations + planetObservations + [sunObservation,moonObservation].compactMap { $0 }).filter { $0.altitude > 0 }.sorted { $0.star.mag < $1.star.mag } }
    // Cached with the sky snapshot so gyro/UI updates don't sort the catalog every frame.
    private(set) var predictedVisibleObjects: [StarObservation] = []
    private func refreshVisibleObjects() {
        guard let snapshot else { predictedVisibleObjects = []; return }
        predictedVisibleObjects = VisibilityEstimator.visibleObjects(stars:stars,sky:snapshot,quality:quality,atmosphere:atmosphere,filters:visibilityFilters)
    }

    var visibleObjectsEmptyMessage: String {
        guard location != nil else { return "Turn on location to see which stars might be visible around you." }
        if visibilityFilters.daylight && (snapshot?.sunAltitude ?? 0) >= -6 { return "It’s still too bright for this list. Check again after dark." }
        if visibilityFilters.clouds && (atmosphere.cloudCover ?? 0) >= 75 { return "The cloud forecast doesn’t suggest a clear view right now. If you spot a star anyway, you can still collect it." }
        return "No stars or planets match your current conditions. Nearby lights, moonlight and stars low on the horizon can make the list shorter."
    }
    var namedObservations: [StarObservation] { observations.filter { $0.star.hasCommonName && $0.altitude > 0 } }
    // Map visibility is independent of naked-eye observing conditions.
    var displayedObservations: [StarObservation] {
        observations.filter { observation in
            let altitude = observation.altitude
            guard altitude > 1 else { return false }
            let airMass = 1/(sin(altitude * .pi/180)+0.50572*pow(altitude+6.07995,-1.6364))
            let magnitude = observation.star.mag+scene.starExtinction*max(0,airMass-1)
            return magnitude <= scene.starLimitingMagnitude
        }
    }
    var sunObservation: StarObservation? {
        guard let snapshot, location != nil else { return nil }
        let aboveHorizon = snapshot.sunDirection.z > 0
        let clear = (atmosphere.cloudCover ?? 0) < 75
        return StarObservation(star:.sun,direction:snapshot.sunDirection,dimmedMagnitude:CatalogStar.sun.mag,
            likelyVisible:aboveHorizon && clear,
            reason:!aboveHorizon ? "Below the horizon" : !clear ? "Cloudy forecast" : "Above the horizon")
    }
    var moonObservation: StarObservation? {
        guard let snapshot, location != nil else { return nil }
        let above = snapshot.moonDirection.z > 0
        return StarObservation(star:.moon,direction:snapshot.moonDirection,dimmedMagnitude:CatalogStar.moon.mag,
            likelyVisible:above,reason:above ? "Above the horizon" : "Below the horizon")
    }
    var planetObservations: [StarObservation] {
        snapshot?.planets.map { body in
            StarObservation(star:body.star,direction:body.direction,dimmedMagnitude:body.star.mag,
                likelyVisible:body.direction.z > 0,reason:body.direction.z > 0 ? "Above the horizon" : "Below the horizon")
        } ?? []
    }
    var selectedObservation: StarObservation? { selectedStar?.isSun == true ? sunObservation : selectedStar?.isMoon == true ? moonObservation : selectedStar?.isPlanet == true ? planetObservations.first { $0.id == selectedStar?.id } : observations.first { $0.id == selectedStar?.id } }
    var motionAvailable: Bool { motion.isAvailable }
    var heading: Double { (scene.azimuth*180 / .pi+360).truncatingRemainder(dividingBy:360) }
    var locationTitle: String { location.map { $0.isManual ? "Custom location" : "Here & now" } ?? "Turn on location" }
    var currentTimeLabel: String { clock.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier:"en"))) }
    var phaseTitle: String { snapshot?.phase ?? "No location yet" }
    func constellationName(_ star: CatalogStar) -> String { star.con.flatMap { constellationNames[$0] } ?? star.con ?? "Unknown" }

    func refreshSky() {
        clock = fixedDate ?? Date()
        guard let location else { scene.hasLocation = false; observations = []; predictedVisibleObjects = []; return }
        let sky = AstronomyService.snapshot(date:clock,location:location)
        snapshot = sky
        let moonAlt = asin(sky.moonDirection.z)*180 / .pi
        let limit = VisibilityEstimator.limitingMagnitude(sunAltitude:sky.sunAltitude,quality:quality,moonAltitude:moonAlt,moonIllumination:sky.moonIllumination)
        observations = stars.map {
            VisibilityEstimator.observation(star:$0,direction:sky.direction(ra:$0.ra_deg,dec:$0.dec_deg),limit:limit,sunAltitude:sky.sunAltitude,atmosphere:atmosphere)
        }
        refreshVisibleObjects()
        scene.equatorialX = sky.basis.columns.0; scene.equatorialY = sky.basis.columns.1; scene.equatorialZ = sky.basis.columns.2
        scene.sunDirection = sky.sunDirection; scene.moonDirection = sky.moonDirection
        scene.moonIllumination = sky.moonIllumination; scene.hasLocation = true
        // Use full darkness for the map, while observations retain the real solar altitude.
        scene.limitingMagnitude = VisibilityEstimator.limitingMagnitude(sunAltitude:-18,quality:quality,moonAltitude:moonAlt,moonIllumination:sky.moonIllumination)
        scene.extinction = atmosphere.extinction; scene.cloudCover = atmosphere.cloudCover ?? 0
    }
    func refreshAtmosphere(force: Bool = false) {
        guard onlineConditions, let location, !isLoadingAtmosphere else { return }
        if !force, let fetched = atmosphere.fetchedAt, Date().timeIntervalSince(fetched) < 1800 { return }
        weatherTask?.cancel(); isLoadingAtmosphere = true
        weatherTask = Task { [weak self] in
            let value = await AtmosphereService.load(location:location)
            guard let self else { return }
            self.isLoadingAtmosphere = false
            guard !Task.isCancelled, self.onlineConditions, self.location == location else { return }
            self.atmosphere = value; self.refreshSky()
        }
    }
    func requestLocation() { locationStatus = "Finding your location…"; gps.start() }
    func useManualLocation() {
        guard let lat = Double(manualLatitude.replacingOccurrences(of:",",with:".")),
              let lon = Double(manualLongitude.replacingOccurrences(of:",",with:".")),
              lat.isFinite, lon.isFinite, (-90...90).contains(lat), (-180...180).contains(lon) else {
            locationStatus = "Use a latitude from −90 to 90 and a longitude from −180 to 180."; return
        }
        gps.stop(); location = ObserverLocation(latitude:lat,longitude:lon,isManual:true)
        locationStatus = "Custom coordinates"; atmosphere = Atmosphere()
        refreshSky(); refreshAtmosphere(force:true)
        if mode == .motion { restartMotion() }
    }
    func openVisibleSkyAR() {
        guard location != nil, !predictedVisibleObjects.isEmpty else { return }
        pendingVisibleSkyAR = true
        activeSheet = nil
    }
    func openStarCamera() {
        guard !showsGarden, !isCameraTransitioning, activeSheet == nil, finderTarget == nil else { return }
        suspend()
        showsStarCamera = true
    }
    func prepareCameraStar(_ star: CatalogStar, location: ObserverLocation) {
        self.location = location
        selectedStar = star
        refreshSky()
    }
    func openGarden() {
        guard !showsGarden, !isGardenTransitioning, !isCameraTransitioning, activeSheet == nil, finderTarget == nil else { return }
        suspend()
        gardenReturnPose = SkyCameraPose(scene:scene)
        showsGarden = true
        transitionGarden(to:1)
    }
    func closeGarden() {
        guard showsGarden, !isGardenTransitioning else { return }
        transitionGarden(to:0)
    }
    private func transitionGarden(to target: Double) {
        let start = gardenProgress
        isGardenTransitioning = true
        gardenFlight.start(duration:scene.reduceMotion ? 0.2 : 1.6) { [weak self] progress in
            let eased = progress*progress*progress*(progress*(progress*6-15)+10)
            guard let self else { return }
            self.gardenProgress = start+(target-start)*eased
            if !self.scene.reduceMotion, let original = self.gardenReturnPose {
                let travel = min(1,self.gardenProgress/0.4)
                let aim = travel*travel*(3-2*travel)
                self.scene.altitude = original.altitude+(max(original.altitude,1.0)-original.altitude)*aim
                self.scene.fieldOfView = exp(log(original.fieldOfView)+(log(8)-log(original.fieldOfView))*aim)
            }
        } completion: { [weak self] in
            guard let self else { return }
            self.gardenProgress = target
            self.isGardenTransitioning = false
            if target == 0 {
                if let original = self.gardenReturnPose { self.applyCameraPose(original) }
                self.gardenReturnPose = nil
                self.showsGarden = false
            }
        }
    }
    func findSelectedInSky() {
        guard location != nil, let selectedStar else { return }
        pendingFinderTarget = selectedStar
        activeSheet = nil
    }
    func collectInCamera() {
        guard location != nil else { return }
        pendingCollectionCamera = true
        activeSheet = nil
    }
    func handleSheetDismissal() {
        if pendingVisibleSkyAR {
            pendingVisibleSkyAR = false
            suspend(); showsVisibleSkyAR = true
        } else if pendingCollectionCamera {
            pendingCollectionCamera = false
            cameraFlight.cancel()
            if let pose = returnCameraPose { applyCameraPose(pose) }
            returnCameraPose = nil; detailVisualProgress = 0; isCameraTransitioning = false
            suspend(); showsStarCamera = true
        } else if let star = pendingDetailStar {
            pendingDetailStar = nil
            beginDetailFlight(star)
        } else if let target = pendingFinderTarget {
            pendingFinderTarget = nil
            // The panorama is hidden behind the live camera; restore its pose without
            // launching a competing zoom-out animation under the full-screen cover.
            cameraFlight.cancel()
            if let pose = returnCameraPose { applyCameraPose(pose) }
            returnCameraPose = nil; detailVisualProgress = 0; isCameraTransitioning = false
            suspend()
            finderTarget = target
        } else if returnCameraPose != nil {
            returnFromDetail()
        }
    }
    func collectSelected() {
        guard let observation = selectedObservation, observation.canCollect, let location, collected[observation.id] == nil else { return }
        collected[observation.id] = CollectedStar(id:observation.id,date:clock,latitude:location.latitude,longitude:location.longitude)
        if let data = try? JSONEncoder().encode(Array(collected.values)) { defaults.set(data,forKey:"collectedStars") }
    }
    /// Removes a collected object and its photo from the garden.
    func deleteCollected(id: Int) {
        guard let record = collected[id] else { return }
        var updated = collected
        updated[id] = nil
        guard let data = try? JSONEncoder().encode(Array(updated.values)) else { return }
        defaults.set(data,forKey:"collectedStars")
        collected = updated
        if let photo = record.photoFilename { StarPhotoStore.remove(photo) }
    }

    func saveCameraObservation(_ draft: CameraObservationDraft,note: String) throws {
        // Seeing a source in the camera is enough to save it. Forecasts never gate this path.
        let filename = try StarPhotoStore.save(draft.image)
        let previous = collected[draft.star.id]
        var updated = collected
        updated[draft.star.id] = CollectedStar(id:draft.star.id,date:draft.date,
            latitude:draft.location.latitude,longitude:draft.location.longitude,
            photoFilename:filename,note:note.trimmingCharacters(in:.whitespacesAndNewlines),
            identificationNote:draft.identificationNote)
        do {
            let data = try JSONEncoder().encode(Array(updated.values))
            defaults.set(data,forKey:"collectedStars")
            collected = updated
            if let old = previous?.photoFilename { StarPhotoStore.remove(old) }
        } catch {
            StarPhotoStore.remove(filename)
            throw error
        }
    }
    func updateObservationNote(id: Int,note: String) {
        guard var record = collected[id] else { return }
        record.note = note.trimmingCharacters(in:.whitespacesAndNewlines)
        var updated = collected; updated[id] = record
        guard let data = try? JSONEncoder().encode(Array(updated.values)) else { return }
        defaults.set(data,forKey:"collectedStars"); collected = updated
    }
    func updateObservationPlace(id: Int,name: String) {
        guard var record = collected[id], let name = ObservationPlaceName.readableName(city:name,region:nil) else { return }
        record.placeName = name
        var updated = collected; updated[id] = record
        guard let data = try? JSONEncoder().encode(Array(updated.values)) else { return }
        defaults.set(data,forKey:"collectedStars"); collected = updated
    }
    func showDetail(_ star: CatalogStar) {
        guard !isCameraTransitioning else { return }
        selectedStar = star
        if activeSheet != nil && activeSheet != .detail {
            pendingDetailStar = star
            activeSheet = nil
        } else {
            beginDetailFlight(star)
        }
    }
    private func beginDetailFlight(_ star: CatalogStar) {
        guard let direction = (star.isSun ? sunObservation : star.isMoon ? moonObservation : star.isPlanet ? planetObservations.first(where: { $0.id == star.id }) : observations.first { $0.id == star.id })?.direction else {
            activeSheet = .detail; return
        }
        if returnCameraPose == nil { returnCameraPose = SkyCameraPose(scene:scene) }
        motion.stop(); dragOrigin = nil; zoomOrigin = nil
        let target = SkyCameraPose(azimuth:atan2(direction.x,direction.y),altitude:asin(direction.z),
                                   fieldOfView:min(scene.fieldOfView,8))
        animateCamera(to:target,visualProgress:1,duration:1.05) { [weak self] in self?.activeSheet = .detail }
    }
    func closeDetail() { activeSheet = nil }
    private func returnFromDetail() {
        guard let original = returnCameraPose else { return }
        animateCamera(to:original,visualProgress:0,duration:0.9) { [weak self] in
            guard let self else { return }
            self.returnCameraPose = nil
            if self.isRunning && self.mode == .motion { self.restartMotion() }
        }
    }
    private func applyCameraPose(_ pose: SkyCameraPose) {
        scene.azimuth = pose.azimuth; scene.altitude = pose.altitude; scene.fieldOfView = pose.fieldOfView
    }
    private func animateCamera(to target: SkyCameraPose,visualProgress: Double,duration: Double,completion: @escaping () -> Void) {
        let start = SkyCameraPose(scene:scene), startVisual = detailVisualProgress
        cameraFlight.cancel()
        if scene.reduceMotion {
            applyCameraPose(target); detailVisualProgress = visualProgress
            isCameraTransitioning = false; completion(); return
        }
        isCameraTransitioning = true
        cameraFlight.start(duration:duration) { [weak self] t in
            guard let self else { return }
            // Face the object before the strongest zoom; reverse that sequence on exit.
            let panProgress = visualProgress > startVisual ? min(1,t/0.7) : max(0,(t-0.3)/0.7)
            var pose = SkyCameraPose.interpolate(from:start,to:target,progress:t)
            let pan = SkyCameraPose.interpolate(from:start,to:target,progress:panProgress)
            pose.azimuth = pan.azimuth; pose.altitude = pan.altitude
            self.applyCameraPose(pose)
            let eased = t*t*t*(t*(t*6-15)+10)
            self.detailVisualProgress = startVisual+(visualProgress-startVisual)*eased
        } completion: { [weak self] in
            self?.isCameraTransitioning = false
            completion()
        }
    }
    func focus(_ star: CatalogStar) {
        guard let p = (star.isSun ? sunObservation : star.isMoon ? moonObservation : star.isPlanet ? planetObservations.first(where: { $0.id == star.id }) : observations.first(where: { $0.id == star.id }))?.direction else { return }
        scene.azimuth = atan2(p.x,p.y); scene.altitude = asin(p.z)
        if mode == .motion { restartMotion() }
    }
    func drag(_ value: CGSize,width: Double) {
        guard mode == .touch, !isInspectingStar else { return }
        if dragOrigin == nil { dragOrigin = (scene.azimuth,scene.altitude) }
        guard let origin = dragOrigin else { return }
        let scale = scene.fieldOfView * .pi/180 / max(width,1)
        scene.azimuth = origin.0-value.width*scale
        scene.altitude = min(1.45,max(-1.35,origin.1+value.height*scale))
    }
    func endDrag() { dragOrigin = nil }
    func zoom(_ scale: Double) {
        // Pinching changes magnification only; gyro continues to own the viewing direction.
        guard !isInspectingStar, !isCameraTransitioning, !isMotionCalibrating,
              scale.isFinite, scale > 0 else { return }
        if zoomOrigin == nil { zoomOrigin = scene.fieldOfView }
        scene.fieldOfView = min(SkySceneState.maximumFieldOfView,max(SkySceneState.minimumFieldOfView,(zoomOrigin ?? 72)/scale))
    }
    func endZoom() { zoomOrigin = nil }
    func reset() {
        scene.fieldOfView = 72
        if mode == .motion { restartMotion() }
        else { scene.azimuth = 0; scene.altitude = 18 * .pi/180 }
    }
    func setMode(_ value: LookMode) {
        guard value != mode else { return }
        motion.stop(); dragOrigin = nil; zoomOrigin = nil
        mode = value
        isMotionCalibrating = value == .motion
        motionCalibrationProgress = 0
        if value == .motion { restartMotion() } else { motionStatus = "Touch" }
    }
    func recalibrateMotion() { if mode == .motion { restartMotion() } }
    private func restartMotion() {
        guard mode == .motion, !isInspectingStar else { motion.stop(); return }
        motion.stop()
        isMotionCalibrating = true; motionCalibrationProgress = 0; motionCalibrationStage = .location
        motionStatus = "Finding your location and north…"
        motion.start() { [weak self] azimuth,altitude,_ in
            guard let self, self.mode == .motion, !self.isMotionCalibrating, !self.isInspectingStar else { return }
            let diff = atan2(sin(azimuth-self.scene.azimuth),cos(azimuth-self.scene.azimuth))
            let easing = 1-exp(-10.0/60)
            self.scene.azimuth += diff*easing
            self.scene.altitude += (altitude-self.scene.altitude)*easing
        }
    }
    func resume() {
        guard !showsStarCamera, !showsVisibleSkyAR, !showsGarden, finderTarget == nil, !isRunning else { return }; isRunning = true
        refreshSky()
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        let isTest = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        if !isPreview && !isTest && location?.isManual != true { requestLocation() }
        if mode == .motion && !isPreview { restartMotion() }
        if !isPreview && !isTest { refreshAtmosphere() }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for:.seconds(5))
                guard !Task.isCancelled, let self else { return }
                self.refreshSky()
                if !isPreview && !isTest { self.refreshAtmosphere() }
            }
        }
    }
    func suspend() {
        isRunning = false
        isMotionCalibrating = false
        cameraFlight.finish()
        gardenFlight.finish()
        motion.stop(); gps.stop()
        clockTask?.cancel(); clockTask = nil
        weatherTask?.cancel(); weatherTask = nil; isLoadingAtmosphere = false
    }
}

enum HomeSheet: String, Identifiable {
    case search, nearby, layers, observing, detail
    var id: String { rawValue }
}
