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
    
    
    let PHOTO_FOLDER_NAME = "original"
    let PHOTO_WITH_DEPTH_FOLDER_NAME = "withdepth"
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
    
    var depthImg: ODImage?
    var realImg: ODImage?
    
    
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
        
        //let setting = NSDictionary()
        //setting.setValue(NSNumber(value: kCMPixelFormat_32ARGB), forKey: kCVPixelBufferPixelFormatTypeKey)
        //self.videoOutput.setValue(kCMPixelFormat_32ARGB, forKey: kCVPixelBufferPixelFormatTypeKey as String)
        guard self.captureSession.canAddOutput(self.videoOutput) else {return}
        self.captureSession.addOutput(self.videoOutput)
        guard let videoConn = self.videoOutput.connections.first else { return }
        videoConn.videoOrientation = .landscapeRight
        self.videoOutput.videoSettings![kCVPixelBufferPixelFormatTypeKey as String] = kCMPixelFormat_32BGRA
        
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
        guard let candidateDepthImg = ODImage(withCVPixelBuffer: depthData.depthData.depthDataMap) else { return }
        candidateDepthImg.filter()
        self.depthImg = candidateDepthImg
        
        // Convert image buffer data to image to show.
        // And resize image to the same size as depth map.
        guard let scaledImg = ODImage(withCMSampleBuffer: imgData.sampleBuffer) else { return }
        self.realImg = scaledImg
        
        // Show imgs.
        guard let scaledCGImg = self.realImg!.toCGImg() else { return }
        guard let depthCGImg = self.depthImg!.toCGImg() else { return }
        DispatchQueue.main.async {
            self.previewView.image = UIImage(cgImage: scaledCGImg)
            self.depthView.image = UIImage(cgImage: depthCGImg)
        }
        
        guard let storeImgCandidate = ODImage(withODImage: scaledImg)!.addToAlpha(withImg: self.depthImg) else { return }
        self.storeImg = storeImgCandidate
        
        //obstacleDetector.detectObstacle(withImg: self.storeImg!)
        obstacleDetector.runModelOn(withBuffer: imgData.sampleBuffer)
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
    
    
    func getDocumentFolder() -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    
    func createFolder(withName name: String) -> URL? {
        let folder = getDocumentFolder().appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
        } catch {
            return nil
        }
        return folder
    }
    
    
    func deleteFolder(withName name: String) -> Bool {
        let folder = getDocumentFolder().appendingPathComponent(name, isDirectory: true)
        do {
            try FileManager.default.removeItem(at: folder)
        } catch {
            return false
        }
        return true
    }
    
    
    func shareItems(items: [Any]) {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: [])
        self.present(vc, animated: true, completion: nil)
    }
    
    
    @IBAction func takePhoto(_ sender: UIButton) {
        if (self.storeImg == nil) {
            return
        }
        
        // Store img to file.
        guard let photoFolder = createFolder(withName: PHOTO_FOLDER_NAME) else { return }
        guard let photoWithDepthFolder = createFolder(withName: PHOTO_WITH_DEPTH_FOLDER_NAME) else { return }
        
        let imgName = curTimeStamp()
        let photoPath = photoFolder.appendingPathComponent(imgName + ".png")
        let photoWithDepthPath = photoWithDepthFolder.appendingPathComponent(imgName + ".png")
        
        if (
            (self.realImg?.writeTo(url: photoPath, withName: imgName))! &&
            (self.storeImg?.writeTo(url: photoWithDepthPath, withName: imgName))!
        ) {
            self.view.backgroundColor = self.PHOTO_CAPTURE_BG_COLOR
            self.restoreBgColor()
        }
    }
    
    
    @IBAction func exportOriginalPhotos(_ sender: UIButton) {
        do {
            let folderUrl = getDocumentFolder()
            
            let photoFolder = folderUrl.appendingPathComponent(PHOTO_FOLDER_NAME, isDirectory: true)
            let zipPath = folderUrl.appendingPathComponent("OriginalPhotos.zip")
            
            try Zip.zipFiles(paths: [photoFolder], zipFilePath: zipPath, password: nil, progress: nil)
            
            shareItems(items: [zipPath])
        } catch {
            print("shit happened when zipping" + error.localizedDescription)
        }
    }
    
    
    @IBAction func exportPhotosWithDepth(_ sender: UIButton) {
        do {
            let folderUrl = getDocumentFolder()
            
            let photoFolder = folderUrl.appendingPathComponent(PHOTO_WITH_DEPTH_FOLDER_NAME, isDirectory: true)
            let zipPath = folderUrl.appendingPathComponent("PhotosWithDepth.zip")
            
            try Zip.zipFiles(paths: [photoFolder], zipFilePath: zipPath, password: nil, progress: nil)
            
            shareItems(items: [zipPath])
        } catch {
            print("shit happened when zipping" + error.localizedDescription)
        }
    }
    
    
    @IBAction func clearAllPhotos(_ sender: UIButton) {
        if (
            deleteFolder(withName: PHOTO_FOLDER_NAME) &&
            deleteFolder(withName: PHOTO_WITH_DEPTH_FOLDER_NAME)
        ) {
            self.view.backgroundColor = self.PHOTO_DELETE_BG_COLOR
            self.restoreBgColor()
        }
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
    
    
    func obstacleReport(byDetector detector: ObstacleDetector, message msg: String) {
        DispatchQueue.main.async {
            self.detectionInfoLabel.text = msg
            self.detectionInfoLabel.textColor = self.ALERT_TEXT_DEFAULT_COLOR
        }
    }

}

