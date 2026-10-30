"""Preview renders for checking models against the reference photos:
python preview.py cleveland iowa ...   -> /tmp/previews/<name>.png (top-down + oblique side by side).
With no names, renders every class in SPECS."""
import os, sys
import numpy as np
from PIL import Image
from render import render
from warship import build_spec
import specs

OUT = '/tmp/previews'

def preview(name, M, L):
    os.makedirs(OUT, exist_ok=True)
    ppm = max(2.0, min(6.0, 900.0 / L))
    top = render(M, (0, -1, 0.001), (0, 0, 0), L + 30, max(40, L * 0.35), ppm, (-0.45, 0.8, -0.38), ('#06213f', '#0f4d73'), ss=1, foam=False)
    obl = render(M, (-0.55, -0.6, 0.6), (0, 4, 0), L + 30, max(50, L * 0.4), ppm, (-0.45, 0.8, -0.38), ('#06213f', '#0f4d73'), ss=1, foam=False)
    w = max(top.width, obl.width)
    im = Image.new('RGB', (w, top.height + obl.height + 6), (20, 20, 20))
    im.paste(top, (0, 0)); im.paste(obl, (0, top.height + 6))
    im.save(os.path.join(OUT, name + '.png'))
    print('preview', name, im.size)

if __name__ == '__main__':
    names = sys.argv[1:] or list(specs.SPECS)
    for n in names:
        spec = specs.SPECS[n]
        preview(n, build_spec(spec), spec['L'])
