//
//  ContentView.swift
//  celyx
//
import SwiftUI

struct ContentView: View {
    @State private var model = HomeViewModel()
    var body: some View {
        HomeView(model:model)
            .environment(\.locale,Locale(identifier:"en"))
    }
}

#Preview { ContentView() }
