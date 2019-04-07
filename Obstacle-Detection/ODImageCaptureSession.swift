//
//  ODImageCaptureSession.swift
//  Obstacle-Detection
//
//  Created by Peter Zhu on 4/6/19.
//  Copyright © 2019 Kaihan Zhu. All rights reserved.
//

import UIKit

class ODImageCaptureSession: AVCaptureSession {
    
    let DESIRED_MIN_FPS: CMTimeScale = 10 // Must be less than 30.
    
    let frameProcessingQueue = DispatchQueue(label: "ImageCaptureSessionFrameProcessingQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    let depthOutput = AVCaptureDepthDataOutput()
    let imageVideoOutput = AVCaptureVideoDataOutput()
    var captureSync: AVCaptureDataOutputSynchronizer?
    let videoDevice: AVCaptureDevice

    init(withDelegate deleg: AVCaptureDataOutputSynchronizerDelegate) {
        videoDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .unspecified)!
        super.init()
        
        self.beginConfiguration()
        self.sessionPreset = .photo
        
        // Confugure for dual cameras device.
        try? videoDevice.lockForConfiguration()
        
        // Focus is automatic.
        videoDevice.focusMode = .continuousAutoFocus
        
        // Add dual camera input to session.
        guard
            let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
            self.canAddInput(videoDeviceInput)
            else { return }
        self.addInput(videoDeviceInput)
        
        // Add depth data output to session.
        guard self.canAddOutput(self.depthOutput) else { return }
        self.addOutput(self.depthOutput)
        guard let connection = self.depthOutput.connections.first else { return }
        connection.videoOrientation = .landscapeRight
        self.depthOutput.isFilteringEnabled = false
        
        guard self.canAddOutput(self.imageVideoOutput) else { return }
        self.addOutput(self.imageVideoOutput)
        guard let videoConn = self.imageVideoOutput.connections.first else { return }
        videoConn.videoOrientation = .landscapeRight
        
        self.captureSync = AVCaptureDataOutputSynchronizer(dataOutputs: [imageVideoOutput, depthOutput])
        self.captureSync?.setDelegate(deleg, queue: frameProcessingQueue)
        
        // Set frame rate.
        // Discover maximum frame duration.
        var maxFrameDuration = videoDevice.activeDepthDataMinFrameDuration
        for range in (videoDevice.activeDepthDataFormat?.videoSupportedFrameRateRanges)! {
            if range.maxFrameDuration > maxFrameDuration {
                maxFrameDuration = range.maxFrameDuration
            }
        }
        
        // Set frame rate.
        let DESIRED_FRAME_DUR: CMTime = CMTime(value: 1, timescale: DESIRED_MIN_FPS)
        if (maxFrameDuration > DESIRED_FRAME_DUR) {
            maxFrameDuration = DESIRED_FRAME_DUR
        }
        videoDevice.activeVideoMinFrameDuration = maxFrameDuration
        videoDevice.activeVideoMaxFrameDuration = maxFrameDuration
        videoDevice.activeDepthDataMinFrameDuration = maxFrameDuration
        
        videoDevice.unlockForConfiguration()
        
        self.commitConfiguration()
    }
}
