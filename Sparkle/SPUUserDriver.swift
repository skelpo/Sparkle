//
//  SPUUserDriver.swift
//  Sparkle
//
//  Created by Gwynne Raskind on 9/15/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

import Foundation

/// The action to be taken when a new update is found. See
/// `SPUUserDriver.show(update:userInitiated:reply:)` for details.
@objc public enum SPUUserDriverUpdatePendingAction: Int {
    case install = 1
    case remindLater
    case skip
}

/// The action to be taken when a partially-installed update is found and can be resumed,
/// or a new update has been made ready to install. See
/// `SPUUserDriver.show(resumableUpdate:userInitiated:reply:)` and
/// `show(readyToInstall:)` for details.
@objc public enum SPUUserDriverUpdateInstallationAction: Int {
    case installAndRelaunch = 1
    case installOnly
    case dismiss
}

/// The action to be taken when a purely informational update is found. See
/// `SPUUserDriver.show(informationalUpdate:userInitiated:reply:)` for details.
@objc public enum SPUUserDriverUpdateInformationAction: Int {
    case dismiss = 1
    case skip
}

/// The API in Sparkle for controlling the user interaction.
///
/// This protocol is used for implementing a user interface for the Sparkle updater. Sparkle's internal drivers tell
/// an object that implements this protocol what actions to take and show to the user.
///
/// Every method in this protocol is required (i.e, not optional) and has a void return type and can optionally take a single parameter block,
/// which waits for a response back from the user driver. Note that every parameter block, or reply,///must* be responded to eventually - that
/// is, none can be ignored. Furthermore, they can only be replied to///once* - a reply or completion block should be considered invalidated
/// after it's once used. The faster a reply can be made, the more Sparkle may be able to idle, and so the better. Lastly, every method in this
/// protocol can be called from any thread. Thus, an implementor may choose to always dispatch asynchronously to the main thread. However, an
/// implementor should also avoid unnecessary nested asynchronous dispatches.
///
/// An implementor of this protocol should act defensively. For example, it may be possible for an action that says to invalidate or dismiss
/// something to be called multiple times in succession, and the implementor may choose to ignore further requests.
///
/// - Note: Once upon a time, when first developing the user driver API, I had the user driver exist in a separate process from the rest of the
///   framework. If you're familiar with how the higher level XPC APIs work, this explains why some of the decisions above were made (reply block
///   executed on any thread, reply block replied only once, single reply block, void return types, idleness, no optional methods, ...) This is
///   somewhat of an artifact (maybe?) now, but I think most of these set of restrictions still enforces a well designed API.
@objc public protocol SPUUserDriver {

    /// A state flag indicating whether it is currently possible for the user to initiate an update check.
    ///
    /// Normally, a user can always initiate an update check. There are several conditions under which this is not
    /// the case, however. For example:
    ///
    ///   - A user-initiated check is already in progress
    ///   - An automatic check is already in progress
    ///   - An update is already being downloaded or installed
    ///   - The Internet connection is known to be offline
    ///   - The application is in the process of terminating
    ///   - An application-modal alert is active
    ///
    /// This flag corresponds conceptually to the "enabled" state of the standard "Check for Updates..." menu item provided
    /// by many applications. An object conforming to `NSUserInterfaceValidations` could store this value in a property
    /// and return it from `validateUserInterfaceItem(_:)`, for example.
    ///
    /// - Note: At the time of this writing, the getter for this property will never be invoked by Sparkle; it is required by
    ///   the protocol only because it is not possible to define a "write-only" property in either Objective-C or Swift. It is
    ///   nonetheless recommended that implementations provide a thread-safe getter as well as a thread-safe in case it is called
    ///   by other code or Sparkle's implementation changes.
    ///
    /// - Warning: The property setter may be called on any queue.
    @objc var userCanInitiateUpdateCheck: Bool { get set }

    /// Request the user's permission to make automatic update checks.
    ///
    /// This method is invoked when the updater determines that it has not yet requested the user's permission
    /// to make update checks automatically. A sample system profile is provided so that the implementation may
    /// show the user exactly what information (if any) is sent with such checks. The implementation must invoke
    /// the `reply` callback to signal the user's choice.
    ///
    /// - Important: While implementations can respond to a permission request without actually involving the user
    ///   in the decision, doing so is _strongly_ discouraged and can damage user trust in an application.
    ///
    /// - Parameters:
    ///   - request: The update permission request, containing an anonymous system profile.
    ///   - reply: A callback to be invoked upon completion of the request. The `response` parameter shall be an
    ///     `SUUpdatePermissionResponse` describing the behavior chosen by the user.
    ///
    /// - Note: The choice of whether to send a system profile with update requests is independent of the automatic
    ///   updates settings; profiles may be sent by user-initiated update checks as well.
    ///
    /// - Warning: This method may be called on any queue.
    @objc(showUpdatePermissionRequest:reply:)
    func requestUpdatePermission(with request: SPUUpdatePermissionRequest, reply: @escaping (_ response: SUUpdatePermissionResponse) -> Void)

    /// Notify the user that an update check they initiated is now in progress.
    ///
    /// - Note: Sparkle's standard implementation shows an indeterminate progress bar.
    ///
    /// - Parameters:
    ///   - cancelCallback: The implementation make invoke this callback to signal to the updater that the
    ///     user has attempted to cancel the update check. Invoking this callback after
    ///     `dismissUserInitiatedUpdateCheck()` has been called has no effect.
    ///
    /// - Warning: This method may be called on any queue.
    @objc(showUserInitiatedUpdateCheckWithCancelCallback:)
    func showUserInitiatedUpdatedCheck(cancelCallback: @escaping () -> Void)
    
    /// Dismiss any presented UI concerning a user-initiated update check.
    ///
    /// Called when a user-initiated update check has completed, even if an error occurred.
    ///
    /// - Warning: This method may be called on any queue.
    @objc
    func dismissUserInitiatedUpdateCheck()

    /// Notify the user that a new update has been found.
    ///
    /// This applies to any update that has at least one valid downloadable binary which has not yet actually been
    /// downloaded. Most updates will be of this sort.
    ///
    /// - Parameters:
    ///   - appcastItem: An `SUAppcastItem` describing the new update.
    ///   - userInitiated: `true` if the update check which found this update was user-initiated, `false` otherwise.
    ///   - reply:
    ///     * `.install`: Begin downloading and installation of the update immediately.
    ///     * `.remindLater`: Dismiss the update for now, but show it again on the next update check.
    ///     * `.skip`: Mark this update as skipped; it will not be found again except by an explicitly user-initiated
    ///       update check.
    ///
    /// - Warning: This method may be called on any queue.
    @objc(showUpdateFoundWithAppcastItem:userInitiated:reply:)
    func show(update appcastItem: SUAppcastItem, userInitiated: Bool, reply: @escaping (SPUUserDriverUpdatePendingAction) -> Void)

    /// Notify the user that a new update has been found and has already been fully downloaded.
    ///
    /// This method is identical to `show(updateFound:userInitiated:reply:)` with the exception that it signifies
    /// that the update is already fully downloaded.
    ///
    /// - Warning: This method may be called on any queue.
    @objc(showDownloadedUpdateFoundWithAppcastItem:userInitiated:reply:)
    func show(downloadedUpdate appcastItem: SUAppcastItem, userInitiated: Bool, reply: @escaping (SPUUserDriverUpdatePendingAction) -> Void)

    /// Notify the user that a previously partially-installed update has been found and that resuming the installation is possible.
    ///
    /// This applies only to an update that was previously fully downloaded and had been at least partially installed without
    /// completing said installation (most likely due to user interruption). The installation of the update can not be canceled
    /// once it reaches this state, though it can be further delayed.
    ///
    /// - Parameters:
    ///   - appcastItem: An `SUAppcastItem` describing the partially-installed update.
    ///   - userInitiated: `true` if the update check which found this update was user-initiated, `false` otherwise.
    ///   - reply:
    ///     * `.installAndRelaunch`: Complete the installation of the update immediately and relaunch the application.
    ///     * `.installOnly`: Complete the installation of the update immediately, but do not relaunch.
    ///     * `.dismiss`: Do not complete the installation at the present time. Instead, an attempt will be made to finish
    ///       the installation after the application terminates.
    ///
    /// - Note: The application is never relaunched if it was not running before installing the update.
    ///
    /// - Warning: This method may be called on any queue.
    @objc(showResumableUpdateFoundWithAppcastItem:userInitiated:reply:)
    func show(resumableUpdate appcastItem: SUAppcastItem, userInitiated: Bool, reply: @escaping (SPUUserDriverUpdateInstallationAction) -> Void)
    
    /// Notify the user that a new informational update is available.
    ///
    /// An informational update is one which provides a link to detailed information, but has no downloadable binaries.
    /// Informational updates are useful for displaying important notices to users without having to issue a new release
    /// for the purpose, such as showing a warning that an upcoming update must be manually downloaded. Informational
    /// updates are still considered to be separate versions of the application and will reappear later if dismissed
    /// without being skipped.
    ///
    /// - Parameters:
    ///   - appcastItem: An `SUAppcastItem` describing the new update. The `infoURL` property is of particular interest for
    ///     informational updates.
    ///   - userInitiated: `true` if the update check which found this update was user-initiated, `false` otherwise.
    ///   - reply:
    ///     * `.dismiss`: Dismiss the update notice. The update will be found again the next time an update check is run,
    ///       unless superseded by a further update in the interim.
    ///     * `.skip`: Skip this update. The update will not be found again unless either the user explicitly requests an
    ///       update check, or the updater's "skip" state is reset.
    ///
    /// - Note: It is expected that an implementation may take additional actions before invoking the `reply` callback, such
    ///   as navigating to the update's `infoURL` (the behavior of the standard implementation).
    ///
    /// - Warning: This method may be called on any queue.
    @objc(showInformationalUpdateFoundWithAppcastItem:userInitiated:reply:)
    func show(informationalUpdate appcastItem: SUAppcastItem, userInitiated: Bool, reply: @escaping (SPUUserDriverUpdateInformationAction) -> Void)
    
    /// Notify the user that the downloaded release notes for a new update are now available for display.
    ///
    /// This method is only applicable if the release notes for a given update are located at a separate URL
    /// specified by the appcast; release notes embedded directly in the appcast do not trigger a spearate download.
    /// Implementations may check the `releaseNotesURL` property of `SUAppcastItem` to determine whether a separate
    /// download will be attempted.
    ///
    /// - Parameters:
    ///   - downloadData: The data for the release notes that was downloaded from the new update's appcast.
    ///
    /// - Warning: This method may be called on any queue.
    @objc(showUpdateReleaseNotesWithDownloadData:)
    func show(releaseNotes downloadData: SPUDownloadData)

    /// Notify the user that an error occurred trying to download a new update's release notes.
    ///
    /// This method is only applicable if the release notes for a given update are located at a separate URL
    /// specified by the appcast; release notes embedded directly in the appcast do not trigger a spearate download.
    /// Implementations may check the `releaseNotesURL` property of `SUAppcastItem` to determine whether a separate
    /// download will be attempted.
    ///
    /// - Parameters:
    ///   - error: An error explaining why the new update's release notes could not be downloaded.
    ///
    /// - Warning: This method may be called on any queue.
    @objc(showUpdateReleaseNotesFailedToDownloadWithError:)
    func showReleaseNotesFailedToDownload(error: Error)

    /// Notify the user that no new updates were found.
    ///
    /// - Parameters:
    ///   - acknowledgement: Called to acknowledge to the updater that appropriate UI was shown.
    ///
    /// - Warning: This method may be called on any queue.
    @objc(showUpdateNotFoundWithAcknowledgement:)
    func showUpdateNotFound(acknowledgement: @escaping () -> Void)
    
    /// Notify the user that an error has occurred during an update.
    ///
    /// The implementation should present UI to notify the user of the error, with as much detail as is deemed
    /// appropriate (and is available). The `acknowledgement` callback must be invoked once the user has
    /// acknowledged the error message; if the UI is not modal, the callback should be invoked immediately.
    ///
    /// - Note: This method will not be invoked unless at least one other method informing the user of an update
    ///   has already been invoked.
    ///
    /// - Parameters:
    ///   - acknowledgement: Called to acknowledge to the updater that the error was shown.
    ///
    /// - Warning: This method may be called on any queue.
    @objc(showUpdaterError:acknowledgement:)
    func show(updaterError error: Error, acknowledgement: @escaping () -> Void)
    
    /// Notify the user that a new update is downloading.
    ///
    /// - Parameters:
    ///   - cancelCallback: The implementation may invoke this callback to inform the updater that the user
    ///     has requested to stop the download. Has no effect if invoked after the download is complete.
    ///
    /// - Warning: This method may be called on any queue.
    @objc(showDownloadInitiatedWithCancelCallback:)
    func showDownloadInitiated(cancelCallback: @escaping () -> Void)

    /// Notify the user that the total expected size of a downloaded update is available.
    ///
    /// - Parameters:
    ///   - expectedContentLength: The expected content length of the update being downloaded.
    ///
    /// Thanks to the peculiarities of the HTTP protocol, this value should be considered an estimate only; the
    /// actual download may be larger or smaller than indicated. This method may not be invoked at all for any
    /// given download. It can also be invoked more than once for the same download.
    ///
    /// - Warning: This method may be called on any queue.
    @objc(showDownloadDidReceiveExpectedContentLength:)
    func download(didReceiveExpectedContentLength expectedContentLength: UInt64)

    /// Notify the user that some amount of data has been downloaded for an update.
    ///
    /// This may be an appropriate time to advance a visible progress indicator of the download.
    ///
    /// - Parameters:
    ///   - length: The number of additional bytes that have been downloaded.
    ///
    /// - Note: The current download progress can be calculated as `totalLengthReceived / expectedContentLength`.
    ///   If the `show(downloadDidReceiveExpectedContentLength:)` method was not invoked for the current download
    ///   session, the progress should be considered indeterminate. It is also possible for more data to be downloaded
    ///   than was expected, yielding progress greater than 100% - implementations should handle this case gracefully.
    ///
    /// - Warning: This method may be called on any queue.
    @objc(showDownloadDidReceiveDataOfLength:)
    func download(didReceiveData length: UInt64)

    /// Notify the user that an update has finished downloading and that extraction has begun.
    ///
    /// This is an appropriate time to reply to `showDownloadInitiated(completion:)` with `SPUDownloadUpdateDone`,
    /// if this has not already happened.
    ///
    /// - Note: Sparkle's standard implementation shows an indeterminate progress bar.
    ///
    /// - Note: An update may resume at this point after having been previously downloaded, so implementations should be
    ///   prepared for this method to be invoked in the absence of any of the other download callbacks.
    ///
    /// - Warning: This method may be called on any queue.
    @objc(showDownloadDidStartExtractingUpdate)
    func downloadDidStartExtractingUpdate()

    /// Notify the user of the current progress of extracting an update.
    ///
    /// - Parameters:
    ///   - progress: The percentage of completion of the extraction, ranging
    ///     from 0.0 (0%) to 1.0 (100%).
    ///
    /// - Warning: This method may be called on any queue.
    @objc(showExtractionProgress:)
    func show(extractionProgress progress: Double)

    /// Notify the user that an update has been downloaded and extracted, and
    /// is ready to install.
    ///
    /// Let the user know that an update is ready and ask them whether they want to install or not.
    /// The `reply` callback must be invoked before any futher action will be taken.
    ///
    /// - Parameters:
    ///   - reply: One of:
    ///     * `.installAndRelaunch`: Install the update immediately and relaunch the application.
    ///     * `.installOnly`: Install the update immediately, but do not relaunch.
    ///     * `.dismiss`: Dismiss the installation.
    ///
    /// - Note: If the target application has already terminated and the update can be performed silently,
    ///   this method may not be invoked.
    ///
    /// - Note: If the application was not already running, `.installAndRelaunch` will not cause it to launch.
    ///
    /// - Note: The update may still be installed after the application terminates if `.dismiss` is returned,
    ///   but this behavior is not guaranteed.
    ///
    /// - Warning: This method may be called on any queue.
    @objc(showReadyToInstall:)
    func show(readyToInstall reply: @escaping (SPUUserDriverUpdateInstallationAction) -> Void)
    
    /// Notify the user that installation of an update has begin.
    ///
    /// - Note: Sparkle's standard implementation shows an indeterminate progress bar.
    ///
    /// - Warning: This method may be called on any queue.
    @objc
    func showInstallingUpdate()

    /// Invoked when the update driver is about to send a termination signal to the application.
    ///
    /// The application may or may not be reluanched after termination.
    ///
    /// Termination and optional relaunch of the application may take an indeterminate length of time,
    /// including the possibility that the application or user may delay or even cancel termination
    /// after this method has been called.
    ///
    /// It is up to the implementation whether or not to continue showing installation progress; one common
    /// reason to dismiss installation UI at this time is to avoid accidentally obscuring parts of the
    /// application's interface that appear during a termination sequence.
    ///
    /// - Warning: This method may be called on any queue.
    @objc
    func showSendingTerminationSignal()
    
    /// Notify the user that installation of an update is complete.
    ///
    /// This will only be invoked if the updater process is still alive. Because the updater process' lifetime
    /// is often tied to that of the application being updated, this is often not the case.
    ///
    /// - Parameters:
    ///   - acknowledgement: Let the updater know that the user has signaled that it's safe to continue.
    ///
    /// - Warning: This method may be called on any queue.
    @objc(showUpdateInstallationDidFinishWithAcknowledgement:)
    func show(updateInstallationDidFinish acknowledgement: @escaping () -> Void)

    /// Dismiss the current update installation.
    ///
    /// Stop and tear down everything. Dismiss all update windows, alerts, progress, etc. Do not display any
    /// additional message to the user. Basically, stop everything that could have been started. This method
    /// may be invoked when an update is stopped or errors out, or even just on completion.
    ///
    /// - Important: All outstanding reply/completion/acknowledgement blocks pending from other methods must be
    ///   completed upon invocation of this method.
    ///
    /// - Warning: This method may be called on any queue.
    @objc
    func dismissUpdateInstallation()
}
