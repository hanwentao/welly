//
//  YLController.h
//  MacBlueTelnet
//
//  Created by Yung-Luen Lan on 9/11/07.
//  Copyright 2007 yllan.org. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "XITabBarControl.h"
#import "YLSite.h"
#import "KOAutoReplyDelegate.h"
#import "LLFullScreenController.h"
#import "LLTelnetProcessor.h"

#define scrollTimerInterval 0.12
#define floatWindowLevel kCGStatusWindowLevel+1

@class YLView, YLTerminal;
@class RemoteControl;
@class MultiClickRemoteBehavior;

@interface YLController : NSObject {
    /* composeWindow */
    IBOutlet NSTextView *_composeText;
    IBOutlet NSPanel *_composeWindow;
	
	/* post download window */
	IBOutlet NSPanel *_postWindow;
	IBOutlet NSTextView *_postText;
    
    /* password window */
    IBOutlet NSPanel *_passwordWindow;
    IBOutlet NSSecureTextField *_passwordField;
	
    IBOutlet NSPanel *_sitesWindow;
    IBOutlet NSPanel *_emoticonsWindow;
    IBOutlet NSWindow *_mainWindow;
    IBOutlet NSPanel *_messageWindow;
    IBOutlet id _addressBar;
    IBOutlet id _detectDoubleByteButton;
    IBOutlet id _autoReplyButton;
    IBOutlet id _mouseButton;

    IBOutlet YLView *_telnetView;
    IBOutlet XITabBarControl *_tab;
    IBOutlet NSMenuItem *_detectDoubleByteMenuItem;
    IBOutlet NSMenuItem *_closeWindowMenuItem;
    IBOutlet NSMenuItem *_closeTabMenuItem;
	IBOutlet NSMenuItem *_autoReplyMenuItem;
    NSMutableArray *_sites;
    NSMutableArray *_emoticons;
    IBOutlet NSArrayController *_sitesController;
    IBOutlet NSArrayController *_emoticonsController;
    IBOutlet NSTableView *_tableView;
    IBOutlet NSMenuItem *_sitesMenu;
    IBOutlet NSTextField *_siteNameField;
    IBOutlet NSTextField *_siteAddressField;
	IBOutlet NSTextField *_autoReplyStringField;
    IBOutlet NSMenuItem *_showHiddenTextMenuItem;
    IBOutlet NSMenuItem *_encodingMenuItem;
	IBOutlet NSMenuItem *_fullScreenMenuItem;
	
	IBOutlet NSTextView *_unreadMessageTextView;
	
	// Remote Control
	RemoteControl *remoteControl;
	MultiClickRemoteBehavior *remoteControlBehavior;
	
	// Full Screen
	LLFullScreenController* _fullScreenController;
	
	// Timer test
	NSTimer* _scrollTimer;
}

- (IBAction)setEncoding:(id)sender;
- (IBAction)setDetectDoubleByteAction:(id)sender;
- (IBAction)setAutoReplyAction:(id)sender;
- (IBAction)setMouseAction:(id)sender;

- (IBAction)newTab:(id)sender;
- (IBAction)connect:(id)sender;
- (IBAction)openLocation:(id)sender;
- (IBAction)selectNextTab:(id)sender;
- (IBAction)selectPrevTab:(id)sender;
- (void)selectTabNumber:(int)index;
- (IBAction)closeTab:(id)sender;
- (IBAction)reconnect:(id)sender;
- (IBAction)openSites:(id)sender;
- (IBAction)editSites:(id)sender;
- (IBAction)closeSites:(id)sender;
- (IBAction)addSites:(id)sender;
- (IBAction)showHiddenText:(id)sender;
- (IBAction)openPreferencesWindow:(id)sender;
- (void)newConnectionWithSite:(YLSite *)site;

/* emoticon actions */
- (IBAction) closeEmoticons: (id) sender;
- (IBAction) inputEmoticons: (id) sender;
- (IBAction) openEmoticonsWindow: (id) sender;

- (IBAction) closeMessageWindow: (id) sender;

/* compose actions */
- (IBAction) openCompose: (id) sender;
- (IBAction) commitCompose: (id) sender;
- (IBAction) cancelCompose: (id) sender;
- (IBAction) setUnderline: (id) sender;
- (IBAction) setBlink: (id) sender;
- (IBAction) changeBackgroundColor: (id) sender;
- (void) prepareCompose: (id) param;

/* post download actions */
- (IBAction)openPostDownload:(id)sender;
- (IBAction)cancelPostDownload:(id)sender;

/* password window actions */
- (IBAction)openPassword:(id)sender;
- (IBAction)confirmPassword:(id)sender;
- (IBAction)cancelPassword:(id)sender;

// sites accessors
- (NSArray *)sites;
- (unsigned)countOfSites;
- (id)objectInSitesAtIndex:(unsigned)index;
- (void)getSites:(id *)objects range:(NSRange)range;
- (void)insertObject:(id)anObject inSitesAtIndex:(unsigned)index;
- (void)removeObjectFromSitesAtIndex:(unsigned)index;
- (void)replaceObjectInSitesAtIndex:(unsigned)index withObject:(id)anObject;

// emoticons accessors
- (NSArray *)emoticons;
- (unsigned)countOfEmoticons;
- (id)objectInEmoticonsAtIndex:(unsigned)theIndex;
- (void)getEmoticons:(id *)objsPtr range:(NSRange)range;
- (void)insertObject:(id)obj inEmoticonsAtIndex:(unsigned)theIndex;
- (void)removeObjectFromEmoticonsAtIndex:(unsigned)theIndex;
- (void)replaceObjectInEmoticonsAtIndex:(unsigned)theIndex withObject:(id)obj;

// for bindings access
- (RemoteControl*) remoteControl;
- (MultiClickRemoteBehavior*) remoteBehavior;

// for full screen
- (IBAction) fullScreenMode: (id) sender;

// for timer
- (void) doScrollUp:(NSTimer*) timer;
- (void) doScrollDown:(NSTimer*) timer;
- (void) disableTimer;

// for portal
- (IBAction)browseImage:(id)sender;
- (IBAction) removeSiteImage:(id)sender;
- (void)openPanelDidEnd:(NSOpenPanel *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void)checkPortal;
// temporary added, should be remove in future!!!
// by K.O.ed
- (YLView *) getView;

@end
