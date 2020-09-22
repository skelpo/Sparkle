//
//  SPUInstallationType.h
//  Sparkle
//
//  Created by Mayur Pawashe on 7/24/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#ifndef SPUInstallationType_h
#define SPUInstallationType_h

#import <Foundation/Foundation.h>

/// The default installation type for ordinary application updates.
extern NSString * const SPUInstallationTypeApplication;

/// The preferred installation type for package installations.
extern NSString * const SPUInstallationTypeGuidedPackage;

/// The deprecated installation type; use guided package instead.
extern NSString * const SPUInstallationTypeInteractivePackage;

extern NSString * const SPUInstallationTypeDefault;

#define SPUInstallationTypesArray @[SPUInstallationTypeApplication, SPUInstallationTypeGuidedPackage, SPUInstallationTypeInteractivePackage]

#define SPUValidInstallationType(x) ((x != nil) && [SPUInstallationTypesArray containsObject:x])

#endif /* SPUInstallationType_h */
