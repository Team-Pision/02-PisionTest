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
  
  @StateObject private var cameraManager = CameraManager()
}

extension MainView {
  var body: some View {
    ZStack {
      Color.clear.ignoresSafeArea()
      
      VStack {
        CameraView(session: cameraManager.session)
        
        VStack {
          Text("rolls: \(cameraManager.rollAngles)") // 고개를 좌/우로 기울이는 동작
          Text("yaw: \(cameraManager.yawAngles)") // 고개를 좌/우로 도리도리 하는 동작
        }
        .font(.headline)
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
