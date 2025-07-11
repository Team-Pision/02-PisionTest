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
  private var mlModel: PisionTestModel?
  
  override init() {
    super.init()
    setupVision()
  }
  
  private func setupVision() {
    // Core ML 모델 로드
    do {
      let config = MLModelConfiguration()
      mlModel = try PisionTestModel(configuration: config)
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
    
    // Core ML 모델로 포즈 분류
    classifyPose(from: observation)
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
  
  private func classifyPose(from observation: VNHumanBodyPoseObservation) {
    print("🔍 classifyPose 시작")
    
    guard let mlModel = mlModel else {
      print("❌ ML 모델이 로드되지 않았습니다")
      // 모델이 없으면 시뮬레이션 사용
      simulatePoseClassification(from: observation)
      return
    }
    
    print("✅ ML 모델 로드 확인")
    
    do {
      // MLMultiArray 생성 (모델의 입력 형식에 맞게)
      // 입력 형태: [120, 3, 18] - 120개 프레임, 3개 좌표(x,y,confidence), 18개 관절
      print("📊 MLMultiArray 생성 시도...")
      let multiArray = try MLMultiArray(shape: [90, 3, 18], dataType: .float32)
      print("✅ MLMultiArray 생성 성공")
      
      // 모든 값을 0으로 초기화
      for i in 0..<multiArray.count {
        multiArray[i] = 0
      }
      
      // 관절 인덱스 매핑 (18개 관절)
      let jointMapping: [(VNHumanBodyPoseObservation.JointName, Int)] = [
        (.nose, 0), (.leftEye, 1), (.rightEye, 2), (.leftEar, 3), (.rightEar, 4),
        (.leftShoulder, 5), (.rightShoulder, 6), (.leftElbow, 7), (.rightElbow, 8),
        (.leftWrist, 9), (.rightWrist, 10), (.leftHip, 11), (.rightHip, 12),
        (.leftKnee, 13), (.rightKnee, 14), (.leftAnkle, 15), (.rightAnkle, 16),
        (.neck, 17)  // 18번째 관절 추가
      ]
      
      // 현재 프레임의 관절 데이터를 첫 번째 프레임(인덱스 0)에만 입력
      print("🦴 관절 데이터 입력 시작...")
      var detectedJointCount = 0
      
      for (joint, index) in jointMapping {
        if index < 17 {  // neck은 Vision에서 직접 제공하지 않으므로 처리
          if let point = try? observation.recognizedPoint(joint) {
            // [프레임=0, 좌표, 관절] 순서로 데이터 입력
            multiArray[[0, 0, index] as [NSNumber]] = NSNumber(value: Float(point.x))      // x
            multiArray[[0, 1, index] as [NSNumber]] = NSNumber(value: Float(point.y))      // y
            multiArray[[0, 2, index] as [NSNumber]] = NSNumber(value: Float(point.confidence)) // confidence
            detectedJointCount += 1
          }
        } else {
          // neck 관절은 leftShoulder와 rightShoulder의 중간점으로 계산
          if let leftShoulder = try? observation.recognizedPoint(.leftShoulder),
             let rightShoulder = try? observation.recognizedPoint(.rightShoulder) {
            let neckX = (leftShoulder.x + rightShoulder.x) / 2
            let neckY = (leftShoulder.y + rightShoulder.y) / 2
            let neckConfidence = (leftShoulder.confidence + rightShoulder.confidence) / 2
            
            multiArray[[0, 0, 17] as [NSNumber]] = NSNumber(value: Float(neckX))
            multiArray[[0, 1, 17] as [NSNumber]] = NSNumber(value: Float(neckY))
            multiArray[[0, 2, 17] as [NSNumber]] = NSNumber(value: Float(neckConfidence))
            detectedJointCount += 1
          }
        }
      }
      
      print("✅ 관절 데이터 입력 완료 (감지된 관절: \(detectedJointCount)/18)")
      print("📐 입력 배열 shape: \(multiArray.shape)")
      
      // 모델 예측 실행
      print("🤖 모델 예측 시작...")
      let input = PisionTestModelInput(poses: multiArray)
      print("✅ PisionTestModelInput 생성 성공")
      
      let prediction = try mlModel.model.prediction(from: input)
      print("✅ 모델 예측 성공")
      
      // 결과 처리
      print("📝 예측 결과 처리 중...")
      if let output = prediction.featureValue(for: "label")?.stringValue {
        print("✅ 예측 레이블: \(output)")
          
          DispatchQueue.main.async { [weak self] in
            self?.currentState = output
          }
//        if let confidenceArray = prediction.featureValue(for: "classLabelProbs")?.dictionaryValue {
//          print("✅ 신뢰도 딕셔너리 획득")
//          
//          // 신뢰도 값 가져오기
//          let confidence = confidenceArray[output] as? Double ?? 0.0
//          print("✅ 최종 신뢰도: \(confidence)")
//          
//          DispatchQueue.main.async { [weak self] in
//            self?.currentState = "\(output) (신뢰도: \(String(format: "%.1f%%", confidence * 100)))"
//          }
//        } else {
//          print("⚠️ classLabelProbs를 찾을 수 없음")
//        }
      } else {
        print("⚠️ label을 찾을 수 없음")
        print("🔍 사용 가능한 feature 이름들:")
        for featureName in prediction.featureNames {
          print("  - \(featureName)")
        }
      }
      
    } catch {
      print("❌ 포즈 분류 실패")
      print("❌ 에러 타입: \(type(of: error))")
      print("❌ 에러 상세: \(error)")
      print("❌ 에러 로컬라이즈드: \(error.localizedDescription)")
      
      // 에러 발생시 임시 시뮬레이션 사용
      simulatePoseClassification(from: observation)
    }
  }
}
