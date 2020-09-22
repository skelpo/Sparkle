//
//  SUUpdateAlert.swift
//  Sparkle
//
//  Created by Gwynne Raskind on 9/16/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

import Cocoa
import WebKit

@objcMembers internal final class SUUpdateAlert: NSWindowController, WebFrameLoadDelegate, WebPolicyDelegate, WebUIDelegate, NSTouchBarDelegate, NSWindowDelegate {
    
    // MARK: - Callback types
    
    internal typealias StandardCompletionBlock = @convention(block) (SPUUserDriverUpdatePendingAction) -> Void
    internal typealias ResumableCompletionBlock = @convention(block) (SPUUserDriverUpdateInstallationAction) -> Void
    internal typealias InformationalCompletionBlock = @convention(block) (SPUUserDriverUpdateInformationAction) -> Void
    
    private enum StoredCompletion {
        case standard(StandardCompletionBlock)
        case resumable(ResumableCompletionBlock)
        case informational(InformationalCompletionBlock)
        
        func invoke(with selection: SPUUpdateAlertChoice) { switch self {
            case .standard(let block): block(selection.toUpdatePendingAction)
            case .resumable(let block): block(selection.toUpdateInstallationAction)
            case .informational(let block): block(selection.toUpdateInformationAction)
        } }
    }
    
    // MARK: - Outlets
    
    @IBOutlet private      var releaseNotesView: WebView!
    @IBOutlet private weak var releaseNotesContainerView: NSView!
    @IBOutlet private weak var descriptionField: NSTextField!
    @IBOutlet private weak var automaticallyInstallUpdatesButton: NSButton!
    @IBOutlet private weak var installButton: NSButton!
    @IBOutlet private weak var skipButton: NSButton!
    @IBOutlet private weak var laterButton: NSButton!
    
    // MARK: - Private properties
    
    private let host: SUHost
    private let updateItem: SUAppcastItem
    private var allowsAutomaticUpdates: Bool
    private var completion: StoredCompletion?
    private var alreadyDownloaded: Bool = false
    private var appearanceObservation: NSKeyValueObservation?
    private var releaseNotesSpinner: NSProgressIndicator?
    private var webViewFinishedLoading: Bool = false
    private var darkBackgroundView: NSBox?
    
    // MARK: - Interface properties
    
    internal private(set) weak var versionDisplayer: SUVersionDisplay?
    
    // MARK: - Initializers

    private init(appcastItem: SUAppcastItem, host: SUHost, versionDisplayer: SUVersionDisplay?, completion: StoredCompletion, alreadyDownloaded: Bool = false) {
        self.host = host
        self.updateItem = appcastItem
        self.versionDisplayer = versionDisplayer
        self.allowsAutomaticUpdates = SPUUpdaterSettings(hostBundle: host.bundle).allowsAutomaticUpdates && !appcastItem.isInformationOnlyUpdate
        self.completion = completion
        self.alreadyDownloaded = alreadyDownloaded

        super.init(window: nil)
        self.shouldCascadeWindows = false
        
        // Note: No need to put a dummy call to `WebView` here, in Swift the `import` will guarantee the link.
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    public override var windowNibName: NSNib.Name? { "SUUpdateAlert" }
    
    internal convenience init(
        appcastItem: SUAppcastItem, alreadyDownloaded: Bool, host: SUHost, versionDisplayer: SUVersionDisplay?,
        completionBlock: @escaping StandardCompletionBlock
    ) {
        self.init(
            appcastItem: appcastItem, host: host, versionDisplayer: versionDisplayer,
            completion: .standard(completionBlock), alreadyDownloaded: alreadyDownloaded
        )
    }

    internal convenience init(
        appcastItem: SUAppcastItem, host: SUHost, versionDisplayer: SUVersionDisplay?,
        resumableCompletionBlock: @escaping ResumableCompletionBlock
    ) {
        self.init(
            appcastItem: appcastItem, host: host, versionDisplayer: versionDisplayer,
            completion: .resumable(resumableCompletionBlock), alreadyDownloaded: true
        )
    }
    
    internal convenience init(
        appcastItem: SUAppcastItem, host: SUHost, versionDisplayer: SUVersionDisplay?,
        informationalCompletionBlock: @escaping InformationalCompletionBlock
    ) {
        self.init(appcastItem: appcastItem, host: host, versionDisplayer: versionDisplayer, completion: .informational(informationalCompletionBlock))
    }
    
    // MARK: - Actions
    
    @IBAction func installUpdate(_: Any) {
        self.end(with: .installUpdateChoice)
    }
    
    @IBAction func openInfoURL(_: Any) {
        NSWorkspace.shared.open(self.updateItem.infoURL)
        self.end(with: .installLaterChoice)
    }
    
    @IBAction func skipThisVersion(_: Any) {
        self.end(with: .skipThisVersionChoice)
    }
    
    @IBAction func remindMeLater(_: Any) {
        self.end(with: .installLaterChoice)
    }

    // MARK: - Implementation
    
    private func end(with selection: SPUUpdateAlertChoice) {
        self.releaseNotesView.stopLoading(self)
        self.releaseNotesView.frameLoadDelegate = nil
        self.releaseNotesView.policyDelegate = nil
        self.releaseNotesView.removeFromSuperview() // Otherwise it gets sent Esc presses (why?!) and gets very confused.
        self.close()
        self.completion?.invoke(with: selection)
        self.completion = nil
    }
    
    private func displayReleaseNotes() {
        // Configure the WebView.
        self.releaseNotesView.preferencesIdentifier = SUBundleIdentifier
        self.releaseNotesView.preferences.arePlugInsEnabled = false
        self.releaseNotesView.preferences.isJavaEnabled = false
        self.releaseNotesView.preferences.isJavaScriptEnabled = self.host.bool(forInfoDictionaryKey: SUEnableJavaScriptKey)
        self.releaseNotesView.frameLoadDelegate = self
        self.releaseNotesView.policyDelegate = self
        
        // Set the default font. `-apple-system` refers to the system UI font.
        self.releaseNotesView.preferences.standardFontFamily = "-apple-system"
        self.releaseNotesView.preferences.defaultFontSize = Int32(NSFont.systemFontSize)
        
        // Adapt our apeparance to that of the release notes.
        self.adaptReleaseNotesAppearance()
        if self.appearanceObservation == nil {
            self.appearanceObservation = self.releaseNotesView.observe(\WebView.effectiveAppearance) { view, change in self.adaptReleaseNotesAppearance() }
        }
        
        // Stick a nice big spinner in the middle of the web view until the page is loaded.
        self.releaseNotesSpinner = .init(frame: .init(
            x: self.releaseNotesView.superview!.frame.midX - 16,
            y: self.releaseNotesView.superview!.frame.midY - 16,
            width: 32, height: 32
        ))
        self.releaseNotesSpinner?.style = .spinning
        self.releaseNotesSpinner?.startAnimation(self)
        self.releaseNotesView.superview?.addSubview(self.releaseNotesSpinner!)
        
        // If there's no release notes URL, just stick the contents of the description into the web view
        // Otherwise we'll wait until the client wants us to show release notes
        self.webViewFinishedLoading = false
        if self.updateItem.releaseNotesURL == nil {
            self.releaseNotesView.mainFrame.loadHTMLString(self.updateItem.itemDescription, baseURL: nil)
        }
    }
    
    private func adaptReleaseNotesAppearance() {
        let bestAppearance = self.releaseNotesView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
    
        if bestAppearance == .darkAqua {
            // Set user stylesheet adapted to light on dark
            self.releaseNotesView.preferences.userStyleSheetEnabled = true
            self.releaseNotesView.preferences.userStyleSheetLocation = Bundle(for: Self.self).url(forResource: "DarkAqua", withExtension: "css")

            // Remove web view background...
            self.releaseNotesView.drawsBackground = false
            // ... and use NSBox to get the dynamically colored background
            if self.darkBackgroundView == nil {
                self.darkBackgroundView = .init(frame: self.releaseNotesView.frame)
                self.darkBackgroundView?.boxType = .custom
                self.darkBackgroundView?.fillColor = .textBackgroundColor
                self.darkBackgroundView?.borderColor = .clear
                // Using auto-resizing mask instead of contraints works well enough
                self.darkBackgroundView?.autoresizingMask = [.width, .height]
                self.releaseNotesView.superview?.addSubview(self.darkBackgroundView!, positioned: .below, relativeTo: self.releaseNotesView)
                // The release note user stylesheet will not adjust to the user changing the theme until adaptReleaseNoteAppearance is called again.
                // So lock the appearance of the background to keep the text readable if the system theme changes.
                self.darkBackgroundView?.appearance = self.darkBackgroundView?.effectiveAppearance
            }
        } else {
            // Restore standard dark on light appearance
            self.darkBackgroundView?.removeFromSuperview()
            self.darkBackgroundView = nil
            self.releaseNotesView.preferences.userStyleSheetEnabled = false
            self.releaseNotesView.drawsBackground = true
        }
    }
    
    /// If a MIME type isn't provided, we will pick `text/html` as the default, as opposed to plain text.
    /// We'll pick `utf-8` as the default text encoding name if one isn't provided which I think is reasonable
    internal func showUpdateReleaseNotes(downloadData: SPUDownloadData) {
        if !self.webViewFinishedLoading {
            let baseUrl = self.updateItem.releaseNotesURL.deletingLastPathComponent()
            let chosenMIMEType = downloadData.mimeType ?? "text/html"
            let chosenTextEncoding = downloadData.textEncodingName ?? "utf-8"
            
            self.releaseNotesView.mainFrame.load(downloadData.data, mimeType: chosenMIMEType, textEncodingName: chosenTextEncoding, baseURL: baseUrl)
        }
    }
    
    internal func showReleaseNotesFailedToDownload() {
        self.stopReleaseNotesSpinner()
        self.webViewFinishedLoading = true
    }
    
    private func stopReleaseNotesSpinner() {
        self.releaseNotesSpinner?.stopAnimation(self)
        self.releaseNotesSpinner?.isHidden = true
    }
    
    private var showsReleaseNotes: Bool {
        if self.host.object(forInfoDictionaryKey: SUShowReleaseNotesKey) != nil {
            return self.host.bool(forInfoDictionaryKey: SUShowReleaseNotesKey)
        } else {
            return (self.updateItem.itemDescription.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? false) ||
                   self.updateItem.releaseNotesURL != nil
        }
    }
    
    // MARK: - Lifecycle
    
    public override func windowDidLoad() {
        self.window!.setFrameAutosaveName(self.showsReleaseNotes ? "SUUpdateAlert" : "SUUpdateAlertSmall")
        
        if SUApplicationInfo.isBackground(application: NSApp) {
            self.window!.level = .floating
        }
        
        if self.updateItem.isInformationOnlyUpdate {
            self.installButton.title = SULocalizedString("Learn More...", "Alternate title for 'Install Update' button when displaying informational update.")
            self.installButton.action = #selector(openInfoURL(_:))
        }
        
        if self.showsReleaseNotes {
            self.displayReleaseNotes()
        } else {
            let constraint = NSLayoutConstraint(item: self.automaticallyInstallUpdatesButton!, attribute: .top, relatedBy: .equal, toItem: self.descriptionField!, attribute: .bottom, multiplier: 1.0, constant: 8.0)
            self.window!.contentView?.addConstraint(constraint)
            self.releaseNotesContainerView.removeFromSuperview()
        }

        // When we show release notes, it looks ugly if the install buttons are not closer to the release notes view
        // However when we don't show release notes, it looks ugly if the install buttons are too close to the description field. Shrugs.
        if self.showsReleaseNotes && !self.allowsAutomaticUpdates {
            let constraint = NSLayoutConstraint(item: self.skipButton!, attribute: .top, relatedBy: .equal, toItem: self.releaseNotesContainerView!, attribute: .bottom, multiplier: 1.0, constant: 12.0)
            self.window!.contentView?.addConstraint(constraint)
            self.automaticallyInstallUpdatesButton.removeFromSuperview()
        }
        
        if case .some(.resumable(_)) = self.completion {
            // Should we hide the button or disable the button if the update has already started installing?
            // Personally I think it looks better when the button is visible on the window...
            // Anyway an already downloaded update can't be skipped
            self.skipButton.isEnabled = false
            
            // We're going to be relaunching pretty instantaneously
            self.installButton.title = SULocalizedString("Install & Relaunch", nil)
            
            // We should be explicit that the update will be installed on quit
            self.laterButton.title = SULocalizedString("Install on Quit", nil)
        }
        
        if self.updateItem.isCriticalUpdate {
            self.skipButton.isEnabled = false
        }
        
        self.window!.center()
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        self.end(with: .installLaterChoice)
        return true
    }
    
    // MARK: - Bindings
    
    var applicationIcon: NSImage? { SUApplicationInfo.bestIcon(forHost: self.host) }
    
    var titleText: String? {
        if self.updateItem.isCriticalUpdate {
            return String.localizedStringWithFormat(SULocalizedString("An important update to %@ is ready to install!", nil), self.host.name)
        } else if self.alreadyDownloaded {
            return String.localizedStringWithFormat(SULocalizedString("A new version of %@ is ready to install!", nil), self.host.name)
        } else {
            return String.localizedStringWithFormat(SULocalizedString("A new version of %@ is available!", nil), self.host.name)
        }
    }
    
    var descriptionText: String? {
        var updateItemVersion = self.updateItem.displayVersionString!
        var hostVersion = self.host.displayVersion
        
        if let versionDisplayer = self.versionDisplayer {
            (updateItemVersion, hostVersion) = versionDisplayer.format(version: updateItemVersion, and: hostVersion)
        } else if updateItemVersion == hostVersion {
            updateItemVersion.append(" (\(self.updateItem.versionString ?? "?"))")
            hostVersion.append(" (\(self.host.version))")
        }

        // We display a different summary depending on if it's an "info-only" item, or a "critical update" item, or if we've
        // already downloaded the update and just need to relaunch.
        if self.updateItem.isInformationOnlyUpdate {
            return String.localizedStringWithFormat(SULocalizedString("%@ %@ is now available--you have %@. Would you like to learn more about this update on the web?", "Description text for SUUpdateAlert when the update informational with no download."), self.host.name, updateItemVersion, hostVersion)
        } else if self.updateItem.isCriticalUpdate && self.alreadyDownloaded {
            return String.localizedStringWithFormat(SULocalizedString("%1$@ %2$@ has been downloaded and is ready to use! This is an important update; would you like to install it and relaunch %1$@ now?", "Description text for SUUpdateAlert when the critical update has already been downloaded and ready to install."), self.host.name, updateItemVersion)
        } else if self.updateItem.isCriticalUpdate {
            return String.localizedStringWithFormat(SULocalizedString("%@ %@ is now available--you have %@. This is an important update; would you like to download it now?", "Description text for SUUpdateAlert when the critical update is downloadable."), self.host.name, updateItemVersion, hostVersion)
        } else if self.alreadyDownloaded {
            return String.localizedStringWithFormat(SULocalizedString("%1$@ %2$@ has been downloaded and is ready to use! Would you like to install it and relaunch %1$@ now?", "Description text for SUUpdateAlert when the update has already been downloaded and ready to install."), self.host.name, updateItemVersion)
        } else {
            return String.localizedStringWithFormat(SULocalizedString("%@ %@ is now available--you have %@. Would you like to download it now?", "Description text for SUUpdateAlert when the update is downloadable."), self.host.name, updateItemVersion, hostVersion)
        }
    }
    
    // MARK: - WebView delegate
    
    func webView(_ sender: WebView!, didFinishLoadFor frame: WebFrame!) {
        if frame.parent == nil {
            self.stopReleaseNotesSpinner()
            self.webViewFinishedLoading = true
            sender.display() // necessary to prevent weird scroll bar artifacting
        }
    }
    
    func webView(_ webView: WebView!, decidePolicyForNavigationAction actionInformation: [AnyHashable : Any]!, request: URLRequest!, frame: WebFrame!, decisionListener listener: WebPolicyDecisionListener!) {
        guard ["http", "https"].contains(request.url?.scheme ?? "") || request.url?.absoluteString == "about:blank" else {
            SULog(.default, "Blocked display of URL \(request.url!) which may be dangerous")
            listener.ignore()
            return
        }
        
        if self.webViewFinishedLoading {
            if let url = request.url {
                NSWorkspace.shared.open(url)
            }
            listener.ignore()
        } else {
            listener.use()
        }
    }
    
    func webView(_ sender: WebView!, contextMenuItemsForElement element: [AnyHashable : Any]!, defaultMenuItems: [Any]!) -> [Any]! {
        return defaultMenuItems!
            .map { $0 as! NSMenuItem }
            .filter { ![
                WebMenuItemTagOpenLinkInNewWindow,
                WebMenuItemTagDownloadLinkToDisk,
                WebMenuItemTagOpenImageInNewWindow,
                WebMenuItemTagDownloadImageToDisk,
                WebMenuItemTagOpenFrameInNewWindow,
                WebMenuItemTagGoBack,
                WebMenuItemTagGoForward,
                WebMenuItemTagStop,
                WebMenuItemTagReload,
            ].contains($0.tag) }
    }
    
    // MARK: - Touch Bar
    
    private static var TouchBarIndentifier: NSTouchBarItem.Identifier { .init("\(SUBundleIdentifier).SUUpdatePermissionPrompt") }

    override func makeTouchBar() -> NSTouchBar? {
        let touchBar = NSTouchBar()
        touchBar.defaultItemIdentifiers = [Self.TouchBarIndentifier]
        touchBar.principalItemIdentifier = Self.TouchBarIndentifier
        touchBar.delegate = self
        return touchBar
    }
    
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
            case Self.TouchBarIndentifier:
                let item = NSCustomTouchBarItem(identifier: identifier)
                item.viewController = SUTouchBarButtonGroup(referencingButtons:[self.installButton, self.laterButton, self.skipButton])
                return item
            default:
                return nil
        }
    }
}

fileprivate extension SPUUpdateAlertChoice {
    
    var toUpdatePendingAction: SPUUserDriverUpdatePendingAction { switch self {
        case .installUpdateChoice: return .install
        case .installLaterChoice: return .remindLater
        case .skipThisVersionChoice: return .skip
        default: fatalError()
    } }
    
    var toUpdateInstallationAction: SPUUserDriverUpdateInstallationAction { switch self {
        case .installUpdateChoice: return .installAndRelaunch
        case .installLaterChoice: return .dismiss
        default: fatalError()
    } }
    
    var toUpdateInformationAction: SPUUserDriverUpdateInformationAction { switch self {
        case .installLaterChoice: return .dismiss
        case .skipThisVersionChoice: return .skip
        default: fatalError()
    } }
    
}

