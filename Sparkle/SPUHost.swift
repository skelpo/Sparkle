//
//  SPUHost.swift
//  Sparkle
//
//  Created by Gwynne Raskind on 8/26/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

import Foundation

fileprivate extension Bundle {

    var isMainBundle: Bool { self == Self.main }

    func complexObject(forInfoDictionaryKey key: String) -> Any? {
        return (self.isMainBundle ?
            self.object(forInfoDictionaryKey: key) :
            (CFBundleCopyInfoDictionaryInDirectory(self.bundleURL as CFURL).map { $0 as NSDictionary })?[key]
        )
    }
}

@objc public final class SUHost: NSObject {
    
    /// The bundle Sparkle is responsible for updating. Usually the main bundle.
    @objc public let bundle: Bundle
    
    /// The user defaults domain searched by `object(forUsetDefaultsKey:)` and its siblings.
    private let defaultsDomain: String?
    
    /// See `Bundle.isMainBundle`.
    private var isMainBundle: Bool { self.bundle.isMainBundle }
    
    /// A `UserDefaults` instance properly configured to search either the standard suites or `self.defaultsDomain`, as
    /// appropriate. Returns `nil` if the suite specified by `defaultsDomain` can't be accessed.
    private var domainUserDefaults: UserDefaults? {
        switch self.defaultsDomain {
            case .none, Bundle.main.bundleIdentifier: return .standard
            case let suite: return UserDefaults(suiteName: suite)
        }
    }
    
    /// Set up a host object for updating a given `Bundle`.
    @objc public init(bundle: Bundle) {
        self.bundle = bundle
        self.defaultsDomain = (self.bundle.complexObject(forInfoDictionaryKey: SUDefaultsDomainKey) as? String) ?? bundle.bundleIdentifier
        super.init()
        
        if self.bundle.bundleIdentifier == nil {
            print("Error: The bundle being updated at \(self.bundle) has no \(kCFBundleIdentifierKey! as String)! This will cause preference read/write not to work properly.")
        }
    }
    
    /// See `Bundle.bundlePath`.
    @objc public var bundlePath: String { self.bundle.bundlePath }
    
    /// See `Bundle.bundleURL`.
    @objc public var bundleURL: URL { self.bundle.bundleURL }
    
    /// The display name for the hosted bundle, to be used by UI components. The name is localized if possible.
    @objc public var name: String {
        self.nonemptyString(forInfoDictionaryKey: "SUBundleName") ??
        self.nonemptyString(forInfoDictionaryKey: "CFBundleDisplayName") ??
        self.nonemptyString(forInfoDictionaryKey: kCFBundleNameKey! as String) ??
        (try? self.bundleURL.resourceValues(forKeys: [.localizedNameKey]))?.localizedName ??
        ""
    }

    /// The version of the hosted bundle. Returns an empty string if the bundle provides an invalid version (which at
    /// the moment, just means "none at all").
    @objc public lazy var version: String = {
        if let ver = self.nonemptyString(forInfoDictionaryKey: kCFBundleVersionKey! as String) {
            return ver
        } else {
            print("This host (\(self.bundlePath)) has no \(kCFBundleVersionKey!)! This attribute is required.")
            return ""
        }
    }()
    
    /// Whether the hosted bundle specifies a valid version itself. A version is "valid" if it exists.
    @objc public var validVersion: Bool { !self.version.isEmpty }
    
    /// The localized human-readable version of the hosted bundle, suitable for display by UI components.
    @objc public var displayVersion: String { self.nonemptyString(forInfoDictionaryKey: "CFBundleShortVersionString") ?? self.version }
    
    /// An `SUPublicKeys` instance containing the public update signing keys for the hosted bundle.
    /// If the hosted bundle provides a resource filename as a DSA key, that file's contents are loaded.
    @objc public var publicKeys: SUPublicKeys { .init(
        dsa: self.nonemptyString(forInfoDictionaryKey: SUPublicDSAKeyKey) ??
             self.bundle.url(forResource: self.publicDSAKeyFileKey, withExtension: nil).flatMap { try? String(contentsOf: $0, encoding: .ascii) },
        ed: self.nonemptyString(forInfoDictionaryKey: SUPublicEDKeyKey)
    ) }

    /// The DSA key file path, specified as a bundle resource name, provided by the hosted bundle, if any.
    @objc public var publicDSAKeyFileKey: String? { self.nonemptyString(forInfoDictionaryKey: SUPublicDSAKeyFileKey) }
    
    /// `true` if the hosted bundle resides on a filesystem that is mounted read-only.
    @objc public var isRunningOnReadOnlyVolume: Bool { (try? self.bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false }
    
    /// `true` if the process corresponding to hosted bundle is currently being run under App Translocation.
    @objc public var isRunningTranslocated: Bool { self.bundleURL.pathComponents.contains("AppTranslocation") }
    
    /// Returns a value from the hosted bundle's info dictionary. If the hosted bundle is _not_ the main bundle, uses the
    /// slower CoreFoundation-level functions to retrieve the key, ensuring that `Foundation`'s caching does not cause
    /// problems if the hosted bundle changed on disk at some point.
    @objc public func object(forInfoDictionaryKey key: String) -> Any? { self.bundle.complexObject(forInfoDictionaryKey: key) }
    
    /// Convenience for retrieving an info dictionary key as a `Bool`. Returns `false` if the key does not exist.
    @objc public func bool(forInfoDictionaryKey key: String) -> Bool { self.object(forInfoDictionaryKey: key) as? Bool ?? false }
    
    /// Convenience for retrieving an info dictionary key as a `String`. Returns `nil` if the key does not exist.
    @objc public func string(forInfoDictionaryKey key: String) -> String? { self.object(forInfoDictionaryKey: key) as? String }

    /// Same as `string(forInfoDictionaryKey:)`, except also returns `nil` if the key exists but is an empty string.
    @objc public func nonemptyString(forInfoDictionaryKey key: String) -> String? { self.string(forInfoDictionaryKey: key).flatMap { $0.isEmpty ? nil : $0 } }
    
    /// Returns a value from the appropriate user defaults domain for the hosted bundle.
    /// See `UserDefaults.object(forKey:)`.
    @objc public func object(forUserDefaultsKey key: String) -> Any? { self.domainUserDefaults?.object(forKey: key) }
    
    /// See `UserDefaults.bool(forKey:)`.
    @objc public func bool(forUserDefaultsKey key: String) -> Bool { self.domainUserDefaults?.bool(forKey: key) ?? false }

    /// Updates (or removes) a value in the appropriate user defaults domain for the hosted bundle.
    /// See `UserDefaults.set(_:forKey:)`.
    @objc public func setObject(_ value: Any?, forUserDefaultsKey key: String) { self.domainUserDefaults?.set(value, forKey: key) }
    
    /// See `UserDefaults.set(_:forKey:)`.
    @objc public func setBool(_ value: Bool, forUserDefaultsKey key: String) { self.domainUserDefaults?.set(value, forKey: key) }
    
    /// Convenience for using `object(forInfoDictionaryKey:)` as a fallback for `object(forUserDefaultsKey:)`.
    @objc public func object(forKey key: String) -> Any? { self.object(forUserDefaultsKey: key) ?? self.object(forInfoDictionaryKey: key) }

    /// Convenience for using `bool(forInfoDictionaryKey:)` as a fallback for `bool(forUserDefaultsKey:)`.
    @objc public func bool(forKey key: String) -> Bool { self.object(forKey: key).flatMap { $0 as? Bool }  ?? false }
}
