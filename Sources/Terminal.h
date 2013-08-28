//
//  Terminal.h
//  Serial Tools
//
//  Created by Kok Chen on 4/11/09.
//  Copyright 2009  Kok Chen, W7AY. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@protocol TerminalDisplayDelegate;

@interface Terminal : NSObject

@property (nonatomic,unsafe_unretained) id<TerminalDisplayDelegate> display;

- (void)initTerminal ;

- (BOOL)openConnections:(const char*)port baudrate:(int)baud bits:(int)bits parity:(int)parity stopBits:(int)stops ;
- (BOOL)openInputConnection:(const char*)port baudrate:(int)baud bits:(int)bits parity:(int)parity stopBits:(int)stops ;
- (BOOL)openOutputConnection:(const char*)port baudrate:(int)baud bits:(int)bits parity:(int)parity stopBits:(int)stops ;

- (void)closeConnections ;
- (void)closeInputConnection ;
- (void)closeOutputConnection ;

- (BOOL)connected ;
- (BOOL)inputConnected ;
- (BOOL)outputConnected ;

- (int)inputFileDescriptor ;
- (int)outputFileDescriptor ;

- (void)setCrlfEnable:(Boolean)state ;
- (BOOL)crlfEnabled ;

- (void)setRawEnable:(Boolean)state ;

- (int)getTermios ;
- (void)setRTS:(Boolean)state ;
- (void)setDTR:(Boolean)state ;

- (void)transmitCharacters:(NSString*)string;

int openPort( const char *path, int speed, int bits, int parity, int stops, int openFlags, Boolean input ) ;

@end

@protocol TerminalDisplayDelegate <NSObject>

@required
- (void)appendStringToDisplay:(NSString*)string;

@end
