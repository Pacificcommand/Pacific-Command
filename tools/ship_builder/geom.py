"""Mesh building helpers. Internal axes: x = forward (bow), y = up, z = starboard. Units: meters."""
import numpy as np

class Mesh:
    def __init__(self):
        self.groups = {}          # name -> dict(pivot, tris list of (3x3 array), colors)

    def group(self, name, pivot=(0, 0, 0)):
        if name not in self.groups:
            self.groups[name] = {'pivot': np.array(pivot, float), 'tris': [], 'mats': []}
        return self.groups[name]

class Builder:
    """Adds triangles to one group with one material."""
    def __init__(self, mesh, group, mat, pivot=(0, 0, 0)):
        self.g = mesh.group(group, pivot)
        self.mat = mat
        self.xf = None   # optional 3x3 rotation + offset applied to added points

    def set_mat(self, mat):
        self.mat = mat
        return self

    def tri(self, a, b, c):
        t = np.array([a, b, c], float)
        if self.xf is not None:
            R, o = self.xf
            t = t @ R.T + o
        self.g['tris'].append(t)
        self.g['mats'].append(self.mat)

    def quad(self, a, b, c, d):
        self.tri(a, b, c)
        self.tri(a, c, d)

    def poly(self, pts):
        """Fan-triangulate a convex polygon (list of 3D points, any winding)."""
        for i in range(1, len(pts) - 1):
            self.tri(pts[0], pts[i], pts[i + 1])

    # ---- primitives ----
    def box(self, c, s, top_inset=0.0):
        cx, cy, cz = c
        sx, sy, sz = s[0] / 2, s[1] / 2, s[2] / 2
        ti = top_inset
        b = [(cx - sx, cy - sy, cz - sz), (cx + sx, cy - sy, cz - sz), (cx + sx, cy - sy, cz + sz), (cx - sx, cy - sy, cz + sz)]
        t = [(cx - sx + ti, cy + sy, cz - sz + ti), (cx + sx - ti, cy + sy, cz - sz + ti), (cx + sx - ti, cy + sy, cz + sz - ti), (cx - sx + ti, cy + sy, cz + sz - ti)]
        self.poly(t)
        self.poly(b[::-1])
        for i in range(4):
            j = (i + 1) % 4
            self.quad(b[i], b[j], t[j], t[i])

    def prism(self, plan, y0, y1, inset=0.0, top=True, bottom=False):
        """Extrude a plan polygon (list of (x, z)) from y0 to y1. Top may be inset (sloped sides)."""
        plan = [tuple(p) for p in plan]
        if inset:
            cx = sum(p[0] for p in plan) / len(plan)
            cz = sum(p[1] for p in plan) / len(plan)
            tp = []
            for x, z in plan:
                dx, dz = x - cx, z - cz
                d = (dx * dx + dz * dz) ** .5 or 1
                tp.append((x - dx / d * inset, z - dz / d * inset))
        else:
            tp = plan
        n = len(plan)
        for i in range(n):
            j = (i + 1) % n
            self.quad((plan[i][0], y0, plan[i][1]), (plan[j][0], y0, plan[j][1]), (tp[j][0], y1, tp[j][1]), (tp[i][0], y1, tp[i][1]))
        if top:
            self.capfan([(x, y1, z) for x, z in tp])
        if bottom:
            self.capfan([(x, y0, z) for x, z in plan])

    def capfan(self, pts):
        c = np.mean(np.array(pts), axis=0)
        n = len(pts)
        for i in range(n):
            self.tri(tuple(c), pts[i], pts[(i + 1) % n])

    def cyl(self, a, b, r0, r1=None, n=16, caps=True, rz_scale=1.0):
        """Frustum between points a and b."""
        r1 = r0 if r1 is None else r1
        a = np.array(a, float); b = np.array(b, float)
        ax = b - a
        L = np.linalg.norm(ax)
        ax = ax / L
        tmp = np.array([0, 1, 0]) if abs(ax[1]) < .9 else np.array([1, 0, 0])
        u = np.cross(ax, tmp); u /= np.linalg.norm(u)
        v = np.cross(ax, u)
        ra, rb = [], []
        for i in range(n):
            t = i / n * 2 * np.pi
            d = u * np.cos(t) + v * np.sin(t) * rz_scale
            ra.append(a + d * r0)
            rb.append(b + d * r1)
        for i in range(n):
            j = (i + 1) % n
            self.quad(ra[i], ra[j], rb[j], rb[i])
        if caps:
            self.capfan([tuple(p) for p in rb])
            self.capfan([tuple(p) for p in ra[::-1]])
        return ra, rb

    def ellipse_plan(self, cx, cz, rx, rz, n=24):
        return [(cx + np.cos(t) * rx, cz + np.sin(t) * rz) for t in np.linspace(0, 2 * np.pi, n, endpoint=False)]


def rot_y(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rounded_plan(x_front, x_back, half, r_front, n=10, r_back=0.6):
    """Deckhouse plan: rounded front (bow side), small corner radius aft."""
    pts = []
    # front arc from port to starboard
    for t in np.linspace(-np.pi / 2, np.pi / 2, n):
        pts.append((x_front - r_front + np.cos(t) * r_front, np.sin(t) * half))
    pts.append((x_back + r_back, half))
    pts.append((x_back, half - r_back))
    pts.append((x_back, -half + r_back))
    pts.append((x_back + r_back, -half))
    return pts
