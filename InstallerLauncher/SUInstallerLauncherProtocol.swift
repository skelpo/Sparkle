//
//  SUInstallerLauncherProtocol.swift
//  SparkleInstallerLauncher
//
//  Created by Gwynne Raskind on 9/18/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

import Foundation

@objc public protocol SUInstallerLauncherProtocol: NSObjectProtocol {

    @objc(launchInstallerWithHostBundlePath:authorizationPrompt:installationType:allowingDriverInteraction:allowingUpdaterInteraction:completion:)
    func launchInstaller(hostBundlePath: String, authorizationPrompt: String, installationType: String, allowingDriverInteraction: Bool, allowingUpdaterInteraction: Bool, completion: @escaping (SUInstallerLauncherStatus) -> Void)
    
    @objc(checkIfApplicationInstallationRequiresAuthorizationWithHostBundlePath:reply:)
    func checkIfApplicationInstallationRequiresAuthorization(hostBundlePath: String, reply: @escaping (Bool) -> Void)
}
