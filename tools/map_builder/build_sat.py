"""The operations map as a satellite view: assets/map/sat.jpg and assets/map/clouds.png.

  SRC_DIR=<folder with ne_10m_land.json> BATHY_DIR=<folder with ne_10m_bathymetry_*.json>
  SAT_DIR=<folder with 2_no_clouds_4k.jpg, elev_bump_4k.jpg, water_4k.png, fair_clouds_4k.png>
  python3 build_sat.py [sat] [clouds]

Sources (all public domain): Natural Earth 1:10m land and bathymetry (naturalearthdata.com, via
github.com/nvkelso/natural-earth-vector); NASA Blue Marble colour, elevation and clouds at 4K
(via github.com/turban/webgl-earth). The ocean colour comes from the real depths (deep navy over
the trenches, lighter over the shelves, turquoise reef water round tropical coasts and atolls);
the land is Blue Marble colour inside the detailed Natural Earth coastline, hill-shaded from the
elevation map with fine relief added. Same window and scale as the chart (ops.gd CHART).
"""
import json, os, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

Image.MAX_IMAGE_PIXELS = None
LON0, LON1, LAT0, LAT1 = 60.0, 252.0, 62.0, -60.0
PX = 24.0
W, H = int((LON1 - LON0) * PX), int((LAT0 - LAT1) * PX)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'assets', 'map')
SRC = os.environ.get('SRC_DIR', '.')
BATHY = os.environ.get('BATHY_DIR', '.')
SAT = os.environ.get('SAT_DIR', '.')
DEPTHS = [('L', 0), ('K', 200), ('J', 1000), ('I', 2000), ('H', 3000), ('G', 4000), ('F', 5000),
          ('E', 6000), ('D', 7000), ('C', 8000), ('B', 9000)]


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


def raster(path, ss=1):
    """Fill every polygon of a GeoJSON file into a W x H mask (antialiased with ss > 1).
    Drawn on a whole-globe canvas in plain -180..180 longitudes (Natural Earth already splits
    its polygons at the date line), then the chart window is cut out across the wrap."""
    G = json.load(open(path))
    gw, gh = int(360 * PX * ss), int((LAT0 - LAT1) * PX * ss)
    img = Image.new('L', (gw, gh), 0)
    d = ImageDraw.Draw(img)

    def ring(r):
        return [((lon + 180.0) * PX * ss, (LAT0 - lat) * PX * ss) for lon, lat in r]

    for f in G['features']:
        g = f['geometry']
        if g is None:
            continue
        polys = [g['coordinates']] if g['type'] == 'Polygon' else g['coordinates']
        for poly in polys:
            outer = ring(poly[0])
            ys = [p[1] for p in outer]
            if max(ys) < -50 or min(ys) > gh + 50:
                continue
            if len(outer) >= 3:
                d.polygon(outer, fill=255)
            for hole in poly[1:]:
                hh = ring(hole)
                if len(hh) >= 3:
                    d.polygon(hh, fill=0)
    a = np.asarray(img)
    a = np.roll(a, -int(round((LON0 + 180.0) * PX * ss)), axis=1)[:, :W * ss]
    if ss > 1:
        a = np.asarray(Image.fromarray(a).resize((W, H), Image.LANCZOS))
    return a.astype(np.float32) / 255.0


def sample_globe(img_arr, order=3):
    """Sample an equirectangular whole-globe array (H, W[, C]) at every chart pixel."""
    gh, gw = img_arr.shape[:2]
    ppd = gw / 360.0
    lon = LON0 + (np.arange(W) + 0.5) / PX
    lat = LAT0 - (np.arange(H) + 0.5) / PX
    gx = ((lon + 180.0) % 360.0) * ppd - 0.5
    gy = (90.0 - lat) * ppd - 0.5
    X, Y = np.meshgrid(gx, gy)
    if img_arr.ndim == 2:
        return ndimage.map_coordinates(img_arr.astype(np.float32), [Y, X], order=order, mode='wrap')
    return np.stack([ndimage.map_coordinates(img_arr[..., c].astype(np.float32), [Y, X], order=order, mode='wrap')
                     for c in range(img_arr.shape[2])], -1)


def sat():
    print('land'); land = raster(os.path.join(SRC, 'ne_10m_land.json'), 2)
    isl = land > 0.5
    dsea = ndimage.distance_transform_edt(~isl)          # px from the coast, at sea
    dland = ndimage.distance_transform_edt(isl)
    yy = np.arange(H)[:, None]
    lat = LAT0 - (yy + 0.5) / PX
    tropic = np.clip((32.0 - np.abs(lat)) / 10.0, 0, 1)    # coral seas
    # ---- depth from the Natural Earth bathymetry layers (deepest layer that covers a pixel)
    depth = np.zeros((H, W), np.float32)
    for code, dm in DEPTHS[1:]:
        p = os.path.join(BATHY, 'ne_10m_bathymetry_%s_%d.json' % (code, dm))
        print('depth', dm)
        m = raster(p, 1) > 0.5
        depth[m] = dm
    # the shelf (under 200 m) has no finer layers: let it deepen away from the shore
    shelf = depth < 1.0
    depth[shelf] = np.minimum(18.0 + dsea[shelf] * 9.0, 185.0)
    # soften the steps between layers, keep the coast shallow
    depth = ndimage.gaussian_filter(depth, 2.5)
    depth = np.minimum(depth, dsea * 320.0)
    # ---- ocean colour by depth
    stops = [(0, (0.40, 0.78, 0.76)), (25, (0.22, 0.60, 0.68)), (80, (0.15, 0.48, 0.60)), (180, (0.10, 0.38, 0.55)), (400, (0.07, 0.31, 0.50)),
             (1500, (0.045, 0.24, 0.42)), (3500, (0.035, 0.19, 0.36)), (5500, (0.028, 0.155, 0.31)), (8000, (0.02, 0.11, 0.24))]
    ds = np.array([s[0] for s in stops], np.float32)
    cs = np.array([s[1] for s in stops], np.float32)
    sea = np.stack([np.interp(depth, ds, cs[:, c]) for c in range(3)], -1)
    # reef water: turquoise round tropical coasts and atolls; temperate shelves stay greener and greyer
    reef = np.clip(1.0 - dsea / 2.8, 0, 1) ** 1.2 * tropic
    sea = sea * (1 - reef[..., None] * 0.85) + np.array([0.45, 0.85, 0.82], np.float32) * reef[..., None] * 0.85
    temperate = (1 - tropic)[..., None] * np.clip(1.0 - depth / 300.0, 0, 1)[..., None]
    sea = sea * (1 - temperate * 0.35) + np.array([0.20, 0.42, 0.45], np.float32) * temperate * 0.35
    # the sea surface: broad swells of light and fine texture
    broad = fbm(H, W, [400, 200, 100], 11)
    fine = fbm(H, W, [3, 7], 12)
    sea *= (0.93 + 0.10 * broad[..., None]) * (0.985 + 0.03 * fine[..., None])
    # ---- land: Blue Marble colour, spread over the detailed coastline, hill-shaded
    print('blue marble')
    bm = np.asarray(Image.open(os.path.join(SAT, '2_no_clouds_4k.jpg')).convert('RGB')).astype(np.float32) / 255.0
    water = np.asarray(Image.open(os.path.join(SAT, 'water_4k.png')).convert('L')) > 128
    # paint the sea in the Blue Marble with the nearest land colour, so coasts never pick up blue
    idx = ndimage.distance_transform_edt(water, return_distances=False, return_indices=True)
    bm_land = bm[idx[0], idx[1]]
    col = np.clip(sample_globe(bm_land, 1), 0, 1)
    # lift the dark Blue Marble greens towards how it looks from orbit on a clear day
    col = np.clip((col - 0.02) * 1.28, 0, 1) ** 0.92
    elev = np.asarray(Image.open(os.path.join(SAT, 'elev_bump_4k.jpg')).convert('L')).astype(np.float32) / 255.0
    el = sample_globe(elev, 3)
    detail = fbm(H, W, [6, 12, 24], 13)
    rough = np.clip(el * 3.0, 0, 1)
    hgt = el * 22.0 + (detail - 0.5) * (0.3 + 2.2 * rough)
    gy, gx = np.gradient(ndimage.gaussian_filter(hgt, 1.2))
    nrm = np.stack([-gx, -gy, np.ones_like(gx)], -1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    sun = np.array([-0.55, -0.55, 0.63]); sun /= np.linalg.norm(sun)
    shade = np.clip((nrm @ sun) / sun[2], 0.72, 1.22)
    col = col * shade[..., None]
    # a pale beach line on tropical shores
    beach = np.clip(1.0 - dland / 1.6, 0, 1) * tropic * 0.45
    col = col * (1 - beach[..., None]) + np.array([0.82, 0.78, 0.62], np.float32) * beach[..., None]
    a = land[..., None]
    img = sea * (1 - a) + col * a
    # a touch of atmosphere: haze that thickens slightly towards the poles
    haze = np.clip((np.abs(lat) - 25.0) / 40.0, 0, 1)[..., None] * 0.12
    img = img * (1 - haze) + np.array([0.70, 0.78, 0.86], np.float32) * haze
    out = (np.clip(img, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(out).save(os.path.join(OUT, 'sat.jpg'), quality=90, subsampling=0)
    print('sat', W, H)


def clouds():
    """The whole globe's band of cloud (wraps east-west), white with the cloud as alpha."""
    # the cloud is in the image's transparency (a palette PNG with a transparency table)
    c = np.asarray(Image.open(os.path.join(SAT, 'fair_clouds_4k.png')).convert('RGBA'))[..., 3].astype(np.float32) / 255.0
    gh, gw = c.shape
    ppd = gw / 360.0
    y0, y1 = int((90 - LAT0) * ppd), int((90 - LAT1) * ppd)
    band = c[y0:y1]
    # shift so the band starts at LON0 like the map
    band = np.roll(band, -int((LON0 + 180.0) * ppd), axis=1)
    a = np.clip((band - 0.04) * 1.1, 0, 1)
    rgba = np.zeros(band.shape + (2,), np.uint8)
    rgba[..., 0] = 255
    rgba[..., 1] = (a * 255).astype(np.uint8)
    Image.fromarray(rgba, 'LA').save(os.path.join(OUT, 'clouds.png'), optimize=True)
    print('clouds', band.shape)


if __name__ == '__main__':
    want = sys.argv[1:] or ['sat', 'clouds']
    for f in want:
        globals()[f]()
