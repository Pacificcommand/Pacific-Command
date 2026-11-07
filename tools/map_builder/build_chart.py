"""The operations map's chart, the table it lies on, and paper for the clipboard and cards.

  SRC_DIR=<folder with ne_10m_land.json> python3 build_chart.py

Writes assets/map/chart.png (the whole theatre at PX_PER_DEG, an aged printed chart: sea, shallow
band and soundings line round every coast, buff land with an ink coastline, paper grain and stains),
assets/map/wood.png (the table top, 2048x1152, stretched) and assets/map/paper.png (tileable paper grain).
The game draws the chart between LON0..LON1 and LAT1..LAT0 (scripts/ops.gd CHART_*).
"""
import json, math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

LON0, LON1, LAT0, LAT1 = 60.0, 252.0, 62.0, -60.0
PX = 24.0                       # pixels per degree
W, H = int((LON1 - LON0) * PX), int((LAT0 - LAT1) * PX)
SS = 2                          # supersampling for the coastline
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'assets', 'map')
rng = np.random.default_rng(7)


def fbm(h, w, scales, seed):
    r = np.random.default_rng(seed)
    out = np.zeros((h, w), np.float32)
    amp = 1.0
    for s in scales:
        small = r.random((max(2, h // s), max(2, w // s))).astype(np.float32)
        out += amp * np.array(Image.fromarray(small).resize((w, h), Image.BICUBIC))
        amp *= 0.5
    out -= out.min()
    return out / max(1e-6, out.max())


def land_mask():
    G = json.load(open(os.path.join(os.environ.get('SRC_DIR', '.'), 'ne_10m_land.json')))
    img = Image.new('L', (W * SS, H * SS), 0)
    d = ImageDraw.Draw(img)

    def ring(r):
        lons = [p[0] for p in r]
        wrap = max(lons) > 170 and min(lons) < -170
        pts = []
        for lon, lat in r:
            if lon < 0 and (wrap or lon < -30):
                lon += 360
            pts.append(((lon - LON0) * PX * SS, (LAT0 - lat) * PX * SS))
        return pts

    for f in G['features']:
        g = f['geometry']
        polys = [g['coordinates']] if g['type'] == 'Polygon' else g['coordinates']
        for poly in polys:
            outer = ring(poly[0])
            xs = [p[0] for p in outer]; ys = [p[1] for p in outer]
            if max(xs) < -50 or min(xs) > W * SS + 50 or max(ys) < -50 or min(ys) > H * SS + 50:
                continue
            if len(outer) >= 3:
                d.polygon(outer, fill=255)
            for hole in poly[1:]:
                h = ring(hole)
                if len(h) >= 3:
                    d.polygon(h, fill=0)
    small = img.resize((W, H), Image.LANCZOS)
    return np.asarray(small).astype(np.float32) / 255.0


def chart():
    m = land_mask()
    land = m > 0.5
    dist_sea = ndimage.distance_transform_edt(~land)       # px from the coast, at sea
    dist_land = ndimage.distance_transform_edt(land)
    grain = fbm(H, W, [3, 7], 1)
    blot = fbm(H, W, [180, 90, 45], 2)
    fine = fbm(H, W, [2], 3)
    sea = np.array([0.66, 0.74, 0.71], np.float32)
    shallow = np.array([0.73, 0.80, 0.76], np.float32)
    buff = np.array([0.86, 0.80, 0.63], np.float32)
    ink = np.array([0.29, 0.23, 0.16], np.float32)
    img = np.empty((H, W, 3), np.float32)
    # the sea: a lighter band along every coast, fading out
    # how much land is about: big coasts get the full shallows band and soundings line,
    # a lone atoll only a faint ring
    big = np.clip(ndimage.gaussian_filter(m, 18.0) * 14.0, 0, 1)
    band = 5.0 + 9.0 * big
    t = np.clip(1.0 - dist_sea / band, 0, 1) ** 1.5 * (0.45 + 0.55 * big)
    img[:] = sea
    img = img * (1 - t[..., None]) + shallow * t[..., None]
    # the soundings line: a fine dotted line a little off the coast
    line = (np.abs(dist_sea - 9.0) < 0.6) & (fine > 0.45) & (big > 0.5)
    img[line] = img[line] * 0.84
    # land: buff, a touch darker just inside the coast
    edge_in = np.clip(1.0 - dist_land / 5.0, 0, 1)
    lc = buff[None, None, :] * (1.0 - 0.08 * edge_in[..., None]) * (0.95 + 0.08 * blot[..., None])
    a = m[..., None]
    img = img * (1 - a) + lc * a
    # the coastline in ink (from the antialiased mask's edge)
    coast = np.clip(1.0 - np.abs(m - 0.5) * 2.2, 0, 1) ** 0.8
    img = img * (1 - coast[..., None] * 0.85) + ink * coast[..., None] * 0.85
    # print and age: paper grain, broad stains, a darker rim
    img *= (0.94 + 0.08 * grain[..., None])
    img *= (0.93 + 0.09 * blot[..., None])
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, 'chart.png'), optimize=True)
    print('chart', W, H)


def wood():
    """A table top of long planks, 2048x1152, stretched over the screen (no tiling)."""
    w, h = 2048, 1152
    r = np.random.default_rng(11)
    col = np.zeros((h, w, 3), np.float32)
    base = np.array([0.40, 0.25, 0.13], np.float32)
    dark = np.array([0.17, 0.10, 0.05], np.float32)
    y = 0
    k = 0
    while y < h:
        ph = int(r.integers(150, 230))
        y1 = min(h, y + ph)
        n = y1 - y
        # long grain: noise squashed along x, then gentle waves
        g1 = np.array(Image.fromarray(r.random((max(2, n // 3), 40)).astype(np.float32)).resize((w, n), Image.BICUBIC))
        g2 = np.array(Image.fromarray(r.random((max(2, n // 1), 160)).astype(np.float32)).resize((w, n), Image.BICUBIC))
        yy, xx = np.mgrid[0:n, 0:w].astype(np.float32)
        warp = np.array(Image.fromarray(r.random((4, 12)).astype(np.float32)).resize((w, n), Image.BICUBIC)) * 30
        cx = r.uniform(-0.5, 1.5) * w
        rings = np.sin((yy + warp + 0.0006 * (xx - cx) ** 2 * r.uniform(0.2, 1.0)) / r.uniform(5, 9))
        v = 0.62 + 0.10 * rings + 0.30 * (g1 - 0.5) + 0.12 * (g2 - 0.5)
        v *= r.uniform(0.86, 1.08)
        c = dark + (base - dark) * np.clip(v, 0, 1.3)[..., None]
        # seam shadow along the top of each plank, a highlight just below
        c[:2] *= 0.45
        c[2:4] *= 1.08
        col[y:y1] = c
        # butt joints
        for _ in range(int(r.integers(0, 2)) + (1 if k % 2 else 0)):
            jx = int(r.integers(200, w - 200))
            col[y:y1, jx:jx + 2] *= 0.5
        y = y1
        k += 1
    Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, 'wood.png'), optimize=True)
    print('wood')


def paper():
    n = 512
    g = fbm(n, n, [2, 5, 40], 9)
    base = np.array([0.95, 0.92, 0.84], np.float32)
    col = base * (0.94 + 0.07 * g[..., None])
    a = col
    b = np.roll(np.roll(a, n // 2, 0), n // 2, 1)
    yy, xx = np.mgrid[0:n, 0:n]
    w1 = np.clip(np.minimum(np.minimum(xx, n - 1 - xx), np.minimum(yy, n - 1 - yy)) / (n / 2) * 3.0, 0, 1)[..., None]
    out = a * w1 + b * (1 - w1)
    Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, 'paper.png'), optimize=True)
    print('paper')


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    import sys
    want = sys.argv[1:] or ['chart', 'wood', 'paper']
    for f in want:
        globals()[f]()
