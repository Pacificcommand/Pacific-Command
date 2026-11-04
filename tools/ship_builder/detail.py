"""Surface and small-detail helpers shared by every class: paint (camouflage, plating shades,
weathering), portholes, doors, ladders, hatches, lockers, rafts, rigging, railings.
Everything here is cheap in triangles: the battle view is top-down and big fights must stay smooth,
so the detail is mostly flat quads laid on the surfaces, not extra solids."""
import numpy as np


def shade(hexcol, k):
    """Lighten (k > 1) or darken (k < 1) a #rrggbb colour."""
    h = hexcol.lstrip('#')
    rgb = [min(255, max(0, int(round(int(h[i:i + 2], 16) * k)))) for i in (0, 2, 4)]
    return '#%02x%02x%02x' % tuple(rgb)


def mix(a, b, t):
    ha, hb = a.lstrip('#'), b.lstrip('#')
    rgb = [int(round(int(ha[i:i + 2], 16) * (1 - t) + int(hb[i:i + 2], 16) * t)) for i in (0, 2, 4)]
    return '#%02x%02x%02x' % tuple(rgb)


def _hash(*vals):
    """Deterministic 0..1 from integers (so a rebuild gives the same ship)."""
    h = 2166136261
    for v in vals:
        h = (h ^ (int(v) & 0xffffffff)) * 16777619 & 0xffffffff
    return ((h >> 8) & 0xffff) / 65536.0


# ---------------------------------------------------------------------
# paint
# ---------------------------------------------------------------------

class Paint:
    """Returns the material for a triangle from its base material and centroid.
    - hull plating: plates of slightly different shade (weathered paint)
    - weathering: rust streaks near the waterline and under the anchors, soot behind funnels
    - dazzle: Measure 32-style bands over hull and superstructure when scheme == 'dazzle'
    """

    def __init__(self, P, L, freeboard, scheme='plain', seed=7):
        self.P = P
        self.L = L
        self.H = max(freeboard, 4.0)
        self.scheme = scheme
        self.seed = seed
        self.hull = P['hull']
        self.sup = P['sup']
        self.gun = P.get('gun', P['sup'])
        # plating shades
        self.hull_sh = [P['hull'], shade(P['hull'], 1.07), shade(P['hull'], 0.94), shade(P['hull'], 1.03)]
        self.sup_sh = [P['sup'], shade(P['sup'], 1.05), shade(P['sup'], 0.95)]
        self.rust = '#5a3a28'
        self.streak = mix(P['hull'], '#4a3a30', 0.45)
        # dazzle bands: Measure 32 colours (light gray 5-L, ocean gray 5-O, dull black BK)
        rng = np.random.RandomState(seed)
        self.cols = ['#a9b2b6', '#616c74', '#2e363e']
        edges = np.sort(rng.uniform(-1.6, 1.6, 9))
        self.edges = edges
        self.slant = rng.uniform(0.25, 0.45)
        self.funnels = []      # x positions of funnels for soot

    def u_of(self, x, y):
        return x / self.L * 2.0 + self.slant * (y / self.H)

    def band(self, x, y):
        k = int(np.searchsorted(self.edges, self.u_of(x, y)))
        return self.cols[(k * 2 + (k // 3)) % 3]

    def split_tri(self, mat, t):
        """Cut a triangle along the dazzle band edges it crosses so the pattern has straight,
        sharp boundaries instead of following the mesh. Returns a list of triangles or None."""
        if self.scheme != 'dazzle' or mat not in (self.hull, self.sup, self.gun):
            return None
        if mat == self.hull and t[:, 1].max() < 0.5:
            return None
        us = [self.u_of(p[0], p[1]) for p in t]
        lo, hi = min(us), max(us)
        cuts = [e for e in self.edges if lo < e < hi]
        if not cuts:
            return None
        polys = [[(np.array(p), u) for p, u in zip(t, us)]]
        for e in cuts:
            nxt = []
            for poly in polys:
                below, above = [], []
                n = len(poly)
                for i in range(n):
                    a, ua = poly[i]
                    b, ub = poly[(i + 1) % n]
                    (below if ua <= e else above).append((a, ua))
                    if (ua - e) * (ub - e) < 0:
                        f = (e - ua) / (ub - ua)
                        m = a + (b - a) * f
                        below.append((m, e)); above.append((m, e))
                for part in (below, above):
                    if len(part) >= 3:
                        nxt.append(part)
            polys = nxt
        out = []
        for poly in polys:
            pts = [p for p, _ in poly]
            for i in range(1, len(pts) - 1):
                out.append(np.array([pts[0], pts[i], pts[i + 1]]))
        return out

    def __call__(self, mat, c):
        x, y, z = c
        if mat == self.hull:
            if self.scheme == 'dazzle' and y > 0.5:
                base = self.band(x, y)
            else:
                i = int(_hash(self.seed, np.floor(x / 5.0), np.floor(y / 1.6), 1 if z > 0 else 0) * 10)
                base = self.hull_sh[[0, 0, 0, 0, 1, 1, 2, 2, 3, 3][i]]
            # rust streaks running down from the deck edge, more toward the bow and stern
            if 0.2 < y < self.H + 2.0:
                r = _hash(self.seed + 1, np.floor(x / 1.6), 1 if z > 0 else 0)
                edge = abs(x) / (self.L / 2)
                if r < 0.05 + 0.10 * edge ** 2:
                    return mix(base, self.rust, 0.35 if y > 0.9 else 0.6)
            return base
        if mat == self.sup:
            if self.scheme == 'dazzle':
                base = self.band(x, y)
            else:
                i = int(_hash(self.seed + 2, np.floor(x / 4.0), np.floor(y / 2.0), np.floor(z / 3.0)) * 6)
                base = self.sup_sh[[0, 0, 0, 1, 2, 0][i]]
            # soot on things close behind a funnel top
            for fx, fy in self.funnels:
                if -9.0 < x - fx < -1.0 and abs(z) < 4.0 and y > fy - 3.0:
                    return mix(base, '#1c1c1c', 0.35)
            return base
        if mat == self.gun and self.scheme == 'dazzle':
            return self.band(x, y)
        return mat


# ---------------------------------------------------------------------
# flat details laid on surfaces (2 triangles each)
# ---------------------------------------------------------------------

def _facing_quad(B, c, w, h, normal):
    """A w x h rectangle centred at c, facing `normal` (one of 'x+', 'x-', 'z+', 'z-')."""
    x, y, z = c
    e = 0.025   # stand-off so it draws over the surface
    if normal == 'z+':
        B.quad((x - w / 2, y - h / 2, z + e), (x + w / 2, y - h / 2, z + e), (x + w / 2, y + h / 2, z + e), (x - w / 2, y + h / 2, z + e))
    elif normal == 'z-':
        B.quad((x + w / 2, y - h / 2, z - e), (x - w / 2, y - h / 2, z - e), (x - w / 2, y + h / 2, z - e), (x + w / 2, y + h / 2, z - e))
    elif normal == 'x+':
        B.quad((x + e, y - h / 2, z + w / 2), (x + e, y - h / 2, z - w / 2), (x + e, y + h / 2, z - w / 2), (x + e, y + h / 2, z + w / 2))
    else:
        B.quad((x - e, y - h / 2, z - w / 2), (x - e, y - h / 2, z + w / 2), (x - e, y + h / 2, z + w / 2), (x - e, y + h / 2, z - w / 2))


def _facing_disc(B, c, r, normal, n=8):
    x, y, z = c
    e = 0.025
    pts = []
    for i in range(n):
        a = i / n * 2 * np.pi
        if normal in ('z+', 'z-'):
            pts.append((x + np.cos(a) * r, y + np.sin(a) * r, z + (e if normal == 'z+' else -e)))
        else:
            pts.append((x + (e if normal == 'x+' else -e), y + np.sin(a) * r, z + np.cos(a) * r))
    if normal in ('z-', 'x+'):
        pts = pts[::-1]
    B.poly(pts)


def portholes(B, P, pts, normal, size=0.42):
    """Round scuttles: a dark octagon with a faint brass-grey rim."""
    B.raw = True
    rim = mix(P['hull'], P['rim'], 0.3)
    for c in pts:
        B.set_mat(rim)
        _facing_disc(B, c, size * 0.5 * 1.3, normal)
        B.set_mat(P['glass'])
        x, y, z = c
        e = 0.03
        c2 = (x + (e if normal == 'x+' else -e if normal == 'x-' else 0), y, z + (e if normal == 'z+' else -e if normal == 'z-' else 0))
        _facing_disc(B, c2, size * 0.5, normal)
    B.raw = False


def door(B, P, c, normal, w=0.75, h=1.75):
    B.raw = True
    B.set_mat(P['dark'])
    _facing_quad(B, c, w, h, normal)
    B.set_mat(P['rim'])
    x, y, z = c
    _facing_quad(B, (x, y - h * 0.46, z), w * 0.9, 0.08, normal)   # sill
    B.raw = False


def ladder(B, P, c, normal, h, w=0.5):
    """Vertical ladder on a wall: two rails and rungs as flat quads."""
    B.raw = True
    B.set_mat(P['dark'])
    x, y, z = c
    if normal in ('z+', 'z-'):
        for s in (-1, 1):
            _facing_quad(B, (x + s * w / 2, y, z), 0.06, h, normal)
        for k in range(int(h / 0.32)):
            _facing_quad(B, (x, y - h / 2 + 0.16 + k * 0.32, z), w, 0.05, normal)
    else:
        for s in (-1, 1):
            _facing_quad(B, (x, y, z + s * w / 2), 0.06, h, normal)
        for k in range(int(h / 0.32)):
            _facing_quad(B, (x, y - h / 2 + 0.16 + k * 0.32, z), w, 0.05, normal)
    B.raw = False


def window_strip(B, P, x0, x1, y, z, normal, h=0.7, pitch=1.1):
    """A row of bridge windows along x on a wall at z."""
    B.raw = True
    B.set_mat(P['glass'])
    for x in np.arange(x0 + 0.6, x1 - 0.3, pitch):
        _facing_quad(B, (x, y, z), pitch * 0.7, h, normal)
    B.raw = False


# ---------------------------------------------------------------------
# small solids
# ---------------------------------------------------------------------

def hatch(B, P, x, y, z, L=1.6, w=1.3, h=0.35, along_x=True):
    B.set_mat(P['dark'])
    B.box((x, y + h / 2, z), (L, h, w) if along_x else (w, h, L), top_inset=0.1)


def locker(B, P, x, y, z, L=1.2, w=0.7, h=0.9):
    B.set_mat(P['sup'])
    B.box((x, y + h / 2, z), (L, h, w))
    B.raw = True
    B.set_mat(P['dark'])
    B.box((x, y + h + 0.02, z), (L * 1.04, 0.04, w * 1.04))
    B.raw = False


def raft(B, P, x, y, z, along_x=True, L=2.8, w=1.3, t=0.35):
    """Balsa life raft: an oval ring with a lashed floor, hung flat on a wall or lying on deck."""
    B.set_mat(P['raft'])
    pts = [(x + np.cos(a) * L / 2, z + np.sin(a) * w / 2) for a in np.linspace(0, 2 * np.pi, 10, endpoint=False)]
    inner = [(x + np.cos(a) * (L / 2 - 0.4), z + np.sin(a) * (w / 2 - 0.4)) for a in np.linspace(0, 2 * np.pi, 10, endpoint=False)]
    for i in range(10):
        j = (i + 1) % 10
        B.quad((pts[i][0], y + t, pts[i][1]), (pts[j][0], y + t, pts[j][1]), (inner[j][0], y + t, inner[j][1]), (inner[i][0], y + t, inner[i][1]))
        B.quad((pts[j][0], y, pts[j][1]), (pts[i][0], y, pts[i][1]), (pts[i][0], y + t, pts[i][1]), (pts[j][0], y + t, pts[j][1]))
    B.set_mat(P['dark'])
    B.capfan([(px, y + t * 0.5, pz) for px, pz in inner])


def raft_on_wall(B, P, x, y, z, side):
    """A raft hung vertically on a bulkhead whose outside faces +z (side=1) or -z (side=-1)."""
    B.set_mat(P['raft'])
    L, w, t = 2.4, 1.1, 0.3
    zz = z + side * t / 2
    pts = [(x + np.cos(a) * L / 2, y + np.sin(a) * w / 2) for a in np.linspace(0, 2 * np.pi, 10, endpoint=False)]
    inner = [(x + np.cos(a) * (L / 2 - 0.38), y + np.sin(a) * (w / 2 - 0.38)) for a in np.linspace(0, 2 * np.pi, 10, endpoint=False)]
    for i in range(10):
        j = (i + 1) % 10
        a, b = pts[i], pts[j]
        ia, ib = inner[i], inner[j]
        B.quad((a[0], a[1], zz + side * t / 2), (b[0], b[1], zz + side * t / 2), (ib[0], ib[1], zz + side * t / 2), (ia[0], ia[1], zz + side * t / 2))
        B.quad((a[0], a[1], z), (b[0], b[1], z), (b[0], b[1], zz + side * t / 2), (a[0], a[1], zz + side * t / 2))
    B.set_mat(P['dark'])
    B.capfan([(px, py, zz) for px, py in inner])


def capstan(B, P, x, y, z=0.0, r=0.55):
    B.set_mat(P['dark'])
    B.cyl((x, y, z), (x, y + 0.9, z), r * 0.8, r, n=12)
    B.cyl((x, y + 0.9, z), (x, y + 1.05, z), r * 1.1, r * 1.1, n=12)


def reel(B, P, x, y, z, r=0.5, w=1.0):
    """Cable or hose reel on deck."""
    B.set_mat(P['dark'])
    B.cyl((x, y + r + 0.1, z - w / 2), (x, y + r + 0.1, z + w / 2), r, n=10)
    for s in (-1, 1):
        B.box((x, y + r * 0.55, z + s * (w / 2 + 0.05)), (0.5, r * 1.1, 0.1))


def stays(B, P, top, feet, r=0.035):
    """Rigging: thin lines from a mast top to points on deck."""
    B.raw = True
    B.set_mat(P['rail'])
    for f in feet:
        B.cyl(top, f, r, r, n=3, caps=False)
    B.raw = False


def railing(B, P, pts, h=1.0, post_every=1, mid=True):
    """Railing along a polyline of (x, y, z) deck-edge points: stanchions, top rail, middle rail."""
    B.raw = True
    B.set_mat(P['rail'])
    for i, (x, y, z) in enumerate(pts):
        if i % post_every == 0:
            B.box((x, y + h / 2, z), (0.05, h, 0.05))
    for a, b in zip(pts[:-1], pts[1:]):
        B.quad((a[0], a[1] + h, a[2]), (b[0], b[1] + h, b[2]), (b[0], b[1] + h + 0.04, b[2]), (a[0], a[1] + h + 0.04, a[2]))
        if mid:
            B.quad((a[0], a[1] + h * 0.5, a[2]), (b[0], b[1] + h * 0.5, b[2]), (b[0], b[1] + h * 0.5 + 0.03, b[2]), (a[0], a[1] + h * 0.5 + 0.03, a[2]))
    B.raw = False
