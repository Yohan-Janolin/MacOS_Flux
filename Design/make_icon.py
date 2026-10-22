import io, sys, cairosvg
from PIL import Image, ImageFilter

DEFS = '''
<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#FFB054"/><stop offset="0.5" stop-color="#FF6A3D"/><stop offset="1" stop-color="#E8336B"/>
</linearGradient>
<linearGradient id="shine" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.26"/><stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0"/>
</linearGradient>
<clipPath id="sq"><rect x="100" y="100" width="824" height="824" rx="185" ry="185"/></clipPath>
'''
def svg(body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><defs>{DEFS}</defs>{body}</svg>'

BG = svg('''
<rect x="100" y="100" width="824" height="824" rx="185" ry="185" fill="url(#bg)"/>
<g clip-path="url(#sq)">
  <rect x="100" y="100" width="824" height="824" fill="url(#shine)"/>
</g>''')

GLYPH = svg('''
<g fill="none" stroke="#FFFFFF" stroke-width="82.8" stroke-linecap="round">
  <circle cx="269.5" cy="754.5" r="55.8" fill="#FFFFFF" stroke="none"/>
  <path d="M 269.5 547.5 A 207.0 207.0 0 0 1 476.5 754.5" stroke-opacity="1"/>
  <path d="M 269.5 394.5 A 360.0 360.0 0 0 1 629.5 754.5" stroke-opacity="1"/>
  <!-- troisième onde, plus pâle : le flux qui s'estompe -->
  <path d="M 269.5 255.0 A 499.5 499.5 0 0 1 769.0 754.5" stroke-opacity="0.38"/>
</g>''')

def render(s, size=1024):
    return Image.open(io.BytesIO(cairosvg.svg2png(bytestring=s.encode(), output_width=size, output_height=size))).convert("RGBA")

def shadow(layer, blur, dy, opacity, color=(0, 0, 0)):
    a = layer.getchannel("A").filter(ImageFilter.GaussianBlur(blur)).point(lambda v: int(v * opacity))
    sh = Image.new("RGBA", layer.size, color + (0,))
    sh.putalpha(a)
    out = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    out.paste(sh, (0, dy), sh)
    return out

bg, glyph = render(BG), render(GLYPH)
icon = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
icon = Image.alpha_composite(icon, shadow(bg, 14, 12, 0.32))
icon = Image.alpha_composite(icon, bg)
icon = Image.alpha_composite(icon, shadow(glyph, 10, 8, 0.22, (120, 20, 40)))
icon = Image.alpha_composite(icon, glyph)
icon.save(sys.argv[1])
