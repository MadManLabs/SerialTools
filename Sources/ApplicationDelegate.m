//
//  ApplicationDelegate.m
//  Serial Tools
//
//  Created by Kok Chen on 4/11/09.
//  Copyright 2009 Kok Chen, W7AY. All rights reserved.
//

#import "ApplicationDelegate.h"
#import "serial.h"

@interface ApplicationDelegate ()

@property (nonatomic,copy) NSString *plistPath;
@property (nonatomic,strong) NSMutableArray *guis;
@property (nonatomic,strong) NSMutableArray *recentGUIs;
@property (nonatomic,strong) NSMutableArray *recentFiles;
@property (nonatomic,assign) int uniqueCount;
@property (nonatomic,strong) GUI *activeGUI;

@property (nonatomic,assign) IONotificationPortRef notifyPort;
@property (nonatomic,assign) CFRunLoopSourceRef runLoopSource;
@property io_iterator_t addIterator, removeIterator;

@property BOOL openedFromFile;

@end

@implementation ApplicationDelegate

- (id)init
{
	NSUserDefaults *defaults;
	NSArray *recent;
	
	self = [super init];
	if ( self ) {
		_openedFromFile = NO;
		[NSApp setDelegate:self];
		_guis = [[NSMutableArray alloc]initWithCapacity:4];
		_recentGUIs = [[NSMutableArray alloc]initWithCapacity:4];
		_uniqueCount = 1;
		_activeGUI = nil;
		//  create and update recent file array from user defaults if neccessary
		_recentFiles = [[NSMutableArray alloc]initWithCapacity:4];
		defaults = [[NSUserDefaultsController sharedUserDefaultsController]defaults];
		recent = [defaults objectForKey:kRecentFiles];
		if ( recent ) [_recentFiles addObjectsFromArray:recent];
		[self startNotification];
	}
	return self;
}

- (void)awakeFromNib
{
	[_recentMenu setDelegate:self];
	//  enable menus explicitly in menuNeedsUpdate
	[_recentMenu setAutoenablesItems:NO];
	//  start a session if it is not done by application:openFile
	[NSTimer scheduledTimerWithTimeInterval:0.75 target:self selector:@selector(openSession:) userInfo:self repeats:NO];
}

- (void)openSession:(NSTimer*)timer
{
	if ( _openedFromFile ) return;
	_openedFromFile = YES;
	[self newSession:self];
}

- (void)guiBecameActive:(GUI*)which
{
	_activeGUI = which;
	[_recentGUIs removeObject:which];
	[_recentGUIs addObject:which];
}

- (void)guiClosing:(GUI*)which
{
	int count;
	
	[_guis removeObject:which];
	[_recentGUIs removeObject:which];
	//  check recent guis and activate the most recent one (last one in array)
	count = [_recentGUIs count];
	if ( count == 0 ) {
		_activeGUI = nil;
		return;
	}
	_activeGUI = _recentGUIs[count-1];
	[_activeGUI activate];
}

- (IBAction)newSession:(id)sender
{
	GUI *gui;
	
	gui = [[GUI alloc]initWithUntitled:[NSString stringWithFormat:@"Untitled %d", _uniqueCount++]dictionary:nil];
	if ( gui ) {
        [_guis addObject:gui ];
    };
}

- (void)openPath:(NSString*)path
{
	NSString *errorString;
	NSData *xmlData;
	//NSDictionary *dict;
    id plist;
	GUI *gui;
	
    xmlData = [NSData dataWithContentsOfFile:path];
    plist = [NSPropertyListSerialization propertyListFromData:xmlData mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:&errorString];
    if (!plist) {
        NSLog(@"Oops, failed to read settings: %@",errorString);
    }
    
//	dict = (NSDictionary*)CFPropertyListCreateFromXMLData( kCFAllocatorDefault, (__bridge CFDataRef)xmlData, kCFPropertyListImmutable, (CFStringRef*)&errorString );
	if ( plist ) {
		gui = [[GUI alloc]initWithName:path dictionary:plist];
		if ( gui ) {
			_openedFromFile = YES;
			[_guis addObject:gui];
			if ( [_recentFiles containsObject:path]) {
				//  first remove existing path so that the recentFiles array is sorted with the latest in last place
				[_recentFiles removeObject:path];
			}
			[_recentFiles addObject:path];
		}
		return;
	}
	[[NSAlert alertWithMessageText:@"Could not find file." defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"\nFile may have moved or have been deleted, or of the wrong type.\n"]runModal];	
}

- (IBAction)open:(id)sender
{
	NSOpenPanel *open;
	int result;

	open = [NSOpenPanel openPanel];
	[open setAllowsMultipleSelection:NO];
	result = [open runModal];
	if ( result == NSOKButton ) {
		[self openPath: ((NSURL*)[open URLs ][0]).path];
	}
}

//  double click on sertool file
- (BOOL)application:(NSApplication*)application openFile:(NSString*)filename
{
	[self openPath:filename];
	return YES;
}

- (void)updateRecentMenu
{
	NSUserDefaults *defaults;
	NSMutableArray *newArray;
	int i, count;

	//  now set up recent files for plist
	defaults = [[NSUserDefaultsController sharedUserDefaultsController]defaults];
	//  reverse the array position
	count = [_recentFiles count];
	while ( count > 8 ) {
		[_recentFiles removeObjectAtIndex:0];
		count--;
	}
	newArray = [NSMutableArray arrayWithCapacity:count];
	for ( i = 1; i <= count; i++ ) {
		[newArray addObject:_recentFiles[count-i]];
	}
	[defaults setObject:newArray forKey:kRecentFiles];
}

- (void)addToRecentFiles:(NSString*)added
{
	[_recentFiles addObject:added];
	[self updateRecentMenu];
}

- (IBAction)save:(id)sender
{
	if ( _activeGUI ) [_activeGUI saveGUI];
}

- (IBAction)saveAs:(id)sender
{
	if ( _activeGUI ) [_activeGUI saveGUIAs];
}

- (void)recentFile:(id)sender
{
	[self openPath:[sender title]];
}

- (void)clearRecentMenu:(id)sender
{
	[_recentFiles removeAllObjects];
}

- (void)menuNeedsUpdate:(NSMenu*)menu
{
	int i, items, count;
	
	if ( menu == _recentMenu ) {
		items = [menu numberOfItems];
		for ( i = 0; i < items; i++ ) [menu removeItemAtIndex:0];
		count = [_recentFiles count];
		if ( count > 0 ) {	
			for ( i = 0; i < count; i++ ) [menu addItemWithTitle:_recentFiles[i] action:@selector(recentFile:) keyEquivalent:@""];
			[menu addItem:[NSMenuItem separatorItem]];
			[menu addItemWithTitle:@"Clear Menu" action:@selector(clearRecentMenu:) keyEquivalent:@""];
		}
	}
}

- (void)portsChanged:(Boolean)added iterator:(io_iterator_t)iterator 
{
	int i, count;
	io_object_t modemService;
	CFStringRef cfString;
	GUI *g;

	//  inform all GUI objects
	count = [_guis count];
	for ( i = 0; i < count; i++ ) {
		g = _guis[i];
		if ( g ) {
			[g serialPortsChanged:added];

			//  Report to serial port window
			while ( ( modemService = IOIteratorNext( iterator ) ) ) {
				cfString = IORegistryEntryCreateCFProperty( modemService, CFSTR( kIOTTYDeviceKey ), kCFAllocatorDefault, 0 );
				if ( cfString ) {
					[g port:(__bridge NSString*)cfString added:added];
					CFRelease( cfString );
				}
				IOObjectRelease( modemService );
			}
		}
	}
}

//  callback notification when device added
static void deviceAdded(void *refcon, io_iterator_t iterator )
{
	io_object_t modemService;
	
	if ( refcon ) {
        [(__bridge ApplicationDelegate*)refcon portsChanged:YES iterator:iterator];
    } else {
		while ( ( modemService = IOIteratorNext( iterator ) ) ) IOObjectRelease( modemService );
	}
}

static void deviceRemoved(void *refcon, io_iterator_t iterator )
{
	io_object_t modemService;
	
	if ( refcon ) {
        [(__bridge ApplicationDelegate*)refcon portsChanged:NO iterator:iterator];
    } else {
		while ( ( modemService = IOIteratorNext( iterator ) ) ) IOObjectRelease( modemService );
	}
}

- (void)startNotification
{
	CFMutableDictionaryRef matchingDict;
	
	_notifyPort = IONotificationPortCreate( kIOMasterPortDefault );
	CFRunLoopAddSource( CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource( _notifyPort ), kCFRunLoopDefaultMode );
	matchingDict = IOServiceMatching( kIOSerialBSDServiceValue );
	CFRetain( matchingDict );
	CFDictionarySetValue( matchingDict, CFSTR(kIOSerialBSDTypeKey), CFSTR( kIOSerialBSDAllTypes ) );
	
	IOServiceAddMatchingNotification( _notifyPort, kIOFirstMatchNotification, matchingDict, deviceAdded, (__bridge void *)(self), &_addIterator );
	deviceAdded( nil, _addIterator );	//  set up addIterator

	IOServiceAddMatchingNotification( _notifyPort, kIOTerminatedNotification, matchingDict, deviceRemoved, (__bridge void *)(self), &_removeIterator );
	deviceRemoved( nil, _removeIterator );	// set up removeIterator
}

- (void)stopNotification
{
	if ( _addIterator ) {
		IOObjectRelease( _addIterator );
		_addIterator = 0; 
	}
	
	if ( _removeIterator ) {
		IOObjectRelease( _removeIterator );
		_removeIterator = 0;
	}
	if ( _notifyPort ) {
		CFRunLoopRemoveSource( CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource( _notifyPort ), kCFRunLoopDefaultMode );
		IONotificationPortDestroy( _notifyPort );
		_notifyPort = nil;
	}
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender
{
	[self stopNotification];
	return NSTerminateNow;
}


@end
