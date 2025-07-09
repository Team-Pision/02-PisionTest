//
//  CameraView.swift
//  PisionTest1
//
//  Created by 여성일 on 7/9/25.
//

import AVFoundation
import SwiftUI
import UIKit

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
