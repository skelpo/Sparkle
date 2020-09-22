//
//  SPUStandardUserDriver.swift
//  Sparkle
//
//  Created by Gwynne Raskind on 9/16/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

import Foundation

@objc public final class SPUStandardUserDriver: NSObject, SPUUserDriver, SPUStandardUserDriverProtocol {

    // MARK: - Private Properties
    
    private let host: SUHost
    private weak var delegate: SPUStandardUserDriverDelegate?
    private let coreComponent: SPUUserDriverCoreComponent
    private var activeUpdateAlert: SUUpdateAlert?
    private var statusController: SUStatusController?
    private var checkingController: SUStatusController?

    // MARK: - Birth
    
    @objc public init(hostBundle: Bundle, delegate: SPUStandardUserDriverDelegate?) {
        self.host = .init(bundle: hostBundle)
        self.delegate = delegate
        self.coreComponent = .init()
        self.hideOnDeactivate = true
        super.init()
    }
    
    // MARK: - API properties
    
    @objc public var hideOnDeactivate: Bool
    
    // MARK: - SPUStandardUserDriverProtocol
    
    @objc public var canCheckForUpdates: Bool {
        get { DispatchQueue.main.sync { self.coreComponent.canCheckForUpdates } }
        set { DispatchQueue.main.async { self.coreComponent.showCanCheck(forUpdates: newValue) } }
    }
    
    // MARK: - Update Check Capability

    @objc public var userCanInitiateUpdateCheck: Bool {
        get { self.canCheckForUpdates }
        set { self.canCheckForUpdates = newValue }
    }

    // MARK: - Update Permission
    
    @objc public func requestUpdatePermission(with request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        DispatchQueue.main.async { SUUpdatePermissionPrompt.prompt(host: self.host, request: request, reply: reply) }
    }
    
    // MARK: - Update Alert Focus
    
    private func setUpFocusForActiveUpdateAlert() {
        // Make sure the window is loaded in any case
        _ = self.activeUpdateAlert!.window!
        if !self.hideOnDeactivate {
            self.activeUpdateAlert!.window!.hidesOnDeactivate = false
        }
        
        // If the app is a menubar app or the like, we need to focus it first and alter the
        // update prompt to behave like a normal window. Otherwise if the window were hidden
        // there may be no way for the application to be activated to make it visible again.
        if SUApplicationInfo.isBackground(application: NSApp) {
            self.activeUpdateAlert!.window!.hidesOnDeactivate = false
            NSApp.activate(ignoringOtherApps: true)
        }
        
        // Only show the update alert if the app is active; otherwise, we'll wait until it is.
        if NSApp.isActive {
            self.activeUpdateAlert!.window!.makeKeyAndOrderFront(self)
        } else {
            var observer: Any!
            observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: OperationQueue.main, using: { _ in
                self.activeUpdateAlert!.window!.makeKeyAndOrderFront(self)
                NotificationCenter.default.removeObserver(observer!)
            })
        }
    }
    
    // MARK: - Update Found
    
    private func showUpdateFound(alertHandler: @escaping (SPUStandardUserDriver, SUHost, SUVersionDisplay?) -> SUUpdateAlert) {
        DispatchQueue.main.async {
            let versionDisplayer = self.delegate?.standardUserDriverRequestsVersionDisplayer?()
            
            self.activeUpdateAlert = alertHandler(self, self.host, versionDisplayer)
            self.setUpFocusForActiveUpdateAlert()
        }
    }
    
    @objc public func show(update appcastItem: SUAppcastItem, userInitiated: Bool, reply: @escaping (SPUUserDriverUpdatePendingAction) -> Void) {
        // For some reason, specifying the types of the alert handler closure's parameters explicitly prevents the Swift 5.3 compiler in
        // Xcode 12 GM from erroring out on the `[weak driver]` capture with the unhelpful message "Failed to produce diagnostic for expression."
        self.showUpdateFound(alertHandler: { (driver: SPUStandardUserDriver, host: SUHost, versionDisplayer: SUVersionDisplay?) in
            return SUUpdateAlert(appcastItem: appcastItem, alreadyDownloaded: false, host: host, versionDisplayer: versionDisplayer) { [weak driver] choice in
                reply(choice)
                driver?.activeUpdateAlert = nil
            }
        })
    }
    
    @objc public func show(downloadedUpdate appcastItem: SUAppcastItem, userInitiated: Bool, reply: @escaping (SPUUserDriverUpdatePendingAction) -> Void) {
        self.showUpdateFound(alertHandler: { (driver: SPUStandardUserDriver, host: SUHost, versionDisplayer: SUVersionDisplay?) in
            return SUUpdateAlert(appcastItem: appcastItem, alreadyDownloaded: true, host: host, versionDisplayer: versionDisplayer) { [weak driver] choice in
                reply(choice)
                driver?.activeUpdateAlert = nil
            }
        })
    }
    
    @objc public func show(resumableUpdate appcastItem: SUAppcastItem, userInitiated: Bool, reply: @escaping (SPUUserDriverUpdateInstallationAction) -> Void) {
        self.showUpdateFound(alertHandler: { (driver: SPUStandardUserDriver, host: SUHost, versionDisplayer: SUVersionDisplay?) in
            return SUUpdateAlert(appcastItem: appcastItem, host: host, versionDisplayer: versionDisplayer, resumableCompletionBlock: { [weak driver] choice in
                reply(choice)
                driver?.activeUpdateAlert = nil
            })
        })
    }

    @objc public func show(informationalUpdate appcastItem: SUAppcastItem, userInitiated: Bool, reply: @escaping (SPUUserDriverUpdateInformationAction) -> Void) {
        self.showUpdateFound(alertHandler: { (driver: SPUStandardUserDriver, host: SUHost, versionDisplayer: SUVersionDisplay?) in
            return SUUpdateAlert(appcastItem: appcastItem, host: host, versionDisplayer: versionDisplayer, informationalCompletionBlock: { [weak driver] choice in
                reply(choice)
                driver?.activeUpdateAlert = nil
            })
        })
    }
    
    @objc public func show(releaseNotes downloadData: SPUDownloadData) {
        DispatchQueue.main.async {
            self.activeUpdateAlert?.showUpdateReleaseNotes(downloadData: downloadData)
        }
    }
    
    @objc public func showReleaseNotesFailedToDownload(error: Error) {
        DispatchQueue.main.async {
            SULog(.error, "Failed to download release notes due to error: \(error)")
            self.activeUpdateAlert?.showReleaseNotesFailedToDownload()
        }
    }
    
    // MARK: - Install and Relaunch
    
    @objc public func show(readyToInstall reply: @escaping (SPUUserDriverUpdateInstallationAction) -> Void) {
        DispatchQueue.main.async {
            self.statusController?.beginAction(title: SULocalizedString("Ready to Install", nil), maxProgressValue: 1.0, statusText: nil)
            self.statusController?.progressValue = 1.0 // Fill the bar
            self.statusController?.isButtonEnabled = true
            self.statusController?.set(buttonTitle: SULocalizedString("Install and Relaunch"), target: self, action: #selector(self.installAndRestart(_:)), isDefault: true)
            self.statusController?.window?.makeKeyAndOrderFront(self)
            NSApp.requestUserAttention(.informationalRequest)
            self.coreComponent.registerInstallUpdateHandler({ status in switch status {
                case .installAndRelaunchUpdateNow: reply(.installAndRelaunch)
                case .installUpdateNow: reply(.installOnly)
                case .dismissUpdateInstallation: reply(.dismiss)
                default: fatalError()
            } })
        }
    }
    
    @objc private func installAndRestart(_: AnyObject?) {
        self.coreComponent.installUpdate(withChoice: .installAndRelaunchUpdateNow)
    }
    
    // MARK: - Check for Updates
    
    @objc public func showUserInitiatedUpdatedCheck(cancelCallback: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.coreComponent.registerUpdateCheckStatusHandler({ status in switch status {
                case .done: break
                case .canceled: cancelCallback()
                default: fatalError()
            } })
            self.checkingController = .init(host: self.host)
            self.checkingController?.window?.center()
            self.checkingController?.beginAction(title: SULocalizedString("Checking for updates...", nil), maxProgressValue: 0.0, statusText: nil)
            self.checkingController?.set(buttonTitle: SULocalizedString("Cancel", nil), target: self, action: #selector(self.cancelCheckForUpdates(_:)), isDefault: false)
            self.checkingController?.showWindow(self)
            
            // Obtain focus for background applications. Useful if the update check is requested from another app, such as System Preferences.
            if SUApplicationInfo.isBackground(application: NSApp) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    private func closeCheckingWindow() {
        self.checkingController?.window?.close()
        self.checkingController = nil
    }
    
    @objc private func cancelCheckForUpdates(_: AnyObject?) {
        self.coreComponent.cancelUpdateCheckStatus()
        self.closeCheckingWindow()
    }
    
    @objc public func dismissUserInitiatedUpdateCheck() {
        DispatchQueue.main.async {
            self.coreComponent.completeUpdateCheckStatus()
            self.closeCheckingWindow()
        }
    }
    
    // MARK: - Update Errors
    
    @objc public func show(updaterError error: Error, acknowledgement: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.coreComponent.registerAcknowledgement(acknowledgement)
            let alert = NSAlert()
            alert.messageText = SULocalizedString("Update Error!", nil)
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: SULocalizedString("Cancel Update", nil))
            self.showAlert(alert)
            self.coreComponent.acceptAcknowledgement()
        }
    }
    
    @objc public func showUpdateNotFound(acknowledgement: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.coreComponent.registerAcknowledgement(acknowledgement)
            let alert = NSAlert()
            alert.messageText = SULocalizedString("You're up-to-date!", "Status message shown when the user checks for updates but is already current or the feed doesn't contain any updates.")
            alert.informativeText = .localizedStringWithFormat(SULocalizedString("%@ %@ is currently the newest version available.", nil), self.host.name, self.host.displayVersion)
            alert.addButton(withTitle: SULocalizedString("OK", nil))
            self.showAlert(alert)
            self.coreComponent.acceptAcknowledgement()
        }
    }
    
    private func showAlert(_ alert: NSAlert) {
        DispatchQueue.main.async {
            self.delegate?.standardUserDriverWillShowModalAlert?()
            
            // When showing a modal alert we need to ensure that background applications are focused to inform
            // the user, since there is no dock icon to notify them.
            if SUApplicationInfo.isBackground(application: NSApp) {
                NSApp.activate(ignoringOtherApps: true)
            }
            alert.icon = SUApplicationInfo.bestIcon(forHost: self.host)
            alert.runModal()
            
            self.delegate?.standardUserDriverDidShowModalAlert?()
        }
    }
    
    // MARK: - Download & Installl Updates
    
    private func showStatusController() {
        guard self.statusController == nil else { return }
        self.statusController = .init(host: self.host)
        self.statusController?.showWindow(self)
    }
    
    @objc public func showDownloadInitiated(cancelCallback: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.coreComponent.registerDownloadStatusHandler({ status in switch status {
                case .done: break
                case .canceled: cancelCallback()
                default: fatalError()
            } })
            self.showStatusController()
            self.statusController?.beginAction(title: SULocalizedString("Downloading update...", "Take care not to overflow the status window."), maxProgressValue: 0.0, statusText: nil)
            self.statusController?.set(buttonTitle: SULocalizedString("Cancel", nil), target: self, action: #selector(self.cancelDownload(_:)), isDefault: false)
        }
    }
    
    @objc private func cancelDownload(_: AnyObject?) {
        self.coreComponent.cancelDownloadStatus()
    }
    
    @objc public func download(didReceiveExpectedContentLength expectedContentLength: UInt64) {
        DispatchQueue.main.async {
            self.statusController?.maxProgressValue = Double(expectedContentLength)
        }
    }
    
    private let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.zeroPadsFractionDigits = true
        return formatter
    }()

    private func localizedString(from byteCount: Int64) -> String {
        return self.byteCountFormatter.string(fromByteCount: byteCount)
    }
    
    @objc public func download(didReceiveData length: UInt64) {
        DispatchQueue.main.async {
            let newProgressValue = self.statusController!.progressValue + Double(length)
            
            if newProgressValue > self.statusController!.maxProgressValue {
                self.statusController?.maxProgressValue = newProgressValue
            }
            self.statusController?.progressValue = newProgressValue
            if self.statusController!.maxProgressValue > 0.0 {
                self.statusController?.statusText = .localizedStringWithFormat(SULocalizedString("%@ of %@", nil), self.localizedString(from: Int64(self.statusController!.progressValue)), self.localizedString(from: Int64(self.statusController!.maxProgressValue)))
            } else {
                self.statusController?.statusText = .localizedStringWithFormat(SULocalizedString("%@ downloaded", nil), self.localizedString(from: Int64(self.statusController!.progressValue)))
            }
        }
    }
    
    @objc public func downloadDidStartExtractingUpdate() {
        DispatchQueue.main.async {
            self.coreComponent.completeDownloadStatus()
            self.showStatusController()
            self.statusController?.beginAction(title: SULocalizedString("Extracting update...", "Take care not to overflow the status window."), maxProgressValue: 0.0, statusText: nil)
            self.statusController?.set(buttonTitle: SULocalizedString("Cancel", nil), target: nil, action: nil, isDefault: false)
            self.statusController?.isButtonEnabled = false
        }
    }
    
    @objc public func show(extractionProgress progress: Double) {
        DispatchQueue.main.async {
            if self.statusController!.maxProgressValue == 0.0 {
                self.statusController?.maxProgressValue = 1.0
            }
            self.statusController?.progressValue = progress
        }
    }
    
    @objc public func showInstallingUpdate() {
        DispatchQueue.main.async {
            self.statusController?.beginAction(title: SULocalizedString("Installing update...", "Take care not to overflow the status window."), maxProgressValue: 0.0, statusText: nil)
            self.statusController?.isButtonEnabled = false
        }
    }
    
    @objc public func show(updateInstallationDidFinish acknowledgement: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.coreComponent.registerAcknowledgement(acknowledgement)
            self.coreComponent.acceptAcknowledgement()
        }
    }
    
    // MARK: - Aborting Everything
    
    @objc public func showSendingTerminationSignal() {
        DispatchQueue.main.async {
            // The "quit" event can always be canceled or delayed by the application we're updating,
            // so we can't easily predict how long the installation will take or if it won't happen right away.
            // We close our status window because we don't want it persisting for too long and have it obscure other windows.
            self.statusController?.close()
            self.statusController = nil
        }
    }
    
    @objc public func dismissUpdateInstallation() {
        DispatchQueue.main.async {
            // Make sure everything we call here does not dispatch async to main queue; we're already on the main queue
            // (and I've been bitten in the past by this before).
            self.coreComponent.dismissUpdateInstallation()
            self.closeCheckingWindow()
            self.statusController?.close()
            self.statusController = nil
            self.activeUpdateAlert?.close()
            self.activeUpdateAlert = nil
        }
    }
}
