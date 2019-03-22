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


class ViewController: UIViewController, AVCaptureDepthDataOutputDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    
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
        self.depthOutput.setDelegate(self, callbackQueue: DispatchQueue.main)
        guard self.captureSession.canAddOutput(self.depthOutput) else { return }
        self.captureSession.addOutput(self.depthOutput)
        if let connection = self.depthOutput.connections.first {
            connection.videoOrientation = .landscapeRight
        }
        
        self.videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue.main)
        guard self.captureSession.canAddOutput(self.videoOutput) else {return}
        self.captureSession.addOutput(self.videoOutput)
        if let connection = self.videoOutput.connections.first {
            connection.videoOrientation = .landscapeRight
        }
        
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
        self.depthView.image = image
        self.depthView.frame = CGRect(origin: CGPoint(x: 0, y: 0), size: image.size)
    }
    
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let videoImage = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return }
        
        // Resize image to the same size as depth map.
        guard let depthImg = self.depthView.image?.cgImage else { return }
        
        let context = CGContext(data: nil, width: depthImg.width, height: depthImg.height, bitsPerComponent: depthImg.bitsPerComponent, bytesPerRow: depthImg.bytesPerRow, space: depthImg.colorSpace!, bitmapInfo: depthImg.bitmapInfo.rawValue)
        context!.interpolationQuality = .high
        context!.draw(videoImage, in: CGRect(x: 0, y: 0, width: depthImg.width, height: depthImg.height))
        let scaled = context?.makeImage()
        
        self.previewView.image = UIImage(cgImage: scaled!, scale: 1.0, orientation: .right)
        self.previewView.frame = CGRect(origin: CGPoint(x: 0, y: self.depthView.frame.maxY), size: (self.previewView.image?.size)!)
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
            
            guard let realImg = self.previewView.image?.cgImage else { return }
            //guard let realData = realImg.pngData() else { return }
            guard let depthImg = self.depthView.image?.cgImage else { return }
            //guard let depthData = depthImg.pngData() else { return }
            
            let width = depthImg.width;
            let height = depthImg.height;
            
            let bytesPerPixel = 4;
            let bytesPerRow = bytesPerPixel * width;
            let bitsPerComponent = 8;
            
            let realContext = CGContext(data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            realContext?.draw(realImg, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            let depthContext = CGContext(data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            depthContext?.draw(depthImg, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            guard let realData = realContext?.data?.bindMemory(to: UInt8.self, capacity: width * height) else { return }
            guard let depthData = depthContext?.data?.bindMemory(to: UInt8.self, capacity: width * height) else { return }
            
            var base, offset:Int
            
            for y in 0..<height {
                base = y * height * 4
                for x in 0..<width {
                    offset = base + x * 4
                    realData[offset] = (depthData[offset] + depthData[offset + 1] + depthData[offset + 2]) / 3
                }
            }
            
            
            do {
                try realData.write(to: photoFolder.appendingPathComponent(imgName + "_realImg.png"))
                try depthData.write(to: photoFolder.appendingPathComponent(imgName + "_depthImg.png"))
            } catch {
                print("shit happened when saving img" + error.localizedDescription)
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

