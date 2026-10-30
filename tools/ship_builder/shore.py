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

SHORE = [('shore_battery', build_battery), ('supply_dump', build_dump), ('raft', build_raft)]
