//
//  ErrorHelper.m
//  react-native-ble-manager
//
//  Created by TacoDev02 on 5/28/24.
//

#import <Foundation/Foundation.h>

#import "ErrorHelper.h"
 
@implementation ErrorHelper
 
+ (NSDictionary *)createATTResponseErrorDictionaryWithStatus:(NSInteger)status {
    return @{
        @"type": @(BTErrorTypeATTResponse),
        @"status": @(status)
    };
}
 
+ (NSDictionary *)createInvalidStateErrorDictionaryWithStatus:(InvalidStateCode)status {
    return @{
        @"type": @(BTErrorTypeInvalidState),
        @"status": @(status)
    };
}
 
+ (NSDictionary *)createInvalidArgumentErrorDictionaryWithMessage:(NSString *)message {
    return @{
        @"type": @(BTErrorTypeInvalidArgument),
        @"message": message ?: @""
    };
}
 
+ (NSDictionary *)createUnexpectedErrorDictionaryWithMessage:(NSString *)message {
    return @{
        @"type": @(BTErrorTypeUnexpected),
        @"message": message ?: @""
    };
}
 
@end
