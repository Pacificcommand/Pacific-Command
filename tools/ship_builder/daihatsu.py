"""Daihatsu (14 m) landing barge, Imperial Japanese Army. Real dimensions in meters.
The workhorse of night supply runs around Guadalcanal, New Guinea and the Solomons, and a
common PT-boat target. LOA 14.9 m, beam 3.35 m, draft about 0.8 m loaded.
Steel hull with a W-shaped bottom, bow ramp, open cargo well, engine and steering aft,
usually one or two light machine guns. Shown loaded with supply drums and crates."""
import numpy as np
from geom import Mesh, Builder, rot_y

L = 14.9
XB, XS = L / 2, -L / 2
HB = 1.675
GUN = 1.35          # gunwale height above the waterline

P = dict(hull='#4b5048', hull2='#41463f', bottom='#5c2c24', well='#3a3d38', ramp='#50554c', dark='#1d1f1c', steel='#6b706a',
         drum='#5b4a34', drum2='#6e6a50', crate='#7c6a48', canvas='#77735c', wood='#6a5236', flag='#d9d4c8', red='#b33a2e')


def build(load=True):
    M = Mesh()
    H = Builder(M, 'Hull', P['hull'])
    xr = 5.3   # where the ramp begins
    # hull plan: nearly rectangular, slightly narrowed at the bow ramp and stern
    def hw(x):
        if x > xr:
            return HB * (1 - 0.22 * (x - xr) / (XB - xr))
        if x < -5.8:
            return HB * (1 - 0.12 * (-5.8 - x) / (-5.8 - XS))
        return HB
    xs = np.linspace(XS, xr, 22)
    for a, b in zip(xs[:-1], xs[1:]):
        wa, wb = hw(a), hw(b)
        for s in (1, -1):
            H.set_mat(P['bottom'])
            # W-bottom: center keel, two shallow tunnels
            H.quad((a, -0.75, 0), (b, -0.75, 0), (b, -0.55, s * wb * 0.5), (a, -0.55, s * wa * 0.5))
            H.quad((a, -0.55, s * wa * 0.5), (b, -0.55, s * wb * 0.5), (b, -0.7, s * wb), (a, -0.7, s * wa))
            H.quad((a, -0.7, s * wa), (b, -0.7, s * wb), (b, 0.05, s * wb), (a, 0.05, s * wa))
            H.set_mat(P['hull'])
            H.quad((a, 0.05, s * wa), (b, 0.05, s * wb), (b, GUN, s * wb), (a, GUN, s * wa))
            # inner face of the bulwark and the well floor
            H.set_mat(P['hull2'])
            H.quad((a, GUN, s * (wa - 0.12)), (b, GUN, s * (wb - 0.12)), (b, 0.25, s * (wb - 0.12)), (a, 0.25, s * (wa - 0.12)))
            H.quad((a, GUN, s * wa), (b, GUN, s * wb), (b, GUN, s * (wb - 0.12)), (a, GUN, s * (wa - 0.12)))
        H.set_mat(P['well'])
        H.quad((a, 0.25, -(wa - 0.12)), (b, 0.25, -(wb - 0.12)), (b, 0.25, wb - 0.12), (a, 0.25, wa - 0.12))
    # transom
    H.set_mat(P['hull2'])
    w = hw(XS)
    H.poly([(XS, -0.75, 0), (XS, -0.55, w * 0.5), (XS, -0.7, w), (XS, GUN, w), (XS, GUN, -w), (XS, -0.7, -w), (XS, -0.55, -w * 0.5)])
    # bow: sloped forefoot under a hinged ramp
    R = Builder(M, 'Hull', P['ramp'])
    wr, wf = hw(xr), hw(XB)
    for s in (1, -1):
        R.set_mat(P['bottom']); R.quad((xr, -0.7, s * wr), (XB, 0.2, s * wf), (XB, 0.2, 0), (xr, -0.75, 0))
        R.set_mat(P['hull']); R.poly([(xr, -0.7, s * wr), (xr, GUN + 0.15, s * wr), (XB, GUN + 0.35, s * wf), (XB, 0.2, s * wf)])
    R.set_mat(P['ramp'])
    R.quad((xr + 0.2, 0.3, -wr + 0.1), (xr + 0.2, 0.3, wr - 0.1), (XB, GUN + 0.35, wf), (XB, GUN + 0.35, -wf))
    R.set_mat(P['dark'])
    for k in range(6):
        t = (k + 0.5) / 6
        x = xr + 0.2 + (XB - xr - 0.2) * t; y = 0.3 + (GUN + 0.05) * t
        R.box((x, y + 0.03, 0), (0.06, 0.04, 2 * wf))
    # stern deck over the engine, steering position with a splinter shield
    E = Builder(M, 'Hull', P['hull2'])
    E.box((-6.1, GUN - 0.05, 0), (2.6, 0.12, 2 * hw(-6.1) - 0.1))
    E.set_mat(P['steel']); E.box((-4.6, 0.9, 0), (0.9, 1.0, 1.6))                    # engine casing in the well
    E.set_mat(P['hull']); E.prism([(-5.0, 0.9), (-5.0, -0.9), (-6.3, -0.95), (-6.3, 0.95)], GUN, GUN + 1.0)
    E.set_mat(P['dark']); E.box((-5.65, GUN + 1.02, 0), (1.2, 0.04, 1.7))
    E.set_mat(P['steel']); E.cyl((-6.6, GUN, 0.9), (-6.6, GUN + 1.4, 0.9), 0.08, n=8)   # exhaust
    # tiller and a small ensign staff
    E.set_mat(P['dark']); E.cyl((-7.2, GUN, 0), (-7.2, GUN + 1.2, 0), 0.03, n=5)
    E.set_mat(P['flag']); E.box((-7.45, GUN + 1.05, 0), (0.45, 0.3, 0.02))
    E.set_mat(P['red']); E.box((-7.45, GUN + 1.05, 0.011), (0.14, 0.14, 0.01))
    if load:
        C = Builder(M, 'Hull', P['drum'])
        # supply drums (the "Tokyo Express" floated these ashore) and crates under canvas
        k = 0
        for x in np.arange(-3.4, 4.6, 0.75):
            for z in (-0.95, -0.25, 0.45, 1.1):
                if (x > 2.4 and abs(z) > 1.0):
                    continue
                C.set_mat(P['drum'] if (k % 3) else P['drum2'])
                C.cyl((x, 0.27, z), (x, 1.15, z), 0.3, n=10)
                k += 1
        C.set_mat(P['canvas']); C.box((0.4, 1.25, 0.0), (3.2, 0.25, 2.6))
        C.set_mat(P['crate']); C.box((-2.4, 0.75, -0.6), (1.2, 0.9, 1.0)); C.box((-2.4, 0.75, 0.7), (1.0, 0.8, 0.9))
    mg(M, 'MG1', (-6.6, GUN + 0.05, 0.0))
    mg(M, 'MG2', (4.8, GUN + 0.05, 0.9))
    return M


def mg(M, name, pos):
    """Type 96 light machine gun or Type 93 13 mm on a pintle."""
    G = Builder(M, name, P['steel'], pivot=pos)
    G.xf = (np.eye(3) if pos[0] > 0 else rot_y(-np.pi), np.array(pos))
    G.cyl((0, 0, 0), (0, 0.6, 0), 0.05, n=6)
    G.set_mat(P['dark']); G.box((0.1, 0.7, 0), (0.7, 0.12, 0.1)); G.cyl((0.4, 0.7, 0), (1.2, 0.72, 0), 0.025, n=5)
