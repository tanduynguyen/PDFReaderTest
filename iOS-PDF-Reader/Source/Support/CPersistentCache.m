//
//  CPersistentCache.m
//  iOS-PDF-Reader
//
//  Created by Jonathan Wight on 06/02/11.
//  Copyright 2012 Jonathan Wight. All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without modification, are
//  permitted provided that the following conditions are met:
//
//     1. Redistributions of source code must retain the above copyright notice, this list of
//        conditions and the following disclaimer.
//
//     2. Redistributions in binary form must reproduce the above copyright notice, this list
//        of conditions and the following disclaimer in the documentation and/or other materials
//        provided with the distribution.
//
//  THIS SOFTWARE IS PROVIDED BY JONATHAN WIGHT ``AS IS'' AND ANY EXPRESS OR IMPLIED
//  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
//  FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL JONATHAN WIGHT OR
//  CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
//  SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
//  ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
//  NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
//  ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
//  The views and conclusions contained in the software and documentation are those of the
//  authors and should not be interpreted as representing official policies, either expressed
//  or implied, of Jonathan Wight.

#import "CPersistentCache.h"

#import <MobileCoreServices/MobileCoreServices.h>

#define CACHE_VERSION 0

@interface CPersistentCache ()
@property (readwrite, nonatomic, strong) NSCache *cache;
@property (readwrite, nonatomic, strong) NSURL *URL;

- (BOOL)object:(id)inObject toData:(NSData **)outData type:(NSString **)outType error:(NSError **)outError;
- (BOOL)data:(NSData *)inData type:(NSString *)inType toObject:(id *)outObject error:(NSError **)outError;
@end

#pragma mark -

@implementation CPersistentCache

@synthesize name = _name;
@synthesize converterBlock = _converterBlock;
@synthesize reverseConverterBlock = _reverseConverterBlock;

@synthesize cache = _cache;
@synthesize URL = _URL;

- (id)initWithName:(NSString *)inName
	{
	if ((self = [super init]) != NULL)
		{
        _name = inName;
//        _cache = [[NSCache alloc] init];
		}
	return(self);
	}

    
- (NSURL *)URL
    {
    if (_URL == NULL)
        {
        NSURL *theURL = [[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] lastObject];
        theURL = [theURL URLByAppendingPathComponent:@"PersistentCache"];
        theURL = [theURL URLByAppendingPathComponent:[NSString stringWithFormat:@"V%d", CACHE_VERSION]];
        theURL = [theURL URLByAppendingPathComponent:self.name];
        if ([[NSFileManager defaultManager] fileExistsAtPath:theURL.path] == NO)
            {
            [[NSFileManager defaultManager] createDirectoryAtPath:theURL.path withIntermediateDirectories:YES attributes:NULL error:NULL];
            }
        _URL = theURL;
        }
    return(_URL);
    }
    
- (BOOL)containsObjectForKey:(id)key
    {
    id theObject = [self.cache objectForKey:key];
    if (theObject == NULL)
        {
        NSURL *theMetadataURL = [[self.URL URLByAppendingPathComponent:key] URLByAppendingPathExtension:@"metadata.plist"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:theMetadataURL.path] == YES)
            {
            return(YES);
            }
        }
    return(NO);
    }
    
- (id)objectForKey:(id)key
    {
    id theObject = NULL;
    theObject = [self.cache objectForKey:key];
    if (theObject == NULL)
        {
        NSURL *theMetadataURL = [[self.URL URLByAppendingPathComponent:key] URLByAppendingPathExtension:@"metadata.plist"];
        
        NSDictionary *theMetadata = [NSDictionary dictionaryWithContentsOfURL:theMetadataURL];
        if (theMetadata != NULL)
            {
            NSURL *theDataURL = [self.URL URLByAppendingPathComponent:[theMetadata objectForKey:@"href"]];
            NSUInteger theCost = [[theMetadata objectForKey:@"cost"] unsignedIntegerValue];
            NSData *theData = [NSData dataWithContentsOfURL:theDataURL options:NSDataReadingMapped error:NULL];
            if (theData)
                {
                NSString *theType = [theMetadata objectForKey:@"type"];            
                [self data:theData type:theType toObject:&theObject error:NULL];
                
                [self.cache setObject:theObject forKey:key cost:theCost];
                }
            }
        }
    
    return(theObject);
    }

- (void)setObject:(id)obj forKey:(id)key
    {
    [self setObject:obj forKey:key cost:0];
    }
    
- (void)setObject:(id)obj forKey:(id)key cost:(NSUInteger)g
    {
    [self.cache setObject:obj forKey:key cost:g];
    
    NSURL *theURL = [self.URL URLByAppendingPathComponent:key];
// thealch3m1st: dispatching this block causes weird behavior with the preview pages. Like some of them not showing up untill all of them are generated. My opinion is that this happens because the delegate callback in the document view controller happens before the file is actually written and this happens because of dispatch_async. I tested this on single core devices because thats where I had the issue.
//    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^(void) {
        
        BOOL theWriteFlag = NO;
        
        NSURL *theDataURL = NULL;

        NSData *theData = NULL;
        NSString *theType = NULL;
        if ([self object:obj toData:&theData type:&theType error:NULL] == YES)
            {
            NSString *theFilenameExtension = (__bridge_transfer NSString *)UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)theType, kUTTagClassFilenameExtension);
            theDataURL = [theURL URLByAppendingPathExtension:theFilenameExtension];
            [theData writeToURL:theDataURL options:0 error:NULL];
            theWriteFlag = YES;
            }
            
        if (theWriteFlag == YES)
            {
            NSDictionary *theMetadata = [NSDictionary dictionaryWithObjectsAndKeys:
                [theDataURL lastPathComponent], @"href",
                [NSNumber numberWithUnsignedInteger:g], @"cost",
                theType, @"type",
                NULL];

            NSData *theData = [NSPropertyListSerialization dataWithPropertyList:theMetadata format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
            [theData writeToURL:[theURL URLByAppendingPathExtension:@"metadata.plist"] options:0 error:NULL];
            }
//        });
    }

- (void)removeObjectForKey:(id)key
    {
    [self.cache removeObjectForKey:key];
    
    NSURL *theMetadataURL = [[self.URL URLByAppendingPathComponent:key] URLByAppendingPathExtension:@"metadata.plist"];
    
    NSDictionary *theMetadata = [NSDictionary dictionaryWithContentsOfURL:theMetadataURL];
    if (theMetadata != NULL)
        {
        NSURL *theDataURL = [self.URL URLByAppendingPathComponent:[theMetadata objectForKey:@"href"]];
        
        [[NSFileManager defaultManager] removeItemAtURL:theMetadataURL error:NULL];
        [[NSFileManager defaultManager] removeItemAtURL:theDataURL error:NULL];
        }
    }

#pragma mark -

- (BOOL)object:(id)inObject toData:(NSData **)outData type:(NSString **)outType error:(NSError **)outError
    {
    BOOL theResult = NO;
    if ([inObject isKindOfClass:[UIImage class]] == YES)
        {
        if (outData)
            {
            *outData = UIImagePNGRepresentation(inObject);
            }
        if (outType)
            {
            *outType = (NSString *)kUTTypePNG;
            }
        theResult = YES;
        }
    else if ([inObject conformsToProtocol:@protocol(NSCoding)])
        {
        if (outData)
            {
            *outData = [NSKeyedArchiver archivedDataWithRootObject:inObject];
            }
        if (outType)
            {
            *outType = (NSString *)kUTTypeData;
            }
        theResult = YES;
        }
    else if (self.converterBlock != NULL)
        {
        theResult = self.converterBlock(inObject, outData, outType, outError);
        }

    return(theResult);
    }
    
- (BOOL)data:(NSData *)inData type:(NSString *)inType toObject:(id *)outObject error:(NSError **)outError
    {
    BOOL theResult = NO;
    if ([inType isEqualToString:(NSString *)kUTTypePNG])
        {
        if (outObject)
            {
            *outObject = [UIImage imageWithData:inData];
            }
        theResult = YES;
        }
    else if ([inType isEqualToString:(NSString *)kUTTypeData])
        {
        if (outObject)
            {
            *outObject = [NSKeyedUnarchiver unarchiveObjectWithData:inData];
            }
        theResult = YES;
        }
    else if (self.reverseConverterBlock != NULL)
        {
        theResult = self.reverseConverterBlock(inData, inType, outObject, outError);
        }

    return(theResult);
    }

- (void)destroyAllPersistedData
{
	NSError *theError = NULL;
	if ([[NSFileManager defaultManager] removeItemAtURL:self.URL error:&theError] == NO) {
		NSLog(@"Error destorying cache %@: %@", self.name, theError);
        // thealch3m1st: set the URL to nil otherwise it won't save anymore 
        _URL = nil;
	}
}

@end
