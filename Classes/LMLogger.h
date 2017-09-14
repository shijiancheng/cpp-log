//
//  Logger.h
//  LMLogger
//
//  Created by xingpeng on 09/07/2016.
//  Copyright (c) 2016 lemon. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum : NSUInteger
{
    LogLevelVerbose,
    LogLevelDebug,
    LogLevelInfoDev,
    LogLevelInfo,
    LogLevelWarn,
    LogLevelError
} LogLevel;

typedef enum : NSUInteger {
    LogFilePolicyNoLogFile,
    LogFilePolicyPerDay,
    LogFilePolicyPerLaunch,
} LogFilePolicy;

@interface LogConfig : NSObject

@property (nonatomic, strong) NSString *dir;                       // log文件目录
@property (nonatomic, assign) LogFilePolicy policy;                // log文件策略
@property (nonatomic, assign) LogLevel outputLevel;                // 输出级别，大于等于此级别的log才会输出
@property (nonatomic, assign) LogLevel fileLevel;                  // 输出到文件的级别，大于等于此级别的log才会写入文件
@property (nonatomic, assign) BOOL consoleOutput;                  // 是否输出到控制台,@default = YES

@end

@interface LMLogger : NSObject

+ (void)enableCrashLog;

+ (void)config:(LogConfig *)cfg;

+ (LogConfig *)getConfig;

+ (LMLogger *)getLMLogger:(NSString *)tag;

+ (NSString *)logFilePath;

+ (NSArray *)sortedLogFileArray;

+ (NSString *)logFileDir;

+ (void)log:(NSString *)tag level:(LogLevel)level message:(NSString *)format, ...NS_FORMAT_FUNCTION(3, 4);

+ (void)verbose:(NSString *)tag message:(NSString *)format, ...NS_FORMAT_FUNCTION(2, 3);

+ (void)debug:(NSString *)tag message:(NSString *)format, ...NS_FORMAT_FUNCTION(2, 3);

+ (void)info:(NSString *)tag message:(NSString *)format, ...NS_FORMAT_FUNCTION(2, 3);

+ (void)warn:(NSString *)tag message:(NSString *)format, ...NS_FORMAT_FUNCTION(2, 3);

+ (void)error:(NSString *)tag message:(NSString *)format, ...NS_FORMAT_FUNCTION(2, 3);

+ (void)cleanLogFiles;

- (void)log:(LogLevel)level message:(NSString *)format, ...NS_FORMAT_FUNCTION(2, 3);

- (void)verbose:(NSString *)format, ...NS_FORMAT_FUNCTION(1, 2);

- (void)debug:(NSString *)format, ...NS_FORMAT_FUNCTION(1, 2);

- (void)info:(NSString *)format, ...NS_FORMAT_FUNCTION(1, 2);

- (void)warn:(NSString *)format, ...NS_FORMAT_FUNCTION(1, 2);

- (void)error:(NSString *)format, ...NS_FORMAT_FUNCTION(1, 2);

@end

@interface LMLogger (fileUpload)

+ (NSArray*)filePathsFromBeginDate:(NSDate*)begin endDate:(NSDate*)date fromDir:(NSString *)dirPath;

+ (BOOL)perLaunchLogsWriteToPerDayLogWithFilepaths:(NSArray *)filePaths toDir:(NSString *)destinationDirPath;

@end

#define SPACE
#define doLog(name, format, arg...)\
{\
NSString* newFormat = [NSString stringWithFormat:@"[func:%s,line:%d]:%@%@", __func__, __LINE__, @"%@", format];\
newFormat = [NSString stringWithFormat:newFormat, @"", ##arg];\
_log_##name(newFormat);\
}

#define logVerbose(format, arg...) doLog( verbose, format, ##arg)
NS_INLINE void _log_verbose(NSString* log)
{
    [LMLogger verbose:@"" message:@"%@", log];
}

#define logDebug(format, arg...) doLog(debug, format, ##arg)
NS_INLINE void _log_debug(NSString* log)
{
    [LMLogger debug:@"" message:@"%@", log];
}

#define logInfo(format, arg...) doLog(info, format, ##arg)
NS_INLINE void _log_info(NSString* log)
{
    [LMLogger info:@"" message:@"%@", log];
}

#define logWarning(format, arg...) doLog(warn, format, ##arg)
NS_INLINE void _log_warn(NSString* log)
{
    [LMLogger warn:@"" message:@"%@", log];
}

#define logError(format, arg...) doLog(error, format, ##arg)
NS_INLINE void _log_error(NSString* log)
{
    [LMLogger error:@"" message:@"%@", log];
}

//非类形式的另一个打Log函数，为方便使用
#define LogVerbose(tag, format, arg...)  [LMLogger verbose:tag message:format, ##arg]
#define LogDebug(tag, format, arg...)  [LMLogger debug:tag message:format, ##arg]
#define LogInfoDev(tag, format, arg...)  [LMLogger info:tag message:format, ##arg]
#define LogInfo(tag, format, arg...)  [LMLogger info:tag message:format, ##arg]
#define LogWarn(tag, format, arg...)  [LMLogger warn:tag message:format, ##arg]
#define LogError(tag, format, arg...)  [LMLogger error:tag message:format, ##arg]

