//
//  GUI.h
//  Serial Tools
//
//  Created by Kok Chen on 4/11/09.
//  Copyright 2009 Kok Chen, W7AY. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "Terminal.h"

@interface GUI : NSObject <TerminalDisplayDelegate,NSTabViewDelegate,NSWindowDelegate>

@property (nonatomic,strong) IBOutlet NSWindow* window;
@property (nonatomic,strong) IBOutlet NSTabView* tab;
	
//  terminal
@property (nonatomic,strong) IBOutlet NSTextView* textView;
@property (nonatomic,strong) IBOutlet NSPopUpButton* connectButton;
@property (nonatomic,strong) IBOutlet NSPopUpButton* terminalPortMenu;
@property (nonatomic,strong) IBOutlet NSPopUpButton* baudMenu;
@property (nonatomic,strong) IBOutlet NSPopUpButton* parityMenu;
@property (nonatomic,strong) IBOutlet NSPopUpButton* bitsMenu;
@property (nonatomic,strong) IBOutlet NSPopUpButton* stopbitsMenu;
@property (nonatomic,strong) IBOutlet NSTextField* designator;
@property (nonatomic,strong) IBOutlet NSButton* crlf;
@property (nonatomic,strong) IBOutlet NSButton* rawCheckbox;
	
@property (nonatomic,strong) IBOutlet NSProgressIndicator* progressIndicator;
@property (nonatomic,strong) IBOutlet NSLevelIndicator* ctsIndicator;
@property (nonatomic,strong) IBOutlet NSButton* dsrIndicator;
@property (nonatomic,strong) IBOutlet NSButton* rtsCheckbox;
@property (nonatomic,strong) IBOutlet NSButton* dtrCheckbox;

//  monitor
@property (nonatomic,strong) IBOutlet NSTextView* monitorView;
@property (nonatomic,strong) IBOutlet NSTabView* tabMenu;
    
@property (nonatomic,strong) IBOutlet NSTextField* outboundTextField;

- (id)initWithName:(NSString*)filename dictionary:(NSDictionary*)dict;
- (id)initWithUntitled:(NSString*)filename dictionary:(NSDictionary*)dict;

- (void)activate;

- (int)findPorts;
- (void)serialPortsChanged:(BOOL)added;
- (void)port:(NSString*)name added:(BOOL)added;

- (void)saveGUI;
- (void)saveGUIAs;

- (void)setupFromPlist;
- (void)terminalParamsChanged:(id)sender;

- (IBAction)sendOutboundText:(id)sender;

#define kGUIWindowPosition		@"GUI Position"
#define kTermWindowPosition		@"Term Position"
#define	kGUIDomain				@"w7ay.Serial Tools"
#define	kTerminalPort			@"Terminal Serial Port"
#define	kTerminalBaudRate		@"Terminal Baud Rate"
#define	kTerminalBits			@"Terminal Bits"
#define	kTerminalStopbits		@"Terminal Stop Bits"
#define	kTerminalParity			@"Terminal Parity"
#define	kTerminalCRLF			@"Terminal Send CRLF"
#define	kTerminalRaw			@"Terminal Raw"
#define	kTerminalRTS			@"Terminal RTS"
#define	kTerminalDTR			@"Terminal DTR"

#define	kTool					@"GUI Tool"

@end
