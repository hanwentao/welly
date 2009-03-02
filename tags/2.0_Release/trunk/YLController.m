//
//  YLController.m
//  MacBlueTelnet
//
//  Created by Yung-Luen Lan on 9/11/07.
//  Copyright 2007 yllan.org. All rights reserved.

#import "YLController.h"
#import "YLTerminal.h"
#import "YLView.h"
#import "YLConnection.h"
#import "XIPTY.h"
#import "YLLGlobalConfig.h"
#import "DBPrefsWindowController.h"
#import "YLEmoticon.h"
#import "KOPostDownloader.h"

// for remote control
#import "AppleRemote.h"
#import "KeyspanFrontRowControl.h"
#import "RemoteControlContainer.h"
#import "MultiClickRemoteBehavior.h"

// Test code by gtCarrera
#import "LLPopUpMessage.h"
// End
#import <Carbon/Carbon.h>

const NSTimeInterval DEFAULT_CLICK_TIME_DIFFERENCE = 0.25;	// for remote control
#define SiteTableViewDataType @"SiteTableViewDataType"

@interface  YLController ()
- (void)updateSitesMenu;
- (void)loadSites;
- (void)loadEmoticons;
- (void)loadLastConnections;
@end

@implementation YLController

- (id)init {
    if (self = [super init]) {
        _sites = [[NSMutableArray alloc] init];
        _emoticons = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_sites release];
    [_emoticons release];
    [super dealloc];
}

- (void)awakeFromNib {
    // Register URL
    [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self andSelector:@selector(getUrl:withReplyEvent:) forEventClass:kInternetEventClass andEventID:kAEGetURL];
    
    NSArray *observeKeys = [NSArray arrayWithObjects: @"shouldSmoothFonts", @"showHiddenText", @"messageCount", @"cellWidth", @"cellHeight", 
                            @"chineseFontName", @"chineseFontSize", @"chineseFontPaddingLeft", @"chineseFontPaddingBottom",
                            @"englishFontName", @"englishFontSize", @"englishFontPaddingLeft", @"englishFontPaddingBottom", 
                            @"colorBlack", @"colorBlackHilite", @"colorRed", @"colorRedHilite", @"colorGreen", @"colorGreenHilite",
                            @"colorYellow", @"colorYellowHilite", @"colorBlue", @"colorBlueHilite", @"colorMagenta", @"colorMagentaHilite", 
                            @"colorCyan", @"colorCyanHilite", @"colorWhite", @"colorWhiteHilite", @"colorBG", @"colorBGHilite", nil];
    for (NSString *key in observeKeys)
        [[YLLGlobalConfig sharedInstance] addObserver:self
                                           forKeyPath:key
                                              options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) 
                                              context:nil];

    // tab control style
    [_tab setCanCloseOnlyTab:YES];
    NSAssert([_tab delegate] == self, @"set in .nib");
    //show a new-tab button
    //[_tab setShowAddTabButton:YES];
    [[_tab addTabButton] setTarget:self];
    [[_tab addTabButton] setAction:@selector(newTab:)];
    _telnetView = (YLView *)[_tab tabView];
	
    // Trigger the KVO to update the information properly.
    [[YLLGlobalConfig sharedInstance] setShowHiddenText:[[YLLGlobalConfig sharedInstance] showHiddenText]];
    [[YLLGlobalConfig sharedInstance] setCellWidth:[[YLLGlobalConfig sharedInstance] cellWidth]];
    
    [self loadSites];
    [self updateSitesMenu];
    [self loadEmoticons];

    //[_mainWindow setHasShadow:YES];
    [_mainWindow setOpaque:NO];

    [_mainWindow setFrameAutosaveName:@"wellyMainWindowFrame"];
    
    [NSTimer scheduledTimerWithTimeInterval:120 target:self selector:@selector(antiIdle:) userInfo:nil repeats:YES];
    [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(updateBlinkTicker:) userInfo:nil repeats:YES];

    // post download
    [_postText setFont:[NSFont fontWithName:@"Monaco" size:12]];

    // set remote control
    // 1. instantiate the desired behavior for the remote control device
    remoteControlBehavior = [[MultiClickRemoteBehavior alloc] init];	
    // 2. configure the behavior
    [remoteControlBehavior setDelegate:self];
    [remoteControlBehavior setClickCountingEnabled:YES];
    [remoteControlBehavior setSimulateHoldEvent:YES];
    [remoteControlBehavior setMaximumClickCountTimeDifference:DEFAULT_CLICK_TIME_DIFFERENCE];
    // 3. a Remote Control Container manages a number of devices and conforms to the RemoteControl interface
    //    Therefore you can enable or disable all the devices of the container with a single "startListening:" call.
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	RemoteControlContainer *container = [[RemoteControlContainer alloc] initWithDelegate: remoteControlBehavior];
    [container instantiateAndAddRemoteControlDeviceWithClass:[AppleRemote class]];	
    [container instantiateAndAddRemoteControlDeviceWithClass:[KeyspanFrontRowControl class]];
    // to give the binding mechanism a chance to see the change of the attribute
    [self setValue:container forKey:@"remoteControl"];
    [container startListening:self];
    remoteControl = container;
	[pool release];
	// For full screen, initiallize the full screen controller
	_fullScreenController = [[LLFullScreenController alloc] 
							 initWithoutProcessor:_telnetView 
							 superView:[_telnetView superview] 
							 originalWindow:_mainWindow];
	
    // drag & drop in site view
    [_tableView registerForDraggedTypes:[NSArray arrayWithObject:SiteTableViewDataType] ];

    // open the portal
    // the switch
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"Portal"]) {
		[_telnetView updatePortal];
    }
    [self tabViewDidChangeNumberOfTabViewItems:_telnetView];
	[_tab setMainController:[self retain]];
    
    // restore connections
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"RestoreConnection"]) 
        [self loadLastConnections];
}

- (void)updateSitesMenu {
    int total = [[_sitesMenu submenu] numberOfItems];
    int i = total - 1;
    // search the last seperator from the bottom
    for (; i > 0; i--)
        if ([[[_sitesMenu submenu] itemAtIndex:i] isSeparatorItem])
            break;

    // then remove all menuitems below it, since we need to refresh the site menus
    ++i;
    for (int j = i; j < total; j++) {
        [[_sitesMenu submenu] removeItemAtIndex:i];
    }
    
    // Now add items of site one by one
    for (YLSite *s in _sites) {
        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:[s name] ?: @"" action:@selector(openSiteMenu:) keyEquivalent:@""];
        [menuItem setRepresentedObject:s];
        [[_sitesMenu submenu] addItem:menuItem];
        [menuItem release];
    }
    
    // Reset portal if necessary
	if([[NSUserDefaults standardUserDefaults] boolForKey:@"Portal"]) {
		[_telnetView resetPortal];
	}
}

- (void)updateEncodingMenu {
    // update encoding menu status
    NSMenu *m = [_encodingMenuItem submenu];
    for (int i = 0; i < [m numberOfItems]; i++) {
        NSMenuItem *item = [m itemAtIndex:i];
        [item setState:NSOffState];
    }
    if (![_telnetView frontMostTerminal])
        return;
    YLEncoding currentEncoding = [[_telnetView frontMostTerminal] encoding];
    if (currentEncoding == YLBig5Encoding)
        [[m itemWithTitle:titleBig5] setState:NSOnState];
    if (currentEncoding == YLGBKEncoding)
        [[m itemWithTitle:titleGBK] setState:NSOnState];
}

- (void)updateBlinkTicker:(NSTimer *)timer {
    [[YLLGlobalConfig sharedInstance] updateBlinkTicker];
    if ([_telnetView hasBlinkCell])
        [_telnetView setNeedsDisplay:YES];
}

- (void)antiIdle:(NSTimer *)timer {
    if (![[NSUserDefaults standardUserDefaults] boolForKey: @"AntiIdle"]) return;
    NSArray *a = [_telnetView tabViewItems];
    for (NSTabViewItem *item in a) {
        YLConnection *connection = [item identifier];
        if ([connection connected] && [connection lastTouchDate] && [[NSDate date] timeIntervalSinceDate:[connection lastTouchDate]] >= 119) {
//            unsigned char msg[] = {0x1B, 'O', 'A', 0x1B, 'O', 'B'};
            unsigned char msg[] = {0x00, 0x00, 0x00, 0x00, 0x00, 0x00};
            [connection sendBytes:msg length:6];
        }
    }
}

- (void)newConnectionWithSite:(YLSite *)site {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

	// Set the view to be focused.
	[_mainWindow makeFirstResponder:_telnetView];

    YLConnection *connection;
    NSTabViewItem *tabViewItem;
    BOOL emptyTab = [_telnetView frontMostConnection] && ([_telnetView frontMostTerminal] == nil);
    if (emptyTab && ![site empty]) {
		// reuse the empty tab
        tabViewItem = [_telnetView selectedTabViewItem];
        connection = [tabViewItem identifier];
        [connection setSite:site];
        [self tabView:_telnetView didSelectTabViewItem:tabViewItem];
    } else {
        connection = [[[YLConnection alloc] initWithSite:site] autorelease];
        tabViewItem = [[[NSTabViewItem alloc] initWithIdentifier:connection] autorelease];
        // this will invoke tabView:didSelectTabViewItem for the first tab
        [_telnetView addTabViewItem:tabViewItem];
        [_telnetView selectTabViewItem:tabViewItem];
    }
    
    // set the tab label as the site name.
    [tabViewItem setLabel:[site name]];

    if ([site empty]) {
        [connection setTerminal:nil];
        [connection setProtocol:nil];
    } else {
		// Close the portal
		if ([_telnetView isInPortalState]) {
			[_telnetView removePortal];
		}
        // new terminal
        YLTerminal *terminal = [YLTerminal terminalWithView:_telnetView];
        [connection setTerminal:terminal];

        // XIPTY as the default protocol (a proxy)
        XIPTY *protocol = [[XIPTY new] autorelease];
        [connection setProtocol:protocol];
        [protocol setDelegate:connection];
        [protocol connect:[site address]];
    }

    [self updateEncodingMenu];
    [_detectDoubleByteButton setState:[site detectDoubleByte] ? NSOnState : NSOffState];
    [_detectDoubleByteMenuItem setState:[site detectDoubleByte] ? NSOnState : NSOffState];
    [_autoReplyButton setState:[site autoReply] ? NSOnState : NSOffState];
    [_autoReplyMenuItem setState:[site autoReply] ? NSOnState : NSOffState];
    [_mouseButton setState:[site enableMouse] ? NSOnState : NSOffState];

    [pool release];
}

#pragma mark -
#pragma mark KVO

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if ([keyPath isEqualToString:@"showHiddenText"]) {
        if ([[YLLGlobalConfig sharedInstance] showHiddenText]) 
            [_showHiddenTextMenuItem setState:NSOnState];
        else
            [_showHiddenTextMenuItem setState:NSOffState];        
    } else if ([keyPath isEqualToString:@"messageCount"]) {
        NSDockTile *dockTile = [NSApp dockTile];
        if ([[YLLGlobalConfig sharedInstance] messageCount] == 0) {
            [dockTile setBadgeLabel:nil];
        } else {
            [dockTile setBadgeLabel:[NSString stringWithFormat:@"%d", [[YLLGlobalConfig sharedInstance] messageCount]]];
        }
        [dockTile display];
    } else if ([keyPath isEqualToString:@"shouldSmoothFonts"]) {
        [[[[_telnetView selectedTabViewItem] identifier] terminal] setAllDirty];
        [_telnetView updateBackedImage];
        [_telnetView setNeedsDisplay:YES];
    } else if ([keyPath hasPrefix:@"cell"]) {
        YLLGlobalConfig *config = [YLLGlobalConfig sharedInstance];
        NSRect r = [_mainWindow frame];
        CGFloat topLeftCorner = r.origin.y + r.size.height;

        CGFloat shift = 0.0;

        // Calculate the toolbar height
        shift = NSHeight([_mainWindow frame]) - NSHeight([[_mainWindow contentView] frame]) + 22;

        r.size.width = [config cellWidth] * [config column];
        r.size.height = [config cellHeight] * [config row] + shift;
        r.origin.y = topLeftCorner - r.size.height;
        [_mainWindow setFrame:r display:YES animate:NO];
        [_telnetView configure];
        [[[[_telnetView selectedTabViewItem] identifier] terminal] setAllDirty];
        [_telnetView updateBackedImage];
        [_telnetView setNeedsDisplay: YES];
        NSRect tabRect = [_tab frame];
        tabRect.size.width = r.size.width;
        [_tab setFrame: tabRect];
    } else if ([keyPath hasPrefix:@"chineseFont"] || [keyPath hasPrefix:@"englishFont"] || [keyPath hasPrefix:@"color"]) {
        [[YLLGlobalConfig sharedInstance] refreshFont];
        [[[[_telnetView selectedTabViewItem] identifier] terminal] setAllDirty];
        [_telnetView updateBackedImage];
        [_telnetView setNeedsDisplay:YES];
    }
}

#pragma mark -
#pragma mark User Defaults

- (void)loadSites {
    NSArray *array = [[NSUserDefaults standardUserDefaults] arrayForKey:@"Sites"];
    for (NSDictionary *d in array)
        //[_sites addObject:[YLSite siteWithDictionary:d]];
        [self insertObject:[YLSite siteWithDictionary:d] inSitesAtIndex:[self countOfSites]];    
}

- (void)saveSites {
    NSMutableArray *a = [NSMutableArray array];
    for (YLSite *s in _sites)
        [a addObject:[s dictionaryOfSite]];
    [[NSUserDefaults standardUserDefaults] setObject:a forKey:@"Sites"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self updateSitesMenu];
}

- (void) loadEmoticons {
    NSArray *a = [[NSUserDefaults standardUserDefaults] arrayForKey: @"Emoticons"];
    for (NSDictionary *d in a)
        [self insertObject: [YLEmoticon emoticonWithDictionary: d] inEmoticonsAtIndex: [self countOfEmoticons]];
}

- (void) saveEmoticons {
    NSMutableArray *a = [NSMutableArray array];
    for (YLEmoticon *e in _emoticons) 
        [a addObject: [e dictionaryOfEmoticon]];
    [[NSUserDefaults standardUserDefaults] setObject: a forKey: @"Emoticons"];    
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void) loadLastConnections {
    NSArray *a = [[NSUserDefaults standardUserDefaults] arrayForKey: @"LastConnections"];
    for (NSDictionary *d in a) {
        [self newConnectionWithSite: [YLSite siteWithDictionary: d]];
    }    
}

- (void) saveLastConnections {
    int tabNumber = [_telnetView numberOfTabViewItems];
    int i;
    NSMutableArray *a = [NSMutableArray array];
    for (i = 0; i < tabNumber; i++) {
        id connection = [[_telnetView tabViewItemAtIndex: i] identifier];
        if ([connection terminal]) // not empty tab
            [a addObject: [[connection site] dictionaryOfSite]];
    }
    [[NSUserDefaults standardUserDefaults] setObject: a forKey: @"LastConnections"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark -
#pragma mark Actions
- (IBAction) setDetectDoubleByteAction: (id) sender {
    BOOL ddb = [sender state];
    if ([sender isKindOfClass: [NSMenuItem class]])
        ddb = !ddb;
    [[[_telnetView frontMostConnection] site] setDetectDoubleByte: ddb];
    [_detectDoubleByteButton setState: ddb ? NSOnState : NSOffState];
    [_detectDoubleByteMenuItem setState: ddb ? NSOnState : NSOffState];
}

- (IBAction) setAutoReplyAction: (id) sender {
	BOOL ar = [sender state];
	if ([sender isKindOfClass: [NSMenuItem class]])
		ar = !ar;
	// set the state of the button and menuitem
	[_autoReplyButton setState: ar ? NSOnState : NSOffState];
	[_autoReplyMenuItem setState: ar ? NSOnState : NSOffState];
	if (!ar && ar != [[[_telnetView frontMostConnection] site] autoReply]) {
		// when user is to close auto reply, 
		if ([[[_telnetView frontMostConnection] autoReplyDelegate] unreadCount] > 0) {
			// we should inform him with the unread messages
			[[[_telnetView frontMostConnection] autoReplyDelegate] showUnreadMessagesOnTextView: _unreadMessageTextView];
			[_messageWindow makeKeyAndOrderFront: self];
		}
	}
	
	[[[_telnetView frontMostConnection] site] setAutoReply: ar];
}

- (IBAction)setMouseAction:(id)sender {
    BOOL state = [sender state];
    if ([sender isKindOfClass:[NSMenuItem class]])
        state = !state;
    [_mouseButton setState:(state ? NSOnState : NSOffState)];
	
	[[[_telnetView frontMostConnection] site] setEnableMouse: state];
}

- (IBAction) closeMessageWindow: (id) sender {
	[_messageWindow orderOut: self];
}

- (IBAction) setEncoding: (id) sender {
    //int index = [[_encodingMenuItem submenu] indexOfItem: sender];
	YLEncoding encoding = YLGBKEncoding;
	if ([[sender title] isEqual: titleGBK])
		encoding = YLGBKEncoding;
	if ([[sender title] isEqual: titleBig5])
		encoding = YLBig5Encoding;
    if ([_telnetView frontMostTerminal]) {
        [[_telnetView frontMostTerminal] setEncoding: encoding];
        [[_telnetView frontMostTerminal] setAllDirty];
        [_telnetView updateBackedImage];
        [_telnetView setNeedsDisplay: YES];
        [self updateEncodingMenu];
    }
}

- (IBAction)newTab:(id)sender {
    [self newConnectionWithSite:[YLSite site]];
	
	// Draw the portal and entering the portal control mode if needed...
	if([[YLSite site] empty] && ([[NSUserDefaults standardUserDefaults] boolForKey:@"Portal"])) {
		[_telnetView updatePortal];
	}
    /*
    YLConnection *connection = [[[YLConnection alloc] initWithSite:site] autorelease];

    NSTabViewItem *tabItem = [[[NSTabViewItem alloc] initWithIdentifier:connection] autorelease];
    [tabItem setLabel:@"Untitled"];
    [_telnetView addTabViewItem:tabItem];
    [_telnetView selectTabViewItem:tabItem];

    [_mainWindow makeKeyAndOrderFront:self];
    */
    // let user input
    //[_mainWindow makeFirstResponder:_addressBar];
}

- (IBAction) connect: (id) sender {
	[sender abortEditing];
	[[_telnetView window] makeFirstResponder: _telnetView];
    BOOL ssh = NO;
    
    NSString *name = [sender stringValue];
    if ([[name lowercaseString] hasPrefix:@"ssh://"]) 
        ssh = YES;
//        name = [name substringFromIndex: 6];
    if ([[name lowercaseString] hasPrefix:@"telnet://"])
        name = [name substringFromIndex: 9];
    if ([[name lowercaseString] hasPrefix:@"bbs://"])
        name = [name substringFromIndex: 6];
    
    NSMutableArray *matchedSites = [NSMutableArray array];
    YLSite *s;
        
    if ([name rangeOfString: @"."].location != NSNotFound) { /* Normal address */        
        for (YLSite *site in _sites) 
            if ([[site address] rangeOfString:name].location != NSNotFound && !(ssh ^ [[site address] hasPrefix:@"ssh://"])) 
                [matchedSites addObject:site];
        if ([matchedSites count] > 0) {
            [matchedSites sortUsingDescriptors:[NSArray arrayWithObject:[[[NSSortDescriptor alloc] initWithKey:@"address.length" ascending:YES] autorelease]]];
            s = [[[matchedSites objectAtIndex:0] copy] autorelease];
        } else {
            s = [YLSite site];
            [s setAddress:name];
            [s setName:name];
        }
    } else { /* Short Address? */
        for (YLSite *site in _sites) 
            if ([[site name] rangeOfString: name].location != NSNotFound) 
                [matchedSites addObject:site];
        [matchedSites sortUsingDescriptors: [NSArray arrayWithObject:[[[NSSortDescriptor alloc] initWithKey:@"name.length" ascending:YES] autorelease]]];
        if ([matchedSites count] == 0) {
            for (YLSite *site in _sites) 
                if ([[site address] rangeOfString: name].location != NSNotFound)
                    [matchedSites addObject:site];
            [matchedSites sortUsingDescriptors: [NSArray arrayWithObject:[[[NSSortDescriptor alloc] initWithKey:@"address.length" ascending:YES] autorelease]]];
        } 
        if ([matchedSites count] > 0) {
            s = [[[matchedSites objectAtIndex:0] copy] autorelease];
        } else {
            s = [YLSite site];
            [s setAddress:[sender stringValue]];
            [s setName:name];
        }
    }
    [self newConnectionWithSite:s];
    [sender setStringValue:[s address]];
}

- (IBAction)openLocation:(id)sender {
    [_mainWindow makeFirstResponder:_addressBar];
}

- (BOOL)shouldReconnect {
	if (![[_telnetView frontMostConnection] connected]) return YES;
    if (![[NSUserDefaults standardUserDefaults] boolForKey: @"ConfirmOnClose"]) return YES;
    NSBeginAlertSheet(NSLocalizedString(@"Are you sure you want to reconnect?", @"Sheet Title"), 
                      NSLocalizedString(@"Confirm", @"Default Button"), 
                      NSLocalizedString(@"Cancel", @"Cancel Button"), 
                      nil, 
                      _mainWindow, self, 
                      @selector(confirmSheetDidEnd:returnCode:contextInfo:), 
                      @selector(confirmSheetDidDismiss:returnCode:contextInfo:), 
                      nil, 
                      NSLocalizedString(@"The connection is still alive. If you reconnect, the current connection will be lost. Do you want to reconnect anyway?", @"Sheet Message"));
    return NO;
}

- (void) confirmReconnect:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void  *)contextInfo {
    if (returnCode == NSAlertDefaultReturn) {
		[[_telnetView frontMostConnection] reconnect];
    }
}

- (IBAction) reconnect: (id) sender {
    if (![[_telnetView frontMostConnection] connected] || ![[NSUserDefaults standardUserDefaults] boolForKey: @"ConfirmOnClose"]) {
		// Close the portal
		if ([_telnetView isInPortalState] && ![[[_telnetView frontMostConnection] site] empty] 
			&& [_telnetView numberOfTabViewItems] > 0) {
			[_telnetView removePortal];
		}
		[[_telnetView frontMostConnection] reconnect];
        return;
    }
    NSBeginAlertSheet(NSLocalizedString(@"Are you sure you want to reconnect?", @"Sheet Title"), 
                      NSLocalizedString(@"Confirm", @"Default Button"), 
                      NSLocalizedString(@"Cancel", @"Cancel Button"), 
                      nil, 
                      _mainWindow, self, 
                      @selector(confirmReconnect:returnCode:contextInfo:), 
                      nil, 
                      nil, 
                      NSLocalizedString(@"The connection is still alive. If you reconnect, the current connection will be lost. Do you want to reconnect anyway?", @"Sheet Message"));
    return;	
}

- (void) fullScreenPopUp {
	NSString* currSiteName = [[[_telnetView frontMostConnection] site] name];
	[LLPopUpMessage showPopUpMessage:currSiteName 
							duration:1.2
						  effectView:((KOEffectView*)[_telnetView getEffectView])];
}

- (IBAction)selectNextTab:(id)sender {
    [_tab selectNextTabViewItem:sender];
	[self checkPortal];
	[self fullScreenPopUp];
}

- (IBAction)selectPrevTab:(id)sender {
    [_tab selectPreviousTabViewItem:sender];
	[self checkPortal];
	[self fullScreenPopUp];
}

- (void)selectTabNumber:(int)index {
    if (index > 0 && index <= [_telnetView numberOfTabViewItems]) {
        [_tab selectTabViewItemAtIndex:index-1];
    }
//	NSLog(@"Select tab %d", index);
	[self checkPortal];
}

- (IBAction)closeTab:(id)sender {
    if ([_telnetView numberOfTabViewItems] == 0) return;
	// Here, sometimes it may throw a exception...
	@try {
		[_tab removeTabViewItem:[_telnetView selectedTabViewItem]];
	}
	@catch (NSException * e) {
	}
	[self checkPortal];
    /*
    if ([self tabView:_telnetView shouldCloseTabViewItem:sel]) {
        [self tabView:_telnetView willCloseTabViewItem:sel];
        [_telnetView removeTabViewItem:sel];
    }
    */
}

- (IBAction) editSites: (id) sender {
    [NSApp beginSheet: _sitesWindow
       modalForWindow: _mainWindow
        modalDelegate: nil
       didEndSelector: NULL
          contextInfo: nil];
	[_sitesWindow setLevel:	floatWindowLevel];
}

- (IBAction) openSites: (id) sender {
    NSArray *a = [_sitesController selectedObjects];
    [self closeSites: sender];
    
    if ([a count] == 1) {
        YLSite *s = [a objectAtIndex: 0];
        [self newConnectionWithSite: [[s copy] autorelease]];
    }
}

- (IBAction) openSiteMenu: (id) sender {
    YLSite *s = [sender representedObject];
    [self newConnectionWithSite: s];
}

- (IBAction) closeSites: (id) sender {
    [_sitesWindow endEditingFor: nil];
    [NSApp endSheet: _sitesWindow];
    [_sitesWindow orderOut: self];
    [self saveSites];
}

- (IBAction)addSites:(id)sender {
    if ([_telnetView numberOfTabViewItems] == 0) return;
    NSString *address = [[[_telnetView frontMostConnection] site] address];
    
    for (YLSite *s in _sites) 
        if ([[s address] isEqualToString:address]) 
            return;
    
    YLSite *site = [[[[_telnetView frontMostConnection] site] copy] autorelease];
    [_sitesController addObject:site];
    [_sitesController setSelectedObjects:[NSArray arrayWithObject:site]];
    [self performSelector:@selector(editSites:) withObject:sender afterDelay:0.1];
    if ([_siteNameField acceptsFirstResponder])
        [_sitesWindow makeFirstResponder:_siteNameField];
}



- (IBAction) showHiddenText: (id) sender {
    BOOL show = ([sender state] == NSOnState);
    if ([sender isKindOfClass: [NSMenuItem class]]) {
        show = !show;
    }

    [[YLLGlobalConfig sharedInstance] setShowHiddenText: show];
    [_telnetView refreshHiddenRegion];
    [_telnetView updateBackedImage];
    [_telnetView setNeedsDisplay: YES];
}

- (IBAction) openPreferencesWindow: (id) sender {
    [[DBPrefsWindowController sharedPrefsWindowController] showWindow:nil];
}

- (IBAction) openEmoticonsWindow: (id) sender {
    [_emoticonsWindow makeKeyAndOrderFront: self];
}

- (IBAction) closeEmoticons: (id) sender {
    [_emoticonsWindow endEditingFor: nil];
    [_emoticonsWindow makeFirstResponder: _emoticonsWindow];
    [_emoticonsWindow orderOut: self];
    [self saveEmoticons];
}

- (IBAction) inputEmoticons: (id) sender {
    [self closeEmoticons: sender];
    
    if ([[_telnetView frontMostConnection] connected]) {
        NSArray *a = [_emoticonsController selectedObjects];
        
        if ([a count] == 1) {
            YLEmoticon *e = [a objectAtIndex: 0];
            [_telnetView insertText: [e content]];
        }
    }
}

#pragma mark -
#pragma mark Sites Accessors

- (NSArray *)sites {
    return _sites;
}

- (unsigned)countOfSites {
    return [_sites count];
}

- (id)objectInSitesAtIndex:(unsigned)index {
    return [_sites objectAtIndex:index];
}

- (void)getSites:(id *)objects range:(NSRange)range {
    [_sites getObjects:objects range:range];
}

- (void)insertObject:(id)anObject inSitesAtIndex:(unsigned)index {
    [_sites insertObject:anObject atIndex:index];
}

- (void)removeObjectFromSitesAtIndex:(unsigned)index {
    [_sites removeObjectAtIndex:index];
}

- (void)replaceObjectInSitesAtIndex:(unsigned)index withObject:(id)anObject {
    [_sites replaceObjectAtIndex:index withObject:anObject];
}

#pragma mark -
#pragma mark Emoticons Accessors

- (NSArray *)emoticons {
    return _emoticons;
}

- (unsigned)countOfEmoticons {
    return [_emoticons count];
}

- (id)objectInEmoticonsAtIndex:(unsigned)theIndex {
    return [_emoticons objectAtIndex:theIndex];
}

- (void)getEmoticons:(id *)objsPtr range:(NSRange)range {
    [_emoticons getObjects:objsPtr range:range];
}

- (void)insertObject:(id)obj inEmoticonsAtIndex:(unsigned)theIndex {
    [_emoticons insertObject:obj atIndex:theIndex];
}

- (void)removeObjectFromEmoticonsAtIndex:(unsigned)theIndex {
    [_emoticons removeObjectAtIndex:theIndex];
}

- (void)replaceObjectInEmoticonsAtIndex:(unsigned)theIndex withObject:(id)obj {
    [_emoticons replaceObjectAtIndex:theIndex withObject:obj];
}

/* commented out by boost @ 9#: who is using this...
- (IBOutlet) view { return _telnetView; }
- (void) setView: (IBOutlet) o {}
*/

#pragma mark -
#pragma mark Application Delegation
- (BOOL) validateMenuItem: (NSMenuItem *) item {
    SEL action = [item action];
    if ((action == @selector(addSites:) ||
         action == @selector(reconnect:) ||
         action == @selector(selectNextTab:) ||
         action == @selector(selectPrevTab:) )
        && [_telnetView numberOfTabViewItems] == 0) {
        return NO;
    } else if (action == @selector(setEncoding:) && [_telnetView numberOfTabViewItems] == 0) {
        return NO;
    }
    return YES;
}

- (BOOL) applicationShouldHandleReopen: (id) s hasVisibleWindows: (BOOL) b {
    [_mainWindow makeKeyAndOrderFront: self];
    return NO;
} 

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
	// Restore from full screen firstly
	[_fullScreenController releaseFullScreen];
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey: @"RestoreConnection"]) 
        [self saveLastConnections];
    
    if (![[NSUserDefaults standardUserDefaults] boolForKey: @"ConfirmOnClose"]) 
        return YES;
    
    int tabNumber = [_telnetView numberOfTabViewItems];
	int connectedConnection = 0;
    for (int i = 0; i < tabNumber; i++) {
        id connection = [[_telnetView tabViewItemAtIndex:i] identifier];
        if ([connection connected])
            ++connectedConnection;
    }
    if (connectedConnection == 0) return YES;
    NSBeginAlertSheet(NSLocalizedString(@"Are you sure you want to quit Welly?", @"Sheet Title"), 
                      NSLocalizedString(@"Quit", @"Default Button"), 
                      NSLocalizedString(@"Cancel", @"Cancel Button"), 
                      nil, 
                      _mainWindow, self, 
                      @selector(confirmSheetDidEnd:returnCode:contextInfo:), 
                      @selector(confirmSheetDidDismiss:returnCode:contextInfo:), nil, 
                      [NSString stringWithFormat:NSLocalizedString(@"There are %d tabs open in Welly. Do you want to quit anyway?", @"Sheet Message"),
                                connectedConnection]);
    return NSTerminateLater;
}

- (void) confirmSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void  *)contextInfo {
    [[NSUserDefaults standardUserDefaults] synchronize];
    [NSApp replyToApplicationShouldTerminate: (returnCode == NSAlertDefaultReturn)];
}

- (void) confirmSheetDidDismiss:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void  *)contextInfo {
    [[NSUserDefaults standardUserDefaults] synchronize];
    [NSApp replyToApplicationShouldTerminate: (returnCode == NSAlertDefaultReturn)];
}

#pragma mark -
#pragma mark Window Delegation

- (BOOL) windowShouldClose: (id) window {
    [_mainWindow orderOut: self];
    return NO;
}

- (BOOL) windowWillClose: (id) window {
//    [NSApp terminate: self];
    return NO;
}

- (void) windowDidBecomeKey: (NSNotification *) notification {
    [_closeWindowMenuItem setKeyEquivalentModifierMask: NSCommandKeyMask | NSShiftKeyMask];
    [_closeTabMenuItem setKeyEquivalent: @"w"];
}

- (void) windowDidResignKey: (NSNotification *) notification {
    [_closeWindowMenuItem setKeyEquivalentModifierMask: NSCommandKeyMask];
    [_closeTabMenuItem setKeyEquivalent: @""];
}

- (void)getUrl:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent {
	NSString *url = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
	// now you can create an NSURL and grab the necessary parts
    if ([[url lowercaseString] hasPrefix: @"bbs://"])
        url = [url substringFromIndex: 6];
    [_addressBar setStringValue: url];
    [self connect: _addressBar];
}

#pragma mark -
#pragma mark TabView delegation

- (BOOL)tabView:(NSTabView *)tabView shouldCloseTabViewItem:(NSTabViewItem *)tabViewItem {
	// Restore from full screen firstly
	[_fullScreenController releaseFullScreen];
	
    if (![[tabViewItem identifier] connected]) return YES;
    if (![[NSUserDefaults standardUserDefaults] boolForKey: @"ConfirmOnClose"]) return YES;
    /* commented out by boost @ 9#: modal makes more sense
    NSBeginAlertSheet(NSLocalizedString(@"Are you sure you want to close this tab?", @"Sheet Title"), 
                      NSLocalizedString(@"Close", @"Default Button"), 
                      NSLocalizedString(@"Cancel", @"Cancel Button"), 
                      nil, 
                      _mainWindow, self, 
                      @selector(didShouldCloseTabViewItem:returnCode:contextInfo:), 
                      NULL, 
                      tabViewItem, 
                      NSLocalizedString(@"The connection is still alive. If you close this tab, the connection will be lost. Do you want to close this tab anyway?", @"Sheet Message"));
    */
    NSAlert *alert = [NSAlert alertWithMessageText:NSLocalizedString(@"Are you sure you want to close this tab?", @"Sheet Title")
                              defaultButton:NSLocalizedString(@"Close", @"Default Button")
                              alternateButton:NSLocalizedString(@"Cancel", @"Cancel Button")
                              otherButton:nil
                              informativeTextWithFormat:NSLocalizedString(@"The connection is still alive. If you close this tab, the connection will be lost. Do you want to close this tab anyway?", @"Sheet Message")];
    if ([alert runModal] == NSAlertDefaultReturn)
        return YES;
    return NO;
}

- (void)tabView:(NSTabView *)tabView willCloseTabViewItem:(NSTabViewItem *)tabViewItem {
    // close the connection
    [[tabViewItem identifier] close];
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    YLConnection *connection = [tabViewItem identifier];
    YLSite *site = [connection site];
    [_addressBar setStringValue:[site address]];
    YLTerminal *terminal = [connection terminal];
    [connection resetMessageCount];
    [terminal setAllDirty];

    [_mainWindow makeFirstResponder:tabView];
    NSAssert(tabView == _telnetView, @"tabView");
    [_telnetView updateBackedImage];
    [_telnetView clearSelection];
    [_telnetView setNeedsDisplay:YES];

//    if ([_telnetView layer])
//        [_telnetView setWantsLayer:[site empty]];
    [self updateEncodingMenu];
#define CELLSTATE(x) ((x) ? NSOnState : NSOffState)
    [_detectDoubleByteButton setState:CELLSTATE([site detectDoubleByte])];
    [_detectDoubleByteMenuItem setState:CELLSTATE([site detectDoubleByte])];
    [_autoReplyButton setState:CELLSTATE([site autoReply])];
	[_autoReplyMenuItem setState:CELLSTATE([site autoReply])];
	[_mouseButton setState:CELLSTATE([site enableMouse])];
#undef CELLSTATE
}

- (void)tabViewDidChangeNumberOfTabViewItems:(NSTabView *)tabView {
    // all tab closed, no didSelectTabViewItem will happen
    if ([tabView numberOfTabViewItems] == 0) {
        if ([_sites count]) {
//            if ([_telnetView layer])
//                [_telnetView setWantsLayer:YES];
            [_mainWindow makeFirstResponder:_telnetView];
        } else {
//            if ([_telnetView layer])
//                [_telnetView setWantsLayer:NO];
            [_mainWindow makeFirstResponder:_addressBar];
        }
    }
}

/*
- (BOOL)tabView:(NSTabView *)tabView shouldSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    return YES;
}
- (void)tabView:(NSTabView *)tabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    id identifier = [tabViewItem identifier];
    [[identifier terminal] setAllDirty];
    [_telnetView clearSelection];
}
*/

#pragma mark -
#pragma mark Compose
/* compose actions */
- (void)prepareCompose:(id)param {
    const int sleepTime = 500000;
    const int maxRounds = 3;
    const int linesPerRound = [[YLLGlobalConfig sharedInstance] row] - 1;
    BOOL isFinished = NO;
	/*
	[[_telnetView frontMostConnection] sendText: @"\023"];
	usleep(sleepTime);
	*/
    [_composeText setString:@""];
    [_composeText setBackgroundColor:[NSColor blackColor]];
    [_composeText setTextColor:[NSColor lightGrayColor]];
    [_composeText setInsertionPointColor:[NSColor whiteColor]];
    for (int i = 0; i < maxRounds && !isFinished; ++i) {
        for (int j = 0; j < linesPerRound; ++j) {
            NSString *nextLine = [[_telnetView frontMostTerminal] stringFromIndex:j * [[YLLGlobalConfig sharedInstance] column] length:[[YLLGlobalConfig sharedInstance] column]] ?: @"";
            if ([nextLine isEqualToString:@"--"]) {
                isFinished = YES;
                break;
            }
            [_composeText setString:[[[_composeText string] stringByAppendingString:nextLine] stringByAppendingString:@"\r"]];
			/*
			[_composeText insertText: nextLine];
			[_composeText insertText: @"\r"];
			*/
        }
        for (int j = 0; j < linesPerRound; ++j)
            [[_telnetView frontMostConnection] sendText:@"\031"];
        usleep(sleepTime);
    }
    [_composeText setString:[[_composeText string] stringByAppendingString:@"--\rgenerated by Welly\r"]];//\030\012"]];
    [_composeText setSelectedRange:NSMakeRange(0, 0)];
    [NSThread exit];
}

- (IBAction) openCompose: (id) sender {
	[NSThread detachNewThreadSelector: @selector(prepareCompose:) toTarget: self withObject: self];
    [NSApp beginSheet: _composeWindow
       modalForWindow: _mainWindow
        modalDelegate: nil
       didEndSelector: NULL
          contextInfo: nil];
}

- (IBAction) commitCompose: (id) sender {
	//[[_telnetView frontMostConnection] sendText: [_composeText string]];
	NSString *escString;
    YLSite *s = [[_telnetView frontMostConnection] site];
    if ([s ansiColorKey] == YLCtrlUANSIColorKey) {
        escString = @"\x15";
    } else if ([s ansiColorKey] == YLEscEscEscANSIColorKey) {
        escString = @"\x1B\x1B";
    } else {
        escString = @"\x1B";
    }
	
	NSFontManager *fontManager = [NSFontManager sharedFontManager];
	NSMutableString *writeBuffer = [NSMutableString string];
	NSTextStorage *storage = [_composeText textStorage];
	NSString *rawString = [storage string];
	BOOL underline, preUnderline = NO;
	BOOL blink, preBlink = NO;
	
	for (int i = 0; i < [storage length]; ++i) {
		char tmp[100] = "";
		// get attributes of i-th character
		
		underline = ([[storage attribute: NSUnderlineStyleAttributeName atIndex: i effectiveRange: nil] intValue] != NSUnderlineStyleNone);
		blink = [fontManager traitsOfFont: [storage attribute: NSFontAttributeName atIndex: i effectiveRange: nil]] & NSBoldFontMask;
		
		/* Add attributes */
		if ((underline != preUnderline) || 
			(blink != preBlink)) {
			strcat(tmp, "[");
			if (underline && !preUnderline) {
				strcat(tmp, "4;");
			}
			if (blink && !preBlink)
				strcat(tmp, "5;");
			strcat(tmp, "m");
			[writeBuffer appendString:escString];
			[writeBuffer appendString:[NSString stringWithCString:tmp]];
			preUnderline = underline;
			preBlink = blink;
		}
		
		// get i-th character
		unichar ch = [rawString characterAtIndex:i];
		
		// write to the buffer
		[writeBuffer appendString:[NSString stringWithCharacters:&ch length:1]];
	}
	
	[[_telnetView frontMostConnection] sendText:writeBuffer];
	
    [_composeWindow endEditingFor: nil];
	[NSApp endSheet: _composeWindow];
    [_composeWindow orderOut: self];
}

- (IBAction) cancelCompose: (id) sender {
    [_composeWindow endEditingFor: nil];
    [NSApp endSheet: _composeWindow];
    [_composeWindow orderOut: self];
}

- (IBAction) setUnderline: (id) sender {
	NSTextStorage *storage = [_composeText textStorage];
	NSRange selectedRange = [_composeText selectedRange];
	// get the underline style attribute of the first character in the text view
	id underlineStyle = [storage attribute: NSUnderlineStyleAttributeName atIndex: selectedRange.location effectiveRange: nil];
	// if already underlined, then the user is meant to remove the line.
	if ([underlineStyle intValue] == NSUnderlineStyleNone)
		[storage addAttribute: NSUnderlineStyleAttributeName value: [NSNumber numberWithInt: NSUnderlineStyleSingle] range: selectedRange];
	else
		[storage addAttribute: NSUnderlineStyleAttributeName value: [NSNumber numberWithInt: NSUnderlineStyleNone] range: selectedRange];
}

- (IBAction) setBlink: (id) sender {
	NSTextStorage *storage = [_composeText textStorage];
	NSRange selectedRange = [_composeText selectedRange];
	NSFontManager *fontManager = [NSFontManager sharedFontManager];
	// get the bold style attribute of the first character in the text view
	NSFont *font = [storage attribute: NSFontAttributeName atIndex: selectedRange.location effectiveRange: nil];
	NSFontTraitMask traits = [fontManager traitsOfFont: font];
	NSFont *newFont;
	if (traits & NSBoldFontMask)
		newFont = [fontManager convertFont: font toNotHaveTrait: NSBoldFontMask];
	else
		newFont = [fontManager convertFont: font toHaveTrait: NSBoldFontMask];
		
	[storage addAttribute: NSFontAttributeName value: newFont range: [_composeText selectedRange]];
}

#pragma mark -
#pragma mark Post Download

- (void)preparePostDownload:(id)param {
    // clear s
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init]; 
    NSString *s = [KOPostDownloader downloadPostFromConnection:[_telnetView frontMostConnection]];
    [_postText performSelectorOnMainThread:@selector(setString:) withObject:s waitUntilDone:TRUE];
    [pool release];
}

- (IBAction)openPostDownload:(id)sender {
    [_postText setString:@""];
    [NSThread detachNewThreadSelector:@selector(preparePostDownload:) toTarget:self withObject:self];
    [NSApp beginSheet:_postWindow modalForWindow:_mainWindow modalDelegate:nil didEndSelector:nil contextInfo:nil];
}

- (IBAction)cancelPostDownload:(id)sender {
    [_postWindow endEditingFor:nil];
    [NSApp endSheet:_postWindow];
    [_postWindow orderOut:self];

}

#pragma mark -
#pragma mark Remote Control
/* Remote Control */
- (void) remoteButton: (RemoteControlEventIdentifier) buttonIdentifier 
		  pressedDown: (BOOL) pressedDown 
		   clickCount: (unsigned int) clickCount {
	NSString *cmd = nil;

	if (!pressedDown) {	// release
		switch(buttonIdentifier) {
			case kRemoteButtonPlus:		// up
				if (clickCount == 1)
					cmd = termKeyUp;
				else
					cmd = termKeyPageUp;
				break;
			case kRemoteButtonMinus:	// down
				if (clickCount == 1)
					cmd = termKeyDown;
				else
					cmd = termKeyPageDown;
				break;			
			case kRemoteButtonMenu:
				break;
			case kRemoteButtonPlay:
				cmd = termKeyEnter;
				break;			
			case kRemoteButtonRight:	// right
				if (clickCount == 1)
					cmd = termKeyRight;
				else
					cmd = termKeyEnd;
				break;			
			case kRemoteButtonLeft:		// left
				if (clickCount == 1)
					cmd = termKeyLeft;
				else
					cmd = termKeyHome;
				break;			
			case kRemoteButtonPlus_Hold:
				[self disableTimer];
				break;				
			case kRemoteButtonMinus_Hold:
				[self disableTimer];
				break;				
			case kRemoteButtonPlay_Hold:
				break;
		}
	}
	else { // Key Press
		switch(buttonIdentifier) {
			case kRemoteButtonRight_Hold:	// Right Tab
				[self selectNextTab:self];
				break;
			case kRemoteButtonLeft_Hold:	// Left Tab
				[self selectPrevTab:self];
				break;
			case kRemoteButtonPlus_Hold:
				// Enable timer!
				[self disableTimer];
				_scrollTimer = [[NSTimer scheduledTimerWithTimeInterval:scrollTimerInterval 
									  target:self 
									  selector:@selector(doScrollUp:)
									  userInfo:nil
									  repeats:YES] retain];
				break;
			case kRemoteButtonMinus_Hold:
				// Enable timer!
				[self disableTimer];
				_scrollTimer = [[NSTimer scheduledTimerWithTimeInterval:scrollTimerInterval
									  target:self 
									  selector:@selector(doScrollDown:)
									  userInfo:nil
									  repeats:YES] retain];
				break;
			case kRemoteButtonMenu_Hold:
				[self fullScreenMode:nil];
				break;
		}
	}
	
	if (cmd != nil) {
		[[_telnetView frontMostConnection] sendText:cmd];
	}
}

// for timer
- (void)doScrollDown:(NSTimer*)timer {
    [[_telnetView frontMostConnection] sendText:termKeyDown];
}

- (void)doScrollUp:(NSTimer*)timer {
    [[_telnetView frontMostConnection] sendText:termKeyUp];
}

- (void)disableTimer {
    [_scrollTimer invalidate];
    [_scrollTimer release];
    _scrollTimer = nil;
}

// for bindings access
- (RemoteControl*) remoteControl {
    return remoteControl;
}

- (MultiClickRemoteBehavior*) remoteBehavior {
    return remoteControlBehavior;
}
#pragma mark -
#pragma mark For Portal
- (void) checkPortal {
	if([[NSUserDefaults standardUserDefaults] boolForKey:@"Portal"]) {
		[_telnetView checkPortal];
	}
}

#pragma mark -
#pragma mark For full screen
// Here is an example to the newly designed full screen module with a customized processor
// A "processor" here will resize the NSViews and do some necessary work before full
// screen
- (IBAction)fullScreenMode:(id)sender {
	if([_fullScreenController getProcessor] == nil) {
		LLTelnetProcessor* myPro = [[LLTelnetProcessor alloc] initByView:_telnetView 
															   myTabView:_tab 
															  effectView:((KOEffectView*)[_telnetView getEffectView])];
		[_fullScreenController setProcessor:myPro];
	}
	[_fullScreenController handleFullScreen];
}

#pragma mark -
#pragma mark Site View Drag & Drop
- (BOOL)tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard*)pboard {
    // copy to the pasteboard.
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:rowIndexes];
    [pboard declareTypes:[NSArray arrayWithObject:SiteTableViewDataType] owner:self];
    [pboard setData:data forType:SiteTableViewDataType];
    return YES;
}

- (NSDragOperation)tableView:(NSTableView*)tv validateDrop:(id <NSDraggingInfo>)info
                   proposedRow:(int)row proposedDropOperation:(NSTableViewDropOperation)op {
    // don't hover
    if (op == NSTableViewDropOn)
        return NSDragOperationNone;
    return NSDragOperationEvery;
}

- (BOOL)tableView:(NSTableView *)aTableView acceptDrop:(id <NSDraggingInfo>)info
        row:(int)row dropOperation:(NSTableViewDropOperation)op {
    NSPasteboard* pboard = [info draggingPasteboard];
    NSData* rowData = [pboard dataForType:SiteTableViewDataType];
    NSIndexSet* rowIndexes = [NSKeyedUnarchiver unarchiveObjectWithData:rowData];
    int dragRow = [rowIndexes firstIndex];
    // move
    NSObject *obj = [_sites objectAtIndex:dragRow];
    [_sitesController insertObject:obj atArrangedObjectIndex:row];
    if (row < dragRow)
        ++dragRow;
    [_sitesController removeObjectAtArrangedObjectIndex:dragRow];
    // done
    return YES;
}

- (YLView *) getView {
	return _telnetView;
}

// for portal
- (IBAction)browseImage:(id)sender {
	[_sitesWindow setLevel:0];
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	[openPanel beginSheetForDirectory:@"~"
								 file:nil
								types:[NSArray arrayWithObjects:@"jpg", @"jpeg", @"bmp", @"png", @"gif", @"tiff", @"tif", nil]
					   modalForWindow:_sitesWindow
						modalDelegate:self
					   didEndSelector:@selector(openPanelDidEnd:returnCode:contextInfo:)
						  contextInfo:nil];
	//[openPanel setLevel:floatWindowLevel + 1];
}

- (void) removeImage {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	// Get the destination dir
	NSString *destination = [[[[[NSHomeDirectory() stringByAppendingPathComponent:@"Library"]
								stringByAppendingPathComponent:@"Application Support"]
							   stringByAppendingPathComponent:@"Welly"]
							  stringByAppendingPathComponent:@"Covers"]
							 stringByAppendingPathComponent:[_siteNameField stringValue]];
	
	// For all allowed types
	NSArray *allowedTypes = [NSArray arrayWithObjects:@"jpg", @"jpeg", @"bmp", @"png", @"gif", @"tiff", @"tif", nil];
	for (NSString *ext in allowedTypes) {
		// Remove it!
		[fileManager removeItemAtPath:[destination stringByAppendingPathExtension:ext] error:NULL];
	}
}

- (IBAction) removeSiteImage:(id)sender {
	[_sitesWindow setAlphaValue:0];
	NSAlert *alert = [NSAlert alertWithMessageText:NSLocalizedString(@"Are you sure you want to delete the cover?", @"Sheet Title")
									 defaultButton:NSLocalizedString(@"Delete", @"Default Button")
								   alternateButton:NSLocalizedString(@"Cancel", @"Cancel Button")
									   otherButton:nil
						 informativeTextWithFormat:NSLocalizedString(@"Welly will delete this cover file, please confirm.", @"Sheet Message")];
	if ([alert runModal] == NSAlertDefaultReturn)
		[self removeImage];
	[_sitesWindow setAlphaValue:100];
}

- (void)openPanelDidEnd:(NSOpenPanel *)sheet
			 returnCode:(int)returnCode
			contextInfo:(void *)contextInfo {
	if (returnCode == NSOKButton) {
		NSFileManager *fileManager = [NSFileManager defaultManager];
		NSString *source = [sheet filename];
		// Create the dir if necessary
		// by gtCarrera
		NSString *destDir = [[[NSHomeDirectory() stringByAppendingPathComponent:@"Library"]
							   stringByAppendingPathComponent:@"Application Support"]
							 stringByAppendingPathComponent:@"Welly"];
		[fileManager createDirectoryAtPath:destDir attributes:nil];
		destDir = [destDir stringByAppendingPathComponent:@"Covers"];
		[fileManager createDirectoryAtPath:destDir attributes:nil];
		
 		NSString *destination = [destDir stringByAppendingPathComponent:[_siteNameField stringValue]];
		// Ends here
		
		NSArray *allowedTypes = [NSArray arrayWithObjects:@"jpg", @"jpeg", @"bmp", @"png", @"gif", @"tiff", @"tif", nil];
		for (NSString *ext in allowedTypes) {
			[fileManager removeItemAtPath:[destination stringByAppendingPathExtension:ext] error:NULL];
		}
		[fileManager copyItemAtPath:source toPath:[destination stringByAppendingPathExtension:[source pathExtension]] error:NULL];
	}
}

@end