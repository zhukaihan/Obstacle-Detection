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
    func obstacleReport(byDetector detector: ObstacleDetector, img: CGImage, realImg: CGImage)
    
}

class ObstacleDetector {
    var delegate: ObstacleDetectorDelegate?
    static let NEXT_PIXEL_INTERVAL: Int = 10
    static let OBSTACLE_DIFF_THRESHOLD: Int = 100
    static let DEPTH_OFFSET: Int = 3
    static let PIXEL_BYTES: Int = 4
    
    let LABEL_COLOR = [UIColor.green.cgColor, UIColor.darkGray.cgColor, UIColor.blue.cgColor, UIColor.red.cgColor]
    let LABEL_NAME = ["Obstacle", "Pothole", "Edge", "Uplift"]
    let EVAL_THRESHOLD = 0.5
    
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
        guard let imageBuffer = CMSampleBufferGetImageBuffer(buf) else { return }
        guard let img = ODImage(withCVImageBuffer: imageBuffer) else { return }
        guard let realImg = img.toCGImg() else { return }
        
        guard let sortedLabels = eval.evaluate(on: imageBuffer) else { return }
        
        for label in (sortedLabels as NSArray as! [NSDictionary]) {
            //print("\(label["obj_class"]) \(label["confidence"]) \(label["xmin"]) \(label["xmax"]) \(label["ymin"]) \(label["ymax"]) \n")
            
            let labelClass = Int(label["obj_class"] as! NSInteger)
            let confidence = round((label["confidence"] as! NSNumber).doubleValue * 100) / 100
            
            if (confidence < EVAL_THRESHOLD) {
                continue
            }
            
            let xmin_to_top_left = (label["xmin"] as! NSNumber).doubleValue * Double(img.width)
            let ymin_to_top_left = (label["ymin"] as! NSNumber).doubleValue * Double(img.height)
            let xmax_to_top_left = (label["xmax"] as! NSNumber).doubleValue * Double(img.width)
            let ymax_to_top_left = (label["ymax"] as! NSNumber).doubleValue * Double(img.height)
            
            // Core Graphics has origin at lower left corner.
            let x = xmin_to_top_left
            let y = Double(img.height) - ymax_to_top_left
            let width = xmax_to_top_left - xmin_to_top_left
            let height = ymax_to_top_left - ymin_to_top_left
            
            let rect = CGRect(x: x, y: y, width: width, height: height)
            let rectThickness = Int(Double(img.width / 80) * (confidence)) // Thicker box has more confidence.
            img.drawBox(rect: rect, withThickness: rectThickness, withColor: LABEL_COLOR[labelClass])
            
            let text = "\(LABEL_NAME[labelClass]): \(confidence)"
            img.drawText(text: text, atOrigin: rect.origin, withFontSize: CGFloat(rectThickness * 4))
        }
        
        if (delegate != nil) {
            guard let modelResultImg = img.toCGImg() else { return }
            self.delegate?.obstacleReport(byDetector: self, img: modelResultImg, realImg: realImg)
        }
    }
    
    func detectObstacle(withImg img: ODImage) {
        var isObstacle = false
        let width = img.width;
        let height = img.height;
        let nextPixel = ObstacleDetector.NEXT_PIXEL_INTERVAL
        let pixelBytes = ObstacleDetector.PIXEL_BYTES
        let depthOffset = ObstacleDetector.DEPTH_OFFSET
        
        // Set up pointer for
        guard let data = img.context.data?.bindMemory(to: UInt8.self, capacity: width * height) else { return }
        
        // Traverse image data to set alpha for realData.
        var offset = 0
        for _ in 0..<img.height {
            for _ in 0..<img.width - nextPixel {
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
