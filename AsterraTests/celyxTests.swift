//
//  celyxTests.swift
//  celyx
//
//  Created by Ferdiansyah Annora on 02/11/26.
//

import Testing
import Foundation
import MetalKit
import AVFoundation
import UIKit
import CoreVideo
import simd
@testable import Asterra

@MainActor
struct celyxTests {
    @Test func panoramaDragWrapsFreelyAndClampsAtPoles() {
        let model = HomeViewModel.preview()
        model.drag(CGSize(width: -4000, height: 10000), width: 400)
        #expect(model.scene.azimuth > 2 * .pi)
        #expect(model.scene.altitude == 1.45)
        model.endDrag()
        model.drag(CGSize(width: 0, height: -10000), width: 400)
        #expect(model.scene.altitude == -1.35)
    }
    @Test func zoomIsBoundedAndResetPreservesLayers() {
        let model = HomeViewModel.preview()
        model.scene.showsGrid = true
        model.zoom(100)
        #expect(model.scene.fieldOfView == 6)
        model.endZoom()
        model.zoom(0.01)
        #expect(model.scene.fieldOfView == 100)
        model.reset()
        #expect(model.scene.fieldOfView == 72)
        #expect(model.scene.azimuth == 0)
        #expect(model.scene.showsGrid)
    }
    @Test func catalogueLoadsAndSearchFocusUsesSameProjectionAsRenderer() throws {
        let model = HomeViewModel.preview()
        #expect(model.stars.count == 3248)
        model.query = "Sirius"
        let star = try #require(model.results.first)
        #expect(star.title == "Sirius")
        model.activeSheet = .search
        model.scene.reduceMotion = true
        model.showDetail(star)
        model.handleSheetDismissal()
        let p = try #require(model.snapshot).direction(ra:star.ra_deg,dec:star.dec_deg)
        #expect(abs(model.scene.altitude - asin(p.z)) < 0.00001)
        #expect(abs(model.scene.azimuth - atan2(p.x, p.y)) < 0.00001)
        #expect(model.activeSheet == .detail)
    }
    @Test func liveSkyBasisAndSolarDayNight() {
        let location = ObserverLocation(latitude:-6.1754,longitude:106.8272)
        let date = Date(timeIntervalSince1970:1793633400)
        let sky = AstronomyService.snapshot(date:date,location:location)
        let basis = sky.basis
        #expect(abs(simd_dot(basis.columns.0,basis.columns.1)) < 1e-10)
        #expect(abs(simd_length(basis.columns.2)-1) < 1e-10)
        #expect(sky.sunAltitude < -18)
        let noon = AstronomyService.snapshot(date:date.addingTimeInterval(-10*3600),location:location)
        #expect(noon.sunAltitude > 60)
        let later = AstronomyService.snapshot(date:date.addingTimeInterval(6*3600),location:location)
        #expect(simd_length(later.basis.columns.0-basis.columns.0) > 0.5)
        let otherLocation = AstronomyService.snapshot(date:date,location:ObserverLocation(latitude:51.5,longitude:0))
        #expect(simd_length(otherLocation.basis.columns.0-basis.columns.0) > 0.5)
    }

    @Test func visibilityAndCollectionAreBoundedAndPersisted() throws {
        let defaults = UserDefaults(suiteName:"celyx.collection.tests")!
        defaults.removePersistentDomain(forName:"celyx.collection.tests")
        defer { defaults.removePersistentDomain(forName:"celyx.collection.tests") }
        let location = ObserverLocation(latitude:-6.1754,longitude:106.8272,isManual:true)
        let date = Date(timeIntervalSince1970:1793633400)
        let model = HomeViewModel(location:location,date:date,defaults:defaults)
        model.quality = .dark
        #expect(model.nearby.allSatisfy { $0.altitude > 0 })
        let candidate = try #require(model.nearby.first { $0.canCollect })
        model.scene.reduceMotion = true
        model.showDetail(candidate.star)
        model.collectSelected(); model.collectSelected()
        #expect(model.collected.count == 1)
        let restored = HomeViewModel(location:location,date:date,defaults:defaults)
        #expect(restored.collected[candidate.id]?.latitude == location.latitude)
        let cloudy = VisibilityEstimator.observation(star:candidate.star,direction:candidate.direction,limit:6,sunAltitude:-30,atmosphere:Atmosphere(cloudCover:95))
        #expect(!cloudy.likelyVisible)
        let daylight = VisibilityEstimator.observation(star:candidate.star,direction:candidate.direction,limit:6,sunAltitude:20,atmosphere:Atmosphere())
        #expect(!daylight.canCollect)
        let below = VisibilityEstimator.observation(star:candidate.star,direction:SIMD3(0,0,-1),limit:6,sunAltitude:-30,atmosphere:Atmosphere())
        #expect(!below.likelyVisible)
        let hazy = VisibilityEstimator.observation(star:candidate.star,direction:candidate.direction,limit:6,sunAltitude:-30,atmosphere:Atmosphere(aerosolOpticalDepth:1))
        #expect(hazy.dimmedMagnitude >= candidate.dimmedMagnitude)
    }

    @Test func zoomWorksWithoutHardwareCameraControlsAndClampsItsRange() {
        let service = SkyFinderService()
        #expect(service.maximumZoom == 10)
        service.setZoom(6,animated:true)
        #expect(service.cameraZoom == 6)
        service.setZoom(100)
        #expect(service.cameraZoom == 10)
        service.setZoom(0.1)
        #expect(service.cameraZoom == 1)
        service.setZoom(.nan)
        #expect(service.cameraZoom == 1)
    }

    @Test func zoomedProjectionAndImageCoordinatesProduceTheSameWorldRay() {
        let base = simd_float4x4(columns:(SIMD4(2,0,0,0),SIMD4(0,1,0,0),SIMD4(0.1,-0.05,-1,-1),SIMD4(0,0,-0.02,0)))
        for zoom in [1.0,2,6,10] {
            let transform = CameraZoom.normalizedTransform(zoom)
            let projection = CameraZoom.projection(base,zoom:zoom)
            for point in [CGPoint(x:0.5,y:0.5),CGPoint(x:0.48,y:0.52)] {
                let displayed = point.applying(transform)
                let recovered = displayed.applying(transform.inverted())
                #expect(hypot(recovered.x-point.x,recovered.y-point.y) < 1e-10)
                func ray(_ p: CGPoint,_ matrix: simd_float4x4) -> SIMD3<Float> {
                    let clip = SIMD4<Float>(Float(p.x*2-1),Float(1-p.y*2),1,1)
                    let local = simd_inverse(matrix)*clip
                    return simd_normalize(SIMD3(local.x,local.y,local.z))
                }
                #expect(simd_length(ray(point,base)-ray(displayed,projection)) < 0.00001)
            }
        }
    }

    @Test func zoomedPhotosUseTheSameCenteredCropAsThePreview() {
        let extent = CGRect(x:30,y:40,width:1000,height:800)
        let viewport = CGSize(width:400,height:800)
        let base = CameraZoom.imageCrop(extent:extent,viewport:viewport,zoom:1)
        let zoomed = CameraZoom.imageCrop(extent:extent,viewport:viewport,zoom:4)
        #expect(zoomed.midX == base.midX && zoomed.midY == base.midY)
        #expect(zoomed.width == base.width/4 && zoomed.height == base.height/4)
        #expect(extent.contains(zoomed))
    }

    @Test func previewZoomScalesCameraAndWorldMarkersTogetherAndConvertsTaps() {
        let container = FinderCameraContainer(frame:CGRect(x:0,y:0,width:400,height:800))
        container.zoom = 3
        container.layoutIfNeeded()
        #expect(container.clipsToBounds)
        #expect(container.cameraView.bounds.size == CGSize(width:400,height:800))
        #expect(container.cameraView.transform.a == 3 && container.cameraView.transform.d == 3)
        let point = container.cameraView.convert(CGPoint(x:210,y:400),to:container)
        #expect(abs(point.x-230) < 0.001 && abs(point.y-400) < 0.001)
        container.cameraView.stopRendering()
    }

    private func cameraLuminanceBuffer(width: Int = 320,height: Int = 240,
        pixel: (Int,Int) -> UInt8) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,width,height,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,nil,&buffer)
        #expect(status == kCVReturnSuccess)
        let image = try #require(buffer)
        CVPixelBufferLockBaseAddress(image,[])
        defer { CVPixelBufferUnlockBaseAddress(image,[]) }
        let bytes = try #require(CVPixelBufferGetBaseAddressOfPlane(image,0)).assumingMemoryBound(to:UInt8.self)
        let row = CVPixelBufferGetBytesPerRowOfPlane(image,0)
        for y in 0..<height { for x in 0..<width { bytes[y*row+x] = pixel(x,y) } }
        return image
    }

    @Test func faintCameraSourceSurvivesBrightSkyElsewhereInTheFrame() throws {
        let image = try cameraLuminanceBuffer { x,y in
            let r2 = Double((x-90)*(x-90)+(y-120)*(y-120))
            return UInt8(20+Double(x)*0.32+14*exp(-r2/(2*1.5*1.5)))
        }
        let sources = CameraStarDetector.detect(in:image)
        #expect(sources.contains { hypot($0.point.x*320-90,$0.point.y*240-120) < 2 })
    }

    @Test func focusedSearchFindsSoftDimLightAtDigitalZoom() throws {
        let image = try cameraLuminanceBuffer { x,y in
            let r2 = Double((x-160)*(x-160)+(y-120)*(y-120))
            return UInt8(20+9*exp(-r2/(2*4.5*4.5)))
        }
        let focused = CameraStarDetector.detect(in:image,zoom:2.8,
            focusRegion:CGRect(x:0.4,y:0.4,width:0.2,height:0.2))
        #expect(focused.contains { hypot($0.point.x*320-160,$0.point.y*240-120) < 3 })
    }

    @Test func focusedSearchKeepsSharpSourcesAndExcludesLightsOutsideTheSelectedArea() throws {
        let image = try cameraLuminanceBuffer { x,y in
            if (160...161).contains(x) && (120...121).contains(y) { return 90 }
            if (70...71).contains(x) && (120...121).contains(y) { return 90 }
            return 20
        }
        let sources = CameraStarDetector.detect(in:image,zoom:2.8,
            focusRegion:CGRect(x:0.4,y:0.4,width:0.2,height:0.2))
        #expect(sources.count == 1)
        #expect(try #require(sources.first).point.x > 0.49)
    }

    @Test func focusedDetectionStillRejectsHotPixelsGrainAndBroadGlows() throws {
        let image = try cameraLuminanceBuffer { x,y in
            let r2 = Double((x-220)*(x-220)+(y-120)*(y-120))
            let grain = (x*37+y*19)%5-2
            if x == 90 && y == 120 { return 255 }
            return UInt8(30+grain+Int(20*exp(-r2/(2*25*25))))
        }
        let sources = CameraStarDetector.detect(in:image,zoom:2.8,focusRegion:CGRect(x:0,y:0,width:1,height:1))
        #expect(sources.isEmpty,"Unexpected detections: \(sources)")
    }

    @Test func calibrationIsSharedInSessionButNeverRestoresAnOldWorldRotation() throws {
        let suite = "celyx.alignment.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let alignment = CameraSkyAlignment(defaults:defaults)
        let first = SkyFinderService(alignment:alignment)
        let second = SkyFinderService(alignment:alignment)
        let rotation = simd_quatf(angle:0.2,axis:SIMD3<Float>(0,1,0))
        alignment.save(rotation:rotation,reference:"Sun",date:Date())
        #expect(first.alignment === second.alignment)
        #expect(second.alignment.reference == "Sun")
        #expect(simd_length(alignment.correct(SIMD3(0,0,-1))-SIMD3(0,0,-1)) > 0.1)
        let relaunched = CameraSkyAlignment(defaults:defaults)
        #expect(relaunched.requiresCalibration)
        #expect(relaunched.reference == nil)
        #expect(relaunched.correct(SIMD3(0,0,-1)) == SIMD3(0,0,-1))
        #expect(defaults.data(forKey:"cameraSkyAlignment.v1") == nil)
    }

    @Test func backgroundInvalidatesCalibrationAndRejectsFrozenPhotosFromTheOldWorld() throws {
        let suite = "celyx.alignment.background.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let alignment = CameraSkyAlignment(defaults:defaults)
        let service = SkyFinderService(alignment:alignment)
        alignment.save(rotation:simd_quatf(angle:0.2,axis:SIMD3(0,1,0)),reference:"Sun",date:Date())
        let frame = CameraAlignmentFrame(generation:alignment.generation,image:UIImage(),size:CGSize(width:100,height:100),
            date:Date(),location:ObserverLocation(latitude:0,longitude:0),view:matrix_identity_float4x4,projection:matrix_identity_float4x4)
        service.suspendForBackground()
        #expect(alignment.requiresCalibration)
        #expect(alignment.reference == nil)
        #expect(alignment.generation != frame.generation)
        #expect(!service.applyAlignment(frame:frame,star:.sun,point:CGPoint(x:50,y:50)))
        #expect(service.targetMarker == nil)
        #expect(service.aimTarget() == nil)
        alignment.save(rotation:simd_quatf(angle:0,axis:SIMD3(0,1,0)),reference:"Sun",date:Date())
        #expect(!alignment.requiresCalibration)
    }

    @Test func relocationRequestsCalibrationWithoutReactingToOrdinaryGPSNoise() throws {
        let suite = "celyx.alignment.location.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let alignment = CameraSkyAlignment(defaults:defaults)
        let location = ObserverLocation(latitude:-6.17,longitude:106.82,accuracy:30)
        alignment.save(rotation:simd_quatf(angle:0,axis:SIMD3(0,1,0)),reference:"Sun",date:Date(),location:location)
        #expect(!alignment.validateLocation(ObserverLocation(latitude:-6.1701,longitude:106.82,accuracy:30)))
        #expect(!alignment.requiresCalibration)
        #expect(!alignment.validateLocation(ObserverLocation(latitude:-6.172,longitude:106.82,accuracy:500)))
        #expect(alignment.validateLocation(ObserverLocation(latitude:-6.18,longitude:106.82,accuracy:30)))
        #expect(alignment.requiresCalibration)
    }

    @Test func legacyStoredQuaternionRequiresNewCalibration() throws {
        let suite = "celyx.alignment.legacy.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.set(Data("legacy rotation".utf8),forKey:"cameraSkyAlignment.v1")
        let alignment = CameraSkyAlignment(defaults:defaults)
        #expect(alignment.requiresCalibration)
        #expect(alignment.reference == nil)
        #expect(defaults.data(forKey:"cameraSkyAlignment.v1") == nil)
    }

    @Test func nativePreviewUsesAspectFillAndRemovesFilteredMarkers() {
        let view = FinderCameraView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        #expect(view.preview.videoGravity == .resizeAspectFill)
        view.updateSkyMarkers([], labeledIDs: [], selectedID: nil)
        #expect(view.subviews.isEmpty)
        view.stopRendering()
    }

    @Test func daylightFilterCanBeDisabledWithoutChangingTimeOrCollectionEligibility() throws {
        let model = HomeViewModel(location:ObserverLocation(latitude:-6.1754,longitude:106.8272,isManual:true),
                                  date:Date(timeIntervalSince1970:1793633400-10*3600),defaults:UserDefaults(suiteName:"celyx.filter.tests")!)
        let originalDate = try #require(model.snapshot).date
        #expect(model.predictedVisibleObjects.isEmpty)
        model.visibilityFilters.daylight = false
        #expect(!model.predictedVisibleObjects.isEmpty)
        #expect(model.predictedVisibleObjects.allSatisfy { $0.altitude > 1 })
        #expect(model.snapshot?.date == originalDate)
        #expect(model.observations.allSatisfy { !$0.canCollect })
        model.visibilityFilters = VisibilityFilters()
        #expect(model.predictedVisibleObjects.isEmpty)
    }

    @Test func visibilityParametersCanBeBypassedIndependently() throws {
        let star = try #require(HomeViewModel.preview().stars.first { $0.title == "Sirius" })
        func observation(_ filters: VisibilityFilters, direction: SIMD3<Double> = SIMD3(0,0,1),
                         limit: Double = 6, sunAltitude: Double = -30, atmosphere: Atmosphere? = nil) -> StarObservation {
            VisibilityEstimator.observation(star:star,direction:direction,limit:limit,
                                            sunAltitude:sunAltitude,atmosphere:atmosphere ?? Atmosphere(),filters:filters)
        }
        var filters = VisibilityFilters()
        #expect(!observation(filters,sunAltitude:30).likelyVisible)
        filters.daylight = false
        #expect(observation(filters,sunAltitude:30).likelyVisible)
        #expect(!observation(filters,atmosphere:Atmosphere(cloudCover:95)).likelyVisible)
        filters = VisibilityFilters(); filters.clouds = false
        #expect(observation(filters,atmosphere:Atmosphere(cloudCover:95)).likelyVisible)
        #expect(!observation(filters,sunAltitude:30).likelyVisible)
        filters = VisibilityFilters(); filters.brightness = false
        #expect(observation(filters,limit:-10).likelyVisible)
        #expect(!observation(filters,direction:SIMD3(0,0,-1)).likelyVisible)
        filters = VisibilityFilters(); filters.horizon = false
        #expect(observation(filters,direction:SIMD3(0,0,-1),limit:100).likelyVisible)
        filters = VisibilityFilters(); filters.atmosphericExtinction = false
        #expect(observation(filters,direction:SIMD3(0,sqrt(0.99),0.1)).dimmedMagnitude == star.mag)
        func limit(_ filters: VisibilityFilters, quality: SkyQuality = .city, moonAltitude: Double = 45) -> Double {
            VisibilityEstimator.limitingMagnitude(sunAltitude:-30,quality:quality,moonAltitude:moonAltitude,
                                                 moonIllumination:1,filters:filters)
        }
        filters = VisibilityFilters(); filters.moonlight = false
        #expect(limit(filters) == limit(VisibilityFilters(),moonAltitude:-45))
        filters = VisibilityFilters(); filters.lightPollution = false
        #expect(limit(filters) == limit(VisibilityFilters(),quality:.dark))
    }

    @Test func daytimeMapShowsStarsAndConstellationsWhileObservationUsesRealConditions() throws {
        let defaults = UserDefaults(suiteName:"celyx.daylight.tests")!
        defaults.removePersistentDomain(forName:"celyx.daylight.tests")
        defer { defaults.removePersistentDomain(forName:"celyx.daylight.tests") }
        let model = HomeViewModel(location:ObserverLocation(latitude:-6.1754,longitude:106.8272,isManual:true),
                                  date:Date(timeIntervalSince1970:1793633400-10*3600),defaults:defaults)
        #expect(try #require(model.snapshot).sunAltitude > 60)
        #expect(!model.displayedObservations.isEmpty)
        #expect(model.displayedObservations.contains { $0.star.hasCommonName })
        #expect(!model.visibleConstellationIDs.isEmpty)
        #expect(model.observations.allSatisfy { !$0.canCollect })
        let sky = try #require(model.snapshot)
        let moonAltitude = asin(sky.moonDirection.z)*180 / .pi
        #expect(model.scene.limitingMagnitude == VisibilityEstimator.limitingMagnitude(
            sunAltitude:-18,quality:model.quality,moonAltitude:moonAltitude,moonIllumination:sky.moonIllumination))
        var drawings: [ProjectedConstellationFigure] = []
        for figure in model.constellationFigures {
            let center = sky.basis*figure.center
            model.scene.azimuth = atan2(center.x,center.y); model.scene.altitude = asin(center.z)
            drawings += ConstellationFigureProjection.project([figure],visibleIDs:model.visibleConstellationIDs,
                scene:model.scene,size:CGSize(width:402,height:874))
        }
        #expect(!drawings.isEmpty)
    }

    @Test func zoomRevealsFainterStarsIncludingUnnamedCatalogueEntries() throws {
        let model = HomeViewModel.preview()
        let original = Set(model.displayedObservations.map(\.id))
        let baseLimit = model.scene.starLimitingMagnitude
        model.zoom(1.5)
        let middleLimit = model.scene.starLimitingMagnitude
        #expect(middleLimit > baseLimit)
        model.zoom(100)
        let zoomed = Set(model.displayedObservations.map(\.id))
        #expect(model.scene.starLimitingMagnitude > middleLimit)
        #expect(original.isSubset(of:zoomed))
        #expect(zoomed.count > original.count)
        #expect(model.displayedObservations.contains { !original.contains($0.id) && !$0.star.hasCommonName })
        model.endZoom(); model.reset()
        #expect(Set(model.displayedObservations.map(\.id)) == original)
        for quality in SkyQuality.allCases {
            model.quality = quality
            let base = model.scene.starLimitingMagnitude
            model.zoom(100)
            #expect(model.scene.starLimitingMagnitude >= base)
            #expect(model.scene.starLimitingMagnitude == 6.5)
            model.endZoom(); model.reset()
        }
    }

    @Test func sunUsesLivePositionAndCanBeCollectedAndRestoredDuringDaytime() throws {
        let suite = "celyx.sun.tests"
        let defaults = UserDefaults(suiteName:suite)!
        defaults.removePersistentDomain(forName:suite)
        defer { defaults.removePersistentDomain(forName:suite) }
        let location = ObserverLocation(latitude:-6.1754,longitude:106.8272,isManual:true)
        let noon = Date(timeIntervalSince1970:1793633400-10*3600)
        let model = HomeViewModel(location:location,date:noon,defaults:defaults)
        model.query = "Matahari"
        #expect(model.results.map(\.id) == [CatalogStar.sun.id])
        model.query = "Sun"
        #expect(model.results.contains { $0.isSun })
        #expect(model.nearby.contains { $0.star.isSun })
        model.scene.reduceMotion = true
        model.showDetail(.sun)
        let solar = try #require(model.selectedObservation)
        #expect(solar.canCollect)
        #expect(solar.direction == model.scene.sunDirection)
        #expect(abs(model.scene.altitude-asin(solar.direction.z)) < 1e-10)
        model.collectSelected(); model.collectSelected()
        #expect(model.collected.count == 1)
        let restored = HomeViewModel(location:location,date:noon,defaults:defaults)
        #expect(restored.collected[CatalogStar.sun.id]?.latitude == location.latitude)
        let night = HomeViewModel(location:location,date:noon.addingTimeInterval(10*3600),defaults:defaults)
        night.scene.reduceMotion = true
        night.showDetail(.sun)
        #expect(try #require(night.selectedObservation).canCollect == false)
        #expect(!night.nearby.contains { $0.star.isSun })
    }

    @Test func finderProjectsTrueDirectionsAndNeverSnapsAlignedObjectsToCenter() throws {
        #expect(SkyFinderProjection.worldDirection(SIMD3(0,1,0)) == SIMD3(0,0,-1))
        #expect(SkyFinderProjection.worldDirection(SIMD3(1,0,0)) == SIMD3(1,0,0))
        #expect(SkyFinderProjection.worldDirection(SIMD3(0,0,1)) == SIMD3(0,1,0))
        let size = CGSize(width:400,height:800)
        // Perspective matrix with a forward-facing -Z camera.
        let projection = simd_float4x4(columns:(SIMD4(2,0,0,0),SIMD4(0,1,0,0),SIMD4(0,0,-1,-1),SIMD4(0,0,-0.02,0)))
        func guide(_ direction: SIMD3<Float>,view: simd_float4x4 = matrix_identity_float4x4) -> SkyFinderProjection {
            SkyFinderProjection.project(direction:simd_normalize(direction),view:view,projection:projection,size:size)
        }
        let centered = guide(SIMD3(0,0,-1))
        #expect(centered.isAligned)
        #expect(centered.point == CGPoint(x:200,y:400))
        let near = guide(SIMD3(0.02,0,-1))
        #expect(near.isAligned)
        #expect(try #require(near.point).x > 200)
        let right = guide(SIMD3(1,0,-1))
        #expect(!right.isAligned && right.point == nil && right.arrow.dx > 0)
        let up = guide(SIMD3(0,1,-1))
        #expect(up.arrow.dy < 0)
        let behind = guide(SIMD3(-0.1,0,1))
        #expect(behind.point == nil && behind.arrow.dx < 0)
        #expect(guide(SIMD3(0,0,1)).point == nil)
        let roll = simd_float4x4(simd_quatf(angle:.pi/2,axis:SIMD3(0,0,1)))
        let rolled = guide(SIMD3(0.1,0,-1),view:roll)
        #expect(abs(rolled.arrow.dx) < 0.001 && rolled.arrow.dy < 0)
    }

    @Test func finderPresentationWaitsForDetailDismissalAndRequiresLocation() throws {
        let model = HomeViewModel.preview()
        model.scene.reduceMotion = true
        model.showDetail(.sun)
        model.findSelectedInSky()
        #expect(model.activeSheet == nil)
        #expect(model.finderTarget == nil)
        model.handleSheetDismissal()
        #expect(model.finderTarget?.isSun == true)
        let missing = HomeViewModel()
        missing.selectedStar = .sun
        missing.findSelectedInSky(); missing.handleSheetDismissal()
        #expect(missing.finderTarget == nil)
    }

    @Test func deepZoomFadesAtmosphereWithoutChangingAstronomicalPositions() throws {
        let model = HomeViewModel.preview()
        let basis = try #require(model.snapshot).basis
        let solar = model.scene.sunDirection
        let originalObservations = model.observations.map(\.likelyVisible)
        #expect(model.scene.spaceBlend == 0)
        model.scene.fieldOfView = 35
        #expect(model.scene.spaceBlend == 0)
        model.scene.fieldOfView = 20
        #expect(model.scene.spaceBlend > 0 && model.scene.spaceBlend < 1)
        model.scene.cloudCover = 95
        #expect(model.scene.renderedCloudCover < 95)
        model.scene.fieldOfView = 8
        #expect(model.scene.spaceBlend == 1)
        #expect(model.scene.renderedExtinction == 0)
        #expect(model.scene.renderedCloudCover == 0)
        #expect(model.snapshot?.basis == basis)
        #expect(model.scene.sunDirection == solar)
        #expect(model.observations.map(\.likelyVisible) == originalObservations)
        model.scene.cloudCover = 0
        model.reset()
        #expect(model.scene.spaceBlend == 0)
        #expect(model.scene.renderedExtinction == model.scene.extinction)
    }

    @Test func cameraFlightTakesShortestTurnAndZoomsContinuously() {
        let from = SkyCameraPose(azimuth:359 * .pi/180,altitude:0.2,fieldOfView:72)
        let to = SkyCameraPose(azimuth:1 * .pi/180,altitude:0.8,fieldOfView:8)
        let middle = SkyCameraPose.interpolate(from:from,to:to,progress:0.5)
        #expect(abs(middle.azimuth-2 * .pi) < 1e-10)
        #expect(abs(middle.fieldOfView-24) < 1e-10)
        var last = from.fieldOfView
        for step in 0...100 {
            let pose = SkyCameraPose.interpolate(from:from,to:to,progress:Double(step)/100)
            #expect(pose.fieldOfView <= last+1e-10)
            #expect(abs(pose.azimuth-from.azimuth) <= 2 * .pi/180+1e-10)
            last = pose.fieldOfView
        }
    }

    @Test func detailFlightAnimatesInAndRestoresPreviousCameraOnDismissal() async throws {
        let model = HomeViewModel.preview()
        model.scene.azimuth = 0.35; model.scene.altitude = 0.4; model.scene.fieldOfView = 56
        let original = SkyCameraPose(scene:model.scene)
        let star = try #require(model.namedObservations.first?.star)
        model.showDetail(star)
        #expect(model.isCameraTransitioning)
        #expect(model.activeSheet == nil)
        #expect(SkyCameraPose(scene:model.scene) == original)
        try await Task.sleep(for:.milliseconds(180))
        #expect(model.detailVisualProgress > 0 && model.detailVisualProgress < 1)
        #expect(model.scene.fieldOfView < 56 && model.scene.fieldOfView > 8)
        try await Task.sleep(for:.milliseconds(1100))
        #expect(model.activeSheet == .detail)
        #expect(!model.isCameraTransitioning)
        #expect(abs(model.scene.fieldOfView-8) < 1e-8)
        model.closeDetail(); model.handleSheetDismissal()
        #expect(model.isCameraTransitioning)
        try await Task.sleep(for:.milliseconds(1100))
        #expect(!model.isInspectingStar)
        #expect(model.detailVisualProgress == 0)
        #expect(abs(model.scene.azimuth-original.azimuth) < 1e-8)
        #expect(abs(model.scene.altitude-original.altitude) < 1e-8)
        #expect(abs(model.scene.fieldOfView-original.fieldOfView) < 1e-8)
    }

    @Test func gardenResolvesRealRecordsSortsNewestAndPreservesMissingCatalogueItems() throws {
        let catalogue = try SkyAssets.stars()
        let first = try #require(catalogue.first)
        let old = Date(timeIntervalSince1970:100)
        let recent = Date(timeIntervalSince1970:200)
        let records = [first.id:CollectedStar(id:first.id,date:old,latitude:-6.2,longitude:106.8),
                       -1:CollectedStar(id:-1,date:recent,latitude:-7,longitude:107),
                       999999:CollectedStar(id:999999,date:old,latitude:0,longitude:0)]
        let items = GardenCollectionItem.resolve(records:records,catalogue:catalogue)
        #expect(items.count == records.count)
        #expect(items.first?.star.isSun == true)
        #expect(items.first?.record.latitude == -7)
        #expect(items.contains { $0.id == 999999 && $0.star.title == "Objek 999999" })
        #expect(GardenCollectionItem.resolve(records:[:],catalogue:catalogue).isEmpty)
        #expect(FileManager.default.fileExists(atPath:try SkyAssets.url("your-galaxy-1400",extension:"jpg").path))
    }

    @Test func gardenMarkersStayOnTheDiscAndSelectionCanRotateIntoView() {
        let center = CGPoint(x:200,y:400)
        for id in [-1,0,1,100,3247] {
            let rotation = -.pi/2+0.35-GardenOrbit.angle(id:id)
            let selected = GardenOrbit.point(id:id,rotation:rotation,diameter:800,center:center)
            #expect(selected.x > 44 && selected.x < 356)
            #expect(selected.y > 120 && selected.y < 650)
            let repeated = GardenOrbit.point(id:id,rotation:rotation+2 * .pi,diameter:800,center:center)
            #expect(abs(selected.x-repeated.x) < 1e-8)
            #expect(abs(selected.y-repeated.y) < 1e-8)
        }
    }

    @Test func gardenPortalZoomsBothWaysWithoutChangingSkyCamera() async throws {
        let model = HomeViewModel.preview()
        let pose = SkyCameraPose(scene:model.scene)
        model.openGarden()
        #expect(model.showsGarden && model.isGardenTransitioning)
        #expect(model.gardenProgress == 0)
        try await Task.sleep(for:.milliseconds(180))
        #expect(model.gardenProgress > 0 && model.gardenProgress < 1)
        try await Task.sleep(for:.milliseconds(1100))
        #expect(model.showsGarden && !model.isGardenTransitioning)
        #expect(model.gardenProgress == 1)
        model.closeGarden()
        #expect(model.isGardenTransitioning)
        try await Task.sleep(for:.milliseconds(180))
        #expect(model.gardenProgress > 0 && model.gardenProgress < 1)
        try await Task.sleep(for:.milliseconds(1100))
        #expect(!model.showsGarden && !model.isGardenTransitioning)
        #expect(model.gardenProgress == 0)
        #expect(SkyCameraPose(scene:model.scene) == pose)
    }

    @Test func missingAndInvalidLocationNeverPretendToBeLive() {
        let model = HomeViewModel()
        #expect(model.location == nil)
        #expect(model.nearby.isEmpty)
        model.manualLatitude = "95"; model.manualLongitude = "200"
        model.useManualLocation()
        #expect(model.location == nil)
        model.manualLatitude = "-6.1754"; model.manualLongitude = "106.8272"
        model.useManualLocation()
        #expect(model.location?.isManual == true)
        #expect(model.scene.hasLocation)
    }

    @Test func stereographicProjectionRoundTripsAtTallScreenEdges() throws {
        for fieldOfView in [6.0,8,20,35,72,100] {
        let focal = CameraProjection.focalLength(width: 402, height: 874, fieldOfView: fieldOfView)
        for x in [-201.0,0,201] {
            for y in [-463.0,0,411] {
                let offset = SIMD2(x,y)
                let ray = CameraProjection.ray(offset: offset,focal: focal)
                #expect(abs(simd_length(ray)-1) < 1e-10)
                let screen = try #require(CameraProjection.project(direction: ray,focal: focal))
                #expect(simd_length(screen-offset) < 1e-9)
                // Equal screen distances should have equal angular scale in X and Y,
                // even at the corners where the previous pinhole camera stretched shapes.
                let dx = CameraProjection.ray(offset: offset+SIMD2(0.01,0),focal: focal)-ray
                let dy = CameraProjection.ray(offset: offset+SIMD2(0,0.01),focal: focal)-ray
                #expect(abs(simd_length(dx)/simd_length(dy)-1) < 0.0001)
                #expect(abs(simd_dot(simd_normalize(dx),simd_normalize(dy))) < 0.0001)
            }
        }
        #expect(CameraProjection.project(direction: SIMD3(0,0,-1),focal: focal) == nil)
        }
    }

    @Test func rendererCanChangeCollectionAfterLoadingTheCatalog() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let view = MTKView(frame:.zero,device:device)
        let renderer = try PanoramaRenderer(view:view)
        let first = try #require(SkyAssets.stars().first)
        renderer.scene.collectedIDs = []
        renderer.draw(in:view)
        #expect(renderer.starCount == 0)
        renderer.scene.collectedIDs = [first.id]
        renderer.draw(in:view)
        #expect(renderer.starCount == 1)
        renderer.scene.collectedIDs = nil
        renderer.draw(in:view)
        #expect(renderer.starCount == 3248)
    }

    @Test func rendererCompilesGPUStarsAndFitsTextureBudget() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let view = MTKView(frame: CGRect(x: 0,y: 0,width: 402,height: 874),device: device)
        let renderer = try PanoramaRenderer(view: view)
        #expect(renderer.starCount == 3248)
        #expect(renderer.textureByteCount <= 160*1024*1024)
    }

    @Test func figureCatalogueIncludesAllBundledIllustrations() throws {
        let figures = try ConstellationFigure.load()
        #expect(figures.count == 85)
        for figure in figures {
            let file = URL(fileURLWithPath:figure.definition.file)
            #expect(FileManager.default.fileExists(atPath:try SkyAssets.url(file.deletingPathExtension().lastPathComponent,extension:file.pathExtension).path))
        }
        #expect(!figures.contains { ["Pup","Ser","Vel"].contains($0.id) })
    }

    @Test func constellationArtworkTracksAllThreeAnchorsAcrossZoomAndRotation() throws {
        let model = HomeViewModel.preview()
        let sky = try #require(model.snapshot)
        let figure = try #require(model.constellationFigures.first { $0.id == "And" })
        let center = sky.basis*figure.center
        model.scene.azimuth = atan2(center.x,center.y)
        model.scene.altitude = asin(center.z)
        let size = CGSize(width:402,height:874)
        for fov in [35.0,72,100] {
            for offset in [0.0,0.12] {
                var scene = model.scene
                scene.azimuth += offset; scene.fieldOfView = fov
                let drawing = try #require(ConstellationFigureProjection.project([figure],visibleIDs:["And"],scene:scene,size:size).first)
                let az = scene.azimuth, alt = scene.altitude
                let forward = SIMD3(sin(az)*cos(alt),cos(az)*cos(alt),sin(alt))
                let right = SIMD3(cos(az),-sin(az),0.0), up = simd_cross(right,forward)
                let focal = CameraProjection.focalLength(width:size.width,height:size.height,fieldOfView:fov)
                for anchor in figure.definition.anchors {
                    let d = sky.basis*anchor.equatorial
                    let p = try #require(CameraProjection.project(direction:SIMD3(simd_dot(d,right),simd_dot(d,up),simd_dot(d,forward)),focal:focal))
                    let actual = CGPoint(x:anchor.pixel[0],y:anchor.pixel[1]).applying(drawing.transform)
                    #expect(abs(actual.x-(size.width*0.5+p.x)) < 1e-7)
                    #expect(abs(actual.y-(size.height*0.47-p.y)) < 1e-7)
                }
            }
        }
        let source = [CGPoint.zero,CGPoint(x:1,y:1),CGPoint(x:2,y:2)]
        #expect(ConstellationFigureProjection.affine(source:source,target:source) == nil)
    }

    @Test func constellationArtworkFadesAndStaysInsideViewingRadius() throws {
        let model = HomeViewModel.preview()
        let figure = try #require(model.constellationFigures.first { $0.id == "And" })
        let sky = try #require(model.snapshot)
        let center = sky.basis*figure.center
        var scene = model.scene
        scene.azimuth = atan2(center.x,center.y); scene.altitude = asin(center.z)
        let size = CGSize(width:402,height:874)
        func drawings(_ scene: SkySceneState,_ ids: Set<String> = ["And"]) -> [ProjectedConstellationFigure] {
            ConstellationFigureProjection.project([figure],visibleIDs:ids,scene:scene,size:size)
        }
        let initial = try #require(drawings(scene).first)
        var edge = scene; edge.altitude -= 18 * .pi/180
        let faded = try #require(drawings(edge).first)
        #expect(faded.opacity > 0 && faded.opacity < initial.opacity)
        edge.altitude = scene.altitude-23 * .pi/180
        #expect(drawings(edge).isEmpty)
        #expect(drawings(scene,[]).isEmpty)
        var disabled = scene; disabled.showsConstellationFigures = false
        #expect(drawings(disabled).isEmpty)
        var daylight = scene; daylight.sunDirection = SIMD3(0,0,1)
        let daytimeDrawing = try #require(drawings(daylight).first)
        #expect(daytimeDrawing.opacity == initial.opacity)
        disabled = scene; disabled.hasLocation = false
        #expect(drawings(disabled).isEmpty)
        disabled = scene; disabled.cloudCover = 90
        #expect(drawings(disabled).isEmpty)
    }

}
