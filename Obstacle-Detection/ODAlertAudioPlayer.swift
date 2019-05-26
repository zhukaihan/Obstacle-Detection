//
//  ODAlertAudioPlayer.swift
//  Obstacle-Detection
//
//  Created by Peter Zhu on 5/18/19.
//  Copyright © 2019 Kaihan Zhu. All rights reserved.
//

import Foundation
import AVFoundation

class ODAlertAudioPlayer {
    let ALERT_Y_THRESHOLD = 0.3
    
    let CYCLE_TIME: Double = 0.5 * 1000000
    let EDGE_ALERT_EVERY: Double = 60 * 1000000
    
    var playerObstacle: AVAudioPlayer?
    var playerEdge: AVAudioPlayer?
    
    let thread = DispatchQueue(label: "alertAudioPlayer")
    
    var alertYObstacle: Double = 0
    var alertYEdge: Double = 0
    
    var curAlertY: Double = 0
    var prevAlertY: Double = 0
    
    var isPlaying: Bool = false
    
    init() {
        do {
            try playerObstacle = AVAudioPlayer(contentsOf: URL(fileURLWithPath: Bundle.main.path(forResource: "beep_3x.m4a", ofType:nil)!))
            try playerEdge = AVAudioPlayer(contentsOf: URL(fileURLWithPath: Bundle.main.path(forResource: "beep_3x.m4a", ofType:nil)!))
            
            thread.async {
                var edgeAlertCyclesTime: Double = 0;
                while (true) {
                    let alertYObstacle = self.alertYObstacle
                    let alertYEdge = self.alertYEdge
                    if (!self.isPlaying) {
                        edgeAlertCyclesTime += self.CYCLE_TIME
                        usleep(useconds_t(self.CYCLE_TIME))
                        continue;
                    }
                    if (alertYObstacle < self.ALERT_Y_THRESHOLD) {
                        self.playerObstacle?.play()
                    }
                    if (edgeAlertCyclesTime > self.EDGE_ALERT_EVERY) {
                        edgeAlertCyclesTime = 0
                    }
                    if (edgeAlertCyclesTime == 0 && alertYEdge < self.ALERT_Y_THRESHOLD) {
                        self.playerEdge?.play()
                    }
                    edgeAlertCyclesTime += self.CYCLE_TIME
                    usleep(useconds_t(self.CYCLE_TIME))
                }
            }
        } catch {
            print("failed init alert player" + error.localizedDescription)
        }
    }
    
    func start() {
        isPlaying = true
    }
    
    func stop() {
        isPlaying = false
    }
    
    func setAlertYObstacle(alertY: Double) {
        // Median filter with size of 3.
//        if (self.prevFreq > self.curFreq && self.prevFreq < freq) ||
//            (self.prevFreq < self.curFreq && self.prevFreq > freq){
//            self.freq = self.prevFreq
//        } else if
//            (self.curFreq > self.prevFreq && self.curFreq < freq) ||
//            (self.curFreq < self.prevFreq && self.curFreq > freq)
//        {
//            self.freq = self.curFreq
//        } else if
//            (freq > self.prevFreq && freq < self.curFreq) ||
//            (freq < self.prevFreq && freq > self.curFreq)
//        {
//            self.freq = self.curFreq
//        }
//        self.prevFreq = self.curFreq
//        self.curFreq = freq
        
        // 33% decay function.
        self.alertYObstacle = (self.alertYObstacle + self.alertYObstacle + alertY) / 3
    }
    
    func setAlertYEdge(alertY: Double) {
        self.alertYEdge = (self.alertYEdge + self.alertYEdge + alertY) / 3
    }
}
