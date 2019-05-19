//
//  ODInferenceSession.swift
//  Obstacle-Detection
//
//  Created by Peter Zhu on 4/6/19.
//  Copyright © 2019 Kaihan Zhu. All rights reserved.
//

import UIKit

protocol ODCaptureSessionDelegate {
    func depthDataOutput(withODCaptureSession odCaptureSession: ODCaptureSession, withDepthData depthData: AVDepthData)
    func imageDataOutput(withODCaptureSession odCaptureSession: ODCaptureSession, withImageData sampleBuffer: CMSampleBuffer)
}

class ODCaptureSession: AVCaptureSession, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureDataOutputSynchronizerDelegate {
    
    let DESIRED_MIN_FPS: CMTimeScale = 10 // Must be less than 30.

    let videoDevice: AVCaptureDevice
    let videoOutput = AVCaptureVideoDataOutput()
    let depthOutput = AVCaptureDepthDataOutput()
    var captureSync: AVCaptureDataOutputSynchronizer?
    
    let modelProcessingQueue = DispatchQueue(label: "odCaptureSessionModelProcessingQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    let depthProcessingQueue = DispatchQueue(label: "odCaptureSessionDepthProcessingQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    var depthDeliveryEnabled = false
    
    var deleg: ODCaptureSessionDelegate?
    
    init(withSuperViewController superViewController: ViewController) {
        
        // Use a video device.
        self.videoDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .unspecified) ?? AVCaptureDevice.default(for: .video)!
        super.init()
        
        self.beginConfiguration()
        self.sessionPreset = .photo
        
        // Confugure for camera device.
        try? self.videoDevice.lockForConfiguration()
        
        // Focus is automatic.
        self.videoDevice.focusMode = .continuousAutoFocus
        
        // Add the camera input to session.
        guard
            let videoDeviceInput = try? AVCaptureDeviceInput(device: self.videoDevice),
            self.canAddInput(videoDeviceInput)
            else { return }
        self.addInput(videoDeviceInput)
        
        // Add video data output to session.
        guard self.canAddOutput(self.videoOutput) else { return }
        self.addOutput(self.videoOutput)
        guard let videoConn = self.videoOutput.connections.first else { return }
        videoConn.videoOrientation = .landscapeRight
        self.videoOutput.videoSettings![kCVPixelBufferPixelFormatTypeKey as String] = kCMPixelFormat_32BGRA
        self.videoOutput.alwaysDiscardsLateVideoFrames = true
        
        if (self.videoDevice.deviceType == .builtInDualCamera) {
            let alert = UIAlertController(
                title: "Do you want depth data?" ,
                message: "This device can output depth data. The side affect is the photos are zoomed to 2x and slightly increased battery usage. ",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "Yes", style: .default, handler: { action in
                self.depthDeliveryEnabled = true
                
                guard self.canAddOutput(self.depthOutput) else { return }
                self.addOutput(self.depthOutput)
                guard let connection = self.depthOutput.connections.first else { return }
                connection.videoOrientation = .landscapeRight
                self.depthOutput.isFilteringEnabled = true
                self.depthOutput.alwaysDiscardsLateDepthData = true
                
                self.captureSync = AVCaptureDataOutputSynchronizer(dataOutputs: [self.videoOutput, self.depthOutput])
                self.captureSync?.setDelegate(self, queue: self.modelProcessingQueue)
            }))
            alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: { action in
                self.depthDeliveryEnabled = false
            }))
        
            DispatchQueue.main.async {
                superViewController.present(alert, animated: true)
            }
        }
        self.captureSync = AVCaptureDataOutputSynchronizer(dataOutputs: [self.videoOutput])
        self.captureSync?.setDelegate(self, queue: self.modelProcessingQueue)
        
        // Set frame rate.
        // Discover maximum frame duration.
        var maxFrameDuration = self.videoDevice.activeVideoMinFrameDuration
        for range in (self.videoDevice.activeFormat.videoSupportedFrameRateRanges) {
            if range.maxFrameDuration > maxFrameDuration {
                maxFrameDuration = range.maxFrameDuration
            }
        }
        
        // Set frame rate.
        let DESIRED_FRAME_DUR: CMTime = CMTime(value: 1, timescale: DESIRED_MIN_FPS)
        if (maxFrameDuration > DESIRED_FRAME_DUR) {
            maxFrameDuration = DESIRED_FRAME_DUR
        }
        self.videoDevice.activeVideoMinFrameDuration = maxFrameDuration
        self.videoDevice.activeVideoMaxFrameDuration = maxFrameDuration
        
        self.videoDevice.unlockForConfiguration()
        
        self.commitConfiguration()
    }
    
    func setDelegate(newDeleg: ODCaptureSessionDelegate) {
        self.deleg = newDeleg
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if (self.deleg == nil) {
            return
        }
        self.deleg?.imageDataOutput(withODCaptureSession: self, withImageData: sampleBuffer)
    }
    
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        if (self.deleg == nil) {
            return
        }
        
        guard let imageData = synchronizedDataCollection[self.videoOutput] as? AVCaptureSynchronizedSampleBufferData else { return }
        if let depthData = synchronizedDataCollection[self.depthOutput] as? AVCaptureSynchronizedDepthData {
            self.depthProcessingQueue.async {
                self.deleg?.depthDataOutput(withODCaptureSession: self, withDepthData: depthData.depthData)
            }
        }
        
        self.deleg?.imageDataOutput(withODCaptureSession: self, withImageData: imageData.sampleBuffer)
        
    }
}
