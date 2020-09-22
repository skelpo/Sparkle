//
//  SUInstallerLauncher.swift
//  SparkleInstallerLauncher
//
//  Created by Gwynne Raskind on 9/18/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

import Foundation
import ServiceManagement

final class SUInstallerLauncher: NSObject, SUInstallerLauncherProtocol {
    
    private func submitProgressTool(at path: String, hostBundle: Bundle, inSystemDomainForInstaller: Bool) -> Bool {
        let progressToolUrl = URL(fileURLWithPath: path, isDirectory: false)
        
        do {
            try SUFileManager().releaseItemFromQuarantine(atRootURL: progressToolUrl)
        } catch {
            SULog(.error, "Failed to release quarantine on installer at \(path) with error \(error)")
        }
        
        let executablePath = Bundle(url: progressToolUrl)!.executablePath!
        let hostBundlePath = hostBundle.bundlePath
        let hostBundleIdentifier = hostBundle.bundleIdentifier!
        let arguments = [executablePath, hostBundlePath, "\(inSystemDomainForInstaller)"]
        let label = "\(hostBundleIdentifier)-sparkle-progress"

        var auth: AuthorizationRef?
        let createStatus = AuthorizationCreate(nil, nil, [], &auth)
        guard createStatus == errAuthorizationSuccess else {
            return false
        }
        defer { _ = auth.map { AuthorizationFree($0, []) } }
        
        var rawRemoveError: Unmanaged<CFError>?
        if !SMJobRemove(kSMDomainUserLaunchd, label as CFString, auth, true, &rawRemoveError),
           let removeError = rawRemoveError?.takeRetainedValue(),
           CFErrorGetCode(removeError) != kSMErrorJobNotFound
        {
            SULog(.error, "Remove error: \(removeError)")
        }
        
        let jobDictionary: [String: Any] = [
            "Label": label,
            "ProgramArguments": arguments,
            "EnableTransactions": false,
            "KeepAlive": ["SuccessfulExit": false],
            "RunAtLoad": false,
            "NICE": 0,
            "LaunchOnlyOnce": true,
            "MachServices": [SPUStatusInfoServiceNameForBundleIdentifier(hostBundleIdentifier): true],
        ]
        
        var rawSubmitError: Unmanaged<CFError>?
        if !SMJobSubmit(kSMDomainUserLaunchd, jobDictionary as CFDictionary, auth, &rawSubmitError) {
            SULog(.error, "Submit progress error: \(rawSubmitError!.takeRetainedValue())")
            return false
        }
        return true
    }
    
    /// Use `/tmp` rather than `NSTemporaryDirectory()` or `SUFileManager` because the file must reside in a system-
    /// readable location and `/tmp` is one of the few such areas remaining.
    ///
    /// See https://github.com/sparkle-project/Sparkle/issues/347#issuecomment-149523848
    private func writeTemporaryIconFile(for bundle: Bundle, withPathTemplate template: String = "/tmp/XXXXXX.png") -> URL? {
        // Find a 32x32 image representation of the icon and write out a PNG version of it to a temporary location.
        // Then use it (if it was available) for the authorization prompt. `NSImage` is avoided because it needs `AppKit`.
        // If we don't find a 32x32 representation, then we don't provide an icon. Don't try to make
        // for it by (for example) scaling some other representation. The app developer should be
        // providing the icon at scale, and the authorization API will not accept other sizes.
        guard let iconUrl = SUBundleIcon.iconURL(forHost: .init(bundle: bundle)),
              let imageSource = CGImageSourceCreateWithURL(iconUrl as CFURL, [:] as CFDictionary),
              let firstSizedImageIndex = (0 ..< CGImageSourceGetCount(imageSource)).first(where: { imageIndex in
                  guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, imageIndex, [:] as CFDictionary) as NSDictionary?,
                        let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
                        let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int,
                        pixelWidth == 32, pixelHeight == 32
                  else {
                      return false
                  }
                  return true
              })
        else {
            return nil
        }
        
        var path = Array(template.utf8)
        let tempIconFile = path.withUnsafeMutableBufferPointer({ $0.withMemoryRebound(to: Int8.self) { mkstemps($0.baseAddress!, Int32(strlen(".png"))) } })
        guard tempIconFile != -1 else {
            SULog(.error, "Failed to open temp icon from path buffer with error: \(errno)")
            return nil
        }
        close(tempIconFile)
        
        let tempIconFileUrl = URL(fileURLWithPath: String(decoding: path, as: UTF8.self), isDirectory: false)
        
        guard let imageDestination = CGImageDestinationCreateWithURL(tempIconFileUrl as CFURL, kUTTypePNG, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImageFromSource(imageDestination, imageSource, firstSizedImageIndex, nil)
        guard CGImageDestinationFinalize(imageDestination) else {
            return nil
        }
        
        return tempIconFileUrl
    }
    
    func submitInstaller(at path: String, hostBundle: Bundle, authPrompt: String, inSystemDomain: Bool) -> SUInstallerLauncherStatus {
        // No need to release the quarantine for this utility
        // In fact, we shouldn't because the tool may be located at a path we should not be writing too.
        let hostBundleIdentifier = hostBundle.bundleIdentifier!
        
        // The first argument has to be the path to the program, and the second is a host identifier so that the
        // installer knows what mach services to host. We intentionally do not pass any more arguments. Anything else
        // should be done via IPC. This is compatible with `SMJobBless()`, which does not allow arguments. Though we
        // aren't using that API at this time, it'd be wise to avoid purposely reducing our compatibility with it.
        let arguments = [path, hostBundleIdentifier]
        
        var _auth: AuthorizationRef?
        var failedToUseSystemDomain = false, canceledAuthorization = false
        let createStatus = AuthorizationCreate(nil, nil, [], &_auth)
        if createStatus != errAuthorizationSuccess {
            SULog(.error, "Failed to create authorization reference: \(createStatus)")
        }
        
        guard let auth = _auth else { return .failure }
        defer { AuthorizationFree(auth, []) }
        
        if inSystemDomain {
            func proceed(rights: AuthorizationRights, environment: AuthorizationEnvironment) {
                var rgt = rights, env = environment
                let copyStatus = AuthorizationCopyRights(auth, &rgt, &env, [.extendRights, .interactionAllowed], nil)
                failedToUseSystemDomain = (copyStatus != errAuthorizationSuccess)
                canceledAuthorization = failedToUseSystemDomain && copyStatus == errAuthorizationCanceled
                if failedToUseSystemDomain && !canceledAuthorization {
                    SULog(.error, "Failed copying system domain rights: \(copyStatus)")
                }
            }
            // See Apple's 'EvenBetterAuthorizationSample' sample code and
            // https://developer.apple.com/library/mac/technotes/tn2095/_index.html#//apple_ref/doc/uid/DTS10003110-CH1-SECTION7
            // We can set a custom right name for authenticating as an administrator.
            // For now, we're using this; we should switch to something like `kSMRightModifySystemDaemons`, but this
            // allows us to present a better-worded prompt.
            let rightName = "\(hostBundleIdentifier)-sparkle-auth"
            if AuthorizationRightGet(rightName, nil) == errAuthorizationDenied,
               AuthorizationRightSet(auth, rightName, kAuthorizationRuleAuthenticateAsAdmin as CFString, authPrompt as CFString, nil, nil) != errAuthorizationSuccess {
                SULog(.error, "Failed to make auth right set")
            }
                        
            rightName.withCString { rightName in
                var right = AuthorizationItem(name: rightName, valueLength: 0, value: nil, flags: 0)
                withUnsafeMutablePointer(to: &right) { rightsBuffer in
                    let rights = AuthorizationRights(count: 1, items: rightsBuffer)
                    
                    if let authIconPath = self.writeTemporaryIconFile(for: hostBundle).map({ Array($0.path.utf8) }) {
                        authIconPath.withUnsafeBufferPointer { buf in kAuthorizationEnvironmentIcon.withCString { iconEnvStr in
                            var iconAuthItem = AuthorizationItem(name: iconEnvStr, valueLength: buf.count, value: .init(mutating: buf.baseAddress!), flags: 0)
                            withUnsafeMutablePointer(to: &iconAuthItem) { proceed(rights: rights, environment: .init(count: 1, items: $0)) }
                        } }
                        try? FileManager.default.removeItem(atPath: .init(decoding: authIconPath, as: UTF8.self))
                    } else {
                        proceed(rights: rights, environment: .init(count: 0, items: nil))
                    }
                }
            }
        }
        
        if !canceledAuthorization && !failedToUseSystemDomain {
            let label = "\(hostBundleIdentifier)-sparkle-updater"
            let domain = inSystemDomain ? kSMDomainSystemLaunchd : kSMDomainUserLaunchd
            var removeError: Unmanaged<CFError>?
            if !SMJobRemove(domain, label as CFString, auth, true, &removeError), let removeError = removeError?.takeRetainedValue(),
               CFErrorGetCode(removeError) != kSMErrorJobNotFound
            {
                SULog(.error, "Remove job error: \(removeError)")
            }
            
            let jobDictionary: [String: Any] = [
                "Label": label,
                "ProgramArguments": arguments,
                "EnableTransactions": false,
                "KeepAlive": ["SuccessfulExit": false],
                "RunAtLoad": false,
                "NICE": 0,
                "LaunchOnlyOnce": true,
                "MachServices": [
                    SPUStatusInfoServiceNameForBundleIdentifier(hostBundleIdentifier): true,
                    SPUProgressAgentServiceNameForBundleIdentifier(hostBundleIdentifier): true,
                ],
            ]

            var rawSubmitError: Unmanaged<CFError>?
            if SMJobSubmit(domain, jobDictionary as CFDictionary, auth, &rawSubmitError) {
                return .success
            } else if let submitError = rawSubmitError?.takeRetainedValue() {
                SULog(.error, "Submit progress error: \(submitError)")
            }
        }
        
        return canceledAuthorization ? .canceled : .failure
    }
    
    private func url(forBundledTool tool: String, extension ext: String, in bundle: Bundle) -> URL? {
        return (
            bundle.url(forAuxiliaryExecutable: URL(fileURLWithPath: tool, isDirectory: false).appendingPathExtension(ext).lastPathComponent) ??
            bundle.url(forResource: tool, withExtension: ext)
        )
    }
    
    /// - Note: do not pass untrusted information such as paths to the installer and progress agent tools, when we can find them ourselves here
    func launchInstaller(
        hostBundlePath: String,
        authorizationPrompt: String,
        installationType: String,
        allowingDriverInteraction: Bool,
        allowingUpdaterInteraction: Bool,
        completion: @escaping (SUInstallerLauncherStatus) -> Void
    ) {
        DispatchQueue.main.async {
            // We may be inside the InstallerLauncher XPC bundle or in the Sparkle.framework bundle if no XPC service is used.
            let ourBundle = Bundle(for: Self.self)
            let hostBundle = Bundle(path: hostBundlePath)!
            let needsSystemAuth = SPUNeedsSystemAuthorizationAccess(hostBundlePath, installationType)
            
            if !allowingUpdaterInteraction && (needsSystemAuth || installationType == SPUInstallationTypeInteractivePackage) {
                SULog(.error, "Updater is not allowing user interaction in the launcher.")
                return completion(.failure)
            }
            if needsSystemAuth && !allowingDriverInteraction {
                return completion(.authorizeLater)
            }
            
            // Note we do not have to copy this tool out of the bundle it's in because it's a utility with no dependencies.
            // Furthermore, we can keep the tool at a place that may not necessarily be writable.
            // We do, however, have to copy the progress tool app somewhere safe, due to its external depedencies.
            guard let installerUrl = self.url(forBundledTool: "Autoupdate", extension: "", in: ourBundle),
                  let progressToolResourceUrl = self.url(forBundledTool: "Updater", extension: "", in: ourBundle)
            else {
                SULog(.error, "Error: Can not submit installer or progress tool because they could not be located.")
                return completion(.failure)
            }
            
            // It is tempting to take this opportunity to validate the signatures of the installer and progress tool,
            // but it turns out that this isn't very reliable. The signature of the host bundle may not be the same as
            // that of the framework or XPC services (such as in sparkle-cli). For now we just allow the signing
            // requirements for embedded resources to provide a reasonable level of safey.
            let rootCacheUrl = URL(fileURLWithPath: SPULocalCacheDirectory.cachePath(forBundleIdentifier: hostBundle.bundleIdentifier!), isDirectory: true)
                .appendingPathComponent("Launcher", isDirectory: true)
            
            SPULocalCacheDirectory.removeOldItems(inDirectory: rootCacheUrl.path)
            guard let progressToolUrl = SPULocalCacheDirectory
                .createUniqueDirectory(inDirectory: rootCacheUrl.path)
                .map({ URL(fileURLWithPath: $0, isDirectory: true) })?
                .appendingPathComponent("Updater", isDirectory: false)
                .appendingPathExtension("app")
            else {
                SULog(.error, "Failed to create cache directory for progress tool in \(rootCacheUrl)")
                return completion(.failure)
            }
            do { try SUFileManager().copyItem(at: progressToolResourceUrl, to: progressToolUrl) }
            catch {
                SULog(.error, "Failed to copy progress tool to cache: \(error)")
                return completion(.failure)
            }
            
            switch self.submitInstaller(at: installerUrl.path, hostBundle: hostBundle, authPrompt: authorizationPrompt, inSystemDomain: needsSystemAuth) {
                case .success: break
                case .canceled: return completion(.canceled)
                case .authorizeLater: fatalError()
                case .failure:
                    SULog(.error, "Failed to submit installer job")
                    return completion(.failure)
            }
            guard self.submitProgressTool(at: installerUrl.path, hostBundle: hostBundle, inSystemDomainForInstaller: needsSystemAuth) else {
                SULog(.error, "Failed to submit progress tool job")
                return completion(.failure)
            }
            return completion(.success)
        }
    }
    
    func checkIfApplicationInstallationRequiresAuthorization(hostBundlePath: String, reply: @escaping (Bool) -> Void) {
        reply(SPUNeedsSystemAuthorizationAccess(hostBundlePath, SPUInstallationTypeApplication))
    }
}
