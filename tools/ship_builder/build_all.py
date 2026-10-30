"""Rebuild every ship model into assets/models (run from this folder: python build_all.py).
Needs Python 3 with numpy (and Pillow for preview renders)."""
import os
from render import export_glb
from fletcher import build as fletcher
from kagero import build as kagero
from pt_elco import build as pt_elco
from daihatsu import build as daihatsu
from merchant import build_cargo, build_tanker
from warship import build_spec
import specs

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'assets', 'models')
SHIPS = [
    ('fletcher_m21', 'Fletcher', lambda: fletcher('m21')),
    ('fletcher_m22', 'Fletcher', lambda: fletcher('m22')),
    ('kagero', 'Kagero', kagero),
    ('pt_elco', 'PTBoat', pt_elco),
    ('daihatsu', 'Daihatsu', daihatsu),
    ('cargo_maru', 'CargoMaru', build_cargo),
    ('tanker_maru', 'TankerMaru', build_tanker),
]
for name in specs.SPECS:
    SHIPS.append((name, name.title().replace('_', ''), (lambda n: (lambda: build_spec(specs.SPECS[n])))(name)))
from planes import PLANES, build_plane
for name, nation, kind in PLANES:
    SHIPS.append((name, name.title().replace('_', ''), (lambda n, k: (lambda: build_plane(n, k)))(nation, kind)))
for name, root, fn in SHIPS:
    M = fn()
    M.rootname = root
    export_glb(M, os.path.join(OUT, name + '.glb'))
    print('built', name)
