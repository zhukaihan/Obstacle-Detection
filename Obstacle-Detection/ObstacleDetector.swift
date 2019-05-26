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
    func obstacleReport(byDetector detector: ObstacleDetector, img: ODImage, alertYObstacle: Double, alertYEdge: Double)
    
}

class ObstacleDetector {
    var delegate: ObstacleDetectorDelegate?
    static let NEXT_PIXEL_INTERVAL: Int = 10
    static let OBSTACLE_DIFF_THRESHOLD: Int = 100
    static let DEPTH_OFFSET: Int = 3
    static let PIXEL_BYTES: Int = 4
    
    let EVAL_CONFIDENCE_THRESHOLD = 0.2
    let EVAL_IOU_THRESHOLD = 0.8
    let Y_ALERT_THRESHOLD = 0.2
    
    let LABEL_COLOR = [UIColor.green.cgColor, UIColor.darkGray.cgColor, UIColor.blue.cgColor, UIColor.red.cgColor]
    let LABEL_NAME = ["Obstacle", "Pothole", "Edge", "Uplift"]
    
    let eval = ODModelEvaluator()
    var isDetecting: Bool = true
    
    init() {
        eval.loadModel()
    }
    
    deinit {
        eval.freeModel()
    }
    
    func setDelegate(_ delegate: ObstacleDetectorDelegate) {
        self.delegate = delegate
    }
    
    func start() {
        self.isDetecting = true
    }
    
    func stop() {
        self.isDetecting = false
    }
    
    func runModelOn(withBuffer buf: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(buf) else { return }
        guard let img = ODImage(withCVImageBuffer: imageBuffer) else { return }
        
        // Run model on the image.
        guard let sortedLabels = eval.evaluate(on: imageBuffer) else { return }
        
        // minY now has origin on the lower left.
        // minY is in form of percentage of the image height.
        // Y coordinate is treated as the closeness of obstacle, due to the position of the phone.
        // minY is the closest obstacle.
        var minYObstacle: Double = 1
        var minYEdge: Double = 1
        
        if self.isDetecting {
            // Loop through existing boxes.
            for box in (sortedLabels as NSArray as! [NSDictionary]) {
                let label = Int(box["obj_class"] as! NSInteger)
                let confidence = round((box["confidence"] as! NSNumber).doubleValue * 100) / 100
                
                // Reject the boxes that has low confidence score.
                if (confidence < EVAL_CONFIDENCE_THRESHOLD) {
                    continue
                }
                
                // Coordinate of the output box.
                let xmin_to_top_left = (box["xmin"] as! NSNumber).doubleValue * Double(img.width)
                let ymin_to_top_left = (box["ymin"] as! NSNumber).doubleValue * Double(img.height)
                let xmax_to_top_left = (box["xmax"] as! NSNumber).doubleValue * Double(img.width)
                let ymax_to_top_left = (box["ymax"] as! NSNumber).doubleValue * Double(img.height)
                
                // Core Graphics has origin at lower left corner.
                // Convert coordinate.
                let x = xmin_to_top_left
                let y = Double(img.height) - ymax_to_top_left
                let width = xmax_to_top_left - xmin_to_top_left
                let height = ymax_to_top_left - ymin_to_top_left
                
                // IOU of the box and image.
                // To simplify the logic, it's box's area / image's area.
                // Intersect = box's area; Union = image's area.
                let IOU = width * height / Double(img.width) / Double(img.height)
                
                // Reject the boxes that has a high IOU with the image as they are frequent false positives.
                if (IOU > EVAL_IOU_THRESHOLD) {
                    continue
                }
                
                // Draw box in the image.
                let rect = CGRect(x: x, y: y, width: width, height: height)
                let rectThickness = Int(Double(img.width / 80) * (confidence)) // Thicker box has more confidence.
                img.drawBox(rect: rect, withThickness: rectThickness, withColor: LABEL_COLOR[label])
                
                let text = "\(LABEL_NAME[label]): \(confidence)"
                img.drawText(text: text, atOrigin: rect.origin, withFontSize: CGFloat(rectThickness * 4))
                
                
                
                if (
                    // Check if the object is eligible for alert, the object is in the path of the user (intersects with the horizontal center of the image).
                    x < Double(img.width) / 2) && (x + width > Double(img.width) / 2) &&
                    // If yes, compare with the existing closest obstacle.
                    ((y / Double(img.height)) < minYObstacle) &&
                    // If all conditions passes, check category.
                    label == 0
                {
                    minYObstacle = y / Double(img.height)
                }
                
                if (
                    // Check if the object is eligible for alert, the object is in the path of the user (intersects with the horizontal center of the image).
                    x < Double(img.width) / 2) && (x + width > Double(img.width) / 2) &&
                    // If yes, compare with the existing closest edge.
                    ((y / Double(img.height)) < minYEdge) &&
                    // If all conditions passes, check category.
                    label == 2
                {
                    minYEdge = y / Double(img.height)
                }
                
            }
        }
        
        let alertYObstacle = 1 - minYObstacle // Convert minY from lower left coor to upper left coor.
        let alertYEdge = 1 - minYEdge // Convert minY from lower left coor to upper left coor.
        if (delegate != nil) {
            // Check if the closest obstacle is close enough for alert.
            self.delegate?.obstacleReport(byDetector: self, img: img, alertYObstacle: alertYObstacle, alertYEdge: alertYEdge)
        }
    }
    
    // A way to detect obstacle with depth map (deprecated).
    // If the difference between the intensities of two neighboring pixels larger than a threshold, we say an obstacle detected.
    @available(*, deprecated)
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
