"""Inventra brand assets: an isometric 'inventory box' woven with kente-style
stripes and a mudcloth-style diamond on top. Original artwork."""
import math, cairosvg

INDIGO = '#14213D'
GOLD = '#F2B705'
TERRA = '#C8412B'
GREEN = '#1E8F4E'
CREAM = '#FFF4E0'
INK = '#0B1226'

def mark(cx=512, cy=540, s=250, pattern=True):
    """Cube centred on (cx, cy). s = half-width."""
    h = s * math.tan(math.radians(30))          # rise of the top edges
    T = (cx, cy - 2*h); R = (cx + s, cy - h); C = (cx, cy); L = (cx - s, cy - h)
    side = s * 1.16                              # height of the side faces
    BL = (cx - s, cy - h + side); B = (cx, cy + side); BR = (cx + s, cy - h + side)
    P = lambda pts: ' '.join(f'{x:.1f},{y:.1f}' for x, y in pts)
    out = []
    out.append(f'<clipPath id="cl"><polygon points="{P([L,C,B,BL])}"/></clipPath>')
    out.append(f'<clipPath id="cr"><polygon points="{P([C,R,BR,B])}"/></clipPath>')
    out.append(f'<clipPath id="ct"><polygon points="{P([T,R,C,L])}"/></clipPath>')
    out.append(f'<polygon points="{P([L,C,B,BL])}" fill="{TERRA}"/>')
    out.append(f'<polygon points="{P([C,R,BR,B])}" fill="{GREEN}"/>')
    out.append(f'<polygon points="{P([T,R,C,L])}" fill="{GOLD}"/>')
    if pattern:
        slope = h / s
        # Kente bands on the left face: lines parallel to its top edge (L->C, rising to the right? L is higher)
        def band(clip, x0, x1, y_at_x0, slope, offsets, color, w):
            for o in offsets:
                out.append(f'<line x1="{x0-40}" y1="{y_at_x0+o - slope*40:.1f}" x2="{x1+40}" '
                           f'y2="{y_at_x0+o + slope*(x1-x0+40):.1f}" stroke="{color}" '
                           f'stroke-width="{w}" clip-path="url(#{clip})"/>')
        def zigzag(clip, x0, x1, y_at_x0, slope, off, amp, step, color, w):
            pts = []; x = x0 - step; i = 0
            while x <= x1 + step:
                y = y_at_x0 + off + slope*(x - x0) + (amp if i % 2 else -amp)
                pts.append((x, y)); x += step; i += 1
            out.append(f'<polyline points="{P(pts)}" fill="none" stroke="{color}" stroke-width="{w}" '
                       f'stroke-linejoin="miter" clip-path="url(#{clip})"/>')
        # left face: top edge goes from L (high) down to C => slope +slope
        yL = L[1]
        band('cl', L[0], C[0], yL, slope, [side*0.22, side*0.26], CREAM, 7)
        zigzag('cl', L[0], C[0], yL, slope, side*0.47, 16, 34, INK, 9)
        band('cl', L[0], C[0], yL, slope, [side*0.68, side*0.72], CREAM, 7)
        # right face: top edge from C (low) up to R => slope -slope
        yC = C[1]
        band('cr', C[0], R[0], yC, -slope, [side*0.22, side*0.26], CREAM, 7)
        zigzag('cr', C[0], R[0], yC, -slope, side*0.47, 16, 34, INK, 9)
        band('cr', C[0], R[0], yC, -slope, [side*0.68, side*0.72], CREAM, 7)
        # top face: nested diamonds (mudcloth-style) + centre dot
        tc = (cx, cy - h)
        for k, col, w in [(0.62, INDIGO, 10), (0.36, INDIGO, 10)]:
            d = [(tc[0], tc[1] - h*k), (tc[0] + s*k, tc[1]), (tc[0], tc[1] + h*k), (tc[0] - s*k, tc[1])]
            out.append(f'<polygon points="{P(d)}" fill="none" stroke="{col}" stroke-width="{w}" clip-path="url(#ct)"/>')
        out.append(f'<circle cx="{tc[0]}" cy="{tc[1]}" r="{s*0.075:.1f}" fill="{INDIGO}"/>')
        # dots along the outer top edges, like stitched cloth
        for t in [0.2, 0.4, 0.6, 0.8]:
            for a, b in [(T, R), (T, L)]:
                x = a[0] + (b[0]-a[0])*t; y = a[1] + (b[1]-a[1])*t + h*0.13
                out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="6" fill="{INDIGO}"/>')
    # crisp edges
    out.append(f'<polyline points="{P([L,C,R])}" fill="none" stroke="{INK}" stroke-opacity="0.35" stroke-width="5"/>')
    out.append(f'<line x1="{C[0]}" y1="{C[1]}" x2="{B[0]}" y2="{B[1]}" stroke="{INK}" stroke-opacity="0.35" stroke-width="5"/>')
    return '\n'.join(out)

def svg(body, w=1024, h=1024, bg=None, radius=0):
    bgs = '' if bg is None else f'<rect width="{w}" height="{h}" rx="{radius}" fill="{bg}"/>'
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{bgs}{body}</svg>'

def kente_strip(y, w, hgt=36):
    """A thin woven border strip used on the splash and wordmark."""
    cols = [GOLD, GREEN, TERRA, GOLD, INDIGO, GREEN]
    out = []; x = 0; i = 0; bw = 48
    while x < w:
        out.append(f'<rect x="{x}" y="{y}" width="{bw}" height="{hgt}" fill="{cols[i % len(cols)]}"/>')
        out.append(f'<rect x="{x+bw*0.42:.1f}" y="{y}" width="{bw*0.16:.1f}" height="{hgt}" fill="{CREAM}" opacity="0.85"/>')
        x += bw; i += 1
    return '\n'.join(out)

def write(name, content, size=None):
    open(f'{name}.svg', 'w').write(content)
    cairosvg.svg2png(bytestring=content.encode(), write_to=f'{name}.png',
                     output_width=size, output_height=size if size else None)

# 1. Logo (rounded square) for display
logo = svg(mark(), bg=INDIGO, radius=224)
write('inventra_logo', logo, 1024)
# 2. App icon, full bleed (iOS/Android legacy)
write('app_icon', svg(mark(), bg=INDIGO), 1024)
# 3. Android adaptive foreground: mark inside the 66% safe zone, transparent
write('app_icon_foreground', svg(mark(cx=512, cy=560, s=190)), 1024)
# 4. Splash image: mark only, transparent (Android 12 shows it inside a circle)
write('splash_logo', svg(mark(cx=512, cy=560, s=200)), 1024)
# 5. Wordmark for the splash bottom / branding (transparent)
word = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="300" viewBox="0 0 1200 300">
<text x="600" y="175" text-anchor="middle" font-family="Poppins" font-weight="700" font-size="150" fill="{CREAM}" letter-spacing="4">Inventra</text>
<text x="600" y="250" text-anchor="middle" font-family="Poppins" font-weight="500" font-size="40" fill="{GOLD}" letter-spacing="10">SALES · STOCK · GROWTH</text>
</svg>'''
write('splash_branding', word)
# 6. Full brand card (logo + wordmark) to show the user
card = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="900" viewBox="0 0 1600 900">
<rect width="1600" height="900" fill="{INDIGO}"/>
{kente_strip(0, 1600, 28)}{kente_strip(872, 1600, 28)}
<g transform="translate(130,170) scale(0.55)">{mark()}</g>
<text x="760" y="440" font-family="Poppins" font-weight="700" font-size="150" fill="{CREAM}">Inventra</text>
<text x="766" y="515" font-family="Poppins" font-weight="500" font-size="40" fill="{GOLD}" letter-spacing="10">SALES · STOCK · GROWTH</text>
</svg>'''
write('inventra_brand', card)
# 7. Splash preview (what the phone shows)
prev = f'''<svg xmlns="http://www.w3.org/2000/svg" width="540" height="1170" viewBox="0 0 540 1170">
<rect width="540" height="1170" fill="{INDIGO}"/>
<g transform="translate(90,330) scale(0.35)">{mark(cx=512, cy=560, s=200)}</g>
<g transform="translate(70,960) scale(0.333)"><text x="600" y="175" text-anchor="middle" font-family="Poppins" font-weight="700" font-size="150" fill="{CREAM}" letter-spacing="4">Inventra</text>
<text x="600" y="250" text-anchor="middle" font-family="Poppins" font-weight="500" font-size="40" fill="{GOLD}" letter-spacing="10">SALES · STOCK · GROWTH</text></g>
</svg>'''
write('splash_preview', prev)
print('done')
