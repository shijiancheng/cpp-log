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
    LogLevelInfo,
    LogLevelWarn,
    LogLevelError
} LogLevel;

@interface LogConfig : NSObject

@property (nonatomic, strong) NSString *dir;             // log文件目录,请采用单独的路径，不要和其它文件放一起,一般不用设置，logger会采用默认路径。
@property (nonatomic, assign) LogLevel logLevel;         // 日志级别，大于等于此级别的log才会被记录
@property (nonatomic, assign) BOOL consoleOutput;        // 是否输出到控制台,@default = YES

@end

@interface LMLogger : NSObject

/**
 * 打开日志功能,在- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions打开。
 */
+ (void)openLogger:(LogConfig *)cfg;
/**
 * 关闭日志功能，请在- (void)applicationWillTerminate:(UIApplication *)application 中调用。
 */
+ (void)closeLogger;

+ (LogConfig *)getConfig;

+ (LMLogger *)getLMLogger:(NSString *)tag;

+ (void)log:(NSString *)tag level:(LogLevel)level message:(NSString *)format, ...NS_FORMAT_FUNCTION(3, 4);

+ (void)verbose:(NSString *)tag message:(NSString *)format, ...NS_FORMAT_FUNCTION(2, 3);

+ (void)debug:(NSString *)tag message:(NSString *)format, ...NS_FORMAT_FUNCTION(2, 3);

+ (void)info:(NSString *)tag message:(NSString *)format, ...NS_FORMAT_FUNCTION(2, 3);

+ (void)warn:(NSString *)tag message:(NSString *)format, ...NS_FORMAT_FUNCTION(2, 3);

+ (void)error:(NSString *)tag message:(NSString *)format, ...NS_FORMAT_FUNCTION(2, 3);

- (void)log:(LogLevel)level message:(NSString *)format, ...NS_FORMAT_FUNCTION(2, 3);

- (void)verbose:(NSString *)format, ...NS_FORMAT_FUNCTION(1, 2);

- (void)debug:(NSString *)format, ...NS_FORMAT_FUNCTION(1, 2);

- (void)info:(NSString *)format, ...NS_FORMAT_FUNCTION(1, 2);

- (void)warn:(NSString *)format, ...NS_FORMAT_FUNCTION(1, 2);

- (void)error:(NSString *)format, ...NS_FORMAT_FUNCTION(1, 2);

@end

//非类形式的另一个打Log函数，为方便使用
#define LogVerbose(tag, format, arg...)  [LMLogger verbose:tag message:format, ##arg]
#define LogDebug(tag, format, arg...)  [LMLogger debug:tag message:format, ##arg]
#define LogInfoDev(tag, format, arg...)  [LMLogger info:tag message:format, ##arg]
#define LogInfo(tag, format, arg...)  [LMLogger info:tag message:format, ##arg]
#define LogWarn(tag, format, arg...)  [LMLogger warn:tag message:format, ##arg]
#define LogError(tag, format, arg...)  [LMLogger error:tag message:format, ##arg]

