"""Fletcher-class destroyer, 1943 fit, built at real dimensions (meters).
Sources for layout: plan drawings and photos in the Ship references tab (Fletcher DD-445, Fullam overhead, Charles Ausburne plan views).
LOA 114.8 m, beam 12.0 m, draft 4.2 m."""
import numpy as np
from geom import Mesh, Builder, rounded_plan, rot_y

LOA = 114.8
XB, XS = 57.4, -57.4          # bow (stem at deck), stern
BEAM = 6.0                     # half beam
DRAFT = 4.2

def deck_y(x):
    if x >= 0:
        return 4.1 + 2.6 * (x / XB) ** 2
    return 4.1 - 0.7 * (-x / -XS)

def stem_x(y):
    # raked stem: 57.4 at deck height, 53.5 at keel
    return 53.5 + (57.4 - 53.5) * np.clip((y + DRAFT) / (7.0 + DRAFT), 0, 1)

def half_breadth(x, y):
    """Half breadth of the hull at station x, height y."""
    yd = deck_y(x)
    # plan width at this height
    xs = stem_x(y)
    if x >= xs:
        return 0.0
    if x > 6:
        t = (x - 6) / (xs - 6)
        w = BEAM * (1 - t ** 2.1) ** 0.62
    elif x > -34:
        w = BEAM
    else:
        t = (x - -34) / (XS - -34)
        w = BEAM * (1 - 0.30 * t ** 1.6)
    # flare forward: narrower near the waterline than at the deck
    if x > 20 and y < yd:
        f = np.clip((x - 20) / 37, 0, 1)
        w *= 1 - 0.22 * f * np.clip((yd - y) / (yd + DRAFT), 0, 1)
    # bilge and run below water
    if y < 0:
        d = -y / DRAFT
        w *= (1 - d ** 3.2) ** (1 / 3.2) if d < 1 else 0.0
        if x < -36:
            t = (x + 36) / (XS + 36)
            w *= 1 - 0.75 * t * d ** 0.7
    return max(w, 0.0)

PAL = {
    'm22': dict(hull='#7d8890', deck='#3b4350', sup='#8a959c', gun='#8a959c', dark='#2a3036', bottom='#5a2a24', boot='#2b3a4c',
                wood='#8d7a5c', raft='#7a858c', black='#0b0b0b', rail='#2a3036', canvas='#9b9580', glass='#3a4850', light='#d8dee0', band='#2b3a4c'),
    'm21': dict(hull='#2d3a4a', deck='#3b4350', sup='#33404f', gun='#36434f', dark='#1b1f23', bottom='#5a2a24', boot='#151719',
                wood='#8d7a5c', raft='#5c6670', black='#0b0b0b', rail='#20262c', canvas='#7a7562', glass='#26323a', light='#c9d1d4'),
}

def build(scheme='m21', train=None):
    P = PAL[scheme]
    M = Mesh()
    H = Builder(M, 'Hull', P['hull'])

    # ---------------- hull ----------------
    xs_list = list(np.linspace(XS, 52.0, 96)) + list(np.linspace(52.4, 57.3, 12))
    levels = 18
    sections = []
    for x in xs_list:
        yd = deck_y(x)
        ys = np.linspace(-DRAFT, yd, levels)
        sections.append([(x, y, half_breadth(x, y)) for y in ys])
    for i in range(len(sections) - 1):
        a, b = sections[i], sections[i + 1]
        for k in range(levels - 1):
            ya = a[k][1]
            mat = P['bottom'] if ya < -0.05 else (P['boot'] if ya < 0.45 else (P['band'] if ('band' in P and ya < 3.35) else P['hull']))
            H.set_mat(mat)
            for s in (1, -1):
                H.quad((a[k][0], a[k][1], s * a[k][2]), (b[k][0], b[k][1], s * b[k][2]),
                       (b[k + 1][0], b[k + 1][1], s * b[k + 1][2]), (a[k + 1][0], a[k + 1][1], s * a[k + 1][2]))
    # stem closure: from last section to the stem line
    last = sections[-1]
    H.set_mat(P['hull'])
    for k in range(levels - 1):
        y0, y1 = last[k][1], last[k + 1][1]
        H.set_mat(P['bottom'] if y0 < -0.05 else P['hull'])
        for s in (1, -1):
            H.quad((last[k][0], y0, s * last[k][2]), (stem_x(y0), y0, 0), (stem_x(y1), y1, 0), (last[k + 1][0], y1, s * last[k + 1][2]))
    # transom
    st = sections[0]
    H.set_mat(P['hull'])
    for k in range(levels - 1):
        H.set_mat(P['bottom'] if st[k][1] < -0.05 else P['hull'])
        H.quad((XS, st[k][1], -st[k][2]), (XS, st[k][1], st[k][2]), (XS, st[k + 1][1], st[k + 1][2]), (XS, st[k + 1][1], -st[k + 1][2]))
    # deck with camber
    D = Builder(M, 'Hull', P['deck'])
    ncam = 8
    for i in range(len(sections) - 1):
        xa, xb = sections[i][-1][0], sections[i + 1][-1][0]
        wa, wb = sections[i][-1][2], sections[i + 1][-1][2]
        ya, yb = sections[i][-1][1], sections[i + 1][-1][1]
        for k in range(ncam):
            z0, z1 = -1 + 2 * k / ncam, -1 + 2 * (k + 1) / ncam
            cam = lambda z: 0.16 * (1 - z * z)
            D.quad((xa, ya + cam(z0), z0 * wa), (xb, yb + cam(z0), z0 * wb), (xb, yb + cam(z1), z1 * wb), (xa, ya + cam(z1), z1 * wa))
    xl = sections[-1][-1][0]; yl = sections[-1][-1][1]; wl = sections[-1][-1][2]
    D.tri((xl, yl, -wl), (stem_x(deck_y(XB)), deck_y(XB), 0), (xl, yl, wl))

    # ---------------- deck fittings ----------------
    F = Builder(M, 'Hull', P['gun'])
    dy = deck_y
    # breakwater ahead of mount 51
    F.set_mat(P['sup'])
    bw = [(46.5, 0), (43.0, 4.6)]
    for s in (1, -1):
        a = (bw[0][0], dy(46) + 0.05, 0); b = (bw[1][0], dy(43) + 0.05, s * bw[1][1])
        F.quad(a, b, (b[0], b[1] + 0.9, b[2]), (a[0], a[1] + 0.9, a[2]))
    # anchor windlass, capstan, chain
    F.set_mat(P['dark'])
    for s in (1, -1):
        F.cyl((50.5, dy(50.5), s * 1.3), (50.5, dy(50.5) + 0.5, s * 1.3), 0.45, n=14)
        F.cyl((53.5, dy(53.5) - 0.05, s * 1.5), (53.5, dy(53.5) + 0.06, s * 1.5), 0.35, n=12)
        for i in range(8):
            x = 53.3 - i * 0.35
            F.box((x, dy(x) + 0.04, s * (1.5 - i * 0.03)), (0.3, 0.08, 0.16))
    # bollards along the deck edges
    for x in [52, 44, 30, 12, -6, -24, -40, -52]:
        for s in (1, -1):
            z = s * (half_breadth(x, dy(x)) - 0.7)
            for dx in (-0.35, 0.35):
                F.cyl((x + dx, dy(x), z), (x + dx, dy(x) + 0.45, z), 0.16, n=8)
    # ventilators
    F.set_mat(P['sup'])
    for x, z in [(36, 3.2), (36, -3.2), (-14, 3.8), (-14, -3.8), (-48, 2.6), (-48, -2.6), (10, 4.2), (10, -4.2)]:
        F.cyl((x, dy(x), z), (x, dy(x) + 1.0, z), 0.32, n=10)
        F.cyl((x, dy(x) + 1.0, z), (x, dy(x) + 1.25, z), 0.42, 0.2, n=10)

    # ---------------- superstructure ----------------
    S = Builder(M, 'Hull', P['sup'])
    # forward deckhouse (01 level) carrying mount 52 and the bridge
    fwd = rounded_plan(34.5, 11.0, 4.6, 3.0)
    S.prism(fwd, dy(22) - 0.2, dy(22) + 2.5)
    L1 = dy(22) + 2.5
    # bridge levels with the round front
    S.prism(rounded_plan(27.0, 15.0, 4.2, 4.0), L1, L1 + 2.6)
    L2 = L1 + 2.6
    S.set_mat(P['glass'])
    S.prism(rounded_plan(26.6, 18.5, 3.9, 3.8), L2, L2 + 0.9)
    S.set_mat(P['sup'])
    S.prism(rounded_plan(26.4, 18.5, 3.9, 3.8), L2 + 0.9, L2 + 1.3)
    # open bridge wings
    for s in (1, -1):
        S.box((22.0, L2 + 0.1, s * 4.6), (3.2, 0.2, 1.6))
    # director platform pedestal
    S.cyl((21.2, L2 + 1.3, 0), (21.2, L2 + 2.6, 0), 1.6, n=18)
    L3 = L2 + 2.6
    # amidships casing between the funnels (01 level, narrower)
    mid = [(11.0, 3.3), (-11.0, 3.3), (-11.0, -3.3), (11.0, -3.3)]
    S.prism(mid, dy(0) - 0.2, dy(0) + 2.4)
    Lmid = dy(0) + 2.4
    # 40mm platform abreast forward funnel
    for s in (1, -1):
        S.prism([(5.5, s * 3.3), (0.5, s * 3.3), (0.5, s * 5.6), (5.5, s * 5.6)], Lmid - 0.25, Lmid)
    # searchlight platform aft of second funnel
    S.cyl((-11.5, Lmid, 0), (-11.5, Lmid + 2.2, 0), 1.3, n=16)
    # after deckhouse: 01 level for mount 54, 02 level for mount 53
    aft1 = [(-18.0, 3.6), (-38.5, 3.6), (-39.5, 2.6), (-39.5, -2.6), (-38.5, -3.6), (-18.0, -3.6)]
    S.prism(aft1, dy(-28) - 0.2, dy(-28) + 2.4)
    La1 = dy(-28) + 2.4
    aft2 = [(-23.0, 2.9), (-32.0, 2.9), (-32.5, 2.3), (-32.5, -2.3), (-32.0, -2.9), (-23.0, -2.9)]
    S.prism(aft2, La1, La1 + 2.3)
    La2 = La1 + 2.3
    # 40mm wings on the after deckhouse
    for s in (1, -1):
        S.prism([(-19.0, s * 3.6), (-23.5, s * 3.6), (-23.5, s * 5.4), (-19.0, s * 5.4)], La1 - 0.25, La1)

    # ---------------- funnels ----------------
    for fx, h in [(7.2, 9.0), (-7.4, 8.6)]:
        base = Lmid
        rake = 0.9
        ring = lambda y, k: [(fx - rake * (y - base) / h + np.cos(t) * 2.3 * k, y, np.sin(t) * 1.55 * k) for t in np.linspace(0, 2 * np.pi, 24, endpoint=False)]
        S.set_mat(P['sup'])
        lo, hi = ring(base, 1.0), ring(base + h, 0.97)
        for i in range(24):
            j = (i + 1) % 24
            S.quad(lo[i], lo[j], hi[j], hi[i])
        cap0, cap1 = ring(base + h, 1.04), ring(base + h + 0.6, 1.04)
        S.set_mat(P['dark'])
        for i in range(24):
            j = (i + 1) % 24
            S.quad(cap0[i], cap0[j], cap1[j], cap1[i])
        S.set_mat(P['black'])
        S.capfan(ring(base + h + 0.45, 0.92))
        # funnel cap grille
        S.set_mat(P['dark'])
        for k in range(-3, 4):
            S.box((fx - rake + k * 0.55, base + h + 0.62, 0), (0.06, 0.05, 2.6))

    # ---------------- mast and radar ----------------
    Mt = Builder(M, 'Hull', P['dark'])
    mx = 15.0
    top = L1 + 18.5
    Mt.cyl((mx, L1 + 2.6, 0), (mx, top, 0), 0.22, 0.12, n=10)
    for s in (1, -1):
        Mt.cyl((mx - 3.0, L1 + 2.6, s * 2.2), (mx, L1 + 11.0, 0), 0.10, n=6, caps=False)
    Mt.cyl((mx, L1 + 13.5, -4.0), (mx, L1 + 13.5, 4.0), 0.07, n=6)   # yardarm
    # SC air-search radar: a flat lattice "bedspring"
    Mt.set_mat(P['rail'])
    ry = L1 + 16.0
    for k in range(9):
        z = -2.0 + k * 0.5
        Mt.box((mx + 0.4, ry, z), (0.05, 2.0, 0.05))
    for k in range(5):
        Mt.box((mx + 0.4, ry - 1.0 + k * 0.5, 0), (0.05, 0.05, 4.0))
    # SG surface-search radome on the topmast
    Mt.set_mat(P['sup'])
    Mt.cyl((mx, top - 0.2, 0), (mx, top + 0.7, 0), 0.6, 0.45, n=14)

    # ---------------- boats, rafts, searchlights ----------------
    B = Builder(M, 'Hull', P['light'])
    # 26-ft whaleboat on davits, port side by the forward funnel
    bx, bz, by = 9.0, -5.6, Lmid + 0.8
    pts = []
    for t in np.linspace(0, 2 * np.pi, 20, endpoint=False):
        pts.append((bx + np.cos(t) * 4.0, bz + np.sin(t) * 0.95 * (1 - 0.25 * max(0, np.cos(t)))))
    B.prism(pts, by - 0.7, by, inset=0.25)
    B.set_mat(P['canvas'])
    B.prism([(p[0] * .82 + bx * .18, p[1] * .7 + bz * .3) for p in pts], by, by + 0.15)
    B.set_mat(P['dark'])
    for dx in (-3.2, 3.2):
        B.cyl((bx + dx, Lmid - 0.2, -3.6), (bx + dx, by + 1.2, bz + 0.2), 0.08, n=6)
    # life rafts on the deckhouse sides and aft
    B.set_mat(P['raft'])
    for x, z, y in [(30.5, 4.75, L1 - 1.4), (30.5, -4.75, L1 - 1.4), (-29.0, 3.75, La1 - 1.3), (-29.0, -3.75, La1 - 1.3),
                    (-2.0, 3.45, Lmid - 1.2), (-2.0, -3.45, Lmid - 1.2)]:
        B.box((x, y, z), (2.6, 1.0, 0.3))
    # searchlights
    B.set_mat(P['light'])
    B.cyl((-11.5, Lmid + 2.2, 0), (-11.5, Lmid + 2.8, 0), 0.55, n=14)

    # ---------------- depth charges and K-guns ----------------
    K = Builder(M, 'Hull', P['dark'])
    for s in (1, -1):
        z = s * 2.0
        K.box((-53.5, dy(-53.5) + 0.25, z), (6.0, 0.5, 0.9))
        for i in range(6):
            x = -51.2 - i * 0.9
            K.cyl((x, dy(x) + 0.5, z - 0.4), (x, dy(x) + 0.5, z + 0.4), 0.3, n=10)
        for x in (-44, -47):
            K.cyl((x, dy(x), s * 4.6), (x, dy(x) + 0.9, s * 4.9), 0.18, n=8)

    # ---------------- railings ----------------
    R = Builder(M, 'Hull', P['rail'])
    xs = np.arange(XS + 1.5, 55.5, 1.8)
    for s in (1, -1):
        prev = None
        for x in xs:
            y = dy(x); z = s * (half_breadth(x, y) - 0.12)
            R.box((x, y + 0.5, z), (0.05, 1.0, 0.05))
            if prev is not None:
                for h in (0.55, 1.0):
                    a = (prev[0], prev[1] + h, prev[2]); b = (x, y + h, z)
                    R.quad(a, b, (b[0], b[1] + 0.03, b[2]), (a[0], a[1] + 0.03, a[2]))
            prev = (x, y, z)

    # ---------------- weapons (separate groups so they can rotate) ----------------
    mounts = [('Mount51', 40.5, dy(40.5), 0.0), ('Mount52', 31.0, L1, 0.0),
              ('Mount53', -27.5, La2, np.pi), ('Mount54', -36.0, La1, np.pi), ('Mount55', -45.5, dy(-45.5), np.pi)]
    for name, x, y, face in mounts:
        gun_mount(M, name, (x, y, 0), face if train is None else train, P)
    for name, x, y, z in [('Torpedo1', 0.5, Lmid, 0.0), ('Torpedo2', -15.0, dy(-15), 0.0)]:
        torpedo_mount(M, name, (x, y, z), P)
    for name, x, y, z in [('Bofors1', 3.0, Lmid, 4.5), ('Bofors2', 3.0, Lmid, -4.5), ('Bofors3', -21.2, La1, 4.4), ('Bofors4', -21.2, La1, -4.4),
                          ('Bofors5', 12.0, Lmid, 0.0)]:
        bofors(M, name, (x, y, z), P, outward=np.sign(z) if z else 0)
    for i, (x, y, z) in enumerate([(22.5, L2 + 0.2, 4.8), (22.5, L2 + 0.2, -4.8), (33.8, L1, 3.6), (33.8, L1, -3.6),
                                   (-41.0, dy(-41), 4.6), (-41.0, dy(-41), -4.6), (-50.0, dy(-50), 3.4), (-50.0, dy(-50), -3.4)]):
        oerlikon(M, 'Oerlikon%d' % (i + 1), (x, y, z), P, np.sign(z))
    director(M, 'Director', (21.2, L3, 0), P)
    return M


def gun_mount(M, name, pos, face, P):
    """5-inch/38 Mk 30 enclosed single mount. Group origin = training axis at deck level."""
    G = Builder(M, name, P['gun'], pivot=pos)
    R = rot_y(-face)
    G.xf = (R, np.array(pos))
    # base ring
    G.cyl((0, 0, 0), (0, 0.35, 0), 2.1, n=24)
    # gunhouse: sloped front, flat sides, rounded rear
    plan = [(2.3, -1.4), (2.3, 1.4), (1.2, 2.0), (-2.2, 2.0), (-2.9, 1.2), (-2.9, -1.2), (-2.2, -2.0), (1.2, -2.0)]
    G.prism(plan, 0.35, 2.6, inset=0.18)
    # roof hatches and sight hoods
    G.set_mat(P['sup'])
    G.box((-1.3, 2.68, 0.0), (1.2, 0.16, 1.4))
    for s in (1, -1):
        G.box((0.8, 2.7, s * 1.25), (0.9, 0.3, 0.6))
    # barrel and blast bag
    G.set_mat(P['canvas'])
    G.cyl((2.0, 1.5, 0), (2.6, 1.5, 0), 0.33, 0.26, n=12)
    G.set_mat(P['dark'])
    G.cyl((2.5, 1.5, 0), (7.5, 1.5, 0), 0.12, 0.09, n=12)


def torpedo_mount(M, name, pos, P):
    G = Builder(M, name, P['gun'], pivot=pos)
    G.xf = (rot_y(-0.25), np.array(pos))
    G.cyl((0, 0, 0), (0, 0.5, 0), 1.6, n=18)
    G.set_mat(P['dark'])
    for k in range(5):
        z = -1.4 + k * 0.7
        G.cyl((-3.6, 1.0, z), (3.6, 1.0, z), 0.3, n=12)
    G.set_mat(P['gun'])
    G.box((-2.4, 1.6, 0), (1.2, 0.9, 1.2))


def bofors(M, name, pos, P, outward=0):
    """Twin 40 mm in a round splinter-shield tub. The tub stays with the hull; the gun trains."""
    T = Builder(M, 'Hull', P['sup'])
    x, y, z = pos
    ra, rb = T.cyl((x, y, z), (x, y + 1.1, z), 2.0, n=22, caps=False)
    T.cyl((x, y + 0.02, z), (x, y + 0.04, z), 1.9, n=22)
    G = Builder(M, name, P['gun'], pivot=pos)
    a = (np.pi / 2 if outward > 0 else -np.pi / 2) if outward else 0.0
    G.xf = (rot_y(-a), np.array(pos))
    G.cyl((0, 0, 0), (0, 0.9, 0), 0.55, n=12)
    G.box((0.0, 1.05, 0), (1.3, 0.5, 1.3))
    G.set_mat(P['dark'])
    for s in (1, -1):
        G.cyl((0.4, 1.15, s * 0.32), (3.2, 1.25, s * 0.32), 0.07, n=8)
    G.set_mat(P['gun'])
    G.box((-0.7, 0.9, 0), (0.4, 0.8, 1.6))


def oerlikon(M, name, pos, P, outward):
    G = Builder(M, name, P['gun'], pivot=pos)
    G.xf = (rot_y(-(np.pi / 2 if outward > 0 else -np.pi / 2)), np.array(pos))
    G.cyl((0, 0, 0), (0, 0.9, 0), 0.12, n=8)
    G.box((0.15, 1.15, 0), (0.08, 0.8, 0.9))
    G.set_mat(P['dark'])
    G.cyl((0.0, 1.1, 0), (2.2, 1.2, 0), 0.05, n=6)


def director(M, name, pos, P):
    """Mk 37 gun director with rangefinder and Mk 4 fire-control radar."""
    G = Builder(M, name, P['sup'], pivot=pos)
    G.xf = (np.eye(3), np.array(pos))
    plan = [(1.6, -1.2), (1.6, 1.2), (1.0, 1.6), (-1.8, 1.6), (-1.8, -1.6), (1.0, -1.6)]
    G.prism(plan, 0.0, 1.9, inset=0.1)
    G.set_mat(P['gun'])
    G.cyl((-0.2, 1.3, -2.6), (-0.2, 1.3, 2.6), 0.22, n=12)   # rangefinder arms
    G.set_mat(P['rail'])
    G.box((0.0, 2.6, 0), (0.25, 1.3, 2.4))                   # Mk 4 radar antenna
