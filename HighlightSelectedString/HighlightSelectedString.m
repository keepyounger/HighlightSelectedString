//
//  HighlightSelectedString.m
//  HighlightSelectedString
//
//  Created by lixy on 15/1/23.
//  Copyright (c) 2015年 lixy. All rights reserved.
//

#import "HighlightSelectedString.h"
#import "NSLayoutManager+SelectedSymbols.h"
#import <objc/runtime.h>
#import "Aspects.h"

#define HighlightColorKey @"HighlightColorKey"
#define HighlightEnableStateKey @"HighlightEnableStateKey"
#define HighlightOnlySymbolsKey @"HighlightOnlySymbolsKey"
#define HighlightDoubleClickKey @"HighlightDoubleClickKey"


static const char hilightStateKey;

static HighlightSelectedString *sharedPlugin;

@interface HighlightSelectedString()

@property (nonatomic,copy) NSString *selectedText;

@property (nonatomic, unsafe_unretained) NSTextView *sourceTextView;
@property (readonly) NSTextStorage *textStorage;
@property (readonly) NSString *string;

@property (nonatomic, strong) NSMenuItem *enableMenuItem;
@property (nonatomic, strong) NSMenuItem *symbolsOnlyMenuItem;
@property (nonatomic, strong) NSMenuItem *doubleClickMenuItem;

@property (nonatomic, strong) NSColor *highlightColor;

@end

@implementation HighlightSelectedString

+ (void)pluginDidLoad:(NSBundle *)plugin
{
    static dispatch_once_t onceToken;
    NSString *currentApplicationName = [[NSBundle mainBundle] infoDictionary][@"CFBundleName"];
    if ([currentApplicationName isEqual:@"Xcode"]) {
        dispatch_once(&onceToken, ^{
            sharedPlugin = [[self alloc] initWithBundle:plugin];
        });
    }
}

+ (instancetype)sharedPlugin
{
    return sharedPlugin;
}

- (id)initWithBundle:(NSBundle *)plugin
{
    if (self = [super init]) {
        //一定要在初始化的时候添加Observer 否则会意外崩溃
        [self addObserverAndNotifitions];
    }
    return self;
}

- (void)applicationDidFinishLaunching: (NSNotification*)noti
{
    [self loadConfig];
    [self loadMenuItems];
}

- (void)loadConfig
{
    NSUserDefaults *userD = [NSUserDefaults standardUserDefaults];
    NSArray *array = [userD objectForKey:HighlightColorKey];
    
    if (array) {
        CGFloat red = [array[0] floatValue];
        CGFloat green = [array[1] floatValue];
        CGFloat blue = [array[2] floatValue];
        CGFloat alpha = [array[3] floatValue];
        
        _highlightColor = [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:alpha];
        
    } else {
        _highlightColor = [NSColor colorWithCalibratedRed:1.000 green:0.992 blue:0.518 alpha:1.000];
    }
}

- (void)loadMenuItems
{
    NSUserDefaults *userD = [NSUserDefaults standardUserDefaults];
    NSMenuItem *editMenuItem = [[NSApp mainMenu] itemWithTitle:@"Edit"];
    
    BOOL enableState = [userD objectForKey:HighlightEnableStateKey]?[[userD objectForKey:HighlightEnableStateKey] integerValue]:1;
    
    BOOL symbolsOnlyState = [userD objectForKey:HighlightOnlySymbolsKey]?[[userD objectForKey:HighlightOnlySymbolsKey] integerValue]:1;
    
    BOOL doubleClickState = [userD objectForKey:HighlightDoubleClickKey]?[[userD objectForKey:HighlightDoubleClickKey] integerValue]:0;
    
    if (editMenuItem) {
        [[editMenuItem submenu] addItem:[NSMenuItem separatorItem]];
        
        NSMenu *highlightMenu = [[NSMenu alloc] initWithTitle:@"Highlight Menu"];
        
        self.enableMenuItem = [[NSMenuItem alloc] initWithTitle:@"Enable Highlight" action:@selector(enableClick) keyEquivalent:@""];
        [self.enableMenuItem setTarget:self];
        [self.enableMenuItem setState:enableState];
        [highlightMenu addItem:self.enableMenuItem];
        
        NSMenu *symbolsOnlyMenu = [[NSMenu alloc] initWithTitle:@"Symbols Only Menu"];
        
        self.symbolsOnlyMenuItem = [[NSMenuItem alloc] initWithTitle:@"Enable" action:NULL keyEquivalent:@""];
        [self.symbolsOnlyMenuItem setTarget:self];
        [self.symbolsOnlyMenuItem setState:symbolsOnlyState];
        [self.symbolsOnlyMenuItem setAction:enableState?@selector(symbolsOnlyClick):NULL];
        [symbolsOnlyMenu addItem:self.symbolsOnlyMenuItem];
        
        self.doubleClickMenuItem = [[NSMenuItem alloc] initWithTitle:@"Double Click" action:NULL keyEquivalent:@""];
        [self.doubleClickMenuItem setTarget:self];
        [self.doubleClickMenuItem setState:doubleClickState];
        [self.doubleClickMenuItem setAction:(enableState && self.symbolsOnlyMenuItem.state)?@selector(doubleClick):NULL];
        [symbolsOnlyMenu addItem:self.doubleClickMenuItem];
        
        NSMenuItem *symbolsOnlyMenuItem = [[NSMenuItem alloc] initWithTitle:@"Symbols Only" action:nil keyEquivalent:@""];
        [symbolsOnlyMenuItem setSubmenu:symbolsOnlyMenu];
        [highlightMenu addItem:symbolsOnlyMenuItem];
        
        NSMenuItem *setting = [[NSMenuItem alloc] initWithTitle:@"Set Highlight Color" action:@selector(setHighlightColor) keyEquivalent:@""];
        [setting setTarget:self];
        [highlightMenu addItem:setting];
        
        NSMenuItem *highlightMenuItem = [[NSMenuItem alloc] initWithTitle:@"Highlight" action:nil keyEquivalent:@""];
        [highlightMenuItem setSubmenu:highlightMenu];
        [[editMenuItem submenu] addItem:highlightMenuItem];
    }
    
}

- (void)addObserverAndNotifitions
{
    [NSLayoutManager aspect_hookSelector:@selector(init) withOptions:AspectPositionAfter usingBlock:^( id<AspectInfo> info) {
        NSLayoutManager *layoutM = [info instance];
        layoutM.highlightKey = @"1";
        [layoutM addObserver:self forKeyPath:@"autoHighlightTokenRanges" options:NSKeyValueObservingOptionNew context:nil];
        
    } error:nil];
    
    [NSLayoutManager aspect_hookSelector:NSSelectorFromString(@"dealloc") withOptions:AspectPositionBefore usingBlock:^( id<AspectInfo> info) {
        
        NSLayoutManager *layoutM = [info instance];
        if (layoutM.highlightKey.intValue==1) {
            [layoutM removeObserver:self forKeyPath:@"autoHighlightTokenRanges"];
        }
        
    } error:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(selectionDidChange:)
                                                 name:NSTextViewDidChangeSelectionNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidFinishLaunching:)
                                                 name:NSApplicationDidFinishLaunchingNotification
                                               object:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context
{
    if ([keyPath isEqualToString:@"autoHighlightTokenRanges"]) {
        NSLayoutManager *manager = object;
        if (manager.firstTextView == self.sourceTextView) {
            if (self.enableMenuItem.state) {
                if (self.symbolsOnlyMenuItem.state) {
                    if (!self.doubleClickMenuItem.state) {
                        [self highlightSelectedSymbols];
                    } else {
                        if (self.selectedText.length>0) {
                            [self highlightSelectedSymbols];
                        }
                    }
                }
            }
        }
    }
}

#pragma mark Highlight Selected String state
- (void)enableClick
{
    self.enableMenuItem.state = !self.enableMenuItem.state;
    
    if (!self.enableMenuItem.state) {
        
        [self removeAllHighlighting];
        self.symbolsOnlyMenuItem.action = NULL;
        self.doubleClickMenuItem.action = NULL;
        
    } else{
        self.symbolsOnlyMenuItem.action = @selector(symbolsOnlyClick);
        self.doubleClickMenuItem.action = @selector(doubleClick);
    }
    
    NSUserDefaults *userD = [NSUserDefaults standardUserDefaults];
    [userD setObject:@(self.enableMenuItem.state) forKey:HighlightEnableStateKey];
    [userD synchronize];
}

- (void)symbolsOnlyClick
{
    self.symbolsOnlyMenuItem.state = !self.symbolsOnlyMenuItem.state;
    
    if (!self.symbolsOnlyMenuItem.state) {
        self.doubleClickMenuItem.action = NULL;
    } else{
        self.doubleClickMenuItem.action = @selector(doubleClick);
    }
    
    [self resetHighlight];

    NSUserDefaults *userD = [NSUserDefaults standardUserDefaults];
    [userD setObject:@(self.symbolsOnlyMenuItem.state) forKey:HighlightOnlySymbolsKey];
    [userD synchronize];
}

- (void)doubleClick
{
    self.doubleClickMenuItem.state = !self.doubleClickMenuItem.state;
    
    NSUserDefaults *userD = [NSUserDefaults standardUserDefaults];
    [userD setObject:@(self.doubleClickMenuItem.state) forKey:HighlightDoubleClickKey];
    [userD synchronize];
}

#pragma mark Highlight color function
-(void)selectionDidChange:(NSNotification *)noti {
    
    NSTextView *textView = [noti object];
    NSString *className = NSStringFromClass([textView class]);
    
    if ([className isEqualToString:@"DVTSourceTextView"]/* 代码编辑器 */ || [className isEqualToString:@"IDEConsoleTextView"] /* 控制台 */) {
        
        if (self.sourceTextView != textView) {
            self.sourceTextView = textView;
        }
        
        //延迟0.1秒执行高亮
        [[self class] cancelPreviousPerformRequestsWithTarget:self selector:@selector(todoSomething) object:nil];
        [self performSelector:@selector(todoSomething) withObject:nil afterDelay:0.1f];
        
    }
}


- (void)todoSomething
{
    if (self.enableMenuItem.state) {
        NSString *className = NSStringFromClass([self.sourceTextView class]);
        
        if ([className isEqualToString:@"DVTSourceTextView"]/* 代码编辑器 */) {
            if (self.symbolsOnlyMenuItem.state) {
                if (self.doubleClickMenuItem.state) {
                    if (self.selectedText.length>0) {
                        [self highlightSelectedSymbols];
                    }
                    else {
                        [self removeAllHighlighting];
                    }
                }
            } else {
                [self highlightSelectedStrings];
            }

        } else {// 控制台 直接高亮
            [self highlightSelectedStrings];
        }
    }
}

- (NSString *)selectedText
{
    NSTextView *textView = self.sourceTextView;
    NSRange selectedRange = [textView selectedRange];
    NSString *text = textView.textStorage.string;
    NSString *nSelectedStr = [[text substringWithRange:selectedRange] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \n"]];
    
    //如果新选中的长度为0 就返回空
    if (!nSelectedStr.length) {
        return @"";
    }
    
    _selectedText = nSelectedStr;
    
    return _selectedText;
}

- (void)highlightSelectedStrings
{
    //每次高亮 都撤销之前高亮
    [self removeAllHighlighting];
    
    NSArray *array = [self rangesOfString:self.selectedText];
    
    if (array.count<2) {
        return;
    }
    
    [self addBgColorWithRangeArray:array];
}

- (NSMutableArray*)rangesOfString:(NSString *)string
{
    if (string.length == 0) {
        return nil;
    }
    
    NSUInteger length = [self.string length];
    
    NSRange searchRange = NSMakeRange(0, length);
    NSRange foundRange = NSMakeRange(0, 0);
    
    NSMutableArray *rangArray = [NSMutableArray array];
    
    while (YES)
    {
        foundRange = [self.string rangeOfString:string options:0 range:searchRange];
        NSUInteger searchRangeStart = foundRange.location + foundRange.length;
        searchRange = NSMakeRange(searchRangeStart, length - searchRangeStart);
        
        if (foundRange.location != NSNotFound)
        {
            [rangArray addObject:[NSValue valueWithRange:foundRange]];
        } else
            break;
    }
    return rangArray;
}


- (void)highlightSelectedSymbols
{
    NSString *className = NSStringFromClass([self.sourceTextView class]);
    
    if ([className isEqualToString:@"DVTSourceTextView"]/* 代码编辑器 */) {
        
        [self removeAllHighlighting];
        
        NSArray *array = self.sourceTextView.layoutManager.autoHighlightTokenRanges;
        if (array.count>1) {
            [self addBgColorWithRangeArray:array];
        }
        
    }
}

#pragma mark---Color rendering----
- (void)addBgColorWithRangeArray:(NSArray*)rangeArray
{
    NSTextView *textView = self.sourceTextView;
    
    [rangeArray enumerateObjectsUsingBlock:^(NSValue *value, NSUInteger idx, BOOL *stop) {
        NSRange range = [value rangeValue];
        [textView.layoutManager addTemporaryAttribute:NSBackgroundColorAttributeName value:_highlightColor forCharacterRange:range];
    }];
    
    [textView setNeedsDisplay:YES];
    if (textView) {
        objc_setAssociatedObject(textView, &hilightStateKey, @"1", OBJC_ASSOCIATION_COPY);
    }
}

- (void)resetHighlight
{
    [self removeAllHighlighting];
    
    NSArray *rangesArray = nil;
    if (self.symbolsOnlyMenuItem.state) {
        rangesArray = self.sourceTextView.layoutManager.autoHighlightTokenRanges;
    } else {
        rangesArray = [self rangesOfString:self.selectedText];
    }
    
    if (rangesArray.count>1) {
        [self addBgColorWithRangeArray:rangesArray];
    }
}

- (void)removeAllHighlighting   
{
    NSUInteger length = [[self.textStorage string] length];
    NSTextView *textView = self.sourceTextView;
    
    NSString *hilightState = objc_getAssociatedObject(textView, &hilightStateKey);
    if (![hilightState boolValue]) {
        return;
    }
    
    NSRange range = NSMakeRange(0, 0);
    for (int i=0; i<length;) {
        NSDictionary *dic = [textView.layoutManager temporaryAttributesAtCharacterIndex:i effectiveRange:&range];
        id obj = dic[NSBackgroundColorAttributeName];
        if (obj && [_highlightColor isEqual:obj]) {
            
            [textView.layoutManager removeTemporaryAttribute:NSBackgroundColorAttributeName forCharacterRange:range];
        }
        i += range.length;
    }
    
    [textView setNeedsDisplay:YES];
    
    if (textView) {
        objc_setAssociatedObject(textView, &hilightStateKey, @"0", OBJC_ASSOCIATION_RETAIN);
    }
}

#pragma mark Accessor Overrides
- (NSTextStorage *)textStorage
{
    return [self.sourceTextView textStorage];
}

- (NSString *)string
{
    return [self.textStorage string];
}

#pragma mark Set Highlight Color
// Based on: https://github.com/limejelly/Backlight-for-XCode
- (void)setHighlightColor
{
    NSColorPanel *panel = [NSColorPanel sharedColorPanel];
    panel.color = self.highlightColor;
    panel.target = self;
    panel.action = @selector(colorPanelColorDidChange:);
    [panel orderFront:nil];
    
    // Observe the closing of the color panel so we can remove ourself from the target.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(colorPanelWillClose:)
                                                 name:NSWindowWillCloseNotification object:nil];
    
}

- (void)colorPanelWillClose:(NSNotification *)notification
{
    NSColorPanel *panel = [NSColorPanel sharedColorPanel];
    if (panel == notification.object) {
        panel.target = nil;
        panel.action = nil;
        
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:NSWindowWillCloseNotification
                                                      object:nil];
    }
}

- (void)colorPanelColorDidChange:(id)sender
{
    NSColorPanel *panel = (NSColorPanel *)sender;
    
    if (!panel.color) return;
    
    CGFloat red = 0;
    CGFloat green = 0;
    CGFloat blue = 0;
    CGFloat alpha = 0;
    
    [panel.color getRed:&red green:&green blue:&blue alpha:&alpha];
    
    NSArray *array = @[@(red), @(green), @(blue), @(alpha)];
    NSUserDefaults *userD = [NSUserDefaults standardUserDefaults];
    [userD setObject:array forKey:HighlightColorKey];
    [userD synchronize];
    
    //想要预览高亮需要 移除再次添加
    [self removeAllHighlighting];
    
    self.highlightColor = panel.color;
    
    [self resetHighlight];
}

#pragma mark ---line---

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
