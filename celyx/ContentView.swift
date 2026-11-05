//
//  ContentView.swift
//  celyx
//
import SwiftUI

struct ContentView: View {
    @State private var model = HomeViewModel()
    @State private var showsSky = false

    var body: some View {
        Group {
            if showsSky {
                HomeView(model:model,onReturnToGarden:{
                    model.suspend()
                    showsSky = false
                })
            } else {
                GardenView(model:model,isHome:true,onStartCollect:model.openStarCamera,onClose:{ showsSky = true })
                    .fullScreenCover(isPresented:$model.showsStarCamera) { StarCameraView(model:model) }
            }
        }
        .environment(\.locale,Locale(identifier:"en"))
    }
}

#Preview { ContentView() }
