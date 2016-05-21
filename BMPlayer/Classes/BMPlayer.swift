//
//  BMPlayer.swift
//  Pods
//
//  Created by BrikerMan on 16/4/28.
//
//

import UIKit
import SnapKit
import MediaPlayer

enum BMPlayerState {
    case NotSetURL      // 未设置URL
    case ReadyToPlay    // 可以播放
    case Buffering      // 缓冲中
    case BufferFinished // 缓冲完毕
    case PlayedToTheEnd // 播放结束
    case Error          // 出现错误
}

/// 枚举值，包含水平移动方向和垂直移动方向
enum BMPanDirection: Int {
    case Horizontal = 0
    case Vertical   = 1
}

public class BMPlayer: UIView {
    
    public var backBlock:(() -> Void)?
    
    var playerItems: [BMPlayerItemProtocol] = []
    
    var playerLayer: BMPlayerLayerView?
    
    var controlView: BMPlayerControlView!
    
    var customControlView: BMPlayerControlView?
    /// 是否显示controlView
    private var isMaskShowing = false
    
    private var isFullScreen  = false
    /// 用来保存快进的总时长
    private var sumTime     : NSTimeInterval!
    /// 滑动方向
    private var panDirection = BMPanDirection.Horizontal
    /// 是否是音量
    private var isVolume = false
    /// 音量滑竿
    private var volumeViewSlider: UISlider!
    
    private let BMPlayerAnimationTimeInterval:Double                = 4.0
    private let BMPlayerControlBarAutoFadeOutTimeInterval:Double    = 0.5
    
    private var totalTime:NSTimeInterval = 1
    
    private var isSliderSliding = false
    
    private var isPlayerPrepared = false
    
    // MARK: - Public functions
    /**
     直接使用URL播放
     
     - parameter url:   视频URL
     - parameter title: 视频标题
     */
    public func playWithURL(url: NSURL, title: String = "") {
        playerLayer?.videoURL       = url
        controlView.titleLabel.text = title
    }
    
    /**
     播放可切换清晰度的视频
     
     - parameter items: model列表
     - parameter title: 视频标题
     */
    public func playWithQualityItems(items:[BMPlayerItemProtocol], title: String, playIndex: Int = 0) {
        playerLayer?.videoURL       = items[playIndex].playURL
        controlView.titleLabel.text = title
    }
    
    
    
    public func play() {
        playerLayer?.play()
    }
    
    public func pause() {
        playerLayer?.pause()
    }
    
    public func autoFadeOutControlBar() {
        NSObject.cancelPreviousPerformRequestsWithTarget(self, selector: #selector(hideControlViewAnimated), object: nil)
        self.performSelector(#selector(hideControlViewAnimated), withObject: nil, afterDelay: BMPlayerAnimationTimeInterval)
    }
    
    public func cancelAutoFadeOutControlBar() {
        NSObject.cancelPreviousPerformRequestsWithTarget(self)
    }
    
    // MARK: - Action Response
    private func playStateDidChanged() {
        if let player = playerLayer {
            if player.isPlaying {
                autoFadeOutControlBar()
                controlView.playButton.selected = true
                isSliderSliding = false
            } else {
                controlView.playButton.selected = false
            }
        }
        
    }
    
    
    @objc private func hideControlViewAnimated() {
        UIView.animateWithDuration(BMPlayerControlBarAutoFadeOutTimeInterval, animations: {
            self.controlView.hidePlayerIcons()
            UIApplication.sharedApplication().setStatusBarHidden(true, withAnimation: UIStatusBarAnimation.Fade)
            
        }) { (_) in
            self.isMaskShowing = false
        }
    }
    
    @objc private func showControlViewAnimated() {
        UIView.animateWithDuration(BMPlayerControlBarAutoFadeOutTimeInterval, animations: {
            self.controlView.showPlayerIcons()
            UIApplication.sharedApplication().setStatusBarHidden(false, withAnimation: UIStatusBarAnimation.Fade)
        }) { (_) in
            self.isMaskShowing = true
        }
    }
    
    @objc private func tapGestureTapped(sender: UIGestureRecognizer) {
        if isMaskShowing {
            hideControlViewAnimated()
            autoFadeOutControlBar()
        } else {
            showControlViewAnimated()
        }
    }
    
    @objc private func panDirection(pan: UIPanGestureRecognizer) {
        // 根据在view上Pan的位置，确定是调音量还是亮度
        let locationPoint = pan.locationInView(self)
        
        // 我们要响应水平移动和垂直移动
        // 根据上次和本次移动的位置，算出一个速率的point
        let velocityPoint = pan.velocityInView(self)
        
        // 判断是垂直移动还是水平移动
        switch pan.state {
        case UIGestureRecognizerState.Began:
            // 使用绝对值来判断移动的方向
            
            let x = fabs(velocityPoint.x)
            let y = fabs(velocityPoint.y)
            
            if x > y {
                self.panDirection = BMPanDirection.Horizontal
                
                // 给sumTime初值
                if let player = playerLayer?.player {
                    let time = player.currentTime()
                    self.sumTime = NSTimeInterval(time.value) / NSTimeInterval(time.timescale)
                }
                
                playerLayer?.player?.pause()
                playerLayer?.timer?.fireDate = NSDate.distantFuture()
            } else {
                self.panDirection = BMPanDirection.Vertical
                if locationPoint.x > self.bounds.size.width / 2 {
                    self.isVolume = true
                } else {
                    self.isVolume = false
                }
            }
            
        case UIGestureRecognizerState.Changed:
            switch self.panDirection {
            case BMPanDirection.Horizontal:
                self.horizontalMoved(velocityPoint.x)
                BMPlayerManager.shared.log("\(velocityPoint.x)")
            case BMPanDirection.Vertical:
                self.verticalMoved(velocityPoint.y)
                BMPlayerManager.shared.log("\(velocityPoint.y)")
            }
        case UIGestureRecognizerState.Ended:
            // 移动结束也需要判断垂直或者平移
            // 比如水平移动结束时，要快进到指定位置，如果这里没有判断，当我们调节音量完之后，会出现屏幕跳动的bug
            switch (self.panDirection) {
            case BMPanDirection.Horizontal:
                playerLayer?.player?.play()
                playerLayer?.timer?.fireDate = NSDate()
                
                controlView.hideSeekToView()
                playerLayer?.seekToTime(Int(self.sumTime), completionHandler: nil)
                // 把sumTime滞空，不然会越加越多
                self.sumTime = 0.0
                
            case BMPanDirection.Vertical:
                self.isVolume = false
            }
        default:
            break
        }
    }
    
    private func verticalMoved(value: CGFloat) {
        self.isVolume ? (self.volumeViewSlider.value -= Float(value / 10000)) : (UIScreen.mainScreen().brightness -= value / 10000)
    }
    
    private func horizontalMoved(value: CGFloat) {
        isSliderSliding = true
        if let playerItem = playerLayer?.playerItem {
            // 每次滑动需要叠加时间，通过一定的比例，使滑动一直处于统一水平
            self.sumTime = self.sumTime + NSTimeInterval(value) / 100.0 * (NSTimeInterval(self.totalTime)/400)
            
            let totalTime       = playerItem.duration
            
            // 防止出现NAN
            if totalTime.timescale == 0 { return }
            
            let totalDuration   = NSTimeInterval(totalTime.value) / NSTimeInterval(totalTime.timescale)
            if (self.sumTime > totalDuration) { self.sumTime = totalDuration}
            if (self.sumTime < 0){ self.sumTime = 0}
            
            let targetTime      = formatSecondsToString(sumTime)
            
            controlView.timeSlider.value      = Float(sumTime / self.totalTime)
            controlView.currentTimeLabel.text = targetTime
            controlView.showSeekToView(targetTime, isAdd: value > 0)
            
        }
    }
    
    @objc private func progressSliderTouchBegan(sender: UISlider)  {
        playerLayer?.onTimeSliderBegan()
        cancelAutoFadeOutControlBar()
        isSliderSliding = true
    }
    
    @objc private func progressSliderValueChanged(sender: UISlider)  {
        self.pause()
    }
    
    @objc private func progressSliderTouchEnded(sender: UISlider)  {
        controlView.showLoader()
        autoFadeOutControlBar()
        playerLayer?.onSliderTouchEnd(withValue: sender.value)
    }
    
    @objc private func backButtonPressed(button: UIButton) {
        if isFullScreen {
            fullScreenButtonPressed(nil)
        } else {
            playerLayer?.prepareToDeinit()
            backBlock?()
        }
    }
    
    @objc private func replayButtonPressed(button: UIButton) {
        controlView.centerButton.hidden = true
        self.playerLayer?.isPauseByUser = false
        playerLayer?.seekToTime(0, completionHandler: {
            self.playerLayer?.play()
        })
    }
    
    @objc private func playButtonPressed(button: UIButton) {
        if button.selected {
            self.pause()
        } else {
            self.play()
        }
    }
    
    @objc private func fullScreenButtonPressed(button: UIButton?) {
        if isFullScreen {
            UIDevice.currentDevice().setValue(UIInterfaceOrientation.Portrait.rawValue, forKey: "orientation")
            UIApplication.sharedApplication().setStatusBarHidden(false, withAnimation: UIStatusBarAnimation.Fade)
            UIApplication.sharedApplication().setStatusBarOrientation(UIInterfaceOrientation.Portrait, animated: false)
        } else {
            UIDevice.currentDevice().setValue(UIInterfaceOrientation.LandscapeRight.rawValue, forKey: "orientation")
            UIApplication.sharedApplication().setStatusBarHidden(false, withAnimation: UIStatusBarAnimation.Fade)
            UIApplication.sharedApplication().setStatusBarOrientation(UIInterfaceOrientation.LandscapeRight, animated: false)
        }
        isFullScreen = !isFullScreen
    }
    
    // MARK: - 生命周期
    deinit {
        playerLayer?.pause()
        playerLayer?.prepareToDeinit()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        initUI()
        initUIData()
        configureVolume()
        preparePlayer()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        initUI()
        initUIData()
        configureVolume()
        preparePlayer()
    }
    
    private func formatSecondsToString(secounds: NSTimeInterval) -> String {
        let Min = Int(secounds / 60)
        let Sec = Int(secounds % 60)
        return String(format: "%02d:%02d", Min, Sec)
    }
    
    // MARK: - 初始化
    private func initUI() {
        self.backgroundColor = UIColor.blackColor()
        if let customControlView = customControlView {
            controlView =  customControlView
        } else {
            controlView =  BMPlayerControlView()
        }
        
        addSubview(controlView)
        controlView.snp_makeConstraints { (make) in
            make.edges.equalTo(self)
        }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.tapGestureTapped(_:)))
        self.addGestureRecognizer(tapGesture)
        
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(self.panDirection(_:)))
        //        panGesture.delegate = self
        self.addGestureRecognizer(panGesture)
    }
    
    private func initUIData() {
        controlView.playButton.addTarget(self, action: #selector(self.playButtonPressed(_:)), forControlEvents: UIControlEvents.TouchUpInside)
        controlView.fullScreenButton.addTarget(self, action: #selector(self.fullScreenButtonPressed(_:)), forControlEvents: UIControlEvents.TouchUpInside)
        controlView.backButton.addTarget(self, action: #selector(self.backButtonPressed(_:)), forControlEvents: UIControlEvents.TouchUpInside)
        //        controlView.centerButton.addTarget(self, action: #selector(self.replayButtonPressed(_:)), forControlEvents: UIControlEvents.TouchUpInside)
        controlView.timeSlider.addTarget(self, action: #selector(progressSliderTouchBegan(_:)), forControlEvents: UIControlEvents.TouchDown)
        controlView.timeSlider.addTarget(self, action: #selector(progressSliderValueChanged(_:)), forControlEvents: UIControlEvents.ValueChanged)
        controlView.timeSlider.addTarget(self, action: #selector(progressSliderTouchEnded(_:)), forControlEvents: [UIControlEvents.TouchUpInside,UIControlEvents.TouchCancel, UIControlEvents.TouchUpOutside])
    }
    
    private func configureVolume() {
        let volumeView = MPVolumeView()
        for view in volumeView.subviews {
            if let slider = view as? UISlider {
                self.volumeViewSlider = slider
            }
        }
    }
    
    private func preparePlayer() {
        playerLayer = BMPlayerLayerView()
        insertSubview(playerLayer!, atIndex: 0)
        playerLayer!.snp_makeConstraints { (make) in
            make.edges.equalTo(self)
        }
        playerLayer!.delegate = self
        controlView.showLoader()
        self.layoutIfNeeded()
    }
}

extension BMPlayer: BMPlayerLayerViewDelegate {
    func bmPlayer(player player: BMPlayerLayerView, playerIsPlaying playing: Bool) {
        playStateDidChanged()
    }
    
    func bmPlayer(player player: BMPlayerLayerView ,loadedTimeDidChange  loadedDuration: NSTimeInterval , totalDuration: NSTimeInterval) {
        BMPlayerManager.shared.log("loadedTimeDidChange - \(loadedDuration) - \(totalDuration)")
        controlView.progressView.setProgress(Float(loadedDuration)/Float(totalDuration), animated: true)
    }
    
    func bmPlayer(player player: BMPlayerLayerView, playerStateDidChange state: BMPlayerState) {
        BMPlayerManager.shared.log("playerStateDidChange - \(state)")
        switch state {
        case BMPlayerState.ReadyToPlay:
            break
        case BMPlayerState.Buffering:
            cancelAutoFadeOutControlBar()
            controlView.showLoader()
            playStateDidChanged()
        case BMPlayerState.BufferFinished:
            controlView.hideLoader()
            playStateDidChanged()
        case BMPlayerState.PlayedToTheEnd:
            self.pause()
            controlView.showVideoEndedView()
        default:
            break
        }
    }
    
    func bmPlayer(player player: BMPlayerLayerView, playTimeDidChange currentTime: NSTimeInterval, totalTime: NSTimeInterval) {
        BMPlayerManager.shared.log("playTimeDidChange - \(currentTime) - \(totalTime)")
        self.totalTime = totalTime
        if isSliderSliding {
            return
        }
        controlView.currentTimeLabel.text = formatSecondsToString(currentTime)
        controlView.totalTimeLabel.text = formatSecondsToString(totalTime)
        
        controlView.timeSlider.value    = Float(currentTime) / Float(totalTime)
    }
}