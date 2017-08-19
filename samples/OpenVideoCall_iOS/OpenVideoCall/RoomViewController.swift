//
//  RoomViewController.swift
//  OpenVideoCall
//
//  Created by GongYuhua on 16/8/22.
//  Copyright © 2016年 Agora. All rights reserved.
//

import UIKit
import AVFoundation

protocol RoomVCDelegate: class {
    func roomVCNeedClose(_ roomVC: RoomViewController)
}

class RoomViewController: UIViewController {
    
    //MARK: Faceunity
    static var mcontext:EAGLContext!
    var items:[Int32] = [0,0]
    var fuInit:Bool = false
    var frameID:Int32 = 0
    var needReloadItem:Bool = true
    // --------------- Faceunity ----------------
    
    //MARK: Thrid filter
    fileprivate lazy var yuvProcessor:YuvPreProcessor? = {
        let yuvProcessor = YuvPreProcessor()
        yuvProcessor.delegate = self
        return yuvProcessor
    }()
    fileprivate var shouldYuvProcessor = true {
        didSet {
            if shouldYuvProcessor {
                yuvProcessor?.turnOn()
            } else {
                yuvProcessor?.turnOff()
            }
        }
    }
    
    //MARK: IBOutlet
    @IBOutlet weak var containerView: UIView!
    @IBOutlet var flowViews: [UIView]!
    @IBOutlet weak var roomNameLabel: UILabel!
    
    @IBOutlet weak var controlView: UIView!
    @IBOutlet weak var messageTableContainerView: UIView!
    
    @IBOutlet weak var messageButton: UIButton!
    
    @IBOutlet weak var muteVideoButton: UIButton!
    @IBOutlet weak var muteAudioButton: UIButton!
    
    @IBOutlet weak var cameraButton: UIButton!
    @IBOutlet weak var speakerButton: UIButton!
    
    @IBOutlet weak var filterButton: UIButton!
    
    @IBOutlet weak var messageInputerView: UIView!
    @IBOutlet weak var messageInputerBottom: NSLayoutConstraint!
    @IBOutlet weak var messageTextField: UITextField!
    
    @IBOutlet var backgroundTap: UITapGestureRecognizer!
    {
        didSet {
            backgroundTap.delegate = self
        }
    }
    @IBOutlet var backgroundDoubleTap: UITapGestureRecognizer!
    
    @IBOutlet var fuDemoBar: FUAPIDemoBar! {
        
        didSet {
//            fuDemoBar.itemsDataSource = ["noitem", "tiara", "item0208", "YellowEar", "PrincessCrown", "Mood", "Deer", "BeagleDog", "item0501", "item0210",  "HappyRabbi", "item0204", "hartshorn", "ColorCrown"]
            
            fuDemoBar.itemsDataSource = ["noitem", "yuguan", "yazui", "mask_matianyu", "lixiaolong", "EatRabbi", "Mood"]
            fuDemoBar.selectedItem = fuDemoBar.itemsDataSource[1]
            
            fuDemoBar.filtersDataSource = ["nature", "delta", "electric", "slowlived", "tokyo", "warm"]
            fuDemoBar.selectedFilter = fuDemoBar.filtersDataSource[0]
            
            fuDemoBar.selectedBlur = 6
            fuDemoBar.beautyLevel = 0.2
            fuDemoBar.thinningLevel = 1.0
            fuDemoBar.enlargingLevel = 0.5
            fuDemoBar.faceShapeLevel = 0.5
            fuDemoBar.faceShape = 3
            fuDemoBar.redLevel = 0.5
            fuDemoBar.delegate = self
        }

    }
    
    //MARK: public var
    var roomName: String!
    var encryptionSecret: String?
    var encryptionType: EncryptionType!
    var videoProfile: AgoraRtcVideoProfile!
    weak var delegate: RoomVCDelegate?
    
    //MARK: hide & show
    fileprivate var shouldHideFlowViews = false {
        didSet {
            if let flowViews = flowViews {
                for view in flowViews {
                    view.isHidden = shouldHideFlowViews
                }
            }
        }
    }
    
    //MARK: engine & session
    var agoraKit: AgoraRtcEngineKit!
    fileprivate var videoSessions = [VideoSession]() {
        didSet {
            updateInterface(with: self.videoSessions, targetSize: containerView.frame.size, animation: true)
        }
    }
    fileprivate var doubleClickFullSession: VideoSession? {
        didSet {
            if videoSessions.count >= 3 && doubleClickFullSession != oldValue {
                updateInterface(with: videoSessions, targetSize: containerView.frame.size, animation: true)
            }
        }
    }
    fileprivate let videoViewLayouter = VideoViewLayouter()
    fileprivate var dataChannelId: Int = -1
    
    //MARK: alert
    fileprivate weak var currentAlert: UIAlertController?
    
    //MARK: mute
    fileprivate var audioMuted = false {
        didSet {
            muteAudioButton?.setImage(UIImage(named: audioMuted ? "btn_mute_blue" : "btn_mute"), for: UIControlState())
            agoraKit.muteLocalAudioStream(audioMuted)
        }
    }
    fileprivate var videoMuted = false {
        didSet {
            muteVideoButton?.setImage(UIImage(named: videoMuted ? "btn_video" : "btn_voice"), for: UIControlState())
            cameraButton?.isHidden = videoMuted
            speakerButton?.isHidden = !videoMuted
            
            agoraKit.muteLocalVideoStream(videoMuted)
            setVideoMuted(videoMuted, forUid: 0)
            
            updateSelfViewVisiable()
        }
    }
    
    //MARK: speaker
    fileprivate var speakerEnabled = true {
        didSet {
            speakerButton?.setImage(UIImage(named: speakerEnabled ? "btn_speaker_blue" : "btn_speaker"), for: UIControlState())
            speakerButton?.setImage(UIImage(named: speakerEnabled ? "btn_speaker" : "btn_speaker_blue"), for: .highlighted)
            
            agoraKit.setEnableSpeakerphone(speakerEnabled)
        }
    }
    
    //MARK: filter
    fileprivate var isFiltering = false {
        didSet {
            guard let agoraKit = agoraKit else {
                return
            }
            
            if isFiltering {
                AGVideoPreProcessing.registerVideoPreprocessing(agoraKit)
                filterButton?.setImage(UIImage(named: "btn_filter_blue"), for: UIControlState())
            } else {
                AGVideoPreProcessing.deregisterVideoPreprocessing(agoraKit)
                filterButton?.setImage(UIImage(named: "btn_filter"), for: UIControlState())
            }
        }
    }
    
    //MARK: text message
    fileprivate var chatMessageVC: ChatMessageViewController?
    fileprivate var isInputing = false {
        didSet {
            if isInputing {
                messageTextField?.becomeFirstResponder()
            } else {
                messageTextField?.resignFirstResponder()
            }
            messageInputerView?.isHidden = !isInputing
            messageButton?.setImage(UIImage(named: isInputing ? "btn_message_blue" : "btn_message"), for: UIControlState())
        }
    }
    
    //MARK: - life cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        roomNameLabel.text = "\(roomName!)"
        backgroundTap.require(toFail: backgroundDoubleTap)
        addKeyboardObserver()
        
        loadAgoraKit()

    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let segueId = segue.identifier else {
            return
        }
        
        switch segueId {
        case "VideoVCEmbedChatMessageVC":
            chatMessageVC = segue.destination as? ChatMessageViewController
        default:
            break
        }
    }
    
    //MARK: - user action
    @IBAction func doMessagePressed(_ sender: UIButton) {
        isInputing = !isInputing
    }
    
    @IBAction func doCloseMessagePressed(_ sender: UIButton) {
        isInputing = false
    }
    
    @IBAction func doMuteVideoPressed(_ sender: UIButton) {
        videoMuted = !videoMuted
    }
    
    @IBAction func doMuteAudioPressed(_ sender: UIButton) {
        audioMuted = !audioMuted
    }
    
    @IBAction func doCameraPressed(_ sender: UIButton) {
        agoraKit.switchCamera()
    }
    
    @IBAction func doSpeakerPressed(_ sender: UIButton) {
        speakerEnabled = !speakerEnabled
    }
    
    @IBAction func doFilterPressed(_ sender: UIButton) {
        isFiltering = !isFiltering
    }
    
    @IBAction func doClosePressed(_ sender: UIButton) {
        leaveChannel()
    }
    
    @IBAction func doBackTapped(_ sender: UITapGestureRecognizer) {
        
        if !isInputing {
            shouldHideFlowViews = !shouldHideFlowViews
        }
    }
    
    @IBAction func doBackDoubleTapped(_ sender: UITapGestureRecognizer) {
        if doubleClickFullSession == nil {
            //将双击到的session全屏
            if let tappedIndex = videoViewLayouter.reponseViewIndex(of: sender.location(in: containerView)) {
                doubleClickFullSession = videoSessions[tappedIndex]
            }
        } else {
            doubleClickFullSession = nil
        }
    }
    
    override var supportedInterfaceOrientations : UIInterfaceOrientationMask {
        return .all
    }
}

//MARK: - textFiled
extension RoomViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if let text = textField.text , !text.isEmpty {
            send(text: text)
            textField.text = nil
        }
        return true
    }
}

//MARK: - private
private extension RoomViewController {
    func addKeyboardObserver() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name.UIKeyboardWillShow, object: nil, queue: nil) { [weak self] notify in
            guard let strongSelf = self, let userInfo = (notify as NSNotification).userInfo,
                let keyBoardBoundsValue = userInfo[UIKeyboardFrameEndUserInfoKey] as? NSValue,
                let durationValue = userInfo[UIKeyboardAnimationDurationUserInfoKey] as? NSNumber else {
                    return
            }
            
            let keyBoardBounds = keyBoardBoundsValue.cgRectValue
            let duration = durationValue.doubleValue
            let deltaY = keyBoardBounds.size.height
            
            if duration > 0 {
                var optionsInt: UInt = 0
                if let optionsValue = userInfo[UIKeyboardAnimationCurveUserInfoKey] as? NSNumber {
                    optionsInt = optionsValue.uintValue
                }
                let options = UIViewAnimationOptions(rawValue: optionsInt)
                
                UIView.animate(withDuration: duration, delay: 0, options: options, animations: {
                    strongSelf.messageInputerBottom.constant = deltaY
                    strongSelf.view?.layoutIfNeeded()
                    }, completion: nil)
                
            } else {
                strongSelf.messageInputerBottom.constant = deltaY
            }
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name.UIKeyboardWillHide, object: nil, queue: nil) { [weak self] notify in
            guard let strongSelf = self else {
                return
            }
            
            let duration: Double
            if let userInfo = (notify as NSNotification).userInfo, let durationValue = userInfo[UIKeyboardAnimationDurationUserInfoKey] as? NSNumber {
                duration = durationValue.doubleValue
            } else {
                duration = 0
            }
            
            if duration > 0 {
                var optionsInt: UInt = 0
                if let userInfo = (notify as NSNotification).userInfo, let optionsValue = userInfo[UIKeyboardAnimationCurveUserInfoKey] as? NSNumber {
                    optionsInt = optionsValue.uintValue
                }
                let options = UIViewAnimationOptions(rawValue: optionsInt)
                
                UIView.animate(withDuration: duration, delay: 0, options: options, animations: {
                    strongSelf.messageInputerBottom.constant = 0
                    strongSelf.view?.layoutIfNeeded()
                    }, completion: nil)
                
            } else {
                strongSelf.messageInputerBottom.constant = 0
            }
        }
    }
    
    func updateInterface(with sessions: [VideoSession], targetSize: CGSize, animation: Bool) {
        if animation {
            UIView.animate(withDuration: 0.3, delay: 0, options: .beginFromCurrentState, animations: {[weak self] () -> Void in
                self?.updateInterface(with: sessions, targetSize: targetSize)
                self?.view.layoutIfNeeded()
                }, completion: nil)
        } else {
            updateInterface(with: sessions, targetSize: targetSize)
        }
    }
    
    func updateInterface(with sessions: [VideoSession], targetSize: CGSize) {
        guard !sessions.isEmpty else {
            return
        }
        
        let selfSession = sessions.first!
        videoViewLayouter.selfView = selfSession.hostingView
        videoViewLayouter.selfSize = selfSession.size
        videoViewLayouter.targetSize = targetSize
        var peerVideoViews = [VideoView]()
        for i in 1..<sessions.count {
            peerVideoViews.append(sessions[i].hostingView)
        }
        videoViewLayouter.videoViews = peerVideoViews
        videoViewLayouter.fullView = doubleClickFullSession?.hostingView
        videoViewLayouter.containerView = containerView
        
        videoViewLayouter.layoutVideoViews()
        
        updateSelfViewVisiable()
        
        //只有三人及以上时才能切换布局形式
        if sessions.count >= 3 {
            backgroundDoubleTap.isEnabled = true
        } else {
            backgroundDoubleTap.isEnabled = false
            doubleClickFullSession = nil
        }
    }
    
    func setIdleTimerActive(_ active: Bool) {
        UIApplication.shared.isIdleTimerDisabled = !active
    }
    
    func fetchSession(of uid: UInt) -> VideoSession? {
        for session in videoSessions {
            if session.uid == uid {
                return session
            }
        }
        
        return nil
    }
    
    func videoSession(of uid: UInt) -> VideoSession {
        if let fetchedSession = fetchSession(of: uid) {
            return fetchedSession
        } else {
            let newSession = VideoSession(uid: uid)
            videoSessions.append(newSession)
            return newSession
        }
    }
    
    func setVideoMuted(_ muted: Bool, forUid uid: UInt) {
        fetchSession(of: uid)?.isVideoMuted = muted
    }
    
    func updateSelfViewVisiable() {
        guard let selfView = videoSessions.first?.hostingView else {
            return
        }
        
        if videoSessions.count == 2 {
            selfView.isHidden = videoMuted
        } else {
            selfView.isHidden = false
        }
    }
    
    func alert(string: String) {
        guard !string.isEmpty else {
            return
        }
        chatMessageVC?.append(alert: string)
    }
}

//MARK: - engine
private extension RoomViewController {
    func loadAgoraKit() {
        agoraKit = AgoraRtcEngineKit.sharedEngine(withAppId: KeyCenter.AppId, delegate: self)
        agoraKit.setChannelProfile(.channelProfile_Communication)
        agoraKit.enableVideo()
        agoraKit.setVideoProfile(videoProfile, swapWidthAndHeight: false)
        
        addLocalSession()
        agoraKit.startPreview()
        if let encryptionType = encryptionType, let encryptionSecret = encryptionSecret, !encryptionSecret.isEmpty {
            agoraKit.setEncryptionMode(encryptionType.modeString())
            agoraKit.setEncryptionSecret(encryptionSecret)
        }
        
        let code = agoraKit.joinChannel(byKey: nil, channelName: roomName, info: nil, uid: 0, joinSuccess: nil)
        
        if code == 0 {
            setIdleTimerActive(false)
            shouldYuvProcessor = true
        } else {
            DispatchQueue.main.async(execute: {
                self.alert(string: "Join channel failed: \(code)")
            })
        }
        
        agoraKit.createDataStream(&dataChannelId, reliable: true, ordered: true)
    }
    
    func addLocalSession() {
        let localSession = VideoSession.localSession()
        videoSessions.append(localSession)
        agoraKit.setupLocalVideo(localSession.canvas)
        
        if let mediaInfo = MediaInfo(videoProfile: videoProfile) {
            localSession.mediaInfo = mediaInfo
        }
    }
    
    func leaveChannel() {
        agoraKit.setupLocalVideo(nil)
        agoraKit.leaveChannel(nil)
        agoraKit.stopPreview()
        isFiltering = false
        
        if shouldYuvProcessor {
            //离开时关闭YuvProcessor,并销毁美颜及道具内存
            shouldYuvProcessor = false
            
            //-------------faceunity--------------
            setupContex()
            fuDestroyAllItems()
        }
        
        for session in videoSessions {
            session.hostingView.removeFromSuperview()
        }
        videoSessions.removeAll()
        
        setIdleTimerActive(true)
        delegate?.roomVCNeedClose(self)
    }
    
    func send(text: String) {
        if dataChannelId > 0, let data = text.data(using: String.Encoding.utf8) {
            agoraKit.sendStreamMessage(dataChannelId, data: data)
            chatMessageVC?.append(chat: text, fromUid: 0)
        }
    }
}

//MARK: - engine delegate
extension RoomViewController: AgoraRtcEngineDelegate {
    func rtcEngineConnectionDidInterrupted(_ engine: AgoraRtcEngineKit!) {
        alert(string: "Connection Interrupted")
    }
    
    func rtcEngineConnectionDidLost(_ engine: AgoraRtcEngineKit!) {
        alert(string: "Connection Lost")
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit!, didOccurError errorCode: AgoraRtcErrorCode) {
        //
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit!, firstRemoteVideoDecodedOfUid uid: UInt, size: CGSize, elapsed: Int) {
        let userSession = videoSession(of: uid)
        let sie = size.fixedSize(with: containerView.bounds.size)
        userSession.size = sie
        userSession.updateMediaInfo(resolution: size)
        agoraKit.setupRemoteVideo(userSession.canvas)
    }
    
    //first local video frame
    func rtcEngine(_ engine: AgoraRtcEngineKit!, firstLocalVideoFrameWith size: CGSize, elapsed: Int) {
        if let selfSession = videoSessions.first {
            let fixedSize = size.fixedSize(with: containerView.bounds.size)
            selfSession.size = fixedSize
            updateInterface(with: videoSessions, targetSize: containerView.frame.size, animation: false)
        }
    }
    
    //user offline
    func rtcEngine(_ engine: AgoraRtcEngineKit!, didOfflineOfUid uid: UInt, reason: AgoraRtcUserOfflineReason) {
        var indexToDelete: Int?
        for (index, session) in videoSessions.enumerated() {
            if session.uid == uid {
                indexToDelete = index
            }
        }
        
        if let indexToDelete = indexToDelete {
            let deletedSession = videoSessions.remove(at: indexToDelete)
            deletedSession.hostingView.removeFromSuperview()
            if let doubleClickFullSession = doubleClickFullSession , doubleClickFullSession == deletedSession {
                self.doubleClickFullSession = nil
            }
        }
    }
    
    //video muted
    func rtcEngine(_ engine: AgoraRtcEngineKit!, didVideoMuted muted: Bool, byUid uid: UInt) {
        setVideoMuted(muted, forUid: uid)
    }
    
    //remote stat
    func rtcEngine(_ engine: AgoraRtcEngineKit!, remoteVideoStats stats: AgoraRtcRemoteVideoStats!) {
        if let stats = stats, let session = fetchSession(of: stats.uid) {
            session.updateMediaInfo(resolution: CGSize(width: CGFloat(stats.width), height: CGFloat(stats.height)), bitRate: Int(stats.receivedBitrate), fps: Int(stats.receivedFrameRate))
        }
    }
    
    //data channel
    func rtcEngine(_ engine: AgoraRtcEngineKit!, receiveStreamMessageFromUid uid: UInt, streamId: Int, data: Data!) {
        guard let data = data, let string = String(data: data, encoding: String.Encoding.utf8) , !string.isEmpty else {
            return
        }
        chatMessageVC?.append(chat: string, fromUid: Int64(uid))
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit!, didOccurStreamMessageErrorFromUid uid: UInt, streamId: Int, error: Int, missed: Int, cached: Int) {
        print("Data channel error: \(error), missed: \(missed), cached: \(cached)\n")
    }
}

extension RoomViewController:UIGestureRecognizerDelegate
{
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        
        let ret = touch.view?.superview?.superview?.isKind(of: VideoView.self) ?? false || touch.view?.superview?.isKind(of: VideoView.self) ?? false || touch.view?.isKind(of: VideoView.self) ?? false || touch.view == self.controlView

        return ret
    }
}

//MARK: - rotation
extension RoomViewController {
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        for session in videoSessions {
            if let sessionSize = session.size {
                session.size = sessionSize.fixedSize(with: size)
            }
        }
        updateInterface(with: videoSessions, targetSize: size, animation: true)
        
        var frame = fuDemoBar.frame
        frame.size.width = size.width
        fuDemoBar.frame = frame
    }
}

//MARK: - FUAPIDemoBarDelegate
extension RoomViewController: FUAPIDemoBarDelegate
{
    func demoBarDidSelectedItem(_ item: String!) {
        needReloadItem = true
    }
    
}

//MARK: - YuvPreProcessorProtocol

//在这里处理视频数据，添加Faceunity特效
extension RoomViewController: YuvPreProcessorProtocol {
    func onFrameAvailable(_ y: UnsafeMutablePointer<UInt8>, ubuf u: UnsafeMutablePointer<UInt8>, vbuf v: UnsafeMutablePointer<UInt8>, ystride: Int32, ustride: Int32, vstride: Int32, width: Int32, height: Int32) {
        
        setupContex()
        
        if !fuInit {
            fuInit = true
            var size:Int32 = 0;
            let v3 = mmap_bundle(bundle: "v3.bundle", psize: &size)
            
            FURenderer.share().setup(withData: v3, ardata: nil, authPackage: &g_auth_package, authSize: Int32(MemoryLayout.size(ofValue: g_auth_package)))
        }
        
        if needReloadItem {
            needReloadItem = false
            
            reloadItem()
        }
        
        if items[1] == 0 {
            loadFilter()
        }
        
        //  Set item parameters
        fuItemSetParamd(items[1], UnsafeMutablePointer(mutating: ("cheek_thinning" as NSString).utf8String!), Double(self.fuDemoBar.thinningLevel));//瘦脸
        fuItemSetParamd(items[1], UnsafeMutablePointer(mutating: ("eye_enlarging" as NSString).utf8String!), Double(self.fuDemoBar.enlargingLevel));//大眼
        fuItemSetParamd(items[1], UnsafeMutablePointer(mutating: ("color_level" as NSString).utf8String!), Double(self.fuDemoBar.beautyLevel));//美白
        fuItemSetParams(items[1], UnsafeMutablePointer(mutating: ("filter_name" as NSString).utf8String!), UnsafeMutablePointer(mutating: (fuDemoBar.selectedFilter as NSString).utf8String!));// 滤镜
        fuItemSetParamd(items[1], UnsafeMutablePointer(mutating: ("blur_level" as NSString).utf8String!), Double(self.fuDemoBar.selectedBlur));// 磨皮
        fuItemSetParamd(items[1], UnsafeMutablePointer(mutating: ("face_shape" as NSString).utf8String!), Double(self.fuDemoBar.faceShape));//瘦脸类型
        fuItemSetParamd(items[1], UnsafeMutablePointer(mutating: ("face_shape_level" as NSString).utf8String!), Double(self.fuDemoBar.faceShapeLevel));//瘦脸等级
        fuItemSetParamd(items[1], UnsafeMutablePointer(mutating: ("red_level" as NSString).utf8String!), Double(self.fuDemoBar.redLevel));//红润
        
        FURenderer.share().renderFrame(y, u: u, v: v, ystride: ystride, ustride: ustride, vstride: vstride, width: width, height: height, frameId: frameID, items: UnsafeMutablePointer<Int32>(mutating: items)!, itemCount: 2);
        
        frameID += 1
    }
    
}

//MARK: -Faceunity Data Load
extension RoomViewController
{
    func setupContex() {
        
        if RoomViewController.mcontext == nil {
            RoomViewController.mcontext = EAGLContext(api: .openGLES2)
        }
        
        if RoomViewController.mcontext == nil || !EAGLContext.setCurrent(RoomViewController.mcontext) {
            print("context error")
        }
    }
    
    func reloadItem()
    {
        setupContex()
        
        if fuDemoBar.selectedItem == "noitem" || fuDemoBar.selectedItem == nil
        {
            if items[0] != 0 {
                fuDestroyItem(items[0])
            }
            items[0] = 0
            return
        }
        
        var size:Int32 = 0
        // load selected
        let data = mmap_bundle(bundle: fuDemoBar.selectedItem + ".bundle", psize: &size)
        
        let itemHandle = fuCreateItemFromPackage(data, size)
        
        if items[0] != 0 {
            fuDestroyItem(items[0])
        }
        
        items[0] = itemHandle
        
        print("faceunity: load item")
    }
    
    func loadFilter()
    {
        setupContex()
        
        var size:Int32 = 0
        
        let data = mmap_bundle(bundle: "face_beautification.bundle", psize: &size)
        
        items[1] = fuCreateItemFromPackage(data, size);
    }
    
    func mmap_bundle(bundle: String, psize:inout Int32) -> UnsafeMutableRawPointer? {
        
        // Load item from predefined item bundle
        let str = Bundle.main.resourcePath! + "/" + bundle
        let fn = str.cString(using: String.Encoding.utf8)!
        let fd = open(fn, O_RDONLY)
        
        var size:Int32
        var zip:UnsafeMutableRawPointer!
        
        if fd == -1 {
            print("faceunity: failed to open bundle")
            size = 0
        }else
        {
            size = getFileSize(fd: fd);
            zip = mmap(nil, Int(size), PROT_READ, MAP_SHARED, fd, 0)
        }
        
        psize = size
        return zip
    }
    
    func getFileSize(fd: Int32) -> Int32
    {
        var sb:stat = stat()
        sb.st_size = 0
        fstat(fd, &sb)
        return Int32(sb.st_size)
    }
}
