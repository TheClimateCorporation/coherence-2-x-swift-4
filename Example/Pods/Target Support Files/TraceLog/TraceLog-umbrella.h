#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "TLConsoleWriter.h"
#import "TLLogger.h"
#import "TLLogLevel.h"
#import "TLWriter.h"
#import "TraceLog-Bridging-Header.h"
#import "TraceLog.h"

FOUNDATION_EXPORT double TraceLogVersionNumber;
FOUNDATION_EXPORT const unsigned char TraceLogVersionString[];

