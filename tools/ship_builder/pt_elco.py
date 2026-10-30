"""Elco 80-ft PT boat, 1943-44 Pacific fit. Real dimensions in meters.
Reference: Elco cutaway illustration and the "PT boats at speed" photo in the reference PDF.
LOA 24.4 m (80 ft), beam 6.3 m (20 ft 8 in), draft 1.6 m (5 ft 3 in).
Hard-chine planing hull; mahogany plywood painted dark green (Measure 31 style).
Armament: 37 mm bow gun, 20 mm Oerlikon, two twin .50 turrets, 40 mm Bofors aft,
four Mark 13 torpedoes on roll-off racks, two Mark 50 rocket launchers, SO radar mast."""
import numpy as np
from geom import Mesh, Builder, rot_y

XB, XS = 12.2, -12.2
HB = 3.15

P = dict(hull='#3d4a36', hull2='#34402f', deck='#46533e', bottom='#5a2a22', boot='#141615', sup='#4a5743', gun='#3a3f3a',
         dark='#1c1f1c', steel='#666b66', torp='#7c8279', warhead='#8f8a6a', glass='#2a3436', canvas='#8d8a6e', raft='#b9a45e',
         white='#d8dad5', flagr='#a83a32', flagb='#26365e')


def deck_y(x):
    # sheer rises toward the bow
    t = (x - XS) / (XB - XS)
    return 1.85 + 0.55 * t ** 2.2


def deck_w(x):
    # full beam aft, fine entry at the bow
    if x < 1.0:
        return HB * (1 - 0.06 * ((1.0 - x) / (1.0 - XS)) ** 2)
    t = (x - 1.0) / (XB - 1.0)
    return HB * max(0.0, 1 - t ** 1.9) ** 0.62


def chine(x):
    """(height, half-width) of the hard chine."""
    t = (x - XS) / (XB - XS)
    y = -0.15 + 1.25 * max(0.0, (x - 2.0) / (XB - 2.0)) ** 1.6
    w = deck_w(x) * (0.93 - 0.08 * max(0.0, (x - 4.0) / (XB - 4.0)))
    return y, w


def keel_y(x):
    if x < 2.0:
        return -1.05 + 0.15 * (2.0 - x) / (2.0 - XS)
    t = (x - 2.0) / (XB - 2.0)
    return -1.05 + (deck_y(XB) + 1.05) * t ** 2.4


def build():
    M = Mesh()
    H = Builder(M, 'Hull', P['hull'])
    xs = list(np.linspace(XS, 8.0, 34)) + list(np.linspace(8.25, XB - 0.02, 16))
    secs = []
    for x in xs:
        yc, wc = chine(x)
        secs.append((x, keel_y(x), yc, wc, deck_y(x), deck_w(x)))
    for a, b in zip(secs[:-1], secs[1:]):
        for s in (1, -1):
            # bottom: keel to chine (V deadrise), antifouling below the waterline
            H.set_mat(P['bottom'])
            H.quad((a[0], a[1], 0), (b[0], b[1], 0), (b[0], b[2], s * b[3]), (a[0], a[2], s * a[3]))
            # topsides: chine to sheer, boot topping stripe near the waterline
            ya_mid = a[2] + 0.35
            yb_mid = b[2] + 0.35
            H.set_mat(P['boot'])
            H.quad((a[0], a[2], s * a[3]), (b[0], b[2], s * b[3]), (b[0], yb_mid, s * (b[3] + (b[5] - b[3]) * 0.3)), (a[0], ya_mid, s * (a[3] + (a[5] - a[3]) * 0.3)))
            H.set_mat(P['hull'])
            H.quad((a[0], ya_mid, s * (a[3] + (a[5] - a[3]) * 0.3)), (b[0], yb_mid, s * (b[3] + (b[5] - b[3]) * 0.3)), (b[0], b[4], s * b[5]), (a[0], a[4], s * a[5]))
    # stem
    l = secs[-1]
    H.set_mat(P['hull'])
    for s in (1, -1):
        H.tri((l[0], l[1], 0), (XB, deck_y(XB), 0), (l[0], l[4], s * l[5]))
        H.tri((l[0], l[1], 0), (l[0], l[4], s * l[5]), (l[0], l[2], s * l[3]))
    # transom
    f = secs[0]
    H.set_mat(P['hull2'])
    for s in (1, -1):
        H.poly([(XS, f[1], 0), (XS, f[2], s * f[3]), (XS, f[4], s * f[5]), (XS, f[4], 0)])
    # deck, with a slight crown
    D = Builder(M, 'Hull', P['deck'])
    n = 6
    for a, b in zip(secs[:-1], secs[1:]):
        for k in range(n):
            z0, z1 = -1 + 2 * k / n, -1 + 2 * (k + 1) / n
            cr = lambda z: 0.08 * (1 - z * z)
            D.quad((a[0], a[4] + cr(z0), z0 * a[5]), (b[0], b[4] + cr(z0), z0 * b[5]), (b[0], b[4] + cr(z1), z1 * b[5]), (a[0], a[4] + cr(z1), z1 * a[5]))
    D.tri((l[0], l[4], -l[5]), (XB, deck_y(XB), 0), (l[0], l[4], l[5]))
    dy = lambda x: deck_y(x) + 0.06

    # day cabin and chart house with the cockpit at its after end
    S = Builder(M, 'Hull', P['sup'])
    c0 = dy(2)
    plan = [(5.4, 0.0), (5.0, 1.15), (4.2, 1.45), (-0.6, 1.45), (-0.6, -1.45), (4.2, -1.45), (5.0, -1.15)]
    S.prism(plan, c0 - 0.1, c0 + 0.75, inset=0.08)
    S.set_mat(P['glass'])
    for s in (1, -1):
        for xw in (1.2, 2.4, 3.6):
            S.box((xw, c0 + 0.45, s * 1.42), (0.5, 0.18, 0.04))
    S.set_mat(P['sup'])
    # chart house / conning station, raised behind the day cabin
    S.prism([(1.4, 1.0), (-1.9, 1.0), (-1.9, -1.0), (1.4, -1.0)], c0 + 0.75, c0 + 1.35)
    S.set_mat(P['glass'])
    S.quad((1.45, c0 + 1.35, -0.9), (1.45, c0 + 1.35, 0.9), (1.2, c0 + 1.75, 0.8), (1.2, c0 + 1.75, -0.8))
    S.set_mat(P['dark'])
    S.box((0.1, c0 + 1.37, 0), (2.2, 0.05, 1.6))      # open cockpit floor
    S.set_mat(P['steel']); S.cyl((0.6, c0 + 1.4, 0.0), (0.6, c0 + 1.75, 0.0), 0.2, n=12)  # wheel pedestal
    # life raft on the cabin roof
    S.set_mat(P['raft']); S.box((3.6, c0 + 0.92, 0.0), (1.6, 0.25, 1.1))
    # radar mast with SO radome, and a whip antenna
    R = Builder(M, 'Hull', P['dark'])
    R.cyl((-1.2, c0 + 1.35, 0), (-1.2, c0 + 4.8, 0), 0.08, 0.06, n=8)
    R.set_mat(P['steel']); R.cyl((-1.2, c0 + 4.8, 0), (-1.2, c0 + 5.3, 0), 0.32, 0.32, n=12)
    R.set_mat(P['dark']); R.cyl((-1.6, c0 + 1.4, 1.2), (-1.9, c0 + 8.5, 1.4), 0.03, n=5)
    # engine room hatches and ventilators aft
    E = Builder(M, 'Hull', P['sup'])
    for x0, x1 in [(-2.6, -4.6), (-5.0, -7.2)]:
        y = dy((x0 + x1) / 2)
        E.box(((x0 + x1) / 2, y + 0.12, 0), (abs(x1 - x0), 0.24, 1.6))
        E.set_mat(P['dark'])
        for k in range(5):
            E.box(((x0 + x1) / 2 - 0.8 + k * 0.4, y + 0.25, 0), (0.08, 0.02, 1.4))
        E.set_mat(P['sup'])
    for s in (1, -1):
        for x in (-2.2, -7.6):
            E.cyl((x, dy(x), s * 0.9), (x, dy(x) + 0.7, s * 0.9), 0.16, n=10)
            E.set_mat(P['dark']); E.cyl((x, dy(x) + 0.7, s * 0.9), (x + 0.25, dy(x) + 0.85, s * 0.9), 0.17, n=10); E.set_mat(P['sup'])
    # smoke generator on the transom
    E.set_mat(P['steel']); E.cyl((-11.9, dy(-11.9) + 0.4, -1.6), (-11.9, dy(-11.9) + 0.4, -0.6), 0.32, n=12)
    # depth charges / gear lockers along the stern
    E.set_mat(P['dark'])
    for s in (1, -1):
        E.cyl((-11.3, dy(-11.3) + 0.35, s * 2.2), (-11.3, dy(-11.3) + 0.35, s * 2.7), 0.3, n=10)
    # deck railing (low) forward
    K = Builder(M, 'Hull', P['dark'])
    for s in (1, -1):
        prev = None
        for x in np.arange(5.5, 11.6, 0.9):
            y = dy(x); z = s * (deck_w(x) - 0.08)
            K.box((x, y + 0.25, z), (0.03, 0.5, 0.03))
            if prev is not None:
                a, b = (prev[0], prev[1] + 0.5, prev[2]), (x, y + 0.5, z)
                K.quad(a, b, (b[0], b[1] + 0.025, b[2]), (a[0], a[1] + 0.025, a[2]))
            prev = (x, y, z)
    # ensign on the radar mast
    F = Builder(M, 'Hull', P['white'])
    F.set_mat(P['flagb']); F.box((-1.55, c0 + 4.2, 0.0), (0.5, 0.4, 0.02))
    F.set_mat(P['flagr']); F.box((-2.05, c0 + 4.1, 0.0), (0.6, 0.4, 0.02))
    # hull number on both bows
    F.set_mat(P['white'])
    for s in (1, -1):
        F.box((8.6, deck_y(8.6) - 0.45, s * (deck_w(8.6) + 0.01)), (0.9, 0.22, 0.02))

    # weapons (each a group so it can turn)
    gun37(M, 'Gun37', (8.6, dy(8.6), 0.0))
    oerlikon(M, 'Oerlikon', (6.3, dy(6.3), -1.6))
    twin50(M, 'Twin50Port', (1.8, dy(1.8), -2.05), -np.pi / 2)
    twin50(M, 'Twin50Stbd', (-0.9, dy(-0.9), 2.05), np.pi / 2)
    bofors(M, 'Bofors', (-9.6, dy(-9.6), 0.0))
    for s, nm in ((1, 'RocketsStbd'), (-1, 'RocketsPort')):
        rockets(M, nm, (4.9, dy(4.9), s * 1.85))
    # four Mark 13 torpedoes on roll-off racks
    for i, (x, s) in enumerate([(2.9, 1), (2.9, -1), (-4.1, 1), (-4.1, -1)]):
        torpedo(M, 'Torpedo%d' % (i + 1), (x, dy(x), s * 2.55))
    return M


def gun37(M, name, pos):
    G = Builder(M, name, P['gun'], pivot=pos)
    G.xf = (np.eye(3), np.array(pos))
    G.cyl((0, 0, 0), (0, 0.5, 0), 0.35, n=12)
    G.box((0.1, 0.75, 0), (1.2, 0.45, 0.55))
    G.set_mat(P['steel']); G.box((0.3, 0.9, 0), (0.12, 0.8, 1.2))   # shield
    G.set_mat(P['dark']); G.cyl((0.6, 0.8, 0), (2.6, 0.82, 0), 0.06, n=8)


def oerlikon(M, name, pos):
    G = Builder(M, name, P['gun'], pivot=pos)
    G.xf = (np.eye(3), np.array(pos))
    G.cyl((0, 0, 0), (0, 0.9, 0), 0.12, n=8)
    G.set_mat(P['steel']); G.box((0.1, 1.15, 0), (0.08, 0.7, 0.9))
    G.set_mat(P['dark']); G.cyl((0.0, 1.1, 0), (1.9, 1.15, 0), 0.04, n=6)
    G.cyl((-0.1, 1.25, 0), (-0.1, 1.45, 0), 0.18, n=10)


def twin50(M, name, pos, face):
    G = Builder(M, name, P['steel'], pivot=pos)
    G.xf = (rot_y(-face), np.array(pos))
    G.cyl((0, 0, 0), (0, 0.85, 0), 0.62, n=18, caps=False)
    G.set_mat(P['dark']); G.cyl((0, 0.82, 0), (0, 0.86, 0), 0.62, n=18)
    G.set_mat(P['gun']); G.box((0.15, 1.1, 0), (0.7, 0.25, 0.5))
    G.set_mat(P['dark'])
    for s in (1, -1):
        G.cyl((0.4, 1.15, s * 0.16), (1.7, 1.2, s * 0.16), 0.04, n=6)


def bofors(M, name, pos):
    G = Builder(M, name, P['gun'], pivot=pos)
    G.xf = (rot_y(-np.pi), np.array(pos))
    G.cyl((0, 0, 0), (0, 0.35, 0), 0.95, n=16)
    G.box((0.0, 0.8, 0), (1.3, 0.7, 1.1))
    G.set_mat(P['steel']); G.box((0.4, 0.95, 0), (0.08, 0.6, 1.5))
    G.set_mat(P['dark']); G.cyl((0.5, 0.95, 0), (2.9, 1.0, 0), 0.07, n=8)
    G.cyl((2.7, 1.0, 0), (2.95, 1.0, 0), 0.11, n=8)


def rockets(M, name, pos):
    G = Builder(M, name, P['steel'], pivot=pos)
    G.xf = (np.eye(3), np.array(pos))
    G.cyl((0, 0, 0), (0, 0.3, 0), 0.12, n=6)
    for k in range(4):
        for j in range(2):
            G.box((0.0, 0.42 + j * 0.16, -0.24 + k * 0.16), (1.5, 0.05, 0.05))


def torpedo(M, name, pos):
    G = Builder(M, name, P['torp'], pivot=pos)
    G.xf = (np.eye(3), np.array(pos))
    G.set_mat(P['dark'])
    for x in (-1.6, 1.6):
        G.box((x, 0.18, 0), (0.12, 0.36, 0.7))       # roll-off rack chocks
    G.set_mat(P['torp'])
    G.cyl((-2.05, 0.45, 0), (1.6, 0.45, 0), 0.28, n=14, caps=False)
    G.set_mat(P['warhead']); G.cyl((1.6, 0.45, 0), (2.1, 0.45, 0), 0.28, 0.12, n=14)
    G.set_mat(P['dark']); G.cyl((-2.4, 0.45, 0), (-2.05, 0.45, 0), 0.12, 0.28, n=14)
    G.box((-2.45, 0.45, 0), (0.05, 0.55, 0.04)); G.box((-2.45, 0.45, 0), (0.05, 0.04, 0.55))
