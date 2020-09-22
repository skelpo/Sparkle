//
//  SUVersionDisplayProtocol.h
//  EyeTV
//
//  Created by Uli Kusterer on 08.12.09.
//  Copyright 2009 Elgato Systems GmbH. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
    Applies special display formatting to version numbers.
*/
@protocol SUVersionDisplay <NSObject>

/*!
    @brief Formats two version strings.

    @details Both versions are provided, allowing meaningful distinguishing information to be displayed while omitting
    unnecessary and/or confusing data.
    
    @note The use of @c NS_SWIFT_NAME is deliberately crafted to have the same effect as would @c NS_REFINED_FOR_SWIFT,
    save that the latter does not work with protocol methods. A protocol extension is provided in Swift which forwards
    a more Swift-native method signature down to this method. Direct use of this method from Swift is discouraged.
*/
- (void)formatVersion:(NSString * _Nonnull __autoreleasing * _Nonnull)inOutVersionA
           andVersion:(NSString * _Nonnull __autoreleasing * _Nonnull)inOutVersionB
  NS_SWIFT_NAME(__formatVersion(_:andVersion:));

@end

NS_ASSUME_NONNULL_END
