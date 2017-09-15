//
//  LMLogger.m
//  LMLogger
//
//  Created by xingpeng on 09/07/2016.
//  Copyright (c) 2016 lemon. All rights reserved.
//

#if ! __has_feature(objc_arc)
#error This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

#import "LMLogger.h"
#import <mars/xlog/xlogger.h>
#import <mars/xlog/appender.h>
#import <sys/xattr.h>
#import <libkern/OSAtomic.h>

static NSDateComponents* _currentDateComponents;

@implementation LogConfig
- (id)init
{
    if (self = [super init])
    {
        NSString* logPath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingString:@"/xlog"];
        _dir = logPath;
#if DEBUG
        _logLevel = LogLevelDebug;
        _consoleOutput = YES;
#else
        _logLevel = LogLevelInfo;
        _consoleOutput = NO;
#endif
    }
    return self;
}

@end

@interface LMLogger ()
{
    NSString *_tag;
}

@end

@implementation LMLogger

static LogConfig *logConfig = nil;
static OSSpinLock loggerLock = OS_SPINLOCK_INIT;
static bool loggerOpen = false;

+ (void)openLogger:(LogConfig *)cfg {
    OSSpinLockLock(&loggerLock);
    NSAssert(logConfig==NULL, @"log is already open,please close logger before it");
    [self config:cfg];
    loggerOpen = true;
    xlogger2(toTLogLevel(LogLevelDebug), "logger", __XFILE__, __XFUNCTION__, __LINE__, "log path=%s",[logConfig.dir UTF8String]);
    OSSpinLockUnlock(&loggerLock);
}

+ (void)closeLogger {
    OSSpinLockLock(&loggerLock);
    logConfig = NULL;
    appender_close();
    loggerOpen = false;
    OSSpinLockUnlock(&loggerLock);
}

+ (void)config:(LogConfig *)cfg
{
    if (cfg == NULL) {
        logConfig = [LogConfig new];
    }
    else {
        logConfig = cfg;
    }
    const char* attrName = "com.apple.MobileBackup";
    u_int8_t attrValue = 1;
    // set do not backup for logpath
    setxattr([logConfig.dir UTF8String], attrName, &attrValue, sizeof(attrValue), 0, 0);
    xlogger_SetLevel(toTLogLevel(logConfig.logLevel));
    appender_set_console_log(logConfig.consoleOutput);
    appender_open(kAppednerAsync, [logConfig.dir UTF8String], "LMLogger", "");
}

+ (LogConfig*)getConfig
{
    return logConfig;
}

+ (LMLogger *)getLMLogger:(NSString *)tag
{
    static NSMutableDictionary *loggers = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        loggers = [[NSMutableDictionary alloc] init];
    });
    
    if (tag.length == 0) {
        tag = @"Default";
    }
    
    LMLogger *logger = nil;
    @synchronized(loggers) {
        logger = [loggers objectForKey:tag];
        if (logger == nil) {
            logger = [[LMLogger alloc] initWithTag:tag];
            [loggers setObject:logger forKey:tag];
        }
    }
    
    return logger;
}

static NSString *logLevelToString(LogLevel level)
{
    NSString *str;
    switch (level) {
        case LogLevelVerbose: {
            str = @"Verbose";
            break;
        }
        case LogLevelDebug: {
            str = @"Debug";
            break;
        }
        case LogLevelInfo: {
            str = @"Info";
            break;
        }
        case LogLevelWarn: {
            str = @"Warn";
            break;
        }
        case LogLevelError: {
            str = @"Error";
            break;
        }
        default: {
            str = @"Unknown";
            break;
        }
    }
    return str;
}

static NSString *formatLogStr(NSString *tag, LogLevel level, NSString *format, va_list args)
{
    NSString *input = [[NSString alloc] initWithFormat:format arguments:args];
    NSString *thread;
    if ([[NSThread currentThread] isMainThread]) {
        thread = @"Main";
    } else {
        thread = [NSString stringWithFormat:@"%p", [NSThread currentThread]];
    }
    
    NSString *logString = [NSString stringWithFormat:@"[%@][%@][%@] %@", thread, tag, logLevelToString(level), input];
    return logString;
}

static TLogLevel toTLogLevel(LogLevel level) {
    TLogLevel tlog = kLevelNone;
    switch (level) {
        case LogLevelVerbose:
            tlog = kLevelVerbose;
            break;
        case LogLevelDebug:
            tlog = kLevelDebug;
            break;
        case LogLevelInfo:
            tlog = kLevelInfo;
            break;
        case LogLevelWarn:
            tlog = kLevelWarn;
            break;
        case LogLevelError:
            tlog = kLevelError;
            break;
        default:
            break;
    }
    return tlog;
}

static void logInternal(NSString *tag, LogLevel level, NSString *format, va_list args)
{
    if (false == loggerOpen) {
        //log 还没打开，
        return;
    }
    NSString *logString = formatLogStr(tag, level, format, args);
    xlogger2(toTLogLevel(level), [tag UTF8String], __XFILE__, __XFUNCTION__, __LINE__, [logString UTF8String]);
}

+ (void)log:(NSString *)tag level:(LogLevel)level message:(NSString *)format, ...NS_FORMAT_FUNCTION(3, 4)
{
    va_list args;
    va_start(args, format);
    logInternal(tag, level, format, args);
    va_end(args);
}

+ (void)verbose:(NSString *)tag message:(NSString *)format, ...NS_FORMAT_FUNCTION(2, 3)
{
    va_list args;
    va_start(args, format);
    logInternal(tag, LogLevelVerbose, format, args);
    va_end(args);
}

+ (void)debug:(NSString *)tag message:(NSString *)format, ...NS_FORMAT_FUNCTION(2, 3)
{
    va_list args;
    va_start(args, format);
    logInternal(tag, LogLevelDebug, format, args);
    va_end(args);
}

+ (void)info:(NSString *)tag message:(NSString *)format, ...NS_FORMAT_FUNCTION(2, 3)
{
    va_list args;
    va_start(args, format);
    logInternal(tag, LogLevelInfo, format, args);
    va_end(args);
}

+ (void)warn:(NSString *)tag message:(NSString *)format, ...NS_FORMAT_FUNCTION(2, 3)
{
    va_list args;
    va_start(args, format);
    logInternal(tag, LogLevelWarn, format, args);
    va_end(args);
}

+ (void)error:(NSString *)tag message:(NSString *)format, ...NS_FORMAT_FUNCTION(2, 3)
{
    va_list args;
    va_start(args, format);
    logInternal(tag, LogLevelError, format, args);
    va_end(args);
}

- (void)log:(LogLevel)level message:(NSString *)format, ...NS_FORMAT_FUNCTION(2, 3)
{
    va_list args;
    va_start(args, format);
    logInternal(_tag, level, format, args);
    va_end(args);
}

- (void)verbose:(NSString *)format, ...NS_FORMAT_FUNCTION(1, 2)
{
    va_list args;
    va_start(args, format);
    logInternal(_tag, LogLevelVerbose, format, args);
    va_end(args);
}

- (void)debug:(NSString *)format, ...NS_FORMAT_FUNCTION(1, 2)
{
    va_list args;
    va_start(args, format);
    logInternal(_tag, LogLevelDebug, format, args);
    va_end(args);
}

- (void)info:(NSString *)format, ...NS_FORMAT_FUNCTION(1, 2)
{
    va_list args;
    va_start(args, format);
    logInternal(_tag, LogLevelInfo, format, args);
    va_end(args);
}

- (void)warn:(NSString *)format, ...NS_FORMAT_FUNCTION(1, 2)
{
    va_list args;
    va_start(args, format);
    logInternal(_tag, LogLevelWarn, format, args);
    va_end(args);
}

- (void)error:(NSString *)format, ...NS_FORMAT_FUNCTION(1, 2)
{
    va_list args;
    va_start(args, format);
    logInternal(_tag, LogLevelError, format, args);
    va_end(args);
}

- (id)initWithTag:(NSString *)tag
{
    if (self = [super init])
    {
        _tag = tag;
    }
    return self;
}

@end
