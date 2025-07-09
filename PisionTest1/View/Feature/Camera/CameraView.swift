//
//  CameraView.swift
//  PisionTest1
//
//  Created by 여성일 on 7/9/25.
//

import AVFoundation
import SwiftUI
import UIKit
import Vision

struct CameraView: UIViewRepresentable {
  let session: AVCaptureSession
  
  final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    
    override func layoutSubviews() {
      super.layoutSubviews()
      previewLayer.frame = bounds
    }
  }
  
  func makeUIView(context: Context) -> CameraPreviewView {
    let view = CameraPreviewView()
    view.backgroundColor = .black
    view.previewLayer.session = session
    view.previewLayer.videoGravity = .resizeAspectFill
    
    // iOS 17.0 이상에서는 videoRotationAngle 사용
    if #available(iOS 17.0, *) {
      view.previewLayer.connection?.videoRotationAngle = 0 // portrait
    } else {
      view.previewLayer.connection?.videoOrientation = .portrait
    }
    
    return view
  }
  
  func updateUIView(_ uiView: CameraPreviewView, context: Context) {
    // 필요시 업데이트 로직
  }
}

struct PoseOverlayView: View {
  let bodyPosePoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
  
  var body: some View {
    Canvas { context, size in
      // 관절 그리기
      for (joint, point) in bodyPosePoints {
        let x = point.x * size.width
        let y = (1 - point.y) * size.height // Vision 좌표계는 Y가 뒤집혀 있음
        
        // 관절 점 그리기
        context.fill(
          Path(ellipseIn: CGRect(x: x - 6, y: y - 6, width: 12, height: 12)),
          with: .color(jointColor(for: joint))
        )
        
        // 외곽선 추가
        context.stroke(
          Path(ellipseIn: CGRect(x: x - 6, y: y - 6, width: 12, height: 12)),
          with: .color(.white),
          lineWidth: 2
        )
      }
      
      // 골격 연결선 그리기
      drawSkeleton(context: context, size: size)
    }
  }
  
  private func drawSkeleton(context: GraphicsContext, size: CGSize) {
    let connections: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
      // 머리
      (.nose, .leftEye), (.nose, .rightEye),
      (.leftEye, .leftEar), (.rightEye, .rightEar),
      
      // 몸통
      (.leftShoulder, .rightShoulder),
      (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
      (.leftHip, .rightHip),
      
      // 팔
      (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
      (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
      
      // 다리
      (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
      (.rightHip, .rightKnee), (.rightKnee, .rightAnkle)
    ]
    
    for (joint1, joint2) in connections {
      if let point1 = bodyPosePoints[joint1],
         let point2 = bodyPosePoints[joint2] {
        let start = CGPoint(
          x: point1.x * size.width,
          y: (1 - point1.y) * size.height
        )
        let end = CGPoint(
          x: point2.x * size.width,
          y: (1 - point2.y) * size.height
        )
        
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        
        context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round))
      }
    }
  }
  
  private func jointColor(for joint: VNHumanBodyPoseObservation.JointName) -> Color {
    switch joint {
    case .nose, .leftEye, .rightEye, .leftEar, .rightEar:
      return .red
    case .leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist:
      return .blue
    case .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle:
      return .green
    default:
      return .white
    }
  }
}
