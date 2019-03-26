//
//  ImageProcessor.swift
//  Obstacle-Detection
//
//  Created by Peter Zhu on 3/24/19.
//  Copyright © 2019 Kaihan Zhu. All rights reserved.
//

import Foundation
import UIKit

class ImageProcessor {
    
    static func combineRGBAndDepth(rgb realImg: CGImage, depth depthImg: CGImage) -> CGImage? {
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
        guard let realData = realContext?.data?.bindMemory(to: UInt8.self, capacity: width * height) else { return nil }
        guard let depthData = depthContext?.data?.bindMemory(to: UInt8.self, capacity: width * height) else { return nil }
        
        // Traverse image data to set alpha for realData.
        var offset = 0
        for _ in 0..<height {
            for _ in 0..<width {
                realData[offset + 3] = UInt8((Int(depthData[offset]) + Int(depthData[offset + 1]) + Int(depthData[offset + 2])) / 3)
                offset += 4
            }
        }
        
        return realContext?.makeImage()
    }
}
