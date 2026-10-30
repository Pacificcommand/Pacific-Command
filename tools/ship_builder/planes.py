"""Aircraft models for the air war: one small glb per family, wings spread, built at real size.
Fighters (Wildcat/Hellcat, Zero), dive and torpedo bombers (Dauntless/Avenger, Val/Kate) and
floatplanes (Kingfisher, Jake). Each is a single 'Hull' group plus a 'Prop' group."""
import numpy as np
from geom import Mesh, Builder
from warship import PAL, aircraft, floatplane

def build_plane(nation, kind):
    P = dict(PAL[nation])
    if nation == 'ijn':
        P['plane'] = '#6d7a5c' if kind != 'fighter' else '#9a9f8e'
        P['planew'] = '#7f8a6a' if kind != 'fighter' else '#a9ae9d'
    else:
        P['plane'] = '#2d3f55'
        P['planew'] = '#4f6680'
    M = Mesh()
    B = Builder(M, 'Hull', P['plane'])
    if kind == 'float':
        floatplane(B, P, 0, 0, 0, 0.0, span=11.0, length=10.0, twin_float=(nation == 'ijn'))
    else:
        span, length = (11.6, 9.0) if kind == 'fighter' else (16.0, 12.0)
        aircraft(B, P, 0, 0, 0, 0.0, span=span, length=length, folded=False)
        if nation == 'ijn':
            # hinomaru on the wings
            B.set_mat(P['red'])
            for s in (1, -1):
                B.cyl((length * 0.02, 1.12, s * span * 0.33), (length * 0.02, 1.16, s * span * 0.33), 0.9, n=12)
        else:
            B.set_mat('#e8e8e8')
            for s in (1, -1):
                B.cyl((length * 0.02, 1.12, s * span * 0.33), (length * 0.02, 1.16, s * span * 0.33), 0.7, n=12)
    return M

PLANES = [('plane_us_fighter', 'us', 'fighter'), ('plane_us_bomber', 'us', 'bomber'), ('plane_us_float', 'us', 'float'),
          ('plane_jp_fighter', 'ijn', 'fighter'), ('plane_jp_bomber', 'ijn', 'bomber'), ('plane_jp_float', 'ijn', 'float')]
