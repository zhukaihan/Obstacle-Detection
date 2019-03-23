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


class ViewController: UIViewController, AVCaptureDepthDataOutputDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureDataOutputSynchronizerDelegate {
    
    
    let PHOTO_FOLDER_NAME = "Obstacle-Detection-imgs"
    let FPS: Double = 15
    
    let captureSession = AVCaptureSession()
    @IBOutlet var depthView: UIImageView!
    @IBOutlet var previewView: UIImageView!
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
        guard let videoDevice = AVCaptureDevice.default(.builtInDualCamera,
                                                        for: .video, position: .unspecified) else { return }
        try? videoDevice.lockForConfiguration()
        
        // Focus is automatic.
        videoDevice.focusMode = .continuousAutoFocus
        
        // Set frame rate.
        /*var lowestFormat: AVCaptureDevice.Format?
        var lowestFrameRateRange: AVFrameRateRange?
        
        for format in videoDevice.formats {
            for range in format.videoSupportedFrameRateRanges {
                if lowestFrameRateRange == nil || range.minFrameRate < (lowestFrameRateRange?.minFrameRate)! {
                    lowestFormat = format;
                    lowestFrameRateRange = range;
                    print(range.minFrameRate)
                    print(range.maxFrameRate)
                }
            }
        }
        if lowestFormat != nil && lowestFrameRateRange != nil {
            videoDevice.activeFormat = lowestFormat!;
            videoDevice.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 4)// lowestFrameRateRange!.maxFrameDuration
            videoDevice.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 4)// lowestFrameRateRange!.maxFrameDuration
            //videoDevice.activeDepthDataFormat = lowestFormat!;
            //videoDevice.activeDepthDataMinFrameDuration = lowestFrameRateRange!.maxFrameDuration
            print(lowestFrameRateRange?.minFrameDuration)
            print(lowestFrameRateRange?.maxFrameDuration)
        }*/
        
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
        
        guard self.captureSession.canAddOutput(self.videoOutput) else {return}
        self.captureSession.addOutput(self.videoOutput)
        guard let videoConn = self.videoOutput.connections.first else { return }
        videoConn.videoOrientation = .landscapeRight
        
        self.captureSync = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, depthOutput])
        self.captureSync?.setDelegate(self, queue: dataOutputQueue)
        
        self.captureSession.commitConfiguration()
        self.captureSession.startRunning()
        videoDevice.unlockForConfiguration()
        
    }
    
    
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        guard let depthData = synchronizedDataCollection[self.depthOutput] as? AVCaptureSynchronizedDepthData else {return}
        guard let imgData = synchronizedDataCollection[self.videoOutput] as? AVCaptureSynchronizedSampleBufferData else {return}
        
        let depthDataMap = depthData.depthData.depthDataMap
        let depthBuffer = CIImage(cvPixelBuffer: depthDataMap)
        
        // Convert depth data to an image to show.
        guard let depthImg = CIContext().createCGImage(
            depthBuffer,
            from: CGRect(
                x: 0, y: 0,
                width: CVPixelBufferGetWidth(depthDataMap),
                height: CVPixelBufferGetHeight(depthDataMap)
            )
        ) else {return}
        
        // Convert image buffer data to image to show.
        guard let imageBuffer = CMSampleBufferGetImageBuffer(imgData.sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let videoImage = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return }
        
        // Resize image to the same size as depth map.
        guard let imgContext = CGContext(
            data: nil,
            width: depthImg.width, height: depthImg.height,
            bitsPerComponent: depthImg.bitsPerComponent, bytesPerRow: depthImg.bytesPerRow,
            space: depthImg.colorSpace!, bitmapInfo: depthImg.bitmapInfo.rawValue
        ) else { return }
        imgContext.interpolationQuality = .high
        imgContext.draw(videoImage, in: CGRect(x: 0, y: 0, width: depthImg.width, height: depthImg.height))
        guard let scaled = imgContext.makeImage() else { return }
        
        // Show imgs.
        self.showDepthImg(depthImg)
        self.showVideoImg(scaled)
    }
    
    
    func showDepthImg(_ videoImage: CGImage) {
        DispatchQueue.main.async {
            self.depthView.image = UIImage(cgImage: videoImage)
        }
    }
    
    
    func showVideoImg(_ videoImage: CGImage) {
        DispatchQueue.main.async {
            self.previewView.image = UIImage(cgImage: videoImage)
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
            guard let realImg = self.previewView.image?.cgImage else { return }
            guard let depthImg = self.depthView.image?.cgImage else { return }
            
            // Settings for CGContext.
            let width = depthImg.width;
            let height = depthImg.height;
            
            let bytesPerPixel = 4;
            let bytesPerRow = bytesPerPixel * width;
            let bitsPerComponent = 8;
            
            // Get the raw rgb data for real and depth imgs.
            let realContext = CGContext(data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            realContext?.draw(realImg, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            let depthContext = CGContext(data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            depthContext?.draw(depthImg, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            // Set up pointer for
            guard let realData = realContext?.data?.bindMemory(to: UInt8.self, capacity: width * height) else { return }
            guard let depthData = depthContext?.data?.bindMemory(to: UInt8.self, capacity: width * height) else { return }
            
            // Traverse image data to set alpha for realData.
            var offset = 0
            for _ in 0..<height {
                for _ in 0..<width {
                    realData[offset + 3] = UInt8((Int(depthData[offset]) + Int(depthData[offset + 1]) + Int(depthData[offset + 2])) / 3)
                    offset += 4
                }
            }
            
            // Store img to file.
            let photoFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(PHOTO_FOLDER_NAME)
            try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true, attributes: nil)
            
            let imgName = curTimeStamp()
            
            let imgPath = photoFolder.appendingPathComponent(imgName + ".png")
            guard let dest = CGImageDestinationCreateWithURL(imgPath as CFURL, kUTTypePNG, 1, nil) else { return }
            guard let imageToStore = realContext?.makeImage() else { return }
            CGImageDestinationAddImage(dest, imageToStore, nil)
            CGImageDestinationFinalize(dest)
            
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

