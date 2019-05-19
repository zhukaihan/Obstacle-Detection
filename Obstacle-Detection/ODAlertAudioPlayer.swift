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
    
    var player1x: AVAudioPlayer?
    var player2x: AVAudioPlayer?
    var player3x: AVAudioPlayer?
    var player4x: AVAudioPlayer?
    
    let thread = DispatchQueue(label: "alertAudioPlayer")
    var alertY: Double = 0
    var curAlertY: Double = 0
    var prevAlertY: Double = 0
    var isPlaying: Bool = false
    
    init() {
        do {
//            try player1x = AVAudioPlayer(contentsOf: URL(fileURLWithPath: Bundle.main.path(forResource: "beep_1x.m4a", ofType:nil)!))
//            try player2x = AVAudioPlayer(contentsOf: URL(fileURLWithPath: Bundle.main.path(forResource: "beep_2x.m4a", ofType:nil)!))
            try player3x = AVAudioPlayer(contentsOf: URL(fileURLWithPath: Bundle.main.path(forResource: "beep_3x.m4a", ofType:nil)!))
//            try player4x = AVAudioPlayer(contentsOf: URL(fileURLWithPath: Bundle.main.path(forResource: "beep_4x.m4a", ofType:nil)!))
//            player1x?.numberOfLoops = -1
//            player2x?.numberOfLoops = -1
            player3x?.numberOfLoops = -1
//            player4x?.numberOfLoops = -1
            
            thread.async {
                while (true) {
                    let alertY = self.alertY
                    if (!self.isPlaying || alertY < self.ALERT_Y_THRESHOLD) {
//                        self.player1x?.stop()
//                        self.player2x?.stop()
                        self.player3x?.stop()
//                        self.player4x?.stop()
                        usleep(useconds_t(0.16 * 2 * 1000000))
                        continue;
                    }
//                    if (alertY < 0.25) {
//                        self.player2x?.stop()
//                        self.player3x?.stop()
//                        self.player4x?.stop()
//                        self.player1x?.play()
//                        usleep(useconds_t(0.27 * 00000))
//                        self.player1x?.stop()
//                    } else if (alertY < 0.5) {
//                        self.player1x?.stop()
//                        self.player3x?.stop()
//                        self.player4x?.stop()
//                        self.player2x?.play()
//                        usleep(useconds_t(0.19 * 1000000))
////                        self.player2x?.stop()
//                    } else if (alertY < 75) {
//                        self.player1x?.stop()
//                        self.player2x?.stop()
//                        self.player4x?.stop()
                        self.player3x?.play()
                        usleep(useconds_t(0.16 * 2 * 1000000))
////                        self.player3x?.stop()
//                    } else {
//                        self.player1x?.stop()
//                        self.player2x?.stop()
//                        self.player3x?.stop()
//                        self.player4x?.play()
//                        usleep(useconds_t(0.13 * 2 * 1000000))
////                        self.player4x?.stop()
//                    }
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
    
    func setAlertY(alertY: Double) {
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
        self.alertY = alertY
    }
}
