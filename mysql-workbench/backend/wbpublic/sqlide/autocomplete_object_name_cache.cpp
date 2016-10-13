/* 
 * Copyright (c) 2012, 2016, Oracle and/or its affiliates. All rights reserved.
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

#include <sqlite/execute.hpp>
#include <sqlite/query.hpp>
#include <sqlite/database_exception.hpp>
#include <glib.h>

#include "autocomplete_object_name_cache.h"
#include "base/string_utilities.h"
#include "base/log.h"
#include "base/file_utilities.h"
#include "base/sqlstring.h"
#include "grt/common.h"
#include "sqlide_generics.h"

using namespace bec;

DEFAULT_LOG_DOMAIN("AutoCCache");

// The cache automatically loads objects once on startup (for the main objects like schema names)
//  and when queried (for the others). After that no fetch is performed anymore until an explicit
//  refresh is requested by the application (via any of the refresh_* functions).

//--------------------------------------------------------------------------------------------------

AutoCompleteCache::AutoCompleteCache(const std::string &connection_id,
  boost::function<base::RecMutexLock (sql::Dbc_connection_handler::Ref &)> get_connection,
  const std::string &cache_dir, boost::function<void (bool)> feedback)
  : _refresh_thread(NULL), _cache_working(1), _connection_id(connection_id),
    _get_connection(get_connection), _shutdown(false)
{
  _feedback = feedback;
  std::string path = make_path(cache_dir, _connection_id) + ".cache";
  bool newDb = !base::file_exists(path);
  if (!newDb)
    newDb = base::tryRemove(path);

  _sqconn = new sqlite::connection(path);
  sqlite::execute(*_sqconn, "PRAGMA temp_store=MEMORY", true);
  sqlite::execute(*_sqconn, "PRAGMA synchronous=NORMAL", true);

  // Re-init only if we could remove the cache file, which might fail if another connection
  // is open already that uses this cache.
  if (newDb)
    init_db();

  log_debug2("Using autocompletion cache file %s\n", (make_path(cache_dir, _connection_id) + ".cache").c_str());


  // Top level objects.
  // They are retrieved automatically only once to limit traffic to the server.
  // The user can manually trigger a refresh when needed.
  add_pending_refresh(RefreshTask::RefreshSchemas);

  // Objects that don't change while a server is running.
  add_pending_refresh(RefreshTask::RefreshVariables);
  add_pending_refresh(RefreshTask::RefreshEngines);
  add_pending_refresh(RefreshTask::RefreshCharsets);
  add_pending_refresh(RefreshTask::RefreshCollations);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::shutdown()
{
  {
    // Temporarily lock both mutexes so we wait for any ongoing work.
    base::RecMutexLock connection_lock(_sqconn_mutex);
    base::RecMutexLock pending_lock(_pending_mutex);
    _shutdown = true;

    _pending_tasks.clear();
    _feedback = NULL;
  }

  if (_refresh_thread)
  {
    log_debug2("Waiting for worker thread to finish...\n");
    g_thread_join(_refresh_thread);
    _refresh_thread = NULL;
    log_debug2("Worker thread finished.\n");
  }
}

//--------------------------------------------------------------------------------------------------

AutoCompleteCache::~AutoCompleteCache()
{
  g_assert(_shutdown);

  delete _sqconn;
}

//--------------------------------------------------------------------------------------------------

std::vector<std::string> AutoCompleteCache::get_matching_schema_names(const std::string &prefix)
{
  return get_matching_objects("schemas", "", "",  prefix, RetrieveWithNoQualifier);
}

//--------------------------------------------------------------------------------------------------

std::vector<std::string> AutoCompleteCache::get_matching_table_names(const std::string &schema, const std::string &prefix)
{
  refresh_schema_cache_if_needed(schema);

  return get_matching_objects("tables", schema, "", prefix, RetrieveWithSchemaQualifier);
}

//--------------------------------------------------------------------------------------------------

std::vector<std::string> AutoCompleteCache::get_matching_view_names(const std::string &schema, const std::string &prefix)
{
  refresh_schema_cache_if_needed(schema);

  return get_matching_objects("views", schema, "", prefix, RetrieveWithSchemaQualifier);
}

//--------------------------------------------------------------------------------------------------

std::vector<std::string> AutoCompleteCache::get_matching_column_names(const std::string &schema,
  const std::string &table, const std::string &prefix)
{
  refresh_schema_cache_if_needed(schema);
  
  return get_matching_objects("columns", schema, table, prefix, RetrieveWithFullQualifier);
}

//--------------------------------------------------------------------------------------------------

std::vector<std::string> AutoCompleteCache::get_matching_procedure_names(const std::string &schema,
  const std::string &prefix)
{
  refresh_schema_cache_if_needed(schema);
  
  return get_matching_objects("procedures", schema, "", prefix, RetrieveWithSchemaQualifier);
}

//--------------------------------------------------------------------------------------------------

std::vector<std::string> AutoCompleteCache::get_matching_function_names(const std::string &schema,
  const std::string &prefix)
{
  refresh_schema_cache_if_needed(schema);

  return get_matching_objects("functions", schema, "", prefix, RetrieveWithSchemaQualifier);
}

//--------------------------------------------------------------------------------------------------

std::vector<std::string> AutoCompleteCache::get_matching_trigger_names(const std::string &schema,
  const std::string &table, const std::string &prefix)
{
  refresh_schema_cache_if_needed(schema);

  return get_matching_objects("triggers", schema, table, prefix, RetrieveWithSchemaQualifier);
}

//--------------------------------------------------------------------------------------------------

std::vector<std::string> AutoCompleteCache::get_matching_udf_names(const std::string &prefix)
{
  return get_matching_objects("udfs", "", "", prefix, RetrieveWithNoQualifier);
}

//--------------------------------------------------------------------------------------------------

std::vector<std::string> AutoCompleteCache::get_matching_variables(const std::string &prefix)
{
  // System variables names are cached at startup as their existence/names will never change.
  return get_matching_objects("variables", "", "", prefix, RetrieveWithNoQualifier);
}

//--------------------------------------------------------------------------------------------------

std::vector<std::string> AutoCompleteCache::get_matching_engines(const std::string &prefix)
{
  // Engines are cached at startup as they will never change (as long as we are connected).
  return get_matching_objects("engines", "", "", prefix, RetrieveWithNoQualifier);
}

//--------------------------------------------------------------------------------------------------

std::vector<std::string> AutoCompleteCache::get_matching_logfile_groups(const std::string &prefix)
{
  add_pending_refresh(RefreshTask::RefreshLogfileGroups);

  return get_matching_objects("logfile_groups", "", "", prefix, RetrieveWithNoQualifier);
}

//--------------------------------------------------------------------------------------------------

std::vector<std::string> AutoCompleteCache::get_matching_tablespaces(const std::string &prefix)
{
  add_pending_refresh(RefreshTask::RefreshTableSpaces);

  return get_matching_objects("tablespaces", "", "", prefix, RetrieveWithNoQualifier);
}

//--------------------------------------------------------------------------------------------------

std::vector<std::string> AutoCompleteCache::get_matching_charsets(const std::string &prefix)
{
  return get_matching_objects("charsets", "", "", prefix, RetrieveWithNoQualifier);
}

//--------------------------------------------------------------------------------------------------

std::vector<std::string> AutoCompleteCache::get_matching_collations(const std::string &prefix)
{
  return get_matching_objects("collations", "", "", prefix, RetrieveWithNoQualifier);
}

//--------------------------------------------------------------------------------------------------

std::vector<std::string> AutoCompleteCache::get_matching_events(const std::string &schema, const std::string &prefix)
{
  return get_matching_objects("events", schema, "", prefix, RetrieveWithSchemaQualifier);
}

//--------------------------------------------------------------------------------------------------

/**
 * Core object retrieval function.
 */
std::vector<std::string> AutoCompleteCache::get_matching_objects(const std::string &cache,
  const std::string &schema, const std::string &table, const std::string &prefix, RetrievalType type)
{
  base::RecMutexLock lock(_sqconn_mutex);
  if (_shutdown)
    return std::vector<std::string>();

  std::vector<std::string> items;
  std::string sql;
  switch (type)
  {
  case RetrieveWithNoQualifier:
    sql = "SELECT name FROM " + cache + " WHERE name LIKE ? ESCAPE '\\'";
    break;
  case RetrieveWithSchemaQualifier:
    sql = "SELECT name FROM " + cache + " WHERE schema_id LIKE ? ESCAPE '\\' "
      "AND name LIKE ? ESCAPE '\\'";
    break;
  default: // RetrieveWithFullQualifier
    sql = "SELECT name FROM " + cache + " WHERE schema_id LIKE ? ESCAPE '\\' "
      "AND table_id LIKE ? ESCAPE '\\' AND name LIKE ? ESCAPE '\\'";
    break;
  }

  sqlite::query q(*_sqconn, sql);
  switch (type)
  {
  case RetrieveWithNoQualifier:
    q.bind(1, base::escape_sql_string(prefix, true) + "%");
    break;
  case RetrieveWithSchemaQualifier:
    q.bind(1, schema.empty() ? "%" : base::escape_sql_string(schema, true));
    q.bind(2, base::escape_sql_string(prefix, true) + "%");
    break;
  default: // RetrieveWithFullQualifier
    q.bind(1, schema.empty() ? "%" : base::escape_sql_string(schema, true));
    q.bind(2, table.empty() ? "%" : base::escape_sql_string(table, true));
    q.bind(3, base::escape_sql_string(prefix, true) + "%");
    break;
  }

  if (q.emit())
  {
    boost::shared_ptr<sqlite::result> matches(q.get_result());
    do
    {
      items.push_back(matches->get_string(0));
    } while (matches->next_row());
  }

  return items;
}

//--------------------------------------------------------------------------------------------------

/**
 * Update all schema names. Used by code outside this class.
 */
void AutoCompleteCache::refresh_schema_list()
{
  add_pending_refresh(RefreshTask::RefreshSchemas);
}

//--------------------------------------------------------------------------------------------------

/**
 * Checks if the given schema was loaded already (only tables, views, routines and columns).
 * If not, the loading is triggered. Other objects are loaded on demand.
 */
bool AutoCompleteCache::refresh_schema_cache_if_needed(const std::string &schema)
{
  if (schema.empty())
    return false;

  base::RecMutexLock lock(_sqconn_mutex);
  if (_shutdown)
    return false;

  sqlite::query q(*_sqconn, "SELECT last_refresh FROM schemas WHERE name LIKE ? ESCAPE '\\' ");
  q.bind(1, schema.empty() ? "%" : base::escape_sql_string(schema, true));
  if (q.emit())
  {
    boost::shared_ptr<sqlite::result> matches(q.get_result());
    // If a value is set for last_refresh then schema info is already loaded in cache.
    if (matches->get_int(0) != 0)
    {
      log_debug3("schema %s is already cached\n", schema.c_str());
      return false;
    }
  }

  // Add tasks to load various schema objects. They will then update the last_refresh value.
  log_debug3("schema %s is not cached, populating cache...\n", schema.c_str());

  // Refreshing a schema implicitly refreshs its local objects too.
  add_pending_refresh(RefreshTask::RefreshTables, schema);
  add_pending_refresh(RefreshTask::RefreshViews, schema);
  add_pending_refresh(RefreshTask::RefreshProcedures, schema);
  add_pending_refresh(RefreshTask::RefreshFunctions, schema);
  add_pending_refresh(RefreshTask::RefreshEvents, schema);

  return true;
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::refresh_columns(const std::string &schema, const std::string &table)
{
  add_pending_refresh(RefreshTask::RefreshColumns, schema, table);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::refresh_triggers(const std::string &schema, const std::string &table)
{
  add_pending_refresh(RefreshTask::RefreshTableSpaces, schema, table);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::refresh_udfs()
{
  add_pending_refresh(RefreshTask::RefreshUDFs);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::refresh_tablespaces()
{
  add_pending_refresh(RefreshTask::RefreshTableSpaces);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::refresh_logfile_groups()
{
  add_pending_refresh(RefreshTask::RefreshLogfileGroups);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::refresh_events()
{
  add_pending_refresh(RefreshTask::RefreshEvents);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::refresh_cache_thread()
{
  log_debug2("entering worker thread\n");

  while (!_shutdown)
  {
    try
    {
      RefreshTask task;
      if (!get_pending_refresh(task)) // If there's nothing more to do end the thread.
        break;

      if (_shutdown)
        break;

      switch (task.type)
      {
        case RefreshTask::RefreshSchemas:
          refresh_schemas_w();
          break;

        case RefreshTask::RefreshTables:
          refresh_tables_w(task.schema_name);
          break;

        case RefreshTask::RefreshViews:
          refresh_views_w(task.schema_name);
          break;

        case RefreshTask::RefreshProcedures:
          refresh_procedures_w(task.schema_name);
          break;

        case RefreshTask::RefreshFunctions:
          refresh_functions_w(task.schema_name);
          break;

        case RefreshTask::RefreshColumns:
          refresh_columns_w(task.schema_name, task.table_name);
          break;

        case RefreshTask::RefreshTriggers:
          refresh_triggers_w(task.schema_name, task.table_name);
          break;

        case RefreshTask::RefreshUDFs:
          refresh_udfs_w();
          break;

        case RefreshTask::RefreshCharsets:
          refreshCharsets_w();
          break;

        case RefreshTask::RefreshCollations:
          refreshCollations_w();
          break;

        case RefreshTask::RefreshVariables:
          refresh_variables_w();
          break;

        case RefreshTask::RefreshEngines:
          refresh_engines_w();
          break;

        case RefreshTask::RefreshLogfileGroups:
          refresh_logfile_groups_w();
          break;

        case RefreshTask::RefreshTableSpaces:
          refresh_tablespaces_w();
          break;

        case RefreshTask::RefreshEvents:
          refreshEvents_w(task.schema_name);

        break;
      }
    }
    catch (std::exception &exc)
    {
      log_error("Exception while running refresh task: %s\n", exc.what());
    }
  }

  // Signal the main thread that the worker thread is (about to be) gone.
  _cache_working.post();

  if (_feedback && !_shutdown)
    _feedback(false);

  log_debug2("leaving worker thread\n");
}

//--------------------------------------------------------------------------------------------------

void *AutoCompleteCache::_refresh_cache_thread(void *data)
{
  try
  {
    AutoCompleteCache *self = reinterpret_cast<AutoCompleteCache*>(data);
    self->refresh_cache_thread();
  }
  catch (sql::SQLException &exc)
  {
    log_error("SQLException executing refresh_cache_thread: Error Code: %d\n, %s\n", exc.getErrorCode(), exc.what());
  }

  return NULL;
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::refresh_schemas_w()
{
  std::vector<std::string> schemas;
  {
    sql::Dbc_connection_handler::Ref conn;
    base::RecMutexLock lock(_get_connection(conn));
    {
      std::auto_ptr<sql::Statement> statement(conn->ref->createStatement());
      std::auto_ptr<sql::ResultSet> rs(statement->executeQuery("SHOW DATABASES"));
      if (rs.get())
      {
        while (rs->next() && !_shutdown)
          schemas.push_back(rs->getString(1));
        log_debug2("Found %li schemas\n", (long)schemas.size());
      }
      else
        log_debug2("No schema found\n");
    }
  }

  if (!_shutdown)
    update_schemas(schemas);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::refresh_tables_w(const std::string &schema)
{
  base::StringListPtr tables(new std::list<std::string>());
  {
    sql::Dbc_connection_handler::Ref conn;

    // TODO: check if it is possible that the connection can be locked even it was already deleted.
    base::RecMutexLock lock(_get_connection(conn));
    {
      // Avoid an exception for an unknown schema by checking in advance.
      std::auto_ptr<sql::Statement> statement(conn->ref->createStatement());
      std::string sql = base::sqlstring("show schemas like ?", 0) << schema;
      std::auto_ptr<sql::ResultSet> rs1(statement->executeQuery(sql));
      if (rs1.get() && rs1->next())
      {
        sql = base::sqlstring("SHOW FULL TABLES FROM !", 0) << schema;
        std::auto_ptr<sql::ResultSet> rs2(statement->executeQuery(sql));
        if (rs2.get())
        {
          while (rs2->next() && !_shutdown)
          {
            std::string type = rs2->getString(2);
            std::string table = rs2->getString(1);
            if (type != "VIEW")
            {
              tables->push_back(table);

              // Implicitly load table-local objects for each table/view.
              add_pending_refresh(RefreshTask::RefreshColumns, schema, table);
              add_pending_refresh(RefreshTask::RefreshTriggers, schema, table);
            }
          }

          log_debug2("Found %li tables\n", (long)tables->size());
        }
        else
          log_debug2("No tables found for %s\n", schema.c_str());
      }
    }
  }

  if (!_shutdown)
    update_object_names("tables", schema, tables);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::refresh_views_w(const std::string &schema)
{
  base::StringListPtr views(new std::list<std::string>());
  {
    sql::Dbc_connection_handler::Ref conn;

    base::RecMutexLock lock(_get_connection(conn));
    {
      // Avoid an exception for an unknown schema by checking in advance.
      std::auto_ptr<sql::Statement> statement(conn->ref->createStatement());
      std::string sql = base::sqlstring("show schemas like ?", 0) << schema;
      std::auto_ptr<sql::ResultSet> rs1(statement->executeQuery(sql));
      if (rs1.get() && rs1->next())
      {
        sql = base::sqlstring("SHOW FULL TABLES FROM !", 0) << schema;
        std::auto_ptr<sql::ResultSet> rs2(statement->executeQuery(sql));
        if (rs2.get())
        {
          while (rs2->next() && !_shutdown)
          {
            std::string type = rs2->getString(2);
            std::string table = rs2->getString(1);
            if (type == "VIEW")
            {
              views->push_back(table);

              // Implicitly load columns for each table/view.
              add_pending_refresh(RefreshTask::RefreshColumns, schema, table);
            }
          }

          log_debug2("Found %li views\n", (long)views->size());
        }
        else
          log_debug2("No views found for %s\n", schema.c_str());
      }
    }
  }

  if (!_shutdown)
    update_object_names("views", schema, views);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::refresh_functions_w(const std::string &schema)
{
  base::StringListPtr functions(new std::list<std::string>());
  {
    sql::Dbc_connection_handler::Ref conn;
    base::RecMutexLock lock(_get_connection(conn));
    {
      std::string sql = base::sqlstring("SHOW FUNCTION STATUS WHERE Db=?", 0) << schema;
      std::auto_ptr<sql::Statement> statement(conn->ref->createStatement());
      std::auto_ptr<sql::ResultSet> rs(statement->executeQuery(sql));
      if (rs.get())
      {
        while (rs->next() && !_shutdown)
          functions->push_back(rs->getString(2));
      }
      else
        log_debug2("No functions found for %s\n", schema.c_str());
    }
  }

  if (!_shutdown)
    update_object_names("functions", schema, functions);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::refresh_procedures_w(const std::string &schema)
{
  base::StringListPtr procedures(new std::list<std::string>());
  {
    sql::Dbc_connection_handler::Ref conn;
    base::RecMutexLock lock(_get_connection(conn));
    {
      std::string sql = base::sqlstring("SHOW PROCEDURE STATUS WHERE Db=?", 0) << schema;
      std::auto_ptr<sql::Statement> statement(conn->ref->createStatement());
      std::auto_ptr<sql::ResultSet> rs(statement->executeQuery(sql));
      if (rs.get())
      {
        while (rs->next() && !_shutdown)
          procedures->push_back(rs->getString(2));
      }
      else
        log_debug2("No procedures found for %s\n", schema.c_str());
    }
  }
  if (!_shutdown)
    update_object_names("procedures", schema, procedures);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::refresh_columns_w(const std::string &schema, const std::string &table)
{
  std::vector<std::string> columns;
  {
    sql::Dbc_connection_handler::Ref conn;
    base::RecMutexLock lock(_get_connection(conn));
    {
      std::string sql = base::sqlstring("SHOW COLUMNS FROM !.!", 0) << schema << table;
      std::auto_ptr<sql::Statement> statement(conn->ref->createStatement());
      std::auto_ptr<sql::ResultSet> rs(statement->executeQuery(sql));
      if (rs.get())
      {
        while (rs->next() && !_shutdown)
          columns.push_back(rs->getString(1));
      }
      else
        log_debug2("No columns found for schema %s and table %s\n", schema.c_str(), table.c_str());
    }
  }

  if (!_shutdown)
    update_object_names("columns", schema, table, columns);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::refresh_triggers_w(const std::string &schema, const std::string &table)
{
  std::vector<std::string> triggers;
  {
    sql::Dbc_connection_handler::Ref conn;
    base::RecMutexLock lock(_get_connection(conn));
    {
      std::string sql;
      if (!table.empty())
        sql = base::sqlstring("SHOW TRIGGERS FROM ! WHERE ! = ?", 0) << schema << "Table" << table;
      else
        sql = base::sqlstring("SHOW TRIGGERS FROM !", 0) << schema;

      std::auto_ptr<sql::Statement> statement(conn->ref->createStatement());
      std::auto_ptr<sql::ResultSet> rs(statement->executeQuery(sql));
      if (rs.get())
      {
        while (rs->next() && !_shutdown)
          triggers.push_back(rs->getString(1));
      }
      else
        log_debug2("No triggers found for schema %s and table %s\n", schema.c_str(), table.c_str());
    }
  }

  if (!_shutdown)
    update_object_names("triggers", schema, table, triggers);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::refresh_udfs_w()
{
  std::vector<std::string> udfs;
  {
    sql::Dbc_connection_handler::Ref conn;
    base::RecMutexLock lock(_get_connection(conn));
    {
      std::auto_ptr<sql::Statement> statement(conn->ref->createStatement());
      std::auto_ptr<sql::ResultSet> rs(statement->executeQuery("SELECT NAME FROM mysql.func"));
      if (rs.get())
      {
        while (rs->next() && !_shutdown)
          udfs.push_back(rs->getString(1));

        log_debug2("Found %li UDFs.\n", (long)udfs.size());
      }
      else
        log_debug2("No UDF found.\n");
    }
  }

  if (!_shutdown)
    update_object_names("udfs", udfs);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::refreshCharsets_w()
{
  std::vector<std::string> charsets;
  {
    sql::Dbc_connection_handler::Ref conn;
    base::RecMutexLock lock(_get_connection(conn));
    {
      std::auto_ptr<sql::Statement> statement(conn->ref->createStatement());
      std::auto_ptr<sql::ResultSet> rs(statement->executeQuery("show charset"));
      if (rs.get())
      {
        while (rs->next() && !_shutdown)
          charsets.push_back(rs->getString(1));

        log_debug2("Found %li character sets.\n", (long)charsets.size());
      }
      else
        log_debug2("No character sets found.\n");
    }
  }

  if (!_shutdown)
    update_object_names("charsets", charsets);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::refreshCollations_w()
{
  std::vector<std::string> collations;
  {
    sql::Dbc_connection_handler::Ref conn;
    base::RecMutexLock lock(_get_connection(conn));
    {
      std::auto_ptr<sql::Statement> statement(conn->ref->createStatement());
      std::auto_ptr<sql::ResultSet> rs(statement->executeQuery("show collation"));
      if (rs.get())
      {
        while (rs->next() && !_shutdown)
          collations.push_back(rs->getString(1));

        log_debug2("Found %li collations.\n", (long)collations.size());
      }
      else
        log_debug2("No collations found.\n");
    }
  }

  if (!_shutdown)
    update_object_names("collations", collations);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::refresh_variables_w()
{
  std::vector<std::string> variables;
  {
    sql::Dbc_connection_handler::Ref conn;
    base::RecMutexLock lock(_get_connection(conn));
    {
      std::auto_ptr<sql::Statement> statement(conn->ref->createStatement());
      std::auto_ptr<sql::ResultSet> rs(statement->executeQuery("SHOW GLOBAL VARIABLES"));
      if (rs.get())
      {
        while (rs->next() && !_shutdown)
          variables.push_back("@@" + rs->getString(1));

        log_debug2("Found %li variables.\n", (long)variables.size());
      }
      else
        log_debug2("No variables found.\n");
    }
  }

  if (!_shutdown)
    update_object_names("variables", variables);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::refresh_engines_w()
{
  std::vector<std::string> engines;
  {
    sql::Dbc_connection_handler::Ref conn;
    base::RecMutexLock lock(_get_connection(conn));
    {
      std::auto_ptr<sql::Statement> statement(conn->ref->createStatement());
      std::auto_ptr<sql::ResultSet> rs(statement->executeQuery("SHOW ENGINES"));
      if (rs.get())
      {
        while (rs->next() && !_shutdown)
          engines.push_back(rs->getString(1));

        log_debug2("Found %li engines.\n", (long)engines.size());
      }
      else
        log_debug2("No engines found.\n");
    }
  }

  if (!_shutdown)
    update_object_names("engines", engines);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::refresh_logfile_groups_w()
{
  std::vector<std::string> logfile_groups;
  {
    sql::Dbc_connection_handler::Ref conn;
    base::RecMutexLock lock(_get_connection(conn));
    {
      std::auto_ptr<sql::Statement> statement(conn->ref->createStatement());

      // Logfile groups and tablespaces are referenced as single unqualified identifiers in MySQL syntax.
      // They are stored however together with a table schema and a table name.
      // For auto completion however we only need to support what the syntax supports.
      std::auto_ptr<sql::ResultSet> rs(statement->executeQuery("SELECT distinct logfile_group_name FROM information_schema.FILES"));
      if (rs.get())
      {
        while (rs->next() && !_shutdown)
          logfile_groups.push_back(rs->getString(1));

        log_debug2("Found %li logfile groups.\n", (long)logfile_groups.size());
      }
      else
        log_debug2("No logfile group found.\n");
    }
  }

  if (!_shutdown)
    update_object_names("logfile_groups", logfile_groups);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::refresh_tablespaces_w()
{
  std::vector<std::string> tablespaces;
  {
    sql::Dbc_connection_handler::Ref conn;
    base::RecMutexLock lock(_get_connection(conn));
    {
      std::auto_ptr<sql::Statement> statement(conn->ref->createStatement());
      std::auto_ptr<sql::ResultSet> rs(statement->executeQuery("SELECT distinct tablespace_name FROM information_schema.FILES"));
      if (rs.get())
      {
        while (rs->next() && !_shutdown)
        {
          std::string entry = rs->getString(1);
          if (!entry.empty())
            tablespaces.push_back(entry);
        }

        log_debug2("Found %li tablespaces.\n", (long)tablespaces.size());
      }
      else
        log_debug2("No tablespaces found.\n");
    }
  }

  if (!_shutdown)
    update_object_names("tablespaces", tablespaces);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::refreshEvents_w(const std::string &schema)
{
  base::StringListPtr events(new std::list<std::string>());
  {
    sql::Dbc_connection_handler::Ref conn;
    base::RecMutexLock lock(_get_connection(conn));
    {
      std::string sql = base::sqlstring("SELECT EVENT_NAME FROM information_schema.EVENTS WHERE EVENT_SCHEMA = ?", 0) << schema;
      std::auto_ptr<sql::Statement> statement(conn->ref->createStatement());
      std::auto_ptr<sql::ResultSet> rs(statement->executeQuery(sql));
      if (rs.get())
      {
        while (rs->next() && !_shutdown)
        {
          std::string entry = rs->getString(1);
          if (!entry.empty())
            events->push_back(entry);
        }

        log_debug2("Found %li events in schema %s.\n", (long)events->size(), schema.c_str());
      }
      else
        log_debug2("No events found for schema %s.\n", schema.c_str());
    }
  }

  if (!_shutdown)
    update_object_names("events", schema, events);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::init_db()
{
  log_info("Initializing autocompletion cache for %s\n", _connection_id.c_str());

  try
  {
    std::string sql = "create table meta (name varchar(64) primary key, value varchar(64))";
    sqlite::execute(*_sqconn, sql, true);
  }
  catch (std::exception &exc)
  {
    log_error("Error creating cache db.meta: %s\n", exc.what());
  }

  try
  {
    std::string sql = "create table schemas (name varchar(64) primary key, last_refresh int default 0)";
    sqlite::execute(*_sqconn, sql, true);
  }
  catch (std::exception &exc)
  {
    log_error("Error creating cache db.schemas: %s\n", exc.what());
  }

  // Creation of cache tables that consist only of a single column (name).
  std::string single_param_caches[] = {"variables", "engines", "tablespaces", "logfile_groups", "udfs", "charsets", "collations"};

  for (size_t i = 0; i < sizeof(single_param_caches) / sizeof(single_param_caches[0]); ++i)
  {
    try
    {
      std::string sql = "create table " + single_param_caches[i] + " (name varchar(64) primary key)";
      sqlite::execute(*_sqconn, sql, true);
    }
    catch (std::exception &exc)
    {
      log_error("Error creating cache db.%s: %s\n", single_param_caches[i].c_str(), exc.what());
    }
  }

  // Creation of cache tables that consist of a name and a schema column.
  std::string dual_param_caches[] = {"tables", "views", "functions", "procedures", "events"};

  for (size_t i = 0; i < sizeof(dual_param_caches) / sizeof(dual_param_caches[0]); ++i)
  {
    try
    {
      std::string sql = "create table " + dual_param_caches[i] + " (schema_id varchar(64) NOT NULL, "
        " name varchar(64) NOT NULL, primary key (schema_id, name))";
      sqlite::execute(*_sqconn, sql, true);
    }
    catch (std::exception &exc)
    {
      log_error("Error creating cache db.%s: %s\n", dual_param_caches[i].c_str(), exc.what());
    }
  }

  // Creation of cache tables that consist of a name, a schema and a table column.
  std::string triple_param_caches[] = {"columns", "triggers"};

  for (size_t i = 0; i < sizeof(triple_param_caches) / sizeof(triple_param_caches[0]); ++i)
  {
    try
    {
      std::string sql = "create table " + triple_param_caches[i] + " (schema_id varchar(64) NOT NULL, "
        "table_id varchar(64) NOT NULL, name varchar(64) NOT NULL, "
        "primary key (schema_id, table_id, name), "
        "foreign key (schema_id, table_id) references tables (schema_id, name) on delete cascade)";
      sqlite::execute(*_sqconn, sql, true);
    }
    catch (std::exception &exc)
    {
      log_error("Error creating cache db.%s: %s\n", triple_param_caches[i].c_str(), exc.what());
    }
  }

}

//--------------------------------------------------------------------------------------------------

bool AutoCompleteCache::is_schema_list_fetch_done()
{
  // TODO: optimize this.
  base::RecMutexLock lock(_sqconn_mutex);
  sqlite::query q(*_sqconn, "select * from schemas");
  if (q.emit())
    return true;
  return false;
}

//--------------------------------------------------------------------------------------------------

bool AutoCompleteCache::is_schema_tables_fetch_done(const std::string &schema)
{
  return is_fetch_done("tables", schema);
}

//--------------------------------------------------------------------------------------------------

bool AutoCompleteCache::is_schema_table_columns_fetch_done(const std::string &schema, const std::string &table)
{
  return is_fetch_done("columns", schema);
}

//--------------------------------------------------------------------------------------------------

bool AutoCompleteCache::is_schema_functions_fetch_done(const std::string &schema)
{
  return is_fetch_done("functions", schema);
}

//--------------------------------------------------------------------------------------------------

bool AutoCompleteCache::is_schema_procedure_fetch_done(const std::string &schema)
{
  return is_fetch_done("procedures", schema);
}

//--------------------------------------------------------------------------------------------------

bool AutoCompleteCache::is_fetch_done(const std::string &cache, const std::string &schema)
{
  base::RecMutexLock lock(_sqconn_mutex);
  sqlite::query q(*_sqconn, "select * from " + cache + " where schema_id = ?");
  q.bind(1, schema);
  if (q.emit())
    return true;
  return false;
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::touch_schema_record(const std::string &schema)
{
  {
    sqlite::query q(*_sqconn, "select * from schemas where name=?");
    q.bind(1, schema);
    if (q.emit())
    {
      sqlite::command update(*_sqconn, "update schemas set last_refresh=strftime('%s', 'now') where name=?");
      update.bind(1, schema);
      update.emit();
      return;
    }
  }
  {
    sqlite::command insert(*_sqconn, "insert into schemas (name, last_refresh) values (?, strftime('%s', 'now'))");
    insert.bind(1, schema);
    insert.emit();
  }
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::update_schemas(const std::vector<std::string> &schemas)
{
  try
  {
    base::RecMutexLock lock(_sqconn_mutex);
    if (_shutdown)
      return;

    std::map<std::string, int> old_schema_update_times;
    {
      sqlite::query q(*_sqconn, "select name, last_refresh from schemas");
      if (q.emit())
      {
        boost::shared_ptr<sqlite::result> matches(q.get_result());
        do
        {
          std::string name = matches->get_string(0);
          if (!name.empty()) // Entry with empty name means a fetch is underway.
            old_schema_update_times[name] = matches->get_int(1);
        }
        while (matches->next_row());
      }
    }

    sqlide::Sqlite_transaction_guarder trans(_sqconn, false);
    {
      sqlite::execute del(*_sqconn, "delete from schemas");
      del.emit();
    }

    // If there are no schemas, create a dummy item signaling the update already happened.
    if (schemas.empty())
    {
      sqlite::execute insert(*_sqconn, "insert into schemas (name) values ('')");
      insert.emit();
    }
    else
    {
      sqlite::execute insert(*_sqconn, "insert into schemas (name, last_refresh) values (?, ?)");
      for (std::vector<std::string>::const_iterator t = schemas.begin(); t != schemas.end(); ++t)
      {
        insert.bind(1, *t);
        if (old_schema_update_times.find(*t) == old_schema_update_times.end())
          insert.bind(2, 0);
        else
          insert.bind(2, old_schema_update_times[*t]);
        insert.emit();
        insert.clear();
      }
    }
  }
  catch (std::exception &exc)
  {
    log_error("Exception caught while updating schema name cache: %s\n", exc.what());
  }
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::update_tables(const std::string &schema, base::StringListPtr tables)
{
  update_object_names("tables", schema, tables);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::update_views(const std::string &schema, base::StringListPtr views)
{
  update_object_names("views", schema, views);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::update_procedures(const std::string &schema, base::StringListPtr procedures)
{
  update_object_names("procedures", schema, procedures);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::update_functions(const std::string &schema, base::StringListPtr functions)
{
  update_object_names("functions", schema, functions);
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::update_events(const std::string &schema, base::StringListPtr events)
{
  update_object_names("events", schema, events);
}

//--------------------------------------------------------------------------------------------------

/**
 * Central update routine for cache tables that have a single column "name".
 */
void AutoCompleteCache::update_object_names(const std::string &cache, const std::vector<std::string> &objects)
{
  try
  {
    base::RecMutexLock lock(_sqconn_mutex);
    if (_shutdown)
      return;

    sqlide::Sqlite_transaction_guarder trans(_sqconn, false);
    {
      sqlite::execute del(*_sqconn, "delete from " + cache);
      del.emit();
    }

    sqlite::execute insert(*_sqconn, "insert into " + cache + " (name) values (?)");
    for (std::vector<std::string>::const_iterator i = objects.begin(); i != objects.end(); ++i)
    {
      insert.bind(1, *i);
      insert.emit();
      insert.clear();
    }
  }
  catch (std::exception &exc)
  {
    log_error("Exception caught while updating object name in cache %s: %s\n", cache.c_str(), exc.what());
  }
}

//--------------------------------------------------------------------------------------------------

/**
 * Updates a cache table with objects for a given schema.
 * We use here a (less efficient) list for the objects instead of a vector, as we use this code also
 * for calls from the SQL IDE which uses lists for them.
 */
void AutoCompleteCache::update_object_names(const std::string &cache, const std::string &schema,
  base::StringListPtr objects)
{
  try
  {
    base::RecMutexLock lock(_sqconn_mutex);
    if (_shutdown)
      return;

    sqlide::Sqlite_transaction_guarder trans(_sqconn, false); // Will be committed when we go out of the scope.

    sqlite::execute del(*_sqconn, "delete from " + cache + " where schema_id = ?");
    del.bind(1, schema);
    del.emit();

    sqlite::query insert(*_sqconn, "insert into " + cache + " (schema_id, name) values (?, ?)");
    insert.bind(1, schema);
    for (std::list<std::string>::const_iterator i = objects->begin(); i != objects->end(); ++i)
    {
      insert.bind(2, *i);
      insert.emit();
      insert.clear();
    }
  }
  catch (std::exception &exc)
  {
    log_error("Exception caught while updating %s name cache for schema %s: %s\n", cache.c_str(),
      schema.c_str(), exc.what());
  }
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::update_object_names(const std::string &cache, const std::string &schema,
  const std::string &table, const std::vector<std::string> &objects)
{
  try
  {
    base::RecMutexLock lock(_sqconn_mutex);
    if (_shutdown)
      return;

    sqlide::Sqlite_transaction_guarder trans(_sqconn, false);

    // Clear records for this schema/table.
    {
      sqlite::execute del(*_sqconn, "delete from " + cache + " where schema_id = ? and table_id = ?");
      del.bind(1, schema);
      del.bind(2, table);
      del.emit();
    }

    sqlite::query insert(*_sqconn, "insert into " + cache + " (schema_id, table_id, name) values (?, ?, ?)");
    insert.bind(1, schema);
    insert.bind(2, table);
    for (std::vector<std::string>::const_iterator i = objects.begin(); i != objects.end(); ++i)
    {
      insert.bind(3, *i);
      insert.emit();
      insert.clear();
    }
  }
  catch (std::exception &exc)
  {
    log_error("Exception caught while updating %s name cache for %s.%s: %s\n", cache.c_str(),
              schema.c_str(), table.c_str(), exc.what());
  }
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::add_pending_refresh(RefreshTask::RefreshType type, const std::string &schema,
  const std::string &table)
{
  base::RecMutexLock lock(_pending_mutex);
  if (_shutdown)
    return;

  // Add the new task only if there isn't already one of the same type and for the same objects.
  bool found = false;
  for (std::list<RefreshTask>::const_iterator i = _pending_tasks.begin(); !found && i != _pending_tasks.end(); ++i)
  {
    if (i->type != type)
      continue;

    switch (type) {
      case RefreshTask::RefreshSchemas:
      case RefreshTask::RefreshVariables:
      case RefreshTask::RefreshEngines:
      case RefreshTask::RefreshUDFs:
      case RefreshTask::RefreshCharsets:
      case RefreshTask::RefreshCollations:
        found = true;
        break;

      case RefreshTask::RefreshTables:
      case RefreshTask::RefreshViews:
      case RefreshTask::RefreshProcedures:
      case RefreshTask::RefreshFunctions:
      case RefreshTask::RefreshEvents:
        found = i->schema_name == schema;
        break;

      case RefreshTask::RefreshTriggers:
      case RefreshTask::RefreshColumns:
      case RefreshTask::RefreshLogfileGroups:
      case RefreshTask::RefreshTableSpaces:
        found = (i->schema_name == schema) && (i->table_name == table);
        break;
    }
    if (found)
      break;
  }

  if (!found)
    _pending_tasks.push_back(RefreshTask(type, schema, table));

  // Create the worker thread if there's work to do. Does nothing if there's already a thread.
  if (_pending_tasks.size() > 0)
    create_worker_thread();
}

//--------------------------------------------------------------------------------------------------

bool AutoCompleteCache::get_pending_refresh(RefreshTask &task)
{
  bool result = false;

  base::RecMutexLock lock(_pending_mutex);
  if (_shutdown)
    return result;

  if (!_pending_tasks.empty())
  {
    result = true;
    task = _pending_tasks.front();
    _pending_tasks.pop_front();
  }

  return result;
}

//--------------------------------------------------------------------------------------------------

void AutoCompleteCache::create_worker_thread()
{
  // Fire up thread to start caching.
  if (!_cache_working.try_wait()) // If there is already working thread, just do nothing and exit.
    return;

  //we need to wait for previous thread to finish before we create new thread
  if (_refresh_thread != NULL)
  {
    //this may lead to undefined behavior if g_thread_join would be called from different threads that will wait for one single thread,
    //but for now we need to wait for it, because we can deadlock when closing sqlide
    g_thread_join(_refresh_thread);
    _refresh_thread = NULL;
  }
  if (!_shutdown)
  {
    log_debug3("creating worker thread\n");

    GError *error = NULL;
    _refresh_thread = base::create_thread(&AutoCompleteCache::_refresh_cache_thread, this, &error);
    if (!_refresh_thread)
    {
      log_error("Error creating autocompletion worker thread: %s\n", error ? error->message : "out of mem?");
      g_error_free(error);
    }
    else
      if (_feedback)
        _feedback(true);
  }
}

//--------------------------------------------------------------------------------------------------
