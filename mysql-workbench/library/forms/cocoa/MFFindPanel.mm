/* 
 * Copyright (c) 2012, 2015, Oracle and/or its affiliates. All rights reserved.
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

#import "MFMForms.h"
#import "MFFindPanel.h"
#import "NSString_extras.h"
#import "MFView.h"

#include "mforms/code_editor.h"

using namespace mforms;

@interface MFFindPanel()
{
  mforms::FindPanel *mOwner;

  __weak IBOutlet NSSegmentedControl *mFindTypeSegmented;
  __weak IBOutlet NSTextField *mReplaceText;
  __weak IBOutlet NSTextField *mFindLabel;
  __weak IBOutlet NSSegmentedControl *mFindSegmented;
  __weak IBOutlet NSMenu *mSearchMenu;

  BOOL mMatchCase;
  BOOL mMatchWhole;
  BOOL mWrapAround;
  BOOL mUseRegex;

  NSMutableArray *nibObjects;
}

@property (assign, unsafe_unretained) IBOutlet NSSearchField *findText;

@end

@implementation MFFindPanel

@synthesize findText;

- (instancetype)initWithOwner: (mforms::FindPanel*)owner
{
  if (owner == nil)
    return nil;

  self = [super initWithFrame: NSMakeRect(0, 0, 100, 100)];
  if (self)
  {
    NSMutableArray *temp;
    if ([NSBundle.mainBundle loadNibNamed: @"EmbedableFindPane" owner: self topLevelObjects: &temp])
    {
      nibObjects = temp;

      mOwner = owner;
      mOwner->set_data(self);

      // Find the top view holding the subviews we wanna move to ourselve.
      NSView *holder = nil;
      for (id entry in nibObjects)
      {
        if ([entry isKindOfClass: NSView.class])
        {
          holder = entry;
          break;
        }
      }

      // Now transfer the views.
      // Wouldn't be necessary if that class were just an NSViewController.
      [self setFrame: [holder frame]];
      for (id subview in [[holder subviews] reverseObjectEnumerator])
      {
        NSRect r = [subview frame];
        [subview removeFromSuperview];
        [self addSubview: subview];
        [subview setFrame: r];
      }

      mMatchCase = NO;
      mWrapAround = YES;

      [[mSearchMenu itemWithTag: 20] setState: mUseRegex ? NSOffState : NSOnState];
      [[mSearchMenu itemWithTag: 21] setState: !mUseRegex ? NSOffState : NSOnState];

      [[mSearchMenu itemWithTag: 30] setState: !mMatchCase ? NSOnState : NSOffState];
      [[mSearchMenu itemWithTag: 31] setState: mMatchWhole ? NSOnState : NSOffState];
      [[mSearchMenu itemWithTag: 32] setState: mWrapAround ? NSOnState : NSOffState];
      
      [self enableReplaceInFindPanel: NO];
    }
  }
  return self;
}

-(instancetype)initWithFrame: (NSRect)frame
{
  return [self initWithOwner: nil];
}

-(instancetype)initWithCoder: (NSCoder *)coder
{
  return [self initWithOwner: nil];
}


- (BOOL)expandsOnLayoutVertically:(BOOL)flag
{
  return NO;
}


- (void)enableReplaceInFindPanel: (BOOL)flag
{
  if (!flag)
  {
    [mFindTypeSegmented setSelectedSegment: 0];
    for (id view in [self subviews])
      if ([view tag] >= 10 && [view tag] <= 13)
        [view setHidden: YES];
    [self setFrameSize: NSMakeSize(NSWidth([self frame]), 23)];
  }
  else
  {
    [mFindTypeSegmented setSelectedSegment: 1];
    for (id view in [self subviews])
      if ([view tag] >= 10 && [view tag] <= 13)
        [view setHidden: NO];    
    [self setFrameSize: NSMakeSize(NSWidth([self frame]), 46)];
  }
  [mFindLabel setStringValue: @""];
  if ([[self superview] respondsToSelector: @selector(subviewMinimumSizeChanged)])
    [(id)[self superview] subviewMinimumSizeChanged];
}


- (NSSize)minimumSize
{
  if ([mFindTypeSegmented selectedSegment] == 0)
    return NSMakeSize(100, 23);
  else
    return NSMakeSize(100, 46);
}

- (void)focusFindPanel
{
  [mFindLabel setStringValue: @""];
  [[self window] makeFirstResponder: findText];
  [findText selectText: nil];
}


- (BOOL)findNext:(BOOL)backwards
{
  mforms::FindFlags flags = mforms::FindDefault;  
  if (mMatchWhole)
    flags = flags | mforms::FindWholeWords;
  if (mMatchCase)
    flags = flags | mforms::FindMatchCase;
  if (mWrapAround)
    flags = flags | mforms::FindWrapAround;
  if (mUseRegex)
    flags = flags | mforms::FindRegex;

  return mOwner->get_editor()->find_and_highlight_text([findText.stringValue CPPString], flags,
                                                       true, backwards);
}


- (BOOL)replaceAndFind:(BOOL)findFirst
{
  mforms::FindFlags flags = mforms::FindDefault;  
  if (mMatchWhole)
    flags = flags | mforms::FindWholeWords;
  if (mMatchCase)
    flags = flags | mforms::FindMatchCase;
  if (mWrapAround)
    flags = flags | mforms::FindWrapAround;
  if (mUseRegex)
    flags = flags | mforms::FindRegex;

  if (findFirst)
    return mOwner->get_editor()->find_and_replace_text([findText.stringValue CPPString],
                                                       [[mReplaceText stringValue] CPPString], 
                                                       flags, false) > 0;
  else
  {
    mOwner->get_editor()->replace_selected_text([[mReplaceText stringValue] CPPString]);

    return mOwner->get_editor()->find_and_highlight_text([findText.stringValue CPPString], flags,
                                                  true, false);
  }
}


- (int)replaceAll
{
  mforms::FindFlags flags = mforms::FindDefault;
  if (mMatchWhole)
    flags = flags | mforms::FindWholeWords;
  if (mMatchCase)
    flags = flags | mforms::FindMatchCase;
  if (mWrapAround)
    flags = flags | mforms::FindWrapAround;
  if (mUseRegex)
    flags = flags | mforms::FindRegex;
  
  return mOwner->get_editor()->find_and_replace_text([findText.stringValue CPPString],
                                                     [[mReplaceText stringValue] CPPString], 
                                                     flags, true);  
}


- (IBAction)findActionClicked:(id)sender
{
  switch ([sender tag])
  {
    case 5: // find&replace button
      [self enableReplaceInFindPanel: [mFindTypeSegmented selectedSegment] == 1];
      break;
      
    case 1: // find text
      mOwner->perform_action(FindNext);
      break;

    case 6: // find back/next segmented
      mOwner->perform_action([mFindSegmented selectedSegment] == 1 ? FindNext : FindPrevious);
      break;
      
    case 7: // done
      mOwner->get_editor()->hide_find_panel();
      break;
      
    case 10: // replace all
      mOwner->perform_action(ReplaceAll);
      break;
      
    case 11: // replace selection (without find)
      mOwner->perform_action(FindAndReplace);
      break;
      
    // Menu
    case 20: // plain text
      mUseRegex = NO;
      [[[sender menu] itemWithTag: 20] setState: NSOnState];
      [[[sender menu] itemWithTag: 21] setState: NSOffState];      
      break;
    case 21:
      mUseRegex = YES;
      [[[sender menu] itemWithTag: 20] setState: NSOffState];
      [[[sender menu] itemWithTag: 21] setState: NSOnState];
      break;

    case 30: // ignore case
      mMatchCase = [sender state] == NSOnState;
      [sender setState: mMatchCase ? NSOffState : NSOnState];
      break;
    case 31: // match whole words
      mMatchWhole = [sender state] != NSOnState;
      [sender setState: mMatchWhole ? NSOnState : NSOffState];
      break;
    case 32: // wrap around
      mWrapAround = [sender state] != NSOnState;
      [sender setState: mWrapAround ? NSOnState : NSOffState];
      break;
  }
}

- (int)performFindAction:(FindPanelAction)action
{
  switch (action)
  {
    case FindNext:
      if ([findText.stringValue length] == 0)
        [mFindLabel setStringValue: @""];
      else
      {
        if ([self findNext:NO])
        {
          [mFindLabel setStringValue: @"Found match"];
          return 1;
        }
        else
          [mFindLabel setStringValue: @"Not found"];
      }
      break;
    case FindPrevious:
      if ([findText.stringValue length] == 0)
        [mFindLabel setStringValue: @""];
      else
      {
        if ([self findNext:YES])
        {
          [mFindLabel setStringValue: @"Found match"];
          return 1;
        }
        else
          [mFindLabel setStringValue: @"Not found"];
      }
      break;
    case FindAndReplace:
      if ([findText.stringValue length] > 0)
      {
        if ([self replaceAndFind:YES])
        {
          [mFindLabel setStringValue: @"Replaced 1"];
          return 1;
        }
        else
          [mFindLabel setStringValue: @"Not found"];
      }      
      break;
    case ReplaceAll:
      if ([findText.stringValue length] > 0)
      {
        int count;
        if ((count = [self replaceAll]) > 0)
          [mFindLabel setStringValue: [NSString stringWithFormat: @"Replaced %i", count]];
        else
          [mFindLabel setStringValue: @"No matches"];
        [self setNeedsDisplay: YES];
        return count;
      }
      break;
  }
  return 0;       
}

@end


static bool find_create(FindPanel *fp)
{
  return [[MFFindPanel alloc] initWithOwner: fp] != nil;
}

static size_t find_perform_action(FindPanel *fp, FindPanelAction action)
{
  MFFindPanel *self = fp->get_data();
  
  return [self performFindAction: action];
}


static void find_focus(FindPanel *fp)
{
  MFFindPanel *panel = fp->get_data();
  [panel.findText.window makeFirstResponder: panel.findText];
}


static void find_enable_replace(FindPanel *fp, bool flag)
{
  MFFindPanel *self = fp->get_data();
  
  [self enableReplaceInFindPanel: flag];
}


void cf_findpanel_init()
{
  ::mforms::ControlFactory *f = ::mforms::ControlFactory::get_instance();
  
  f->_findpanel_impl.create = find_create;
  f->_findpanel_impl.perform_action = find_perform_action;
  f->_findpanel_impl.focus = find_focus;
  f->_findpanel_impl.enable_replace = find_enable_replace;
}


