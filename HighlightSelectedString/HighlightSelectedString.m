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

#define HighlightColorKey @"HighlightColorKey"
#define HighlightEnableStateKey @"HighlightEnableStateKey"
#define HighlightOnlySymbolsKey @"HighlightOnlySymbolsKey"

static const char hilightStateKey;

static HighlightSelectedString *sharedPlugin;

@interface HighlightSelectedString()

@property (nonatomic,copy) NSString *selectedText;

@property (nonatomic, unsafe_unretained) NSTextView *sourceTextView;
@property (readonly) NSTextStorage *textStorage;
@property (readonly) NSString *string;

@property (nonatomic, strong) NSMenuItem *enableMenuItem;
@property (nonatomic, strong) NSMenuItem *onlySymbolsMenuItem;

@property (nonatomic, strong) NSColor *highlightColor;

@property (nonatomic, assign) BOOL enable;
@property (nonatomic, assign) BOOL onlySymbols;

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
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidFinishLaunching:)
                                                     name:NSApplicationDidFinishLaunchingNotification
                                                   object:nil];
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
    
    self.enable = [userD objectForKey:HighlightEnableStateKey]?[[userD objectForKey:HighlightEnableStateKey] integerValue]:1;
    
    self.onlySymbols = [userD objectForKey:HighlightOnlySymbolsKey]?[[userD objectForKey:HighlightOnlySymbolsKey] integerValue]:1;
    
    if (editMenuItem) {
        
        [[editMenuItem submenu] addItem:[NSMenuItem separatorItem]];
        
        self.enableMenuItem = [[NSMenuItem alloc] initWithTitle:@"Highlight Selected String" action:@selector(enableState) keyEquivalent:@""];
        [self.enableMenuItem setTarget:self];
        self.enableMenuItem.state = self.enable;
        [[editMenuItem submenu] addItem:self.enableMenuItem];
        
        self.onlySymbolsMenuItem = [[NSMenuItem alloc] initWithTitle:@"Only Highlight Symbols" action:@selector(onlySymbolsState) keyEquivalent:@""];
        [self.onlySymbolsMenuItem setTarget:self];
        self.onlySymbolsMenuItem.state = self.onlySymbols;
        [[editMenuItem submenu] addItem:self.onlySymbolsMenuItem];
        
        NSMenuItem *setting = [[NSMenuItem alloc] initWithTitle:@"Set Highlight Color" action:@selector(setHighlightColor) keyEquivalent:@""];
        [setting setTarget:self];
        [[editMenuItem submenu] addItem:setting];
    }
    
}

- (void)setEnable:(BOOL)enable
{
    _enable = enable;
    
    if (!enable) {
        [self removeAllHighlighting];
    }
    
    [self addOrRemoveNotificationWithState:enable];
}

- (void)enableState
{
    self.enableMenuItem.state = !self.enableMenuItem.state;
    self.enable = self.enableMenuItem.state;
    
    if (!self.enable) {
        self.onlySymbolsMenuItem.state = self.enable;
        self.onlySymbols = self.enable;
        NSUserDefaults *userD = [NSUserDefaults standardUserDefaults];
        [userD setObject:@(self.onlySymbols) forKey:HighlightOnlySymbolsKey];
        [userD synchronize];
    }
    
    NSUserDefaults *userD = [NSUserDefaults standardUserDefaults];
    [userD setObject:@(self.enable) forKey:HighlightEnableStateKey];
    [userD synchronize];
}

- (void)onlySymbolsState
{
    if (!self.enable) {
        return;
    }
    self.onlySymbolsMenuItem.state = !self.onlySymbolsMenuItem.state;
    self.onlySymbols = self.onlySymbolsMenuItem.state;
    
    NSUserDefaults *userD = [NSUserDefaults standardUserDefaults];
    [userD setObject:@(self.onlySymbols) forKey:HighlightOnlySymbolsKey];
    [userD synchronize];
}

- (void)addOrRemoveNotificationWithState:(BOOL)state
{
    if (!state) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSTextViewDidChangeSelectionNotification object:nil];
    } else {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(selectionDidChange:)
                                                     name:NSTextViewDidChangeSelectionNotification
                                                   object:nil];
    }
}

- (void)setOnlySymbols:(BOOL)onlySymbols
{
    _onlySymbols = onlySymbols;
    [self addOrRemoveNotificationWithOnlySymbols:onlySymbols];
    [self resetHighlight];
}

- (void)addOrRemoveNotificationWithOnlySymbols:(BOOL)state
{
    if (!state) {
        [[NSNotificationCenter defaultCenter]
         removeObserver:self
         name:@"DVTSourceExpressionSelectedExpressionDidChangeNotification"
         object:nil];
    } else {
        [[NSNotificationCenter defaultCenter]
         addObserver:self
         selector:@selector(expressionDidChange:)
         name:@"DVTSourceExpressionSelectedExpressionDidChangeNotification"
         object:nil];
    }
}

- (void)resetHighlight
{
    [self removeAllHighlighting];
    
    NSArray *rangesArray = nil;
    if (self.onlySymbols) {
        rangesArray = self.sourceTextView.layoutManager.autoHighlightTokenRanges;
    } else {
        rangesArray = [self rangesOfString:self.selectedText];
    }
    
    if (rangesArray.count>1) {
        [self addBgColorWithRangeArray:rangesArray];
    }
}

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

-(void)selectionDidChange:(NSNotification *)noti {
    
    self.sourceTextView =  [noti object];
    
    if ([[noti object] isKindOfClass:[NSTextView class]]) {
        
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
}

- (void)expressionDidChange:(NSNotification *)noti
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

- (void)todoSomething
{
    [self highlightSelectedStrings];
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

#pragma mark Highlighting
- (void)highlightSelectedStrings
{
    if (self.onlySymbols) {
        return;
    }
    
    //每次高亮 都撤销之前高亮
    [self removeAllHighlighting];
    
    NSArray *array = [self rangesOfString:self.selectedText];
    
    if (array.count<2) {
        return;
    }
    
    [self addBgColorWithRangeArray:array];
}

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

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
