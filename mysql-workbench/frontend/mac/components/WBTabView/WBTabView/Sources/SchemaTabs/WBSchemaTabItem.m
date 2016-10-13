/*
 * Copyright (c) 2009, 2015, Oracle and/or its affiliates. All rights reserved.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; version 2 of the
 * License.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
 * 02110-1301  USA
 */

#import "WBSchemaTabItem.h"
#import "CGColorUtilities.h"

@implementation WBSchemaTabItem

- (void) updateAppearance;
{
	[super updateAppearance];
		
	[self setShadowOpacity: 0.0];
	
	if (mState == NSOnState) {
		[self setZPosition: -1];
		[mSideLeft setOpacity: 1];
		[mSideRight setOpacity: 1];
    [mBackgroundGradient setOpacity: 1];
	}
	else {
		[self setZPosition: -3];
		[mSideLeft setOpacity: 0];
		[mSideRight setOpacity: 0];
    [mBackgroundGradient setOpacity: 0];
	}
}



- (void) setLabel: (NSString*) label;
{
  [super setLabel: label];
	
	NSFont* font = [NSFont boldSystemFontOfSize: 11.5];
	NSDictionary* attributes = @{NSFontAttributeName: font};
	CGRect r = [mTitleLayer frame];
	r.size.width = ceil([mLabel sizeWithAttributes:attributes].width);
	[mTitleLayer setFrame: r];
}



- (CGFloat) preferredWidth;
{
	CGFloat preferredWidth = 0;
	
	NSFont* font = [NSFont boldSystemFontOfSize: 11.5];
	NSDictionary* attributes = @{NSFontAttributeName: font};
	CGFloat iconWidth = [mIcon frame].size.width + 9;
	
	CGFloat labelWidth = ceil([mLabel sizeWithAttributes:attributes].width);
	CGFloat preferredWidth1 = iconWidth + 5 + labelWidth + 9;

	font = [NSFont boldSystemFontOfSize: 9];
	attributes = @{NSFontAttributeName: font};
	labelWidth = ceil([@"MySQL Schema" sizeWithAttributes:attributes].width);
	CGFloat preferredWidth2 = iconWidth + 5 + labelWidth + 9;
	
	preferredWidth = MAX(preferredWidth1, preferredWidth2);
	
	return preferredWidth;
}

- (WBSchemaTabItem*) initWithIdentifier: (id) identifier
                                  label: (NSString*) label;
{
	self = [super init];
	
	if (self != nil) {
		mIdentifier = identifier;
		
		mHasIcon = YES;
		mTabDirection = WBTabDirectionUp;
		mTabPlacement = WBTabPlacementTop;
		
		mState = -1;
		
    CGColorRef noColor = WB_CGColorCreateCalibratedRGB(0, 0, 0, 0);
		[self setColorActiveSelected: noColor
          colorActiveNotSelected: noColor
          colorNotActiveSelected: noColor
		   colorNotActiveNotSelected: noColor];
		CGColorRelease(noColor);
    
		CGRect frame = CGRectZero;
		frame.size = CGSizeMake(120, 84);
		[self setFrame: frame];
		
		CGFloat horizon = frame.size.height / 2;
		
		{
			// Icon layer.
      NSBundle* b = [NSBundle bundleForClass: [self class]];
      NSString* path = [b pathForResource: @"SchemaTabIcon"
                                   ofType: @"png"];
			mIconImage = [[NSImage alloc] initWithContentsOfFile: path];

      if ([mIconImage.representations[0] isKindOfClass: NSBitmapImageRep.class])
      {
        //NSBitmapImageRep *imageRepresentation = (id)mIconImage.representations[0];
        //CGImageRef img = imageRepresentation.CGImage;
        mIcon = [CALayer layer];
        CGRect r = CGRectZero;
        r.size = NSSizeToCGSize([mIconImage size]);
        r.origin.x = 9;
        r.origin.y = floor(horizon + (horizon / 2) - (r.size.height / 2));
        [mIcon setFrame: r];
        //[mIcon setContents: img];
        mIcon.contents = mIconImage; // Directly supported on 10.6+.
        [self addSublayer: mIcon];
      }
		}
		
		{
			// Title layer.
			CGRect titleFrame = CGRectZero;
			CGRect r = [mIcon frame];
			titleFrame.origin.x = CGRectGetMaxX(r) + 6;
			titleFrame.origin.y = r.origin.y + (r.size.height / 2);
			titleFrame.size.height = 15;
			titleFrame.size.width = 100;
			
			mTitleLayer = [CATextLayer layer];
			[mTitleLayer setFrame: titleFrame];
			[mTitleLayer setAutoresizingMask: (kCALayerMaxXMargin | kCALayerMinYMargin)];
			
			CGColorRef c = WB_CGColorCreateCalibratedRGB(0.1, 0.1, 0.1, 1.0);
			[mTitleLayer setForegroundColor: c];
			CGColorRelease(c);
			NSFont* font = [NSFont boldSystemFontOfSize: 0];
			[mTitleLayer setFont: (__bridge CFTypeRef _Nullable)(font)];
			[mTitleLayer setFontSize: 11.5];
			
			[self addSublayer: mTitleLayer];
			[self setLabel: label];
			
			// Sub title "MySQL Schema".
			mTitleLayerB = [CATextLayer layer];
			titleFrame.origin.y = r.origin.y + (r.size.height / 2) - 15;
			[mTitleLayerB setFrame: titleFrame];
			[mTitleLayerB setAutoresizingMask: (kCALayerMaxXMargin | kCALayerMinYMargin)];
			c = WB_CGColorCreateCalibratedRGB(0.3, 0.3, 0.3, 1.0);
			[mTitleLayerB setForegroundColor: c];
			CGColorRelease(c);
			[mTitleLayerB setFont: (__bridge CFTypeRef _Nullable)(font)];
			[mTitleLayerB setFontSize: 9];
			[self addSublayer: mTitleLayerB];
			[mTitleLayerB setString: @"MySQL Schema"];
		}
		
		{
			// Side lines.
      NSBundle* b = [NSBundle bundleForClass: [self class]];
      NSString* path = [b pathForResource: @"SchemaTabSideLine"
                                   ofType: @"png"];
			mSideLineImage = [[NSImage alloc] initWithContentsOfFile: path];
      
      // CGImageRef img = [(id)[mSideLineImage representations][0] CGImage];
			CGRect r = CGRectMake(0, horizon, 1, frame.size.height / 2);
			mSideLeft = [CALayer layer];
			[mSideLeft setFrame: r];
			mSideLeft.contents = mSideLineImage;
			[mSideLeft setAutoresizingMask: (kCALayerMaxXMargin | kCALayerMinYMargin)];
			[self addSublayer: mSideLeft];

			r = CGRectMake(frame.size.width - 1, horizon, 1, frame.size.height / 2);
			mSideRight = [CALayer layer];
			[mSideRight setFrame: r];
			mSideRight.contents = mSideLineImage;
			[mSideRight setAutoresizingMask: (kCALayerMinXMargin | kCALayerMinYMargin)];
			[self addSublayer: mSideRight];
		}
    
    {
      // Gradient Background layer displayed when the tab is selected.
      NSBundle* b = [NSBundle bundleForClass: [self class]];
      NSString* path = [b pathForResource: @"SchemaTabGradientBackground"
                                   ofType: @"png"];
			mAlphaGradientImage = [[NSImage alloc] initWithContentsOfFile: path];
      //CGImageRef img = [(id)[mAlphaGradientImage representations][0] CGImage];
      mBackgroundGradient = [CALayer layer];
      mBackgroundGradient.contents = mAlphaGradientImage;
			CGRect r = CGRectMake(0, horizon, frame.size.width, frame.size.height / 2);
      [mBackgroundGradient setFrame: r];
			[mBackgroundGradient setAutoresizingMask: (kCALayerWidthSizable | kCALayerHeightSizable)];
      [mBackgroundGradient setZPosition: -1];
      [self addSublayer: mBackgroundGradient];
    }
		
		frame.size.width = [self preferredWidth];
		[self setFrame: frame];
		
		[self setState: NSOffState];
		[self setEnabled: YES];
	}
	
	return self;
}



+ (WBTabItem*) tabItemWithIdentifier: (id) identifier
                               label: (NSString*) label;
{
	return [[WBSchemaTabItem alloc] initWithIdentifier: identifier
                                                label: label];
}






@end


