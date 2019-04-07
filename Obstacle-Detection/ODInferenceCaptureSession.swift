//
//  ODInferenceSession.swift
//  Obstacle-Detection
//
//  Created by Peter Zhu on 4/6/19.
//  Copyright © 2019 Kaihan Zhu. All rights reserved.
//

import UIKit

class ODInferenceCaptureSession: AVCaptureSession {
    
    let DESIRED_MIN_FPS: CMTimeScale = 10 // Must be less than 30.

    let inferenceVideoOutput = AVCaptureVideoDataOutput()
    let frameProcessingQueue = DispatchQueue(label: "InferenceCaptureSessionFrameProcessingQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    var deleg: AVCaptureVideoDataOutputSampleBufferDelegate
    let videoDevice: AVCaptureDevice
    
    init(withDelegate deleg: AVCaptureVideoDataOutputSampleBufferDelegate) {
        self.deleg = deleg
        
        let discoverSession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInDualCamera, .builtInTelephotoCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )
        self.videoDevice = discoverSession.devices.first ?? AVCaptureDevice.default(for: .video)!
        super.init()
        
        self.beginConfiguration()
        self.sessionPreset = .photo
        
        // Confugure for dual cameras device.
        try? self.videoDevice.lockForConfiguration()
        
        // Focus is automatic.
        self.videoDevice.focusMode = .continuousAutoFocus
        
        // Add dual camera input to session.
        guard
            let videoDeviceInput = try? AVCaptureDeviceInput(device: self.videoDevice),
            self.canAddInput(videoDeviceInput)
            else { return }
        self.addInput(videoDeviceInput)
        
        // Add video data output to session.
        guard self.canAddOutput(self.inferenceVideoOutput) else { return }
        self.addOutput(self.inferenceVideoOutput)
        guard let videoConn = self.inferenceVideoOutput.connections.first else { return }
        videoConn.videoOrientation = .landscapeRight
        self.inferenceVideoOutput.videoSettings![kCVPixelBufferPixelFormatTypeKey as String] = kCMPixelFormat_32BGRA
        
        self.inferenceVideoOutput.setSampleBufferDelegate(self.deleg, queue: frameProcessingQueue)
        
        // Set frame rate.
        // Discover maximum frame duration.
        var maxFrameDuration = self.videoDevice.activeDepthDataMinFrameDuration
        for range in (self.videoDevice.activeDepthDataFormat?.videoSupportedFrameRateRanges)! {
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
        self.videoDevice.activeDepthDataMinFrameDuration = maxFrameDuration
        
        self.videoDevice.unlockForConfiguration()
        
        self.commitConfiguration()
    }
}
