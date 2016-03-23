//
//  NSLayoutManager+SelectedSymbols.h
//  HighlightSelectedString
//
//  Created by lixy on 16/2/19.
//  Copyright © 2016年 lixy. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface NSLayoutManager (SelectedSymbols)

@property (nonatomic, copy) NSString *highlightKey;
@property(readonly, copy) NSArray <NSValue *> *autoHighlightTokenRanges; // @synthesize autoHighlightTokenRanges=_autoHighlightTokenRanges;

@end
