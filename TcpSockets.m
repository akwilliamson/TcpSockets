/**
 * Copyright (c) 2015-present, Peel Technologies, Inc.
 * All rights reserved.
 */

#import <React/RCTAssert.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTConvert.h>
#import <React/RCTLog.h>

#import "TcpSockets.h"
#import "TcpSocketClient.h"

// offset native ids by 5000
#define COUNTER_OFFSET 5000

@implementation TcpSockets {
	NSMutableDictionary<NSNumber *,TcpSocketClient *> *_clients;
	int _counter;
}

RCT_EXPORT_MODULE()

- (NSArray<NSString *> *)supportedEvents {
	return @[@"connect", @"connection", @"data", @"close", @"error"];
}

- (void)startObserving { /* Does nothing */ }
- (void)stopObserving { /* Does nothing */ }

-(void)dealloc {
	for (NSNumber *cId in _clients.allKeys) {
		[self destroyClient:cId];
	}
}

- (TcpSocketClient *)createSocket:(nonnull NSNumber*)cId {
	if (!cId) { RCTLogWarn(@"%@.createSocket called with nil id parameter.", [self class]); return nil; }
	if (!_clients) { _clients = [NSMutableDictionary new]; }
	if (_clients[cId]) { RCTLogWarn(@"%@.createSocket called twice with the same id.", [self class]); return nil; }
	
	_clients[cId] = [TcpSocketClient socketClientWithId:cId andConfig:self];
	
	return _clients[cId];
}

RCT_EXPORT_METHOD(connect:(nonnull NSNumber*)cId host:(NSString *)host port:(int)port withOptions:(NSDictionary *)options) {
	TcpSocketClient *client = _clients[cId];
	if (!client) { client = [self createSocket:cId]; }
	
	NSError *error = nil;
	if (![client connect:host port:port withOptions:options error:&error]) {
		[self onError:client withError:error];
		return;
	}
}

RCT_EXPORT_METHOD(write:(nonnull NSNumber*)cId string:(NSString *)base64String callback:(RCTResponseSenderBlock)callback) {
	TcpSocketClient* client = [self findClient:cId];
	if (!client) return;
	
	// iOS7+
	// TODO: use https://github.com/nicklockwood/Base64 for compatibility with earlier iOS versions
	NSData *data = [[NSData alloc] initWithBase64EncodedString:base64String options:0];
	[client writeData:data callback:callback];
}

RCT_EXPORT_METHOD(end:(nonnull NSNumber*)cId) {
	[self endClient:cId];
}

RCT_EXPORT_METHOD(destroy:(nonnull NSNumber*)cId) {
	[self destroyClient:cId];
}

- (void)onConnect:(TcpSocketClient*) client {
	[self sendEventWithName:@"connect" body:@{ @"id": client.id, @"address" : [client getAddress] }];
}

-(void)onConnection:(TcpSocketClient *)client toClient:(NSNumber *)clientID {
	_clients[client.id] = client;
	[self sendEventWithName:@"connection" body:@{ @"id": clientID, @"info": @{ @"id": client.id } }];
}

- (void)onData:(NSNumber *)clientID data:(NSData *)data {
	[self sendEventWithName:@"data" body:@{ @"id": clientID, @"data" : [data base64EncodedStringWithOptions:0] }];
}

- (void)onClose:(NSNumber*) clientID withError:(NSError *)err {
	TcpSocketClient* client = [self findClient:clientID];
	if (!client) { RCTLogWarn(@"onClose: unrecognized client id %@", clientID); }
	
	if (err) {
		[self onError:client withError:err];
	}
	
	[self sendEventWithName:@"close" body:@{ @"id": clientID, @"hadError": err == nil ? @NO : @YES }];
	
	[_clients removeObjectForKey:clientID];
}

- (void)onError:(TcpSocketClient*) client withError:(NSError *)err {
	NSString *msg = err.localizedFailureReason ?: err.localizedDescription;
	[self sendEventWithName:@"error" body:@{ @"id": client.id, @"error": msg }];
}

-(TcpSocketClient*)findClient:(nonnull NSNumber*)cId {
	TcpSocketClient *client = _clients[cId];
	if (!client) {
		NSString *msg = [NSString stringWithFormat:@"no client found with id %@", cId];
		[self sendEventWithName:@"error" body:@{ @"id": cId, @"error": msg }];
		
		return nil;
	}
	return client;
}

-(void)endClient:(nonnull NSNumber*)cId {
	TcpSocketClient* client = [self findClient:cId];
	if (!client) return;
	
	[client end];
}

-(void)destroyClient:(nonnull NSNumber*)cId {
	TcpSocketClient* client = [self findClient:cId];
	if (!client) return;
	
	[client destroy];
}

-(NSNumber*)getNextId {
	return @(_counter++ + COUNTER_OFFSET);
}

@end
