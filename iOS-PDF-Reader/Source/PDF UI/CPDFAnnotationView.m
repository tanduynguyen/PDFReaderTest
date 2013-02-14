//
//  CPDFAnnotationView.m
//  iOS-PDF-Reader
//
//  Created by Jonathan Wight on 5/3/12.
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

#import "CPDFAnnotationView.h"

#import "CPDFAnnotation.h"
#import "PDFUtilities.h"
#import "CPDFStream.h"

#import <MediaPlayer/MediaPlayer.h>

@interface CPDFAnnotationView ()
@property (readwrite, nonatomic, strong) MPMoviePlayerController *moviePlayer;
@end

#pragma mark -

@implementation CPDFAnnotationView

@synthesize annotation = _annotation;
@synthesize moviePlayer = _moviePlayer;

- (id)initWithAnnotation:(CPDFAnnotation *)inAnnotation;
    {
    if ((self = [super initWithFrame:inAnnotation.frame]) != NULL)
        {
        _annotation = inAnnotation;
        }
    return(self);
    }

- (void)layoutSubviews
    {
    [super layoutSubviews];
    //
    if (self.moviePlayer == NULL)
        {
        NSURL *theURL = NULL;
        theURL = self.annotation.URL;

        if (theURL == NULL)
            {
            theURL = [self.annotation.stream fileURLWithPathExtension:@"mov"];
            }

        if (theURL)
            {
            self.moviePlayer = [[MPMoviePlayerController alloc] initWithContentURL:theURL];
            self.moviePlayer.view.frame = self.bounds;
            self.moviePlayer.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [self.moviePlayer prepareToPlay];
            [self addSubview:self.moviePlayer.view];


            double delayInSeconds = 2.0;
            dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
            dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
//                [self.moviePlayer play];
                });
            }
        }
    }


@end
