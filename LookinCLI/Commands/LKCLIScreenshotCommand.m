#import "LKCLIScreenshotCommand.h"
#import "LKCLIConnectedApp.h"
#import "LKCLIDisplayItemFetcher.h"
#import "LKCLIStdIO.h"
#import "LookinAppInfo.h"
#import "LookinDisplayItem.h"
#import "LookinDisplayItemDetail.h"
#import "LookinObject.h"
#import <AppKit/AppKit.h>

typedef NS_ENUM(NSInteger, LKCLIScreenshotKind) {
    LKCLIScreenshotKindGroup,
    LKCLIScreenshotKindSolo,
};

@implementation LKCLIScreenshotCommand

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments {
    NSString *bundleID = nil;
    NSString *outPath = nil;
    LKCLIScreenshotKind kind = LKCLIScreenshotKindGroup;
    unsigned long oid = 0;
    BOOL json = NO;

    for (NSUInteger idx = 0; idx < arguments.count; idx++) {
        NSString *argument = arguments[idx];
        if ([argument isEqualToString:@"--help"] || [argument isEqualToString:@"-h"]) {
            [self printHelp];
            return LKCLIExitCodeOK;
        } else if ([argument isEqualToString:@"--json"]) {
            json = YES;
        } else if ([argument isEqualToString:@"--bundle-id"] || [argument isEqualToString:@"-b"]) {
            if (idx + 1 >= arguments.count) {
                [LKCLIStdIO writeError:@"error: %@ requires a value", argument];
                return LKCLIExitCodeUsage;
            }
            bundleID = arguments[++idx];
        } else if ([argument isEqualToString:@"--oid"]) {
            if (idx + 1 >= arguments.count) {
                [LKCLIStdIO writeError:@"error: --oid requires a value"];
                return LKCLIExitCodeUsage;
            }
            NSString *oidValue = arguments[++idx];
            if (![LKCLIDisplayItemFetcher parseOIDValue:oidValue oid:&oid]) {
                [LKCLIStdIO writeError:@"error: --oid must be a positive integer"];
                return LKCLIExitCodeUsage;
            }
        } else if ([argument isEqualToString:@"--type"]) {
            if (idx + 1 >= arguments.count) {
                [LKCLIStdIO writeError:@"error: --type requires a value"];
                return LKCLIExitCodeUsage;
            }
            NSString *typeValue = arguments[++idx];
            if (![self parseTypeValue:typeValue kind:&kind]) {
                [LKCLIStdIO writeError:@"error: --type must be 'group' or 'solo'"];
                return LKCLIExitCodeUsage;
            }
        } else if ([argument isEqualToString:@"--out"] || [argument isEqualToString:@"-o"]) {
            if (idx + 1 >= arguments.count) {
                [LKCLIStdIO writeError:@"error: %@ requires a value", argument];
                return LKCLIExitCodeUsage;
            }
            outPath = arguments[++idx];
        } else {
            [LKCLIStdIO writeError:@"error: unknown option '%@'", argument];
            [LKCLIStdIO writeError:@"hint: run 'lookin screenshot --help'"];
            return LKCLIExitCodeUsage;
        }
    }

    if (bundleID.length == 0) {
        [LKCLIStdIO writeError:@"error: --bundle-id is required"];
        [LKCLIStdIO writeError:@"hint: run 'lookin apps --json' to find bundle identifiers"];
        return LKCLIExitCodeUsage;
    }
    if (oid == 0) {
        [LKCLIStdIO writeError:@"error: --oid is required"];
        [LKCLIStdIO writeError:@"hint: run 'lookin tree --bundle-id %@' to find object ids", bundleID];
        return LKCLIExitCodeUsage;
    }
    if (outPath.length == 0) {
        [LKCLIStdIO writeError:@"error: --out is required"];
        return LKCLIExitCodeUsage;
    }

    LookinStaticAsyncUpdateTaskType taskType = kind == LKCLIScreenshotKindSolo ? LookinStaticAsyncUpdateTaskTypeSoloScreenshot : LookinStaticAsyncUpdateTaskTypeGroupScreenshot;
    LKCLIDisplayItemFetchResult *result = nil;
    LKCLIExitCode exitCode = [[LKCLIDisplayItemFetcher new] fetchBundleID:bundleID
                                                                       oid:oid
                                                                  taskType:taskType
                                                               attrRequest:LookinDetailUpdateTaskAttrRequest_NotNeed
                                                        needBasisVisualInfo:NO
                                                                    result:&result];
    if (exitCode != LKCLIExitCodeOK) {
        return exitCode;
    }

    NSImage *image = [self screenshotImageFromResult:result kind:kind];
    if (!image) {
        [LKCLIStdIO writeError:@"error: no %@ screenshot returned for oid %lu", [self nameForKind:kind], oid];
        NSString *reason = [self noScreenshotReasonForDisplayItem:result.displayItem];
        if (reason.length) {
            [LKCLIStdIO writeError:@"hint: %@", reason];
        }
        return LKCLIExitCodeGeneralError;
    }

    NSString *finalPath = [self absolutePathForPath:outPath];
    NSString *format = nil;
    NSData *imageData = [self imageDataForImage:image path:finalPath format:&format];
    if (!imageData) {
        [LKCLIStdIO writeError:@"error: failed to encode screenshot"];
        return LKCLIExitCodeGeneralError;
    }

    NSError *writeError = nil;
    BOOL wrote = [imageData writeToFile:finalPath options:NSDataWritingAtomic error:&writeError];
    if (!wrote) {
        [LKCLIStdIO writeError:@"error: %@", writeError.localizedDescription ?: @"failed to write screenshot"];
        return LKCLIExitCodeGeneralError;
    }

    if (json) {
        return [self printJSONWithResult:result kind:kind path:finalPath format:format bytes:imageData.length];
    }

    [LKCLIStdIO writeOut:@"wrote %@ screenshot: %@ (%@, %lu bytes)", [self nameForKind:kind], finalPath, format, (unsigned long)imageData.length];
    return LKCLIExitCodeOK;
}

+ (void)printHelp {
    [LKCLIStdIO writeOut:
     @"Usage:\n"
      "  lookin screenshot --bundle-id <bundle-id> --oid <oid> --out <path> [--type group|solo] [--json]\n"
      "\n"
      "Fetch and write a display item screenshot. The output format is selected from the file extension: .png writes PNG, everything else writes TIFF."];
}

+ (BOOL)parseTypeValue:(NSString *)value kind:(LKCLIScreenshotKind *)kind {
    if ([value caseInsensitiveCompare:@"group"] == NSOrderedSame) {
        if (kind) {
            *kind = LKCLIScreenshotKindGroup;
        }
        return YES;
    }
    if ([value caseInsensitiveCompare:@"solo"] == NSOrderedSame) {
        if (kind) {
            *kind = LKCLIScreenshotKindSolo;
        }
        return YES;
    }
    return NO;
}

+ (NSImage *)screenshotImageFromResult:(LKCLIDisplayItemFetchResult *)result kind:(LKCLIScreenshotKind)kind {
    if (kind == LKCLIScreenshotKindSolo) {
        return result.detail.soloScreenshot ?: result.displayItem.soloScreenshot;
    }
    return result.detail.groupScreenshot ?: result.displayItem.groupScreenshot;
}

+ (NSString *)absolutePathForPath:(NSString *)path {
    NSString *expandedPath = [path stringByExpandingTildeInPath];
    if (expandedPath.isAbsolutePath) {
        return expandedPath;
    }
    return [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:expandedPath];
}

+ (NSData *)imageDataForImage:(NSImage *)image path:(NSString *)path format:(NSString **)format {
    NSString *extension = path.pathExtension.lowercaseString;
    BOOL shouldWritePNG = [extension isEqualToString:@"png"];
    NSData *tiffData = image.TIFFRepresentation;
    if (!tiffData) {
        return nil;
    }

    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithData:tiffData];
    if (shouldWritePNG) {
        if (format) {
            *format = @"png";
        }
        return [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    }

    if (format) {
        *format = @"tiff";
    }
    return [bitmap TIFFRepresentationUsingCompression:NSTIFFCompressionLZW factor:1] ?: tiffData;
}

+ (NSString *)nameForKind:(LKCLIScreenshotKind)kind {
    return kind == LKCLIScreenshotKindSolo ? @"solo" : @"group";
}

+ (NSString *)noScreenshotReasonForDisplayItem:(LookinDisplayItem *)displayItem {
    switch (displayItem.doNotFetchScreenshotReason) {
        case LookinFetchScreenshotPermitted:
            return nil;
        case LookinDoNotFetchScreenshotForTooLarge:
            return @"the display item is too large for screenshot sync";
        case LookinDoNotFetchScreenshotForUserConfig:
            return @"screenshot sync is disabled for this display item";
    }
    return nil;
}

+ (LKCLIExitCode)printJSONWithResult:(LKCLIDisplayItemFetchResult *)result
                                 kind:(LKCLIScreenshotKind)kind
                                 path:(NSString *)path
                               format:(NSString *)format
                                bytes:(NSUInteger)bytes {
    LKCLIConnectedApp *app = result.app;
    LookinObject *object = result.object;
    NSDictionary *root = @{
        @"app": @{
            @"name": app.appInfo.appName ?: [NSNull null],
            @"bundleIdentifier": app.appInfo.appBundleIdentifier ?: [NSNull null],
            @"device": app.appInfo.deviceDescription ?: [NSNull null],
            @"os": app.appInfo.osDescription ?: [NSNull null],
        },
        @"object": @{
            @"oid": @(object.oid),
            @"className": object.rawClassName ?: [NSNull null],
        },
        @"requestedOid": @(result.requestedOID),
        @"detailOid": @(result.detailOID),
        @"type": [self nameForKind:kind],
        @"path": path,
        @"format": format ?: [NSNull null],
        @"bytes": @(bytes),
    };

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
    if (!data) {
        [LKCLIStdIO writeError:@"error: %@", error.localizedDescription ?: @"failed to encode JSON"];
        return LKCLIExitCodeGeneralError;
    }
    NSString *jsonString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [LKCLIStdIO writeOut:@"%@", jsonString];
    return LKCLIExitCodeOK;
}

@end
