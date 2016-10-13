
#ifndef _MODEL_PANEL_H_
#define _MODEL_PANEL_H_

#include <map>
#include <gtkmm/paned.h>
#include <gtkmm/notebook.h>
#include <gtkmm/box.h>
#include <gtkmm/frame.h>
#include <gtkmm/builder.h>
#include "linux_utilities/form_view_base.h"

#include "workbench/wb_overview.h"
#include "workbench/wb_context_ui.h"

class OverviewPanel;
class DocumentationBox;
#ifdef COMMERCIAL_CODE
class ValidationPanel;
#endif

namespace mforms
{
  class TreeNodeView;
};

class ModelPanel : public Gtk::VBox, public FormViewBase
{
public:
  static ModelPanel *create(wb::WBContextUI *wb, wb::OverviewBE *overview);
  ~ModelPanel();
  
  virtual bool on_close();
  virtual void on_activate();

  virtual Gtk::Widget *get_panel() { return this; }
  virtual bec::UIForm *get_form() const;

  virtual void reset_layout() { _editor_paned->set_position(_editor_paned->get_height()-300); }
  OverviewPanel *get_overview() { return _overview; }

  void selection_changed();
  
  virtual void find_text(const std::string &text);
  virtual void restore_sidebar_layout();

private:
  wb::WBContextUI *_wb;
  OverviewPanel *_overview;
  Gtk::Paned *_editor_paned;
  Gtk::Widget *_sidebar;
  Gtk::Frame  *_secondary_sidebar;
  bec::NodeId                  _last_found_node;

  mforms::TreeNodeView        *_history_tree;
  mforms::TreeNodeView        *_usertypes_box;
  DocumentationBox            *_documentation_box;
  #ifdef COMMERCIAL_CODE
  ValidationPanel             *_validation_panel;
  #endif
  bool                         _pending_rebuild_overview;

  friend class Gtk::Builder;
  ModelPanel(GtkVBox *vb, Glib::RefPtr<Gtk::Builder> xml);
  void post_construct(wb::WBContextUI *wb, wb::OverviewBE *overview, Glib::RefPtr<Gtk::Builder> xml);

  bool restore_state(Glib::RefPtr<Gtk::Builder> xml);
  void resize_overview();
  bool do_resize_overview();

  sigc::connection            _sig_restore_layout;
  sigc::connection            _sig_resize_overview;
};


#endif /* _MODEL_PANEL_H_ */
