"""Dev update video: python3 make.py OUT.mp4 "END CARD TITLE" clip.avi "Title" "One line" [clip.avi "Title" "Line" ...]
Each clip: the first 8 frames (menu) dropped, 5.5 s kept, a caption panel bottom left of centre (clear of
the ship dial), a DEV UPDATE tag top centre; then a 3 s end card. 1920x1080, 30 fps, H.264. Needs ffmpeg, PIL."""
import sys, os, subprocess, tempfile
from PIL import Image, ImageDraw, ImageFont

def font(sz, bold=False):
    for p in (['/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'] if bold else []) + ['/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf']:
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()

def wrap(d, text, f, width):
    lines, cur = [], ''
    for w in text.split():
        t = (cur + ' ' + w).strip()
        if d.textlength(t, font=f) > width and cur:
            lines.append(cur); cur = w
        else:
            cur = t
    return lines + [cur]

def overlay(path, title, line):
    im = Image.new('RGBA', (1920, 1080), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    ft, fl, fg = font(30, True), font(22), font(18, True)
    lines = wrap(d, line, fl, 610)
    h = 62 + 30 * len(lines)
    x0, y1 = 440, 1062
    d.rounded_rectangle((x0, y1 - h, x0 + 650, y1), 8, fill=(8, 20, 30, 225), outline=(214, 170, 80, 255), width=2)
    d.text((x0 + 18, y1 - h + 12), title, font=ft, fill=(240, 200, 110, 255))
    for i, l in enumerate(lines):
        d.text((x0 + 18, y1 - h + 54 + 30 * i), l, font=fl, fill=(235, 238, 240, 255))
    d.rounded_rectangle((880, 150, 1040, 184), 6, fill=(214, 170, 80, 255))
    d.text((960, 167), 'DEV UPDATE', font=fg, fill=(10, 20, 28, 255), anchor='mm')
    im.save(path)

def endcard(path, title, items):
    im = Image.new('RGB', (1920, 1080), (8, 20, 30)); d = ImageDraw.Draw(im)
    d.text((960, 330), 'PACIFIC COMMAND', font=font(34, True), fill=(214, 170, 80), anchor='mm')
    d.text((960, 420), title, font=font(64, True), fill=(240, 242, 244), anchor='mm')
    for i, t in enumerate(items):
        d.text((960, 540 + 46 * i), t, font=font(30), fill=(190, 200, 206), anchor='mm')
    im.save(path)

out, title, rest = sys.argv[1], sys.argv[2], sys.argv[3:]
tmp = tempfile.mkdtemp()
parts = []
for i in range(0, len(rest), 3):
    clip, t, l = rest[i:i + 3]
    ov = os.path.join(tmp, 'ov%d.png' % i); overlay(ov, t, l)
    part = os.path.join(tmp, 'p%d.mp4' % i)
    subprocess.check_call(['ffmpeg', '-v', 'error', '-y', '-i', clip, '-i', ov, '-filter_complex',
        '[0:v]trim=start_frame=8,setpts=PTS-STARTPTS,scale=1920:1080[v];[v][1:v]overlay=0:0,format=yuv420p',
        '-t', '5.5', '-r', '30', '-an', '-c:v', 'libx264', '-crf', '20', part])
    parts.append(part)
ec = os.path.join(tmp, 'end.png'); endcard(ec, title, [rest[i + 1] for i in range(0, len(rest), 3)])
part = os.path.join(tmp, 'end.mp4')
subprocess.check_call(['ffmpeg', '-v', 'error', '-y', '-loop', '1', '-i', ec, '-t', '3', '-r', '30', '-vf', 'format=yuv420p', '-c:v', 'libx264', '-crf', '20', part])
parts.append(part)
lst = os.path.join(tmp, 'list.txt'); open(lst, 'w').write(''.join("file '%s'\n" % p for p in parts))
subprocess.check_call(['ffmpeg', '-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', lst, '-c', 'copy', out])
print(out)
