/* 
 * Copyright (c) 2010, 2016, Oracle and/or its affiliates. All rights reserved.
 * 
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; version 2 of the License.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA */

#include "tree_model.h"
#include "wb_overview_physical.h"
#include "wb_context_model.h"
#include "workbench/wb_context.h"

#import "WBModelOverviewPanel.h"
#import "WBOverviewPanel.h"
#import "WBModelSidebarController.h"
#import "WBObjectDescriptionController.h"
#import "GRTListDataSource.h"
#import "GRTTreeDataSource.h"
#import "MTabSwitcher.h"
#import "WBTabView.h"
#import "WBSplitView.h"
#import "MFView.h"
#import "MContainerView.h"

@interface WBModelOverviewPanel()
{
  __weak IBOutlet WBOverviewPanel *overview;
  __weak IBOutlet NSSplitView *sideSplitview;
  __weak IBOutlet WBModelSidebarController *sidebarController;
  __weak IBOutlet WBObjectDescriptionController *descriptionController;
  __weak IBOutlet MTabSwitcher *mSwitcherT;
  __weak IBOutlet MTabSwitcher *mSwitcherB;

  wb::WBContextUI *_wbui;
  NSMutableArray *nibObjects;
}

@end;

@implementation WBModelOverviewPanel

- (instancetype)initWithWBContextUI: (wb::WBContextUI*)wbui
{
  self = [super init];
  if (self)
  {
    _wbui = wbui;
    if (_wbui != NULL)
    {
      NSMutableArray *temp;
      if ([NSBundle.mainBundle loadNibNamed: @"WBModelOverview" owner: self topLevelObjects: &temp])
      {
        nibObjects = temp;

        [editorTabView createDragger];

        [overview setupWithOverviewBE: wbui->get_physical_overview()];
        [sidebarController setupWithContext: wbui->get_wb()->get_model_context()];
        [mSwitcherT setTabStyle: MPaletteTabSwitcherSmallText];
        [mSwitcherB setTabStyle: MPaletteTabSwitcherSmallText];
        [descriptionController setWBContext: wbui];

        [self.splitView setDividerThickness: 1];
        [self.splitView setBackgroundColor: [NSColor colorWithDeviceWhite: 128 / 255.0 alpha: 1.0]];

        [overview performSelector: @selector(rebuildAll) withObject: nil afterDelay: 0.1];

        grtm = _wbui->get_wb()->get_grt_manager();

        [self.splitView setAutosaveName: @"modelSplitPosition"];

        [self restoreSidebarsFor: "ModelOverview" toolbar: wbui->get_physical_overview()->get_toolbar()];
      }
    }
  }
  return self;
}

- (instancetype)init
{
  return [self initWithWBContextUI: NULL];
}

- (void)dealloc
{
  // Make sure scheduled rebuildAll won't blow up if it didn't exec yet.
  [NSObject cancelPreviousPerformRequestsWithTarget: overview];

  [sidebarController invalidate];
  
}

- (NSString*)identifier
{
  return [overview identifier];
}

- (WBOverviewPanel*)overview
{
  return overview;
}

- (NSString*)title
{  
  return [overview title];
}

- (bec::UIForm*)formBE
{
  return [overview formBE];
}

- (void)didActivate
{
  NSView *view = nsviewForView(_wbui->get_wb()->get_model_context()->shared_secondary_sidebar());
  if ([view superview])
    [view removeFromSuperview];

  [secondarySidebar addSubview: view];
  [view setAutoresizingMask: NSViewWidthSizable|NSViewHeightSizable|NSViewMinXMargin|NSViewMinYMargin|NSViewMaxXMargin|NSViewMaxYMargin];
  [view setFrame: [secondarySidebar bounds]];
}

- (BOOL)willClose
{
  return [overview willClose];
}

- (void)selectionChanged
{
  [descriptionController updateForForm: [self formBE]];
}

- (WBModelSidebarController*)sidebarController
{
  return sidebarController;
}

//--------------------------------------------------------------------------------------------------

- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)subview
{
  if (subview == bottomContainer)
    return NO;

  return [super splitView: splitView shouldAdjustSizeOfSubview: subview];
}

//--------------------------------------------------------------------------------------------------


@end
