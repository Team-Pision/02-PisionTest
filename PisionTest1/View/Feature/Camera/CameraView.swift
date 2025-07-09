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
  }
  
  func makeUIView(context: Context) -> CameraPreviewView {
    let view = CameraPreviewView()
    view.backgroundColor = .clear
    view.previewLayer.session = session
    view.previewLayer.videoGravity = .resizeAspectFill

    return view
  }
  
  func updateUIView(_ uiView: CameraPreviewView, context: Context) {
    uiView.previewLayer.frame = uiView.bounds
  }
}
