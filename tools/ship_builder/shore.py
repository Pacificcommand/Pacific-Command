"""Shore targets and small craft: a coastal gun battery, a supply dump and a life raft."""
import numpy as np
from geom import Mesh, Builder
from warship import PAL, turret

def build_battery():
    P = dict(PAL['ijn']); P.update(dict(concrete='#8d8a7e', sand='#b8a77c', earth='#5c4a33', log='#6b4b2a'))
    M = Mesh()
    B = Builder(M, 'Hull', P['concrete'])
    # concrete casemate with an earth bank around it
    B.set_mat(P['earth'])
    B.prism([(14, -14), (14, 14), (-14, 14), (-14, -14)], 0.0, 2.0, inset=2.5)
    B.set_mat(P['sand'])
    for x, z in [(10, -9), (10, 9), (-9, 10), (-9, -10)]:
        B.cyl((x, 2.0, z), (x, 3.2, z), 2.0, 1.6, n=10)
    B.set_mat(P['concrete'])
    B.prism([(6, -7), (6, 7), (-6, 7), (-6, -7)], 2.0, 5.2, inset=0.6)
    B.set_mat(P['log'])
    for z in (-5, 0, 5):
        B.cyl((7.5, 5.0, z), (-7.5, 5.0, z), 0.35, n=8)
    # two guns on the roof in a shallow pit, named so they train
    for i, z in enumerate((-3.0, 3.0)):
        turret(M, 'Gun%d' % (i + 1), (1.0, 5.2, z), 0.0, P, 140, 1)
    return M

def build_dump():
    P = dict(PAL['ijn']); P.update(dict(hut='#7a6a4a', roof='#4a3a2a', crate='#8c7a55', drum='#4d5a4c', sand='#b8a77c'))
    M = Mesh()
    B = Builder(M, 'Hull', P['hut'])
    for x, z, lx, lz in [(0, 0, 12, 8), (-14, 6, 8, 6), (10, -10, 9, 7)]:
        B.set_mat(P['hut'])
        B.box((x, 1.8, z), (lx, 3.6, lz))
        B.set_mat(P['roof'])
        B.prism([(x + lx / 2 + 0.6, z - lz / 2 - 0.6), (x + lx / 2 + 0.6, z + lz / 2 + 0.6), (x - lx / 2 - 0.6, z + lz / 2 + 0.6), (x - lx / 2 - 0.6, z - lz / 2 - 0.6)], 3.6, 5.4, inset=min(lx, lz) / 2 - 0.5)
    B.set_mat(P['crate'])
    for i in range(14):
        B.box((-6 + (i % 7) * 1.6, 0.6, 8 + (i // 7) * 1.6), (1.4, 1.2, 1.4))
    B.set_mat(P['drum'])
    for i in range(18):
        B.cyl((10 + (i % 6) * 1.1, 0, 6 + (i // 6) * 1.1), (10 + (i % 6) * 1.1, 1.0, 6 + (i // 6) * 1.1), 0.45, n=8)
    return M

def build_raft():
    P = dict(PAL['us']); P.update(dict(raft='#6b6f5c', canvas='#8a8468', skin='#c9a27a', vest='#c7b24a'))
    M = Mesh()
    B = Builder(M, 'Hull', P['raft'])
    pts = [(np.cos(t) * 2.6, np.sin(t) * 1.6) for t in np.linspace(0, 2 * np.pi, 14, endpoint=False)]
    B.prism(pts, -0.2, 0.5, inset=0.0)
    B.set_mat(P['canvas'])
    B.prism([(p[0] * 0.65, p[1] * 0.55) for p in pts], 0.5, 0.55)
    B.set_mat(P['vest'])
    for x, z in [(1.0, 0.4), (-0.6, 0.6), (0.2, -0.6), (-1.3, -0.3)]:
        B.cyl((x, 0.55, z), (x, 1.0, z), 0.3, n=8)
        B.set_mat(P['skin']); B.cyl((x, 1.0, z), (x, 1.3, z), 0.18, n=8); B.set_mat(P['vest'])
    return M

def build_airfield():
    """An island airstrip: the runway (x along it, 1000 m), with hangars, a control tower, fuel
    tanks, earth revetments for the planes and anti-aircraft pits along the north side (+z)."""
    P = dict(PAL['ijn']); P.update(dict(strip='#a59f8c', line='#d8d2bd', hangar='#6f7363', roof='#565a4c',
        tower='#8b8574', tank='#5d6655', earth='#6b5a3e', sand='#b8a77c', gun='#3c3f38'))
    M = Mesh()
    B = Builder(M, 'Hull', P['strip'])
    # the runway surface (rolled coral or earth, a little darker than the cleared ground) and its marks
    B.box((0, 0.08, 0), (1000.0, 0.16, 45.0))
    B.set_mat(P['line'])
    for i in range(-11, 12):
        B.box((i * 42.0, 0.17, 0), (20.0, 0.04, 1.2))
    for sx in (-1, 1):
        for k in range(6):
            B.box((sx * 488.0, 0.17, -15 + k * 6.0), (14.0, 0.04, 2.5))
    # taxiway and apron to the north
    B.set_mat(P['strip'])
    B.box((0, 0.06, 52.0), (420.0, 0.12, 50.0))
    B.box((-260, 0.06, 36.0), (22.0, 0.12, 50.0))
    B.box((260, 0.06, 36.0), (22.0, 0.12, 50.0))
    # hangars: low walls with a curved (polygonal) roof
    for hx in (-120.0, -40.0, 60.0):
        B.set_mat(P['hangar'])
        B.box((hx, 3.0, 96.0), (54.0, 6.0, 34.0))
        B.set_mat(P['roof'])
        arc = [(np.cos(t) * 17.5, 6.0 + np.sin(t) * 7.0) for t in np.linspace(0, np.pi, 9)]
        for j in range(len(arc) - 1):
            (z0, y0), (z1, y1) = arc[j], arc[j + 1]
            zc, yc = (z0 + z1) / 2, (y0 + y1) / 2
            ln = np.hypot(z1 - z0, y1 - y0)
            B.box((hx, yc, 96.0 + zc), (55.0, 0.5, ln + 0.3))
    # the control tower and the operations hut
    B.set_mat(P['tower'])
    B.box((150.0, 4.5, 84.0), (7.0, 9.0, 7.0))
    B.box((150.0, 10.0, 84.0), (9.5, 2.4, 9.5))
    B.set_mat(P['roof'])
    B.box((150.0, 11.4, 84.0), (10.5, 0.4, 10.5))
    B.set_mat(P['hangar'])
    B.box((175.0, 2.0, 92.0), (22.0, 4.0, 10.0))
    # fuel tanks
    B.set_mat(P['tank'])
    for k in range(4):
        B.cyl((220.0 + (k % 2) * 16.0, 0, 110.0 + (k // 2) * 16.0), (220.0 + (k % 2) * 16.0, 6.0, 110.0 + (k // 2) * 16.0), 6.0, n=16)
    # U-shaped earth revetments for parked planes along the apron
    B.set_mat(P['earth'])
    for k in range(8):
        rx = -330.0 + k * 34.0 + (300.0 if k >= 4 else 0.0)
        B.box((rx, 1.2, 128.0), (20.0, 2.4, 3.0))
        B.box((rx - 9.0, 1.2, 120.0), (3.0, 2.4, 16.0))
        B.box((rx + 9.0, 1.2, 120.0), (3.0, 2.4, 16.0))
    # anti-aircraft gun pits round the field, named so the guns train
    for i, (gx, gz) in enumerate([(-420.0, 70.0), (0.0, 140.0), (380.0, 70.0), (-200.0, -60.0), (240.0, -60.0)]):
        B.set_mat(P['sand'])
        B.cyl((gx, 0, gz), (gx, 1.4, gz), 5.0, 4.6, n=12)
        turret(M, 'AA%d' % (i + 1), (gx, 1.4, gz), 0.0, P, 60, 2, shielded=False)
    return M

SHORE = [('shore_battery', build_battery), ('supply_dump', build_dump), ('raft', build_raft), ('airfield', build_airfield)]
