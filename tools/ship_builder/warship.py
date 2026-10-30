"""Parametric warship parts shared by every class built in Phase 3 (cruisers, battleships,
carriers, destroyers, escorts, submarines). Same conventions as the hand-built Fletcher:
x forward (m from amidships), y up (0 = waterline), z starboard; every turning weapon is its
own group whose name must match TYPES[...].mounts[].g in scripts/data.gd.

A class is described by a spec dict (see us_ships.py / ijn_ships.py) and built by build_spec()."""
import numpy as np
from geom import Mesh, Builder, rounded_plan, rot_y

# ---------------- palettes ----------------
PAL = {
    # US Measure 21 navy blue (1942-43 Pacific), teak decks on carriers, deck blue elsewhere
    'us': dict(hull='#2f3c4c', deck='#3a4452', sup='#36434f', gun='#384551', dark='#1b1f23', bottom='#5a2a24', boot='#151719',
               wood='#8d7a5c', raft='#5c6670', black='#0b0b0b', rail='#20262c', canvas='#7a7562', glass='#26323a', light='#c9d1d4',
               fdeck='#4a4a48', mark='#d9d6cc', plane='#2d3f55', planew='#9fa9b2'),
    # US Measure 22 graded: haze gray above the sheer line, navy blue below
    'us22': dict(hull='#7d8890', deck='#3b4350', sup='#8a959c', gun='#8a959c', dark='#2a3036', bottom='#5a2a24', boot='#2b3a4c',
                 wood='#8d7a5c', raft='#7a858c', black='#0b0b0b', rail='#2a3036', canvas='#9b9580', glass='#3a4850', light='#d8dee0', band='#2b3a4c',
                 fdeck='#4a4a48', mark='#d9d6cc', plane='#2d3f55', planew='#9fa9b2'),
    # IJN Kure / Sasebo gray, linoleum decks (brown) on cruisers and destroyers, wood on capital ships
    'ijn': dict(hull='#6a7174', deck='#7b4f37', sup='#737a7d', gun='#6e7578', dark='#26292b', bottom='#6b2b22', boot='#1b1c1d',
                black='#0b0b0b', rail='#2a2d2f', canvas='#9a917a', light='#c9cfd1', brass='#a88a52', glass='#2f383c', wood='#9c8762', raft='#5c6164',
                fdeck='#8a7a5a', mark='#e6e2d4', red='#b3312c', plane='#6d7a5c', planew='#b9b2a0'),
}


# =====================================================================
# hull
# =====================================================================

class WarHull:
    """A warship hull from a few numbers: length, half beam, draft, a deck-height function,
    optional forecastle break, bow and stern types, bulges."""

    def __init__(self, L, half_beam, draft, deck_fn, breaks=(), rake=4.0, entry=0.34, run=0.30,
                 flare=0.22, stern='cruiser', bulge=0.0, fine=2.1, clipper=0.0):
        self.L, self.B, self.T = L, half_beam, draft
        self.XB, self.XS = L / 2, -L / 2
        self.deck_fn, self.breaks = deck_fn, sorted(breaks)
        self.rake, self.entry, self.run, self.flare = rake, entry, run, flare
        self.stern, self.bulge, self.fine, self.clipper = stern, bulge, fine, clipper

    def stem_x(self, y):
        top = self.deck_fn(self.XB - 0.5)
        f = np.clip((y + self.T) / (top + self.T), 0, 1)
        # clipper bows (IJN) sweep forward near the deck
        return self.XB - self.rake * (1 - f) ** 1.3 + self.clipper * f ** 3

    def hb(self, x, y):
        L, B = self.L, self.B
        xs = self.stem_x(y)
        if x >= xs:
            return 0.0
        xe = self.XB - self.entry * L
        xr = self.XS + self.run * L
        if x > xe:
            t = (x - xe) / (xs - xe)
            w = B * (1 - t ** self.fine) ** 0.62
        elif x < xr:
            t = (xr - x) / (xr - self.XS)
            if self.stern == 'transom':
                w = B * (1 - 0.25 * t ** 1.8)
            else:
                w = B * (1 - 0.55 * t ** 1.6)
        else:
            w = B
        yd = self.deck_fn(x)
        if x > xe and y < yd:
            f = np.clip((x - xe) / (xs - xe), 0, 1)
            w *= 1 - self.flare * f * np.clip((yd - y) / (yd + self.T), 0, 1)
        if y < 0:
            d = -y / self.T
            w *= (1 - d ** 3.2) ** (1 / 3.2) if d < 1 else 0.0
            if x < xr:
                t = (xr - x) / (xr - self.XS)
                w *= 1 - 0.7 * t * d ** 0.7
            # anti-torpedo bulges on old battleships
            if self.bulge > 0 and -0.3 * L < x < 0.3 * L and 0.15 < d < 0.85:
                w += self.bulge * np.sin((d - 0.15) / 0.7 * np.pi) * (1 - (abs(x) / (0.3 * L)) ** 3)
        return max(w, 0.0)

    def width(self, x):
        return self.hb(x, self.deck_fn(x))

    def build(self, M, P, levels=18, deck_mat=None, camber=0.18):
        H = Builder(M, 'Hull', P['hull'])
        cuts = [self.XS] + list(self.breaks) + [self.XB - 0.6]
        xs_list = []
        for a, b in zip(cuts[:-1], cuts[1:]):
            n = max(4, int((b - a) / 1.6))
            xs_list += list(np.linspace(a + 0.01, b - 0.01, n))
        xs_list += list(np.linspace(self.XB - 0.5, self.stem_x(self.deck_fn(self.XB)) - 0.05, 5))
        secs = []
        for x in xs_list:
            yd = self.deck_fn(x)
            secs.append([(x, y, self.hb(x, y)) for y in np.linspace(-self.T, yd, levels)])
        self.secs = secs
        mat = lambda y: P['bottom'] if y < -0.3 else (P['boot'] if y < 0.5 else (P['band'] if ('band' in P and y < self.deck_fn(0) - 0.8) else P['hull']))
        for a, b in zip(secs[:-1], secs[1:]):
            if abs(a[-1][1] - b[-1][1]) > 0.3:
                lo, hi = (a, b) if a[-1][1] < b[-1][1] else (b, a)
                xb = (a[0][0] + b[0][0]) / 2
                H.set_mat(P['hull'])
                for s in (1, -1):
                    for k in range(levels - 1):
                        y0, y1 = hi[k][1], hi[k + 1][1]
                        if y1 <= lo[-1][1]:
                            continue
                        y0 = max(y0, lo[-1][1])
                        H.quad((xb, y0, 0), (xb, y0, s * self.hb(xb, y0)), (xb, y1, s * self.hb(xb, y1)), (xb, y1, 0))
                top = min(a[-1][1], b[-1][1])
                aa = [(x, min(y, top), self.hb(x, min(y, top))) for x, y, _ in a]
                bb = [(x, min(y, top), self.hb(x, min(y, top))) for x, y, _ in b]
                a, b = aa, bb
            for k in range(levels - 1):
                H.set_mat(mat(a[k][1]))
                for s in (1, -1):
                    H.quad((a[k][0], a[k][1], s * a[k][2]), (b[k][0], b[k][1], s * b[k][2]), (b[k + 1][0], b[k + 1][1], s * b[k + 1][2]), (a[k + 1][0], a[k + 1][1], s * a[k + 1][2]))
        last = secs[-1]
        for k in range(levels - 1):
            y0, y1 = last[k][1], last[k + 1][1]
            H.set_mat(mat(y0))
            for s in (1, -1):
                H.quad((last[k][0], y0, s * last[k][2]), (self.stem_x(y0), y0, 0), (self.stem_x(y1), y1, 0), (last[k + 1][0], y1, s * last[k + 1][2]))
        st = secs[0]
        for k in range(levels - 1):
            H.set_mat(mat(st[k][1]))
            H.quad((st[k][0], st[k][1], -st[k][2]), (st[k][0], st[k][1], st[k][2]), (st[k + 1][0], st[k + 1][1], st[k + 1][2]), (st[k + 1][0], st[k + 1][1], -st[k + 1][2]))
        D = Builder(M, 'Hull', deck_mat or P['deck'])
        for a, b in zip(secs[:-1], secs[1:]):
            if abs(a[-1][1] - b[-1][1]) > 0.3:
                continue
            for k in range(6):
                z0, z1 = -1 + k / 3, -1 + (k + 1) / 3
                cam = lambda z: camber * (1 - z * z)
                D.quad((a[-1][0], a[-1][1] + cam(z0), z0 * a[-1][2]), (b[-1][0], b[-1][1] + cam(z0), z0 * b[-1][2]),
                       (b[-1][0], b[-1][1] + cam(z1), z1 * b[-1][2]), (a[-1][0], a[-1][1] + cam(z1), z1 * a[-1][2]))
        l = secs[-1][-1]
        D.tri((l[0], l[1], -l[2]), (self.stem_x(l[1]), l[1], 0), (l[0], l[1], l[2]))
        return H

    def rails(self, M, P, skip=(), step=2.0):
        R = Builder(M, 'Hull', P['rail'])
        for s in (1, -1):
            prev = None
            for x in np.arange(self.XS + 1.0, self.XB - 3.0, step):
                if any(a <= x <= b for a, b in skip) or any(abs(x - b) < 1.0 for b in self.breaks):
                    prev = None
                    continue
                y = self.deck_fn(x); z = s * (self.width(x) - 0.15)
                R.box((x, y + 0.5, z), (0.06, 1.0, 0.06))
                if prev is not None:
                    a, b = (prev[0], prev[1] + 1.0, prev[2]), (x, y + 1.0, z)
                    R.quad(a, b, (b[0], b[1] + 0.04, b[2]), (a[0], a[1] + 0.04, a[2]))
                prev = (x, y, z)


def sheer(fwd_h, mid_h, aft_h, L, breaks=None):
    """Deck height function: higher at the bow, a little up at the stern, optional raised forecastle."""
    XB = L / 2
    def f(x):
        if x >= 0:
            y = mid_h + (fwd_h - mid_h) * (x / XB) ** 2.2
        else:
            y = mid_h + (aft_h - mid_h) * (-x / XB) ** 1.5
        if breaks:
            for xb, step in breaks:
                if x >= xb:
                    y += step
        return y
    return f


# =====================================================================
# deck fittings
# =====================================================================

def anchors_and_bollards(F, hull, P, bollards):
    dy = hull.deck_fn
    F.set_mat(P['dark'])
    xb = hull.XB
    for s in (1, -1):
        F.cyl((xb - 7, dy(xb - 7), s * 1.4), (xb - 7, dy(xb - 7) + 0.6, s * 1.4), 0.5, n=14)
        for i in range(10):
            x = xb - 4.5 - i * 0.35
            F.box((x, dy(x) + 0.05, s * (1.5 - i * 0.02)), (0.3, 0.1, 0.18))
        F.cyl((xb - 3.5, dy(xb - 3.5) - 0.05, s * 1.6), (xb - 3.5, dy(xb - 3.5) + 0.08, s * 1.6), 0.4, n=12)
    for x in bollards:
        for s in (1, -1):
            w = hull.width(x)
            if w < 1.5:
                continue
            z = s * (w - 0.8)
            for dx in (-0.4, 0.4):
                F.cyl((x + dx, dy(x), z), (x + dx, dy(x) + 0.5, z), 0.18, n=8)


def ventilators(F, P, items, dy):
    F.set_mat(P['sup'])
    for x, z in items:
        F.cyl((x, dy(x), z), (x, dy(x) + 1.1, z), 0.35, n=10)
        F.cyl((x, dy(x) + 1.1, z), (x, dy(x) + 1.4, z), 0.48, 0.22, n=10)


def deckhouse(S, P, x_front, x_back, half, y0, y1, r_front=2.5, inset=0.0, mat=None):
    S.set_mat(mat or P['sup'])
    S.prism(rounded_plan(x_front, x_back, half, r_front), y0, y1, inset=inset)
    return y1


def block(S, P, x_front, x_back, half, y0, y1, mat=None, inset=0.0):
    S.set_mat(mat or P['sup'])
    S.prism([(x_front, half), (x_back, half), (x_back, -half), (x_front, -half)], y0, y1, inset=inset)
    return y1


def platform(S, P, x_front, x_back, z0, z1, y, thick=0.25):
    S.set_mat(P['sup'])
    S.prism([(x_front, z0), (x_back, z0), (x_back, z1), (x_front, z1)], y - thick, y)


def funnel(S, P, x, base, h, rx, rz, rake=0.9, cap=True, trunk=False, lean_aft=True, n=24):
    """Raked oval funnel with a black cap. trunk=True makes it a tall trunked (merged) funnel."""
    sign = 1 if lean_aft else -1
    ring = lambda y, k: [(x - sign * rake * (y - base) / h + np.cos(t) * rx * k, y, np.sin(t) * rz * k) for t in np.linspace(0, 2 * np.pi, n, endpoint=False)]
    S.set_mat(P['sup'])
    lo, hi = ring(base, 1.0), ring(base + h, 0.95)
    for i in range(n):
        j = (i + 1) % n
        S.quad(lo[i], lo[j], hi[j], hi[i])
    if cap:
        c0, c1 = ring(base + h, 1.03), ring(base + h + 0.08 * h, 1.03)
        S.set_mat(P['black'])
        for i in range(n):
            j = (i + 1) % n
            S.quad(c0[i], c0[j], c1[j], c1[i])
        S.capfan(ring(base + h + 0.06 * h, 0.9))
    S.set_mat(P['sup'])


def funnel_downturned(S, P, x, y, z, h, r, side=1):
    """IJN carrier funnel: curves out of the hull side and down toward the sea."""
    S.set_mat(P['sup'])
    pts = [(x, y, z), (x, y - h * 0.3, z + side * r * 1.6), (x, y - h, z + side * r * 2.6)]
    for a, b in zip(pts[:-1], pts[1:]):
        S.cyl(a, b, r, r, n=14, caps=False)
    S.set_mat(P['black'])
    S.cyl(pts[-1], (pts[-1][0], pts[-1][1] - 0.4, pts[-1][2] + side * 0.3), r * 1.05, r, n=14)
    S.set_mat(P['sup'])


def mast_pole(Mt, P, x, y0, h, r0=0.25, r1=0.12, yard=4.0, yard_h=0.7):
    Mt.set_mat(P['dark'])
    Mt.cyl((x, y0, 0), (x, y0 + h, 0), r0, r1, n=10)
    if yard:
        Mt.cyl((x, y0 + h * yard_h, -yard), (x, y0 + h * yard_h, yard), 0.08, n=6)


def mast_tripod(Mt, P, x, y0, h, spread=3.0, yard=5.0):
    Mt.set_mat(P['dark'])
    Mt.cyl((x, y0, 0), (x, y0 + h, 0), 0.32, 0.16, n=10)
    for s in (1, -1):
        Mt.cyl((x - spread, y0, s * spread * 0.8), (x, y0 + h * 0.78, 0), 0.14, 0.10, n=6, caps=False)
    if yard:
        Mt.cyl((x, y0 + h * 0.72, -yard), (x, y0 + h * 0.72, yard), 0.08, n=6)


def mast_lattice(Mt, P, x, y0, h, w=2.2):
    """Cage-like lattice mast (Texas-style cage simplified to four legs and rings)."""
    Mt.set_mat(P['dark'])
    for sx in (1, -1):
        for sz in (1, -1):
            Mt.cyl((x + sx * w, y0, sz * w), (x + sx * w * 0.35, y0 + h, sz * w * 0.35), 0.12, 0.08, n=6, caps=False)
    for k in range(1, 6):
        y = y0 + h * k / 6
        ww = w * (1 - 0.65 * k / 6)
        for a, b in [((x + ww, y, ww), (x - ww, y, ww)), ((x - ww, y, ww), (x - ww, y, -ww)), ((x - ww, y, -ww), (x + ww, y, -ww)), ((x + ww, y, -ww), (x + ww, y, ww))]:
            Mt.cyl(a, b, 0.05, n=5, caps=False)


def radar_bedspring(Mt, P, x, y, w=4.0, h=2.0, nz=9):
    Mt.set_mat(P['rail'])
    for k in range(nz):
        z = -w / 2 + k * w / (nz - 1)
        Mt.box((x, y, z), (0.05, h, 0.05))
    for k in range(5):
        Mt.box((x, y - h / 2 + k * h / 4, 0), (0.05, 0.05, w))


def radome(Mt, P, x, y):
    Mt.set_mat(P['sup'])
    Mt.cyl((x, y, 0), (x, y + 0.9, 0), 0.6, 0.45, n=14)


def director(M, name, pos, P, radar=True, size=1.0):
    G = Builder(M, name, P['sup'], pivot=pos)
    G.xf = (np.eye(3), np.array(pos))
    s = size
    plan = [(1.6 * s, -1.2 * s), (1.6 * s, 1.2 * s), (1.0 * s, 1.6 * s), (-1.8 * s, 1.6 * s), (-1.8 * s, -1.6 * s), (1.0 * s, -1.6 * s)]
    G.prism(plan, 0.0, 1.9 * s, inset=0.1)
    G.set_mat(P['gun'])
    G.cyl((-0.2, 1.3 * s, -2.6 * s), (-0.2, 1.3 * s, 2.6 * s), 0.22 * s, n=12)
    if radar:
        G.set_mat(P['rail'])
        G.box((0.0, 2.6 * s, 0), (0.25, 1.3 * s, 2.4 * s))


def rangefinder_tower(S, P, x, y0, h, half=1.8, arms=5.0):
    """Big rangefinder hood on top of a tower (battleships, IJN cruisers)."""
    S.set_mat(P['sup'])
    S.prism(rounded_plan(x + half, x - half, half, half * 0.9), y0, y0 + h)
    S.set_mat(P['gun'])
    S.cyl((x, y0 + h * 0.7, -arms), (x, y0 + h * 0.7, arms), 0.3, n=12)


def searchlight(B, P, x, y, z):
    B.set_mat(P['dark'])
    B.cyl((x, y, z), (x, y + 0.9, z), 0.15, n=8)
    B.set_mat(P['light'])
    B.cyl((x, y + 0.9, z), (x, y + 1.5, z), 0.55, n=14)


def boat(B, P, x, y, z, L=8.0, w=2.0, davits=True, deck_y=None):
    pts = [(x + np.cos(t) * L / 2, z + np.sin(t) * w / 2 * (1 - 0.25 * max(0, np.cos(t)))) for t in np.linspace(0, 2 * np.pi, 16, endpoint=False)]
    B.set_mat(P['light'])
    B.prism(pts, y - 0.7, y, inset=0.2)
    B.set_mat(P['canvas'])
    B.prism([(p[0] * .85 + x * .15, p[1] * .7 + z * .3) for p in pts], y, y + 0.15)
    if davits and deck_y is not None:
        B.set_mat(P['dark'])
        for dx in (-L * 0.4, L * 0.4):
            B.cyl((x + dx, deck_y, z - np.sign(z) * 1.6), (x + dx, y + 1.2, z + np.sign(z) * 0.1), 0.08, n=6)


def rafts(B, P, items):
    B.set_mat(P['raft'])
    for x, y, z in items:
        B.box((x, y, z), (2.6, 1.0, 0.3))


def crane(B, P, x, y, z, h=9.0, reach=8.0, side=1):
    B.set_mat(P['dark'])
    B.cyl((x, y, z), (x, y + h, z), 0.35, 0.25, n=10)
    B.cyl((x, y + h * 0.55, z), (x - reach * 0.4, y + h * 1.05, z + side * reach), 0.16, 0.12, n=8)
    B.cyl((x, y + h, z), (x - reach * 0.4, y + h * 1.05, z + side * reach), 0.04, n=5, caps=False)


def catapult(B, P, x, y, z, L=20.0, angle=0.0):
    B.set_mat(P['dark'])
    c, s = np.cos(angle), np.sin(angle)
    B.cyl((x, y, z), (x, y + 1.2, z), 0.8, n=12)
    a = (x - c * L / 2, y + 1.2, z - s * L / 2); b = (x + c * L / 2, y + 1.6, z + s * L / 2)
    B.set_mat(P['rail'])
    B.cyl(a, b, 0.5, 0.5, n=6)
    B.cyl((a[0], a[1] - 0.6, a[2]), (b[0], b[1] - 0.6, b[2]), 0.12, n=5)


def floatplane(B, P, x, y, z, heading=0.0, span=11.0, length=10.0, twin_float=False):
    """Kingfisher / Jake / Pete style scout seaplane folded on a catapult or deck."""
    R = rot_y(-heading)
    def pt(px, py, pz):
        v = R @ np.array([px, py, pz]) + np.array([x, y, z])
        return tuple(v)
    B.set_mat(P['plane'])
    # fuselage
    fus = [pt(length / 2, 0.9, 0), pt(length * 0.2, 1.4, 0.45), pt(-length / 2, 1.1, 0.2), pt(-length / 2, 1.1, -0.2), pt(length * 0.2, 1.4, -0.45)]
    B.poly(fus)
    fus2 = [pt(length / 2, 0.5, 0), pt(length * 0.2, 0.5, 0.45), pt(-length / 2, 0.7, 0.2), pt(-length / 2, 0.7, -0.2), pt(length * 0.2, 0.5, -0.45)]
    B.poly(fus2[::-1])
    for i in range(5):
        j = (i + 1) % 5
        B.quad(fus2[i], fus2[j], fus[j], fus[i])
    # wing
    B.set_mat(P['planew'])
    B.quad(pt(length * 0.15, 1.3, -span / 2), pt(length * 0.15, 1.3, span / 2), pt(-length * 0.05, 1.3, span / 2), pt(-length * 0.05, 1.3, -span / 2))
    B.quad(pt(-length * 0.5, 1.1, -span * 0.2), pt(-length * 0.5, 1.1, span * 0.2), pt(-length * 0.38, 1.1, span * 0.2), pt(-length * 0.38, 1.1, -span * 0.2))
    B.box(pt(-length * 0.46, 1.6, 0), (length * 0.1, 1.0, 0.08))
    # floats
    B.set_mat(P['plane'])
    if twin_float:
        for s in (1, -1):
            B.cyl(pt(length * 0.45, 0.0, s * 1.8), pt(-length * 0.35, 0.0, s * 1.8), 0.35, 0.25, n=8)
    else:
        B.cyl(pt(length * 0.5, 0.0, 0), pt(-length * 0.4, 0.0, 0), 0.4, 0.3, n=8)
    # propeller disc
    B.set_mat(P['dark'])
    B.cyl(pt(length / 2, 0.9, 0), pt(length / 2 + 0.1, 0.9, 0), 1.3, n=12)


def aircraft(B, P, x, y, z, heading=0.0, span=12.0, length=9.5, folded=False):
    """Carrier aircraft on deck (wings folded or spread)."""
    R = rot_y(-heading)
    def pt(px, py, pz):
        v = R @ np.array([px, py, pz]) + np.array([x, y, z])
        return tuple(v)
    B.set_mat(P['plane'])
    B.cyl(pt(length / 2, 0.9, 0), pt(-length / 2, 0.9, 0), 0.75, 0.3, n=8)
    B.set_mat(P['planew'])
    if folded:
        for s in (1, -1):
            B.quad(pt(length * 0.05, 1.4, s * 0.9), pt(-length * 0.45, 1.4, s * 0.9), pt(-length * 0.45, 3.0, s * 1.4), pt(length * 0.05, 3.0, s * 1.4))
    else:
        B.quad(pt(length * 0.12, 1.1, -span / 2), pt(length * 0.12, 1.1, span / 2), pt(-length * 0.1, 1.1, span / 2), pt(-length * 0.1, 1.1, -span / 2))
    B.quad(pt(-length * 0.5, 1.0, -span * 0.18), pt(-length * 0.5, 1.0, span * 0.18), pt(-length * 0.4, 1.0, span * 0.18), pt(-length * 0.4, 1.0, -span * 0.18))
    B.box(pt(-length * 0.46, 1.6, 0), (length * 0.1, 1.2, 0.08))
    B.set_mat(P['dark'])
    B.cyl(pt(length / 2, 0.9, 0), pt(length / 2 + 0.1, 0.9, 0), 1.4, n=12)
    for s in (1, -1):
        B.cyl(pt(length * 0.2, 0.0, s * 1.2), pt(length * 0.2, 0.6, s * 1.2), 0.12, n=6)


# =====================================================================
# weapons: every one is its own group so it can train
# =====================================================================

def turret(M, name, pos, face, P, cal, barrels, shielded=True):
    """Main-battery turret scaled from the calibre in mm (152 = 6-inch ... 460 = 18.1-inch)."""
    k = cal / 203.0                       # 1.0 for an 8-inch turret
    G = Builder(M, name, P['gun'], pivot=pos)
    G.xf = (rot_y(-face), np.array(pos))
    w = (1.6 + 1.9 * barrels) * (0.55 + 0.45 * k)   # width grows with barrel count
    L = 7.5 * (0.6 + 0.4 * k) + 1.5 * k
    h = 2.6 * (0.7 + 0.3 * k)
    G.cyl((0, 0, 0), (0, 0.35, 0), w * 0.55, n=24)   # barbette ring
    plan = [(L * 0.45, -w / 2 + 0.3), (L * 0.45, w / 2 - 0.3), (L * 0.3, w / 2), (-L * 0.45, w / 2), (-L * 0.55, w * 0.35), (-L * 0.55, -w * 0.35), (-L * 0.45, -w / 2), (L * 0.3, -w / 2)]
    G.prism(plan, 0.35, 0.35 + h, inset=0.22 * k)
    G.set_mat(P['sup'])
    G.box((-L * 0.25, 0.35 + h + 0.1, 0), (L * 0.3, 0.2, w * 0.6))
    # rangefinder hood on the roof (ijn and us heavy turrets)
    if cal >= 200:
        G.set_mat(P['gun'])
        G.cyl((-L * 0.3, 0.35 + h + 0.6, -w * 0.55), (-L * 0.3, 0.35 + h + 0.6, w * 0.55), 0.3 * k + 0.1, n=10)
    # barrels and blast bags
    bl = 10.5 * k + 2.0
    rb = 0.14 + 0.18 * k
    for i in range(barrels):
        z = (i - (barrels - 1) / 2) * (w / (barrels + 0.6))
        G.set_mat(P['canvas'])
        G.cyl((L * 0.35, 0.35 + h * 0.55, z), (L * 0.45 + 0.6, 0.35 + h * 0.55, z), rb * 2.2, rb * 1.7, n=10)
        G.set_mat(P['dark'])
        G.cyl((L * 0.45 + 0.5, 0.35 + h * 0.55, z), (L * 0.45 + bl, 0.35 + h * 0.55 + bl * 0.03, z), rb, rb * 0.75, n=10)


def dp_twin(M, name, pos, face, P, enclosed=True, cal=127):
    """5-inch/38 twin (US) or 12.7 cm twin (IJN) gunhouse."""
    k = cal / 127.0
    G = Builder(M, name, P['gun'], pivot=pos)
    G.xf = (rot_y(-face), np.array(pos))
    G.cyl((0, 0, 0), (0, 0.35, 0), 2.5 * k, n=20)
    plan = [(2.6, -1.9), (2.6, 1.9), (1.4, 2.5), (-2.4, 2.5), (-3.1, 1.6), (-3.1, -1.6), (-2.4, -2.5), (1.4, -2.5)]
    plan = [(a * k, b * k) for a, b in plan]
    G.prism(plan, 0.35, 0.35 + 2.7 * k, inset=0.18)
    G.set_mat(P['sup'])
    G.box((-1.3 * k, 0.35 + 2.75 * k, 0.0), (1.4 * k, 0.18, 1.8 * k))
    for s in (1, -1):
        z = s * 0.95 * k
        G.set_mat(P['canvas'])
        G.cyl((2.2 * k, 1.75 * k, z), (2.9 * k, 1.75 * k, z), 0.34, 0.26, n=10)
        G.set_mat(P['dark'])
        G.cyl((2.8 * k, 1.75 * k, z), (8.0 * k, 1.85 * k, z), 0.12, 0.09, n=10)


def dp_single(M, name, pos, face, P, cal=127, enclosed=True):
    """5-inch/38 single: enclosed Mk 30 (destroyers) or open Mk 24 (carriers, subs' deck gun)."""
    k = cal / 127.0
    G = Builder(M, name, P['gun'], pivot=pos)
    G.xf = (rot_y(-face), np.array(pos))
    G.cyl((0, 0, 0), (0, 0.35, 0), 2.1 * k, n=20)
    if enclosed:
        plan = [(2.3, -1.4), (2.3, 1.4), (1.2, 2.0), (-2.2, 2.0), (-2.9, 1.2), (-2.9, -1.2), (-2.2, -2.0), (1.2, -2.0)]
        G.prism([(a * k, b * k) for a, b in plan], 0.35, 0.35 + 2.6 * k, inset=0.18)
        G.set_mat(P['sup'])
        G.box((-1.3 * k, 0.35 + 2.68 * k, 0.0), (1.2 * k, 0.16, 1.4 * k))
    else:
        G.cyl((0, 0.35, 0), (0, 1.3 * k, 0), 0.6 * k, n=12)
        G.box((0.3 * k, 1.4 * k, 0), (1.6 * k, 0.6 * k, 1.4 * k))
        # splinter shield
        G.set_mat(P['sup'])
        G.prism([(1.4 * k, -1.5 * k), (1.4 * k, 1.5 * k), (0.4 * k, 1.9 * k), (0.4 * k, -1.9 * k)], 0.35, 0.35 + 1.9 * k, inset=0.0)
    G.set_mat(P['canvas'])
    G.cyl((2.0 * k, 1.5 * k, 0), (2.6 * k, 1.5 * k, 0), 0.33, 0.26, n=10)
    G.set_mat(P['dark'])
    G.cyl((2.5 * k, 1.5 * k, 0), (7.5 * k, 1.6 * k, 0), 0.12, 0.09, n=10)


def casemate_gun(M, name, pos, face, P):
    """Open single gun in a hull casemate (Texas 5-inch/51, Nagato/Kongo 14 cm)."""
    G = Builder(M, name, P['gun'], pivot=pos)
    G.xf = (rot_y(-face), np.array(pos))
    G.cyl((0, 0, 0), (0, 0.9, 0), 0.5, n=10)
    G.box((0.3, 1.1, 0), (1.4, 0.5, 1.0))
    G.set_mat(P['dark'])
    G.cyl((0.8, 1.2, 0), (5.5, 1.3, 0), 0.1, 0.08, n=8)


def torpedo_mount(M, name, pos, P, tubes=5, face=0.0, cover=False):
    G = Builder(M, name, P['gun'], pivot=pos)
    G.xf = (rot_y(-face), np.array(pos))
    G.cyl((0, 0, 0), (0, 0.5, 0), 1.6, n=18)
    G.set_mat(P['dark'])
    w = 0.7
    for k in range(tubes):
        z = (k - (tubes - 1) / 2) * w
        G.cyl((-3.6, 1.0, z), (3.6, 1.0, z), 0.3, n=10)
    G.set_mat(P['gun'])
    if cover:
        G.box((0.0, 1.4, 0), (7.4, 1.2, tubes * w + 0.4), top_inset=0.2)
    else:
        G.box((-2.4, 1.6, 0), (1.2, 0.9, 1.2))


def bofors_quad(M, name, pos, P, face=0.0, tub=True, twin=False):
    T = Builder(M, 'Hull', P['sup'])
    x, y, z = pos
    r = 2.0 if twin else 2.6
    if tub:
        T.cyl((x, y, z), (x, y + 1.1, z), r, n=22, caps=False)
        T.cyl((x, y + 0.02, z), (x, y + 0.04, z), r - 0.1, n=22)
    G = Builder(M, name, P['gun'], pivot=pos)
    G.xf = (rot_y(-face), np.array(pos))
    G.cyl((0, 0, 0), (0, 0.9, 0), 0.6, n=12)
    G.box((0.0, 1.05, 0), (1.5, 0.5, 1.4 if twin else 2.4))
    G.set_mat(P['dark'])
    zs = (-0.32, 0.32) if twin else (-0.95, -0.35, 0.35, 0.95)
    for zz in zs:
        G.cyl((0.4, 1.15, zz), (3.2, 1.25, zz), 0.07, n=8)
    G.set_mat(P['gun'])
    G.box((-0.7, 0.9, 0), (0.4, 0.8, 1.6 if twin else 2.6))


def oerlikon(M, name, pos, P, face):
    G = Builder(M, name, P['gun'], pivot=pos)
    G.xf = (rot_y(-face), np.array(pos))
    G.cyl((0, 0, 0), (0, 0.9, 0), 0.12, n=8)
    G.box((0.15, 1.15, 0), (0.08, 0.8, 0.9))
    G.set_mat(P['dark'])
    G.cyl((0.0, 1.1, 0), (2.2, 1.2, 0), 0.05, n=6)


def jp25_triple(M, name, pos, P, face=0.0, barrels=3):
    G = Builder(M, name, P['gun'], pivot=pos)
    G.xf = (rot_y(-face), np.array(pos))
    G.cyl((0, 0, 0), (0, 0.8, 0), 0.5, n=10)
    G.box((0.0, 1.0, 0), (1.3, 0.5, 0.5 + 0.45 * barrels))
    G.set_mat(P['dark'])
    for k in range(barrels):
        z = (k - (barrels - 1) / 2) * 0.45
        G.cyl((0.3, 1.1, z), (2.6, 1.2, z), 0.06, n=6)


def hedgehog(F, P, x, y):
    F.set_mat(P['dark'])
    F.box((x, y + 0.3, 0), (1.6, 0.6, 2.8))
    for i in range(4):
        for j in range(6):
            F.cyl((x - 0.6 + i * 0.4, y + 0.6, -1.25 + j * 0.5), (x - 0.5 + i * 0.4, y + 1.3, -1.25 + j * 0.5), 0.07, n=5)


def depth_charges(K, P, hull, x_rack=None, k_guns=()):
    dy = hull.deck_fn
    K.set_mat(P['dark'])
    xr = x_rack if x_rack is not None else hull.XS + 4.5
    for s in (1, -1):
        z = s * max(1.2, hull.width(xr) * 0.45)
        K.box((xr, dy(xr) + 0.25, z), (6.0, 0.5, 0.9))
        for i in range(6):
            x = xr + 2.3 - i * 0.9
            K.cyl((x, dy(x) + 0.5, z - 0.4), (x, dy(x) + 0.5, z + 0.4), 0.3, n=10)
    for x in k_guns:
        for s in (1, -1):
            z = s * (hull.width(x) - 1.2)
            K.cyl((x, dy(x), z), (x, dy(x) + 0.9, z + s * 0.3), 0.18, n=8)


# =====================================================================
# carriers
# =====================================================================

def flight_deck(S, P, x_front, x_back, half, y, thick=1.2, round_down=6.0, nose=4.0, markings=True, hull_width=None, elevators=(), stripes=True):
    """A flat flight deck with rounded ends, dashed centre line, elevator outlines and a
    coloured round-down at the stern."""
    S.set_mat(P['sup'])
    plan = []
    n = 8
    for t in np.linspace(-np.pi / 2, np.pi / 2, n):
        plan.append((x_front - nose + np.cos(t) * nose, np.sin(t) * half))
    for t in np.linspace(np.pi / 2, 3 * np.pi / 2, n):
        plan.append((x_back + round_down + np.cos(t) * round_down, np.sin(t) * half))
    S.prism(plan, y - thick, y, bottom=True)
    S.set_mat(P['fdeck'])
    top = [(px, y + 0.02, pz) for px, pz in plan]
    S.capfan(top)
    if markings:
        S.set_mat(P['mark'])
        for x in np.arange(x_back + 12, x_front - 8, 9.0):
            S.box((x, y + 0.05, 0), (5.0, 0.03, 0.5))
        for s in (1, -1):
            S.box(((x_front + x_back) / 2, y + 0.05, s * (half - 1.0)), (x_front - x_back - 20, 0.03, 0.3))
        for ex, el, ew in elevators:
            for a, b, w in [((ex - el / 2, ex + el / 2), (-ew / 2, -ew / 2), 0), ((ex - el / 2, ex + el / 2), (ew / 2, ew / 2), 0)]:
                S.box(((a[0] + a[1]) / 2, y + 0.05, b[0]), (el, 0.03, 0.25))
            S.box((ex - el / 2, y + 0.05, 0), (0.25, 0.03, ew))
            S.box((ex + el / 2, y + 0.05, 0), (0.25, 0.03, ew))
    # supports down to the hull along the edges
    S.set_mat(P['dark'])
    if hull_width is not None:
        for x in np.arange(x_back + 8, x_front - 8, 10.0):
            w = hull_width(x)
            for s in (1, -1):
                if half - w > 0.5:
                    S.cyl((x, y - thick, s * (half - 0.6)), (x, y - thick - 2.5, s * min(w, half - 0.6)), 0.15, n=6, caps=False)


def island(S, P, x, y, half, L, levels=3, lvl_h=2.6, funnel_h=9.0, z=None, funnel=True):
    """Starboard island on a carrier: stacked blocks, a funnel behind, a mast."""
    zc = z if z is not None else half
    plan = [(x + L / 2, zc - half * 0.5), (x + L / 2, zc + half * 0.5), (x - L / 2, zc + half * 0.5), (x - L / 2, zc - half * 0.5)]
    y1 = y
    for k in range(levels):
        sh = 0.0 if k == 0 else 0.6 * k
        S.set_mat(P['sup'])
        S.prism([(px - (sh if px > x else -sh * 0.3), pz) for px, pz in plan], y1, y1 + lvl_h)
        y1 += lvl_h
    S.set_mat(P['glass'])
    S.prism([(px - 1.5, pz) for px, pz in plan], y1, y1 + 0.9)
    if funnel:
        fx = x - L / 2 - 3.0
        S.set_mat(P['sup'])
        S.prism([(fx + 2.0, zc - half * 0.4), (fx + 2.0, zc + half * 0.4), (fx - 2.5, zc + half * 0.4), (fx - 2.5, zc - half * 0.4)], y, y + funnel_h)
        S.set_mat(P['black'])
        S.prism([(fx + 2.1, zc - half * 0.42), (fx + 2.1, zc + half * 0.42), (fx - 2.6, zc + half * 0.42), (fx - 2.6, zc - half * 0.42)], y + funnel_h, y + funnel_h + 0.6)
    return y1 + 0.9


# =====================================================================
# submarines
# =====================================================================

def sub_hull(M, P, L, r, casing_half, deck_y, sail_x, sail_L, sail_h, sail_half=1.4, cut_down=False, name='Hull'):
    H = Builder(M, name, P['hull'])
    XB, XS = L / 2, -L / 2
    n = 40
    xs = np.linspace(XS, XB, n)
    def rad(x):
        t = abs(x) / (L / 2)
        return r * (1 - t ** 3.0) ** 0.5 * (0.98 if x < 0 else 1.0)
    rings = []
    for x in xs:
        rr = max(rad(x), 0.05)
        rings.append([(x, -r * 0.55 + np.sin(a) * rr * 1.05, np.cos(a) * rr) for a in np.linspace(0, 2 * np.pi, 16, endpoint=False)])
    for a, b in zip(rings[:-1], rings[1:]):
        for i in range(16):
            j = (i + 1) % 16
            y = (a[i][1] + a[j][1]) / 2
            H.set_mat(P['bottom'] if y < -0.6 else P['hull'])
            H.quad(a[i], a[j], b[j], b[i])
    # flat wooden casing (deck) along the top
    D = Builder(M, name, P['wood'] if 'wood' in P else P['deck'])
    plan = []
    for x in np.linspace(XS + 2, XB - 2, 30):
        plan.append((x, casing_half * (1 - (abs(x) / (L / 2)) ** 4)))
    plan += [(x, -w) for x, w in plan[::-1]]
    D.prism(plan, deck_y - 0.5, deck_y)
    # conning tower / fairwater
    S = Builder(M, name, P['sup'])
    sail = [(sail_x + sail_L / 2, 0), (sail_x + sail_L / 2 - 1.5, sail_half), (sail_x - sail_L / 2, sail_half * 0.8), (sail_x - sail_L / 2, -sail_half * 0.8), (sail_x + sail_L / 2 - 1.5, -sail_half)]
    S.prism(sail, deck_y, deck_y + sail_h * (0.55 if cut_down else 1.0), inset=0.15)
    S.set_mat(P['dark'])
    for dx, hh in [(0.5, 4.5), (-1.0, 4.0)]:
        S.cyl((sail_x + dx, deck_y + sail_h * 0.5, 0), (sail_x + dx, deck_y + sail_h + hh, 0), 0.14, 0.1, n=8)
    return H


# =====================================================================
# the spec builder
# =====================================================================

def build_spec(spec, scheme=None):
    """Build a Mesh from a class spec dict. Keys used:
    nation, L, B (full beam), T, deck (sheer fwd/mid/aft heights), breaks [(x, step)], bow, stern, bulge,
    bollards, vents, parts: list of (kind, args...) built in order, weapons: list of (kind, name, args...)."""
    P = dict(PAL[scheme or spec['nation']])
    P.update(spec.get('palette', {}))
    M = Mesh()
    L, B, T = spec['L'], spec['B'] / 2, spec['T']
    deck = spec.get('deck_fn') or sheer(*spec['deck'], L, spec.get('breaks'))
    hull = WarHull(L, B, T, deck, breaks=[b[0] for b in spec.get('breaks', [])], rake=spec.get('rake', 4.0),
                   entry=spec.get('entry', 0.34), run=spec.get('run', 0.30), flare=spec.get('flare', 0.22), stern=spec.get('stern', 'cruiser'),
                   bulge=spec.get('bulge', 0.0), fine=spec.get('fine', 2.1), clipper=spec.get('clipper', 0.0))
    if spec.get('sub'):
        sub_hull(M, P, L, spec['B'] / 2, spec['sub']['casing'], spec['sub']['deck_y'], spec['sub']['sail_x'], spec['sub']['sail_L'], spec['sub']['sail_h'], cut_down=spec['sub'].get('cut_down', False))
        dy = lambda x: spec['sub']['deck_y']
    else:
        hull.build(M, P, deck_mat=P.get(spec.get('deck_mat', 'deck')))
        dy = deck
        F = Builder(M, 'Hull', P['gun'])
        anchors_and_bollards(F, hull, P, spec.get('bollards', []))
        ventilators(F, P, spec.get('vents', []), dy)
        hull.rails(M, P, skip=spec.get('rail_skip', []))
    S = Builder(M, 'Hull', P['sup'])
    ctx = {'M': M, 'P': P, 'S': S, 'hull': hull, 'dy': dy}
    for part in spec.get('parts', []):
        kind, args = part[0], part[1:]
        PARTS[kind](ctx, *args)
    for w in spec.get('weapons', []):
        kind, name, args = w[0], w[1], w[2:]
        WEAPONS[kind](ctx, name, *args)
    return M


# part helpers take the context then the spec arguments
def _deckhouse(c, x_front, x_back, half, y0, y1, r=2.5):
    deckhouse(c['S'], c['P'], x_front, x_back, half, y0, y1, r_front=r)
def _block(c, x_front, x_back, half, y0, y1, mat=None):
    block(c['S'], c['P'], x_front, x_back, half, y0, y1, mat=c['P'][mat] if mat else None)
def _glass(c, x_front, x_back, half, y0, h=0.9):
    block(c['S'], c['P'], x_front, x_back, half, y0, y0 + h, mat=c['P']['glass'])
def _platform(c, x_front, x_back, z0, z1, y):
    platform(c['S'], c['P'], x_front, x_back, z0, z1, y)
def _funnel(c, x, base, h, rx, rz, rake=0.9, trunk=False):
    funnel(c['S'], c['P'], x, base, h, rx, rz, rake=rake, trunk=trunk)
def _funnel_down(c, x, y, z, h, r, side=1):
    funnel_downturned(c['S'], c['P'], x, y, z, h, r, side)
def _pole(c, x, y0, h, yard=4.0):
    mast_pole(c['S'], c['P'], x, y0, h, yard=yard)
def _tripod(c, x, y0, h, spread=3.0, yard=5.0):
    mast_tripod(c['S'], c['P'], x, y0, h, spread=spread, yard=yard)
def _lattice(c, x, y0, h, w=2.2):
    mast_lattice(c['S'], c['P'], x, y0, h, w)
def _bedspring(c, x, y, w=4.0, h=2.0):
    radar_bedspring(c['S'], c['P'], x, y, w, h)
def _radome(c, x, y):
    radome(c['S'], c['P'], x, y)
def _tower(c, x, y0, h, half, levels=4, taper=0.08):
    """Stacked tower bridge (US fast battleships: a smooth tower; IJN: pagoda when taper is high)."""
    S, P = c['S'], c['P']
    y = y0
    lh = h / levels
    for k in range(levels):
        hh = half * (1 - taper * k)
        S.set_mat(P['sup'])
        S.prism(rounded_plan(x + hh * 1.3, x - hh * 1.1, hh, hh * 0.8), y, y + lh - 0.15)
        # platforms sticking out at each level (pagoda look)
        if taper > 0.1 and k > 0:
            S.prism(rounded_plan(x + hh * 1.5, x - hh * 1.4, hh * 1.25, hh), y + lh - 0.4, y + lh - 0.15)
        y += lh
    S.set_mat(P['glass'])
    S.prism(rounded_plan(x + half * 1.0, x - half * 0.9, half * (1 - taper * levels), half * 0.7), y - 0.15, y + 0.9)
    return y + 0.9
def _rangefinder(c, x, y0, h, half=1.8, arms=5.0):
    rangefinder_tower(c['S'], c['P'], x, y0, h, half, arms)
def _searchlight(c, x, y, z):
    searchlight(c['S'], c['P'], x, y, z)
def _boat(c, x, y, z, L=8.0, w=2.0):
    boat(c['S'], c['P'], x, y, z, L, w, davits=True, deck_y=c['dy'](x))
def _rafts(c, *items):
    rafts(c['S'], c['P'], items)
def _crane(c, x, y, z, h=9.0, reach=8.0, side=1):
    crane(c['S'], c['P'], x, y, z, h, reach, side)
def _catapult(c, x, y, z, L=20.0, angle=0.0):
    catapult(c['S'], c['P'], x, y, z, L, angle)
def _floatplane(c, x, y, z, heading=0.0, twin=False, span=11.0):
    floatplane(c['S'], c['P'], x, y, z, heading, span=span, twin_float=twin)
def _aircraft(c, x, y, z, heading=0.0, folded=False, span=12.0):
    aircraft(c['S'], c['P'], x, y, z, heading, span=span, folded=folded)
def _deck_park(c, x0, x1, y, cols, spacing=11.0, heading=0.0, folded=True):
    """Rows of folded aircraft parked between x0 and x1 (x1 > x0)."""
    for x in np.arange(x0, x1, spacing):
        for z in cols:
            aircraft(c['S'], c['P'], x, y, z, heading, span=12.0, folded=folded)
def _flight_deck(c, x_front, x_back, half, y, thick=1.2, elevators=(), nose=4.0, round_down=6.0):
    flight_deck(c['S'], c['P'], x_front, x_back, half, y, thick, round_down, nose, elevators=elevators, hull_width=c['hull'].width)
def _island(c, x, y, half, L, levels=3, funnel_h=9.0, z=None, funnel=True):
    island(c['S'], c['P'], x, y, half, L, levels, funnel_h=funnel_h, z=z, funnel=funnel)
def _hedgehog(c, x, y):
    hedgehog(c['S'], c['P'], x, y)
def _depth_charges(c, x_rack=None, k_guns=()):
    depth_charges(c['S'], c['P'], c['hull'], x_rack, k_guns)
def _hangar(c, x_front, x_back, half, y0, y1):
    """Carrier hangar: open-sided box between hull deck and flight deck."""
    block(c['S'], c['P'], x_front, x_back, half, y0, y1)
def _marking(c, x, y, z, lx, lz, mat='mark'):
    c['S'].set_mat(c['P'][mat]); c['S'].box((x, y, z), (lx, 0.04, lz))
def _disc(c, x, y, z, r, mat='red'):
    c['S'].set_mat(c['P'][mat]); c['S'].cyl((x, y - 0.02, z), (x, y + 0.03, z), r, n=24)
def _casemates(c, items, y):
    """Rows of hull-side casemate guns: items = [(x, z), ...] built into the hull (not turning)."""
    S, P = c['S'], c['P']
    for x, z in items:
        S.set_mat(P['sup'])
        S.box((x, y, z), (2.4, 1.6, 1.2))
        S.set_mat(P['dark'])
        S.cyl((x, y + 0.2, z), (x + 3.5 * (1 if z > 0 else 1), y + 0.3, z + np.sign(z) * 2.5), 0.09, 0.07, n=6)
def _box(c, x, y, z, sx, sy, sz, mat='sup'):
    c['S'].set_mat(c['P'][mat]); c['S'].box((x, y, z), (sx, sy, sz))
def _cyl(c, a, b, r0, r1=None, mat='sup'):
    c['S'].set_mat(c['P'][mat]); c['S'].cyl(a, b, r0, r1, n=12)

PARTS = {
    'deckhouse': _deckhouse, 'block': _block, 'glass': _glass, 'platform': _platform, 'funnel': _funnel, 'funnel_down': _funnel_down,
    'pole': _pole, 'tripod': _tripod, 'lattice': _lattice, 'bedspring': _bedspring, 'radome': _radome, 'tower': _tower,
    'rangefinder': _rangefinder, 'searchlight': _searchlight, 'boat': _boat, 'rafts': _rafts, 'crane': _crane, 'catapult': _catapult,
    'floatplane': _floatplane, 'aircraft': _aircraft, 'deck_park': _deck_park, 'flight_deck': _flight_deck, 'island': _island,
    'hedgehog': _hedgehog, 'depth_charges': _depth_charges, 'hangar': _hangar, 'marking': _marking, 'disc': _disc, 'casemates': _casemates,
    'box': _box, 'cyl': _cyl,
}


def _w_turret(c, name, x, y, face, cal, barrels):
    turret(c['M'], name, (x, y, 0.0), face, c['P'], cal, barrels)
def _w_dp_twin(c, name, x, y, z, face, cal=127):
    dp_twin(c['M'], name, (x, y, z), face, c['P'], cal=cal)
def _w_dp_single(c, name, x, y, z, face, cal=127, enclosed=True):
    dp_single(c['M'], name, (x, y, z), face, c['P'], cal=cal, enclosed=enclosed)
def _w_casemate(c, name, x, y, z, face):
    casemate_gun(c['M'], name, (x, y, z), face, c['P'])
def _w_torps(c, name, x, y, z, tubes=5, face=0.0, cover=False):
    torpedo_mount(c['M'], name, (x, y, z), c['P'], tubes=tubes, face=face, cover=cover)
def _w_bofors(c, name, x, y, z, face=0.0, tub=True, twin=False, sponson=False):
    if sponson:
        # gallery sponson hanging off the flight-deck edge
        c['S'].set_mat(c['P']['sup'])
        c['S'].box((x, y - 0.6, z), (6.0, 1.2, 5.0))
    bofors_quad(c['M'], name, (x, y, z), c['P'], face=face, tub=tub, twin=twin)
def _w_oerlikon(c, name, x, y, z, face):
    oerlikon(c['M'], name, (x, y, z), c['P'], face)
def _w_jp25(c, name, x, y, z, face=0.0, barrels=3):
    jp25_triple(c['M'], name, (x, y, z), c['P'], face, barrels)
def _w_director(c, name, x, y, z, radar=True, size=1.0):
    director(c['M'], name, (x, y, z), c['P'], radar=radar, size=size)

WEAPONS = {'turret': _w_turret, 'dp_twin': _w_dp_twin, 'dp_single': _w_dp_single, 'casemate': _w_casemate, 'torps': _w_torps,
           'bofors': _w_bofors, 'oerlikon': _w_oerlikon, 'jp25': _w_jp25, 'director': _w_director}
