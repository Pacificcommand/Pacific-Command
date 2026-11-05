"""Bake every battle island into a map the game draws: assets/islands/<id>.png + <id>.json.

The PNG (N x N, north up, x east, z south) packs four channels:
  R  signed distance to the coast: 0.5 = shoreline, +/- SD metres at 1 / 0 (land positive). The
     game filters it, so the coast is drawn smooth well below the pixel size.
  G  height, log encoded (see enc_h): sea bed -80 m ... 0 ... 3000 m peaks
  B  vegetation cover 0..1 (palm groves, jungle, scrub, cane fields: the json says which)
  A  cleared ground: 1 airfield (coral or concrete), 0.5 town / camp
The json has the window (centre lon/lat, half size, pixel size), the island kind, the landing beach,
the approach from the sea, shore battery sites, the supply dump and a spot for the defenders' boats,
all in metres relative to the window centre (x east, z south).

  python3 bake.py [id ...]        (all islands when none given); previews in /tmp/islands/
"""
import json, math, os, sys
import numpy as np
import cv2
from scipy import ndimage
from PIL import Image
from islands import ISLANDS

N = 1024
SD = 200.0               # metres of signed distance across the R channel's range
H_MAX = 3000.0
D_MAX = 80.0
OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'assets', 'islands')
PREV = '/tmp/islands'


def enc_h(h):
    """Height (m) -> 0..255: 64 is sea level; log steps so 0-5 m atolls and 2,700 m peaks both fit."""
    h = np.asarray(h, dtype=np.float64)
    up = 64.0 + 191.0 * np.log1p(np.clip(h, 0, None) / 2.0) / math.log1p(H_MAX / 2.0)
    dn = 64.0 - 64.0 * np.log1p(np.clip(-h, 0, None) / 2.0) / math.log1p(D_MAX / 2.0)
    return np.where(h >= 0, up, dn)


DEM_DIR = os.environ.get('DEM_DIR', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'dem'))


def sample_dem(tiles, X, Z, lon0, lat0):
    """Heights (m) from USGS 1 arc-second GeoTIFF tiles at the window's points (NaN where none)."""
    lon = lon0 + X / (111320.0 * math.cos(math.radians(lat0)))
    lat = lat0 - Z / 111320.0
    out = np.full(X.shape, np.nan, np.float32)
    for t in tiles:
        im = Image.open(os.path.join(DEM_DIR, t + '.tif'))
        a = np.array(im, dtype=np.float32)
        tp = im.tag_v2[33922]; sc = im.tag_v2[33550]
        col = (lon - tp[3]) / sc[0] - 0.5
        row = (tp[4] - lat) / sc[1] - 0.5
        inb = (col >= 0) & (row >= 0) & (col < a.shape[1] - 1) & (row < a.shape[0] - 1)
        c0 = np.clip(np.floor(col).astype(int), 0, a.shape[1] - 2); r0 = np.clip(np.floor(row).astype(int), 0, a.shape[0] - 2)
        fc = col - c0; fr = row - r0
        v = (a[r0, c0] * (1 - fc) * (1 - fr) + a[r0, c0 + 1] * fc * (1 - fr) + a[r0 + 1, c0] * (1 - fc) * fr + a[r0 + 1, c0 + 1] * fc * fr)
        bad = (a[r0, c0] < -1000) | (a[r0, c0 + 1] < -1000) | (a[r0 + 1, c0] < -1000) | (a[r0 + 1, c0 + 1] < -1000)
        out = np.where(inb & ~bad, v, out)
    return out


def to_local(lon, lat, lon0, lat0):
    dlon = ((np.asarray(lon) - lon0 + 180.0) % 360.0) - 180.0
    x = dlon * 111320.0 * math.cos(math.radians(lat0))
    z = -(np.asarray(lat) - lat0) * 111320.0
    return x, z


def fbm(n, seed, octaves=6, base=4, gain=0.5):
    """Smooth fractal noise -1..1 on an n x n grid."""
    rng = np.random.default_rng(seed)
    out = np.zeros((n, n), np.float32)
    amp, tot, f = 1.0, 0.0, base
    for _ in range(octaves):
        g = rng.standard_normal((f + 3, f + 3)).astype(np.float32)
        up = cv2.resize(g, (n + int(n * 3 / f), n + int(n * 3 / f)), interpolation=cv2.INTER_CUBIC)[:n, :n]
        out += amp * up
        tot += amp
        amp *= gain
        f *= 2
    out /= tot
    return np.clip(out / (np.abs(out).max() + 1e-6), -1, 1)


def chaikin(pts, it):
    for _ in range(it):
        p = np.asarray(pts)
        q = p * 0.75 + np.roll(p, -1, axis=0) * 0.25
        r = p * 0.25 + np.roll(p, -1, axis=0) * 0.75
        pts = np.empty((len(p) * 2, 2))
        pts[0::2] = q
        pts[1::2] = r
    return pts


def bake(iid, I):
    lon0, lat0 = I['center']
    half = float(I['half'])
    px = 2.0 * half / N
    coast = json.load(open(os.path.join(os.path.dirname(__file__), 'coast', iid + '.json')))
    # land mask at 2x for an accurate signed distance
    S = 2
    M = N * S
    land = np.zeros((M, M), np.uint8)
    for ring in coast['rings']:
        r = np.asarray(ring, dtype=np.float64)
        if len(r) < 3:
            continue
        x, z = to_local(r[:, 0], r[:, 1], lon0, lat0)
        pts = np.stack([x, z], 1)
        if I['src'] == 'hand':
            pts = chaikin(pts, 3)
        ij = ((pts + half) / (px / S) * 16.0).round().astype(np.int32)     # 4 bits of sub-pixel precision
        cv2.fillPoly(land, [ij.reshape(-1, 1, 2)], 1, lineType=cv2.LINE_AA, shift=4)
    land = (land > 0).astype(np.uint8)
    din = ndimage.distance_transform_edt(land) * (px / S)
    dout = ndimage.distance_transform_edt(1 - land) * (px / S)
    sdf2 = np.where(land > 0, din - 0.5 * px / S, -(dout - 0.5 * px / S))
    sdf = cv2.resize(sdf2.astype(np.float32), (N, N), interpolation=cv2.INTER_AREA)
    seed = abs(hash(iid)) % 100000
    n1 = fbm(N, seed + 1, 7, 6)
    n2 = fbm(N, seed + 2, 5, 24)
    ii, jj = np.meshgrid(np.arange(N), np.arange(N))         # ii = column (x), jj = row (z)
    X = -half + (ii + 0.5) * px
    Z = -half + (jj + 0.5) * px
    # where the window cuts through land, bring the land down to a ragged shore a little inside the
    # edge, so there is no cliff where the map ends
    bd = np.minimum(half - np.abs(X), half - np.abs(Z))
    margin = 0.05 * 2.0 * half
    sdf = np.minimum(sdf, (bd - margin) * 1.0 + n2 * 0.025 * 2.0 * half)
    d = sdf                                                   # metres inland (+) / offshore (-)

    kind = I['kind']
    base, rise = float(I['base']), float(I['rise'])
    dl = np.clip(d, 0, None)
    if kind == 'atoll':
        h = 0.9 + (base - 0.9) * np.clip(dl / rise, 0, 1) ** 0.7 + 0.5 * n2 * np.clip(dl / 60.0, 0, 1)
    elif kind in ('coral', 'ash'):
        # raised limestone (and Iwo's ash terraces): a steep rise from the shore to a plateau
        h = base * (1.0 - np.exp(-dl / (rise * 0.35))) + 0.06 * base * n1
    else:
        h = base * (1.0 - np.exp(-dl / (rise * 0.3))) + dl * 0.012 * np.clip(rise / 1000.0, 0.3, 3.0)
    coastfade = np.clip(dl / 160.0, 0, 1)
    peaks = []
    for p in I['peaks']:
        plon, plat, ph, pr = p[:4]
        opt = p[4] if len(p) > 4 else {}
        px_, pz_ = to_local(plon, plat, lon0, lat0)
        # a summit listed in the water (coordinates a little off): move it to the highest-inland
        # ground within 2.5 km, so the mountain stands on the island
        i0 = int(np.clip((px_ + half) / px, 0, N - 1)); j0 = int(np.clip((pz_ + half) / px, 0, N - 1))
        inside = abs(px_) < half and abs(pz_) < half
        near_edge = min(half - abs(px_), half - abs(pz_)) < 2500.0
        if inside and not near_edge and d[j0, i0] < 30.0 and not opt.get('cliff'):
            rr = int(float(opt.get('snap', 2500.0)) / px)
            ja, jb, ia, ib = max(0, j0 - rr), min(N, j0 + rr + 1), max(0, i0 - rr), min(N, i0 + rr + 1)
            sub = d[ja:jb, ia:ib]
            yy, xx = np.mgrid[ja:jb, ia:ib]
            score = np.where(sub > 30.0, np.minimum(sub, 400.0) - np.hypot(yy - j0, xx - i0) * px * 0.15, -1e9)
            if score.max() > -1e8:
                k_ = np.unravel_index(np.argmax(score), score.shape)
                j0, i0 = int(yy[k_]), int(xx[k_])
                nx_, nz_ = -half + (i0 + 0.5) * px, -half + (j0 + 0.5) * px
                print('   %s: peak %d m moved %.0f m onto land' % (iid, ph, math.hypot(nx_ - px_, nz_ - pz_)))
                px_, pz_ = nx_, nz_
        peaks.append((px_, pz_, ph, pr, opt, inside))
        rough = opt.get('rough', 0.32 if pr > 1000 else 0.08)
        dist = np.hypot(X - px_, Z - pz_) * (1.0 + rough * n1)     # not a perfect cone
        k = np.clip(1.0 - dist / pr, 0, 1)
        if opt.get('mesa'):
            k = np.clip(k / opt['mesa'], 0, 1); k = k * k * (3.0 - 2.0 * k)   # flat top, escarpment round it
        elif opt.get('cone'):
            k = k ** opt['cone']                                   # concave volcano flanks, steep near the top
        else:
            k = k * k * (3.0 - 2.0 * k) if kind != 'ash' else k ** 1.6   # smooth foot, no crease
        if opt.get('crater'):
            cr, cd = opt['crater']
            k = k - (cd / ph) * np.clip(1.0 - (dist / cr) ** 2, 0, 1) ** 1.5
        if opt.get('gullies'):
            # erosion gullies running straight down the flanks, deepest half-way up
            th = np.arctan2(Z - pz_, X - px_)
            g = np.abs(np.sin(th * opt['gullies'] + 3.0 * n1 + dist / pr * 2.0)) ** 0.5
            flank = np.clip(k * 4.0, 0, 1) * np.clip((1.0 - k) * 3.0, 0, 1)
            k = k - 0.07 * (1.0 - g) * flank
        if opt.get('cliff'):
            cone = ph * k * np.clip(dl / 70.0, 0, 1) ** 0.7        # stands steeply out of the sea
        else:
            # a summit near the shore slopes down to it (at most about 1 in 2.5), not a sheer wall
            cone = ph * k * np.clip(dl / max(160.0, ph * 2.5), 0, 1) ** 0.8
        sk = max(4.0, 0.12 * ph) if not (opt.get('cliff') or opt.get('mesa')) else 3.0
        h = sk * np.logaddexp(h / sk, cone / sk) - sk * math.log(2.0) * np.exp(-np.abs(h - cone) / sk)
    if kind == 'coral':
        h = h + 0.08 * h * n1
    if kind == 'volcanic':
        # ridged noise: spurs and gullies running off the summits, stronger the higher the ground
        n3 = fbm(N, seed + 3, 6, 14)
        ridges = 1.0 - np.abs(n3)
        lift = np.clip(h / 300.0, 0, 1)
        h = h * (1.0 + lift * (0.6 * ridges - 0.6)) + 0.03 * h * n2     # gullies cut down; crests keep the real height
    # every summit at its real height: lift or lower the ground round it to match
    for (px_, pz_, ph, pr, opt, inside) in [q for q in peaks for _ in range(3)]:
        # three rounds, so neighbouring summits that lift each other settle at their heights
        if not inside:
            continue
        i0 = int((px_ + half) / px); j0 = int((pz_ + half) / px)
        if d[j0, i0] <= 0:
            continue
        rr = max(2, int(min(pr * 0.15, 400.0) / px))
        top = float(h[max(0, j0 - rr):j0 + rr + 1, max(0, i0 - rr):i0 + rr + 1].max())
        if abs(top - ph) > 1.0:
            dist = np.hypot(X - px_, Z - pz_)
            bump = np.clip(1.0 - dist / (pr * 0.6), 0, 1)
            # taper toward the shore over a slope of about 1 in 2.5, so a raised summit near the
            # coast does not end in a wall
            bump = bump * bump * (3.0 - 2.0 * bump) * np.clip(dl / max(60.0, abs(ph - top) * 2.5), 0, 1) ** 0.8
            h = h + (ph - top) * bump
    # real elevation data where we have it (USGS 3DEP 1 arc-second: Guam, Saipan, Truk, Palau)
    if I.get('dem'):
        dem = sample_dem(I['dem'], X, Z, lon0, lat0)
        ok = np.isfinite(dem)
        h = np.where(ok & (d > 0), np.maximum(dem, 0.8 * np.clip(dl / 10.0, 0.2, 1) + 0.0), h)
        print('   %s: real elevation data, highest %.0f m' % (iid, np.nanmax(np.where(d > 0, dem, np.nan))))
    h = np.where(d > 0, np.maximum(h, 0.6), h)

    # the sea floor: fringing reef, then the drop-off; atoll lagoons and reef rings
    reef = float(I['reef'])
    off = np.clip(-d, 0, None)
    deep = -60.0 if not I.get('lagoon_all') else -30.0
    sea = np.where(off < reef, -0.5 - 1.6 * (off / max(reef, 1.0)) ** 1.5,
                   np.maximum(deep, -2.1 - (off - reef) * 0.12))
    lag = np.zeros((N, N), bool)
    ring_band = np.zeros((N, N), bool)
    if I.get('lagoon', 0) > 0 and not I.get('rim'):
        # join the islets along the whole rim (crop 3x the window) with a morphological closing:
        # the inside is lagoon, the outer edge of the closed shape the reef ring
        span = 3.0 * half
        NC = 768
        cpx = 2.0 * span / NC
        cm = np.zeros((NC, NC), np.uint8)
        for ring in coast['rings']:
            r = np.asarray(ring, dtype=np.float64)
            if len(r) < 3:
                continue
            x, z = to_local(r[:, 0], r[:, 1], lon0, lat0)
            pts = np.stack([x, z], 1)
            if I['src'] == 'hand':
                pts = chaikin(pts, 3)
            ij = ((pts + span) / cpx * 16.0).round().astype(np.int32)
            cv2.fillPoly(cm, [ij.reshape(-1, 1, 2)], 1, shift=4)
        kk = max(3, int(I['lagoon'] / cpx) * 2 + 1)
        ker = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kk, kk))
        padded = cv2.copyMakeBorder(cm, kk, kk, kk, kk, cv2.BORDER_CONSTANT, value=0)
        closed_c = cv2.morphologyEx(padded, cv2.MORPH_CLOSE, ker)[kk:-kk, kk:-kk]
        closed_c = ndimage.binary_fill_holes(closed_c).astype(np.float32)
        a0 = (span - half) / cpx
        a1 = (span + half) / cpx
        mapx = (a0 + (ii + 0.5) * (a1 - a0) / N - 0.5).astype(np.float32)
        mapy = (a0 + (jj + 0.5) * (a1 - a0) / N - 0.5).astype(np.float32)
        closed = cv2.remap(closed_c, mapx, mapy, cv2.INTER_LINEAR) > 0.5
        lag = closed & (d <= 0)
        edge_c = ndimage.distance_transform_edt(closed_c) * cpx
        edge = cv2.remap(edge_c.astype(np.float32), mapx, mapy, cv2.INTER_LINEAR)
        ring_band = closed & (edge < reef * 0.9)
    if I.get('rim'):
        # the traced reef rim: inside is lagoon, a reef flat runs round its edge
        r = np.asarray(I['rim'], dtype=np.float64)
        x, z = to_local(r[:, 0], r[:, 1], lon0, lat0)
        pts = chaikin(np.stack([x, z], 1), 3)
        rim = np.zeros((N, N), np.uint8)
        cv2.fillPoly(rim, [((pts + half) / px * 16.0).round().astype(np.int32).reshape(-1, 1, 2)], 1, shift=4)
        rim = (rim > 0) | (d > 0)
        # merge the traced rim with the real islets: a closing fills the gaps between them, so
        # the reef runs along the islets' ocean side as it does on the real atoll
        kk = int(1400.0 / px) * 2 + 1
        ker = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kk, kk))
        rim = cv2.morphologyEx(cv2.copyMakeBorder(rim.astype(np.uint8), kk, kk, kk, kk, cv2.BORDER_REPLICATE), cv2.MORPH_CLOSE, ker)[kk:-kk, kk:-kk] > 0
        rim = ndimage.binary_fill_holes(rim)
        edge = ndimage.distance_transform_edt(rim) * px
        # wobble the inner edge of the reef flat so it is not a ruled line
        lag = rim & (d <= 0)
        ring_band = rim & (edge < reef * (0.75 + 0.35 * n2))
        outside = ndimage.distance_transform_edt(~rim) * px
        sea = np.where(~rim & (outside < 220.0), np.maximum(sea, -1.0 - outside * 0.02), sea)
        lag &= True
    if I.get('reef_ring'):
        (rlon, rlat), ra, rb = I['reef_ring']
        cx, cz = to_local(rlon, rlat, lon0, lat0)
        e = np.hypot((X - cx) / ra, (Z - cz) / rb)
        inside = e < 1.0
        lag = inside & (d <= 0)
        ring_band = inside & (e > 1.0 - 380.0 / ra)
        sea = np.where((e >= 1.0) & (e < 1.0 + 300.0 / ra), -1.2, sea)
    lag_depth = -10.0 - 12.0 * (0.5 + 0.5 * n1)      # real lagoons run 10-25 m: ships can steam in
    sea = np.where(lag, np.where(ring_band, -0.7 + 0.3 * n2, np.maximum(lag_depth, np.minimum(sea, -1.0) if True else sea)), sea)
    if I.get('lagoon_all'):
        sea = np.where(off < reef, sea, np.maximum(-30.0, sea))
    # soften the sea floor: reef edges and lagoon mouths drawn on coarse grids show as steps otherwise
    sea = np.minimum(ndimage.gaussian_filter(sea, 2.5), -0.3)
    h = np.where(d > 0, h, sea)

    # cleared ground: airfields (flattened, no trees) and towns
    clear = np.zeros((N, N), np.float32)
    fields_out = []
    for (flon, flat, hdg, ln, w) in I['fields']:
        fx, fz = to_local(flon, flat, lon0, lat0)
        if hdg is None:
            # along the island: the main axis of the land within 1.5 km
            sel = (d > 0) & (np.hypot(X - fx, Z - fz) < 1500.0)
            ys, xs = np.nonzero(sel)
            P = np.stack([X[ys, xs] - fx, Z[ys, xs] - fz], 1)
            ev, evec = np.linalg.eigh(P.T @ P)
            ax = evec[:, 1]
            hdg = math.degrees(math.atan2(ax[0], -ax[1])) % 180.0
        a = math.radians(hdg)
        ux, uz = math.sin(a), -math.cos(a)
        along = (X - fx) * ux + (Z - fz) * uz
        across = -(X - fx) * uz + (Z - fz) * ux
        m = np.clip(1.0 - (np.abs(along) - ln / 2) / 25.0, 0, 1) * np.clip(1.0 - (np.abs(across) - w / 2) / 12.0, 0, 1)
        m = m * (d > 5)
        apron = np.clip(1.0 - (np.abs(along) - ln / 2) / 60.0, 0, 1) * np.clip(1.0 - (np.abs(across) - w * 1.8) / 30.0, 0, 1) * (d > 5)
        clear = np.maximum(clear, np.maximum(m, apron * 0.5))
        hm = float(np.median(h[m > 0.9])) if (m > 0.9).any() else 3.0
        h = np.where(apron > 0, h * (1 - apron) + max(hm, 1.5) * apron, h)
        fields_out.append([float(fx), float(fz), float(hdg), float(ln), float(w)])
    for (tlon, tlat, tr) in I['towns']:
        tx, tz = to_local(tlon, tlat, lon0, lat0)
        t = np.clip(1.0 - np.hypot(X - tx, Z - tz) / tr, 0, 1) * (d > 15)
        t = t * (0.55 + 0.45 * (n2 > -0.2))
        clear = np.maximum(clear, np.where(t > 0.25, 0.5, clear))

    # vegetation: patchy cover, none on the beach, thin on steep slopes and high peaks
    gy, gx = np.gradient(h, px)
    slope = np.hypot(gx, gy)
    beach_w = 25.0 if kind == 'atoll' else (14.0 if kind == 'volcanic' else 8.0)
    veg = float(I['veg']) * np.clip((d - beach_w) / 30.0, 0, 1)
    veg = veg * np.clip(0.75 + 0.5 * n2, 0, 1)
    veg = veg * np.clip(1.3 - slope * (0.8 if kind != 'ash' else 2.5), 0.15, 1)
    if kind == 'ash':
        veg = veg * np.clip(1.0 - h / 140.0, 0, 1)            # Suribachi's upper slopes are bare
    veg = veg * (1.0 - np.clip(clear * 1.6, 0, 1))

    R = np.clip(0.5 + sdf / (2 * SD), 0, 1) * 255
    G = np.clip(enc_h(h), 0, 255)
    B = np.clip(veg, 0, 1) * 255
    A = np.clip(clear, 0, 1) * 255
    img = np.stack([R, G, B, A], -1).round().astype(np.uint8)
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(img, 'RGBA').save(os.path.join(OUT, iid + '.png'), optimize=True)
    # heights at 16 bits (about 5 cm steps from -80 to 3,000 m): high byte in R, low in G
    q = np.clip((h + D_MAX) / (H_MAX + D_MAX) * 65535.0, 0, 65535).round().astype(np.uint16)
    hi = (q >> 8).astype(np.uint8)
    lo = (q & 255).astype(np.uint8)
    Image.fromarray(np.stack([hi, lo, np.zeros_like(hi)], -1), 'RGB').save(os.path.join(OUT, iid + '_h.png'), optimize=True)

    meta = plan_battle(iid, I, d, h, X, Z, px, half, lon0, lat0)
    meta.update({'id': iid, 'name': I['name'], 'lon': lon0, 'lat': lat0, 'half': half, 'n': N, 'px': px,
                 'kind': kind, 'vtype': I['vtype'], 'sd': SD, 'hmax': H_MAX, 'dmax': D_MAX,
                 'peak': float(h.max()), 'fields': fields_out})
    json.dump(meta, open(os.path.join(OUT, iid + '.json'), 'w'), indent=1)
    preview(iid, d, h, veg, clear)
    print('%-13s px %5.1f m  land %5.1f km2  peak %6.0f m  approach %3.0f deg  batteries %d' % (
        iid, px, (d > 0).sum() * px * px / 1e6, h.max(), meta['approach'][0], len(meta['batteries'])))


def sample(arr, x, z, half, px):
    i = int((x + half) / px)
    j = int((z + half) / px)
    if i < 0 or j < 0 or i >= N or j >= N:
        return None
    return arr[j, i]


def plan_battle(iid, I, d, h, X, Z, px, half, lon0, lat0):
    """The landing beach, the approach from the open sea, battery sites, dump and boat spot."""
    bx, bz = to_local(I['beach'][0], I['beach'][1], lon0, lat0)
    # snap the beach to the nearest shoreline point
    shore = np.abs(d) < px * 1.5
    ys, xs = np.nonzero(shore)
    k = np.argmin((X[ys, xs] - bx) ** 2 + (Z[ys, xs] - bz) ** 2)
    sj, si = ys[k], xs[k]
    bx, bz = float(X[sj, si]), float(Z[sj, si])
    gy, gx = np.gradient(ndimage.gaussian_filter(d, 3), px)
    nx, nz = -float(gx[sj, si]), -float(gy[sj, si])          # outward (toward the sea)
    nl = math.hypot(nx, nz) or 1.0
    nx, nz = nx / nl, nz / nl
    nb = math.degrees(math.atan2(nx, -nz))
    # the approach: the bearing off the beach with the longest run of clear water (a fixed one
    # where history says so), and a start distance that stays in that clear water
    best, best_score, best_clear = None, -1e9, 0.0
    fixed = I.get('approach')
    for off in (range(-90, 91, 5) if fixed is None else [0]):
        bdeg = (nb + off) if fixed is None else fixed
        b = math.radians(bdeg)
        ux, uz = math.sin(b), -math.cos(b)
        clear_to = 0.0
        for s_ in np.arange(250.0, 12000.0, 40.0):
            v = sample(h, bx + ux * s_, bz + uz * s_, half, px)
            if v is None:
                clear_to = 12000.0
                break
            if v > -4.0 and s_ > max(450.0, float(I['reef']) + 250.0):
                break
            clear_to = s_
        score = clear_to - abs(off) * 25.0
        if score > best_score:
            best, best_score, best_clear = bdeg % 360.0, score, clear_to
    dist = float(I.get('approach_dist', min(9500.0, max(4000.0, best_clear - 800.0))))
    b = math.radians(best)
    ux, uz = math.sin(b), -math.cos(b)
    # shore batteries: a little way in from the shore facing the approach, spread along it
    cand_m = (d > 50) & (d < 200) & (np.hypot(X - bx, Z - bz) < 4200.0)
    face = (-gx * ux + -gy * uz)
    cand_m &= face > 0.15
    ys, xs = np.nonzero(cand_m)
    pts = np.stack([X[ys, xs], Z[ys, xs]], 1)
    sites = []
    if len(pts):
        order = np.argsort(np.hypot(pts[:, 0] - bx, pts[:, 1] - bz))
        pts = pts[order]
        sites.append(pts[0])
        while len(sites) < 6:
            dd = np.min([np.hypot(pts[:, 0] - s[0], pts[:, 1] - s[1]) for s in sites], axis=0)
            dd = np.where(np.hypot(pts[:, 0] - bx, pts[:, 1] - bz) < 3500.0, dd, 0)
            j = int(np.argmax(dd))
            if dd[j] < 350.0:
                break
            sites.append(pts[j])
    # the dump: 300-700 m inland behind the beach
    dm = (d > 300) & (d < 700) & (np.hypot(X - bx, Z - bz) < 2500.0)
    ys, xs = np.nonzero(dm)
    if len(xs):
        j = np.argmin((X[ys, xs] - bx) ** 2 + (Z[ys, xs] - bz) ** 2)
        dump = [float(X[ys[j], xs[j]]), float(Z[ys[j], xs[j]])]
    else:
        ys, xs = np.nonzero(d > 0)
        j = int(np.argmax(d[ys, xs]))
        dump = [float(X[ys[j], xs[j]]), float(Z[ys[j], xs[j]])]
    # the defenders' boats: water 2-3 km along the coast from the beach, a few hundred metres off
    bm = (h < -2.0) & (h > -30.0) & (d < -150) & (d > -900) & (np.abs(np.hypot(X - bx, Z - bz) - 2600.0) < 600.0)
    ys, xs = np.nonzero(bm)
    if len(xs):
        j = len(xs) // 2
        boat = [float(X[ys[j], xs[j]]), float(Z[ys[j], xs[j]])]
    else:
        boat = [bx + ux * 1500.0 - uz * 1500.0, bz + uz * 1500.0 + ux * 1500.0]
    return {'beach': [bx, bz], 'approach': [best, dist], 'batteries': [[float(s[0]), float(s[1])] for s in sites],
            'dump': dump, 'boats': boat}


def preview(iid, d, h, veg, clear):
    os.makedirs(PREV, exist_ok=True)
    rgb = np.zeros((N, N, 3), np.float32)
    water = d <= 0
    dep = np.clip(-h / 40.0, 0, 1)
    rgb[water] = (np.array([0.35, 0.78, 0.74]) * (1 - dep[water, None]) + np.array([0.08, 0.32, 0.55]) * dep[water, None])
    landc = np.array([0.83, 0.78, 0.6]) * (1 - veg[..., None]) + np.array([0.2, 0.38, 0.17]) * veg[..., None]
    shade = np.clip(1.0 + np.gradient(h)[1] * 0.04 - np.gradient(h)[0] * 0.04, 0.6, 1.3)
    landc = landc * shade[..., None]
    landc = np.where(clear[..., None] > 0.6, np.array([0.8, 0.8, 0.75]), np.where(clear[..., None] > 0.3, np.array([0.6, 0.55, 0.5]), landc))
    rgb[~water] = landc[~water]
    Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8)).save(os.path.join(PREV, iid + '.png'))


def write_gd():
    """scripts/island_maps.gd: every baked island's metadata as a GDScript constant (exports with the game)."""
    out = ['class_name IslandMaps', '## GENERATED by tools/island_builder/bake.py (do not edit): the baked battle islands.',
           '## Positions in metres from the window centre, x east, z south. See bake.py for the PNG channels.', '',
           'const MAPS := {']
    for iid in ISLANDS:
        path = os.path.join(OUT, iid + '.json')
        if not os.path.exists(path):
            continue
        m = json.load(open(path))
        def r(v):
            if isinstance(v, float):
                return round(v, 1)
            if isinstance(v, list):
                return [r(x) for x in v]
            return v
        m = {k: r(v) for k, v in m.items()}
        out.append('\t%s: %s,' % (json.dumps(iid), json.dumps(m)))
    out.append('}')
    open(os.path.join(os.path.dirname(__file__), '..', '..', 'scripts', 'island_maps.gd'), 'w').write('\n'.join(out) + '\n')


if __name__ == '__main__':
    ids = sys.argv[1:] or list(ISLANDS)
    for iid in ids:
        bake(iid, ISLANDS[iid])
    write_gd()
