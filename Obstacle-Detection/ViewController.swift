//
//  ViewController.swift
//  Obstacle-Detection
//
//  Created by Edith jiang on 2019/3/2.
//  Copyright © 2019年 Kaihan Zhu. All rights reserved.
//

import UIKit
import AVFoundation
import MobileCoreServices
import Zip


class ViewController: UIViewController, AVCaptureDepthDataOutputDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureDataOutputSynchronizerDelegate, ObstacleDetectorDelegate {
    
    
    let PHOTO_FOLDER_NAME = "Obstacle-Detection-imgs"
    let DESIRED_MIN_FPS: CMTimeScale = 10 // Must be less than 30.
    let BG_DEFAULT_COLOR = UIColor.black
    let PHOTO_CAPTURE_BG_COLOR = UIColor.white
    let PHOTO_DELETE_BG_COLOR = UIColor.green
    let ALERT_TEXT_DEFAULT_COLOR = UIColor.white
    let ALERT_TEXT_DEFAULT_TEXT = "Obstacle Not Detected. "
    let ALERT_TEXT_ALERT_COLOR = UIColor.red
    let ALERT_TEXT_ALERT_TEXT = "Obstacle Detected! "
    
    
    let captureSession = AVCaptureSession()
    @IBOutlet var depthView: UIImageView!
    @IBOutlet var previewView: UIImageView!
    let dataOutputQueue = DispatchQueue(label: "DepthQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    let depthOutput = AVCaptureDepthDataOutput()
    let videoOutput = AVCaptureVideoDataOutput()
    var captureSync: AVCaptureDataOutputSynchronizer?
    
    let obstacleDetector = ObstacleDetector()
    
    var storeImg: ODImage?
    @IBOutlet var detectionInfoLabel: UILabel!
    
    
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
        
        
        self.view.addSubview(self.depthView)
        
        self.view.addSubview(self.previewView)
        
        self.obstacleDetector.setDelegate(self)
        
    }
    
    
    func initVideoCapture() {
        
        self.captureSession.beginConfiguration()
        self.captureSession.sessionPreset = .photo
        
        // Confugure for dual cameras device.
        guard let videoDevice = AVCaptureDevice.default(.builtInDualCamera,
                                                        for: .video, position: .unspecified) else { return }
        try? videoDevice.lockForConfiguration()
        
        // Focus is automatic.
        videoDevice.focusMode = .continuousAutoFocus
        
        // Add dual camera input to session.
        guard
            let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
            self.captureSession.canAddInput(videoDeviceInput)
            else { return }
        self.captureSession.addInput(videoDeviceInput)
        
        // Add depth data output to session.
        guard self.captureSession.canAddOutput(self.depthOutput) else { return }
        self.captureSession.addOutput(self.depthOutput)
        guard let connection = self.depthOutput.connections.first else { return }
        connection.videoOrientation = .landscapeRight
        self.depthOutput.isFilteringEnabled = false
        
        guard self.captureSession.canAddOutput(self.videoOutput) else {return}
        self.captureSession.addOutput(self.videoOutput)
        guard let videoConn = self.videoOutput.connections.first else { return }
        videoConn.videoOrientation = .landscapeRight
        
        self.captureSync = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, depthOutput])
        self.captureSync?.setDelegate(self, queue: dataOutputQueue)
        
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
        
        self.captureSession.commitConfiguration()
        self.captureSession.startRunning()
        
    }
    
    
    func restoreBgColor() {
        UIView.animate(withDuration: 1.0, animations: {
            self.view.backgroundColor = self.BG_DEFAULT_COLOR
        })
    }
    
    
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        guard let depthData = synchronizedDataCollection[self.depthOutput] as? AVCaptureSynchronizedDepthData else {return}
        guard let imgData = synchronizedDataCollection[self.videoOutput] as? AVCaptureSynchronizedSampleBufferData else {return}
        
        // Convert depth data to an image to show.
        guard let depthImg = ODImage(withCVPixelBuffer: depthData.depthData.depthDataMap) else { return }
        
        // Convert image buffer data to image to show.
        // And resize image to the same size as depth map.
        guard let scaledImg = ODImage(withCMSampleBuffer: imgData.sampleBuffer) else { return }
        
        // Show imgs.
        guard let scaledCGImg = scaledImg.toCGImg() else { return }
        guard let depthCGImg = depthImg.toCGImg() else { return }
        DispatchQueue.main.async {
            self.previewView.image = UIImage(cgImage: scaledCGImg)
            self.depthView.image = UIImage(cgImage: depthCGImg)
        }
        
        guard let storeImgCandidate = scaledImg.addToAlpha(withImg: depthImg) else { return }
        self.storeImg = storeImgCandidate
        
        obstacleDetector.detectObstacle(withImg: self.storeImg!)
    }
    
    
    @IBAction func toggleDepthMode(_ sender: UISwitch) {
        self.depthOutput.isFilteringEnabled = sender.isOn
    }
    
    
    func curTimeStamp() -> String {
        let now = Date()
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: now)
    }
    
    
    @IBAction func takePhoto(_ sender: UIButton) {
        do {
            if (self.storeImg == nil) {
                return
            }
            guard let imageToStore = self.storeImg!.toCGImg() else { return }
            
            // Store img to file.
            let photoFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(PHOTO_FOLDER_NAME)
            try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true, attributes: nil)
            
            let imgName = curTimeStamp()
            
            let imgPath = photoFolder.appendingPathComponent(imgName + ".png")
            guard let dest = CGImageDestinationCreateWithURL(imgPath as CFURL, kUTTypePNG, 1, nil) else { return }
            CGImageDestinationAddImage(dest, imageToStore, nil)
            CGImageDestinationFinalize(dest)
            
            self.view.backgroundColor = self.PHOTO_CAPTURE_BG_COLOR
            self.restoreBgColor()
        } catch {
            print("error in creating dir" + error.localizedDescription)
        }
    }
    
    
    @IBAction func exportPhotos(_ sender: UIButton) {
        
        do {
            let folderUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            
            let photoFolder = folderUrl.appendingPathComponent(PHOTO_FOLDER_NAME, isDirectory: true)
            let zipPath = folderUrl.appendingPathComponent("archive.zip")
            
            try Zip.zipFiles(paths: [photoFolder], zipFilePath: zipPath, password: nil, progress: nil)
            
            let vc = UIActivityViewController(activityItems: [zipPath], applicationActivities: [])
            self.present(vc, animated: true, completion: nil)
        } catch {
            print("shit happened when zipping" + error.localizedDescription)
        }
    }
    
    
    @IBAction func clearAllPhotos(_ sender: UIButton) {
        let folderUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let photoFolder = folderUrl.appendingPathComponent(PHOTO_FOLDER_NAME, isDirectory: true)
        try? FileManager.default.removeItem(at: photoFolder)
        
        self.view.backgroundColor = self.PHOTO_DELETE_BG_COLOR
        self.restoreBgColor()
    }
    
    
    func obstacleReport(byDetector detector: ObstacleDetector, doesExistObstacle isObstacle: Bool) {
        DispatchQueue.main.async {
            if (isObstacle) {
                self.detectionInfoLabel.text = self.ALERT_TEXT_ALERT_TEXT
                self.detectionInfoLabel.textColor = self.ALERT_TEXT_ALERT_COLOR
            } else {
                self.detectionInfoLabel.text = self.ALERT_TEXT_DEFAULT_TEXT
                self.detectionInfoLabel.textColor = self.ALERT_TEXT_DEFAULT_COLOR
            }
        }
    }

}

