//
//  MainView.swift
//  PisionTest1
//
//  Created by 여성일 on 7/9/25.
//

import AVFoundation
import SwiftUI

struct MainView: View {
  @State private var currentState = "Snooze"
  
  let cameraManager = CameraManager()
}

extension MainView {
  var body: some View {
    ZStack {
      Color.clear.ignoresSafeArea()
      
      VStack {
        CameraView(session: cameraManager.session)
        
        Text("상태: \(currentState)")
          .font(.largeTitle)
      }
    }
    .onAppear {
      cameraManager.requestAndCheckPermissions()
      cameraManager.startSession()
    }
    .onDisappear {
      cameraManager.stopSession()
    }
  }
}

#Preview {
  MainView()
}
