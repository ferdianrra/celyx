import Foundation
import Metal
import Testing
import simd

@testable import Asterra

@MainActor
struct GardenZoomTests {
    private let size = CGSize(width: 390, height: 844)

    private func object(_ kind: NightSeaObject.Kind, id: Int = 1, radius: Double) -> NightSeaObject {
        NightSeaObject(id: id, direction: SIMD3(0, 1, 0.5), radius: radius, color: SIMD3(1, 1, 1), kind: kind)
    }

    private func camera(fieldOfView: Double) -> NightSeaCamera {
        var camera = NightSeaCamera()
        camera.fieldOfView = fieldOfView
        return camera
    }

    /// The garden shader is compiled at runtime from text, so a typo would only fail on screen.
    @Test func gardenShadersCompileWithTheBodyPipeline() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sea = try String(contentsOf: SkyAssets.url("NightSeaShader", extension: "txt"), encoding: .utf8)
        let bodies = try String(contentsOf: SkyAssets.url("GardenBodyShader", extension: "txt"), encoding: .utf8)
        let library = try device.makeLibrary(source: sea + "\n" + bodies, options: nil)
        for name in ["gardenBodyVertex", "gardenBodyFragment", "gardenPointVertex", "gardenPointFragment", "seaFragment"] {
            #expect(library.makeFunction(name: name) != nil, "\(name) missing")
        }
        // The sky source is shared with the wormhole, which compiles it with its own shader.
        let wormhole = try String(contentsOf: SkyAssets.url("WormholeShader", extension: "txt"), encoding: .utf8)
        let handover = try device.makeLibrary(source: sea + "\n" + wormhole, options: nil)
        #expect(handover.makeFunction(name: "wormholeFragment") != nil)
        let textures = try NightSeaRenderer.loadBodyTextures(device: device)
        #expect(textures.arrayLength == 5)
        #expect(textures.mipmapLevelCount > 1)
    }

    @Test func defaultViewKeepsTheKitLabelAndTapSizes() {
        let zoom = camera(fieldOfView: 72).gardenZoom(in: size)
        #expect(abs(zoom - 1) < 1e-9)
        let star = object(.star, radius: 3.9).apparent(zoom: zoom)
        #expect(abs(star.labelOffset - (3.9 * 7 / 1.3 * 0.45 + 14)) < 1e-9)
        #expect(star.hitRadius == 36)
        #expect(star.detail == 0)
        let planet = object(.planet, id: -6, radius: 26).apparent(zoom: zoom)
        #expect(abs(planet.labelOffset - (26 * 0.45 + 14)) < 1e-9)
        #expect(planet.detail == 0)
    }

    @Test func zoomGrowsAndResolvesStarsAndPlanets() {
        var previous = 0.0
        for fov in [72.0, 40, 20, 10, 5, 2.5, GardenZoomLimits.minFieldOfView] {
            let apparent = object(.star, radius: 3.9).apparent(camera: camera(fieldOfView: fov), in: size)
            #expect(apparent.disk >= previous)
            previous = apparent.disk
        }
        let deep = camera(fieldOfView: GardenZoomLimits.minFieldOfView)
        // Stars stay points of light; planets resolve.
        let star = object(.star, radius: 3.9).apparent(camera: deep, in: size)
        #expect(star.detail == 0)
        #expect(star.disk <= 3.9 * GardenZoomLimits.maxStarGrowth + 1e-9)
        #expect(object(.planet, id: -6, radius: 26).apparent(camera: deep, in: size).detail == 1)
        // Labels move below the grown disk.
        let resolved = object(.planet, id: -6, radius: 26).apparent(camera: deep, in: size)
        #expect(resolved.labelOffset > resolved.disk)
        #expect(resolved.hitRadius >= resolved.disk)
    }

    @Test func diskIsCappedSoTheObjectStaysWhole() {
        let deep = camera(fieldOfView: GardenZoomLimits.minFieldOfView)
        for item in [object(.star, radius: 6.5), object(.planet, id: -6, radius: 31), object(.moon, id: -2, radius: 38)] {
            #expect(item.apparent(camera: deep, in: size).disk <= 0.3 * 390 + 1e-9)
        }
    }

    @Test func moonNeverDrawsSmallerThanItsTrueSize() {
        let cam = camera(fieldOfView: 4)
        let focal = cam.focalLength(in: size)
        let moon = object(.moon, id: -2, radius: 38).apparent(camera: cam, in: size)
        #expect(moon.disk >= focal * tan(0.2665 * .pi / 180) - 0.1)
        #expect(moon.detail == 1)
    }

    @Test func zoomLimitsAllowTelescopeViews() {
        #expect(camera(fieldOfView: GardenZoomLimits.minFieldOfView).gardenZoom(in: size) > 40)
        var gyro = NightSeaCamera()
        gyro.orientation = simd_quatd(angle: 0, axis: SIMD3(0, 0, 1))
        gyro.zoom = GardenZoomLimits.maxGyroZoom
        #expect(gyro.gardenZoom(in: size) > 15)
    }

    @Test func moonAndPlanetsCarryTheirRealPhaseAndTheSun() throws {
        let location = ObserverLocation(latitude: -6.1754, longitude: 106.8272, isManual: true)
        let date = Date(timeIntervalSince1970: 1_793_633_400)
        let sky = AstronomyService.snapshot(date: date, location: location)
        #expect(sky.planetPhaseAngles.count == 5)
        let items = ([CatalogStar.moon] + CatalogStar.planets).map {
            GardenCollectionItem(star: $0, record: CollectedStar(id: $0.id, date: date,
                latitude: location.latitude, longitude: location.longitude))
        }
        let placed = GardenViewModel.placement(items: items, location: location, date: date).placed
        let moon = try #require(placed.first { $0.id == CatalogStar.moon.id }?.object)
        // k = (1 + cos α) / 2
        #expect(abs((1 + cos(moon.phaseAngle)) / 2 - sky.moonIllumination) < 1e-6)
        #expect(simd_distance(moon.sunDirection, sky.sunDirection) < 1e-9)
        let venus = try #require(placed.first { $0.id == -4 }?.object)
        #expect(abs(venus.phaseAngle - (sky.planetPhaseAngles[-4] ?? 0) * .pi / 180) < 1e-9)
        #expect(placed.first { $0.id == -2 }?.object.textureSlice == 0)
        #expect(placed.first { $0.id == -7 }?.object.textureSlice == -1)
    }

    @Test func starNamesToggleUsesItsOwnSetting() {
        #expect(GardenSkyView.showsStarNamesKey == "gardenShowsStarNames")
    }
}

@MainActor
struct GardenNavigationTests {
    private let size = CGSize(width: 390, height: 844)

    @Test func namesAppearOnlyWhenZoomedIn() {
        #expect(GardenZoomLimits.labelOpacity(zoom: 1) == 0)          // default touch view
        #expect(GardenZoomLimits.labelOpacity(zoom: 1.7) == 0)        // default gyro view
        #expect(GardenZoomLimits.labelOpacity(zoom: 2.3) > 0)
        #expect(GardenZoomLimits.labelOpacity(zoom: 2.6) == 1)
        #expect(GardenZoomLimits.labelOpacity(zoom: 40) == 1)
    }

    @Test func dragFollowsTheFingerWhenZoomedIn() {
        var camera = NightSeaCamera()
        camera.fieldOfView = 2
        let focal = camera.focalLength(in: size)
        // 1:1: a drag of 100 pt turns the view by the angle those 100 pt span.
        let k = GardenZoomLimits.dragRadiansPerPoint(fieldOfView: 2, focalLength: focal)
        #expect(abs(k * focal - 1) < 1e-9)
        // The wide default keeps its original feel.
        camera.fieldOfView = 72
        let wide = GardenZoomLimits.dragRadiansPerPoint(fieldOfView: 72, focalLength: camera.focalLength(in: size))
        let original = 72 / 390 * 1.15 * Double.pi / 180
        #expect(abs(wide - original) / original < 0.12)
    }

    @Test func pinchKeepsTheSkyUnderTheFingers() {
        let model = GardenViewModel(model: AppPreviewData.model, camera: NightSeaCamera())
        model.camera.orientation = nil
        model.camera.fieldOfView = 40
        let anchor = CGPoint(x: 300, y: 250)
        let c = model.camera.center(in: size), f = model.camera.focalLength(in: size)
        let pinned = simd_normalize(model.camera.forward + ((anchor.x - c.x) / f) * model.camera.right
            + ((c.y - anchor.y) / f) * model.camera.up)
        for fov in [30.0, 15, 6, 2] {
            model.zoomTouch(fieldOfView: fov, anchor: anchor, in: size)
            let point = model.camera.project(pinned, in: size)
            #expect(point.map { hypot($0.x - anchor.x, $0.y - anchor.y) < 2 } == true, "fov \(fov): \(String(describing: point))")
        }
        #expect(model.camera.fieldOfView == 2)
    }

    /// On a phone the drag gesture also fires during a pinch. It must not switch the gyro view to
    /// touch (which used to make the zoom jump), and the pinch must keep zooming.
    @Test func gyroPinchIsNotInterruptedByTheDragGesture() {
        let model = GardenViewModel(model: AppPreviewData.model, camera: NightSeaCamera())
        model.camera.orientation = simd_quatd(angle: 0.3, axis: SIMD3(1, 0, 0))
        model.pinch(1, anchor: CGPoint(x: 200, y: 400), in: size)
        model.drag(CGSize(width: 30, height: -20), in: size)
        #expect(model.camera.orientation != nil)
        model.pinch(2, anchor: CGPoint(x: 200, y: 400), in: size)
        model.settleZoom()
        #expect(abs(model.camera.zoom - pow(2, GardenZoomLimits.pinchExponent)) < 1e-9)
        model.pinch(20, anchor: CGPoint(x: 200, y: 400), in: size)
        model.settleZoom()
        #expect(abs(model.camera.zoom - GardenZoomLimits.maxGyroZoom) < 1e-9)
    }

    @Test func touchPinchScalesTheFocalLengthSmoothly() {
        let model = GardenViewModel(model: AppPreviewData.model, camera: NightSeaCamera())
        model.camera.orientation = nil
        let start = model.camera.focalLength(in: size)
        model.pinch(1, anchor: CGPoint(x: 195, y: 400), in: size)
        model.settleZoom()
        #expect(abs(model.camera.focalLength(in: size) - start) / start < 1e-6)
        model.pinch(1.5, anchor: CGPoint(x: 195, y: 400), in: size)
        model.settleZoom()
        let expected = start * pow(1.5, GardenZoomLimits.pinchExponent)
        #expect(abs(model.camera.focalLength(in: size) - expected) / expected < 1e-6)
    }

    @Test func panningResumesWithoutAJumpAfterThePinch() {
        let model = GardenViewModel(model: AppPreviewData.model, camera: NightSeaCamera())
        model.camera.orientation = nil
        model.drag(CGSize(width: 10, height: 0), in: size)
        model.pinch(1.2, anchor: CGPoint(x: 195, y: 400), in: size)
        model.drag(CGSize(width: 60, height: 0), in: size)        // ignored: still pinching
        model.zoomStart = nil                                      // pinch ends, finger stays
        let azimuth = model.camera.azimuth
        model.drag(CGSize(width: 80, height: 0), in: size)        // rebased: no jump
        #expect(abs(model.camera.azimuth - azimuth) < 1e-9)
        model.drag(CGSize(width: 90, height: 0), in: size)
        #expect(model.camera.azimuth < azimuth)
    }

    /// Raising the phone after a touch zoom hands over to the gyro at the same magnification.
    @Test func gyroTakesOverAtTheTouchZoom() {
        let model = GardenViewModel(model: AppPreviewData.model, camera: NightSeaCamera())
        model.setGyroMode(false)
        model.camera.orientation = nil
        model.pinch(1, anchor: CGPoint(x: 195, y: 400), in: size)
        model.pinch(3, anchor: CGPoint(x: 195, y: 400), in: size)
        model.zoomStart = nil
        model.settleZoom()
        let touchFocal = model.camera.focalLength(in: size)
        model.setGyroMode(true)
        var gyro = model.camera
        gyro.orientation = simd_quatd(angle: 0, axis: SIMD3(0, 0, 1))
        #expect(model.camera.zoom > 2)
        #expect(abs(gyro.focalLength(in: size) - touchFocal) / touchFocal < 1e-6)
    }

    /// The zoom eases toward the pinch instead of following each touch event.
    @Test func zoomEasesSmoothlyToThePinch() {
        let model = GardenViewModel(model: AppPreviewData.model, camera: NightSeaCamera())
        model.camera.orientation = nil
        let start = model.camera.focalLength(in: size)
        model.pinch(1, anchor: CGPoint(x: 195, y: 400), in: size)
        model.pinch(2, anchor: CGPoint(x: 195, y: 400), in: size)
        model.zoomStart = nil
        let goal = start * pow(2, GardenZoomLimits.pinchExponent)
        #expect(model.camera.focalLength(in: size) < goal * 0.99)            // not snapped
        var previous = model.camera.focalLength(in: size)
        for _ in 0..<5 {
            model.advanceMotion(1 / 60)
            let focal = model.camera.focalLength(in: size)
            #expect(focal > previous && focal <= goal * 1.0001)
            previous = focal
        }
        var frames = 0
        while model.advanceMotion(1 / 60) { frames += 1; if frames > 600 { break } }
        #expect(abs(model.camera.focalLength(in: size) - goal) / goal < 1e-3)
        #expect(frames < 120)                                                // settles within ~2 s
    }

    @Test func zoomReachesFarterThanBefore() {
        let model = GardenViewModel(model: AppPreviewData.model, camera: NightSeaCamera())
        model.camera.orientation = nil
        model.pinch(1, anchor: CGPoint(x: 195, y: 400), in: size)
        model.pinch(1000, anchor: CGPoint(x: 195, y: 400), in: size)
        model.settleZoom()
        #expect(abs(model.camera.fieldOfView - GardenZoomLimits.minFieldOfView) < 1e-6)
        #expect(model.camera.gardenZoom(in: size) > 100)
    }

    /// A released drag glides on and slows to a stop.
    @Test func releasedDragGlidesAndStops() {
        let model = GardenViewModel(model: AppPreviewData.model, camera: NightSeaCamera())
        model.camera.orientation = nil
        model.drag(CGSize(width: 40, height: 0), in: size)
        model.endDrag(velocity: CGSize(width: 600, height: 0), in: size)
        let azimuth = model.camera.azimuth
        model.advanceMotion(1 / 60)
        let first = azimuth - model.camera.azimuth
        #expect(first > 0)                                                   // keeps moving the same way
        model.advanceMotion(1 / 60)
        #expect(azimuth - model.camera.azimuth - first < first)              // and slows down
        var frames = 0
        while model.advanceMotion(1 / 60) { frames += 1; if frames > 1000 { break } }
        #expect(frames < 200)
    }

    @Test func reduceMotionAppliesGesturesDirectly() {
        let model = GardenViewModel(model: AppPreviewData.model, camera: NightSeaCamera())
        model.camera.orientation = nil
        model.reduceMotion = true
        let start = model.camera.focalLength(in: size)
        model.pinch(1, anchor: CGPoint(x: 195, y: 400), in: size)
        model.pinch(2, anchor: CGPoint(x: 195, y: 400), in: size)
        let goal = start * pow(2, GardenZoomLimits.pinchExponent)
        #expect(abs(model.camera.focalLength(in: size) - goal) / goal < 1e-6)
        model.zoomStart = nil
        model.drag(CGSize(width: 10, height: 0), in: size)
        model.endDrag(velocity: CGSize(width: 800, height: 0), in: size)
        #expect(model.advanceMotion(1 / 60) == false)
    }
}

struct GardenDaylightTests {
    @Test func skyKeepsTheNightUntilTheSunIsCollected() {
        #expect(NightSeaRenderer.daylightVector(sun: nil, strength: NightSeaRenderer.daylightStrength) == .zero)
    }

    @Test func washPointsAtTheSunAndStaysThin() {
        let sun = SIMD3<Double>(0.3, -0.5, 0.8)
        let wash = NightSeaRenderer.daylightVector(sun: sun, strength: NightSeaRenderer.daylightStrength)
        #expect(abs(simd_length(wash) - NightSeaRenderer.daylightStrength) < 1e-5)
        let direction = simd_normalize(sun)
        #expect(simd_distance(simd_normalize(wash), SIMD3(Float(direction.x), Float(direction.y), Float(direction.z))) < 1e-5)
        // Thin enough that stars stay visible at noon.
        #expect(NightSeaRenderer.daylightStrength <= 0.4)
    }
}

@MainActor
struct GardenDomeProjectionTests {
    private let size = CGSize(width: 390, height: 844)

    private func camera(fov: Double, dome: Double) -> NightSeaCamera {
        var camera = NightSeaCamera()
        camera.azimuth = 0.7
        camera.altitude = 0.4
        camera.fieldOfView = fov
        camera.stereographic = dome
        return camera
    }

    @Test func pinholeIsUnchangedAtZero() {
        let cam = camera(fov: 72, dome: 0)
        let d = simd_normalize(cam.forward + 0.3 * cam.right - 0.2 * cam.up)
        let f = cam.focalLength(in: size), c = cam.center(in: size), z = simd_dot(d, cam.forward)
        let expected = CGPoint(x: c.x + simd_dot(d, cam.right) / z * f, y: c.y - simd_dot(d, cam.up) / z * f)
        let point = cam.project(d, in: size)
        #expect(point.map { hypot($0.x - expected.x, $0.y - expected.y) < 1e-9 } == true)
    }

    @Test func projectionRoundTripsForEveryBlend() {
        for dome in [0.0, 0.35, 0.7, 1.0] {
            let cam = camera(fov: 100, dome: dome)
            for point in [CGPoint(x: 195, y: 397), CGPoint(x: 10, y: 20), CGPoint(x: 380, y: 830), CGPoint(x: 300, y: 120)] {
                let direction = cam.direction(at: point, in: size)
                let back = cam.project(direction, in: size)
                #expect(back.map { hypot($0.x - point.x, $0.y - point.y) < 1e-6 } == true, "dome \(dome) \(point)")
            }
        }
    }

    /// The dome shows more sky in the same frame, without changing the scale at the centre.
    @Test func domeWidensTheViewButKeepsTheCentre() {
        let flat = camera(fov: 90, dome: 0), dome = camera(fov: 90, dome: 1)
        let corner = CGPoint(x: 0, y: 0)
        let flatAngle = acos(simd_dot(flat.direction(at: corner, in: size), flat.forward))
        let domeAngle = acos(simd_dot(dome.direction(at: corner, in: size), dome.forward))
        #expect(domeAngle > flatAngle + 0.1)
        let near = CGPoint(x: 197, y: 397)
        let a = flat.direction(at: near, in: size), b = dome.direction(at: near, in: size)
        #expect(simd_distance(a, b) < 1e-5)
    }

    @Test func domeOnlyForTheWideTouchView() {
        let model = GardenViewModel(model: AppPreviewData.model, camera: NightSeaCamera())
        #expect(model.projectionTarget == 0)                       // gyro mode
        model.setGyroMode(false)
        model.camera.orientation = nil
        model.camera.fieldOfView = 72
        #expect(model.projectionTarget == 1)
        model.camera.fieldOfView = 5
        #expect(model.projectionTarget == 0)                       // zoomed in: pinhole
        model.camera.fieldOfView = 72
        model.projectionLocked = true                              // handover / tour
        #expect(model.projectionTarget == 0)
        model.projectionLocked = false
        model.camera.focalOverride = 400
        #expect(model.projectionTarget == 0)
    }

    @Test func domeEasesInWithoutAJump() {
        let model = GardenViewModel(model: AppPreviewData.model, camera: NightSeaCamera())
        model.setGyroMode(false)
        model.camera.orientation = nil
        model.camera.fieldOfView = 72
        model.camera.stereographic = 0
        model.advanceMotion(1 / 60)
        let first = model.camera.stereographic
        #expect(first > 0 && first < 0.3)
        var frames = 0
        while model.advanceMotion(1 / 60) { frames += 1; if frames > 600 { break } }
        #expect(model.camera.stereographic == 1)
        #expect(frames < 90)
    }
}
