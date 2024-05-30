//
//  ErrorHelper.h
//  Pods
//
//  Created by TacoDev02 on 5/28/24.
//

#ifndef ErrorHelper_h
#define ErrorHelper_h
 
typedef NS_ENUM(NSInteger, BTErrorType) {
    BTErrorTypeATTResponse = 1,
    BTErrorTypeInvalidState = 2,
    BTErrorTypeInvalidArgument = 3,
    BTErrorTypeUnexpected = 4
};
 
typedef NS_ENUM(NSInteger, InvalidStateCode) {
    InvalidStateCodeUnknownBterror = 1,
    InvalidStateCodeNotSupported = 2,
    InvalidStateCodeConnectionAttemptFailed = 3,
    InvalidStateCodePeripheralNotConnected = 4,
    InvalidStateCodePeripheralDisconnected = 5,
    InvalidStateCodePeripheralNotFound = 6,
    InvalidStateCodeResourceNotFound = 7,
    InvalidStateCodeBtDisabled = 8,
    InvalidStateCodeBtUnsupported = 9,
    InvalidStateCodeGuiResourceUnavailable = 10,
    InvalidStateCodeConnectionLimitReached = 11
};
 
@interface ErrorHelper : NSObject
 
+ (NSDictionary *)createATTResponseErrorDictionaryWithStatus:(NSInteger)status;
+ (NSDictionary *)createInvalidStateErrorDictionaryWithStatus:(InvalidStateCode)status;
+ (NSDictionary *)createInvalidArgumentErrorDictionaryWithMessage:(NSString *)message;
+ (NSDictionary *)createUnexpectedErrorDictionaryWithMessage:(NSString *)message;
 
@end

#endif /* ErrorHelper_h */
