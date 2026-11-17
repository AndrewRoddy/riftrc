"""Tests rift-indent's `>` / `<` (Normal and Visual), undo/redo and the
Esc / Alt+a Visual exit against Neovim set up like Andre's config
(`vnoremap > >gv`, `vnoremap < <gv`, shiftwidth 4, expandtab).

Every case is typed into Neovim (`nvim --embed`, over RPC, so undo steps
split as they do for a person; set up by visual_indent_nvim.lua) for the
expected text, cursor and mode, then in headless rift with the whole riftrc loaded (so
rift-clipboard etc. are in play), twice: once with each key as its own batch
followed by an idle wait (slow typing) and once with all keys in one batch
(fast typing). A probe plugin records the final state when the case ends with
`:`.

    python plugins/rift-indent/tests/visual_indent.py [--fuzz N] [--seed S] [--jobs J] [-k NAME]

Cases are the hand-written ones below plus N random ones (default 200).
Random cases only use what the plugin can match: selections are never made
upward (rift's anchor can't follow the shift, so Visual mode ends there; see
the README) and `o` / `gv` aren't used.
"""
import argparse, json, os, random, re, shutil, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor

here = os.path.dirname(os.path.abspath(__file__))
plugins = os.path.abspath(os.path.join(here, '..', '..', '..', '..'))  # .../rift/plugins


def w(p):
    return subprocess.run(['cygpath', '-w', p], capture_output=True, text=True).stdout.strip() \
        if shutil.which('cygpath') else p


TEXT = ['alpha', '    beta', '        gamma', '', 'delta', '  eps', '\tzeta',
        'eta', '    theta', 'iota', '      kappa', 'lambda']
# For --wide: no empty line, since rift's `w` skips empty lines and Neovim's
# stops on them.
TEXT_WIDE = [l for l in TEXT if l]

# Each case is a space-separated list of steps, one Neovim command each:
# Normal-mode `>>` is one step, Visual `>` another. `<` is written <lt>.
# All start at row 0, col 0 of TEXT.
HAND = [
    'V >', 'V > >', 'V j >', 'V j j > >', 'V j j > <lt>', 'V j j <lt> <lt>',
    'V j j > <Esc>', 'V j j > <A-a>', 'V j j > d', 'V j j > y',
    'V j j > <Esc> u', 'V j j > > <Esc> u', 'V j j > > <Esc> u u',
    'V j j > > <Esc> u u <C-r>', 'V j j > > <Esc> u u <C-r> <C-r>',
    # The reported bug: >> then << then unhighlight then >> again.
    '>> <lt><lt> V j >', 'V j > > <lt> <lt> <Esc> >>', 'V j > > <lt> <lt> <Esc> V j > >',
    'V j > <Esc> <lt><lt> V j >', '>> V j <lt> <Esc> >>', '>> V j <lt> <Esc> >> u u u',
    'V j > <Esc> >> <lt><lt> u u u',
    'j V j <lt> <Esc> j >> k V j > <Esc> u u u',
    'V j > > <lt> <lt> <Esc> >> j >> V j <lt> <Esc> u u u u <C-r> <C-r>',
    'V j > <A-a> V j > <A-a> V j <lt> <A-a> u u u u <C-r> <C-r> <C-r>',
    '>> u', '>> <lt><lt> u u', 'j j <lt><lt> <lt><lt> >>', '>> >> >> u u <C-r>',
    'v j >', 'v j > <lt>', '<C-v> j j >', '<C-v> j j > <lt>', 'j j j V j >',
    'V ' + 'j ' * 11 + '>', 'V ' + 'j ' * 11 + '> <Esc> u',
    'V j > <Esc> V >', 'V j > <A-a> V j <lt>', 'V j > <Esc> <Esc> >>',
    'x V j > <Esc> u u', 'V j > <Esc> x u u', 'V j > <Esc> u <C-r> u',
    'V j > <Esc> u u u u', 'V j > <Esc> <C-r> u <C-r>',
    # Block shifts over short and empty lines (Neovim pads a line that ends
    # right at the block's edge, leaves shorter and empty ones alone).
    'j j w <C-v> j j j >', 'j j w <C-v> j j j > <lt>', 'j j w <C-v> j j j j j >',
    'j w <C-v> j j >', 'j j j j w <C-v> j j >', 'j j j j j <C-v> j > >',
    'V <lt>', 'V <lt> <lt> <lt>', 'j j V <lt> > <lt>',
    'j l l V j <lt> <lt>', 'j j j $ V <lt>', 'j j l l v j <lt> <lt>',
    'x V <lt> <Esc> u', 'x <lt><lt> u', 'x <lt><lt> u u', 'x V <lt> <lt> <Esc> u u',
    'V j > j j <lt> > <Esc> k k', 'V j <lt> j > <Esc> j j k',
    # Reported: select 3 lines, `>`, Esc, then the same 3 lines again (Esc
    # leaves the cursor on the bottom one, so re-selecting goes upward).
    'V j j > <Esc> V k k <lt> > >', 'V j j > <Esc> V k k > > > >',
    'V j j > <Esc> <lt><lt> V k k > >', 'V j j > <Esc> <lt><lt> >> >>',
    'V j j > <Esc> k k V j j <lt> > > > >', 'j j j j V k k > > <lt>',
]
HAND = [(h, h.split()) for h in HAND]


def fuzz_case(rng, n, wide=False):
    """A random key sequence that stays where the plugin can match Neovim.
    `wide` adds moves within the line (w, 0). Not `$` (after it Neovim
    keeps the cursor at the end of the line, which plugins can't see in
    rift), `p` (rift's register isn't Neovim's) or `h` / `l` (rift's wrap
    to the next / previous line). `x` only where the line can't be empty:
    on an empty line rift's `x` deletes the line, Neovim's does nothing."""
    text = TEXT_WIDE if wide else TEXT
    nrows = len(text)
    xs = [0] * nrows  # `x`s typed on each row (undo ignored, so it errs safe)
    mode, row, anchor, undoing = 'n', 0, 0, False
    keys = []
    for _ in range(rng.randint(3, 14)):
        if mode == 'n':
            ops = ['j', 'j', 'k', '>>', '<<', 'u', 'u', '<C-r>', 'V', 'V',
                   'v', '<C-v>', '<Esc>', '<A-a>', 'x']
            if wide:
                ops += ['w', 'w', '0']
            op = rng.choice(ops)
            if op == 'x':
                r = 0 if undoing else row  # undoing → `gg0` comes first
                if xs[r] >= len(text[r].strip()):
                    op = 'j'
            if undoing and op not in ('u', '<C-r>'):
                keys.append('gg0')  # undo moves the cursor; put it somewhere known
                # (0 too: rift's gg goes to column 0, Neovim's keeps the column)
                row, undoing = 0, False
            if op == 'j':
                row = min(nrows - 1, row + 1)
            elif op == 'k':
                row = max(0, row - 1)
            elif op in ('u', '<C-r>'):
                undoing = True
            elif op == 'x':
                xs[row] += 1
            elif op in ('V', 'v', '<C-v>'):
                mode, anchor = 'v', row
            keys.append('<lt><lt>' if op == '<<' else op)
        else:
            ops = ['j', '>', '>', '<', '<', '<Esc>', '<A-a>', 'y']
            if row > anchor:
                ops.append('k')
            op = rng.choice(ops)
            if op == 'j':
                row = min(nrows - 1, row + 1)
            elif op == 'k':
                row -= 1
            elif op in ('<Esc>', '<A-a>'):
                mode = 'n'
            elif op == 'y':
                mode, row = 'n', min(anchor, row)
            keys.append('<lt>' if op == '<' else op)
    return ('fuzz%03d %s' % (n, ' '.join(keys)), keys)


class Nvim:
    """Minimal msgpack-RPC client for `nvim --embed`."""

    def __init__(self):
        import msgpack
        self.p = subprocess.Popen(['nvim', '--embed', '--headless', '--clean'],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        self.unpacker = msgpack.Unpacker(raw=False)
        self.packb = msgpack.packb
        self.msgid = 0

    def call(self, method, *params):
        self.msgid += 1
        self.p.stdin.write(self.packb([0, self.msgid, method, list(params)]))
        self.p.stdin.flush()
        while True:
            for msg in self.unpacker:
                if msg[0] == 1 and msg[1] == self.msgid:
                    if msg[2]:
                        raise RuntimeError(msg[2])
                    return msg[3]
            data = self.p.stdout.read1(65536)
            if not data:
                raise RuntimeError('nvim exited')
            self.unpacker.feed(data)

    def lua(self, code, *args):
        return self.call('nvim_exec_lua', code, list(args))

    def close(self):
        self.p.kill()


def nvim_results(cases, text):
    """Types each case into Neovim, one step at a time, as a person would."""
    nv = Nvim()
    nv.call('nvim_command', 'luafile ' + w(os.path.join(here, 'visual_indent_nvim.lua')))
    out = {}
    for c in cases:
        nv.lua('vi_reset(...)', text)
        for k in c['keys']:
            nv.call('nvim_input', k)
            nv.call('nvim_get_mode')  # returns once the keys have been handled
        out[c['name']] = nv.lua('return vi_state()')
        nv.call('nvim_input', '<Esc><Esc>')
        nv.call('nvim_get_mode')
    nv.close()
    return out


PROBE = r'''
-- Test probe: when the case ends with `:`, record the state rift was in.
rift.on("ModeChanged", function(ev)
  if ev.to ~= "command" then return end
  local row, col = rift.get_cursor()
  local f = io.open(os.getenv("RIFT_PROBE_OUT"), "w")
  f:write(rift.json.encode({ mode = ev.from:find("^visual") and "visual" or ev.from,
    row = row - 1, col = col, lines = rift.get_lines(1, -1) }))
  f:close()
end)
'''


def run_rift(sandbox, path, batches, out):
    script = os.path.join(os.path.dirname(out), os.path.basename(out) + '.replay')
    with open(script, 'w', encoding='utf-8', newline='\n') as f:
        f.write('open %s\nsize 30 100\nwait idle 300\n' % w(path))
        for b in batches:
            f.write('keys %s\nwait idle 300\n' % b)
        f.write('keys :\nwait idle 300\n')
    env = dict(os.environ, APPDATA=w(sandbox), XDG_CONFIG_HOME=sandbox, RIFT_PROBE_OUT=w(out))
    r = subprocess.run(['rift-replay', w(script)], capture_output=True, text=True, env=env)
    try:
        got = json.load(open(out, encoding='utf-8'))
    except (OSError, ValueError):
        return None, (r.stdout + r.stderr).strip()[-300:]
    lines = got['lines']
    if lines and lines[-1] == '':
        lines.pop()  # the file's final newline
    return got, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--fuzz', type=int, default=200)
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('--wide', action='store_true', help='random cases also move within lines')
    ap.add_argument('--jobs', type=int, default=8)
    ap.add_argument('-k', default=None, help='only cases whose name contains this')
    ap.add_argument('--speed', choices=['slow', 'fast', 'both'], default='both')
    ap.add_argument('-v', action='store_true', help='print every result')
    args = ap.parse_args()

    rng = random.Random(args.seed)
    # The hand-written cases are written for TEXT; --wide runs only random ones.
    cases = [] if args.wide else [{'name': n, 'keys': k} for n, k in HAND]
    cases += [dict(zip(('name', 'keys'), fuzz_case(rng, i, args.wide))) for i in range(args.fuzz)]
    if args.k:
        cases = [c for c in cases if args.k in c['name']]

    tmp = tempfile.mkdtemp()
    # Neovim: the expected results.
    text_lines = TEXT_WIDE if args.wide else TEXT
    want = nvim_results(cases, text_lines)

    # rift: a copy of the plugins directory plus the probe.
    sandbox = os.path.join(tmp, 'appdata')
    shutil.copytree(plugins, os.path.join(sandbox, 'rift', 'plugins'),
                    ignore=shutil.ignore_patterns('.git'))
    with open(os.path.join(sandbox, 'rift', 'plugins', 'zz_probe.lua'), 'w', newline='\n') as f:
        f.write(PROBE)
    text = os.path.join(tmp, 'case.txt')
    with open(text, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(text_lines) + '\n')

    speeds = ['slow', 'fast'] if args.speed == 'both' else [args.speed]
    jobs = []
    for i, c in enumerate(cases):
        for sp in speeds:
            batches = c['keys'] if sp == 'slow' else [''.join(c['keys'])]
            jobs.append((c, sp, batches, os.path.join(tmp, 'out%d_%s.json' % (i, sp))))

    def one(job):
        c, sp, batches, out = job
        return job, run_rift(sandbox, text, batches, out)

    fails = 0
    with ThreadPoolExecutor(args.jobs) as ex:
        for (c, sp, _, _), (got, err) in ex.map(one, jobs):
            exp = want.get(c['name'])
            e = (exp['lines'], exp['row'], exp['col'], exp['mode'])
            g = (got['lines'], got['row'], got['col'], got['mode']) if got else None
            if args.v:
                print('[%s] %s' % (sp, c['name']))
                print('   want %r' % (e,))
                print('   got  %r' % (g,))
            if g == e:
                continue
            fails += 1
            print('FAIL [%s] %s' % (sp, c['name']))
            if not got:
                print('   rift failed:', err)
                continue
            if g[0] != e[0]:
                print('   want lines', e[0])
                print('   got  lines', g[0])
            if g[1:] != e[1:]:
                print('   want cursor %d:%d %s, got %d:%d %s' % (e[1], e[2], e[3], g[1], g[2], g[3]))
    print('%d runs, %d failures' % (len(jobs), fails))
    shutil.rmtree(tmp, ignore_errors=True)
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
