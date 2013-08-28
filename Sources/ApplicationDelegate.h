//
//  ApplicationDelegate.h
//  Serial Tools
//
//  Created by Kok Chen on 4/11/09.
//  Copyright 2009 Kok Chen, W7AY. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "GUI.h"
#import <CoreFoundation/CFRunLoop.h>


@interface ApplicationDelegate : NSObject <NSMenuDelegate>

@property (nonatomic,strong) IBOutlet NSMenu* recentMenu;

- (IBAction)newSession:(id)sender;
- (IBAction)open:(id)sender;
- (IBAction)save:(id)sender;
- (IBAction)saveAs:(id)sender;


- (void)startNotification;

- (void)guiBecameActive:(GUI*)which;
- (void)guiClosing:(GUI*)which;
- (void)addToRecentFiles:(NSString*)added;

#define kPlistDirectory		@"~/Library/Preferences/"
#define	kRecentFiles		@"Serial Tools Recent Files"

@end
