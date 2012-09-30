//
//  NATOS.m
//  natos
//
//  Created by Nolan O'Brien on 9/29/12.
//  Copyright (c) 2012 Nolan O'Brien. All rights reserved.
//

#import "NATOS.h"
#import "NSString+Hex.h"
#import "NSTask+EasyExecute.h"

@interface NATOS ()
{
}

@property (nonatomic, assign, readwrite) unsigned int mainFunctionSymbolAddress;
@property (nonatomic, assign, readwrite) unsigned int slide;
@property (nonatomic, assign, readwrite) unsigned int loadAddress;
@property (nonatomic, assign, readwrite) unsigned int targetSymbolAddress;

- (BOOL) extractAndPrintSymbol;
- (BOOL) deriveDSYMPath;
- (BOOL) extractSlide;
- (BOOL) extractMainFunctionSymbolAddress;
- (BOOL) calculateLoadAddress;
- (BOOL) calculateTargetSymbolAddress;
- (BOOL) printTargetSymbol;

@end

@implementation NATOS

- (NSString*) dSYMPath
{
    if (!_dSYMPath && _XCArchivePath)
    {
        [self deriveDSYMPath];
    }
    return _dSYMPath;
}

- (id) initWithArgc:(int)argc argv:(const char**)argv
{
    if (self = [super init])
    {
        for (int argi = 1; argi < argc - 1; argi++)
        {
            NSString* arg = [NSString stringWithUTF8String:argv[argi]];
            NSString* val = [NSString stringWithUTF8String:argv[argi+1]];
            if (!_XCArchivePath && [arg hasPrefix:@"-x"])
            {
                _XCArchivePath = val;
            }
            else if (!_mainFunctionStackAddress && [arg hasPrefix:@"-m"])
            {
                _mainFunctionStackAddress = val.hexValue;
            }
            else if (!_targetStackAddress && [arg hasPrefix:@"-a"])
            {
                _targetStackAddress = val.hexValue;
            }
            else if (!_CPUArchitecture && [arg hasPrefix:@"-c"])
            {
                _CPUArchitecture = val;
            }
        }
        
        _executionPath = [NSString stringWithUTF8String:argv[0]];
    }
    return self;
}

- (void) printUsage
{
    printf("%s -c <CPU_ARCH> -m <MAIN_FUNCTION_STACK_ADDRES> -a <TARGET_STACK_ADDRES> -x <PATH_TO_XCARCHIVE>\n", _executionPath.UTF8String);
}

- (int) run
{
    if (!_mainFunctionStackAddress ||
        !_targetStackAddress ||
        !_CPUArchitecture ||
        (!_dSYMPath && !_XCArchivePath))
    {
        [self printUsage];
        return -1;
    }
    
    if (!self.dSYMPath)
    {
        fprintf(stderr, "%s is not a viable xarchive!\n", _XCArchivePath.UTF8String);
        return -1;
    }
    
    if (![self extractAndPrintSymbol])
    {
        fprintf(stderr, "Could not load symbol address!\n");
        return -1;
    }
    
    return 0;
}

- (BOOL) extractAndPrintSymbol
{
    BOOL success = NO;
    
    printf("Main Stack Address == 0x%x\n", self.mainFunctionStackAddress);
    printf("Target Stack Address == 0x%x\n", self.targetStackAddress);

    if ([self extractSlide])
    {
        printf("Slide == 0x%x\n", self.slide);
        if ([self extractMainFunctionSymbolAddress])
        {
            printf("Main Symbol Address == 0x%x\n", self.mainFunctionSymbolAddress);
            if ([self calculateLoadAddress])
            {
                printf("Load Address == 0x%x\n", self.loadAddress);
                if ([self calculateTargetSymbolAddress])
                {
                    printf("Target Symbol Address == 0x%x\n", self.targetSymbolAddress);
                    success = [self printTargetSymbol];
                }
            }
        }
    }
    
    return success;
}

- (BOOL) deriveDSYMPath
{
    NSString* binary = nil;
    NSString* xcarchive = _XCArchivePath;
    
    @autoreleasepool {
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:xcarchive isDirectory:&isDir] && isDir)
        {
            NSString* file = [xcarchive stringByAppendingPathComponent:@"dSYMs"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:xcarchive isDirectory:&isDir] && isDir)
            {
                NSMutableArray* possibleDSYMs = [NSMutableArray array];
                NSArray* files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:file error:NULL];
                for (NSString* theFile in files)
                {
                    if ([theFile hasSuffix:@".app.dSYM"])
                    {
                        [possibleDSYMs addObject:[file stringByAppendingPathComponent:theFile]];
                    }
                }
                
                file = nil;
                if (possibleDSYMs.count > 1)
                {
                    file = [possibleDSYMs objectAtIndex:0];
                }
                else if (possibleDSYMs.count == 1)
                {
                    file = [possibleDSYMs objectAtIndex:0];
                }
                
                if (file)
                {
                    NSString* name = [file lastPathComponent];
                    name = [name stringByDeletingPathExtension];
                    name = [name stringByDeletingPathExtension];
                    file = [file stringByAppendingPathComponent:@"Contents"];
                    file = [file stringByAppendingPathComponent:@"Resources"];
                    file = [file stringByAppendingPathComponent:@"DWARF"];
                    file = [file stringByAppendingPathComponent:name];
                    if ([[NSFileManager defaultManager] fileExistsAtPath:file isDirectory:&isDir] && !isDir)
                    {
                        binary = file;
                    }
                }
            }
        }
    }
    
    if (binary)
    {
        _dSYMPath = binary;
    }
    
    return !!binary;
}

- (BOOL) extractSlide
{
    unsigned int slide = 0;
    BOOL success = NO;
    
    @autoreleasepool {
        NSString* output = [NSTask executeAndReturnStdOut:@"/usr/bin/otool" arguments:@[@"-arch", self.CPUArchitecture, @"-l", self.dSYMPath]];
        NSArray* lines = [output componentsSeparatedByString:@"\n"];
        NSCharacterSet* whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
        for (NSUInteger i = 0; i < lines.count && !success; i++)
        {
            NSString* line = [[lines objectAtIndex:i] stringByTrimmingCharactersInSet:whitespace];
            if ([line isEqualToString:@"cmd LC_SEGMENT"])
            {
                BOOL isText = NO;
                for (NSUInteger j = 1; j+i < lines.count && j < 8 && !success; j++)
                {
                    line = [[lines objectAtIndex:i+j] stringByTrimmingCharactersInSet:whitespace];
                    if (!isText)
                    {
                        isText = [line isEqualToString:@"segname __TEXT"];
                    }
                    else if ([line hasPrefix:@"vmaddr"])
                    {
                        success = YES;
                        slide = [[[line stringByReplacingOccurrencesOfString:@"vmaddr" withString:@""] stringByTrimmingCharactersInSet:whitespace] hexValue];
                    }
                }
            }
        }
    }

    if (success)
        self.slide = slide;
    return success;
}

- (BOOL) extractMainFunctionSymbolAddress
{
    unsigned int main_symbol = 0;
    BOOL success = NO;
    
    @autoreleasepool {
        NSString* output = [NSTask executeAndReturnStdOut:@"/usr/bin/dwarfdump"
                                                arguments:@[@"--all", @"--arch", self.CPUArchitecture, self.dSYMPath]
                                      withMaxStringLength:1024*100];
        NSArray* lines = [output componentsSeparatedByString:@"\n"];
        for (NSString* line in lines)
        {
            if ([line hasSuffix:@") main"])
            {
                NSMutableArray* subvalues = [[line componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@":)-["]] mutableCopy];
                for (NSUInteger i = 0; i < subvalues.count; i++)
                {
                    NSString* subvalue = [[subvalues objectAtIndex:i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if (subvalue.length == 0)
                    {
                        [subvalues removeObjectAtIndex:i];
                        i--;
                    }
                }
                
                if (subvalues.count > 1)
                {
                    main_symbol = [[subvalues objectAtIndex:1] hexValue];
                    success = main_symbol > 0;
                }
                
                break;
            }
        }
    }
    
    if (success)
        self.mainFunctionSymbolAddress = main_symbol;
    return success;
}

- (BOOL) calculateLoadAddress
{
    BOOL success = NO;
    unsigned int ld_address = self.mainFunctionStackAddress - self.mainFunctionSymbolAddress;
    if (ld_address > self.mainFunctionStackAddress)
    {
        fprintf(stderr, "main() stack address MUST be larger than the main() symbol address\n");
    }
    else
    {
        ld_address += self.slide;
        if (ld_address < self.slide)
        {
            fprintf(stderr, "value of vm_addr (slide) is too large!\n");
        }
        else
        {
            success = YES;
            self.loadAddress = ld_address;
        }
    }
    return success;
}

- (BOOL) calculateTargetSymbolAddress
{
    BOOL success = NO;
    unsigned int func_symbol_address = self.targetStackAddress - self.loadAddress;
    if (func_symbol_address > self.targetStackAddress)
    {
        fprintf(stderr, "target stack address is too small for the calculated load address (0x%x)\n", self.loadAddress);
    }
    else
    {
        func_symbol_address += self.slide;
        if (func_symbol_address < self.slide)
        {
            fprintf(stderr, "value of vm_addr (slide) is too large!\n");
        }
        else
        {
            success = YES;
            self.targetSymbolAddress = func_symbol_address;
        }
    }
    return success;
}

- (BOOL) printTargetSymbol
{
    NSString* addy = [NSString stringWithFormat:@"0x%x", self.targetSymbolAddress];
    NSString* output = nil;
    output = [NSTask executeAndReturnStdOut:@"/usr/bin/dwarfdump" arguments:@[@"--arch", self.CPUArchitecture, @"--lookup", addy, self.dSYMPath]];
    printf("\n\ndwarfdump output:\n%s\n", output.UTF8String);
    output = [NSTask executeAndReturnStdOut:@"/usr/bin/atos" arguments:@[@"-arch", self.CPUArchitecture, @"-o", self.dSYMPath, addy]];
    printf("\n\natos output:\n%s\n", output.UTF8String);
    return YES;
}

@end