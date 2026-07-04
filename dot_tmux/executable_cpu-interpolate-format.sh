#!/usr/bin/env bash
# The tmux-cpu plugin only interpolates status-left and status-right, replacing
# placeholders like #{cpu_percentage} with #(.../cpu_percentage.sh) command
# substitutions. The top status row lives in status-format[0], which the plugin
# never visits, so its CPU placeholders would render empty. Apply the same
# substitution here. Run after the plugin manager has loaded tmux-cpu.
dir="$HOME/.tmux/plugins/tmux-cpu/scripts"

v="$(tmux show -gv 'status-format[0]')"
for m in percentage icon fg_color bg_color; do
  v="${v//#{cpu_$m\}/#($dir/cpu_$m.sh)}"
done
tmux set -g 'status-format[0]' "$v"
