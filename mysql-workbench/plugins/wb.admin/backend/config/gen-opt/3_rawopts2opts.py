import raw_opts
import raw_vars
import options_layout
import pprint
from variable_column_widths import variable_column_widths

print('-----------------------------------\nRunning %s\n-----------------------------------\n' % __file__)

print "Converting raw_opts.py to opts.py"


def hack_option(option):
    if option['name'] == 'validate_password_dictionary_file':
        option['values'][0]['type'] = 'fileedit'
        default = option['values'][0].get('default')
        if not default:
             option['values'][0]['default'] = '{configdir}/mysql_password_dictionary.txt'
    elif option['name'] == 'ft_stopword_file':
        option['values'][0]['type'] = 'fileedit'
        default = option['values'][0].get('default')
        if not default:
            option['values'][0]['default'] = '{configdir}/mysql_ft_stopword_file.txt'
    elif option['name'] == 'socket':
        option['values'][0]['type'] = 'filebrowse'
    elif option['name'] == 'ndb-recv-thread-cpu-mask':
        option['values'][0]['type'] = 'string'
    elif option['name'] == 'innodb_data_file_path':
        option['values'][0]['type'] = 'string'
    elif option['name'] in ('slow_query_log_file', 'general_log_file', 'log_bin_basename', 'relay_log_basename',
                            'relay_log_info_file', ''):
        option['values'][0]['type'] = 'filedownload'
    elif option['name'] in ('plugin_dir', ):
        for x in option['values']:
            x['default'] = x['default'].replace('BASEDIR/', '{basedir}/')


option_dict = {}
for option in raw_opts.ropts:
    option_dict[option['name']] = option


sys_vars = {}
stat_vars = {}

def find_var(varlist, option):
    for v in varlist:
        if v[0] == option:
            return v
    return None


print "Generating opts.py"
out=open("opts.py", "w+")
out.write("opts_list = [\n")
handled_options = set()
for section, section_items in options_layout.layout:
    out.write("( '%s', [\n" % section)
    for g, (group, group_items) in enumerate(section_items):
        out.write("\t( '%s', [\n" % group)
        for i, option in enumerate(group_items):
            if option in option_dict and not option in handled_options:
                handled_options.add(option)
                info = option_dict[option]
                hack_option(info)
                out.write("\t\t"+repr(info))
                if i < len(group_items)-1:
                    out.write(",\n")
        out.write("])")
        if g < len(section_items)-1:
            out.write(",\n")
    out.write("], %s" % str(variable_column_widths[section]))
    out.write("),\n")
out.write("]\n")

unhandled_options = set(option_dict.keys()) - handled_options
if unhandled_options:
    print "The following options were not handled:", "\n".join(sorted(list(unhandled_options)))

out.close()

def normalize_dict_keys(d):
    return d
    out = {}
    for k, v in d.items():
        out[k.replace("-","_")] = v
    return out

from variable_groups import variable_groups
variable_groups = normalize_dict_keys(dict(variable_groups))

system_var_list = []
for var in raw_vars.system_vars_list:
    current_var = (var['name'], var['description'], var['dynamic'], variable_groups.get(var['name'].replace("-","_"), []))
    system_var_list.append(current_var)


from status_groups import variable_groups
status_groups = normalize_dict_keys(dict(variable_groups))

status_var_list = []
for var in raw_vars.status_vars_list:
    current_var = (var['name'], var['description'], var['dynamic'], status_groups.get(var['name'].replace("-","_"), []))
    #status_var_list.append(tuple(current_var + [status_groups.get(var['name'].replace("-","_"), [])]))
    status_var_list.append(current_var)

print "Generating wb_admin_variable_list.py"
out=open("wb_admin_variable_list.py", "w+")

pp = pprint.PrettyPrinter(indent=2, stream=out)
out.write("system_variable_list = ")
pp.pprint(system_var_list)
out.write("\n\n\n")
out.write("status_variable_list = ")
pp.pprint(status_var_list)
out.close()

