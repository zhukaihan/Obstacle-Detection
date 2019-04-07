//
//  ODImage.swift
//  Obstacle-Detection
//
//  Created by Peter Zhu on 3/24/19.
//  Copyright © 2019 Kaihan Zhu. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation
import MobileCoreServices

/**
 The size of an ODImage will always be 320px*240px.
 */
class ODImage {
    static let WIDTH: Int = 320
    static let HEIGHT: Int = 240
    
    var context: CGContext
    var width: Int {
        return context.width
    }
    var height: Int {
        return context.height
    }
    
    init?() {
        let width = ODImage.WIDTH;
        let height = ODImage.HEIGHT;
        
        let bytesPerPixel = 4;
        let bytesPerRow = bytesPerPixel * width;
        let bitsPerComponent = 8;
        
        // Get the raw rgb data for real and depth imgs.
        guard let newContext = CGContext(data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
        self.context = newContext
        self.context.interpolationQuality = .high
    }
    
    convenience init?(withCGImage img: CGImage) {
        self.init()
        self.context.draw(img, in: CGRect(x: 0, y: 0, width: ODImage.WIDTH, height: ODImage.WIDTH))
    }
    
    convenience init?(withCGContext ctxt: CGContext) {
        guard let cgimg = ctxt.makeImage() else { return nil }
        self.init(withCGImage: cgimg)
    }
    
    convenience init?(withCVPixelBuffer buf: CVPixelBuffer) {
        // Convert CVPixelBuffer to CGImage.
        let ciimg = CIImage(cvPixelBuffer: buf)
        guard let cgimg = CIContext().createCGImage(
            ciimg,
            from: CGRect(
                x: 0, y: 0,
                width: CVPixelBufferGetWidth(buf),
                height: CVPixelBufferGetHeight(buf)
            )
        ) else { return nil }
        
        self.init(withCGImage: cgimg)
    }
    
    convenience init?(withCMSampleBuffer buf: CMSampleBuffer) {
        // Convert CMSampleBuffer to CGImage.
        guard let imageBuffer = CMSampleBufferGetImageBuffer(buf) else { return nil }
        let ciimg = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgimg = CIContext().createCGImage(ciimg, from: ciimg.extent) else { return nil }
        
        self.init(withCGImage: cgimg)
    }
    
    convenience init?(withODImage img: ODImage) {
        guard let cgimg = img.toCGImg() else { return nil }
        self.init(withCGImage: cgimg)
    }
    
    func toCGImg() -> CGImage? {
        return self.context.makeImage()
    }
    
    func addToAlpha(withImg img: ODImage?) -> ODImage? {
        if (img == nil) {
            return nil
        }
        // Settings for CGContext.
        let width = ODImage.WIDTH
        let height = ODImage.HEIGHT
        
        // Set up pointer for
        guard let realData = self.context.data?.bindMemory(to: UInt8.self, capacity: width * height) else { return nil }
        guard let depthData = img!.context.data?.bindMemory(to: UInt8.self, capacity: width * height) else { return nil }
        
        // Traverse image data to set alpha for realData.
        var offset = 0
        for _ in 0..<ODImage.HEIGHT {
            for _ in 0..<ODImage.WIDTH {
                realData[offset + 3] = UInt8((Int(depthData[offset]) + Int(depthData[offset + 1]) + Int(depthData[offset + 2])) / 3)
                if (realData[offset + 3] == 0) {
                    // To avoid having alpha value of 0. If alpha value is 0, rgb value will be ignored by Core Graphics.
                    realData[offset + 3] = 1
                }
                offset += 4
            }
        }
        
        return self
    }
    
    func filter() {
        // Settings for CGContext.
        let width = ODImage.WIDTH
        let height = ODImage.HEIGHT
        
        // Set up pointer for
        guard let data = self.context.data?.bindMemory(to: UInt8.self, capacity: width * height) else { return }
        
        
        
        let HOLE_THRESHOLD: UInt8 = 50
        
        data[0] = HOLE_THRESHOLD
        data[1] = HOLE_THRESHOLD
        data[2] = HOLE_THRESHOLD
        
        // Traverse image data to set alpha for realData.
        var offset = 0
        for _ in 0..<ODImage.HEIGHT {
            for widthI in 0..<ODImage.WIDTH {
                if (data[offset] < HOLE_THRESHOLD || data[offset + 1] < HOLE_THRESHOLD || data[offset + 2] < HOLE_THRESHOLD) {
                    // Sees a hole. Fill this hole.
                    // Find right side of the hole.
                    var leftOffset = offset - 4
                    let leftWidthI = widthI - 1
                    var rightOffset = offset
                    var rightWidthI = widthI
                    while (rightWidthI < ODImage.WIDTH - 1) && (data[rightOffset] < HOLE_THRESHOLD) {
                        rightOffset += 4
                        rightWidthI += 1
                    }
                    // If right side is the edge of image, check its value.
                    if data[rightOffset] < HOLE_THRESHOLD {
                        data[rightOffset] = HOLE_THRESHOLD
                        data[rightOffset + 1] = HOLE_THRESHOLD
                        data[rightOffset + 2] = HOLE_THRESHOLD
                    }
                    
                    var leftVal: Double = Double(data[leftOffset])
                    let rightVal: Double = Double(data[rightOffset])
                    
                    // Fill the hole with a linear function.
                    let incStep: Double = (rightVal - leftVal) / Double(rightWidthI - leftWidthI)
                    
                    while (leftOffset < rightOffset) {
                        leftVal += incStep
                        leftOffset += 4
                        
                        // Consider the upper pixel for the new value.
                        var upperVal = leftVal
                        if (leftOffset - ODImage.WIDTH * 4 >= 0) {
                            upperVal = Double(data[leftOffset - ODImage.WIDTH * 4])
                        }
                        let newVal = UInt8((leftVal + upperVal) / 2)
                        data[leftOffset] = newVal
                        data[leftOffset + 1] = newVal
                        data[leftOffset + 2] = newVal
                    }
                }
                
                offset += 4
            }
        }
    }
    
    func writeTo(url: URL, withName name: String) -> Bool {
        guard let imgToStore = self.toCGImg() else { return false }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, imgToStore, nil)
        CGImageDestinationFinalize(dest)
        return true
    }
}