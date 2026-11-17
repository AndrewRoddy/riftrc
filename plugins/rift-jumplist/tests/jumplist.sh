#!/usr/bin/env bash
# Types keys into headless rift (rift-replay) with only rift-jumplist loaded
# and checks where <C-o> / <C-i> leave the cursor. Expected positions are
# Neovim's for the same keys (rows and columns 0-indexed).
# Usage: bash tests/jumplist.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
plugin="$here/../rift-jumplist.lua"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/app/rift/plugins"; cp "$plugin" "$tmp/app/rift/plugins/"
win() { cygpath -w "$1" 2>/dev/null || echo "$1"; }
seq 1 50 | sed 's/^/line /' > "$tmp/a.txt"
printf 'other1\nother2\n' > "$tmp/b.txt"
fails=0
# case NAME "KEYS..." "ROW COL"  (each space-separated key batch is typed after a pause)
case_() {
  local s="$tmp/c.replay"
  printf 'open %s\nsize 20 80\nwait idle 200\n' "$(win "$tmp/a.txt")" > "$s"
  for k in $2; do printf 'keys %s\nwait idle 150\n' "$k" >> "$s"; done
  printf 'assert cursor %s\n' "$3" >> "$s"
  [ -n "${4:-}" ] && printf 'assert line 0 "%s"\n' "$4" >> "$s"
  if APPDATA="$(win "$tmp/app")" rift-replay "$(win "$s")" >/dev/null 2>"$tmp/err"; then
    echo "ok   $1"
  else
    echo "FAIL $1: $(cat "$tmp/err")"; fails=$((fails + 1))
  fi
}
B="$(cygpath -m "$tmp/b.txt" 2>/dev/null || echo "$tmp/b.txt")"
case_ "G then back"            'G <C-o>'                            '0 0'
case_ "back and forward"       'G <C-o> <C-i>'                      '49 0'
case_ "Tab is <C-i>"           'G <C-o> <Tab>'                      '49 0'
case_ "two back"               '10Gj 30Gj Gk <C-o> <C-o>'           '10 0'
case_ "past the oldest"        '10Gj <C-o> <C-o> <C-o>'             '0 0'
case_ "back back fwd fwd"      '10Gj 30Gj <C-o> <C-o> <C-i> <C-i>'  '30 0'
case_ "j is not a jump"        'j j j <C-o>'                        '3 0'
case_ "search is a jump"       '/line<Space>40<CR> <C-o>'           '0 0'
case_ "search, back, forward"  '/line<Space>40<CR> <C-o> <C-i>'     '39 0'
case_ "column kept"            'jjlll G <C-o>'                      '2 3'
case_ "new jump mid-list"      '10Gj 30Gj <C-o> 40Gj <C-o>'         '10 0'
case_ "back, fwd, back"        'G <C-o> <C-i> <C-o>'                '0 0'
case_ "forward at the newest"  'G <C-i>'                            '49 0'
case_ "insert moves ignored"   'GoX<CR>Y<CR>Z<Esc> <C-o>'           '0 0'
case_ "nothing to go back to"  '<C-o>'                              '0 0'
case_ "other buffer, back"     "5G :e<Space>$B<CR> <C-o>"           '4 0' 'line 1'
case_ "other buffer, forward"  "5G :e<Space>$B<CR> <C-o> <C-i>"     '0 0' 'other1'
echo "$fails failed"
exit $((fails > 0))
