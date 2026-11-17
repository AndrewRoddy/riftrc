#!/usr/bin/env bash
# Types keys into headless rift (rift-replay) with only rift-insert-nonblank
# loaded and checks the resulting line. Expected text is Neovim's, except
# Visual `I`, which is left to rift.
# Usage: bash tests/insert_nonblank.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/app/rift/plugins"; cp "$here/../rift-insert-nonblank.lua" "$tmp/app/rift/plugins/"
win() { cygpath -w "$1" 2>/dev/null || echo "$1"; }
printf '    foo bar\n    \nx\n\tbaz\n' > "$tmp/a.txt"
fails=0
case_() { # NAME KEYS ROW EXPECTED-LINE
  printf 'open %s\nsize 20 80\nwait idle 200\nkeys %s\nwait idle 300\nassert line %s "%s"\n' \
    "$(win "$tmp/a.txt")" "$2" "$3" "$4" > "$tmp/c.replay"
  if APPDATA="$(win "$tmp/app")" rift-replay "$(win "$tmp/c.replay")" >/dev/null 2>"$tmp/err"; then
    echo "ok   $1"
  else
    echo "FAIL $1: $(cat "$tmp/err")"; fails=$((fails + 1))
  fi
}
case_ "I from column 0"       '0IX<Esc>'        0 '    Xfoo bar'
case_ "I from the line end"   '$IX<Esc>'        0 '    Xfoo bar'
case_ "gI is column 0"        '$gIX<Esc>'       0 'X    foo bar'
case_ "whitespace-only line"  'jIX<Esc>'        1 '    X'
case_ "no indent"             'jjIX<Esc>'       2 'Xx'
case_ "tab indent"            'jjjIX<Esc>'      3 '	Xbaz'
case_ "undo"                  '$IX<Esc>u'       0 '    foo bar'
case_ "i unchanged"           '0iX<Esc>'        0 'X    foo bar'
case_ "Visual I left to rift" 'VjIX<Esc>'       0 'X    foo bar'
case_ "typed fast"            'IX<Esc>jIY<Esc>' 1 '    Y'
echo "$fails failed"
exit $((fails > 0))
