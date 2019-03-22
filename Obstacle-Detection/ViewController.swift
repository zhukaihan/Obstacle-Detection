//
//  ViewController.swift
//  Obstacle-Detection
//
//  Created by Edith jiang on 2019/3/2.
//  Copyright © 2019年 Kaihan Zhu. All rights reserved.
//

import UIKit
import AVFoundation
import Zip


class ViewController: UIViewController, AVCaptureDepthDataOutputDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureDataOutputSynchronizerDelegate {
    
    
    
    let PHOTO_FOLDER_NAME = "Obstacle-Detection-imgs"
    
    let captureSession = AVCaptureSession()
    let depthView = UIImageView()
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
        
        
        self.view.addSubview(self.depthView)
        
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
        guard self.captureSession.canAddOutput(self.depthOutput) else { return }
        self.captureSession.addOutput(self.depthOutput)
        if let connection = self.depthOutput.connections.first {
            connection.videoOrientation = .landscapeRight
        }
        
        guard self.captureSession.canAddOutput(self.videoOutput) else {return}
        self.captureSession.addOutput(self.videoOutput)
        if let connection = self.videoOutput.connections.first {
            connection.videoOrientation = .landscapeRight
        }
        
        self.captureSync = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, depthOutput])
        self.captureSync?.setDelegate(self, queue: dataOutputQueue)
        
        self.captureSession.commitConfiguration()
        self.captureSession.startRunning()
        videoDevice?.unlockForConfiguration()
        
    }
    
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        guard let depthData = synchronizedDataCollection[self.depthOutput] as? AVCaptureSynchronizedDepthData else {return}
        guard let imgData = synchronizedDataCollection[self.videoOutput] as? AVCaptureSynchronizedSampleBufferData else {return}
        
        let depthDatMap = depthData.depthData.depthDataMap
        let rawimage = CIImage(cvPixelBuffer: depthDatMap)
        
        // Convert depth data to an image to show.
        let temporaryContext = CIContext()
        guard let depthImg = temporaryContext.createCGImage(
            rawimage,
            from: CGRect(
                x: 0, y: 0,
                width: CVPixelBufferGetWidth(depthDatMap),
                height: CVPixelBufferGetHeight(depthDatMap)
            )
        ) else {return}
        
        // Convert image buffer data to image to show.
        guard let imageBuffer = CMSampleBufferGetImageBuffer(imgData.sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let videoImage = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return }
        
        // Resize image to the same size as depth map.
        let context = CGContext(
            data: nil,
            width: depthImg.width, height: depthImg.height,
            bitsPerComponent: depthImg.bitsPerComponent, bytesPerRow: depthImg.bytesPerRow,
            space: depthImg.colorSpace!, bitmapInfo: depthImg.bitmapInfo.rawValue
        )
        context!.interpolationQuality = .high
        context!.draw(videoImage, in: CGRect(x: 0, y: 0, width: depthImg.width, height: depthImg.height))
        let scaled = context?.makeImage()
        
        // Show imgs.
        self.showDepthImg(depthImg)
        self.showVideoImg(scaled!)
    }
    
    func showDepthImg(_ videoImage: CGImage) {
        DispatchQueue.main.async {
            let image = UIImage(cgImage: videoImage, scale: 1.0, orientation: .right)
            self.depthView.image = image
            self.depthView.frame = CGRect(origin: CGPoint(x: 0, y: 0), size: image.size)
        }
    }
    
    func showVideoImg(_ videoImage: CGImage) {
        DispatchQueue.main.async {
            self.previewView.image = UIImage(cgImage: videoImage, scale: 1.0, orientation: .right)
            self.previewView.frame = CGRect(origin: CGPoint(x: 0, y: self.depthView.frame.maxY), size: (self.previewView.image?.size)!)
        }
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
            let photoFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(PHOTO_FOLDER_NAME)
            try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true, attributes: nil)
            
            let imgName = curTimeStamp()
            
            if let realImg = self.previewView.image {
                if let data = realImg.pngData() {
                    do {
                        try data.write(to: photoFolder.appendingPathComponent(imgName + "_realImg.png"))
                    } catch {
                        print("shit happened when saving realImg" + error.localizedDescription)
                    }
                }
            }
            if let depthImg = self.depthView.image {
                if let data = depthImg.pngData() {
                    do {
                        try data.write(to: photoFolder.appendingPathComponent(imgName + "_depthImg.png"))
                    } catch {
                        print("shit happened when saving depthImg" + error.localizedDescription)
                    }
                }
            }
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
    }

}

