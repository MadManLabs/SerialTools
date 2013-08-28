
//
//  Terminal.m
//  Serial Tools
//
//  Created by Kok Chen on 4/11/09.
//  Copyright 2009  Kok Chen, W7AY. All rights reserved.
//

#import "Terminal.h"
#include <sys/select.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <unistd.h>

@interface Terminal () {
	int outputfd;
	int inputfd;
	BOOL crlf;
	BOOL raw;
}

@end

@implementation Terminal

//  Terminal.m is handles the communication through a serial port.
//  Anything that comes in is displayed passed on to the view.
//
//  Use -openInputConnection and -openOutputConnection to open either direction of the serial port, or -openConnections to open both directions.
//  Close the ports with -closeInputConnection, -closeOutputConnection or -closeConnections.
//
//  Use -setCrlfEnable to convert outgoing newlines to cr/lf pairs.

//  common init code
- (void)initTerminal
{
	inputfd = outputfd = -1;
	crlf = raw = NO;
}

- (id)init
{
	self = [super init];
    if (self) {
        [self initTerminal];
    }
	return self;
}

- (int)getTermios
{
	int bits;
	
	if ( inputfd ) {
		ioctl( inputfd, TIOCMGET, &bits );
		return bits;
	}
	return 0;
}

- (void)setRTS:(Boolean)state
{
	int bits;

	if ( inputfd ) {
		ioctl( inputfd, TIOCMGET, &bits );
		if ( state ) bits |= TIOCM_RTS; else bits &= ~( TIOCM_RTS );
		ioctl( inputfd, TIOCMSET, &bits );
	}
}

- (void)setDTR:(Boolean)state
{
	int bits;

	if ( inputfd ) {
		ioctl( inputfd, TIOCMGET, &bits );
		if ( state ) bits |= TIOCM_DTR; else bits &= ~( TIOCM_DTR );
		ioctl( inputfd, TIOCMSET, &bits );
	}
}

//  common function to open port and set up serial port parameters
int openPort( const char *path, int speed, int bits, int parity, int stops, int openFlags, Boolean input )
{
	int fd, cflag;
	struct termios termattr;
	
	fd = open( path, openFlags );
	if ( fd < 0 ) {
        return -1;
    }
	
	//  build other flags
	cflag = 0;
	cflag |= ( bits == 7 ) ? CS7 : CS8;			//  bits
	if ( parity != 0 ) {
		cflag |= PARENB;							//  parity
		if ( parity == 1 ) cflag |= PARODD;
	}
	if ( stops > 1 ) {
        cflag |= CSTOPB;   
    }
	
	//  merge flags into termios attributes
	tcgetattr( fd, &termattr );
	termattr.c_cflag &= ~( CSIZE | PARENB | PARODD | CSTOPB );	// clear all bits and merge in our selection
	termattr.c_cflag |= cflag;
	
	// set speed, split speed not support on Mac OS X?
	cfsetispeed( &termattr, speed );
	cfsetospeed( &termattr, speed );
	//  set termios
	tcsetattr( fd, TCSANOW, &termattr );

	return fd;
}

- (BOOL)openInputConnection:(const char*)port baudrate:(int)baud bits:(int)bits parity:(int)parity stopBits:(int)stops
{
	[self closeInputConnection];		//  v0.2  sanity check
	
	inputfd = openPort( port, baud, bits, parity, stops, ( O_RDONLY | O_NOCTTY | O_NDELAY ), YES );
	if ( inputfd < 0 ) {
        return NO;
    }
	
	//  If the input is opened successfully, start a thread to monitor characters from it and echoing received
	//  characters to the text view.
	[NSThread detachNewThreadSelector:@selector(readThread) toTarget:self withObject:nil];

	return YES;
}

- (void)closeInputConnection
{
	if ( inputfd > 0 ) {
        close( inputfd );
    }
	inputfd = -1;
}

- (BOOL)openOutputConnection:(const char*)port baudrate:(int)baud bits:(int)bits parity:(int)parity stopBits:(int)stops
{	
	[self closeOutputConnection];	//  v0.2  sanity check
	
	outputfd = openPort( port, baud, bits, parity, stops, ( O_WRONLY | O_NOCTTY | O_NDELAY ), NO );
	return ( outputfd > 0 );
}

- (void)closeOutputConnection
{
	if ( outputfd >= 0 ) {
        close( outputfd );
    }
	outputfd = -1;
}

- (BOOL)inputConnected
{
	return ( inputfd > 0 );
}

- (BOOL)outputConnected
{
	return ( outputfd > 0 );
}

- (BOOL)connected
{
	return ( [self inputConnected]&& [self outputConnected]);
}


- (BOOL)openConnections:(const char*)port baudrate:(int)baud bits:(int)bits parity:(int)parity stopBits:(int)stops
{
	inputfd = openPort( port, baud, bits, parity, stops, ( O_RDONLY | O_NOCTTY | O_NDELAY ), YES );
	if ( inputfd < 0 ) return NO;	
		
	outputfd = openPort( port, baud, bits, parity, stops, ( O_WRONLY | O_NOCTTY | O_NDELAY ), NO );
	if ( outputfd < 0 ) {
		[self closeInputConnection];
		return NO;
	}
	//  start the read thread
	[NSThread detachNewThreadSelector:@selector(readThread) toTarget:self withObject:nil];
	return YES;
}

 - (void)closeConnections
 {
	[self closeInputConnection];
	[self closeOutputConnection];
 }

- (int)inputFileDescriptor
{
	return inputfd;
}

- (int)outputFileDescriptor
{
	return outputfd;
}

- (void)setRawEnable:(Boolean)state
{
	raw = state;
}

- (void)setCrlfEnable:(Boolean)state
{
	crlf = state;
}

- (BOOL)crlfEnabled
{
	return crlf;
}

- (void)transmitCharacters:(NSString*)string
{
	const char *s;
	char alt[2];
	int length;
	
	if ( outputfd >= 0 ) {
		s = [string cStringUsingEncoding:NSASCIIStringEncoding];
		if ( s && ( length = [string length]) > 0 ) {
			switch ( *s ) {
			case 13:
				if ( crlf ) {
					//  add linefeed to carriage return
					alt[0] = 13;
					alt[1] = 10;
					write( outputfd, alt, 2 );
					s++;
					length--;
				}
				break;
			}
			if ( *s && length > 0 ) write( outputfd, s, length );
		}
	}
}

//  insert input (called into the main runloop from -readThread to avoid ThreadSafe issues of NSView).
- (void)insertInput:(NSString*)string
{
    [_display appendStringToDisplay:string];
}

//  thread that loops on a select() call, waiting for input (so that the main thread does not block)
- (void)readThread
{
	@autoreleasepool {
		NSString *string;
		fd_set readfds, basefds, errfds;
		int selectCount, bytesRead, rawBytes, i, v;
		char buffer[1024], rawBuffer[4096], *s, tstr[8];
		
		FD_ZERO( &basefds );
		FD_SET( inputfd, &basefds );	
		while ( 1 ) {	
			FD_COPY( &basefds, &readfds );
			FD_COPY( &basefds, &errfds );
			selectCount = select( inputfd+1, &readfds, NULL, &errfds, nil );
			if ( selectCount > 0 ) {
				if ( FD_ISSET( inputfd, &errfds ) ) break;		//  exit if error in stream
				if ( selectCount > 0 && FD_ISSET( inputfd, &readfds ) ) {
					//  read into buffer, cnvert to NSString and send to the NSTextView.
					[NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];	// v0.2
					bytesRead = read( inputfd, buffer, 1024 );
					if ( raw ) {
						rawBytes = 0;
						for ( i = 0; i < bytesRead; i++ ) {
							v = buffer[i] & 0xff;
							if ( v < 32 || v > 0x7f ) {
								sprintf( tstr, "<%02X>", v );
								s = tstr;
								while ( *s ) rawBuffer[rawBytes++] = *s++;
							}
							else {
								rawBuffer[rawBytes++] = v;
							}
						}
						string = [[NSString alloc]initWithBytes:rawBuffer length:rawBytes encoding:NSASCIIStringEncoding];
					}
					else {
						string = [[NSString alloc]initWithBytes:buffer length:bytesRead encoding:NSASCIIStringEncoding];
					}
					[self performSelectorOnMainThread:@selector(insertInput:) withObject:string waitUntilDone:NO]; // v0.2
				}
			}
		}
		[self closeInputConnection];			//  v0.2  use this instead of close()
	};
}

@end
