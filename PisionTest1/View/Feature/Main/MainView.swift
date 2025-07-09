//
//  MainView.swift
//  PisionTest1
//
//  Created by 여성일 on 7/9/25.
//

import AVFoundation
import SwiftUI

struct MainView: View {
  @StateObject private var cameraManager = CameraManager()
  
  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      
      VStack(spacing: 20) {
        // 카메라 뷰 + 관절 오버레이
        ZStack {
          CameraView(session: cameraManager.session)
          
          // 관절 오버레이
//          PoseOverlayView(bodyPosePoints: cameraManager.bodyPosePoints)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
          RoundedRectangle(cornerRadius: 20)
            .stroke(stateColor, lineWidth: 3)
        )
        .padding()
        
        // 상태 표시
        VStack(spacing: 10) {
          Text("현재 상태")
            .font(.headline)
            .foregroundColor(.gray)
          
          Text(cameraManager.currentState)
            .font(.largeTitle)
            .fontWeight(.bold)
            .foregroundColor(stateColor)
            .padding()
            .background(
              RoundedRectangle(cornerRadius: 15)
                .fill(stateColor.opacity(0.2))
            )
          
          // 관절 개수 표시 (디버깅용)
          if !cameraManager.bodyPosePoints.isEmpty {
            Text("감지된 관절: \(cameraManager.bodyPosePoints.count)개")
              .font(.caption)
              .foregroundColor(.gray)
              .padding(.top, 5)
          }
        }
        .padding(.bottom, 30)
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
  
  // 상태에 따른 색상
  private var stateColor: Color {
    if cameraManager.currentState.contains("Concentration") {
      return .green
    } else if cameraManager.currentState.contains("Snooze") {
      return .orange
    } else if cameraManager.currentState.contains("감지되지 않음") {
      return .red
    } else {
      return .gray
    }
  }
}

#Preview {
  MainView()
}
