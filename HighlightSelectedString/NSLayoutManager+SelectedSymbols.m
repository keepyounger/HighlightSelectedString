//
//  NSLayoutManager+SelectedSymbols.m
//  HighlightSelectedString
//
//  Created by lixy on 16/2/19.
//  Copyright © 2016年 lixy. All rights reserved.
//

#import "NSLayoutManager+SelectedSymbols.h"
#import <objc/runtime.h>

static const char kHighlightLayoutManagerKey;

@implementation NSLayoutManager (SelectedSymbols)

- (NSArray *)autoHighlightTokenRanges
{
    return nil;
}

- (void)setAutoHighlightTokenRanges:(NSArray *)autoHighlightTokenRanges
{
    
}

- (void)setHighlightKey:(NSString *)highlightKey
{
    objc_setAssociatedObject(self, &kHighlightLayoutManagerKey, highlightKey, OBJC_ASSOCIATION_COPY);
}

- (NSString *)highlightKey
{
    NSString *hilightKey = objc_getAssociatedObject(self, &kHighlightLayoutManagerKey);
    return hilightKey;
}

@end
