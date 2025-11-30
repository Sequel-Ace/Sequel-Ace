//
//  SPPostgresConnectionProxy.h
//  SPPostgresFramework
//
//  Created by Mehmet Karabulut (mehmetik@gmail.com) on November 30, 2025.
//  Copyright (c) 2025 Mehmet Karabulut.
//  This software is released under the GPL License.
//  This is an open-source project forked from Sequel Ace.
//

#import <Foundation/Foundation.h>

/**
 * Connection proxy state constants.
 */
typedef enum {
	SPPostgresProxyIdle             = 0,
	SPPostgresProxyConnecting       = 1,
	SPPostgresProxyWaitingForAuth   = 2,
	SPPostgresProxyConnected        = 3,
	SPPostgresProxyForwardingFailed = 4,
	SPPostgresProxyLaunchFailed     = 5
} SPPostgresConnectionProxyState;

@protocol SPPostgresConnectionProxy <NSObject>

/**
 * All the methods for this protocol are required.
 */

/**
 * Connect the proxy.
 */
- (void)connect;

/**
 * Disconnect the proxy.
 */
- (void)disconnect;

/**
 * Get the current state of the proxy.
 */
- (SPPostgresConnectionProxyState)state;

/**
 * Get the local port being provided by the proxy.
 */ 
- (NSUInteger)localPort;

/**
 * Sets the method the proxy should call whenever the state of the connection changes.
 */
- (BOOL)setConnectionStateChangeSelector:(SEL)theStateChangeSelector delegate:(id)theDelegate;

@end
