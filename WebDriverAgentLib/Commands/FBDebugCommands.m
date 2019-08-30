/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDebugCommands.h"

#import "FBApplication.h"
#import "FBRouteRequest.h"
#import "FBSession.h"
#import "XCUIApplication+FBHelpers.h"
#import "XCUIElement+FBUtilities.h"
#import "FBXPath.h"
#import "FBXCTestDaemonsProxy.h"
#import "XCTestManager_ManagerInterface-Protocol.h"
#import "XCAccessibilityElement.h"

@implementation FBDebugCommands

#pragma mark - <FBCommandHandler>

+ (NSArray *)routes
{
  return
  @[
    [[FBRoute GET:@"/source"] respondWithTarget:self action:@selector(handleGetSourceCommand:)],
    [[FBRoute GET:@"/source"].withoutSession respondWithTarget:self action:@selector(handleGetSourceCommand:)],
    [[FBRoute GET:@"/wda/accessibleSource"] respondWithTarget:self action:@selector(handleGetAccessibleSourceCommand:)],
    [[FBRoute GET:@"/wda/accessibleSource"].withoutSession respondWithTarget:self action:@selector(handleGetAccessibleSourceCommand:)],
    [[FBRoute GET:@"/appTerminate"].withoutSession respondWithTarget:self action:@selector(handleGetAppTerminateCommand:)],
    [[FBRoute GET:@"/appStateRunningForeground"].withoutSession respondWithTarget:self action:@selector(handleGetAppStateRunningForegroundCommand:)],
    [[FBRoute GET:@"/appAtPoint"].withoutSession respondWithTarget:self action:@selector(handleGetAppAtPointCommand:)],
  ];
}


#pragma mark - Commands

static NSString *const SOURCE_FORMAT_XML = @"xml";
static NSString *const SOURCE_FORMAT_JSON = @"json";
static NSString *const SOURCE_FORMAT_DESCRIPTION = @"description";

+ (id<FBResponsePayload>)handleGetSourceCommand:(FBRouteRequest *)request
{
  FBApplication *application = request.session.activeApplication ?: [FBApplication fb_activeApplication];
  NSString *sourceType = request.parameters[@"format"] ?: SOURCE_FORMAT_XML;
  id result;
  if ([sourceType caseInsensitiveCompare:SOURCE_FORMAT_XML] == NSOrderedSame) {
    result = application.fb_xmlRepresentation;
  } else if ([sourceType caseInsensitiveCompare:SOURCE_FORMAT_JSON] == NSOrderedSame) {
    result = application.fb_tree;
  } else if ([sourceType caseInsensitiveCompare:SOURCE_FORMAT_DESCRIPTION] == NSOrderedSame) {
    result = application.fb_descriptionRepresentation;
  } else {
    return FBResponseWithStatus(
      FBCommandStatusUnsupported,
      [NSString stringWithFormat:@"Unknown source format '%@'. Only %@ source formats are supported.",
       sourceType, @[SOURCE_FORMAT_XML, SOURCE_FORMAT_JSON, SOURCE_FORMAT_DESCRIPTION]]
    );
  }
  if (nil == result) {
    return FBResponseWithErrorFormat(@"Cannot get '%@' source of the current application", sourceType);
  }
  return FBResponseWithObject(result);
}

+ (id<FBResponsePayload>)handleGetAccessibleSourceCommand:(FBRouteRequest *)request
{
  FBApplication *application = request.session.activeApplication;
  return FBResponseWithObject(application.fb_accessibilityTree ?: @{});
}

+ (id<FBResponsePayload>)handleGetAppTerminateCommand:(FBRouteRequest *)request
{
  NSString *bundleId = request.parameters[@"bundleId"];
  XCUIApplication * app = [[XCUIApplication alloc] initWithBundleIdentifier:bundleId];
  [app terminate];

//  - (void)_XCT_terminateApplicationWithBundleID:(NSString *)arg1 completion:(void (^)(NSError *))arg2;
  BOOL isTerminated = [app waitForState:XCUIApplicationStateNotRunning timeout:9.0];

  return FBResponseWithObject(@{@"isTerminated": @(isTerminated)});
}

+ (id<FBResponsePayload>)handleGetAppStateRunningForegroundCommand:(FBRouteRequest *)request
{
  NSString *bundleId = request.parameters[@"bundleId"];
  NSTimeInterval timeout = [request.parameters[@"timeout"] doubleValue];
  BOOL debug = [request.parameters[@"debug"] boolValue];
  BOOL getDOM = [request.parameters[@"getDOM"] boolValue];

  XCUIApplication * app = [[XCUIApplication alloc] initWithBundleIdentifier:bundleId];
  BOOL isRunning = [app waitForState:XCUIApplicationStateRunningForeground timeout:timeout];
  NSString *debugDescription = debug ? [app debugDescription] : @"";

  NSDictionary *tree = nil;

  if (getDOM) {
    FBApplication *fb_app = [FBApplication appWithPID:[app processID]];
    tree = fb_app.fb_tree;
  } else {
    tree = [[NSMutableDictionary alloc] init];
  }

  return FBResponseWithObject(@{@"isRunning": @(isRunning), @"debugDescription": debugDescription, @"dom": tree});
}

+ (id<FBResponsePayload>)handleGetAppAtPointCommand:(FBRouteRequest *)request
{
  BOOL getDOM = [request.parameters[@"getDOM"] boolValue];
  CGFloat x = [request.parameters[@"x"] floatValue];
  CGFloat y = [request.parameters[@"y"] floatValue];
  CGPoint point = CGPointMake(x, y);

  __block XCAccessibilityElement *resultElement = nil;
  __block NSError *resultError = nil;
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);

  id<XCTestManager_ManagerInterface> proxy = [FBXCTestDaemonsProxy testRunnerProxy];
  [proxy _XCT_requestElementAtPoint:point
                              reply:^(XCAccessibilityElement *element, NSError *error) {
                                if (nil == error) {
                                  resultElement = element;
                                } else {
                                  resultError = error;
                                }
                                dispatch_semaphore_signal(sem);
                              }];

  dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)));

  if (nil != resultError) {
    return FBResponseWithObject(@{@"status": @"error", @"message": [resultError description]});
  }

  if (nil == resultElement) {
    return FBResponseWithObject(@{@"status": @"error", @"message": @"No element found"});
  }

  pid_t pid = resultElement.processIdentifier;

  __block NSString *resultBundleId = nil;
  dispatch_semaphore_t sem2 = dispatch_semaphore_create(0);
  [proxy _XCT_requestBundleIDForPID:pid
                              reply:^(NSString *bundleID, NSError *error) {
                                if (nil == error) {
                                  resultBundleId = bundleID;
                                } else {
                                  resultError = error;
                                }
                                dispatch_semaphore_signal(sem2);
                              }];
  dispatch_semaphore_wait(sem2, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)));

  XCUIApplication * app = [[XCUIApplication alloc] initWithBundleIdentifier:resultBundleId];
  NSString *debugDescription = [app debugDescription];

  NSDictionary *tree = nil;

  if (getDOM) {
    FBApplication *fb_app = [FBApplication appWithPID:[app processID]];
    tree = fb_app.fb_tree;
  } else {
    tree = [[NSMutableDictionary alloc] init];
  }

  return FBResponseWithObject(@{@"status": @"success", @"bundleId": resultBundleId,  @"debugDescription": debugDescription, @"dom": tree});
}

@end
