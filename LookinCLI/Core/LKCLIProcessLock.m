#import "LKCLIProcessLock.h"
#import "LKCLIStdIO.h"
#import <fcntl.h>
#import <sys/file.h>
#import <unistd.h>

@implementation LKCLIProcessLock

+ (LKCLIExitCode)runDeviceCommandWithBlock:(LKCLIExitCode (^)(void))block {
    NSString *lockPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"lookin-cli-device.lock"];
    int fd = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR, 0600);
    if (fd < 0) {
        [LKCLIStdIO writeError:@"warning: failed to open device lock, continuing without process serialization"];
        return block ? block() : LKCLIExitCodeGeneralError;
    }

    if (flock(fd, LOCK_EX) != 0) {
        close(fd);
        [LKCLIStdIO writeError:@"warning: failed to acquire device lock, continuing without process serialization"];
        return block ? block() : LKCLIExitCodeGeneralError;
    }

    LKCLIExitCode exitCode = block ? block() : LKCLIExitCodeGeneralError;
    flock(fd, LOCK_UN);
    close(fd);
    return exitCode;
}

@end
