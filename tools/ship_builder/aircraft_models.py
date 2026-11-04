"""Detailed carrier aircraft, one model per type, built at real size from the real dimensions.
Each type comes in three versions:
  plane_<t>.glb         flying: wheels up, wings spread, level
  plane_<t>_deck.glb    on deck: wheels down, three-point attitude, wings spread (the take-off run)
  plane_<t>_folded.glb  parked: wheels down, wings folded the way the real aircraft folded them
                        (Grumman 'Sto-Wing' back along the fuselage, Helldiver and Kate upward;
                        the Dauntless, Zero and Val did not fold and park with wings spread)
Internal axes: x forward, y up, z starboard; the origin is on the deck under the middle of the plane.
Detail: lofted fuselage, cowling with the engine face, spinner and three-blade propeller, framed
canopy, tapered wings with thickness and dihedral, tailplane, fin, landing gear, wing guns,
bombs or torpedo, national markings. About a thousand triangles each."""
import numpy as np
from geom import Mesh, Builder

US = dict(top='#2b3d55', side='#4d6583', under='#d3d6d6', dark='#151719', glass='#7f97a3', frame='#1e2a38',
          prop='#1b1b1b', tip='#c9b13b', tyre='#121212', metal='#7d8285', star='#f2f2ee', disc='#1d3a78', red='#a32a24', bomb='#3a3e36')
IJN_ZERO = dict(top='#a3a48b', side='#9fa087', under='#999a82', dark='#141414', glass='#7f97a3', frame='#2a2a26',
                prop='#5d4a32', tip='#c9b13b', tyre='#121212', metal='#8a8c86', star='#f2f2ee', disc='#b8231c', red='#b8231c', bomb='#3a3a36')
IJN_GREEN = dict(top='#3b4632', side='#46523b', under='#a4a796', dark='#141414', glass='#7f97a3', frame='#24281f',
                 prop='#5d4a32', tip='#c9b13b', tyre='#121212', metal='#8a8c86', star='#f2f2ee', disc='#b8231c', red='#b8231c', bomb='#3a3a36')

# real dimensions in metres; wing: root chord, tip chord, low/mid position (y of the wing below the
# fuselage centreline), dihedral (deg); fus: max radius vertical/horizontal; fold: sto / up / none
TYPES = {
    'f6f': dict(L=10.24, span=13.06, cr=3.05, ct=1.35, wy=-0.42, dih=6.0, fy=0.80, fz=0.66, cowl=0.72, prop=3.99, blades=3,
                tail=4.9, fin=1.9, canopy=(0.4, 2.2), seats=1, fold='sto', fold_at=0.20, guns=3, pal=US, gear=1.75, wheel=0.42),
    'f4f': dict(L=8.76, span=11.58, cr=2.55, ct=1.20, wy=-0.05, dih=4.0, fy=0.70, fz=0.60, cowl=0.66, prop=2.97, blades=3,
                tail=4.1, fin=1.6, canopy=(0.2, 1.8), seats=1, fold='sto', fold_at=0.18, guns=3, pal=US, gear=1.55, wheel=0.36),
    'sbd': dict(L=10.09, span=12.66, cr=3.0, ct=1.25, wy=-0.45, dih=6.5, fy=0.72, fz=0.58, cowl=0.66, prop=3.2, blades=3,
                tail=4.3, fin=1.8, canopy=(-1.6, 1.9), seats=2, fold='none', fold_at=0.0, guns=0, pal=US, gear=1.6, wheel=0.38, bomb=1),
    'sb2c': dict(L=11.18, span=15.15, cr=3.35, ct=1.55, wy=-0.30, dih=6.0, fy=0.80, fz=0.64, cowl=0.74, prop=3.8, blades=3,
                 tail=5.2, fin=2.2, canopy=(-1.8, 2.0), seats=2, fold='up', fold_at=0.34, guns=0, pal=US, gear=1.85, wheel=0.44, bomb=1),
    'tbf': dict(L=12.48, span=16.51, cr=3.45, ct=1.6, wy=-0.10, dih=5.0, fy=1.00, fz=0.72, cowl=0.80, prop=4.0, blades=3,
                tail=6.0, fin=2.4, canopy=(-2.6, 2.4), seats=3, fold='sto', fold_at=0.18, guns=1, pal=US, gear=1.9, wheel=0.46, turret=1),
    'a6m': dict(L=9.06, span=12.0, cr=2.55, ct=1.05, wy=-0.40, dih=6.0, fy=0.64, fz=0.56, cowl=0.62, prop=2.9, blades=3,
                tail=4.0, fin=1.6, canopy=(-0.4, 1.7), seats=1, fold='tips', fold_at=0.92, guns=1, pal=IJN_ZERO, gear=1.6, wheel=0.36),
    'd3a': dict(L=10.2, span=14.37, cr=2.85, ct=1.2, wy=-0.42, dih=6.0, fy=0.70, fz=0.58, cowl=0.68, prop=3.2, blades=3,
                tail=4.6, fin=1.8, canopy=(-1.7, 1.8), seats=2, fold='tips', fold_at=0.76, guns=0, pal=IJN_GREEN, gear=1.75, wheel=0.40, bomb=1, spats=1),
    'b5n': dict(L=10.3, span=15.52, cr=3.05, ct=1.4, wy=-0.42, dih=6.0, fy=0.72, fz=0.60, cowl=0.70, prop=3.4, blades=3,
                tail=4.8, fin=1.9, canopy=(-2.4, 1.8), seats=3, fold='up', fold_at=0.38, guns=0, pal=IJN_GREEN, gear=1.75, wheel=0.40, torp=1),
}


def _rot(axis, a):
    c, s = np.cos(a), np.sin(a)
    if axis == 'z':
        return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
    if axis == 'x':
        return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


class Plane:
    def __init__(self, t, spec, folded, gear, flying):
        self.t = t
        self.S = spec
        self.P = spec['pal']
        self.folded = folded
        self.gear = gear
        self.flying = flying
        self.M = Mesh()
        self.B = Builder(self.M, 'Hull', self.P['top'])
        L = spec['L']
        self.xn = L * 0.5            # nose
        self.xt = -L * 0.5           # tail
        self.wing_le = L * 0.5 - 1.15 - spec['cr'] * 0.25   # root leading edge, behind the cowling

    # ---------- fuselage ----------
    def radius(self, x):
        """(ry, rz, yc) of the fuselage at x."""
        S = self.S
        u = (x - self.xt) / (self.xn - self.xt)         # 0 at the tail, 1 at the nose
        k = np.clip(u, 0, 1)
        shape = np.sqrt(np.clip(1.0 - ((0.62 - k) / 0.62) ** 2, 0, 1)) if k < 0.62 else 1.0 - 0.12 * ((k - 0.62) / 0.38) ** 2
        ry = max(0.08, S['fy'] * shape)
        rz = max(0.06, S['fz'] * shape)
        yc = 0.25 * (1.0 - k) ** 2       # the tail rises a little toward the fin
        return ry, rz, yc

    def fuselage(self):
        B, P = self.B, self.P
        n = 14
        xs = list(np.linspace(self.xt + 0.05, self.xn - 1.1, 13))
        rings = []
        for x in xs:
            ry, rz, yc = self.radius(x)
            rings.append([(x, yc + ry * np.sin(a), rz * np.cos(a)) for a in np.linspace(0, 2 * np.pi, n, endpoint=False)])
        for i in range(len(rings) - 1):
            for j in range(n):
                k = (j + 1) % n
                a = (j + 0.5) / n * 2 * np.pi
                sy = np.sin(a)
                B.set_mat(P['top'] if sy > 0.35 else (P['side'] if sy > -0.45 else P['under']))
                B.quad(rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j])
        # tail cone
        B.set_mat(P['side'])
        B.capfan(rings[0][::-1])
        self.nose_ring_x = xs[-1]

    def cowling(self):
        B, P, S = self.B, self.P, self.S
        x0 = self.nose_ring_x
        r = S['cowl']
        ry, rz, yc = self.radius(x0)
        B.set_mat(P['top'] if P is not US else P['side'])
        B.cyl((x0, 0.0, 0), (self.xn - 0.05, 0.0, 0), max(ry, r) * 0.98, r, n=18, caps=False)
        # cowl lip and the engine face with cylinder heads
        B.set_mat(P['dark'])
        B.cyl((self.xn - 0.05, 0, 0), (self.xn, 0, 0), r, r * 0.92, n=18, caps=False)
        B.raw = True
        B.cyl((self.xn - 0.25, 0, 0), (self.xn - 0.22, 0, 0), r * 0.9, n=18)
        B.set_mat(P['metal'])
        for i in range(9):
            a = i / 9 * 2 * np.pi
            B.box((self.xn - 0.2, np.sin(a) * r * 0.62, np.cos(a) * r * 0.62), (0.1, 0.22, 0.22))
        B.raw = False
        # cowl flaps behind the cowling and exhaust stubs
        B.set_mat(P['dark'])
        for i in range(3):
            for s in (1, -1):
                B.box((x0 - 0.15 - i * 0.22, -0.15, s * (rz + 0.04)), (0.14, 0.09, 0.08))

    def propeller(self):
        B, P, S = self.B, self.P, self.S
        x = self.xn + 0.12
        R = S['prop'] / 2
        B.set_mat(P['dark'])
        B.cyl((self.xn - 0.02, 0, 0), (x + 0.45, 0, 0), 0.3, 0.04, n=12)
        for i in range(S['blades']):
            a = i / S['blades'] * 2 * np.pi + 0.4
            d = np.array([0, np.sin(a), np.cos(a)])
            w = np.array([0, np.cos(a), -np.sin(a)])
            root = np.array([x, 0, 0]) + d * 0.22
            tip = np.array([x, 0, 0]) + d * R
            ch0, ch1 = 0.16, 0.11
            tw = np.array([0.06, 0, 0])
            B.set_mat(P['prop'])
            B.quad(tuple(root - w * ch0 + tw), tuple(root + w * ch0 - tw), tuple(tip - d * 0.25 + w * ch1 - tw), tuple(tip - d * 0.25 - w * ch1 + tw))
            B.set_mat(P['tip'])
            B.quad(tuple(tip - d * 0.25 - w * ch1 + tw), tuple(tip - d * 0.25 + w * ch1 - tw), tuple(tip + w * ch1 * 0.6), tuple(tip - w * ch1 * 0.6))

    def canopy(self):
        B, P, S = self.B, self.P, self.S
        c0, c1 = S['canopy']
        ry, rz, yc = self.radius(c1)
        top = yc + ry
        h = 0.55 if S['seats'] == 1 else 0.6
        w = rz * 0.62
        n = 8
        xs = list(np.linspace(c0, c1, 6))
        rings = []
        for i, x in enumerate(xs):
            ryx, rzx, ycx = self.radius(x)
            base = ycx + ryx * 0.82
            f = 1.0 if 0 < i < len(xs) - 1 else 0.55
            if i == len(xs) - 1:
                f = 0.35          # the windscreen slopes down to the cowling
            rings.append([(x, base + h * f * np.sin(a), w * np.cos(a)) for a in np.linspace(0, np.pi, n)])
        B.raw = True
        B.set_mat(P['glass'])
        for i in range(len(rings) - 1):
            for j in range(n - 1):
                B.quad(rings[i][j], rings[i][j + 1], rings[i + 1][j + 1], rings[i + 1][j])
        B.capfan(rings[-1])
        B.capfan(rings[0][::-1])
        # frames across and along the glazing
        B.set_mat(P['frame'])
        for i in range(1, len(xs) - 1):
            ring = rings[i]
            for j in range(n - 1):
                a, b = np.array(ring[j]), np.array(ring[j + 1])
                B.quad(tuple(a + [0.03, 0.01, 0]), tuple(b + [0.03, 0.01, 0]), tuple(b + [-0.03, 0.01, 0]), tuple(a + [-0.03, 0.01, 0]))
        mid = n // 2
        for i in range(len(rings) - 1):
            a, b = np.array(rings[i][mid]), np.array(rings[i + 1][mid])
            B.quad(tuple(a + [0, 0.015, -0.03]), tuple(b + [0, 0.015, -0.03]), tuple(b + [0, 0.015, 0.03]), tuple(a + [0, 0.015, 0.03]))
        B.raw = False
        # radio mast behind the canopy (US) / aerial mast (IJN)
        B.set_mat(P['dark'])
        xm = c0 - 0.35
        ryx, rzx, ycx = self.radius(xm)
        B.cyl((xm, ycx + ryx, 0), (xm - 0.2, ycx + ryx + 0.75, 0), 0.03, 0.02, n=4, caps=False)
        if S.get('turret'):
            # Avenger ball turret at the back of the glasshouse
            B.raw = True
            B.set_mat(P['glass'])
            B.cyl((c0 - 0.1, ycx + ryx + 0.2, 0), (c0 - 0.1, ycx + ryx + 0.85, 0), 0.5, 0.42, n=12)
            B.set_mat(P['dark'])
            B.cyl((c0 - 0.1, ycx + ryx + 0.55, 0), (c0 - 1.1, ycx + ryx + 0.6, 0), 0.04, n=5, caps=False)
            B.raw = False

    # ---------- wings and tail ----------
    def wing_point(self, side, s, c, t, panel):
        """Point on a wing at span s (from the root), chord position c (0 = leading edge), thickness t."""
        S = self.S
        half = S['span'] / 2
        z_root = S['fz'] * 0.9
        span = half - z_root
        chord = S['cr'] + (S['ct'] - S['cr']) * (s / span)
        le = self.wing_le - (S['cr'] - chord) * 0.25
        x = le - c * chord
        y = S['wy'] + s * np.tan(np.radians(S['dih'])) + t
        z = z_root + s
        p = np.array([x, y, z])
        fs = S['fold_at'] * span
        if panel == 'outer' and self.folded and S['fold'] != 'none':
            if S['fold'] == 'up' or S['fold'] == 'tips':
                hy = S['wy'] + fs * np.tan(np.radians(S['dih']))
                hz = z_root + fs
                phi = np.radians(100.0 if S['fold'] == 'up' else 90.0)
                dz, dy = z - hz, y - hy
                p = np.array([x, hy + dz * np.sin(phi) + dy * np.cos(phi), hz + dz * np.cos(phi) - dy * np.sin(phi)])
            else:
                # Grumman Sto-Wing: the panel turns on a skewed hinge and lies back along the
                # fuselage, leading edge down, top surface facing outboard
                ch_h = S['cr'] + (S['ct'] - S['cr']) * (fs / span)
                le_h = self.wing_le - (S['cr'] - ch_h) * 0.25
                sp = s - fs
                hy = S['wy'] + fs * np.tan(np.radians(S['dih']))
                p = np.array([le_h - ch_h * 0.55 - sp * 0.96,
                              hy - 0.35 + c * chord * 0.9,
                              z_root + fs + 0.12 + t])
        if side < 0:
            p[2] = -p[2]
        return tuple(p)

    def wing(self, side):
        B, P, S = self.B, self.P, self.S
        half = S['span'] / 2
        z_root = S['fz'] * 0.9
        span = half - z_root
        fs = S['fold_at'] * span
        th = S['cr'] * 0.065
        cs = [0.0, 0.28, 1.0]
        tt = [0.0, th, 0.0]
        tb = [0.0, -th * 0.55, 0.0]
        for panel, s0, s1, n in (('inner', 0.0, fs, 2), ('outer', fs, span, 4)) if S['fold'] != 'none' else (('inner', 0.0, span, 5),):
            ss = np.linspace(s0, s1, n + 1)
            for i in range(n):
                for j in range(2):
                    sa, sb = ss[i], ss[i + 1]
                    B.set_mat(P['top'])
                    B.quad(self.wing_point(side, sa, cs[j], tt[j], panel), self.wing_point(side, sb, cs[j], tt[j], panel),
                           self.wing_point(side, sb, cs[j + 1], tt[j + 1], panel), self.wing_point(side, sa, cs[j + 1], tt[j + 1], panel))
                    B.set_mat(P['under'])
                    B.quad(self.wing_point(side, sa, cs[j], tb[j], panel), self.wing_point(side, sb, cs[j], tb[j], panel),
                           self.wing_point(side, sb, cs[j + 1], tb[j + 1], panel), self.wing_point(side, sa, cs[j + 1], tb[j + 1], panel))
            # the end of the panel
            B.set_mat(P['side'])
            sl = s1 - 0.001 if panel == 'outer' or S['fold'] == 'none' else s1
            B.poly([self.wing_point(side, sl, cs[k], tt[k], panel) for k in range(3)] + [self.wing_point(side, sl, cs[k], tb[k], panel) for k in (1,)])
            if panel == 'inner' and S['fold'] != 'none':
                # hinge face
                B.set_mat(P['dark'])
                B.poly([self.wing_point(side, s1, cs[k], tt[k], panel) for k in range(3)])
        # national markings: US star on the upper port and lower starboard wing; IJN hinomaru on all four
        mid = span * 0.7
        pnl = 'outer' if S['fold'] != 'none' and mid > fs else 'inner'
        top = side < 0 if self.P is US else True
        if top:
            self.insignia(lambda u, v, d=0.0: self.wing_point(side, mid + v, 0.45 + u / max(S['ct'], 1.0), th * 0.85 + 0.02 + d, pnl), 0.55)
        if self.P is not US or side > 0:
            self.insignia(lambda u, v, d=0.0: self.wing_point(side, mid + v, 0.45 + u / max(S['ct'], 1.0), -th * 0.5 - 0.02 - d, pnl), 0.55, flip=True)
        # wing guns in the leading edge
        if S['guns']:
            B.set_mat(P['dark'])
            for g in range(S['guns']):
                sg = span * (0.28 + 0.06 * g) if S['fold'] != 'sto' or not self.folded else span * (0.12 + 0.04 * g)
                pnl2 = 'inner' if sg < fs or S['fold'] == 'none' else 'outer'
                a = np.array(self.wing_point(side, sg, 0.02, 0.0, pnl2))
                b = np.array(self.wing_point(side, sg, -0.18, 0.0, pnl2))
                B.cyl(tuple(a), tuple(b), 0.035, n=5, caps=False)

    def insignia(self, at, r, flip=False):
        """A roundel laid on a surface: at(u, v, lift) maps local (u fore-aft, v span) to a point."""
        B, P = self.B, self.P
        B.raw = True
        n = 14
        def disc(rad, mat, lift):
            B.set_mat(mat)
            pts = [at(np.cos(a) * rad, np.sin(a) * rad, lift) for a in np.linspace(0, 2 * np.pi, n, endpoint=False)]
            B.poly(pts[::-1] if flip else pts)
        if P is US:
            disc(r, P['disc'], 0.0)
            # the white star and the side bars
            B.set_mat(P['star'])
            pts = []
            for k in range(10):
                a = np.pi / 2 + k * np.pi / 5
                rr = r * 0.92 if k % 2 == 0 else r * 0.37
                pts.append(at(np.sin(a) * rr, np.cos(a) * rr, 0.01))
            c = at(0, 0, 0.01)
            for k in range(10):
                tri = [c, pts[k], pts[(k + 1) % 10]]
                B.tri(*(tri[::-1] if flip else tri))
            for sgn in (1, -1):
                q = [at(-r * 0.28, sgn * r * 0.75, 0.01), at(-r * 0.28, sgn * r * 1.75, 0.01), at(r * 0.28, sgn * r * 1.75, 0.01), at(r * 0.28, sgn * r * 0.75, 0.01)]
                B.quad(*(q[::-1] if flip else q))
        else:
            disc(r, P['red'], 0.0)
        B.raw = False

    def tail(self):
        B, P, S = self.B, self.P, self.S
        x0 = self.xt + 1.6
        ry, rz, yc = self.radius(x0)
        half = S['tail'] / 2
        cr, ct = 1.35, 0.7
        th = 0.07
        for side in (1, -1):
            def tp(s, c, t):
                chord = cr + (ct - cr) * s / half
                return (x0 + 0.35 - c * chord, yc + 0.05 + t, side * (0.1 + s))
            for c0, c1 in ((0.0, 0.3), (0.3, 1.0)):
                t0 = th if c0 > 0 else 0.0
                t1 = th if c1 < 1 else 0.0
                B.set_mat(P['top'])
                B.quad(tp(0, c0, t0), tp(half, c0, t0), tp(half, c1, t1), tp(0, c1, t1))
                B.set_mat(P['under'])
                B.quad(tp(0, c0, -t0), tp(half, c0, -t0), tp(half, c1, -t1), tp(0, c1, -t1))
        # fin and rudder
        h = S['fin']
        def fp(s, c, t):
            chord = 1.6 + (0.7 - 1.6) * s / h
            return (x0 + 0.6 - c * chord - s * 0.35, yc + ry * 0.6 + s, t)
        for c0, c1 in ((0.0, 0.35), (0.35, 1.0)):
            t0 = 0.08 if c0 > 0 else 0.0
            t1 = 0.08 if c1 < 1 else 0.0
            for sgn in (1, -1):
                B.set_mat(P['side'] if c1 < 1 else P['top'])
                B.quad(fp(0, c0, sgn * t0), fp(h, c0, sgn * t0), fp(h, c1, sgn * t1), fp(0, c1, sgn * t1))
        # rudder hinge line
        B.raw = True
        B.set_mat(P['frame'])
        for sgn in (1, -1):
            a, b = np.array(fp(0, 0.62, sgn * 0.09)), np.array(fp(h, 0.62, sgn * 0.09))
            B.quad(tuple(a + [0.02, 0, 0]), tuple(b + [0.02, 0, 0]), tuple(b - [0.02, 0, 0]), tuple(a - [0.02, 0, 0]))
        B.raw = False

    def fuselage_markings(self):
        S = self.S
        x = self.xt + S['L'] * 0.3
        ry, rz, yc = self.radius(x)
        r = min(ry * 0.75, 0.55)
        for side in (1, -1):
            self.insignia(lambda u, v, d=0.0, side=side: (x + v, yc + u, side * (rz + 0.02 + d)), r, flip=side > 0)

    def stores(self):
        B, P, S = self.B, self.P, self.S
        if S.get('bomb'):
            B.set_mat(P['bomb'])
            y = S['wy'] - 0.5
            B.cyl((self.wing_le + 0.6, y, 0), (self.wing_le - 1.3, y, 0), 0.22, 0.2, n=10)
            B.cyl((self.wing_le + 0.6, y, 0), (self.wing_le + 0.95, y, 0), 0.22, 0.05, n=10, caps=False)
            for s in (1, -1):
                B.box((self.wing_le - 1.25, y, s * 0.18), (0.3, 0.02, 0.3))
        if S.get('torp'):
            B.set_mat(P['metal'])
            y = -S['fy'] - 0.2
            B.cyl((self.wing_le + 1.2, y, 0), (self.wing_le - 3.6, y, 0), 0.23, n=10, caps=False)
            B.cyl((self.wing_le + 1.2, y, 0), (self.wing_le + 1.6, y, 0), 0.23, 0.08, n=10, caps=False)
            B.set_mat(P['dark'])
            for s in (1, -1):
                B.box((self.wing_le - 3.7, y, s * 0.2), (0.35, 0.02, 0.35))

    def landing_gear(self):
        """Main legs and wheels under the wing, a tail wheel; Val's fixed spatted gear."""
        B, P, S = self.B, self.P, self.S
        x_m = self.wing_le - S['cr'] * 0.12
        track = S['fz'] * 2.6
        drop = S['gear']                         # wheel axle below the fuselage centreline
        wr = S['wheel']
        for side in (1, -1):
            top = (x_m, S['wy'], side * track * 0.45)
            axle = (x_m + 0.05, -drop, side * track * 0.5)
            if S.get('spats'):
                B.set_mat(P['under'])
                B.cyl(top, (axle[0], axle[1] + wr * 0.6, axle[2]), 0.12, 0.1, n=6)
                B.cyl((axle[0] + 0.55, axle[1], axle[2]), (axle[0] - 0.75, axle[1], axle[2]), 0.12, 0.22, n=10)
                B.set_mat(P['tyre'])
                B.cyl((axle[0], axle[1] - 0.05, axle[2] - 0.06), (axle[0], axle[1] - 0.05, axle[2] + 0.06), wr * 0.55, n=10)
            else:
                B.set_mat(P['metal'])
                B.cyl(top, axle, 0.07, 0.06, n=6)
                B.set_mat(P['tyre'])
                B.cyl((axle[0], axle[1], axle[2] - side * 0.1), (axle[0], axle[1], axle[2] + side * 0.1), wr, n=14)
                B.set_mat(P['metal'])
                B.cyl((axle[0], axle[1], axle[2] + side * 0.11), (axle[0], axle[1], axle[2] + side * 0.13), wr * 0.45, n=10)
        # tail wheel and arresting hook
        xt = self.xt + 1.2
        ry, rz, yc = self.radius(xt)
        B.set_mat(P['metal'])
        B.cyl((xt, yc - ry * 0.8, 0), (xt + 0.05, yc - ry - 0.35, 0), 0.04, n=5, caps=False)
        B.set_mat(P['tyre'])
        B.cyl((xt + 0.05, yc - ry - 0.35, -0.07), (xt + 0.05, yc - ry - 0.35, 0.07), 0.18, n=10)
        B.set_mat(P['dark'])
        B.cyl((self.xt + 0.5, yc - ry * 0.7, 0), (self.xt + 1.6, yc - ry - 0.15, 0), 0.025, n=4, caps=False)
        return (x_m, -drop - wr), (xt + 0.05, yc - ry - 0.35 - 0.18)

    def build(self):
        self.fuselage()
        self.cowling()
        self.propeller()
        self.canopy()
        for side in (1, -1):
            self.wing(side)
        self.tail()
        self.fuselage_markings()
        self.stores()
        main = tail = None
        if self.gear or self.S.get('spats'):
            main, tail = self.landing_gear()
        # attitude: on deck the plane sits on its main wheels and tail wheel, nose up;
        # flying it is level with the centreline at the same height as on deck
        if self.gear and main is not None:
            alpha = np.arctan2(main[1] - tail[1], main[0] - tail[0])
            R = _rot('z', -alpha)
            pts = np.array([[main[0], main[1], 0.0], [tail[0], tail[1], 0.0]]) @ R.T
            off = np.array([0.0, -pts[:, 1].min(), 0.0])
        else:
            spec_ground = self.S['gear'] + self.S['wheel']
            R = np.eye(3)
            off = np.array([0.0, spec_ground + 0.35, 0.0])
        for g in self.M.groups.values():
            g['tris'] = [t @ R.T + off for t in g['tris']]
        return self.M


def build(t, variant='fly'):
    spec = TYPES[t]
    if variant == 'fly':
        p = Plane(t, spec, folded=False, gear=False, flying=True)
    elif variant == 'deck':
        p = Plane(t, spec, folded=False, gear=True, flying=False)
    else:
        p = Plane(t, spec, folded=True, gear=True, flying=False)
    return p.build()


def parked_width(t):
    """Athwartships room a parked plane takes (wings folded where they folded, never less than the tailplane)."""
    return max(_fold_width(t), TYPES[t]['tail'] + 0.1)


def _fold_width(t):
    S = TYPES[t]
    if S['fold'] == 'sto':
        z_root = S['fz'] * 0.9
        return 2 * (z_root + S['fold_at'] * (S['span'] / 2 - z_root) + 0.12 + S['cr'] * 0.07) + 0.2
    if S['fold'] == 'up':
        z_root = S['fz'] * 0.9
        return 2 * (z_root + S['fold_at'] * (S['span'] / 2 - z_root)) + 0.9
    if S['fold'] == 'tips':
        z_root = S['fz'] * 0.9
        return 2 * (z_root + S['fold_at'] * (S['span'] / 2 - z_root)) + 0.3
    return S['span']


AIRCRAFT_MODELS = [(t, v) for t in TYPES for v in ('fly', 'deck', 'folded')]
