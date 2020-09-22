//
//  SPUSecureCoding.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/24/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUSecureCoding.h"
#import "SULog.h"


#include "AppKitPrevention.h"

static NSString *SURootObjectArchiveKey = @"SURootObjectArchive";

NSData * _Nullable SPUArchiveRootObjectSecurely(id<NSSecureCoding> rootObject)
{
    NSKeyedArchiver *keyedArchiver = [[NSKeyedArchiver alloc] initRequiringSecureCoding:YES];
    
    @try {
        [keyedArchiver encodeObject:rootObject forKey:SURootObjectArchiveKey];
        return [keyedArchiver.encodedData copy];
    } @catch (NSException *exception) {
        SULog(SULogLevelError, @"Exception while securely archiving object: %@", exception);
        [keyedArchiver finishEncoding];
        return nil;
    }
}

id<NSSecureCoding> _Nullable SPUUnarchiveRootObjectSecurely(NSData *data, Class klass)
{
    NSError *error = nil;
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:&error];
    id<NSSecureCoding> rootObject = nil;
    
    if (unarchiver) {
        rootObject = [unarchiver decodeTopLevelObjectOfClass:klass forKey:SURootObjectArchiveKey error:&error];
        [unarchiver finishDecoding];
    }
    
    if (!unarchiver || !rootObject) {
        SULog(SULogLevelError, @"Error while securely unarchiving object: %@", error);
        return nil;
    }
    
    return rootObject;
}
