//
//  ContentView.swift
//  celyx
//
//  Created by Ferdiansyah Annora on 02/11/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View { HomeView().environment(\.locale,Locale(identifier:"en")) }
}

#Preview { ContentView() }
