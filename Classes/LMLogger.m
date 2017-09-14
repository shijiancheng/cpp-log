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

#import "LMLoggerUtil.h"
#import "ZipUtil.h"
#import "LMCrashCollector.h"

static NSDateComponents* _currentDateComponents;

@implementation LogConfig
- (id)init
{
    if (self = [super init])
    {
        NSString *cachesDirectory = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        _dir = [cachesDirectory stringByAppendingPathComponent:@"Logs"];
        _policy = LogFilePolicyPerLaunch;
        _outputLevel = LogLevelVerbose;
        _fileLevel = LogLevelInfo;
        _consoleOutput = YES;
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

+ (void)enableCrashLog {
    [LMCrashCollector setup];
    [LMCrashCollector handleAllReports:^(NSData *reportData, NSError *error) {
        [[LMLoggerUtil shareInstance] addLog:[[NSString alloc] initWithData:reportData encoding:NSUTF8StringEncoding]];
    }];
}

+ (void)config:(LogConfig *)cfg
{
    if (cfg)
    {
        logConfig = cfg;
    }
    else
    {
        logConfig = [[LogConfig alloc] init];
    }
}

+ (LogConfig*)getConfig
{
    if (logConfig == nil)
    {
        logConfig = [[LogConfig alloc] init];
    }
    
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

static bool isLoggable(LogLevel level)
{
    return level >= logConfig.outputLevel;
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

static NSString *logFilePath = nil;
static NSFileHandle *logFileHandle = nil;

static void createLogFile()
{
    NSString *dir = logConfig.dir;
    NSError *error = nil;
    if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
        if (![[NSFileManager defaultManager] createDirectoryAtPath:dir
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:&error]) {
            //            NSLog(@"Error occurred while creating log dir(%@): %@", dir, error);
        }
    }
    
    if (!error) {
        NSDate* date = [NSDate date];
        
        //log at most one file a day
        NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
        if (logConfig.policy == LogFilePolicyPerDay)
            [formatter setDateFormat:@"yyyy-MM-dd"];
        else
            [formatter setDateFormat:@"yyyy-MM-dd_HH-mm-ss"];
        
        logFilePath = [NSString stringWithFormat:@"%@/%@.log", dir,[formatter stringFromDate:date]];
        if (![[NSFileManager defaultManager] fileExistsAtPath:logFilePath]) {
            [[NSFileManager defaultManager] createFileAtPath:logFilePath
                                                    contents:nil
                                                  attributes:nil];
        }
        NSCalendar *calendar = [NSCalendar currentCalendar];
        _currentDateComponents = [calendar components:(NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit) fromDate:date];
        
        if (logFileHandle != nil)
        {
            [logFileHandle closeFile];
            logFileHandle = nil;
        }
        logFileHandle = [NSFileHandle fileHandleForWritingAtPath:logFilePath];
        [logFileHandle seekToEndOfFile];  //need to move to the end when first open
        //        [Logger info:@"Logger" message:@"log file: %@", logFilePath];
    }
}


static void clearLogFile()
{
    if (logConfig.dir) {
        NSArray *cachedFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:logConfig.dir error:nil];
        
        if (nil == cachedFiles || ([cachedFiles count] < 1)) {
            return;
        }
        
        // 合法日志文件名
        NSDateFormatter* ymdhmsDateFormatter = [[NSDateFormatter alloc] init];
        [ymdhmsDateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
        [ymdhmsDateFormatter setDateFormat:@"yyyy-MM-dd_HH-mm-ss"];
        NSDateFormatter* ymdDateFormatter = [[NSDateFormatter alloc] init];
        [ymdDateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
        [ymdDateFormatter setDateFormat:@"yyyy-MM-dd"];
        NSDate* (^dateFromFileName)(NSString* fileName) = ^NSDate* (NSString* fileName) {
            // parse date
            NSRange range = [fileName rangeOfString:@"\\d{4}-\\d{2}-\\d{2}_\\d{2}-\\d{2}-\\d{2}" options:NSRegularExpressionSearch];
            NSDate* logDate = nil;
            if (range.location != NSNotFound) {
                NSString* dateStr = [fileName substringWithRange:range];
                logDate = [ymdhmsDateFormatter dateFromString:dateStr];
            } else {
                NSRange range = [fileName rangeOfString:@"\\d{4}-\\d{2}-\\d{2}" options:NSRegularExpressionSearch];
                if (range.location != NSNotFound) {
                    NSString* dateStr = [fileName substringWithRange:range];
                    logDate = [ymdDateFormatter dateFromString:dateStr];
                }
            }
            
            return logDate;
        };
        
        __block NSMutableArray* zipLogFiles = [NSMutableArray arrayWithCapacity:[cachedFiles count]];
        __block NSMutableArray* rawLogFiles = [NSMutableArray arrayWithCapacity:[cachedFiles count]];
        // 最少要保留2个未压缩日志
        __block int min_raw_logs = 2;
        
        // 只保留最近30天的
        NSTimeInterval expire_interval = (30 * 24 * 3600);
        NSDate* expireDate = [NSDate dateWithTimeIntervalSinceNow:-expire_interval];
        
        NSString* const RAW_LOG_EXTENSION = @"log";
        NSString* const ZIP_LOG_EXTENSION = @"zip";
        
        // 删除不需要的文件
        [cachedFiles enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            if (![obj isKindOfClass:[NSString class]]) {
                return ;
            }
            
            NSString* fileName = obj;
            // 原始log文件或者压缩后的log文件
            if (fileName && [[fileName pathExtension] isEqualToString:RAW_LOG_EXTENSION]) {
                NSDate* logDate = dateFromFileName(fileName);
                if (logDate != nil) {
                    NSString* fullPath = [logConfig.dir stringByAppendingPathComponent:fileName];
                    if (logFilePath != nil && [fullPath isEqualToString:logFilePath]) {
                        --min_raw_logs;
                    } else {
                        if (fullPath) {
                            [rawLogFiles addObject:@[logDate, fullPath]];
                        }
                        
                    }
                }
            } else if (fileName && [[fileName pathExtension] isEqualToString:ZIP_LOG_EXTENSION]) {
                NSDate* logDate = dateFromFileName(fileName);
                if (logDate != nil) {
                    [zipLogFiles addObject:@[logDate, [logConfig.dir stringByAppendingPathComponent:fileName]]];
                }
            }
        }];
        
        //删除过期的压缩日志文件
        [zipLogFiles enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            if (![obj isKindOfClass:[NSArray class] ]) {
                return ;
            }
            
            NSDate* logDate = [obj firstObject];
            if ([logDate compare:expireDate] == NSOrderedAscending) {
                NSString* fullPath = [obj lastObject];
                
                if ([[NSFileManager defaultManager] isDeletableFileAtPath:fullPath]) {
                    [[NSFileManager defaultManager] removeItemAtPath:fullPath error:NULL];
                }
            }
        }];
        
        // 未压缩日志文件按日期排序
        [rawLogFiles sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            NSDate* logDate1 = [obj1 firstObject];
            NSDate* logDate2 = [obj2 firstObject];
            
            return [logDate1 compare:logDate2];
        }];
        
        // 留下不需压缩的日志文件
        while (([rawLogFiles count] > 0) && (min_raw_logs > 0)) {
            [rawLogFiles removeLastObject];
            --min_raw_logs;
        }
        
        //删除过期的日志文件，并将其余日志文件压缩
        [rawLogFiles enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            
            NSDate* logDate = [obj firstObject];
            NSString* fullPath = [obj lastObject];
            
            BOOL shouldDelete = YES;
            if ([logDate compare:expireDate] != NSOrderedAscending) {
                shouldDelete = NO;
            }
            
            if (shouldDelete && [[NSFileManager defaultManager] isDeletableFileAtPath:fullPath]) {
                [[NSFileManager defaultManager] removeItemAtPath:fullPath error:NULL];
            }
        }];
        
    }
}

static void clearLogFileWithoutRecent()
{
    if (logConfig.dir) {
        NSArray *cachedFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:logConfig.dir error:nil];
        
        if (nil == cachedFiles) {
            return;
        }
        
        [cachedFiles enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            if ([obj isKindOfClass:[NSString class]]) {
                NSString* fullPath = [logConfig.dir stringByAppendingPathComponent:obj];
                if ([[NSFileManager defaultManager] isDeletableFileAtPath:fullPath]
                    && !((nil != logFilePath) && [fullPath isEqualToString:logFilePath])) {
                    [[NSFileManager defaultManager] removeItemAtPath:fullPath error:NULL];
                }
            }
        }];
    }
}

static void logToFile(NSString* text)
{
    static dispatch_once_t onceToken;
    static dispatch_queue_t logQueue;
    static NSDateFormatter *dateFormatter;
    dispatch_once(&onceToken, ^{
        logQueue = dispatch_queue_create("logQueue", DISPATCH_QUEUE_SERIAL);
        dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        dispatch_async(logQueue, ^{
            createLogFile();
            clearLogFile();
        });
        
    });
    
    dispatch_async(logQueue, ^{
        NSDate* date = [NSDate date];
        NSCalendar *calendar = [NSCalendar currentCalendar];
        NSDateComponents* components  = [calendar components:(NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit) fromDate:date];
        
        // 已经不是同一天了 要重写生成日志文件
        if (components.day != _currentDateComponents.day ||
            components.month != _currentDateComponents.month ||
            components.year != components.year)
        {
            createLogFile();
            clearLogFile();
        }
        NSString *dateStr = [dateFormatter stringFromDate:date];
        NSString *logText = [NSString stringWithFormat:@"%@ %@\r\n", dateStr, text];
        
        @try {
            [[LMLoggerUtil shareInstance] addLog:logText];
            
            [logFileHandle writeData:[logText dataUsingEncoding:NSUTF8StringEncoding]];
        } @catch(NSException *e) {
            //            NSLog(@"Error: cannot write log file with exception %@", e);
            logFileHandle = nil;
            createLogFile();
        }
        
    });
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

static void logInternal(NSString *tag, LogLevel level, NSString *format, va_list args)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (logConfig == nil) {
            logConfig = [[LogConfig alloc] init];
        }
    });
    
    if (isLoggable(level)) {
        NSString *logString = formatLogStr(tag, level, format, args);
        if (logConfig.consoleOutput) {
            NSLog(@"%@", logString);
        }
        
        if (level >= logConfig.fileLevel && logConfig.policy != LogFilePolicyNoLogFile) {
            logToFile(logString);
        }
    }
}

+ (NSString *)logFilePath
{
    return logFilePath;
}

+ (NSArray *)sortedLogFileArray
{
    NSArray *sortedLogFileArray = nil;
    if (logConfig.dir) {
        NSArray *logFileArray = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:logConfig.dir
                                                                                    error:nil];
        // 过滤掉 SDK 的日志
        NSMutableArray *logFileTempArray = [logFileArray mutableCopy];
        for (NSString *log in logFileArray) {
            if ([log hasPrefix:@"fusdk_"]) {
                [logFileTempArray removeObject:log];
            }
        }
        
        if ([logFileTempArray count] > 0) {
            logFileArray = [logFileTempArray sortedArrayUsingComparator:^NSComparisonResult(id log1, id log2) {
                return [log1 compare:log2 options:NSNumericSearch];
            }];
            
            NSMutableArray *tempArray = [NSMutableArray array];
            [logFileArray enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                [tempArray addObject:[logConfig.dir stringByAppendingPathComponent:obj]];
            }];
            
            sortedLogFileArray = ([tempArray count] > 0) ? [tempArray copy] : nil;
        }
    }
    
    return sortedLogFileArray;
}

+ (NSString *)logFileDir
{
    return logConfig.dir;
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

+ (void)cleanLogFiles {
    
    clearLogFileWithoutRecent();
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

#pragma mark - upload
+ (NSArray*)filePathsFromBeginDate:(NSDate*)begin endDate:(NSDate*)end fromDir:(NSString *)dirPath
{
    NSArray *cachedFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dirPath error:nil];
    
    if (nil == cachedFiles || ([cachedFiles count] < 1)) {
        return nil;
    }
    
    // 合法日志文件名
    NSDateFormatter* ymdhmsDateFormatter = [[NSDateFormatter alloc] init];
    [ymdhmsDateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    [ymdhmsDateFormatter setDateFormat:@"yyyy-MM-dd_HH-mm-ss"];
    NSDateFormatter* ymdDateFormatter = [[NSDateFormatter alloc] init];
    [ymdDateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    [ymdDateFormatter setDateFormat:@"yyyy-MM-dd"];
    
    
    NSDate* (^dateFromFileName)(NSString* fileName) = ^NSDate* (NSString* fileName) {
        // parse date
        NSRange range = [fileName rangeOfString:@"\\d{4}-\\d{2}-\\d{2}_\\d{2}-\\d{2}-\\d{2}" options:NSRegularExpressionSearch];
        NSDate* logDate = nil;
        if (range.location != NSNotFound) {
            NSString* dateStr = [fileName substringWithRange:range];
            logDate = [ymdhmsDateFormatter dateFromString:dateStr];
        } else {
            NSRange range = [fileName rangeOfString:@"\\d{4}-\\d{2}-\\d{2}" options:NSRegularExpressionSearch];
            if (range.location != NSNotFound) {
                NSString* dateStr = [fileName substringWithRange:range];
                logDate = [ymdDateFormatter dateFromString:dateStr];
            }
        }
        
        return logDate;
    };
    
    NSString* const RAW_LOG_EXTENSION = @"log";
    __block NSMutableArray* rawLogFiles = [NSMutableArray arrayWithCapacity:[cachedFiles count]];
    [cachedFiles enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if (![obj isKindOfClass:[NSString class]]) {
            return ;
        }
        NSString* fileName = obj;
        // 原始log文件或者压缩后的log文件
        if (fileName && [[fileName pathExtension] isEqualToString:RAW_LOG_EXTENSION]) {
            NSDate* logDate = dateFromFileName(fileName);
            if (logDate != nil) {
                NSString* fullPath = [dirPath stringByAppendingPathComponent:fileName];
                [rawLogFiles addObject:@{@"date": logDate, @"path":fullPath}];
            }
        }
    }];
    [rawLogFiles filterUsingPredicate:[NSPredicate predicateWithFormat:@"(date >= %@) AND (date < %@)", begin, end]];
    
    return rawLogFiles;
}
/**
 *  将每次加载的log整合到Document目录下的单日log文件
 *
 *  @param filePaths          cache下的log文件数组
 *  @param destinationDirPath 整合目的路径
 *
 *  @return 成功"YES",失败"NO"
 */
+ (BOOL)perLaunchLogsWriteToPerDayLogWithFilepaths:(NSArray *)filePaths toDir:(NSString *)destinationDirPath {
    
    //1. 先判断destinationDirPath是否存在
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDir = YES;
    NSError *error = nil;
    //不存在创建
    if (![fileManager fileExistsAtPath:destinationDirPath isDirectory:&isDir]) {
        if (![fileManager createDirectoryAtPath:destinationDirPath
                    withIntermediateDirectories:YES
                                     attributes:nil
                                          error:&error]) {
        }
    }
    //存在，则删掉里边的文件
    else {
        NSArray *dirFiles = [fileManager contentsOfDirectoryAtPath:destinationDirPath error:nil];
        for (NSString *file in dirFiles) {
            NSString *filePath = [destinationDirPath stringByAppendingPathComponent:file];
            [fileManager removeItemAtPath:filePath error:&error];
            if (error != nil) {
                //...
            }
        }
    }
    
    //2. 根据文件的时间，创建doc的log文件
    NSString *perDayLogDate;
    NSString *perDayLogFileName;
    BOOL isSuccess = YES;
    for (int index = 0; index < filePaths.count; index ++) {
        
        NSString *filename = [NSString stringWithFormat:@"%@",[filePaths[index] valueForKey:@"date"]];
        
        //截取时间的前10位
        NSRange range = NSMakeRange(0, 10);
        if (range.location != NSNotFound) {
            
            NSString* dateStr = [filename substringWithRange:range];
            
            NSFileHandle *srcFileHander = [NSFileHandle fileHandleForReadingAtPath:[filePaths[index] valueForKey:@"path"]];
            if (srcFileHander == nil) {
                isSuccess = NO;
            }
            NSData *data = [srcFileHander readDataToEndOfFile];
            //不是同一天，则创建另一个文件，并把cachelong内容写入进去
            if (![perDayLogDate isEqualToString:dateStr]) {
                
                perDayLogDate = dateStr;
                
                perDayLogFileName = [NSString stringWithFormat:@"%@/%@.log",destinationDirPath,dateStr];
                [@"\n\n\n" writeToFile:perDayLogFileName atomically:YES encoding:NSUTF8StringEncoding error:&error];
                NSFileHandle *desFileHander = [NSFileHandle fileHandleForWritingAtPath:perDayLogFileName];
                if (desFileHander == nil) {
                    isSuccess = NO;
                }
                [desFileHander writeData:data];
                [desFileHander closeFile];
            }
            //同一天的文件，则继续添加写入
            else {
                NSFileHandle *desFileHander = [NSFileHandle fileHandleForUpdatingAtPath:perDayLogFileName];
                if (desFileHander == nil) {
                    isSuccess = NO;
                }
                [desFileHander seekToEndOfFile];
                [desFileHander writeData:data];
                [desFileHander closeFile];
            }
            
            data = nil;
            [srcFileHander closeFile];
        }
    }
    return isSuccess;
}

@end
