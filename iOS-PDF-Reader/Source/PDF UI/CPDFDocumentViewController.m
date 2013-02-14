//
//  iOS-PDF-ReaderViewController.m
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

#import "CPDFDocumentViewController.h"

#import <QuartzCore/QuartzCore.h>

#import "CPDFDocument.h"
#import "CPDFPageViewController.h"
#import "CPDFPage.h"
#import "CPreviewBar.h"
#import "CPDFPageView.h"
#import "CContentScrollView.h"
#import "Geometry.h"

@interface CPDFDocumentViewController () <CPDFDocumentDelegate, UIPageViewControllerDelegate, UIPageViewControllerDataSource, UIGestureRecognizerDelegate, CPreviewBarDelegate, CPDFPageViewDelegate, UIScrollViewDelegate>

@property (readwrite, nonatomic, strong) UIPageViewController *pageViewController;
@property (readwrite, nonatomic, strong) IBOutlet CContentScrollView *scrollView;
@property (readwrite, nonatomic, strong) IBOutlet CContentScrollView *previewScrollView;
@property (readwrite, nonatomic, strong) IBOutlet CPreviewBar *previewBar;
@property (readwrite, nonatomic, assign) BOOL chromeHidden;
@property (readwrite, nonatomic, strong) NSCache *renderedPageCache;
@property (readwrite, nonatomic, strong) UIView *extraControls;

- (void)hideChrome;
- (void)toggleChrome;
- (BOOL)canDoubleSpreadForOrientation:(UIInterfaceOrientation)inOrientation;
- (void)resizePageViewControllerForOrientation:(UIInterfaceOrientation)inOrientation;
- (CPDFPageViewController *)pageViewControllerWithPage:(CPDFPage *)inPage;
@end

@implementation CPDFDocumentViewController

@synthesize pageViewController = _pageViewController;
@synthesize scrollView = _scrollView;
@synthesize previewScrollView = _previewScrollView;
@synthesize previewBar = _previewBar;
@synthesize chromeHidden = _chromeHidden;
@synthesize renderedPageCache = _renderedPageCache;

@synthesize document = _document;
@synthesize backgroundView = _backgroundView;
@synthesize magazineMode = _magazineMode;
@synthesize pagePlaceholderImage = _pagePlaceholderImage;

- (id)initWithDocument:(CPDFDocument *)inDocument
    {
    if ((self = [super initWithNibName:NULL bundle:NULL]) != NULL)
        {
        _document = inDocument;
        _document.delegate = self;
        _renderedPageCache = [[NSCache alloc] init];
        _renderedPageCache.countLimit = 8;
        }
    return(self);
    }

- (id)initWithURL:(NSURL *)inURL;
    {
    CPDFDocument *theDocument = [[CPDFDocument alloc] initWithURL:inURL];
    return([self initWithDocument:theDocument]);
    }

- (void)didReceiveMemoryWarning
    {
    [super didReceiveMemoryWarning];
    }

#pragma mark -

- (void)setBackgroundView:(UIView *)backgroundView
    {
    if (_backgroundView != backgroundView)
        {
        [_backgroundView removeFromSuperview];

        _backgroundView = backgroundView;
        [self.view insertSubview:_backgroundView atIndex:0];
        }
    }

#pragma mark -

- (void)loadView
    {
    [super loadView];

    [self updateTitle];

    // #########################################################################
    UIPageViewControllerSpineLocation theSpineLocation;
    if ([self canDoubleSpreadForOrientation:self.interfaceOrientation] == YES)
        {
        theSpineLocation = UIPageViewControllerSpineLocationMid;
        }
    else
        {
        theSpineLocation = UIPageViewControllerSpineLocationMin;
        }

    // #########################################################################
    NSDictionary *theOptions = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInt:theSpineLocation], UIPageViewControllerOptionSpineLocationKey,
        NULL];

    self.pageViewController = [[UIPageViewController alloc] initWithTransitionStyle:UIPageViewControllerTransitionStylePageCurl navigationOrientation:UIPageViewControllerNavigationOrientationHorizontal options:theOptions];
    self.pageViewController.delegate = self;
    self.pageViewController.dataSource = self;

    NSRange theRange = { .location = 1, .length = 1 };
    if (self.pageViewController.spineLocation == UIPageViewControllerSpineLocationMid)
        {
        theRange = (NSRange){ .location = 0, .length = 2 };
        }
    NSArray *theViewControllers = [self pageViewControllersForRange:theRange];
    [self.pageViewController setViewControllers:theViewControllers direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:NULL];

    [self addChildViewController:self.pageViewController];

    self.scrollView = [[CContentScrollView alloc] initWithFrame:self.pageViewController.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.contentView = self.pageViewController.view;
    self.scrollView.maximumZoomScale = [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone ? 8.0 : 4.0;
    self.scrollView.delegate = self;
    
    [self.scrollView addSubview:self.scrollView.contentView];

    [self.view insertSubview:self.scrollView atIndex:0];

    // #########################################################################

    CGRect theFrame = (CGRect){
        .origin = {
            .x = CGRectGetMinX(self.view.bounds),
            .y = CGRectGetMaxY(self.view.bounds) - 74,
            },
        .size = {
            .width = CGRectGetWidth(self.view.bounds),
            .height = 74,
            },
        };

    self.previewScrollView = [[CContentScrollView alloc] initWithFrame:theFrame];
    self.previewScrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    self.previewScrollView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.5];
    self.previewScrollView.contentInset = UIEdgeInsetsMake(5.0f, 0.0f, 5.0f, 0.0f);
    [self.view addSubview:self.previewScrollView];

    CGRect contentFrame = (CGRect){
        .size = {
            .width = theFrame.size.width,
            .height = 64,
            },
    };
    self.previewBar = [[CPreviewBar alloc] initWithFrame:contentFrame];
    [self.previewBar addTarget:self action:@selector(gotoPage:) forControlEvents:UIControlEventValueChanged];
    self.previewBar.delegate = self;
    [self.previewBar sizeToFit];

    [self.previewScrollView addSubview:self.previewBar];
    self.previewScrollView.contentView = self.previewBar;

    // #########################################################################

    UITapGestureRecognizer *theSingleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)];
    [self.view addGestureRecognizer:theSingleTapGestureRecognizer];

    UITapGestureRecognizer *theDoubleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTap:)];
    theDoubleTapGestureRecognizer.numberOfTapsRequired = 2;
    [self.view addGestureRecognizer:theDoubleTapGestureRecognizer];

    [theSingleTapGestureRecognizer requireGestureRecognizerToFail:theDoubleTapGestureRecognizer];
    }

- (void)viewWillAppear:(BOOL)animated
    {
    [super viewWillAppear:animated];
    //
    [self resizePageViewControllerForOrientation:self.interfaceOrientation];

    double delayInSeconds = 1.0;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [self populateCache];
        [self.document startGeneratingThumbnails];
        });
    }

- (void)viewDidAppear:(BOOL)animated
    {
    [super viewDidAppear:animated];

    [self performSelector:@selector(hideChrome) withObject:NULL afterDelay:0.5];
    }

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
    {
    return(YES);
    }

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
    {
    [self resizePageViewControllerForOrientation:toInterfaceOrientation];
    }

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
    {
    [self updateTitle];
    [self.renderedPageCache removeAllObjects];
    [self populateCache];
    }

- (void)hideChrome
    {
        if (self.chromeHidden == NO)
            {
            [UIView animateWithDuration:UINavigationControllerHideShowBarDuration animations:^{
                self.navigationController.navigationBar.alpha = 0.0;
                self.previewScrollView.alpha = 0.0;
                [self expandContentView:YES];
                } completion:^(BOOL finished) {
                    self.chromeHidden = YES;                    
                }];
            }
    }

- (void)toggleChrome
    {
    [UIView animateWithDuration:UINavigationControllerHideShowBarDuration animations:^{
        self.navigationController.navigationBar.alpha = (1.0 - !self.chromeHidden);
        self.previewScrollView.alpha = (1.0 - !self.chromeHidden);
        [self expandContentView:!self.chromeHidden];
        } completion:^(BOOL finished) {
        self.chromeHidden = !self.chromeHidden;            
        }];
    }

- (void)expandContentView:(BOOL)hidden
{
    CGRect contentViewFrame = self.scrollView.contentView.frame;
    static CGFloat chromeDelta = 0;
    
    if (hidden) {
        chromeDelta = -chromeDelta;
    } else {        
        chromeDelta = self.navigationController.navigationBar.frame.size.height - contentViewFrame.origin.y;
    }    
    
    contentViewFrame.origin.y += chromeDelta;
    [self.scrollView.contentView setFrame:contentViewFrame];
    self.extraControls.hidden = hidden;
}

- (void)viewDidLoad
{
    [self addControlItems];
}

#pragma mark Constants

#define BUTTON_X 8.0f
#define BUTTON_Y 8.0f
#define BUTTON_SPACE 3.0f
#define BUTTON_HEIGHT 30.0f

#define DONE_BUTTON_WIDTH 100.0f
#define THUMBS_BUTTON_WIDTH 40.0f
#define PRINT_BUTTON_WIDTH 40.0f
#define EMAIL_BUTTON_WIDTH 40.0f
#define MARK_BUTTON_WIDTH 40.0f

#define TEXT_BUTTON_WIDTH 60.0f //customized by tanduy
#define SHARE_BUTTON_WIDTH 35.0f //customized by tanduy

#define TITLE_HEIGHT 28.0f

- (void)stepperAction:(id)sender
{
    UIStepper *actualStepper = (UIStepper *)sender;
    NSLog(@"stepperAction: value = %f", [actualStepper value]);
    [self.scrollView setZoomScale:[actualStepper value]];
}

- (void)addControlItems
{
    UIStepper *stepper = [[UIStepper alloc] initWithFrame:CGRectMake(5, 0, 0, 0)];
    [stepper sizeToFit];
    
    stepper.value = 0;
    stepper.minimumValue = 1;
    stepper.maximumValue = 6;
    stepper.stepValue = 1;
    stepper.layer.opacity = 0.8;
    self.scrollView.maximumZoomScale = 6;
    
    [stepper addTarget:self action:@selector(stepperAction:) forControlEvents:UIControlEventValueChanged];
    self.extraControls = [[UIView alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height - 110, self.view.bounds.size.width, 34)];
    self.extraControls.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
//    [self.extraControls setBackgroundColor:[UIColor redColor]];
    [self.extraControls addSubview:stepper];
    
    [self.view addSubview:self.extraControls];
    [self.view bringSubviewToFront:self.extraControls];    
    
    UIImage *imageH = [UIImage imageNamed:@"Reader-Button-H.png"];
    UIImage *imageN = [UIImage imageNamed:@"Reader-Button-N.png"];
    
    UIImage *buttonH = [imageH stretchableImageWithLeftCapWidth:5 topCapHeight:0];
    UIImage *buttonN = [imageN stretchableImageWithLeftCapWidth:5 topCapHeight:0];
        
    CGFloat leftButtonX = BUTTON_X;
    NSMutableArray *leftBarButtonItems = [[NSMutableArray alloc] init];
    NSMutableArray *rightBarButtonItems = [[NSMutableArray alloc] init];

    UIButton *doneButton = [UIButton buttonWithType:UIButtonTypeCustom];
    
    doneButton.frame = CGRectMake(leftButtonX, BUTTON_Y, DONE_BUTTON_WIDTH, BUTTON_HEIGHT);
    [doneButton setImage:[UIImage imageNamed:@"bt_backtolib"] forState:UIControlStateNormal];
    [doneButton setTitleColor:[UIColor colorWithWhite:0.0f alpha:1.0f] forState:UIControlStateNormal];
    [doneButton setTitleColor:[UIColor colorWithWhite:1.0f alpha:1.0f] forState:UIControlStateHighlighted];
    [doneButton addTarget:self action:@selector(doneButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    doneButton.titleLabel.font = [UIFont systemFontOfSize:14.0f];
    doneButton.autoresizingMask = UIViewAutoresizingNone;    
    
    [leftBarButtonItems addObject:[[UIBarButtonItem alloc] initWithCustomView:doneButton]];
    
    leftButtonX += (DONE_BUTTON_WIDTH + BUTTON_SPACE);

    UIButton *textButton = [UIButton buttonWithType:UIButtonTypeCustom];
    
    textButton.frame = CGRectMake(leftButtonX, BUTTON_Y, TEXT_BUTTON_WIDTH, BUTTON_HEIGHT);
    [textButton setImage:[UIImage imageNamed:@"bt_text"] forState:UIControlStateNormal];
    [textButton setTitleColor:[UIColor colorWithWhite:0.0f alpha:1.0f] forState:UIControlStateNormal];
    [textButton setTitleColor:[UIColor colorWithWhite:1.0f alpha:1.0f] forState:UIControlStateHighlighted];
    [textButton addTarget:self action:@selector(textButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    textButton.titleLabel.font = [UIFont systemFontOfSize:14.0f];
    textButton.autoresizingMask = UIViewAutoresizingNone;
    
    [leftBarButtonItems addObject:[[UIBarButtonItem alloc] initWithCustomView:textButton]];
    
    leftButtonX += (TEXT_BUTTON_WIDTH + BUTTON_SPACE);
    
    UIButton *thumbsButton = [UIButton buttonWithType:UIButtonTypeCustom];
    
    thumbsButton.frame = CGRectMake(leftButtonX, BUTTON_Y, THUMBS_BUTTON_WIDTH, BUTTON_HEIGHT);
    [thumbsButton setImage:[UIImage imageNamed:@"Reader-Thumbs"] forState:UIControlStateNormal];
    [thumbsButton addTarget:self action:@selector(thumbsButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [thumbsButton setBackgroundImage:buttonH forState:UIControlStateHighlighted];
    [thumbsButton setBackgroundImage:buttonN forState:UIControlStateNormal];
    thumbsButton.autoresizingMask = UIViewAutoresizingNone;
    
    [leftBarButtonItems addObject:[[UIBarButtonItem alloc] initWithCustomView:thumbsButton]];
    leftButtonX += (THUMBS_BUTTON_WIDTH + BUTTON_SPACE);
    
    
    CGFloat rightButtonX = self.view.bounds.size.width;
    rightButtonX -= (SHARE_BUTTON_WIDTH + BUTTON_SPACE);
    
    UIButton *shareButton = [UIButton buttonWithType:UIButtonTypeCustom];
    
    shareButton.frame = CGRectMake(rightButtonX, BUTTON_Y, SHARE_BUTTON_WIDTH, BUTTON_HEIGHT);
    [shareButton setImage:[UIImage imageNamed:@"bt_share"] forState:UIControlStateNormal];
    [shareButton setTitleColor:[UIColor colorWithWhite:0.0f alpha:1.0f] forState:UIControlStateNormal];
    [shareButton setTitleColor:[UIColor colorWithWhite:1.0f alpha:1.0f] forState:UIControlStateHighlighted];
    [shareButton addTarget:self action:@selector(shareButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    shareButton.titleLabel.font = [UIFont systemFontOfSize:14.0f];
    shareButton.autoresizingMask = UIViewAutoresizingNone;
    
    [rightBarButtonItems addObject:[[UIBarButtonItem alloc] initWithCustomView:shareButton]];
    
    
    rightButtonX -= (MARK_BUTTON_WIDTH + BUTTON_SPACE);
    
    UIButton *flagButton = [UIButton buttonWithType:UIButtonTypeCustom];
    
    flagButton.frame = CGRectMake(rightButtonX, BUTTON_Y, MARK_BUTTON_WIDTH, BUTTON_HEIGHT);
    [flagButton setImage:[UIImage imageNamed:@"Reader-Mark-N.png"] forState:UIControlStateNormal];
    [flagButton addTarget:self action:@selector(markButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [flagButton setBackgroundImage:buttonH forState:UIControlStateHighlighted];
    [flagButton setBackgroundImage:buttonN forState:UIControlStateNormal];
    flagButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        
    UIButton *markButton = flagButton; markButton.enabled = NO; markButton.tag = NSIntegerMin;
    [rightBarButtonItems addObject:[[UIBarButtonItem alloc] initWithCustomView:markButton]];
//    
//    markImageN = [UIImage imageNamed:@"Reader-Mark-N.png"]; // N image
//    markImageY = [UIImage imageNamed:@"Reader-Mark-Y.png"]; // Y image

    
//
//#if (READER_ENABLE_MAIL == TRUE) // Option
//    
//    if ([MFMailComposeViewController canSendMail] == YES) // Can email
//    {
//        unsigned long long fileSize = [object.fileSize unsignedLongLongValue];
//        
//        if (fileSize < (unsigned long long)15728640) // Check attachment size limit (15MB)
//        {
//            rightButtonX -= (EMAIL_BUTTON_WIDTH + BUTTON_SPACE);
//            
//            UIButton *emailButton = [UIButton buttonWithType:UIButtonTypeCustom];
//            
//            emailButton.frame = CGRectMake(rightButtonX, BUTTON_Y, EMAIL_BUTTON_WIDTH, BUTTON_HEIGHT);
//            [emailButton setImage:[UIImage imageNamed:@"Reader-Email.png"] forState:UIControlStateNormal];
//            [emailButton addTarget:self action:@selector(emailButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
//            [emailButton setBackgroundImage:buttonH forState:UIControlStateHighlighted];
//            [emailButton setBackgroundImage:buttonN forState:UIControlStateNormal];
//            emailButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
//            
//            [self addSubview:emailButton]; titleWidth -= (EMAIL_BUTTON_WIDTH + BUTTON_SPACE);
//        }
//    }
//    
//#endif // end of READER_ENABLE_MAIL Option
//    
//#if (READER_ENABLE_PRINT == TRUE) // Option
//    
//    if (object.password == nil) // We can only print documents without passwords
//    {
//        Class printInteractionController = NSClassFromString(@"UIPrintInteractionController");
//        
//        if ((printInteractionController != nil) && [printInteractionController isPrintingAvailable])
//        {
//            rightButtonX -= (PRINT_BUTTON_WIDTH + BUTTON_SPACE);
//            
//            UIButton *printButton = [UIButton buttonWithType:UIButtonTypeCustom];
//            
//            printButton.frame = CGRectMake(rightButtonX, BUTTON_Y, PRINT_BUTTON_WIDTH, BUTTON_HEIGHT);
//            [printButton setImage:[UIImage imageNamed:@"Reader-Print.png"] forState:UIControlStateNormal];
//            [printButton addTarget:self action:@selector(printButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
//            [printButton setBackgroundImage:buttonH forState:UIControlStateHighlighted];
//            [printButton setBackgroundImage:buttonN forState:UIControlStateNormal];
//            printButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
//            
//            [self addSubview:printButton]; titleWidth -= (PRINT_BUTTON_WIDTH + BUTTON_SPACE);
//        }
//    }
//    
//#endif // end of READER_ENABLE_PRINT Option
//
    
    self.navigationItem.leftBarButtonItems = leftBarButtonItems;
    self.navigationItem.rightBarButtonItems = rightBarButtonItems;
}


#pragma mark UIButton action methods
- (void)doneButtonTapped:(UIButton *)button
{
    
}

- (void)shareButtonTapped:(UIButton *)button
{
    
}

- (void)textButtonTapped:(UIButton *)button
{
    
}

- (void)thumbsButtonTapped:(UIButton *)button
{

}

- (void)updateTitle
    {
    NSArray *theViewControllers = self.pageViewController.viewControllers;
    if (theViewControllers.count == 1)
        {
        CPDFPageViewController *theFirstViewController = [theViewControllers objectAtIndex:0];
        if (theFirstViewController.page.pageNumber == 1)
            {
            self.title = self.document.title;
            }
        else
            {
            self.title = [NSString stringWithFormat:@"Page %d", theFirstViewController.page.pageNumber];
            }
        }
    else if (theViewControllers.count == 2)
        {
        CPDFPageViewController *theFirstViewController = [theViewControllers objectAtIndex:0];
        if (theFirstViewController.page.pageNumber == 1)
            {
            self.title = self.document.title;
            }
        else
            {
            CPDFPageViewController *theSecondViewController = [theViewControllers objectAtIndex:1];
            self.title = [NSString stringWithFormat:@"Pages %d-%d", theFirstViewController.page.pageNumber, theSecondViewController.page.pageNumber];
            }
        }
    }

- (void)resizePageViewControllerForOrientation:(UIInterfaceOrientation)inOrientation
    {
    CGRect theBounds = self.view.bounds;
    CGRect theFrame;
    CGRect theMediaBox = [self.document pageForPageNumber:1].mediaBox;
    if ([self canDoubleSpreadForOrientation:inOrientation] == YES)
        {
        theMediaBox.size.width *= 2;
        theFrame = ScaleAndAlignRectToRect(theMediaBox, theBounds, ImageScaling_Proportionally, ImageAlignment_Center);
        }
    else
        {
        theFrame = ScaleAndAlignRectToRect(theMediaBox, theBounds, ImageScaling_Proportionally, ImageAlignment_Center);
        }

    theFrame = CGRectIntegral(theFrame);

    self.pageViewController.view.frame = theFrame;
    
    // Show fancy shadow if PageViewController view is smaller than parent view
    if (CGRectContainsRect(self.view.frame, self.pageViewController.view.frame) && CGRectEqualToRect(self.view.frame, self.pageViewController.view.frame) == NO)
        {
            CALayer *theLayer = self.pageViewController.view.layer;
            theLayer.shadowPath = [[UIBezierPath bezierPathWithRect:self.pageViewController.view.bounds] CGPath];
            theLayer.shadowRadius = 10.0f;
            theLayer.shadowColor = [[UIColor blackColor] CGColor];
            theLayer.shadowOpacity = 0.75f;
            theLayer.shadowOffset = CGSizeZero;
        }
    else
        {
            self.pageViewController.view.layer.shadowOpacity = 0.0f;
        }
    }

#pragma mark -

- (NSArray *)pageViewControllersForRange:(NSRange)inRange
    {
    NSMutableArray *thePages = [NSMutableArray array];
    for (NSUInteger N = inRange.location; N != inRange.location + inRange.length; ++N)
        {
        //thealch3m1st: if you do this on the last page of a document with an even number of pages it causes the assertion to fail because the last document is not a valid document (number of pages + 1)
        NSUInteger pageNumber = N > self.document.numberOfPages ? 0 : N;
        CPDFPage *thePage = pageNumber > 0 ? [self.document pageForPageNumber:pageNumber] : NULL;
        [thePages addObject:[self pageViewControllerWithPage:thePage]];
        }
    return(thePages);
    }

- (BOOL)canDoubleSpreadForOrientation:(UIInterfaceOrientation)inOrientation
    {
    if (UIInterfaceOrientationIsPortrait(inOrientation) || self.document.numberOfPages == 1)
        {
        return(NO);
        }
    else
        {
        return(YES);
        }
    }

- (CPDFPageViewController *)pageViewControllerWithPage:(CPDFPage *)inPage
    {
    CPDFPageViewController *thePageViewController = [[CPDFPageViewController alloc] initWithPage:inPage];
    thePageViewController.pagePlaceholderImage = self.pagePlaceholderImage;
    // Force load the view.
    [thePageViewController view];
//    NSParameterAssert(thePageViewController.pageView != NULL);
    thePageViewController.pageView.delegate = self;
    thePageViewController.pageView.renderedPageCache = self.renderedPageCache;
    return(thePageViewController);
    }

- (NSArray *)pages
    {
    return([self.pageViewController.viewControllers valueForKey:@"page"]);
    }

#pragma mark -

- (BOOL)openPage:(CPDFPage *)inPage
    {
    CPDFPageViewController *theCurrentPageViewController = [self.pageViewController.viewControllers objectAtIndex:0];
    if (inPage == theCurrentPageViewController.page)
        {
        return(YES);
        }

    NSRange theRange = { .location = inPage.pageNumber, .length = 1 };
    if (self.pageViewController.spineLocation == UIPageViewControllerSpineLocationMid)
        {
        theRange.length = 2;
        }
    NSArray *theViewControllers = [self pageViewControllersForRange:theRange];

    UIPageViewControllerNavigationDirection theDirection = inPage.pageNumber > theCurrentPageViewController.pageNumber ? UIPageViewControllerNavigationDirectionForward : UIPageViewControllerNavigationDirectionReverse;

    [self.pageViewController setViewControllers:theViewControllers direction:theDirection animated:YES completion:NULL];
    [self updateTitle];
    
    [self populateCache];

    return(YES);
    }

- (void)tap:(UITapGestureRecognizer *)inRecognizer
    {
    [self toggleChrome];
    }

- (void)doubleTap:(UITapGestureRecognizer *)inRecognizer
    {
//    NSLog(@"DOUBLE TAP: %f", self.scrollView.zoomScale);
    if (self.scrollView.zoomScale != 1.0)
        {
        [self.scrollView setZoomScale:1.0 animated:YES];
        }
    else
        {
        [self.scrollView setZoomScale:[UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone ? 2.6 : 1.66 animated:YES];
        }
    }

- (IBAction)gotoPage:(id)sender
    {
    NSUInteger thePageNumber = [self.previewBar.selectedPreviewIndexes firstIndex] + 1;
    if (UIInterfaceOrientationIsLandscape(self.interfaceOrientation))
        {
        thePageNumber = thePageNumber / 2 * 2;
        }

    NSUInteger theLength = UIInterfaceOrientationIsPortrait(self.interfaceOrientation) ? 1 : ( thePageNumber < self.document.numberOfPages ? 2 : 1 );
    self.previewBar.selectedPreviewIndexes = [NSIndexSet indexSetWithIndexesInRange:(NSRange){ .location = thePageNumber - 1, .length = theLength }];

    [self openPage:[self.document pageForPageNumber:thePageNumber]];
    }

- (void)populateCache
    {
//    NSLog(@"POPULATING CACHE")

    CPDFPage *theStartPage = [self.pages objectAtIndex:0] != [NSNull null] ? [self.pages objectAtIndex:0] : NULL;
    CPDFPage *theLastPage = [self.pages lastObject] != [NSNull null] ? [self.pages lastObject] : NULL;

    NSInteger theStartPageNumber = [theStartPage pageNumber];
    NSInteger theLastPageNumber = [theLastPage pageNumber];
        
    NSInteger pageSpanToLoad = 1;
    if (UIInterfaceOrientationIsLandscape(self.interfaceOrientation))
        {
        pageSpanToLoad = 2;
        }

    theStartPageNumber = MAX(theStartPageNumber - pageSpanToLoad, 0);
    theLastPageNumber = MIN(theLastPageNumber + pageSpanToLoad, self.document.numberOfPages);

//    NSLog(@"(Potentially) Fetching: %d - %d", theStartPageNumber, theLastPageNumber);

    UIView *thePageView = [[self.pageViewController.viewControllers objectAtIndex:0] pageView];
    if (thePageView == NULL)
        {
        NSLog(@"WARNING: No page view.");
        return;
        }
    CGRect theBounds = thePageView.bounds;

    for (NSInteger thePageNumber = theStartPageNumber; thePageNumber <= theLastPageNumber; ++thePageNumber)
        {
        NSString *theKey = [NSString stringWithFormat:@"%d[%d,%d]", thePageNumber, (int)theBounds.size.width, (int)theBounds.size.height];
        if ([self.renderedPageCache objectForKey:theKey] == NULL)
            {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                UIImage *theImage = [[self.document pageForPageNumber:thePageNumber] imageWithSize:theBounds.size scale:[UIScreen mainScreen].scale];
                if (theImage != NULL)
                    {
                    [self.renderedPageCache setObject:theImage forKey:theKey];
                    }
                });
            }
        }
    }

#pragma mark -

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerBeforeViewController:(UIViewController *)viewController
    {
    CPDFPageViewController *theViewController = (CPDFPageViewController *)viewController;

    NSUInteger theNextPageNumber = theViewController.page.pageNumber - 1;
    if (theNextPageNumber > self.document.numberOfPages)
        {
        return(NULL);
        }

    if (theNextPageNumber == 0 && UIInterfaceOrientationIsPortrait(self.interfaceOrientation))
        {
        return(NULL);
        }

    CPDFPage *thePage = theNextPageNumber > 0 ? [self.document pageForPageNumber:theNextPageNumber] : NULL;
    theViewController = [self pageViewControllerWithPage:thePage];

    return(theViewController);
    }

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerAfterViewController:(UIViewController *)viewController
    {
    CPDFPageViewController *theViewController = (CPDFPageViewController *)viewController;

    NSUInteger theNextPageNumber = theViewController.page.pageNumber + 1;
    if (theNextPageNumber > self.document.numberOfPages)
        {
        //thealch3m1st: if we are in two page mode and the document has an even number of pages if it would just return NULL it woudln't flip to that last page so we have to return a an empty page for the (number of pages + 1)th page.
            if(self.document.numberOfPages %2 == 0 &&
               theNextPageNumber == self.document.numberOfPages + 1 &&
               self.pageViewController.spineLocation == UIPageViewControllerSpineLocationMid)
                return [self pageViewControllerWithPage:NULL];
        return(NULL);
        }

    CPDFPage *thePage = theNextPageNumber > 0 ? [self.document pageForPageNumber:theNextPageNumber] : NULL;
    theViewController = [self pageViewControllerWithPage:thePage];

    return(theViewController);
    }

#pragma mark -

- (void)pageViewController:(UIPageViewController *)pageViewController didFinishAnimating:(BOOL)finished previousViewControllers:(NSArray *)previousViewControllers transitionCompleted:(BOOL)completed;
    {
    [self updateTitle];
    [self populateCache];
    [self hideChrome];

    CPDFPageViewController *theFirstViewController = [self.pageViewController.viewControllers objectAtIndex:0];
    if (theFirstViewController.page)
        {
        NSArray *thePageNumbers = [self.pageViewController.viewControllers valueForKey:@"pageNumber"];
        NSMutableIndexSet *theIndexSet = [NSMutableIndexSet indexSet];
        for (NSNumber *thePageNumber in thePageNumbers)
            {
            int N = [thePageNumber integerValue] - 1;
            if (N != 0)
                {
                [theIndexSet addIndex:N];
                }
            }
        self.previewBar.selectedPreviewIndexes = theIndexSet;
        }
    }

- (UIPageViewControllerSpineLocation)pageViewController:(UIPageViewController *)pageViewController spineLocationForInterfaceOrientation:(UIInterfaceOrientation)orientation
    {
    UIPageViewControllerSpineLocation theSpineLocation;
    NSArray *theViewControllers = NULL;

	if (UIInterfaceOrientationIsPortrait(orientation) || self.document.numberOfPages == 1)
        {
		theSpineLocation = UIPageViewControllerSpineLocationMin;
        self.pageViewController.doubleSided = NO;

        CPDFPageViewController *theCurrentViewController = [self.pageViewController.viewControllers objectAtIndex:0];
        if (theCurrentViewController.page == NULL)
            {
            theViewControllers = [self pageViewControllersForRange:(NSRange){ 1, 1 }];
            }
        else
            {
            theViewControllers = [self pageViewControllersForRange:(NSRange){ theCurrentViewController.page.pageNumber, 1 }];
            }
        }
    else
        {
        theSpineLocation = UIPageViewControllerSpineLocationMid;
        self.pageViewController.doubleSided = YES;

        CPDFPageViewController *theCurrentViewController = [self.pageViewController.viewControllers objectAtIndex:0];
        NSUInteger theCurrentPageNumber = theCurrentViewController.page.pageNumber;

        theCurrentPageNumber = theCurrentPageNumber / 2 * 2;

        theViewControllers = [self pageViewControllersForRange:(NSRange){ theCurrentPageNumber, 2 }];
        }

    [self.pageViewController setViewControllers:theViewControllers direction:UIPageViewControllerNavigationDirectionForward animated:YES completion:NULL];
    return(theSpineLocation);
    }

#pragma mark -

- (NSInteger)numberOfPreviewsInPreviewBar:(CPreviewBar *)inPreviewBar
    {
    return(self.document.numberOfPages);
    }

- (UIImage *)previewBar:(CPreviewBar *)inPreviewBar previewAtIndex:(NSInteger)inIndex;
    {
    UIImage *theImage = [self.document pageForPageNumber:inIndex + 1].thumbnail;
    return(theImage);
    }

#pragma mark -

- (void)PDFDocument:(CPDFDocument *)inDocument didUpdateThumbnailForPage:(CPDFPage *)inPage
    {
    [self.previewBar updatePreviewAtIndex:inPage.pageNumber - 1];
    }

#pragma mark -

- (BOOL)PDFPageView:(CPDFPageView *)inPageView openPage:(CPDFPage *)inPage fromRect:(CGRect)inFrame
    {
    [self openPage:inPage];
    return(YES);
    }

#pragma mark -

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView;     // return a view that will be scaled. if delegate returns nil, nothing happens
    {
    return(self.pageViewController.view);
    }


@end
