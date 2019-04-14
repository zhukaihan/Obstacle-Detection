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


class ViewController: UIViewController, ODCaptureSessionDelegate, ObstacleDetectorDelegate {
    
    
    
    let PHOTO_FOLDER_NAME = "original"
    let BG_DEFAULT_COLOR = UIColor.black
    let PHOTO_CAPTURE_BG_COLOR = UIColor.white
    let PHOTO_DELETE_BG_COLOR = UIColor.green
    
    
    var captureSession: ODCaptureSession?
    
    @IBOutlet var modelOutputView: UIImageView!
    @IBOutlet var depthView: UIImageView!
    
    let obstacleDetector = ObstacleDetector()
    
    var depthImg: ODImage?
    var realImg: CGImage?
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        // Request access for cameras.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: // The user has previously granted access to the camera.
            self.captureSession = ODCaptureSession(withSuperViewController: self)
            self.captureSession?.setDelegate(newDeleg: self)
            self.captureSession?.startRunning()
            
        case .notDetermined: // The user has not yet been asked for camera access.
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.captureSession = ODCaptureSession(withSuperViewController: self)
                    self.captureSession?.setDelegate(newDeleg: self)
                    self.captureSession?.startRunning()
                }
            }
            
        case .denied: // The user has previously denied access.
            return
        case .restricted: // The user can't grant access due to restrictions.
            return
        }
        
        self.obstacleDetector.setDelegate(self)
        
    }
    
    
    func restoreBgColor() {
        UIView.animate(withDuration: 1.0, animations: {
            self.view.backgroundColor = self.BG_DEFAULT_COLOR
        })
    }
    
    
    func depthDataOutput(withODCaptureSession odCaptureSession: ODCaptureSession, withDepthData depthData: AVDepthData) {
        // Convert depth data to an image to show.
        guard let candidateDepthImg = ODImage(withCVPixelBuffer: depthData.depthDataMap) else { return }
        //candidateDepthImg.filter()
        self.depthImg = candidateDepthImg
        
        guard let depthCGImg = self.depthImg!.toCGImg() else { return }
        DispatchQueue.main.async {
            self.depthView.image = UIImage(cgImage: depthCGImg)
        }
    }
    
    
    func imageDataOutput(withODCaptureSession odCaptureSession: ODCaptureSession, withImageData sampleBuffer: CMSampleBuffer) {
        obstacleDetector.runModelOn(withBuffer: sampleBuffer)
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
        // Store img to file.
        guard let photoFolder = createFolder(withName: PHOTO_FOLDER_NAME) else { return }
        //guard let photoWithDepthFolder = createFolder(withName: PHOTO_WITH_DEPTH_FOLDER_NAME) else { return }
        
        let imgName = curTimeStamp()
        let photoPath = photoFolder.appendingPathComponent(imgName + ".png")
        
        if (
            (ODImage.writeTo(url: photoPath, withName: imgName, forImg: self.realImg))
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
    
    
    @IBAction func clearAllPhotos(_ sender: UIButton) {
        if (deleteFolder(withName: PHOTO_FOLDER_NAME)) {
            self.view.backgroundColor = self.PHOTO_DELETE_BG_COLOR
            self.restoreBgColor()
        }
    }
    
    
    func obstacleReport(byDetector detector: ObstacleDetector, doesExistObstacle isObstacle: Bool) {
        
    }
    
    
    func obstacleReport(byDetector detector: ObstacleDetector, img: CGImage, realImg: CGImage) {
        self.realImg = realImg
        DispatchQueue.main.async {
            self.modelOutputView.image = UIImage(cgImage: img)
        }
    }

}

