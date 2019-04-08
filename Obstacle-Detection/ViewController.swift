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
    
    
    let IS_INFERENCING = true
    
    
    var isInference = false
    var captureSession: AVCaptureSession?
    
    @IBOutlet var resultView: UIImageView!
    @IBOutlet var previewView: UIImageView!
    
    let obstacleDetector = ObstacleDetector()
    
    var storeImg: ODImage?
    @IBOutlet var detectionInfoLabel: UILabel!
    
    var resultImg: ODImage?
    var realImg: ODImage?
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        // Request access for cameras.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: // The user has previously granted access to the camera.
            if self.IS_INFERENCING {
                self.captureSession = ODInferenceCaptureSession(withDelegate: self)
            } else {
                self.captureSession = ODImageCaptureSession(withDelegate: self)
            }
            
        case .notDetermined: // The user has not yet been asked for camera access.
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    if self.IS_INFERENCING {
                        self.captureSession = ODInferenceCaptureSession(withDelegate: self)
                    } else {
                        self.captureSession = ODImageCaptureSession(withDelegate: self)
                    }
                }
            }
            
        case .denied: // The user has previously denied access.
            return
        case .restricted: // The user can't grant access due to restrictions.
            return
        }
        
        
        if (self.captureSession != nil) {
            self.captureSession?.startRunning()
        }
        
        
        self.obstacleDetector.setDelegate(self)
        
    }
    
    
    func restoreBgColor() {
        UIView.animate(withDuration: 1.0, animations: {
            self.view.backgroundColor = self.BG_DEFAULT_COLOR
        })
    }
    
    
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        if (self.captureSession == nil) {
            return
        }
        guard let depthData = synchronizedDataCollection[(self.captureSession! as! ODImageCaptureSession).depthOutput] as? AVCaptureSynchronizedDepthData else {return}
        guard let imgData = synchronizedDataCollection[(self.captureSession! as! ODImageCaptureSession).imageVideoOutput] as? AVCaptureSynchronizedSampleBufferData else {return}
        
        // Convert depth data to an image to show.
        guard let candidateDepthImg = ODImage(withCVPixelBuffer: depthData.depthData.depthDataMap) else { return }
        candidateDepthImg.filter()
        self.resultImg = candidateDepthImg
        
        // Convert image buffer data to image to show.
        // And resize image to the same size as depth map.
        guard let scaledImg = ODImage(withCMSampleBuffer: imgData.sampleBuffer) else { return }
        self.realImg = scaledImg
        
        // Show imgs.
        guard let scaledCGImg = self.realImg!.toCGImg() else { return }
        guard let depthCGImg = self.resultImg!.toCGImg() else { return }
        DispatchQueue.main.async {
            self.previewView.image = UIImage(cgImage: scaledCGImg)
            self.resultView.image = UIImage(cgImage: depthCGImg)
        }
        
        guard let storeImgCandidate = ODImage(withODImage: scaledImg)!.addToAlpha(withImg: self.resultImg) else { return }
        self.storeImg = storeImgCandidate
    }
    
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        // Convert image buffer data to image to show.
        // And resize image to the same size as depth map.
        guard let scaledImg = ODImage(withCMSampleBuffer: sampleBuffer) else { return }
        self.realImg = scaledImg
        
        // Show imgs.
        guard let scaledCGImg = self.realImg!.toCGImg() else { return }
        DispatchQueue.main.async {
            self.previewView.image = UIImage(cgImage: scaledCGImg)
        }
        
        obstacleDetector.runModelOn(withBuffer: sampleBuffer)
    }
    
    
    @IBAction func toggleDepthMode(_ sender: UISwitch) {
        //self.depthOutput.isFilteringEnabled = sender.isOn
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
            self.storeImg = self.realImg
        }
        
        // Store img to file.
        guard let photoFolder = createFolder(withName: PHOTO_FOLDER_NAME) else { return }
        //guard let photoWithDepthFolder = createFolder(withName: PHOTO_WITH_DEPTH_FOLDER_NAME) else { return }
        
        let imgName = curTimeStamp()
        let photoPath = photoFolder.appendingPathComponent(imgName + ".png")
        //let photoWithDepthPath = photoWithDepthFolder.appendingPathComponent(imgName + ".png")
        
        if (
            (self.realImg?.writeTo(url: photoPath, withName: imgName))!// &&
            //(self.storeImg?.writeTo(url: photoWithDepthPath, withName: imgName))!
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
    
    
    func obstacleReport(byDetector detector: ObstacleDetector, img: ODImage) {
        DispatchQueue.main.async {
            self.resultImg = img
            self.resultView.image = UIImage(cgImage: img.toCGImg()!)
        }
    }

}

