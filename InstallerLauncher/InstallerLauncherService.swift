//
//  main.swift
//  SparkleInstallerLauncher
//
//  Created by Gwynne Raskind on 9/18/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

import Foundation

//Service.main()
@main
final class Service: NSObject, NSXPCListenerDelegate {
    static func main() {
        // Set up a listener to handle incoming connections.
        let listener = NSXPCListener.service()
        let delegate = Self.init()
        
        listener.delegate = delegate
        listener.resume() // does not return
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Configure the connection with the exported interface.
        newConnection.exportedInterface = .init(with: SUInstallerLauncherProtocol.self)

        // Create a launcher object for the connection to export. All mssages received on the connection will be sent to
        // this object.
        newConnection.exportedObject = SUInstallerLauncher()

        // Start delivering messages received by the connection.
        newConnection.resume()

        // Return true to signal connection accepted.
        return true
    }
}
