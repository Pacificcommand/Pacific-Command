"""Close-up render for detail checks: python closeup.py NAME [x_center] -> /tmp/previews/NAME_close.png"""
import sys, os
from render import render
from warship import build_spec
import specs
name = sys.argv[1]; xc = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
scheme = sys.argv[3] if len(sys.argv) > 3 else None
M = build_spec(specs.SPECS[name], scheme)
im = render(M, (-0.5, -0.45, 0.74), (xc, 8, 0), 90, 50, 12.0, (-0.45, 0.8, -0.38), ('#06213f', '#0f4d73'), ss=1, foam=False)
os.makedirs('/tmp/previews', exist_ok=True)
out = '/tmp/previews/%s_close%s.png' % (name, '_' + scheme if scheme else '')
im.save(out); print(out, im.size)
