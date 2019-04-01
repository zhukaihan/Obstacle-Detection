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
}

class ObstacleDetector {
    var delegate: ObstacleDetectorDelegate?
    static let NEXT_PIXEL_INTERVAL: Int = 10
    static let OBSTACLE_DIFF_THRESHOLD: Int = 100
    static let DEPTH_OFFSET: Int = 3
    static let PIXEL_BYTES: Int = 4
    
    init() {
        
    }
    
    deinit {
        
    }
    
    func setDelegate(_ delegate: ObstacleDetectorDelegate) {
        self.delegate = delegate
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
