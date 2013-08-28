//
//  GUI.m
//  Serial Tools
//
//  Created by Kok Chen on 4/11/09.
//  Copyright 2009 Kok Chen, W7AY. All rights reserved.
//

#import "GUI.h"
#import "ApplicationDelegate.h"
#include "serial.h"
#import "Terminal.h"
#include <termios.h>

int historyIndex = -1;

@interface GUI () {
    //  serial ports
    NSString *stream[32];
    NSString *path[32];
}

@property (nonatomic,strong) Terminal *terminal;

@property (nonatomic,strong) NSLock *termioLock;

@property (nonatomic,copy) NSString *filename;
@property (nonatomic,strong) NSMutableDictionary *dictionary, *initialDictionary;
@property (nonatomic,copy) NSString *originalTerminalPort;
@property (nonatomic,strong) NSMutableArray *commandHistory;


@property BOOL unnamed;
@property BOOL terminalOpened;
@property int displayBacklog;

@end

@implementation GUI

- (id)initWithName:(NSString*)fname dictionary:(NSDictionary*)dict
{
	self = [super init];
	if ( self ) {
        [self initCommon:NO name:fname plist:dict];
    }
	return self;
}

- (id)initWithUntitled:(NSString*)fname dictionary:(NSDictionary*)dict
{
	self = [super init];
	if ( self ) {
        [self initCommon:YES name:fname plist:dict];
    }
	return self;
}

- (void)initCommon:(BOOL)iUnnamed name:(NSString*)fname plist:(NSDictionary*)dict
{
	_filename = fname;
	_displayBacklog = 0;
	_unnamed = iUnnamed;
	_terminalOpened = NO;
    _commandHistory = [[NSMutableArray alloc]init];
    _terminal = [[Terminal alloc]init];
	
	_termioLock = [[NSLock alloc]init];
	
	//  dictionary for plist items
	_dictionary = [[NSMutableDictionary alloc]initWithCapacity:8];		//  v0.2 was initing with nil dictionary
	//  create initial values for dictionary
	_dictionary[kTool]= @0;
	_dictionary[kTerminalPort]= @"";
	_dictionary[kTerminalBaudRate]= @4608;
	_dictionary[kTerminalBits]= @8;
	_dictionary[kTerminalStopbits]= @1;
	_dictionary[kTerminalParity]= @0;
	_dictionary[kTerminalCRLF]= @YES;
	_dictionary[kTerminalRaw]= @NO;
	_dictionary[kTerminalRTS]= @NO;
	_dictionary[kTerminalDTR]= @NO;
	
	//  now merge in any plist that is passed in
	if ( dict ) {
        [_dictionary addEntriesFromDictionary:dict];
    }
	_initialDictionary = [[NSMutableDictionary alloc]initWithDictionary:_dictionary];
	
	_originalTerminalPort = dict[kTerminalPort];
	if ( _originalTerminalPort == nil ) {
        _originalTerminalPort = @"";
    }

    [NSBundle loadNibNamed:@"GUI" owner:self];
}

- (void)setInterface:(NSControl*)object to:(SEL)selector
{
	[object setAction:selector];
	[object setTarget:self];
}

- (void)awakeFromNib
{
	int count, i;
	
	[self setupFromPlist];
	
	[_window setTitle:_filename];
	[_window setDelegate:self];
	[_window makeKeyAndOrderFront:self];
	
	[_tabMenu setDelegate:self];
	
	[self setInterface:_baudMenu to:@selector(terminalParamsChanged:)];
	[self setInterface:_parityMenu to:@selector(terminalParamsChanged:)];
	[self setInterface:_bitsMenu to:@selector(terminalParamsChanged:)];
	[self setInterface:_stopbitsMenu to:@selector(terminalParamsChanged:)];
	[self setInterface:_connectButton to:@selector(connectButtonChanged:)];
	[self setInterface:_rtsCheckbox to:@selector(rtsCheckboxChanged:)];
	[self setInterface:_dtrCheckbox to:@selector(dtrCheckboxChanged:)];
	[self setInterface:_crlf to:@selector(crlfChanged:)];
	[self setInterface:_rawCheckbox to:@selector(rawCheckboxChanged:)];

	[_progressIndicator setUsesThreadedAnimation:YES];
	
	//  terminal window
    _terminal.display = self;
	[self terminalParamsChanged:self];
    
    NSLog(@"terminal isSelectable: %@",[_textView isSelectable]? @"YES" : @"NO");
	
	count = [self findPorts];
	for ( i = 0; i < count; i++ ) {
		[_monitorView insertText:stream[i]];
		[_monitorView insertText:@"\n"];
	}	
	[NSThread detachNewThreadSelector:@selector(terminalControlThread) toTarget:self withObject:nil];
}

- (void)terminalControlThread
{
	@autoreleasepool {
		int termbits, bit;

		while ( 1 ) {
			if ( _terminalOpened ) {
				if ( [_termioLock tryLock]) {
					termbits = [_terminal getTermios];
					bit = ( ( termbits & TIOCM_CTS ) != 0 ) ? 1 : 0;
					if ( [_ctsIndicator intValue]!= bit ) [_ctsIndicator setIntValue:bit];
					bit = ( ( termbits & TIOCM_DSR ) != 0 ) ? 1 : 0;
					if ( [_dsrIndicator intValue]!= bit ) [_dsrIndicator setIntValue:bit];
					[_termioLock unlock];
				}
				[NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
			}
			else {
				if ( [_ctsIndicator intValue]!= 0 ) [_ctsIndicator setIntValue:0];
				if ( [_dsrIndicator intValue]!= 0 ) [_dsrIndicator setIntValue:0];
				[NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
			}
		}
    }
}

- (void)activate
{
	[_window makeKeyAndOrderFront:self];
}
	
- (NSString*)shortName:(NSString*)longName
{
	NSArray *components;
	NSString *reply;
	int n;
	
	components = [longName pathComponents];
	n = [components count];
	if ( n < 3 ) {
		return [longName lastPathComponent];
	}
	reply = [@"..." stringByAppendingPathComponent:components[n-2]];	
	return [reply stringByAppendingPathComponent:components[n-1]];
}

- (int)findPorts
{
	CFStringRef cstream[32], cpath[32];
	int i, count;
	
	count = findPorts( cstream, cpath, 32 );
	for ( i = 0; i < count; i++ ) {
		stream[i]= [NSString stringWithString:(__bridge NSString*)cstream[i]];
		CFRelease( cstream[i]);
		path[i]= [NSString stringWithString:(__bridge NSString*)cpath[i]];
		CFRelease( cpath[i]);
	}
	return count;
}

- (void)setupFromPlist
{
	int i, items;
	NSString *windowPosition;
			
	items = [self findPorts];
	//  terminal port menu
	[_terminalPortMenu removeAllItems];
	for ( i = 0; i < items; i++ ) [_terminalPortMenu addItemWithTitle:stream[i]];
	[_terminalPortMenu selectItemWithTitle: _dictionary[kTerminalPort]];
	i = [_terminalPortMenu indexOfSelectedItem];
	if ( i < 0 ) [_terminalPortMenu selectItemAtIndex:0];
	
	[_tab selectTabViewItemAtIndex:[_dictionary[kTool]intValue]];
	
	[_baudMenu selectItemWithTag:[_dictionary[kTerminalBaudRate]intValue]/100];
	[_bitsMenu selectItemWithTag:[_dictionary[kTerminalBits]intValue]];
	[_parityMenu selectItemWithTag:[_dictionary[kTerminalParity]intValue]];
	[_stopbitsMenu selectItemWithTag:[_dictionary[kTerminalStopbits]intValue]];
	[_crlf setState:[_dictionary[kTerminalCRLF]boolValue]? NSOnState : NSOffState];
	[_rawCheckbox setState:[_dictionary[kTerminalRaw]boolValue]? NSOnState : NSOffState];
	[_rtsCheckbox setState:[_dictionary[kTerminalRTS]boolValue]? NSOnState : NSOffState];
	[_dtrCheckbox setState:[_dictionary[kTerminalDTR]boolValue]? NSOnState : NSOffState];

	//  set up window positions if they exist
	windowPosition = _dictionary[kGUIWindowPosition];
	if ( windowPosition ) [_window setFrameFromString:windowPosition];
}

- (NSString*)browseForField:(NSTextField*)textField key:(NSString*)key isDirectory:(BOOL)dir
{
	NSOpenPanel *panel;
	NSString *fullPath;
    NSString *partialPath;
	int result;
	
	panel = [NSOpenPanel openPanel];
	[panel setCanChooseDirectories:dir];
	[panel setCanChooseFiles:!dir];
	[panel setCanCreateDirectories:dir];
	
	result = [panel runModal];
	if ( result == NSOKButton ) {
		fullPath = [panel URL].path;
		partialPath = [self shortName:fullPath];
	}
	else {
		fullPath = partialPath = @"";
	}
	_dictionary[key]= fullPath;
	[textField setStringValue:fullPath];
	return partialPath;
}

- (void)closeTerminal
{
	[_terminal closeConnections];
	_terminalOpened = NO;
}

- (void)disconnectTerminal
{
	if ( _terminalOpened ) {
		[self closeTerminal];
		[_connectButton setTitle:@"Connect"];
		[_connectButton display];
	}
}

- (void)rtsCheckboxChanged:(id)sender
{
	if ( _terminalOpened ) {
		[_termioLock lock];
		[_terminal setRTS:( [_rtsCheckbox state]== NSOnState )];
		[_termioLock unlock];
	}
}

- (void)dtrCheckboxChanged:(id)sender
{
	if ( _terminalOpened ) {
		[_termioLock lock];
		[_terminal setDTR:( [_dtrCheckbox state]== NSOnState )];
		[_termioLock unlock];
	}
}

- (void)connectTerminal
{
	int index;
	const char *port;
	BOOL opened;
	
	if ( _terminalOpened == NO ) {
		
		[_progressIndicator startAnimation:self];
		
		//  check if serial port is selected
		index = [_terminalPortMenu indexOfSelectedItem];
		if ( index < 0 ) {
			[[NSAlert alertWithMessageText:[NSString stringWithFormat:@"Serial Port for terminal emulator not selected."]defaultButton:@"OK" alternateButton:nil otherButton:nil 
				informativeTextWithFormat:@"Please select the serial port in the Serial Port popup menu in the Terminal tab."]runModal];
			[_progressIndicator stopAnimation:self];
			return;
		}
		
		port = [path[index]cStringUsingEncoding:NSASCIIStringEncoding];
		opened = [_terminal openConnections:port baudrate:[[_baudMenu selectedItem]tag]*100 bits:[[_bitsMenu selectedItem]tag]parity:[[_parityMenu selectedItem]tag]stopBits:[[_stopbitsMenu selectedItem]tag]];
		
		if ( opened == NO ) {
			[[NSAlert alertWithMessageText:[NSString stringWithFormat:@"Cannot open terminal port."]defaultButton:@"OK" alternateButton:nil otherButton:nil 
				informativeTextWithFormat:@"The selected terminal port would not open."]runModal];
			[_progressIndicator stopAnimation:self];
			return;
		}
		
		//  successful open connection
		_terminalOpened = YES;
		[_terminal setCrlfEnable:( [_crlf state]== NSOnState )];
		[_terminal setRawEnable:( [_rawCheckbox state]== NSOnState )];
		[self rtsCheckboxChanged:_rtsCheckbox];
		[self dtrCheckboxChanged:_dtrCheckbox];

		[_connectButton setTitle:@"Disconnect"];
		[_progressIndicator stopAnimation:self];
	}
}

- (void)crlfChanged:(id)sender
{
	if ( _terminalOpened ) {
        [_terminal setCrlfEnable:( [_crlf state]== NSOnState )];
    }
}

- (void)rawCheckboxChanged:(id)sender
{
	if ( _terminalOpened ) {
        [_terminal setRawEnable:( [_rawCheckbox state]== NSOnState )];
    }
}

- (void)connectButtonChanged:(id)sender;
{
	if ( _terminalOpened ) {
        [self disconnectTerminal];
    } else {
        [self connectTerminal];   
    }
}

- (void)terminalParamsChanged:(id)sender
{
	int baudRate, bits, stopbits;
	char parity;
	BOOL wasConnected;
	
	wasConnected = _terminalOpened;
	if ( wasConnected ) [_connectButton setEnabled:NO];
	[self disconnectTerminal];
	
	baudRate = [[_baudMenu selectedItem]tag]*100;
	switch ( [[_parityMenu selectedItem]tag]) {
	case 0:
	default:
		parity = 'N';
		break;
	case 1:
		parity = 'O';
		break;
	case 2:
		parity = 'E';
		break;
	}
	bits = [[_bitsMenu selectedItem]tag];
	stopbits = [[_stopbitsMenu selectedItem]tag];
	
	[_designator setStringValue:[NSString stringWithFormat:@"%d / %d-%c-%d", baudRate, bits, parity, stopbits]];
	
	if ( wasConnected ) {
        [self connectTerminal];
    }
    
	[_connectButton setEnabled:YES];
	[_connectButton display];
}

static int hex( NSString *str )
{
	int value;
	
	sscanf( [str cStringUsingEncoding:NSASCIIStringEncoding], "%x", &value );
	return value & 0xff;
}

- (void)setTextField:(NSTextField*)field forKey:(NSString*)key
{
	_dictionary[key]= [field stringValue];
}

- (void)setPopUpButton:(NSPopUpButton*)field forKey:(NSString*)key alternative:(NSString*)alt
{
	NSString *title;
	
	title = [field titleOfSelectedItem];
	if ( title == nil ) title = alt;
	_dictionary[key]= title;
}

- (void)updatePlist
{
	[self setPopUpButton:_terminalPortMenu forKey:kTerminalPort alternative:_originalTerminalPort];

	_dictionary[kTool]= [NSNumber numberWithInt:[_tab indexOfTabViewItem:[_tab selectedTabViewItem]]];	

	_dictionary[kTerminalBaudRate]= [NSNumber numberWithInt:[[_baudMenu selectedItem]tag]*100];
	_dictionary[kTerminalBits]= [NSNumber numberWithInt:[[_bitsMenu selectedItem]tag]];
	_dictionary[kTerminalParity]= [NSNumber numberWithInt:[[_parityMenu selectedItem]tag]];
	_dictionary[kTerminalStopbits]= [NSNumber numberWithInt:[[_stopbitsMenu selectedItem]tag]];
	_dictionary[kTerminalCRLF]= [NSNumber numberWithBool:( [_crlf state]== NSOnState )];
	_dictionary[kTerminalRaw]= [NSNumber numberWithBool:( [_rawCheckbox state]== NSOnState )];
	_dictionary[kTerminalRTS]= [NSNumber numberWithBool:( [_rtsCheckbox state]== NSOnState )];
	_dictionary[kTerminalDTR]= [NSNumber numberWithBool:( [_dtrCheckbox state]== NSOnState )];
}

//  local
- (void)save
{
	[self updatePlist];		//  v0.2
	[_dictionary writeToFile:_filename atomically:YES];
	//  make the save dictionay our "initial" dictionary
	_initialDictionary = [[NSMutableDictionary alloc]initWithDictionary:_dictionary];
}

- (void)saveGUI
{
	if ( _unnamed ) [self saveGUIAs]; else [self save];
}

- (void)saveGUIAs
{
	NSSavePanel *panel;
	int resultCode;
	
	panel = [NSSavePanel savePanel];
	[panel setTitle:@"Save..."];   
	[panel setAllowedFileTypes:@[@"sertool"]];
	
    //resultCode = [panel runModalForDirectory:nil file:[filename lastPathComponent]];
    resultCode = [panel runModal];
	if ( resultCode != NSOKButton ) return;
	
	_filename = [panel URL].path;
	[self save];
	
	[_window setTitle:_filename];
	[(ApplicationDelegate*)[NSApp delegate]addToRecentFiles:_filename];
	_unnamed = NO;
}

- (IBAction)clear:(id)sender
{
}

//  window delegate
- (void)windowDidBecomeMain:(NSNotification *)notification
{
	[(ApplicationDelegate*)[NSApp delegate]guiBecameActive:self];
}

//  window delegate
- (BOOL)windowShouldClose:(id)win
{
	BOOL closing = YES;
	
	[self closeTerminal];
	//closing = [self shouldTerminate];
	if ( closing ) [[NSApp delegate]guiClosing:self];
	return closing;
}

- (void)serialPortsChanged:(BOOL)added
{
	NSString *selectedTitle;
	int i, items;
	
	[self disconnectTerminal];
	
	items = [self findPorts];			
	if ( [_terminalPortMenu indexOfSelectedItem]>= 0 ) {
		selectedTitle = [_terminalPortMenu titleOfSelectedItem];
		//  get current streams
		[_terminalPortMenu removeAllItems];
		for ( i = 0; i < items; i++ ) [_terminalPortMenu addItemWithTitle:stream[i]];
		[_terminalPortMenu selectItemWithTitle:selectedTitle];
		if ( [_terminalPortMenu indexOfSelectedItem]< 0 ) {
			[[NSAlert alertWithMessageText:[NSString stringWithFormat:@"Selected terminal Port disappeared."]defaultButton:@"OK" alternateButton:nil otherButton:nil 
				informativeTextWithFormat:@"Please select a different port in the Terminal Port popup menu in the Terminal tab."]runModal];
		}
	}
}

- (IBAction)sendOutboundText:(id)sender {
    NSString *outString = [_outboundTextField stringValue];
    [_terminal transmitCharacters: [NSString stringWithFormat:@"%@\r",outString]];
    if (![outString isEqualToString:@""]) {
        [_commandHistory addObject: outString];
        [_outboundTextField setStringValue:@""];
        historyIndex = [_commandHistory count];
    }
}

#pragma mark NSTextViewDelegate Methods
- (BOOL)control:(NSControl *)control textView:(NSTextView *)fieldEditor doCommandBySelector:(SEL)commandSelector
{
    if (commandSelector == @selector(moveUp:) ){
        if ([_commandHistory count]> 0) {
            if (historyIndex == -1) {
                historyIndex = [_commandHistory count];
            }
            if (historyIndex > 0) {
                historyIndex--;
                [_outboundTextField setStringValue:_commandHistory[historyIndex]];
                [[_outboundTextField currentEditor]setSelectedRange:NSMakeRange([[_outboundTextField stringValue]length], 0)];
            } else {
                NSBeep();
            }
        } else {
            NSBeep();
        }
        return YES;    // We handled this command; don't pass it on
    }
    if (commandSelector == @selector(moveDown:) ){
        if ([_commandHistory count]> 0) {
            if (historyIndex == -1) {
                historyIndex = [_commandHistory count];
            } else if (historyIndex == [_commandHistory count]) {
                NSBeep();
            } else if (historyIndex == [_commandHistory count]- 1) {
                [_outboundTextField setStringValue:@""];
                historyIndex = [_commandHistory count];
            } else {
                historyIndex++;
                [_outboundTextField setStringValue:_commandHistory[historyIndex]];
                [[_outboundTextField currentEditor]setSelectedRange:NSMakeRange([[_outboundTextField stringValue]length], 0)];
            }
        } else {
            NSBeep();
        }
        return YES;
    }
    
    return NO;
}

#pragma mark NSTabViewDelegate Methods
- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem*)item
{
}


#pragma mark Monitor

- (void)port:(NSString*)name added:(BOOL)added
{
	[_monitorView insertText:@"--------------\n"];
	[_monitorView insertText:( added ) ? @"Added : " : @"Removed : "];
	[_monitorView insertText:name];
	[_monitorView insertText:@"\n--------------\n"];
}

#pragma mark TerminalDisplayDelegate
- (void)appendStringToDisplay:(NSString *)string
{
    [_textView.textStorage.mutableString appendString:string];
    [_textView setFont:[NSFont fontWithName:@"Monaco" size:12]];
    [_textView scrollToEndOfDocument:self];
}

@end
