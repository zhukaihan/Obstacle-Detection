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
    func obstacleReport(byDetector detector: ObstacleDetector, img: ODImage)
    
}

class ObstacleDetector {
    var delegate: ObstacleDetectorDelegate?
    static let NEXT_PIXEL_INTERVAL: Int = 10
    static let OBSTACLE_DIFF_THRESHOLD: Int = 100
    static let DEPTH_OFFSET: Int = 3
    static let PIXEL_BYTES: Int = 4
    
    let LABEL_COLOR = [UIColor.green.cgColor, UIColor.darkGray.cgColor, UIColor.blue.cgColor, UIColor.red.cgColor]
    let LABEL_NAME = ["Obstacle", "Pothole", "Edge", "Uplift"]
    
    let eval = ODModelEvaluator()
    
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
        
        guard let img = ODImage(withCMSampleBuffer: buf) else { return }
        
        for label in (sortedLabels as NSArray as! [NSDictionary]) {
            //print("\(label["obj_class"]) \(label["confidence"]) \(label["xmin"]) \(label["xmax"]) \(label["ymin"]) \(label["ymax"]) \n")
            
            let labelClass = Int(label["obj_class"] as! NSInteger)
            let confidence = Float(label["confidence"] as! NSNumber)
            let x = Double(label["xmin"] as! NSNumber) * Double(ODImage.WIDTH)
            let y = Double(label["ymin"] as! NSNumber) * Double(ODImage.HEIGHT)
            let width = Double(label["xmax"] as! NSNumber) * Double(ODImage.WIDTH) - x
            let height = Double(label["ymax"] as! NSNumber) * Double(ODImage.HEIGHT) - y
            
            let rect = CGRect(x: x, y: y, width: width, height: height)
            
            img.context.setStrokeColor(LABEL_COLOR[labelClass])
            img.context.stroke(rect, width: 4)
            
            img.context.textPosition = rect.origin
            
            let nsAttr: [NSAttributedString.Key : Any] = [
                kCTBackgroundColorAttributeName as NSAttributedString.Key: UIColor.white.cgColor,
                kCTForegroundColorAttributeName as NSAttributedString.Key: UIColor.black.cgColor,
            ]
            let attrStr = NSAttributedString(string: "\(LABEL_NAME[labelClass]): \(confidence)", attributes: nsAttr)
            
            let textLine = CTLineCreateWithAttributedString(attrStr)
            CTLineDraw(textLine, img.context)
        }
        
        if (delegate != nil) {
            self.delegate?.obstacleReport(byDetector: self, img: img)
        }
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