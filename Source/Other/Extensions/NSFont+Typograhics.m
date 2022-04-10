//
//  NSFont+Typograhics.m
//  Sequel Ace
//
//  Created by Stefan on 10.04.22.
//  Copyright © 2022 Sequel-Ace. All rights reserved.
//

#import "NSFont+Typograhics.h"

@implementation NSFont (Typograhics)

-(NSFont *)sp_monospacedNumbersFont
{
    CTFontDescriptorRef origDesc = CTFontCopyFontDescriptor((__bridge CTFontRef)self);
    CTFontDescriptorRef monoDesc = CTFontDescriptorCreateCopyWithFeature(origDesc, (__bridge CFNumberRef)@(kNumberSpacingType), (__bridge CFNumberRef)@(kMonospacedNumbersSelector));
    CFRelease(origDesc);
    CTFontRef monoFont = CTFontCreateWithFontDescriptor(monoDesc, self.pointSize, NULL);
    CFRelease(monoDesc);
    return (__bridge_transfer NSFont *)monoFont;
}

@end
