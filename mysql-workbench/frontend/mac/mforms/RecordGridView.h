/*
 * Copyright (c) 2014 Oracle and/or its affiliates. All rights reserved.
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

#ifndef _MFORMS_RECORD_GRID_VIEW_H_
#define _MFORMS_RECORD_GRID_VIEW_H_

#include "mforms/record_grid.h"

@class MResultsetViewer;

namespace mforms
{
class RecordGridView : public mforms::RecordGrid
{
  MResultsetViewer *viewer;

public:
  RecordGridView(boost::shared_ptr<Recordset> rset);
  virtual ~RecordGridView();

  virtual int get_column_count();
  virtual int get_column_width(int column);
  virtual void set_column_width(int column, int width);
  virtual void set_column_header_indicator(int column, ColumnHeaderIndicator order);

  virtual bool current_cell(size_t &row, int &column);
  virtual void set_current_cell(size_t row, int column);

  virtual void set_font(const std::string &font);
  virtual void set_header_menu(ContextMenu *menu);

  virtual void update_columns();

  MResultsetViewer *control() { return viewer; }
};
};
#endif