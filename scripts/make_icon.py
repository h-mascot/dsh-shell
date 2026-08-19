from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
source = ROOT / '.build/icon-render-blue-v5/deepseek-icon.svg.png'
out = ROOT / 'Resources/app-icon-1024.png'

rendered = Image.open(source).convert('RGBA')
white = Image.new('RGBA', rendered.size, (255, 255, 255, 255))
diff = ImageChops.difference(rendered, white).convert('L')
mask = diff.point([0 if i <= 12 else 255 for i in range(256)]).filter(ImageFilter.GaussianBlur(0.6))
content = mask.getbbox()
if not content:
    raise SystemExit('official DeepSeek mark did not render')
mark = mask.crop(content)
mark.thumbnail((560, 560), Image.Resampling.LANCZOS)

canvas = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
shadow = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
shadow_draw = ImageDraw.Draw(shadow)
shadow_draw.rounded_rectangle((72, 82, 952, 962), radius=205, fill=(11, 26, 80, 90))
shadow = shadow.filter(ImageFilter.GaussianBlur(34))
canvas.alpha_composite(shadow)

tile_mask = Image.new('L', canvas.size, 0)
ImageDraw.Draw(tile_mask).rounded_rectangle((64, 54, 960, 950), radius=205, fill=255)
gradient = Image.new('RGBA', canvas.size)
pixels = gradient.load()
assert pixels is not None
start = (84, 116, 255)
end = (50, 86, 224)
for y in range(1024):
    for x in range(1024):
        t = min(1.0, max(0.0, (x + y) / 2048.0))
        pixels[x, y] = tuple(round(a + (b-a)*t) for a, b in zip(start, end)) + (255,)
canvas.alpha_composite(Image.composite(gradient, Image.new('RGBA', canvas.size), tile_mask))

shine = Image.new('RGBA', canvas.size, (0,0,0,0))
shine_mask = Image.new('L', canvas.size, 0)
ImageDraw.Draw(shine_mask).ellipse((-220, -330, 1040, 680), fill=90)
shine = Image.composite(Image.new('RGBA', canvas.size, (255,255,255,65)), shine, shine_mask)
shine.putalpha(ImageChops.multiply(shine.getchannel('A'), tile_mask))
canvas.alpha_composite(shine)

white_mark = Image.new('RGBA', mark.size, (255,255,255,255))
white_mark.putalpha(mark)
x = (1024 - mark.width) // 2
y = (1004 - mark.height) // 2
canvas.alpha_composite(white_mark, (x, y))
canvas.save(out, optimize=True)
print(out)
