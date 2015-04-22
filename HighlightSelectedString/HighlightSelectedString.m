//
//  HighlightSelectedString.m
//  HighlightSelectedString
//
//  Created by lixy on 15/1/23.
//  Copyright (c) 2015年 lixy. All rights reserved.
//

#import "HighlightSelectedString.h"
#import "RCXcode.h"
#import <objc/runtime.h>

static HighlightSelectedString *sharedPlugin;

@interface HighlightSelectedString()

@property (nonatomic,copy) NSString *selectedText;

@property (readonly, unsafe_unretained) NSTextView *sourceTextView;
@property (readonly) NSTextStorage *textStorage;
@property (readonly) NSString *string;

@property (nonatomic) BOOL haveHighLight;
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
            object_setClass([NSColorPanel sharedColorPanel], [HighlightColorPanel class]);
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

        _haveHighLight = NO;
        
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
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(colorPanelColorDidChange:) name:NSColorPanelColorDidChangeNotification object:nil];
    
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

- (void)setHighlightColor
{
    [NSColorPanel sharedColorPanel].color = self.highlightColor;
    [[NSColorPanel sharedColorPanel] orderFront:self];

    objc_setAssociatedObject([NSColorPanel sharedColorPanel], &extrnPro, @"1", OBJC_ASSOCIATION_RETAIN);

}

- (void)colorPanelColorDidChange:(NSNotification*)not
{
    NSString *isHighlight = objc_getAssociatedObject([NSColorPanel sharedColorPanel], &extrnPro);
    
    if (isHighlight && [isHighlight boolValue]) {
        
        self.highlightColor = [NSColorPanel sharedColorPanel].color;
        
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

}

- (void)enableState
{
    _aMenuItem.state = _aMenuItem.state == 1? 0 : 1;
    
    if (_aMenuItem.state == 0 && _haveHighLight) {
        [self removeAllHighlighting];
    }
    
    NSUserDefaults *userD = [NSUserDefaults standardUserDefaults];
    [userD setObject:@(_aMenuItem.state) forKey:@"selectedState"];
    [userD synchronize];
}

-(void)selectionDidChange:(NSNotification *)noti {
    
    if ([NSColorPanel sharedColorPanel].isVisible) {
        [[NSColorPanel sharedColorPanel] orderOut:nil];
    }
    
    if ([[noti object] isKindOfClass:[NSTextView class]]) {
        
        IDESourceCodeDocument *document = [RCXcode currentSourceCodeDocument];
        NSTextView *textView = self.sourceTextView;
        
        if (!document || !textView || _aMenuItem.state == 0 || [noti object] != textView) {
            return;
        }
        
        //延迟0.1秒执行高亮
        [[self class] cancelPreviousPerformRequestsWithTarget:self selector:@selector(todoSomething) object:nil];
        [self performSelector:@selector(todoSomething) withObject:nil afterDelay:0.1f];

    }
}
- (void)todoSomething
{
    NSTextView *textView = self.sourceTextView;

    NSRange selectedRange = [textView selectedRange];
    
    if (selectedRange.length==0 && _haveHighLight) {
        [self removeAllHighlighting];
        return;
    } else if (selectedRange.length == 0) {
        return;
    }
    
    NSString *text = textView.textStorage.string;
    NSString *nSelectedStr = [[text substringWithRange:selectedRange] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \n"]];
    
    if (nSelectedStr.length && ![nSelectedStr isEqualToString:self.selectedText] &&_haveHighLight) {
        [self removeAllHighlighting];
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
    
    _haveHighLight = YES;

    NSTextStorage *textStorage = self.textStorage;
    
    if (textStorage.editedRange.location == NSNotFound) {
        
        [self addBgColorWithRangArray:array];
        
    }

}

- (void)addBgColorWithRangArray:(NSArray*)rangeArray
{
    NSTextView *textView = self.sourceTextView;
    
    [rangeArray enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
       
        NSValue *value = obj;
        NSRange range = [value rangeValue];
        [textView.layoutManager addTemporaryAttribute:NSBackgroundColorAttributeName value:_highlightColor forCharacterRange:range];
        [textView setNeedsDisplay:YES];
    }];
    
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
    _haveHighLight = NO;
    NSRange documentRange = NSMakeRange(0, [[self.textStorage string] length]);
    
    NSTextView *textView = self.sourceTextView;

    if (textView.textStorage.editedRange.location == NSNotFound) {
        
        [textView.layoutManager removeTemporaryAttribute:NSBackgroundColorAttributeName forCharacterRange:documentRange];
        
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

- (NSTextView *)sourceTextView
{
    return [RCXcode currentSourceCodeTextView];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

@implementation HighlightColorPanel

- (void)orderOut:(id)sender
{
    objc_setAssociatedObject(self, &extrnPro, @"0", OBJC_ASSOCIATION_RETAIN);
    [super orderOut:sender];
}

@end
