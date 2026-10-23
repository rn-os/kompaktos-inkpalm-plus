#!/usr/bin/env python3
"""Diff two run_diag results.json files.  usage: compare.py OLD/results.json NEW/results.json [--props] [--all]
Exit 1 if any check regressed (PASS -> WARN/FAIL, WARN -> FAIL)."""
import json, sys

RANK = {'PASS': 0, 'SKIP': 1, 'WARN': 2, 'FAIL': 3, None: 1}
NOISY = ('ro.boottime.', 'ro.runtime.', 'sys.uptime', 'sys.boot.', 'init.svc_debug_pid.', 'debug.sf.', 'sys.sysctl.',
         'ro.boot.boottime', 'vendor.boot_', 'persist.sys.timezone', 'sys.lmk', 'dev.bootcomplete', 'sys.usb.state',
         'ro.serialno', 'ro.boot.serialno', 'net.', 'dhcp.', 'wifi.', 'gsm.', 'ril.', 'service.bootanim', 'bootreceiver.',
         'persist.sys.boot', 'sys.rescue', 'ro.build.date', 'ro.bootimage.build.date', 'ro.system.build.date', 'ro.vendor.build.date')

def load(p):
    return json.load(open(p))

def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    show_props = '--props' in sys.argv; show_all = '--all' in sys.argv
    if len(args) != 2:
        print(__doc__); return 2
    a, b = load(args[0]), load(args[1])
    print('A: %s  %s  %s' % (a['meta'].get('timestamp'), a['meta'].get('os'), a['meta'].get('fingerprint')))
    print('B: %s  %s  %s' % (b['meta'].get('timestamp'), b['meta'].get('os'), b['meta'].get('fingerprint')))
    print()
    regress = 0
    ids = sorted(set(a['checks']) | set(b['checks']))
    for i in ids:
        ca, cb = a['checks'].get(i), b['checks'].get(i)
        sa = ca['status'] if ca else None; sb = cb['status'] if cb else None
        if sa == sb and not show_all: continue
        if sa == sb: mark = '  '
        elif RANK[sb] > RANK[sa] and sb != 'SKIP': mark = '- '; regress += 1   # worse
        elif RANK[sb] < RANK[sa] and sa != 'SKIP': mark = '+ '                  # better
        else: mark = '~ '
        print('%s%-18s %-5s -> %-5s' % (mark, i, sa or '-', sb or '-'))
        if sa != sb or show_all:
            if cb: print('      B: %s' % cb['detail'][:200])
            if ca and sa != sb: print('      A: %s' % ca['detail'][:200])
    print()
    ma, mb = a.get('metrics', {}), b.get('metrics', {})
    for k in sorted(set(ma) | set(mb)):
        if ma.get(k) != mb.get(k):
            va, vb = ma.get(k), mb.get(k)
            extra = ''
            if isinstance(va, (int, float)) and isinstance(vb, (int, float)) and va:
                extra = '  (%+.0f%%)' % ((vb - va) * 100.0 / va)
            print('metric %-22s %s -> %s%s' % (k, va, vb, extra))
    if show_props:
        pa, pb = a.get('props', {}), b.get('props', {})
        print()
        for k in sorted(set(pa) | set(pb)):
            if k.startswith(NOISY): continue
            if pa.get(k) != pb.get(k):
                print('prop %-45s %r -> %r' % (k, pa.get(k), pb.get(k)))
    print('\n%d regression(s)' % regress)
    return 1 if regress else 0

sys.exit(main())
