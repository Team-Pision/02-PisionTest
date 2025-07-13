//
//  CameraManager.swift
//  PisionTest1
//
//  Created by 여성일 on 7/9/25.
//

import AVFoundation
import SwiftUI
import Vision
import CoreML

final class CameraManager: NSObject, ObservableObject {
  let session = AVCaptureSession()
  @Published var currentState = "대기 중..."
  
  // 관절 좌표를 저장할 프로퍼티 추가
  @Published var bodyPosePoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint] = [:]
  
  private let videoOutput = AVCaptureVideoDataOutput()
  private var isSessionConfigured = false
  private let sessionQueue = DispatchQueue(label: "CameraSessionQueue")
  private let processingQueue = DispatchQueue(label: "ProcessingQueue")
  
  // Vision 관련 프로퍼티
  private var bodyPoseRequest: VNDetectHumanBodyPoseRequest?
  private var mlModel: pisionModel22?
  
  // 30개의 프레임 시퀀스를 저장하는 버퍼
  private var poseObservationBuffer: [VNHumanBodyPoseObservation] = []
  
  override init() {
    super.init()
    setupVision()
  }
  
  private func setupVision() {
    // Core ML 모델 로드
    do {
      let config = MLModelConfiguration()
      mlModel = try pisionModel22(configuration: config)
      print("PisionTestModel 로드 성공")
    } catch {
      print("모델 로드 실패: \(error)")
    }
    
    // Body Pose 감지 요청 설정
    bodyPoseRequest = VNDetectHumanBodyPoseRequest { [weak self] request, error in
      if let error = error {
        print("Body pose 감지 에러: \(error)")
        return
      }
      
      self?.processBodyPoseObservations(request.results as? [VNHumanBodyPoseObservation])
    }
  }
  
  func startSession() {
    sessionQueue.async {
      if !self.session.isRunning {
        self.session.startRunning()
      }
    }
  }
  
  func stopSession() {
    sessionQueue.async {
      if self.session.isRunning {
        self.session.stopRunning()
      }
    }
  }
  
  func requestAndCheckPermissions() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        if granted {
          self?.configureSessionIfNeeded()
        } else {
          print("사용자가 카메라 접근을 거부했습니다.")
        }
      }
      
    case .authorized:
      configureSessionIfNeeded()
      
    case .restricted, .denied:
      print("카메라 접근이 제한되었거나 거부됨")
      
    @unknown default:
      print("알 수 없는 권한 상태")
    }
  }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    
    processingQueue.async { [weak self] in
      self?.detectBodyPose(in: pixelBuffer)
    }
  }
}

// MARK: - Private Methods
extension CameraManager {
  private func configureSession() {
    session.beginConfiguration()
    
    // 카메라 입력 설정
    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
          let input = try? AVCaptureDeviceInput(device: device),
          session.canAddInput(input) else {
      print("Log: 카메라 인풋 설정 실패")
      session.commitConfiguration()
      return
    }
    
    session.addInput(input)
    
    // 비디오 출력 설정
    videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
    videoOutput.alwaysDiscardsLateVideoFrames = true
    videoOutput.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    ]
    
    if session.canAddOutput(videoOutput) {
      session.addOutput(videoOutput)
      
      // 비디오 방향 설정
      if let connection = videoOutput.connection(with: .video) {
        if #available(iOS 17.0, *) {
          connection.videoRotationAngle = 0 // portrait
        } else {
          connection.videoOrientation = .portrait
        }
        if connection.isVideoMirroringSupported {
          connection.isVideoMirrored = true
        }
      }
    }
    
    session.commitConfiguration()
  }
  
  private func configureSessionIfNeeded() {
    guard !isSessionConfigured else {
      print("이미 세션이 구성되어 있음")
      return
    }
    isSessionConfigured = true
    configureSession()
  }
  
  private func detectBodyPose(in pixelBuffer: CVPixelBuffer) {
    guard let request = bodyPoseRequest else { return }
    
    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
    
    do {
      try handler.perform([request])
    } catch {
      print("Body pose 감지 실행 실패: \(error)")
    }
  }
  
  private func processBodyPoseObservations(_ observations: [VNHumanBodyPoseObservation]?) {
    guard let observations = observations,
          let observation = observations.first else {
      // 사람이 감지되지 않음
      DispatchQueue.main.async { [weak self] in
        self?.currentState = "사람이 감지되지 않음"
        self?.bodyPosePoints = [:]
      }
      return
    }
    
    // 모든 관절 좌표 추출
    var detectedPoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint] = [:]
    
    do {
      // 주요 관절들
      let joints: [VNHumanBodyPoseObservation.JointName] = [
        .nose, .leftEye, .rightEye, .leftEar, .rightEar,
        .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
        .leftWrist, .rightWrist, .leftHip, .rightHip,
        .leftKnee, .rightKnee, .leftAnkle, .rightAnkle
      ]
      
      for joint in joints {
        let point = try observation.recognizedPoint(joint)
        if point.confidence > 0.3 { // 신뢰도가 0.3 이상인 것만
          detectedPoints[joint] = point
        }
      }
      
      DispatchQueue.main.async { [weak self] in
        self?.bodyPosePoints = detectedPoints
      }
      
    } catch {
      print("관절 추출 실패: \(error)")
    }
    
    // 버퍼 업데이트 함수
    updatePoseBuffer(with: observation)
  }
  
  // 버퍼 업데이트 함수
  private func updatePoseBuffer(with observation: VNHumanBodyPoseObservation) {
      poseObservationBuffer.append(observation)
      
      if poseObservationBuffer.count > 30 {
          poseObservationBuffer.removeFirst()
      }
      
      if poseObservationBuffer.count == 30 {
          classifyPoseSequence(from: poseObservationBuffer)
      }
  }

  
  // 임시 시뮬레이션 함수
  private func simulatePoseClassification(from observation: VNHumanBodyPoseObservation) {
    do {
      // 머리와 어깨의 상대적 위치로 간단한 판별
      let nose = try observation.recognizedPoint(.nose)
      let leftShoulder = try observation.recognizedPoint(.leftShoulder)
      let rightShoulder = try observation.recognizedPoint(.rightShoulder)
      
      if nose.confidence > 0.3 && leftShoulder.confidence > 0.3 && rightShoulder.confidence > 0.3 {
        // 머리가 어깨보다 낮으면 졸고 있다고 가정
        let shoulderY = (leftShoulder.y + rightShoulder.y) / 2
        let headTilt = nose.y - shoulderY
        
        let state = headTilt > 0.1 ? "Snooze" : "Concentration"
        let confidence = abs(headTilt) * 100
        
        DispatchQueue.main.async { [weak self] in
          self?.currentState = "\(state) (신뢰도: \(String(format: "%.1f%%", min(confidence, 95))))"
        }
      }
    } catch {
      print("포즈 포인트 추출 실패: \(error)")
    }
  }
  
  private func classifyPoseSequence(from observations: [VNHumanBodyPoseObservation]) {
      print("🔍 classifyPoseSequence 시작")

      guard let mlModel = mlModel else {
          print("❌ ML 모델이 로드되지 않았습니다")
          return
      }

      do {
          let multiArray = try MLMultiArray(shape: [30, 3, 18], dataType: .float32)
          for i in 0..<multiArray.count {
              multiArray[i] = 0
          }

          let jointMapping: [(VNHumanBodyPoseObservation.JointName, Int)] = [
              (.nose, 0), (.leftEye, 1), (.rightEye, 2), (.leftEar, 3), (.rightEar, 4),
              (.leftShoulder, 5), (.rightShoulder, 6), (.leftElbow, 7), (.rightElbow, 8),
              (.leftWrist, 9), (.rightWrist, 10), (.leftHip, 11), (.rightHip, 12),
              (.leftKnee, 13), (.rightKnee, 14), (.leftAnkle, 15), (.rightAnkle, 16),
              (.neck, 17)
          ]

          for (frameIndex, observation) in observations.enumerated() {
              for (joint, jointIndex) in jointMapping {
                  if jointIndex < 17 {
                      if let point = try? observation.recognizedPoint(joint) {
                          multiArray[[frameIndex, 0, jointIndex] as [NSNumber]] = NSNumber(value: Float(point.x))
                          multiArray[[frameIndex, 1, jointIndex] as [NSNumber]] = NSNumber(value: Float(point.y))
                          multiArray[[frameIndex, 2, jointIndex] as [NSNumber]] = NSNumber(value: Float(point.confidence))
                      }
                  } else {
                      if let l = try? observation.recognizedPoint(.leftShoulder),
                         let r = try? observation.recognizedPoint(.rightShoulder) {
                          let neckX = (l.x + r.x) / 2
                          let neckY = (l.y + r.y) / 2
                          let neckConf = (l.confidence + r.confidence) / 2
                          multiArray[[frameIndex, 0, jointIndex] as [NSNumber]] = NSNumber(value: Float(neckX))
                          multiArray[[frameIndex, 1, jointIndex] as [NSNumber]] = NSNumber(value: Float(neckY))
                          multiArray[[frameIndex, 2, jointIndex] as [NSNumber]] = NSNumber(value: Float(neckConf))
                      }
                  }
              }
          }

          let input = PisionTestModelInput(poses: multiArray)
          let prediction = try mlModel.model.prediction(from: input)

          if let output = prediction.featureValue(for: "label")?.stringValue {
              print("✅ 예측 레이블: \(output)")
              DispatchQueue.main.async { [weak self] in
                  self?.currentState = output
              }
          } else {
              print("⚠️ label 예측 실패")
          }

      } catch {
          print("❌ 예측 중 오류 발생: \(error)")
      }
  }
}
