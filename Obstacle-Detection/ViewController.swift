//
//  ViewController.swift
//  Obstacle-Detection
//
//  Created by Edith jiang on 2019/3/2.
//  Copyright © 2019年 Kaihan Zhu. All rights reserved.
//

import UIKit
import AVFoundation

class ViewController: UIViewController, AVCaptureDepthDataOutputDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    let captureSession = AVCaptureSession()
    let imageView = UIImageView()
    let previewView = UIImageView()
    let dataOutputQueue = DispatchQueue(label: "DepthQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    let depthOutput = AVCaptureDepthDataOutput()
    let videoOutput = AVCaptureVideoDataOutput()
    var captureSync: AVCaptureDataOutputSynchronizer?

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        // Request access for cameras.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: // The user has previously granted access to the camera.
            self.initVideoCapture()
            
        case .notDetermined: // The user has not yet been asked for camera access.
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.initVideoCapture()
                }
            }
            
        case .denied: // The user has previously denied access.
            return
        case .restricted: // The user can't grant access due to restrictions.
            return
        }
        
        
        self.view.addSubview(self.imageView)
        
        self.view.addSubview(self.previewView)
        
    }
    
    func initVideoCapture() {
        
        
        self.captureSession.beginConfiguration()
        self.captureSession.sessionPreset = .photo
        
        // Confugure for dual cameras device.
        let videoDevice = AVCaptureDevice.default(.builtInDualCamera,
                                                  for: .video, position: .unspecified)
        try? videoDevice?.lockForConfiguration()
        videoDevice?.focusMode = .continuousAutoFocus
        
        // Add dual camera input to session.
        guard
            let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice!),
            self.captureSession.canAddInput(videoDeviceInput)
            else { return }
        self.captureSession.addInput(videoDeviceInput)
        
        // Add depth data output to session.
        self.depthOutput.setDelegate(self, callbackQueue: DispatchQueue.main)
        guard self.captureSession.canAddOutput(self.depthOutput) else { return }
        self.captureSession.addOutput(self.depthOutput)
        
        self.videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue.main)
        guard self.captureSession.canAddOutput(self.videoOutput) else {return}
        self.captureSession.addOutput(self.videoOutput)
        
        self.captureSync = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, depthOutput])
        
        self.captureSession.commitConfiguration()
        self.captureSession.startRunning()
        videoDevice?.unlockForConfiguration()
        
    }
    
    
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        let rawimage = CIImage(cvPixelBuffer: depthData.depthDataMap)
        
        let temporaryContext = CIContext()
        guard let videoImage = temporaryContext.createCGImage(
            rawimage,
            from: CGRect(
                x: 0, y: 0,
                width: CVPixelBufferGetWidth(depthData.depthDataMap),
                height: CVPixelBufferGetHeight(depthData.depthDataMap)
            )
        ) else {return}
        let image = UIImage(cgImage: videoImage, scale: 1.0, orientation: .right)
        self.imageView.image = image
        self.imageView.frame = CGRect(origin: CGPoint(x: 0, y: 0), size: image.size)
        self.previewView.frame = CGRect(origin: CGPoint(x: 0, y: self.view.bounds.height / 2), size: image.size)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let videoImage = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return }
        
        self.previewView.image = UIImage(cgImage: videoImage, scale: 1.0, orientation: .right)
        
    }


}

