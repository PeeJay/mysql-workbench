/* 
 * Copyright (c) 2009, 2016, Oracle and/or its affiliates. All rights reserved.
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
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#include "base/string_utilities.h"

#include "workbench/wb_context.h"

#import "WBMainController.h"
#import "MainWindowController.h"
#import "MCppUtilities.h"

// for _NSGetArg*
#include <crt_externs.h>

#import "WBPluginPanel.h"
#import "WBPluginEditorBase.h"
#import "WBPluginWindowBase.h"
#import "WBPluginWindowController.h"

#import "WBModelDiagramPanel.h"

#include "workbench/wb_context_ui.h"
#include "model/wb_context_model.h"
#include "grtui/gui_plugin_base.h"

#import "WBExceptions.h"

#import "WBSQLQueryUI.h"

#import "WBMenuManager.h"
#import "WBDiagramSizeController.h"
#import "WBModelDiagramPanel.h"

#import "ScintillaView.h"

#include "mforms/toolbar.h"
#import "MFCodeEditor.h"

#include "workbench/wb_module.h"
#include "base/log.h"

#include "wb_command_ui.h"

static GThread *mainthread= 0;

DEFAULT_LOG_DOMAIN("Workbench")

@interface WBMainController()
{
  wb::WBContextUI *_wbui;
  wb::WBContext *_wb;
  wb::WBOptions *_options;
  std::map<std::string, FormPanelFactory> _formPanelFactories;

  NSMutableArray *_editorWindows;

  BOOL _initFinished;
  BOOL _showingUnhandledException;

  MainWindowController *mainController;
  NSMutableArray *pageSetupNibObjects;

  IBOutlet NSPanel *pageSetup;
  IBOutlet NSPopUpButton *paperSize;
  IBOutlet NSTextField *paperSizeLabel;
  IBOutlet NSButton *landscapeButton;
  IBOutlet NSButton *portraitButton;
}

@end

@implementation WBMainController

static std::string showFileDialog(const std::string &type, const std::string &title, const std::string &extensions)
{   
  NSMutableArray *fileTypes= [NSMutableArray array];
  std::vector<std::string> exts(base::split(extensions,","));
   
  for (std::vector<std::string>::const_iterator iter= exts.begin();
       iter != exts.end(); ++iter)
  {   
    if (iter->find('|') != std::string::npos)
    {
      std::string ext= iter->substr(iter->find('|')+1);
      ext= bec::replace_string(ext, "*.", "");
      [fileTypes addObject:@(ext.c_str())];
    }
    else
      [fileTypes addObject:@(iter->c_str())];
  }  
  
  if (type == "open")
  {
    NSOpenPanel *panel= [NSOpenPanel openPanel];

    [panel setTitle: @(title.c_str())];
    [panel setAllowedFileTypes: fileTypes];
    
    if ([panel runModal] == NSFileHandlingPanelOKButton)
      return [panel.URL.path UTF8String];
  }
  else if (type == "save")
  {
    NSSavePanel *panel= [NSSavePanel savePanel];
    
    [panel setTitle:@(title.c_str())];
    
    [panel setAllowedFileTypes:fileTypes];

    if ([panel runModal] == NSFileHandlingPanelOKButton)
      return [panel.URL.path UTF8String];
  }
  
  return "";
}

- (IBAction)inputDialogClose:(id)sender
{
  [NSApp stopModalWithCode: [sender tag]];
}

static void windowShowStatusText(const std::string &text, MainWindowController *controller)
{
  NSString *string= [[NSString alloc] initWithUTF8String:text.c_str()];

  // setStatusText must release the param
  if ([NSThread isMainThread])
    controller.statusText = string;
  else
    [controller performSelectorOnMainThread: @selector(setStatusText:)
                                 withObject: string
                              waitUntilDone: NO];
}


static NativeHandle windowOpenPlugin(bec::GRTManager *grtm,
                                     grt::Module *ownerModule, const std::string &shlib, const std::string &class_name,
                                     const grt::BaseListRef &args, bec::GUIPluginFlags flags, MainWindowController *controller)
{
  std::string path= ownerModule->path();
  
  // Check if this is a bundle plugin or a plain dylib plugin
  if (g_str_has_suffix(shlib.c_str(), ".mwbplugin"))
  {
    NSBundle *pluginBundle;
    NSString *bundlePath;
    
    // For bundled plugins, we load it, find the requested class and instantiate it.
    
    // determine the path for the plugin bundle by stripping Contents/Framework/dylibname 
    bundlePath= [[[[NSString stringWithCPPString:path] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    
    NSLog(@"opening plugin bundle %@ ([%s initWithModule:grtManager:arguments:...])", bundlePath, class_name.c_str());
    
    pluginBundle= [NSBundle bundleWithPath: bundlePath];
    if (!pluginBundle)
    {
      NSLog(@"plugin bundle %@ for plugin %s could not be loaded", bundlePath, path.c_str());
      NSRunAlertPanel(NSLocalizedString(@"Error Opening Plugin", @"plugin open error"),
                      NSLocalizedString(@"The plugin %s could not be loaded.", @"plugin open error"),
                      nil, nil, nil, shlib.c_str());
      return 0;
    }
    Class pclass= [pluginBundle classNamed:@(class_name.c_str())];
    if (!pclass)
    {
      NSLog(@"plugin class %s was not found in bundle %@", class_name.c_str(), bundlePath);
      
      NSRunAlertPanel(NSLocalizedString(@"Error Opening Plugin", @"plugin open error"),
                      @"The plugin %s does not contain the published object %s",
                      nil, nil, nil, shlib.c_str(), class_name.c_str());
      return 0;
    }
    
    if ((flags & bec::StandaloneWindowFlag))
    {
      // create a window for the panel further down
    }
    else if (!(flags & bec::ForceNewWindowFlag))
    {
      // Check if there is already a panel with an editor for this plugin type.
      id existingPanel = [controller findPanelForPluginType: [pclass class]];
      if (existingPanel != nil)
      {
        // check if it can be closed
        if ([existingPanel respondsToSelector:@selector(willClose)] &&
            ![existingPanel willClose])
        {
          flags= (bec::GUIPluginFlags)(flags | bec::ForceNewWindowFlag);
        }
        else
        {
          // drop the old plugin->handle mapping
          grtm->get_plugin_manager()->forget_gui_plugin_handle((__bridge NativeHandle)existingPanel);
          
          if ([existingPanel respondsToSelector: @selector(pluginEditor)])
          {
            id editor= [existingPanel pluginEditor];
            
            if ([editor respondsToSelector: @selector(reinitWithArguments:)])
            {
              id oldIdentifier = [editor identifier];
              
              [controller closeBottomPanelWithIdentifier: oldIdentifier];
              [editor reinitWithArguments: args];
              [controller addBottomPanel: existingPanel];
            }
          }
          return (__bridge NativeHandle)existingPanel;
        }
      }
    }
    
    // Instantiate and initialize the plugin.
    id plugin = [[pclass alloc] initWithModule: ownerModule grtManager: grtm arguments: args];
      
    if ([plugin isKindOfClass: [WBPluginEditorBase class]])
    {      
      if ((flags & bec::StandaloneWindowFlag))
      {
        WBPluginWindowController *editor = [[WBPluginWindowController alloc] initWithPlugin: plugin];
        
        [controller.owner->_editorWindows addObject: editor];
        
        return (__bridge NativeHandle)editor;
      }
      else
      {
        WBPluginPanel *panel = [[WBPluginPanel alloc] initWithPlugin: plugin];
        [controller addBottomPanel: panel];
      
        return (__bridge NativeHandle)panel;
      }
    }
    else if ([plugin isKindOfClass: WBPluginWindowBase.class])
    {
      [plugin showModal];
      return nil;
    }
    else
    {
      NSLog(@"Plugin %@ is of unknown type", plugin);
      return nil;
    }
  }
  else
  {
    NSLog(@"open_plugin() called for an unknown plugin type");
    return 0;
  }
}

static void windowShowPlugin(NativeHandle handle, MainWindowController *controller)
{
  id plugin= (__bridge id)handle;
  
  if ([plugin respondsToSelector: @selector(setHidden:)])
    [plugin setHidden: NO];
  else if ([plugin respondsToSelector:@selector(topView)])
    [controller reopenEditor: plugin];
}

static void windowHidePlugin(NativeHandle handle, MainWindowController *controller)
{
  id plugin = (__bridge id)handle;

  if ([plugin respondsToSelector: @selector(setHidden:)])
    [plugin setHidden: YES];
}

static void windowPerformCommand(const std::string &command, MainWindowController *controller, WBMainController *main)
{  
  if (command == "reset_layout")
    [controller resetWindowLayout];
  else if (command == "overview.mysql_model")
    [controller showMySQLOverview:nil];
  else if (command == "diagram_size")
    [main showDiagramProperties:nil];
  else if (command == "wb.page_setup")
    [main showPageSetup:nil];
  else
    [controller forwardCommandToPanels: command];
}

static mdc::CanvasView* windowCreateView(const model_DiagramRef &diagram, MainWindowController *controller)
{  
  return [controller createView: diagram.id().c_str() name: diagram->name().c_str()];
}

static void windowDestroyView(mdc::CanvasView *view, MainWindowController *controller)
{
  [controller destroyView: view];
}


static void windowSwitchedView(mdc::CanvasView *cview, MainWindowController *controller)
{
  [controller switchToDiagramWithIdentifier: cview->get_tag().c_str()];
}

static void windowCreateMainFormView(const std::string &type, boost::shared_ptr<bec::UIForm> form,
                                     WBMainController *main, MainWindowController *controller)
{
  if (main->_formPanelFactories.find(type) == main->_formPanelFactories.end())
  {
    throw std::logic_error("Form type " + type + " not supported by frontend");
  }
  else
  {
    WBBasePanel *panel = main->_formPanelFactories[type](controller, form);
    
    [controller addTopPanelAndSwitch: panel];
  }
}

static void windowDestroyMainFormView(bec::UIForm *form, MainWindowController *controller)
{
}

static void windowToolChanged(mdc::CanvasView *canvas, MainWindowController *controller)
{
  if ([[controller selectedMainPanel] isKindOfClass: [WBModelDiagramPanel class]])
  {
    [(WBModelDiagramPanel*)[controller selectedMainPanel] canvasToolChanged:canvas];
  }
}

static void windowRefreshGui(wb::RefreshType type, const std::string &arg1, NativeHandle arg2, MainWindowController *controller)
{
  [controller refreshGUI: type argument1: arg1 argument2: arg2];
}

static void windowLockGui(bool lock, MainWindowController *controller)
{
  [controller blockGUI: lock];
}


static bool quitApplication(MainWindowController *controller)
{
  if (![controller closeAllPanels])
    return false;

  [NSApp terminate: nil];

  return true;
}


- (void)applicationWillTerminate: (NSNotification *)aNotification
{
  log_info("Shutting down Workbench\n");

  [NSObject cancelPreviousPerformRequestsWithTarget: self];
  [[NSNotificationCenter defaultCenter] removeObserver: self];

  
  _wbui->get_wb()->finalize();
  delete _wbui;

  log_info("Workbench shutdown done\n");
}

static void call_copy(wb::WBContextUI *wbui)
{
  if (![[[NSApp keyWindow] firstResponder] tryToPerform:@selector(copy:) with:nil])
    if (wbui->get_active_form() && wbui->get_active_form()->can_copy())
      wbui->get_active_form()->copy();    
}

static void call_cut(wb::WBContextUI *wbui)
{
  if (![[[NSApp keyWindow] firstResponder] tryToPerform:@selector(cut:) with:nil])
    if (wbui->get_active_form() && wbui->get_active_form()->can_cut())
      wbui->get_active_form()->cut();
}

static void call_paste(wb::WBContextUI *wbui)
{
  if (![[[NSApp keyWindow] firstResponder] tryToPerform: @selector(paste:) with:nil])
    if (wbui->get_active_form() && wbui->get_active_form()->can_paste())
      wbui->get_active_form()->paste();
}

static void call_select_all(wb::WBContextUI *wbui)
{
  if (![[[NSApp keyWindow] firstResponder] tryToPerform: @selector(selectAll:) with:nil])
    if (wbui->get_active_form())
      wbui->get_active_form()->select_all();
}

static void call_delete(wb::WBContextUI *wbui)
{
  id responder= [[NSApp keyWindow] firstResponder];

  if (![responder tryToPerform: @selector(delete:) with: nil])
    if (![responder tryToPerform: @selector(deleteBackward:) with:nil])
      if (wbui->get_active_form())
        wbui->get_active_form()->delete_selection();
}

//--------------------------------------------------------------------------------------------------

static bool validate_copy(wb::WBContextUI *wbui)
{
  if ([[[NSApp keyWindow] firstResponder] respondsToSelector: @selector(selectedRange)])
  {
    NSRange textRange = [(id)[[NSApp keyWindow] firstResponder] selectedRange];
    return textRange.length > 0;
  }
  if (/*[[[NSApp keyWindow] firstResponder] isKindOfClass: [NSTableView class]]
      &&*/ [[[NSApp keyWindow] firstResponder] respondsToSelector: @selector(copy:)])
    return true; //[[(NSTableView*)[[NSApp keyWindow] firstResponder] selectedRowIndexes] count] > 0;
  
  return (wbui->get_active_form() && wbui->get_active_form()->can_copy());
}

//--------------------------------------------------------------------------------------------------

static bool validate_cut(wb::WBContextUI *wbui)
{
  if ([[[NSApp keyWindow] firstResponder] respondsToSelector: @selector(selectedRange)])
  {
    NSRange textRange = [(id)[[NSApp keyWindow] firstResponder] selectedRange];
    if (textRange.length > 0)
    {
      if ([[[NSApp keyWindow] firstResponder] respondsToSelector: @selector(isEditable)])
        return [(id)[[NSApp keyWindow] firstResponder] isEditable];
      return true;
    }
    return false;
  }
  else if ([[[NSApp keyWindow] firstResponder] respondsToSelector: @selector(cut:)])
    return true;
  
  return (wbui->get_active_form() && wbui->get_active_form()->can_cut());
}

//--------------------------------------------------------------------------------------------------

static bool validate_paste(wb::WBContextUI *wbui)
{
  if ([[[NSApp keyWindow] firstResponder] respondsToSelector: @selector(isEditable)])
  {
    // Two conditions must be met if target can be considered as pastable.
    // 1) The target is editable.
    BOOL isEditable = [(id)[[NSApp keyWindow] firstResponder] isEditable];
    
    // 2) The pasteboard contains text.
    NSArray* supportedTypes = @[NSStringPboardType];
    NSString *bestType = [[NSPasteboard generalPasteboard] availableTypeFromArray: supportedTypes];

    return isEditable && (bestType != nil);
  }
  else if ([[[NSApp keyWindow] firstResponder] respondsToSelector: @selector(paste:)])
    return true;
  
  return (wbui->get_active_form() && wbui->get_active_form()->can_paste());
}

//--------------------------------------------------------------------------------------------------

static bool validate_select_all(wb::WBContextUI *wbui)
{
  if ([[[NSApp keyWindow] firstResponder] respondsToSelector: @selector(isSelectable)])
    return [(id)[[NSApp keyWindow] firstResponder] isSelectable];

  return (wbui->get_active_form());
}

//--------------------------------------------------------------------------------------------------

static bool validate_delete(wb::WBContextUI *wbui)
{
  NSResponder* responder = [[NSApp keyWindow] firstResponder];
  if ([responder respondsToSelector: @selector(canDeleteItem:)])
    return [responder performSelector: @selector(canDeleteItem:) withObject: nil];
  
  if ([responder respondsToSelector: @selector(selectedRange)])
  {
    NSRange textRange = [(id)[[NSApp keyWindow] firstResponder] selectedRange];
    return textRange.length > 0;
  }

  return (wbui->get_active_form() && wbui->get_active_form()->can_delete());
}

//--------------------------------------------------------------------------------------------------

// XXX deprecated, remove it eventually
static void call_closetab_old(MainWindowController *controller)
{
  if (controller.window.isKeyWindow)
  {
    id activePanel = controller.activePanel;
    bec::UIForm *form = [activePanel formBE];
    if (form && form->get_form_context_name() == "home")
      return;
    
    if (![activePanel respondsToSelector: @selector(closeActiveEditorTab)]
        || ![activePanel closeActiveEditorTab])
      [controller closePanel: activePanel];
  }
}

static void call_close_tab(MainWindowController *controller)
{
  if (controller.window.isKeyWindow)
  {
    id activePanel = controller.activePanel;
    bec::UIForm *form = [activePanel formBE];
    if (form && form->get_form_context_name() == "home")
      return;
    
    [controller closePanel: activePanel];
  }
}

static void call_close_editor(MainWindowController *controller)
{
  if (controller.window.isKeyWindow)
  {
    id activePanel = controller.activePanel;
    bec::UIForm *form = [activePanel formBE];
    if (form && form->get_form_context_name() == "home")
      return;

    [activePanel closeActiveEditorTab];
  }
}

//--------------------------------------------------------------------------------------------------

static bool validate_closetab_old(MainWindowController *controller)
{  
  WBBasePanel *activePanel = controller.activePanel;
  bec::UIForm *form = activePanel.formBE;
  if (form && form->get_form_context_name() == "home")
    return false;
  
  // find where this belongs to
  return activePanel != nil && controller.window.isKeyWindow;
}

static bool validate_close_tab(MainWindowController *controller)
{  
  WBBasePanel *activePanel = controller.activePanel;
  bec::UIForm *form = [activePanel formBE];
  if (form && form->get_form_context_name() == "home")
    return false;
  return activePanel != nil && controller.window.isKeyWindow;
}

static bool validate_close_editor(MainWindowController *controller)
{  
  WBBasePanel *activePanel = controller.activePanel;
  bec::UIForm *form = [activePanel formBE];
  if (form && form->get_form_context_name() == "home")
    return false;
  
  return activePanel != nil && controller.window.isKeyWindow && [activePanel respondsToSelector: @selector(closeActiveEditorTab)];
}

//--------------------------------------------------------------------------------------------------

static void call_toggle_fullscreen(MainWindowController *controller)
{
  [controller.window toggleFullScreen: controller.window];
}

//--------------------------------------------------------------------------------------------------

static bool validate_toggle_fullscreen(MainWindowController *controller)
{
  return NSAppKitVersionNumber > NSAppKitVersionNumber10_6;
}

//--------------------------------------------------------------------------------------------------

static bool validate_find_replace()
{
  id firstResponder = [[NSApp keyWindow] firstResponder];
  if ([firstResponder isKindOfClass: [ScintillaView class]] || [firstResponder isKindOfClass: [NSTextView class]] ||
      [firstResponder isKindOfClass: [SCIContentView class]])
    return true;
  return false;
}

//--------------------------------------------------------------------------------------------------

static void call_find_replace(bool do_replace)
{
  if (validate_find_replace())
  {
    id firstResponder = [[NSApp keyWindow] firstResponder];
    if ([firstResponder isKindOfClass: [SCIContentView class]])
    {
      while (firstResponder && ![firstResponder isKindOfClass: [ScintillaView class]])
        firstResponder = [firstResponder superview];
    }
    if ([firstResponder isKindOfClass: [MFCodeEditor class]])
      [firstResponder showFindPanel: do_replace];
  }
  else
    NSBeep();
}

//--------------------------------------------------------------------------------------------------

static void call_find(MainWindowController *controller)
{
  id firstResponder = [[NSApp keyWindow] firstResponder];
  if ([firstResponder isKindOfClass: [SCIContentView class]])
  {
    while (firstResponder && ![firstResponder isKindOfClass: [ScintillaView class]])
      firstResponder = [firstResponder superview];
  }
  if ([firstResponder isKindOfClass: [MFCodeEditor class]])
    [firstResponder showFindPanel: NO];
  else
    [controller performSearchObject: nil];
}

static bool validate_find(MainWindowController *controller)
{
  bec::UIForm *form = controller.context->get_active_main_form();
  if (form && form->get_toolbar() && form->get_toolbar()->find_item("find"))
    return true;
  return validate_find_replace();
}

//--------------------------------------------------------------------------------------------------

static void call_undo(MainWindowController *controller)
{
  wb::WBContextUI *wbui = controller.context;
  id firstResponder = [[NSApp keyWindow] firstResponder];

  if ([firstResponder respondsToSelector: @selector(undo:)])
    [firstResponder tryToPerform: @selector(undo:) with:nil];
  else if ([firstResponder isKindOfClass: [NSTextView class]])
    return [[firstResponder undoManager] undo];
  else
    if (wbui->get_active_main_form())
      wbui->get_active_main_form()->undo();
}

static bool validate_undo(MainWindowController *controller)
{
  wb::WBContextUI *wbui = controller.context;
  id firstResponder = [[NSApp keyWindow] firstResponder];

  if ([firstResponder respondsToSelector: @selector(canUndo)])
    return [firstResponder canUndo];
  else if ([firstResponder isKindOfClass: [NSTextView class]])
    return [[firstResponder undoManager] canUndo];
  else if ([firstResponder isKindOfClass: [SCIContentView class]])
    return true;
  else
    if (wbui->get_active_main_form())
      return wbui->get_active_main_form()->can_undo();
  return false;
}

static void call_redo(MainWindowController *controller)
{
  wb::WBContextUI *wbui = controller.context;
  id firstResponder = [[NSApp keyWindow] firstResponder];
  
  if ([firstResponder respondsToSelector: @selector(redo:)])
    [firstResponder tryToPerform: @selector(redo:) with:nil];
  else if ([firstResponder isKindOfClass: [NSTextView class]])
    return [[firstResponder undoManager] redo];
  else
    if (wbui->get_active_main_form())
      wbui->get_active_main_form()->redo();
}

static bool validate_redo(MainWindowController *controller)
{
  wb::WBContextUI *wbui = controller.context;
  id firstResponder = [[NSApp keyWindow] firstResponder];
  
  if ([firstResponder respondsToSelector: @selector(canRedo)])
    return [firstResponder canRedo];
  else if ([firstResponder isKindOfClass: [NSTextView class]])
    return [[firstResponder undoManager] canRedo];
  else if ([firstResponder isKindOfClass: [SCIContentView class]])
    return true;
  else
    if (wbui->get_active_main_form())
      return wbui->get_active_main_form()->can_redo();
  return false;
}

- (void)textSelectionChanged: (NSNotification*)notification
{ 
  id firstResponder= [[NSApp keyWindow] firstResponder];

  if ([notification object] == firstResponder ||
      ([firstResponder respondsToSelector:@selector(superview)] &&
       [notification object] == [firstResponder superview]))
  { 
    // refresh edit menu
    wb::WBContextUI *wbui = mainController.context;
    wbui->get_command_ui()->revalidate_edit_menu_items();
  }
}

//--------------------------------------------------------------------------------------------------

- (void)registerCommandsWithBackend
{
  std::list<std::string> commands;
  
  commands.push_back("overview.mysql_model");
  commands.push_back("diagram_size");
  //  commands.push_back("view_model_navigator");
  //  commands.push_back("view_catalog");
  //  commands.push_back("view_layers");
  //  commands.push_back("view_user_datatypes");
  //  commands.push_back("view_object_properties");
  //  commands.push_back("view_object_description");
  //  commands.push_back("view_undo_history");
//  commands.push_back("reset_layout");
  commands.push_back("wb.page_setup");
  //  commands.push_back("help_index");
  //  commands.push_back("help_version_check");

  commands.push_back("wb.toggleSidebar");
  commands.push_back("wb.toggleSecondarySidebar");
  commands.push_back("wb.toggleOutputArea");
  
  commands.push_back("wb.next_tab");
  commands.push_back("wb.back_tab");
  commands.push_back("wb.next_query_tab");
  commands.push_back("wb.back_query_tab");

  _wbui->get_command_ui()->add_frontend_commands(commands);

  _wbui->get_command_ui()->add_builtin_command("closetab", boost::bind(call_closetab_old, mainController),
                                               boost::bind(validate_closetab_old, mainController));
  _wbui->get_command_ui()->add_builtin_command("close_tab", boost::bind(call_close_tab, mainController),
                                               boost::bind(validate_close_tab, mainController));
  _wbui->get_command_ui()->add_builtin_command("close_editor", boost::bind(call_close_editor, mainController),
                                               boost::bind(validate_close_editor, mainController));

  _wbui->get_command_ui()->add_builtin_command("toggle_fullscreen", boost::bind(call_toggle_fullscreen, mainController),
                                               boost::bind(validate_toggle_fullscreen, mainController));

  _wbui->get_command_ui()->add_builtin_command("find", boost::bind(call_find, mainController),
                                               boost::bind(validate_find, mainController));
  _wbui->get_command_ui()->add_builtin_command("find_replace", boost::bind(call_find_replace, true),
                                               boost::bind(validate_find_replace));

  _wbui->get_command_ui()->add_builtin_command("undo", boost::bind(call_undo, mainController),
                                               boost::bind(validate_undo, mainController));
  _wbui->get_command_ui()->add_builtin_command("redo", boost::bind(call_redo, mainController),
                                               boost::bind(validate_redo, mainController));
  _wbui->get_command_ui()->add_builtin_command("copy", boost::bind(call_copy, _wbui),
                                               boost::bind(validate_copy, _wbui));
  _wbui->get_command_ui()->add_builtin_command("cut", boost::bind(call_cut, _wbui), 
                                               boost::bind(validate_cut, _wbui));
  _wbui->get_command_ui()->add_builtin_command("paste", boost::bind(call_paste, _wbui), 
                                               boost::bind(validate_paste, _wbui));
  _wbui->get_command_ui()->add_builtin_command("delete", boost::bind(call_delete, _wbui),
                                               boost::bind(validate_delete, _wbui));
  _wbui->get_command_ui()->add_builtin_command("selectAll", boost::bind(call_select_all, _wbui), 
                                               boost::bind(validate_select_all, _wbui));
}

static void flush_main_thread()
{
  // flush stuff that could be called with performSelectorOnMainThread:
  [[NSRunLoop currentRunLoop] acceptInputForMode:NSModalPanelRunLoopMode beforeDate:[NSDate date]];
}


- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
  std::string path = [filename fileSystemRepresentation];
  if (_initFinished)
  {
    if (_wb->open_file_by_extension(path, true))
      return YES;
  }
  else
  {
    _options->open_at_startup= path;
    return YES;
  }
  return NO;
}


- (void)applicationDidFinishLaunching:(NSNotification*)notification
{
  _wb->get_ui()->init_finish(_options);

  _initFinished= YES;
  [[NSNotificationCenter defaultCenter] addObserver: self
                                           selector: @selector(windowDidBecomeKey:)
                                               name: NSWindowDidBecomeKeyNotification
                                             object: nil];
}


#include "mforms/../cocoa/MFMenuBar.h"

- (void)windowDidBecomeKey: (NSNotification*)notification
{
  if (notification.object != mainController.window)
  {
    cf_swap_edit_menu();
  }
  else
  {
    cf_unswap_edit_menu();
    bec::UIForm *form = _wb->get_active_main_form();
    if (form && form->get_menubar())
      form->get_menubar()->validate();
  }
}

- (void)applicationDidBecomeActive: (NSNotification*)notification
{
  base::NotificationInfo info;
  base::NotificationCenter::get()->send("GNApplicationActivated", NULL, info);
}

static NSString *applicationSupportFolder()
{
  NSArray *res= NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);

  if ([res count] > 0)
    return res[0];
  return @"/tmp/";
}


- (void)setupBackend
{
  mainthread= g_thread_self();

  try
  {
    bec::GRTManager *grtm;
    
    // Setup backend stuff
    _wbui = new wb::WBContextUI(false);
    _wb = _wbui->get_wb();
    
    grtm = _wb->get_grt_manager();
    grtm->get_dispatcher()->set_main_thread_flush_and_wait(flush_main_thread);
    
    mainController.wBContext = _wbui;
    mainController.owner = self;
    
    // Define a set of methods which backend can call to interact with user and frontend
    wb::WBFrontendCallbacks wbcallbacks;
    
    // Assign those callback methods
    wbcallbacks.show_file_dialog= boost::bind(showFileDialog, _1, _2, _3);
    wbcallbacks.show_status_text= boost::bind(windowShowStatusText, _1, mainController);
    wbcallbacks.open_editor= boost::bind(windowOpenPlugin, _1, _2, _3, _4, _5, _6, mainController);
    wbcallbacks.show_editor= boost::bind(windowShowPlugin, _1, mainController);
    wbcallbacks.hide_editor= boost::bind(windowHidePlugin, _1, mainController);
    wbcallbacks.perform_command= boost::bind(windowPerformCommand, _1, mainController, self);
    wbcallbacks.create_diagram= boost::bind(windowCreateView, _1, mainController);
    wbcallbacks.destroy_view= boost::bind(windowDestroyView, _1, mainController);
    wbcallbacks.switched_view= boost::bind(windowSwitchedView, _1, mainController);
    wbcallbacks.create_main_form_view= boost::bind(windowCreateMainFormView, _1, _2, self, mainController);
    wbcallbacks.destroy_main_form_view= boost::bind(windowDestroyMainFormView, _1, mainController);
    wbcallbacks.tool_changed= boost::bind(windowToolChanged, _1, mainController);
    wbcallbacks.refresh_gui= boost::bind(windowRefreshGui, _1, _2, _3, mainController);
    wbcallbacks.lock_gui= boost::bind(windowLockGui, _1, mainController);
    wbcallbacks.quit_application= boost::bind(quitApplication, mainController);
      
    // Add shipped python module search path to PYTHONPATH.
    {
      char *path = getenv("PYTHONPATH");
      if (path)
      {
        path = g_strdup_printf("PYTHONPATH=%s:%s", path, _options->library_search_path.c_str());
        putenv(path);  // path should not be freed
      }
      else
      {
        path = g_strdup_printf("PYTHONPATH=%s", _options->library_search_path.c_str());
        putenv(path); // path should not be freed
      }
    }

    _wbui->init(&wbcallbacks, _options);
    
    _wb->flush_idle_tasks();
  }
  catch (std::exception &exc)
  {
    MShowCPPException(exc);
  }
}

//--------------------------------------------------------------------------------------------------

/**
 * Instantiates the option class for the backend and parses the command line.
 */
- (void)setupOptionsAndParseCommandline
{
  _options= new wb::WBOptions();
  
  _options->basedir = [[[NSBundle mainBundle] resourcePath] fileSystemRepresentation];
  _options->struct_search_path = _options->basedir + "/grt";
  _options->plugin_search_path = std::string([[[NSBundle mainBundle] builtInPlugInsPath] fileSystemRepresentation]);
  _options->module_search_path = std::string([[[NSBundle mainBundle] builtInPlugInsPath] fileSystemRepresentation]) + ":" + std::string([[[NSBundle mainBundle] resourcePath] fileSystemRepresentation]) + "/plugins";
  _options->library_search_path = std::string([[[NSBundle mainBundle] resourcePath] fileSystemRepresentation]) + "/libraries";
  _options->cdbc_driver_search_path = std::string([[[NSBundle mainBundle] privateFrameworksPath] fileSystemRepresentation]);
  _options->user_data_dir= [[applicationSupportFolder() stringByAppendingString: @"/MySQL/Workbench"] fileSystemRepresentation];

  int argc= *_NSGetArgc();
  char **argv= *_NSGetArgv();
  
  int rc = 0;
  if (!_options->parse_args(argv, argc, &rc))
  {
    log_info("Exiting with rc %i after parsing arguments\n", rc);
    exit(rc);
  }

  // no dock icon when the app will quit when finished running script 
  if (_options->quit_when_done)
    [NSApp setActivationPolicy: NSApplicationActivationPolicyAccessory];
}

//--------------------------------------------------------------------------------------------------

extern "C" {
  extern void mforms_cocoa_init();
  extern void mforms_cocoa_check();
};

static void init_mforms()
{
  log_debug("Initializing mforms\n");

  extern void cf_tabview_init();
  extern void cf_record_grid_init();
  static BOOL inited = NO;
  
  if (!inited)
  {
    inited= YES;
  
    mforms_cocoa_init();
    cf_tabview_init();
    cf_record_grid_init();
  }
}

- (instancetype)init
{
  self = [super init];
  if (self != nil)
  {
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(textSelectionChanged:)
                                                 name: NSTextViewDidChangeSelectionNotification
                                               object: nil];
    
    _editorWindows = [NSMutableArray array];
  }
  return self;
}

- (void)registerFormPanelFactory: (FormPanelFactory)fac forFormType: (const std::string&)type
{
  _formPanelFactories[type] = fac;
}

- (void)awakeFromNib
{
  // Since we use this controller to load multiple xibs the awakeFromNib function is called each time of such a load
  // (include the own loading). We can use the mainWindow as indicator (which is set up here).
  // TODO: refactor out classes with own xib files into own controller classes and use them here instead.
  if (mainController == nil)
  {
    // Prepare the logger to be ready as first part.
    base::Logger([[applicationSupportFolder() stringByAppendingString: @"/MySQL/Workbench"] fileSystemRepresentation]);
    log_info("Starting up Workbench\n");

    [self setupOptionsAndParseCommandline];

    init_mforms();
    
    NSApplication.sharedApplication.delegate = self;
    
    // Setup delegate to log symbolic stack traces on exceptions.
    [[NSExceptionHandler defaultExceptionHandler] setExceptionHandlingMask: NSLogUncaughtExceptionMask | NSLogUncaughtSystemExceptionMask | NSLogUncaughtRuntimeErrorMask | NSLogTopLevelExceptionMask | NSLogOtherExceptionMask];
    [[NSExceptionHandler defaultExceptionHandler] setDelegate: [WBExceptionHandlerDelegate new]];
    
    mainController = [MainWindowController new];

    [self setupBackend];
    
    NSTimer *timer= [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(idleTasks:)
                                                   userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSModalPanelRunLoopMode];
    
    NSToolbar *toolbar = mainController.window.toolbar;
    [toolbar setShowsBaselineSeparator: NO];
    
    [self registerCommandsWithBackend];
    
    setupSQLQueryUI(self, mainController, _wbui);
    
    // don't show the main window if we'll quit after running a script
    if ((_options->quit_when_done && !_options->run_at_startup.empty()))
      [mainController.window orderOut: nil];
    else
      [mainController showWindow: nil];

    // do the final setup for after the window is shown
    [mainController setupReady];

    mforms_cocoa_check();
    
    //XXX hack to work-around problem with opening object editors
    {
      NSString *pluginsPath= [[NSBundle mainBundle] builtInPlugInsPath];
      NSDirectoryEnumerator *dirEnum = [[NSFileManager defaultManager] enumeratorAtPath:pluginsPath];
      NSString *file;
      
      while ((file = [dirEnum nextObject])) {
        if ([[file pathExtension] isEqualToString: @"mwbplugin"]) {
          NSString *path= [pluginsPath stringByAppendingPathComponent:file];
          
          NSBundle *bundle= [NSBundle bundleWithPath:path];
          [bundle load];
        }
      }
    }
  }
}


- (void)flushIdleTasks:(id)arg
{
  if (!_showingUnhandledException)
  {
    _showingUnhandledException = YES;
    try
    {
      _wb->flush_idle_tasks();
    }
    catch (const std::exception &exc)
    {
      NSRunAlertPanel(@"Unhandled Exception", @"An unhandled exception has occurred: %s",
                      @"OK", nil, nil, exc.what());
    }
    _showingUnhandledException = NO;
  }
}


- (void)idleTasks:(NSTimer*)timer
{
  static NSArray *modes= nil;
  if (!modes) 
    modes= @[NSDefaultRunLoopMode, NSModalPanelRunLoopMode];
  
  // if we call flush_idle_tasks() directly here, we could get blocked by a plugin with a
  // modal loop. In that case, the timer would not get fired again until the modal loop
  // terminates, which is a problem. So we defer the execution to after this method returns.
  [[NSRunLoop currentRunLoop] performSelector:@selector(flushIdleTasks:) target:self
                                     argument:self order:0 modes:modes];
}


- (void)requestRefresh
{
  @autoreleasepool {
    [self performSelector: @selector(idleTasks:)
               withObject: nil
               afterDelay: 0];
  }
}


- (IBAction)menuItemClicked:(id)sender
{
  // identifiers from the App menu. These are set in the nib
#define APP_MENU_ABOUT 100
#define APP_MENU_PREFERENCES 101
#define APP_MENU_QUIT 102

  // special handling for some Application menu items
  switch ([sender tag])
  {
    case APP_MENU_ABOUT:
      _wbui->get_command_ui()->activate_command("builtin:show_about");
      break;
      
    case APP_MENU_PREFERENCES:
      _wbui->get_command_ui()->activate_command("plugin:wb.form.showOptions");
      break;
      
    case APP_MENU_QUIT:
      quitApplication(mainController);
      break;
  }
}

- (IBAction)showDiagramProperties:(id)sender
{
  WBDiagramSizeController *controller= [[WBDiagramSizeController alloc] initWithWBContext:_wbui];
  
  [controller showModal];
}


- (IBAction)buttonClicked:(id)sender
{
  if ([sender tag] == 10)
  {
    [NSApp stopModalWithCode: NSOKButton];
    [pageSetup orderOut: nil];
  }
  else if ([sender tag] == 11)
  {
    [NSApp stopModalWithCode: NSCancelButton];  
    [pageSetup orderOut: nil];
  }
  else if (sender == landscapeButton)
  {
    [landscapeButton setState: NSOnState];
    [portraitButton setState: NSOffState];
  }
  else if (sender == portraitButton)
  {
    [landscapeButton setState: NSOffState];
    [portraitButton setState: NSOnState];
  }  
}


- (void)selectCollectionItem:(id)sender
{
  if (sender == paperSize)
  {
    [paperSizeLabel setStringValue: [[paperSize selectedItem] representedObject]];
    [paperSizeLabel sizeToFit];
  }
}


- (void)showPageSetup: (id)sender
{
  log_debug("Showing page setup dialog\n");

  app_PageSettingsRef settings(_wbui->get_page_settings());
  
  if (!settings.is_valid())
    return;
  
  if (!pageSetup)
  {
    NSMutableArray *temp;
    if (![NSBundle.mainBundle loadNibNamed: @"PageSetup" owner: self topLevelObjects: &temp])
      return;

    pageSetupNibObjects = temp;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath: @"/System/Library/PrivateFrameworks/PrintingPrivate.framework/Versions/A/Plugins/PrintingCocoaPDEs.bundle/Contents/Resources/Landscape.tiff"])
    {
      [landscapeButton setImage: [[NSImage alloc] initWithContentsOfFile: @"/System/Library/PrivateFrameworks/PrintingPrivate.framework/Versions/A/Plugins/PrintingCocoaPDEs.bundle/Contents/Resources/Landscape.tiff"]];
      [portraitButton setImage: [[NSImage alloc] initWithContentsOfFile: @"/System/Library/PrivateFrameworks/PrintingPrivate.framework/Versions/A/Plugins/PrintingCocoaPDEs.bundle/Contents/Resources/Portrait.tiff"]];
    }
    else
    {
      [landscapeButton setImage: [[NSImage alloc] initWithContentsOfFile: @"/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/Print.framework/Versions/A/Plugins/PrintingCocoaPDEs.bundle/Contents/Resources/Landscape.tiff"]];
      [portraitButton setImage: [[NSImage alloc] initWithContentsOfFile: @"/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/Print.framework/Versions/A/Plugins/PrintingCocoaPDEs.bundle/Contents/Resources/Portrait.tiff"]];
    }
  }
  
  std::list<wb::WBPaperSize> paper_sizes= _wbui->get_paper_sizes(false);
  
  [paperSize removeAllItems];
  for (std::list<wb::WBPaperSize>::const_iterator iter= paper_sizes.begin(); iter != paper_sizes.end(); 
       ++iter)
  {
    [paperSize addItemWithTitle: [NSString stringWithCPPString: iter->name]];
    [[paperSize itemAtIndex: [paperSize numberOfItems]-1] 
     setRepresentedObject: [NSString stringWithCPPString: iter->description]];
  }
  if (settings->paperType().is_valid())
  {
    [paperSize selectItemWithTitle: [NSString stringWithCPPString: *settings->paperType()->name()]];
    [self selectCollectionItem: paperSize];
  }
  if (settings->orientation() == "landscape")
  {
    [landscapeButton setState: NSOnState];
    [portraitButton setState: NSOffState];
  }
  else
  {
    [landscapeButton setState: NSOffState];
    [portraitButton setState: NSOnState];
  }
  
  if ([NSApp runModalForWindow: pageSetup] == NSOKButton)
  {
    log_debug("Page settings accepted. Updating model...\n");
    std::string type= [[paperSize titleOfSelectedItem] UTF8String];
    app_PaperTypeRef paperType(grt::find_named_object_in_list(_wb->get_root()->options()->paperTypes(), 
                                                              type));
    std::string orientation;
    
    if (paperType != settings->paperType())
      settings->paperType(paperType);
    if ([landscapeButton state] == NSOnState)
      orientation= "landscape";
    else
      orientation= "portrait";
    if (orientation != *settings->orientation())
      settings->orientation(orientation);
    
    _wb->get_model_context()->update_page_settings();
  }

  log_debug("Page setup dialog done\n");
}

@end
