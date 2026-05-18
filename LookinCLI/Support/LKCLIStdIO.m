#import "LKCLIStdIO.h"

@implementation LKCLIStdIO

+ (void)writeOut:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    [self writeFormat:format arguments:args file:stdout];
    va_end(args);
}

+ (void)writeError:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    [self writeFormat:format arguments:args file:stderr];
    va_end(args);
}

+ (void)writeFormat:(NSString *)format arguments:(va_list)args file:(FILE *)file {
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    if (![message hasSuffix:@"\n"]) {
        message = [message stringByAppendingString:@"\n"];
    }
    fputs(message.UTF8String, file);
}

@end
