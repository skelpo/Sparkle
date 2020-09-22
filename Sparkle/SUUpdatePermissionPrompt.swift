//
//  SUUpdatePermissionPrompt.swift
//  Sparkle
//
//  Created by Gwynne Raskind on 9/16/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

import Cocoa

public typealias SUUpdatePermissionCallback = @convention(block) (SUUpdatePermissionResponse) -> Void

fileprivate extension NSView {
    func resizeFrame(dx: CGFloat, dy: CGFloat) {
        self.setFrameSize(.init(width: self.frame.size.width + dx, height: self.frame.size.height + dy))
    }
}

fileprivate extension NSWindow {
    func insetFrame(dx: CGFloat, dy: CGFloat, display: Bool = false, animate: Bool = false) {
        self.setFrame(self.frame.insetBy(dx: dx, dy: dy), display: display, animate: animate)
    }
}

@objc public final class SUUpdatePermissionPrompt: NSWindowController, NSTouchBarDelegate, NSTableViewDelegate {
    
    // MARK: - API
    
    /// If this is a background application we need to focus it in order to bring the prompt
    /// to the user's attention. Otherwise the prompt would be hidden behind other applications and
    /// the user would not know why the application was paused.
    @objc public static func prompt(host: SUHost, request: SPUUpdatePermissionRequest, reply: @escaping SUUpdatePermissionCallback) {
        if SUApplicationInfo.isBackground(application: NSApp) {
            NSApp.activate(ignoringOtherApps: true)
        }
        if NSApp.modalWindow == nil {
            // do not prompt if there is is another modal window on screen
            let prompt = Self.init(host: host, request: request, reply: reply)
            if let window = prompt.window {
                NSApp.runModal(for: window)
            }
        }
    }
    
    // MARK: - Outlets
    
    @IBOutlet private var descriptionTextField: NSTextField!
    @IBOutlet private var moreInfoView: NSView!
    @IBOutlet private var moreInfoButton: NSButton!
    @IBOutlet private var profileTableView: NSTableView!
    @IBOutlet private var cancelButton: NSButton!
    @IBOutlet private var checkButton: NSButton!

    // MARK: - Private properties
    
    private let reply: SUUpdatePermissionCallback
    private let host: SUHost
    private var isShowingMoreInfo: Bool
    private var shouldSendProfile: Bool
    private var systemProfileInformationArray: [[String: String]]
    
    // MARK: - Initialization and loading
    
    required init(host: SUHost, request: SPUUpdatePermissionRequest, reply: @escaping SUUpdatePermissionCallback) {
        self.reply = reply
        self.host = host
        self.isShowingMoreInfo = false
        self.shouldSendProfile = host.bool(forInfoDictionaryKey: SUEnableSystemProfilingKey)
        self.systemProfileInformationArray = request.systemProfile
        super.init(window: nil)
        self.shouldCascadeWindows = false
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override public var windowNibName: NSNib.Name? { "SUUpdatePermissionPrompt" }
    
    override public func windowDidLoad() {
        if !self.shouldSendProfile {
            var frame = self.window!.frame
            frame.size.height -= self.moreInfoButton.frame.size.height
            self.window!.setFrame(frame, display: true)
        } else {
            self.profileTableView.delegate = self
        }
    }
    
    // MARK: - NSTableViewDelegate
    
    public func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    // MARK: - Actions
    
    @IBAction func toggleMoreInfo(_ sender: AnyObject?) {
        self.isShowingMoreInfo.toggle()
        
        let contentView = self.window!.contentView!
        var moreInfoViewFrame = self.moreInfoView.frame
        
        if self.isShowingMoreInfo {
            moreInfoViewFrame = .init(
                x: self.descriptionTextField.frame.origin.x, y: self.moreInfoButton.frame.origin.y - moreInfoViewFrame.size.height,
                width: self.descriptionTextField.frame.size.width, height: moreInfoViewFrame.size.height)
            self.moreInfoView.frame = moreInfoViewFrame
            contentView.addSubview(self.moreInfoView, positioned: .below, relativeTo: self.moreInfoButton)
        } else {
            self.moreInfoView.removeFromSuperview()
        }
        contentView.resizeFrame(dx: 0.0, dy: (self.isShowingMoreInfo ? 1.0 : -1.0) * moreInfoViewFrame.size.height)
        contentView.needsDisplay = true
        self.window!.insetFrame(dx: 0.0, dy: (self.isShowingMoreInfo ? -1.0 : 1.0) * moreInfoViewFrame.size.height, display: true, animate: true)
        self.moreInfoView.isHidden = !self.isShowingMoreInfo
    }
    
    @IBAction func finishPrompt(_ sender: NSButton) {
        let response = SUUpdatePermissionResponse(automaticUpdateChecks: sender.tag == 1, sendSystemProfile: self.shouldSendProfile)!
        
        self.reply(response)
        self.window!.close()
        NSApp.stopModal()
    }

    // MARK: - Bindings
    
    @objc public var icon: NSImage? { SUApplicationInfo.bestIcon(forHost: self.host) }
    
    @objc public var promptDescription: String {
        String.localizedStringWithFormat(SULocalizedString("Should %1$@ automatically check for updates? You can always check for updates manually from the %1$@ menu.", nil), self.host.name)
    }

    // MARK: - Touch Bar
    
    private static var TouchBarIndentifier: NSTouchBarItem.Identifier { .init("\(SUBundleIdentifier).SUUpdatePermissionPrompt") }

    public override func makeTouchBar() -> NSTouchBar? {
        let touchBar = NSTouchBar()
        touchBar.defaultItemIdentifiers = [Self.TouchBarIndentifier]
        touchBar.principalItemIdentifier = Self.TouchBarIndentifier
        touchBar.delegate = self
        return touchBar
    }
    
    public func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
            case Self.TouchBarIndentifier:
                let item = NSCustomTouchBarItem(identifier: identifier)
                item.viewController = SUTouchBarButtonGroup(referencingButtons:[self.checkButton, self.cancelButton])
                return item
            default:
                return nil
        }
    }
}
