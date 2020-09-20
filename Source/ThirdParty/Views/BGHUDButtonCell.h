//
//  BGHUDButtonCell.h
//  BGHUDAppKit
//
//  Created by BinaryGod on 5/25/08.
//
//  Copyright (c) 2008, Tim Davis (BinaryMethod.com, binary.god@gmail.com)
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without modification,
//  are permitted provided that the following conditions are met:
//
//		Redistributions of source code must retain the above copyright notice, this
//	list of conditions and the following disclaimer.
//
//		Redistributions in binary form must reproduce the above copyright notice,
//	this list of conditions and the following disclaimer in the documentation and/or
//	other materials provided with the distribution.
//
//		Neither the name of the BinaryMethod.com nor the names of its contributors
//	may be used to endorse or promote products derived from this software without
//	specific prior written permission.
//
//	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS AS IS AND
//	ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//	WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
//	IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
//	INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
//	BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,
//	OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
//	WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//	ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
//	POSSIBILITY OF SUCH DAMAGE.

#import <Cocoa/Cocoa.h>

NS_INLINE CGFloat BGCenterX(NSRect aRect) {
	return (aRect.size.width / 2);
}

NS_INLINE CGFloat BGCenterY(NSRect aRect) {
	return (aRect.size.height / 2);
}

@interface BGHUDButtonCell : NSButtonCell {
	BOOL isMouseIn;
	NSString *themeKey;
	NSButtonType buttonType;
}

@property (retain) NSString *themeKey;

-(void)drawCheckInFrame:(NSRect)frame isRadio:(BOOL)radio;
-(void)drawTexturedRoundedButtonInFrame:(NSRect)frame;
-(void)drawRoundRectButtonInFrame:(NSRect)frame;
-(void)drawSmallSquareButtonInFrame:(NSRect)frame;
-(void)drawRoundedButtonInFrame:(NSRect)frame;
-(void)drawRecessedButtonInFrame:(NSRect)frame;

@end
