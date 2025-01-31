//
//  player.swift
//  custer
//
//  Created by Serhiy Mytrovtsiy on 07/06/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import os.log
import AVFoundation
import MediaPlayer

internal enum player_state: Int {
    case undefined
    
    case error
    case ready
    
    case playing
    case paused
    case stopped
    
    public var description: String {
        switch self {
        case .undefined: return "undefined"
        case .error: return "error"
        case .ready: return "ready"
        case .playing: return "playing"
        case .paused: return "paused"
        case .stopped: return "stopped"
        }
    }
}

internal enum player_error: String {
    case wrongURL = "wrong url provided"
    case emptyURL = "no url provided"
    case interrupted = "stream was interrupted"
}

protocol playerDelegate {
    func onError(error: String)
    func stateChange(state: player_state)
}

internal class Player: NSObject {
    public static let shared = Player()
    
    public var delegate: playerDelegate? = nil
    public var volume: Float {
        get {
            Store.shared.float(key: "volume", defaultValue: 0.8)
        }
        set {
            self.player.volume = newValue
            Store.shared.set(key: "volume", value: newValue)
        }
    }
    public var buffer: (_ total: Double, _ current: Double) -> Void = {_,_ in }
    
    private var player = AVPlayer()
    private var observer: NSObjectProtocol?
    private var bufferObserver: Any!
    
    private var uri: String? = nil
    private var pauseTimestamp: Date? = nil
    
    private let nowPlayingInfoCenter: MPNowPlayingInfoCenter = .default()
    private let remoteCommandCenter: MPRemoteCommandCenter = .shared()
    
    private var error: String? = nil {
        didSet {
            guard self.error != nil else {
                return
            }
            
            if let delegate = self.delegate {
                delegate.onError(error: self.error!)
            }
        }
    }
    private var state: player_state = .undefined {
        didSet {
            if let delegate = self.delegate {
                delegate.stateChange(state: self.state)
            }
        }
    }
    
    override init() {
        super.init()
        
        self.reset()
        
        self.observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: nil,
            using: streamInterrupted
        )
        
        self.remoteCommandCenter.playCommand.addTarget(self, action: #selector(self.playCommandEvent))
        self.remoteCommandCenter.pauseCommand.addTarget(self, action: #selector(self.pauseCommandEvent))
        self.remoteCommandCenter.stopCommand.addTarget(self, action: #selector(self.stopCommandEvent))
        self.remoteCommandCenter.togglePlayPauseCommand.addTarget(self, action: #selector(self.playPauseCommandEvent))
        
        os_log(.debug, log: log, "Initialized player")
    }
    
    deinit {
        guard self.observer != nil else {
            return
        }
        
        if self.bufferObserver != nil {
            self.player.removeTimeObserver(self.bufferObserver!)
            self.bufferObserver = nil
        }
        
        NotificationCenter.default.removeObserver(self.observer!)
    }
    
    private func streamInterrupted(notification: Notification) {
        os_log(.error, log: log, "%s", player_error.interrupted.rawValue)
        self.error = player_error.interrupted.rawValue
        self.state = .error
    }
    
    public func reset(play: Bool = false) {
        guard self.uri != nil else {
            self.error = player_error.emptyURL.rawValue
            self.state = .error
            return
        }
        
        self.error = nil
        
        guard let url = URL(string: self.uri!) else {
            self.error = player_error.wrongURL.rawValue
            self.state = .error
            return
        }
        
        let statusKey = "tracks"
        let asset: AVURLAsset = AVURLAsset(url: url, options: nil)
        asset.loadValuesAsynchronously(forKeys: [statusKey], completionHandler: {
            var error: NSError? = nil
            
            DispatchQueue.main.async {
                if asset.statusOfValue(forKey: statusKey, error: &error) != .loaded {
                    self.error = error!.localizedDescription
                    self.state = .error
                    os_log(.error, log: log, "load asset: %s", error!.localizedDescription)
                    return
                }
                
                self.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
                self.state = .ready
                self.player.volume = self.volume
                
                if play {
                    self.play()
                }
            }
        })
    }
    
    public func play() {
        if self.state == .playing {
            return
        }
        
        if self.pauseTimestamp != nil && abs(self.pauseTimestamp!.timeIntervalSinceNow) > 60*3 {
            self.pauseTimestamp = nil
            self.reset(play: true)
        } else {
            self.player.play()
        }
        self.player.volume = self.volume
        
        self.state = .playing
        os_log(.debug, log: log, "player is playing")
        
        self.bufferObserver = self.player.addPeriodicTimeObserver(forInterval: CMTimeMake(value: 1, timescale: 10), queue: DispatchQueue.main) { [weak self] time in
            self?.buffer(self?.player.currentItem?.totalBuffer() ?? -1, self?.player.currentItem?.currentBuffer() ?? -1)
        }
        
        self.setMetadata()
    }
    
    public func pause() {
        if self.state != .playing {
            return
        }
        
        self.player.pause()
        self.state = .paused
        self.pauseTimestamp = Date()
        os_log(.debug, log: log, "player is paused")
    }
    
    public func setURL(_ uri: String) {
        if uri == "" {
            os_log(.debug, log: log, "try to set empty url")
            return
        }
        
        self.uri = uri
        self.reset()
        
        os_log(.debug, log: log, "new url set: %s", uri)
    }
    
    public func isPlaying() -> Bool {
        return self.state == .playing && self.player.rate == 1
    }
    
    public func isError() -> Bool {
        return self.state == .error
    }
    
    public func clearBuffer() {
        self.reset(play: true)
    }
    
    private func setMetadata() {
        var info = self.nowPlayingInfoCenter.nowPlayingInfo ?? [String: Any]()
        
        info[MPMediaItemPropertyTitle] = "Custer - radio"
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime().seconds
        info[MPMediaItemPropertyPlaybackDuration] = 9999999
        
        DispatchQueue.main.async { [unowned self] in
          self.nowPlayingInfoCenter.nowPlayingInfo = info
        }
        
        self.nowPlayingInfoCenter.nowPlayingInfo = info
        self.nowPlayingInfoCenter.playbackState = .playing
    }
    
    // MARK:- command handlers
    
    @objc func playCommandEvent(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        self.play()
        return .success
    }
    
    @objc func pauseCommandEvent(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        self.pause()
        return .success
    }
    
    @objc func stopCommandEvent(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        self.pause()
        return .success
    }
    
    @objc func playPauseCommandEvent(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        if self.isPlaying() {
            self.pause()
        } else {
            self.play()
        }
        return .success
    }
}
