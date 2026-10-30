"""Kagero-class destroyer (IJN), 1942 fit, real dimensions in meters.
Reference: Yukikaze plan, profile and photo in the reference PDF.
LOA 118.5 m, beam 10.8 m, draft 3.8 m. Raised forecastle with a break aft of the bridge."""
import numpy as np
from geom import Mesh, Builder, rounded_plan, rot_y

XB, XS = 59.25, -59.25
BEAM = 5.4
DRAFT = 3.8
BREAK = 17.0            # forecastle break position

def deck_y(x):
    if x >= BREAK:
        return 6.3 + 1.6 * ((x - BREAK) / (XB - BREAK)) ** 2
    return 4.0 - 0.45 * max(0.0, -x) / -XS

def stem_x(y):
    return 55.0 + (59.25 - 55.0) * np.clip((y + DRAFT) / (8.0 + DRAFT), 0, 1)

def half_breadth(x, y):
    yd = deck_y(x)
    xs = stem_x(y)
    if x >= xs:
        return 0.0
    if x > 8:
        t = (x - 8) / (xs - 8)
        w = BEAM * (1 - t ** 2.0) ** 0.6
    elif x > -36:
        w = BEAM
    else:
        t = (x + 36) / (XS + 36)
        w = BEAM * (1 - 0.32 * t ** 1.5)
    if x > 24 and y < yd:
        f = np.clip((x - 24) / 35, 0, 1)
        w *= 1 - 0.24 * f * np.clip((yd - y) / (yd + DRAFT), 0, 1)
    if y < 0:
        d = -y / DRAFT
        w *= (1 - d ** 3.0) ** (1 / 3.0) if d < 1 else 0.0
        if x < -38:
            t = (x + 38) / (XS + 38)
            w *= 1 - 0.75 * t * d ** 0.7
    return max(w, 0.0)

P = dict(hull='#6a7174', deck='#7b4f37', steel='#5e6568', sup='#737a7d', gun='#6e7578', dark='#26292b', bottom='#6b2b22',
         boot='#1b1c1d', black='#0b0b0b', rail='#2a2d2f', canvas='#9a917a', light='#c9cfd1', brass='#a88a52', glass='#2f383c')

def build():
    M = Mesh()
    H = Builder(M, 'Hull', P['hull'])
    # stations: split at the forecastle break so the deck steps cleanly
    xs_list = list(np.linspace(XS, BREAK - 0.01, 64)) + list(np.linspace(BREAK + 0.01, 54.0, 34)) + list(np.linspace(54.4, 59.15, 10))
    levels = 18
    sections = []
    for x in xs_list:
        yd = deck_y(x)
        sections.append([(x, y, half_breadth(x, y)) for y in np.linspace(-DRAFT, yd, levels)])
    for i in range(len(sections) - 1):
        a, b = sections[i], sections[i + 1]
        if a[0][0] < BREAK < b[0][0]:
            # forecastle break bulkhead
            hi, lo = b, a
            H.set_mat(P['hull'])
            for s in (1, -1):
                H.quad((BREAK, lo[-1][1], 0), (BREAK, lo[-1][1], s * lo[-1][2]), (BREAK, hi[-1][1], s * hi[-1][2]), (BREAK, hi[-1][1], 0))
        for k in range(levels - 1):
            ya = a[k][1]
            H.set_mat(P['bottom'] if ya < -0.05 else (P['boot'] if ya < 0.4 else P['hull']))
            for s in (1, -1):
                H.quad((a[k][0], a[k][1], s * a[k][2]), (b[k][0], b[k][1], s * b[k][2]), (b[k + 1][0], b[k + 1][1], s * b[k + 1][2]), (a[k + 1][0], a[k + 1][1], s * a[k + 1][2]))
    last = sections[-1]
    for k in range(levels - 1):
        y0, y1 = last[k][1], last[k + 1][1]
        H.set_mat(P['bottom'] if y0 < -0.05 else P['hull'])
        for s in (1, -1):
            H.quad((last[k][0], y0, s * last[k][2]), (stem_x(y0), y0, 0), (stem_x(y1), y1, 0), (last[k + 1][0], y1, s * last[k + 1][2]))
    st = sections[0]
    for k in range(levels - 1):
        H.set_mat(P['bottom'] if st[k][1] < -0.05 else P['hull'])
        H.quad((XS, st[k][1], -st[k][2]), (XS, st[k][1], st[k][2]), (XS, st[k + 1][1], st[k + 1][2]), (XS, st[k + 1][1], -st[k + 1][2]))
    # linoleum deck with brass strips, steel at the ends
    D = Builder(M, 'Hull', P['deck'])
    ncam = 8
    for i in range(len(sections) - 1):
        xa, xb = sections[i][-1][0], sections[i + 1][-1][0]
        if xa < BREAK < xb:
            continue
        wa, wb = sections[i][-1][2], sections[i + 1][-1][2]
        ya, yb = sections[i][-1][1], sections[i + 1][-1][1]
        steel = xa > 47 or xa < -52
        for k in range(ncam):
            z0, z1 = -1 + 2 * k / ncam, -1 + 2 * (k + 1) / ncam
            cam = lambda z: 0.14 * (1 - z * z)
            D.set_mat(P['steel'] if steel or abs(z0 + z1) / 2 > 0.82 else P['deck'])
            D.quad((xa, ya + cam(z0), z0 * wa), (xb, yb + cam(z0), z0 * wb), (xb, yb + cam(z1), z1 * wb), (xa, ya + cam(z1), z1 * wa))
    xl, yl, wl = sections[-1][-1][0], sections[-1][-1][1], sections[-1][-1][2]
    D.set_mat(P['steel']); D.tri((xl, yl, -wl), (stem_x(deck_y(XB)), deck_y(XB), 0), (xl, yl, wl))
    D.set_mat(P['brass'])
    for x in np.arange(-50, 46, 2.4):
        if abs(x - BREAK) < 1.2:
            continue
        y = deck_y(x) + 0.15; w = half_breadth(x, deck_y(x)) * 0.8
        D.quad((x, y, -w), (x + 0.06, y, -w), (x + 0.06, y, w), (x, y, w))

    dy = deck_y
    F = Builder(M, 'Hull', P['dark'])
    for s in (1, -1):
        F.cyl((52.5, dy(52.5), s * 1.2), (52.5, dy(52.5) + 0.45, s * 1.2), 0.4, n=12)
        for i in range(8):
            x = 55.2 - i * 0.33
            F.box((x, dy(x) + 0.04, s * (1.3 - i * 0.02)), (0.28, 0.08, 0.15))
    for x in [50, 36, 10, -10, -28, -46, -54]:
        for s in (1, -1):
            z = s * (half_breadth(x, dy(x)) - 0.6)
            for dx in (-0.3, 0.3):
                F.cyl((x + dx, dy(x), z), (x + dx, dy(x) + 0.4, z), 0.14, n=8)

    S = Builder(M, 'Hull', P['sup'])
    # bridge on the forecastle: tiered, with rangefinder on top
    b0 = dy(25)
    S.prism(rounded_plan(31.0, 21.5, 3.6, 2.6), b0, b0 + 2.4)
    S.prism(rounded_plan(30.0, 22.5, 3.0, 2.4), b0 + 2.4, b0 + 4.6)
    S.set_mat(P['glass']); S.prism(rounded_plan(29.6, 24.0, 2.8, 2.3), b0 + 4.6, b0 + 5.4)
    S.set_mat(P['sup']); S.prism(rounded_plan(29.4, 24.0, 2.8, 2.3), b0 + 5.4, b0 + 5.8)
    S.cyl((26.0, b0 + 5.8, 0), (26.0, b0 + 7.0, 0), 1.3, n=16)
    S.set_mat(P['gun']); S.cyl((26.0, b0 + 7.3, -2.4), (26.0, b0 + 7.3, 2.4), 0.25, n=10); S.box((26.0, b0 + 7.3, 0), (1.6, 0.9, 1.4))
    # tripod foremast
    Mt = Builder(M, 'Hull', P['dark'])
    Mt.cyl((20.5, b0 + 4.0, 0), (20.5, b0 + 18.0, 0), 0.2, 0.1, n=8)
    for s in (1, -1):
        Mt.cyl((18.6, dy(18.6), s * 1.8), (20.5, b0 + 11.0, 0), 0.12, n=6, caps=False)
    Mt.cyl((20.5, b0 + 13.0, -3.2), (20.5, b0 + 13.0, 3.2), 0.07, n=6)
    # amidships deckhouse and funnels
    m0 = dy(0)
    S.prism([(14.5, 2.6), (-11.0, 2.6), (-11.0, -2.6), (14.5, -2.6)], m0 - 0.2, m0 + 1.6)
    Lm = m0 + 1.6
    for fx, h, rake, trunk in [(11.0, 8.5, 1.6, True), (-6.0, 7.6, 1.3, False)]:
        ring = lambda y, k, fx=fx, h=h, rake=rake: [(fx - rake * (y - Lm) / h + np.cos(t) * 2.4 * k, y, np.sin(t) * 1.45 * k) for t in np.linspace(0, 2 * np.pi, 24, endpoint=False)]
        S.set_mat(P['sup'])
        lo, hi = ring(Lm, 1.0), ring(Lm + h, 0.95)
        for i in range(24):
            j = (i + 1) % 24
            S.quad(lo[i], lo[j], hi[j], hi[i])
        S.set_mat(P['black'])
        cap0, cap1 = ring(Lm + h, 1.0), ring(Lm + h + 0.9, 1.0)
        for i in range(24):
            j = (i + 1) % 24
            S.quad(cap0[i], cap0[j], cap1[j], cap1[i])
        S.capfan(ring(Lm + h + 0.7, 0.9))
        S.set_mat(P['rail'])
        for k in range(-3, 4):
            S.box((fx - rake + k * 0.55, Lm + h + 0.92, 0), (0.06, 0.05, 2.6))
    # 25 mm twin mounts abreast the forward funnel
    for s in (1, -1):
        S.set_mat(P['sup']); S.prism([(13.5, s * 2.6), (9.0, s * 2.6), (9.0, s * 4.6), (13.5, s * 4.6)], Lm - 0.2, Lm)
    # reload lockers beside the torpedo mounts
    for x in (1.0, -17.5):
        for s in (1, -1):
            S.set_mat(P['steel']); S.box((x + 1.5, dy(x) + 0.7, s * 3.4), (6.5, 1.4, 1.2))
    # mainmast and after deckhouse for mount 2
    Mt.cyl((-22.0, dy(-22), 0), (-22.0, dy(-22) + 14.0, 0), 0.16, 0.08, n=8)
    a0 = dy(-30)
    S.set_mat(P['sup']); S.prism([(-25.5, 2.4), (-34.0, 2.4), (-34.0, -2.4), (-25.5, -2.4)], a0 - 0.2, a0 + 2.2)
    La = a0 + 2.2
    # boats
    B = Builder(M, 'Hull', P['light'])
    for s in (1, -1):
        bx, bz, by = -10.0, s * 4.4, dy(-10) + 2.6
        pts = [(bx + np.cos(t) * 3.2, bz + np.sin(t) * 0.8) for t in np.linspace(0, 2 * np.pi, 18, endpoint=False)]
        B.set_mat(P['light']); B.prism(pts, by - 0.6, by, inset=0.2)
        B.set_mat(P['canvas']); B.prism([(p[0] * .8 + bx * .2, p[1] * .7 + bz * .3) for p in pts], by, by + 0.12)
    # depth charges
    K = Builder(M, 'Hull', P['dark'])
    for s in (1, -1):
        K.box((-55.5, dy(-55.5) + 0.25, s * 1.8), (5.0, 0.5, 0.8))
    # railings
    R = Builder(M, 'Hull', P['rail'])
    for s in (1, -1):
        prev = None
        for x in np.arange(XS + 1.5, 57.5, 1.8):
            if abs(x - BREAK) < 0.9:
                prev = None; continue
            y = dy(x); z = s * (half_breadth(x, y) - 0.12)
            R.box((x, y + 0.45, z), (0.05, 0.9, 0.05))
            if prev is not None and (prev[0] - BREAK) * (x - BREAK) > 0:
                for h in (0.5, 0.9):
                    a = (prev[0], prev[1] + h, prev[2]); b = (x, y + h, z)
                    R.quad(a, b, (b[0], b[1] + 0.03, b[2]), (a[0], a[1] + 0.03, a[2]))
            prev = (x, y, z)
    # weapons
    for name, x, y, face in [('Mount1', 39.0, dy(39), 0.0), ('Mount2', -30.0, La, np.pi), ('Mount3', -38.5, dy(-38.5), np.pi)]:
        twin_mount(M, name, (x, y, 0), face)
    for name, x in [('Torpedo1', 1.0), ('Torpedo2', -17.5)]:
        torpedo_quad(M, name, (x, dy(x), 0))
    for i, s in enumerate((1, -1)):
        aa25(M, 'AA%d' % (i + 1), (11.2, Lm, s * 3.6), s)
    G = Builder(M, 'Director', P['sup'], pivot=(26.0, b0 + 5.8, 0))
    G.xf = (np.eye(3), np.array((26.0, b0 + 5.8, 0)))
    G.box((0, 0.05, 0), (0.1, 0.1, 0.1))
    return M

def twin_mount(M, name, pos, face):
    G = Builder(M, name, P['gun'], pivot=pos)
    G.xf = (rot_y(-face), np.array(pos))
    G.cyl((0, 0, 0), (0, 0.3, 0), 2.2, n=22)
    plan = [(2.4, -1.6), (2.4, 1.6), (1.4, 2.2), (-2.6, 2.2), (-3.0, 1.4), (-3.0, -1.4), (-2.6, -2.2), (1.4, -2.2)]
    G.prism(plan, 0.3, 2.7, inset=0.25)
    G.set_mat(P['sup']); G.box((-1.4, 2.78, 0), (1.2, 0.14, 1.6))
    G.set_mat(P['canvas'])
    for s in (1, -1):
        G.cyl((2.2, 1.5, s * 0.75), (2.7, 1.5, s * 0.75), 0.3, 0.24, n=10)
    G.set_mat(P['dark'])
    for s in (1, -1):
        G.cyl((2.6, 1.5, s * 0.75), (8.0, 1.5, s * 0.75), 0.11, 0.08, n=10)

def torpedo_quad(M, name, pos):
    G = Builder(M, name, P['gun'], pivot=pos)
    G.xf = (rot_y(0.0), np.array(pos))
    G.cyl((0, 0, 0), (0, 0.5, 0), 1.6, n=16)
    G.box((0.0, 1.1, 0), (8.6, 1.2, 2.8))
    G.set_mat(P['dark'])
    for k in range(4):
        z = -1.05 + k * 0.7
        G.cyl((4.3, 1.1, z), (4.5, 1.1, z), 0.3, n=10)

def aa25(M, name, pos, side):
    G = Builder(M, name, P['gun'], pivot=pos)
    G.xf = (rot_y(-(np.pi / 2 if side > 0 else -np.pi / 2)), np.array(pos))
    G.cyl((0, 0, 0), (0, 0.8, 0), 0.5, n=10)
    G.set_mat(P['dark'])
    for s in (1, -1):
        G.cyl((0.3, 1.0, s * 0.25), (2.6, 1.1, s * 0.25), 0.06, n=6)
