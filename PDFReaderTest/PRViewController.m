//
//  PRViewController.m
//  PDFReaderTest
//
//  Created by admin on 2/9/13.
//  Copyright (c) 2013 2359media. All rights reserved.
//

#import "PRViewController.h"

@interface PRViewController ()

@end

@implementation PRViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    NSString *file = [[NSBundle mainBundle] pathForResource:@"PDFs/Duet_Grandparents_Oct_Nov_Dec-2012" ofType:@"pdf"];  //Oct-Dec 2012-success story //Duet_Grandparents_Oct_Nov_Dec-2012
   
    NSURL *theURL = [[NSURL alloc] initFileURLWithPath:file];    
    CPDFDocumentViewController *theViewController = [[CPDFDocumentViewController alloc] initWithURL:theURL];
    theViewController.pagePlaceholderImage = [UIImage imageNamed:@"placeholder_big"];
    [theViewController.view setBackgroundColor:[UIColor grayColor]];
   
    //theViewController.previewBar set
    
    theViewController.modalTransitionStyle = UIModalTransitionStyleFlipHorizontal;
    theViewController.modalPresentationStyle = UIModalPresentationFullScreen;    

    [self.navigationController pushViewController:theViewController animated:YES];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
