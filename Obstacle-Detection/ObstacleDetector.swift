//
//  ObstacleDetector.swift
//  Obstacle-Detection
//
//  Created by Peter Zhu on 3/23/19.
//  Copyright © 2019 Kaihan Zhu. All rights reserved.
//

import Foundation
import UIKit

protocol ObstacleDetectorDelegate {
    func obstacleReport(byDetector detector: ObstacleDetector, doesExistObstacle isObstacle: Bool)
    func obstacleReport(byDetector detector: ObstacleDetector, message msg: String)
    
}

class ObstacleDetector {
    var delegate: ObstacleDetectorDelegate?
    static let NEXT_PIXEL_INTERVAL: Int = 10
    static let OBSTACLE_DIFF_THRESHOLD: Int = 100
    static let DEPTH_OFFSET: Int = 3
    static let PIXEL_BYTES: Int = 4
    
    let eval = ModelEvaluator()
    
    init() {
        eval.loadModel()
        
    }
    
    deinit {
        eval.freeModel()
        
    }
    
    func setDelegate(_ delegate: ObstacleDetectorDelegate) {
        self.delegate = delegate
    }
    
    func runModelOn(withBuffer buf: CMSampleBuffer) {
        guard let sortedLabels = eval.evaluate(on: buf) else { return }
        
        
        var labelCount = 0;
        var displayText = "";
        for entry in sortedLabels {
            let dict = entry as! NSDictionary
            let label = dict["label"] as! NSString?
            let valueObject = dict["value"] as! NSNumber?
            let value = valueObject?.floatValue
            let valuePercentage = Int(roundf(value! * 100.0))
            
            displayText += String(label!) + " " + String(valuePercentage) + "; "
            
            labelCount += 1
            if (labelCount > 4) {
                break;
            }
        }
        
        self.delegate?.obstacleReport(byDetector: self, message: displayText)
    }
    
    func detectObstacle(withImg img: ODImage) {
        var isObstacle = false
        let width = ODImage.WIDTH;
        let height = ODImage.HEIGHT;
        let nextPixel = ObstacleDetector.NEXT_PIXEL_INTERVAL
        let pixelBytes = ObstacleDetector.PIXEL_BYTES
        let depthOffset = ObstacleDetector.DEPTH_OFFSET
        
        // Set up pointer for
        guard let data = img.context.data?.bindMemory(to: UInt8.self, capacity: width * height) else { return }
        
        // Traverse image data to set alpha for realData.
        var offset = 0
        for _ in 0..<ODImage.HEIGHT {
            for _ in 0..<ODImage.WIDTH - nextPixel {
                let depth = Int(data[offset + depthOffset])
                let nextDepth = Int(data[offset + nextPixel * pixelBytes + depthOffset])
                
                if (depth == 0 || nextDepth == 0) {
                    continue
                }
                if (nextDepth - depth > ObstacleDetector.OBSTACLE_DIFF_THRESHOLD) {
                    isObstacle = true
                    break
                }
                
                
                offset += 4
            }
            if isObstacle {
                break
            }
            offset += ObstacleDetector.NEXT_PIXEL_INTERVAL * 4
        }
        
        self.delegate?.obstacleReport(byDetector: self, doesExistObstacle: isObstacle)
    }
}
