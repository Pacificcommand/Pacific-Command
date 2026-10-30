"""Japanese merchant ships ("Maru") for convoys: a three-island cargo ship and an oil tanker.
Generic wartime types, real-world proportions in meters.
  Cargo maru:  LOA 110 m, beam 15.2 m, draft 6.5 m, about 5,000 GRT. Forecastle, midship
               castle with bridge and funnel, poop; four hatches, two masts with derricks.
  Tanker maru: LOA 125 m, beam 16.4 m, draft 7.5 m, about 7,000 GRT. Low cargo deck with a
               fore-and-aft catwalk, bridge amidships, engines and funnel aft.
Both carry a small deck gun on the poop, as most wartime marus did."""
import numpy as np
from geom import Mesh, Builder, rot_y

P = dict(hull='#3a3d3e', boot='#151616', bottom='#6a2c22', sup='#8e918b', sup2='#a7a89f', deck='#7a5d40', steel='#62665f',
         dark='#232525', black='#0c0c0c', tarp='#5f5a45', rail='#2b2d2d', glass='#2c3538', boat='#c9c8bd', red='#a63a2c',
         white='#dedbd2', pipe='#55595a', rust='#6e4630')


class Hull:
    """Ship hull from a plan function and a stepped deck line (islands)."""

    def __init__(self, L, half_beam, draft, deck_fn, breaks, bow_rake=6.0, entry=0.28, run=0.25):
        self.L, self.B, self.T = L, half_beam, draft
        self.XB, self.XS = L / 2, -L / 2
        self.deck_fn, self.breaks = deck_fn, sorted(breaks)
        self.rake, self.entry, self.run = bow_rake, entry, run

    def stem_x(self, y):
        top = self.deck_fn(self.XB - 0.5)
        f = np.clip((y + self.T) / (top + self.T), 0, 1)
        return self.XB - self.rake * (1 - f) ** 1.3

    def hb(self, x, y):
        L, B = self.L, self.B
        xs = self.stem_x(y)
        if x >= xs:
            return 0.0
        xe = self.XB - self.entry * L          # end of parallel body forward
        xr = self.XS + self.run * L            # start of run aft
        if x > xe:
            t = (x - xe) / (xs - xe)
            w = B * (1 - t ** 1.8) ** 0.7
        elif x < xr:
            t = (xr - x) / (xr - self.XS)
            under = np.clip(-y / self.T, 0, 1)
            w = B * (1 - 0.35 * t ** 2) * (1 - 0.85 * t ** 1.4 * under ** 0.6)
        else:
            w = B
        if y < 0:                               # round the bilge
            d = -y / self.T
            w *= (1 - d ** 5) ** 0.2 if d < 1 else 0.0
        if y > 0 and x > xe:                    # flare at the bow
            w *= 1 + 0.06 * (y / (self.deck_fn(x) + 0.01)) * ((x - xe) / (xs - xe + 0.01))
        return max(w, 0.0)

    def build(self, M, deck_mat=None, levels=16):
        H = Builder(M, 'Hull', P['hull'])
        cuts = [self.XS] + self.breaks + [self.XB - 0.4]
        xs_list = []
        for a, b in zip(cuts[:-1], cuts[1:]):
            n = max(3, int((b - a) / 2.2))
            xs_list += list(np.linspace(a + 0.01, b - 0.01, n))
        xs_list += list(np.linspace(self.XB - 0.35, self.stem_x(self.deck_fn(self.XB)) - 0.05, 4))
        secs = []
        for x in xs_list:
            yd = self.deck_fn(x)
            secs.append([(x, y, self.hb(x, y)) for y in np.linspace(-self.T, yd, levels)])
        self.secs = secs
        for a, b in zip(secs[:-1], secs[1:]):
            # step between deck levels at an island break
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
                # hull sides: only up to the lower deck height across the step
                top = min(a[-1][1], b[-1][1])
                aa = [(x, min(y, top), self.hb(x, min(y, top))) for x, y, _ in a]
                bb = [(x, min(y, top), self.hb(x, min(y, top))) for x, y, _ in b]
                self._side(H, aa, bb, levels)
                continue
            self._side(H, a, b, levels)
        # stem closing strip
        last = secs[-1]
        for k in range(levels - 1):
            y0, y1 = last[k][1], last[k + 1][1]
            H.set_mat(self._mat(y0))
            for s in (1, -1):
                H.quad((last[k][0], y0, s * last[k][2]), (self.stem_x(y0), y0, 0), (self.stem_x(y1), y1, 0), (last[k + 1][0], y1, s * last[k + 1][2]))
        # transom (counter stern)
        st = secs[0]
        for k in range(levels - 1):
            H.set_mat(self._mat(st[k][1]))
            H.quad((st[k][0], st[k][1], -st[k][2]), (st[k][0], st[k][1], st[k][2]), (st[k + 1][0], st[k + 1][1], st[k + 1][2]), (st[k + 1][0], st[k + 1][1], -st[k + 1][2]))
        # decks
        D = Builder(M, 'Hull', deck_mat or P['deck'])
        for a, b in zip(secs[:-1], secs[1:]):
            if abs(a[-1][1] - b[-1][1]) > 0.3:
                continue
            for k in range(6):
                z0, z1 = -1 + k / 3, -1 + (k + 1) / 3
                cam = lambda z: 0.2 * (1 - z * z)
                D.quad((a[-1][0], a[-1][1] + cam(z0), z0 * a[-1][2]), (b[-1][0], b[-1][1] + cam(z0), z0 * b[-1][2]),
                       (b[-1][0], b[-1][1] + cam(z1), z1 * b[-1][2]), (a[-1][0], a[-1][1] + cam(z1), z1 * a[-1][2]))
        l = secs[-1][-1]
        D.tri((l[0], l[1], -l[2]), (self.stem_x(l[1]), l[1], 0), (l[0], l[1], l[2]))
        return H

    def _mat(self, y):
        return P['bottom'] if y < -0.4 else (P['boot'] if y < 0.6 else P['hull'])

    def _side(self, H, a, b, levels):
        for k in range(levels - 1):
            H.set_mat(self._mat(a[k][1]))
            for s in (1, -1):
                H.quad((a[k][0], a[k][1], s * a[k][2]), (b[k][0], b[k][1], s * b[k][2]), (b[k + 1][0], b[k + 1][1], s * b[k + 1][2]), (a[k + 1][0], a[k + 1][1], s * a[k + 1][2]))

    def width(self, x):
        return self.hb(x, self.deck_fn(x))

    def rails(self, M, skip=()):
        R = Builder(M, 'Hull', P['rail'])
        for s in (1, -1):
            prev = None
            for x in np.arange(self.XS + 1.0, self.XB - 3.0, 2.0):
                if any(abs(x - b) < 1.0 for b in self.breaks):
                    prev = None
                    continue
                y = self.deck_fn(x); z = s * (self.width(x) - 0.15)
                R.box((x, y + 0.5, z), (0.06, 1.0, 0.06))
                if prev is not None:
                    a, b = (prev[0], prev[1] + 1.0, prev[2]), (x, y + 1.0, z)
                    R.quad(a, b, (b[0], b[1] + 0.04, b[2]), (a[0], a[1] + 0.04, a[2]))
                prev = (x, y, z)


def funnel(S, x, y0, h, rx, rz, band=True):
    ring = lambda y, k: [(x + np.cos(t) * rx * k, y, np.sin(t) * rz * k) for t in np.linspace(0, 2 * np.pi, 24, endpoint=False)]
    def band_(ya, yb, mat):
        S.set_mat(mat)
        lo, hi = ring(ya, 1.0), ring(yb, 1.0)
        for i in range(24):
            j = (i + 1) % 24
            S.quad(lo[i], lo[j], hi[j], hi[i])
    band_(y0, y0 + h * 0.62, P['sup2'])
    if band:
        band_(y0 + h * 0.62, y0 + h * 0.8, P['white'])
        S.set_mat(P['red']); S.box((x, y0 + h * 0.71, rz + 0.01), (1.4, 1.0, 0.04)); S.box((x, y0 + h * 0.71, -rz - 0.01), (1.4, 1.0, 0.04))
    band_(y0 + h * (0.8 if band else 0.62), y0 + h, P['black'])
    S.set_mat(P['black']); S.capfan(ring(y0 + h - 0.3, 0.92))


def cowl(S, x, y, z, face):
    S.set_mat(P['sup2']); S.cyl((x, y, z), (x, y + 2.0, z), 0.35, n=10)
    S.set_mat(P['dark']); S.cyl((x, y + 2.0, z), (x + np.cos(face) * 0.4, y + 2.4, z + np.sin(face) * 0.4), 0.55, 0.6, n=10)


def mast(M, x, y0, h, booms, mat='dark'):
    T = Builder(M, 'Hull', P[mat])
    T.cyl((x, y0, 0), (x, y0 + h, 0), 0.35, 0.18, n=10)
    T.box((x, y0 + h * 0.7, 0), (0.3, 0.25, 5.0))           # crosstree
    for s in (1, -1):
        T.cyl((x - 1.5, y0, s * 6.5), (x, y0 + h * 0.7, s * 2.4), 0.04, n=4, caps=False)   # shrouds
        T.cyl((x + 1.5, y0, s * 6.5), (x, y0 + h * 0.7, s * 2.4), 0.04, n=4, caps=False)
    for (dx, dz) in booms:
        # cargo derricks resting down toward the hatch
        T.cyl((x + np.sign(dx) * 0.4, y0 + 1.2, dz * 0.3), (x + dx, y0 + 4.0, dz), 0.16, 0.1, n=6)


def hatch(S, x, y, lx, lz, tarp=True):
    S.set_mat(P['steel']); S.box((x, y + 0.6, 0), (lx, 1.2, lz))
    if tarp:
        S.set_mat(P['tarp']); S.box((x, y + 1.25, 0), (lx - 0.2, 0.12, lz - 0.2))
        S.set_mat(P['dark'])
        for k in range(1, 4):
            S.box((x - lx / 2 + k * lx / 4, y + 1.33, 0), (0.08, 0.04, lz - 0.1))


def deck_gun(M, name, pos, face):
    """Old 8 cm or 12 cm gun fitted to merchant ships for self-defence."""
    G = Builder(M, name, P['steel'], pivot=pos)
    G.xf = (rot_y(-face), np.array(pos))
    G.cyl((0, 0, 0), (0, 0.9, 0), 0.6, n=14)
    G.box((0.2, 1.3, 0), (1.6, 0.7, 0.9))
    G.box((0.7, 1.4, 0), (0.12, 1.2, 1.8))
    G.set_mat(P['dark']); G.cyl((1.0, 1.4, 0), (4.0, 1.45, 0), 0.1, n=8)


def lifeboat(B, x, y, z):
    pts = [(x + np.cos(t) * 3.4, z + np.sin(t) * 0.95) for t in np.linspace(0, 2 * np.pi, 18, endpoint=False)]
    B.set_mat(P['boat']); B.prism(pts, y, y + 0.9, inset=0.25)
    B.set_mat(P['tarp']); B.prism([(p[0] * .85 + x * .15, p[1] * .7 + z * .3) for p in pts], y + 0.9, y + 1.0)


# ======================================================================
def build_cargo():
    L = 110.0
    def deck(x):
        if x > 44.0:
            return 7.4 + 1.1 * ((x - 44) / 11.0) ** 2      # forecastle with sheer
        if -12.0 < x < 14.0:
            return 7.2                                     # midship castle
        if x < -44.0:
            return 7.2                                     # poop
        return 4.7 + 0.35 * abs(x) / 55.0                  # well decks
    h = Hull(L, 7.6, 6.5, deck, [-44.0, -12.0, 14.0, 44.0], bow_rake=5.5)
    M = Mesh()
    h.build(M)
    h.rails(M)
    S = Builder(M, 'Hull', P['sup'])
    # forecastle: windlass and anchor gear
    S.set_mat(P['dark']); S.box((49.5, deck(49.5) + 0.5, 0), (1.8, 1.0, 3.6))
    # hatches: two forward, two aft
    for x in (36.5, 23.5):
        hatch(S, x, deck(x), 8.5, 7.0)
    for x in (-21.5, -34.0):
        hatch(S, x, deck(x), 8.5, 7.0)
    # midship house: three tiers, wheelhouse with windows, bridge wings
    y0 = 7.2
    S.set_mat(P['sup']); S.box((1.0, y0 + 1.3, 0), (22.0, 2.6, 11.0))
    S.set_mat(P['deck']); S.box((1.0, y0 + 2.62, 0), (22.2, 0.06, 11.2))
    S.set_mat(P['sup']); S.box((7.2, y0 + 3.8, 0), (8.0, 2.4, 10.0))
    S.set_mat(P['sup2']); S.box((9.5, y0 + 6.0, 0), (3.2, 2.0, 7.0))
    S.set_mat(P['glass']); S.box((11.12, y0 + 6.3, 0), (0.05, 0.8, 6.4))
    S.set_mat(P['sup2']); S.box((9.8, y0 + 5.05, 0), (2.0, 0.12, 15.0))   # bridge wings
    S.set_mat(P['canvas'] if 'canvas' in P else P['tarp']); S.box((9.5, y0 + 7.05, 0), (3.4, 0.1, 7.2))
    S.set_mat(P['dark']); S.cyl((9.0, y0 + 7.1, 0), (9.0, y0 + 9.5, 0), 0.12, n=6)
    funnel(S, -3.5, y0 + 2.6, 9.5, 2.4, 1.9)
    for (x, z, f) in [(3.0, 3.5, 0.0), (3.0, -3.5, 0.0), (-8.0, 4.0, np.pi), (-8.0, -4.0, np.pi)]:
        cowl(S, x, y0 + 2.6, z, f)
    B = Builder(M, 'Hull', P['boat'])
    for x in (-6.5, 1.5):
        for s in (1, -1):
            lifeboat(B, x, y0 + 2.9, s * 5.0)
    # kingposts at the castle ends and masts with derricks over the hatches
    K = Builder(M, 'Hull', P['dark'])
    for x in (13.0, -11.0, -43.0):
        for s in (1, -1):
            K.cyl((x, deck(x), s * 3.2), (x, deck(x) + 10.0, s * 3.2), 0.25, 0.18, n=8)
    mast(M, 30.0, deck(30.0), 24.0, [(5.5, 2.4), (5.5, -2.4), (-5.5, 2.4), (-5.5, -2.4)])
    mast(M, -28.0, deck(-28.0), 22.0, [(5.5, 2.4), (5.5, -2.4), (-5.5, 2.4), (-5.5, -2.4)])
    # poop deckhouse, steering engine, gun
    S.set_mat(P['sup']); S.box((-48.0, 7.2 + 1.1, 0), (6.0, 2.2, 8.0))
    deck_gun(M, 'Gun1', (-51.5, 7.2, 0.0), np.pi)
    mg_mount(M, 'AA1', (9.5, y0 + 7.15, 2.5))
    return M


def build_tanker():
    L = 125.0
    def deck(x):
        if x > 51.0:
            return 6.6 + 1.0 * ((x - 51) / 11.5) ** 2      # forecastle
        if -3.0 < x < 9.0:
            return 6.8                                     # bridge island
        if x < -42.0:
            return 6.8                                     # poop with engines
        return 4.2                                         # low tank deck
    h = Hull(L, 8.2, 7.5, deck, [-42.0, -3.0, 9.0, 51.0], bow_rake=6.0, entry=0.22, run=0.2)
    M = Mesh()
    h.build(M, deck_mat=P['steel'])
    h.rails(M)
    S = Builder(M, 'Hull', P['sup'])
    # expansion trunk and tank hatches along the cargo deck
    for a, b in [(10.5, 49.5), (-40.5, -4.5)]:
        S.set_mat(P['steel']); S.box(((a + b) / 2, 4.2 + 0.45, 0), (b - a, 0.9, 5.0))
        S.set_mat(P['dark'])
        for x in np.arange(a + 3, b - 1, 6.0):
            for s in (1, -1):
                S.cyl((x, 4.2, s * 4.6), (x, 4.6, s * 4.6), 0.55, n=12)
    # cargo pipes alongside the trunk
    S.set_mat(P['pipe'])
    for z in (3.2, -3.2, 3.8, -3.8):
        S.cyl((-41.0, 4.45, z), (50.0, 4.45, z), 0.15, n=6, caps=False)
    # fore-and-aft catwalk on posts
    C = Builder(M, 'Hull', P['rust'])
    for a, b in [(9.0, 51.0), (-42.0, -3.0)]:
        C.box(((a + b) / 2, 6.8, 0), (b - a, 0.12, 1.3))
        C.set_mat(P['dark'])
        for x in np.arange(a + 2, b - 1, 4.0):
            C.cyl((x, 5.1, 0), (x, 6.75, 0), 0.08, n=5)
        C.set_mat(P['rust'])
    # bridge island amidships
    y0 = 6.8
    S.set_mat(P['sup']); S.box((3.0, y0 + 1.3, 0), (10.0, 2.6, 12.0))
    S.box((4.0, y0 + 3.6, 0), (7.0, 2.0, 10.5))
    S.set_mat(P['sup2']); S.box((5.5, y0 + 5.6, 0), (3.0, 2.0, 7.5))
    S.set_mat(P['glass']); S.box((7.02, y0 + 5.9, 0), (0.05, 0.8, 7.0))
    S.set_mat(P['sup2']); S.box((5.8, y0 + 4.65, 0), (1.8, 0.12, 16.0))
    # engine house aft with the funnel
    S.set_mat(P['sup']); S.box((-51.0, y0 + 1.5, 0), (16.0, 3.0, 13.0))
    S.box((-53.0, y0 + 3.9, 0), (10.0, 1.8, 10.0))
    funnel(S, -53.5, y0 + 4.8, 8.0, 2.6, 2.1)
    for (x, z) in [(-46.0, 4.0), (-46.0, -4.0), (-58.0, 4.5), (-58.0, -4.5)]:
        cowl(S, x, y0 + 3.0, z, 0.0)
    B = Builder(M, 'Hull', P['boat'])
    for s in (1, -1):
        lifeboat(B, -50.0, y0 + 3.1, s * 5.8)
    # masts with hose derricks
    mast(M, 47.0, deck(47.0), 18.0, [(-6.0, 2.0), (-6.0, -2.0)])
    mast(M, -36.0, deck(-36.0), 16.0, [(6.0, 2.0), (6.0, -2.0)])
    deck_gun(M, 'Gun1', (-59.0, y0, 0.0), np.pi)
    mg_mount(M, 'AA1', (5.5, y0 + 6.65, 2.6))
    return M


def mg_mount(M, name, pos):
    G = Builder(M, name, P['steel'], pivot=pos)
    G.xf = (np.eye(3), np.array(pos))
    G.cyl((0, 0, 0), (0, 0.8, 0), 0.08, n=6)
    G.set_mat(P['dark']); G.box((0.2, 0.9, 0), (0.9, 0.15, 0.15)); G.cyl((0.6, 0.9, 0), (1.6, 0.92, 0), 0.04, n=5)
