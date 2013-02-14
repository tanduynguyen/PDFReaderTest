//
//  CPDFDocument.m
//  iOS-PDF-Reader
//
//  Created by Jonathan Wight on 02/19/11.
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

#import "CPDFDocument.h"

#import "CPDFDocument_Private.h"
#import "CPDFPage.h"
#import "CPersistentCache.h"
#import "PDFUtilities.h"

@interface CPDFDocument ()
@property (readwrite, nonatomic, assign) dispatch_queue_t queue;
@property (readwrite, nonatomic, strong) NSDictionary *pageNumbersByName;

@end

#pragma mark -

@implementation CPDFDocument

@synthesize URL = _URL;
@synthesize cg = _cg;
@synthesize delegate = _delegate;

@synthesize queue = _queue;
@synthesize pageNumbersByName = _pageNumbersByName;

- (id)initWithURL:(NSURL *)inURL;
{
	if ((self = [super init]) != NULL)
    {
        _URL = inURL;
        
        _cg = CGPDFDocumentCreateWithURL((__bridge CFURLRef)inURL);
    }
	return(self);
}

- (void)dealloc
{
    if (_queue != NULL)
    {
        //        dispatch_release(_queue);
        _queue = NULL;
    }
    
    if (_cg)
    {
        CGPDFDocumentRelease(_cg);
        _cg = NULL;
    }
}

#pragma mark -

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained [])buffer count:(NSUInteger)len
{
    NSUInteger theStartIndex = state->state;
    NSUInteger theEndIndex = MIN(state->state + len, self.numberOfPages);
    
    for (NSUInteger N = theStartIndex; N != theEndIndex; ++N)
    {
        buffer[N - theStartIndex] = [self pageForPageNumber:N];
    }
    
    state->state = theEndIndex;
    state->itemsPtr = buffer;
    state->mutationsPtr = (__bridge void *)self;
    
    return(theEndIndex - theStartIndex);
}

#pragma mark -

- (NSUInteger)numberOfPages
{
    return(CGPDFDocumentGetNumberOfPages(self.cg));
}

- (NSString *)title
{
    CGPDFDictionaryRef theInfo = CGPDFDocumentGetInfo(self.cg);
    CGPDFStringRef thePDFTitle = NULL;
    CGPDFDictionaryGetString(theInfo, "Title", &thePDFTitle);
    NSString *theTitle = (__bridge_transfer NSString *)CGPDFStringCopyTextString(thePDFTitle);
    return(theTitle);
}

#pragma mark -

- (CPDFPage *)pageForPageNumber:(NSInteger)inPageNumber
{
    NSString *theKey = [NSString stringWithFormat:@"page_%d", inPageNumber];
    CPDFPage *thePage = [self.cache objectForKey:theKey];
    if (thePage == NULL)
    {
        thePage = [[CPDFPage alloc] initWithDocument:self pageNumber:inPageNumber];
        [self.cache setObject:thePage forKey:theKey];
    }
    return(thePage);
}

- (CPDFPage *)pageForPageName:(NSString *)inPageName;
{
    NSNumber *thePageNumber = [self.pageNumbersByName objectForKey:inPageName];
    if (thePageNumber != NULL)
    {
        return([self pageForPageNumber:thePageNumber.intValue]);
    }
    
    return(NULL);
}

#pragma mark -

- (NSDictionary *)pageNumbersByName
{
    if (_pageNumbersByName == NULL)
    {
        NSMutableDictionary *thePagesByPageInfo = [NSMutableDictionary dictionary];
        size_t theCount = self.numberOfPages;
        for (int N = 0; N != theCount; ++N)
        {
            CPDFPage *thePage = [self pageForPageNumber:N + 1];
            CGPDFDictionaryRef thePageInfo = CGPDFPageGetDictionary(thePage.cg);
            [thePagesByPageInfo setObject:thePage forKey:[NSNumber numberWithInt:(int)thePageInfo]];
        }
        
        NSMutableDictionary *thePageNumbersForPageNames = [NSMutableDictionary dictionary];
        
        CGPDFDictionaryRef theCatalog = CGPDFDocumentGetCatalog(self.cg);
        
        CGPDFObjectRef theObject = NULL;
        
        theObject = TXCGPDFDictionaryGetObjectForPath(theCatalog, @"Names.Dests.Names");
        
        CGPDFArrayRef theNamesArray = NULL;
        CGPDFObjectGetValue(theObject, kCGPDFObjectTypeArray, &theNamesArray);
        size_t theNamesCount = CGPDFArrayGetCount(theNamesArray);
        for (size_t N = 0; N != theNamesCount; N += 2)
        {
            NSString *thePageName = TXCGPDFArrayGetString(theNamesArray, N);
            
            CGPDFArrayRef thePageHolderArray = NULL;
            CGPDFArrayGetArray(theNamesArray, N + 1, &thePageHolderArray);
            
            CGPDFDictionaryRef thePageDictionary = NULL;
            CGPDFArrayGetDictionary(thePageHolderArray, 0, &thePageDictionary);
            
            CPDFPage *thePage = [thePagesByPageInfo objectForKey:[NSNumber numberWithInt:(int)thePageDictionary]];
            
            [thePageNumbersForPageNames setObject:[NSNumber numberWithInt:thePage.pageNumber] forKey:thePageName];
        }
        
        _pageNumbersByName = [thePageNumbersForPageNames copy];
    }
    return(_pageNumbersByName);
}

#pragma mark -

- (void)startGeneratingThumbnails
{
     NSLog(@"START GENERATING THUMBNAILS");
    
    const size_t theNumberOfPages = CGPDFDocumentGetNumberOfPages(self.cg);
    
    // TODO - what if there are multiple queues.
    self.queue = (__bridge dispatch_queue_t)((CFBridgingRetain(dispatch_queue_create("com.2359media.pdf-thumbnail-queue", NULL))));
//    self.queue = dispatch_get_main_queue();
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^(void) {
        
        dispatch_apply(theNumberOfPages, self.queue, ^(size_t inIndex) {
            
            const size_t thePageNumber = inIndex + 1;
            
            CPDFPage *thePage = [self pageForPageNumber:thePageNumber];
            
            NSString *theKey = [NSString stringWithFormat:@"page_%zd_image_128x128", thePageNumber];
            if ([self.cache objectForKey:theKey] == NULL)
            {
                @autoreleasepool
                {
                    UIImage *theImage = [thePage imageWithSize:(CGSize){ 128, 128 } scale:[UIScreen mainScreen].scale];
                    [self.cache setObject:theImage forKey:theKey];
                }
            }
            
            theKey = [NSString stringWithFormat:@"page_%zd_image_preview2", thePageNumber];
            if ([self.cache objectForKey:theKey] == NULL)
            {
                @autoreleasepool
                {
                    CGSize theSize = thePage.mediaBox.size;
                    theSize.width *= 0.5;
                    theSize.height *= 0.5;
                    
                    UIImage *theImage = [thePage imageWithSize:theSize scale:[UIScreen mainScreen].scale];
                    [self.cache setObject:theImage forKey:theKey];
                }
            }
            
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                if ([self.delegate respondsToSelector:@selector(PDFDocument:didUpdateThumbnailForPage:)])
                {
                    [self.delegate PDFDocument:self didUpdateThumbnailForPage:thePage];
                }
            });
        });
    });
}

- (void)stopGeneratingThumbnails
{
}

- (void)clearCachedThumbnails
{
	[self.cache destroyAllPersistedData];
}

@end
