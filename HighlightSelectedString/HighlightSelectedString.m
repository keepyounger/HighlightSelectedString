//
//  HighlightSelectedString.m
//  HighlightSelectedString
//
//  Created by lixy on 15/1/23.
//  Copyright (c) 2015年 lixy. All rights reserved.
//

#import "HighlightSelectedString.h"
#import <objc/runtime.h>

static HighlightSelectedString *sharedPlugin;

@interface HighlightSelectedString()

@property (nonatomic,copy) NSString *selectedText;

@property (nonatomic, unsafe_unretained) NSTextView *sourceTextView;
@property (readonly) NSTextStorage *textStorage;
@property (readonly) NSString *string;

@property (nonatomic, strong) NSMenuItem *aMenuItem;
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
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidFinishLaunching:)
                                                     name:NSApplicationDidFinishLaunchingNotification
                                                   object:nil];
        
    }
    return self;
}

- (void)applicationDidFinishLaunching: (NSNotification*)noti {
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(selectionDidChange:)
                                                 name:NSTextViewDidChangeSelectionNotification
                                               object:nil];
    
    NSUserDefaults *userD = [NSUserDefaults standardUserDefaults];

    NSArray *array = [userD objectForKey:@"highlightColor"];
    if (array) {
        
        CGFloat red = [array[0] floatValue];
        CGFloat green = [array[1] floatValue];
        CGFloat blue = [array[2] floatValue];
        CGFloat alpha = [array[3] floatValue];
        
        _highlightColor = [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:alpha];

        
    } else {
        _highlightColor = [NSColor colorWithCalibratedRed:1.000 green:0.992 blue:0.518 alpha:1.000];

    }
    
    
    NSMenuItem *editMenuItem = [[NSApp mainMenu] itemWithTitle:@"Edit"];
    
    NSInteger state = [userD objectForKey:@"selectedState"]?[[userD objectForKey:@"selectedState"] integerValue]:1;
    
    if (editMenuItem) {
        [[editMenuItem submenu] addItem:[NSMenuItem separatorItem]];
        _aMenuItem = [[NSMenuItem alloc] initWithTitle:@"Highlight Selected String" action:@selector(enableState) keyEquivalent:@""];
        [_aMenuItem setTarget:self];
        _aMenuItem.state = state;
        [[editMenuItem submenu] addItem:_aMenuItem];
        
        NSMenuItem *setting = [[NSMenuItem alloc] initWithTitle:@"Set Highlight Color" action:@selector(setHighlightColor) keyEquivalent:@""];
        [setting setTarget:self];
        [[editMenuItem submenu] addItem:setting];
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

    self.highlightColor = panel.color;

    CGFloat red = 0;
    CGFloat green = 0;
    CGFloat blue = 0;
    CGFloat alpha = 0;

    [self.highlightColor getRed:&red green:&green blue:&blue alpha:&alpha];

    NSArray *array = @[@(red), @(green), @(blue), @(alpha)];
    NSUserDefaults *userD = [NSUserDefaults standardUserDefaults];
    [userD setObject:array forKey:@"highlightColor"];
    [userD synchronize];

}

- (void)enableState
{
    _aMenuItem.state = _aMenuItem.state == 1? 0 : 1;
    
    if (_aMenuItem.state == 0) {
        [self removeAllHighlighting];
    }
    
    NSUserDefaults *userD = [NSUserDefaults standardUserDefaults];
    [userD setObject:@(_aMenuItem.state) forKey:@"selectedState"];
    [userD synchronize];
}

-(void)selectionDidChange:(NSNotification *)noti {
    
    if ([[noti object] isKindOfClass:[NSTextView class]]) {
        
        NSTextView *textView = [noti object];
        
        if (_aMenuItem.state == 0) {
            return;
        }
        
        NSString *className = NSStringFromClass([textView class]);
        
        if ([className isEqualToString:@"DVTSourceTextView"]/* 代码编辑器 */ || [className isEqualToString:@"IDEConsoleTextView"] /* 控制台 */) {
            
            self.sourceTextView = textView;

            //延迟0.1秒执行高亮
            [[self class] cancelPreviousPerformRequestsWithTarget:self selector:@selector(todoSomething) object:nil];
            [self performSelector:@selector(todoSomething) withObject:nil afterDelay:0.1f];
            
        }

    }
}
- (void)todoSomething
{
    NSTextView *textView = self.sourceTextView;
    
    //每次高亮 都撤销之前高亮
    [self removeAllHighlighting];

    NSRange selectedRange = [textView selectedRange];
    NSString *text = textView.textStorage.string;
    NSString *nSelectedStr = [[text substringWithRange:selectedRange] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \n"]];
    
    //如果新选中的长度为0 就不执行任何操作
    if (!nSelectedStr.length) {
        return;
    }
    
    self.selectedText = nSelectedStr;
    
    if (self.selectedText.length) {
        [self highlightSelectedStrings];
    }

}


#pragma mark Highlighting
- (void)highlightSelectedStrings
{
    NSArray *array = [self rangesOfString:self.selectedText];
    if (array.count<2) {
        return;
    }
    
    [self addBgColorWithRangArray:array];
    
}

- (void)addBgColorWithRangArray:(NSArray*)rangeArray
{
    NSTextView *textView = self.sourceTextView;
    
    [rangeArray enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
       
        NSValue *value = obj;
        NSRange range = [value rangeValue];
        [textView.layoutManager addTemporaryAttribute:NSBackgroundColorAttributeName value:_highlightColor forCharacterRange:range];
    }];
    
    [textView setNeedsDisplay:YES];
    
}

- (NSMutableArray*)rangesOfString:(NSString *)string
{
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
    NSRange documentRange = NSMakeRange(0, [[self.textStorage string] length]);
    
    NSTextView *textView = self.sourceTextView;

    [textView.layoutManager removeTemporaryAttribute:NSBackgroundColorAttributeName forCharacterRange:documentRange];
    
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

