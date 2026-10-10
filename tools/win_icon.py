"""Replace the icon resources inside a Godot-exported Windows exe, in place.
No rcedit needed. usage: python3 tools/win_icon.py build.exe icon1024.png icon256.png"""
import struct, sys, zlib

exe_path, png1024, png256 = sys.argv[1:4]

def decode_png(path):
    f = open(path, 'rb').read(); pos = 8; idat = b''; w = h = 0; ct = 0
    while pos < len(f):
        ln = struct.unpack('>I', f[pos:pos+4])[0]; t = f[pos+4:pos+8]; d = f[pos+8:pos+8+ln]; pos += 12 + ln
        if t == b'IHDR': w, h, bd, ct = struct.unpack('>IIBB', d[:10])
        elif t == b'IDAT': idat += d
    bpp = 4 if ct == 6 else 3
    raw = zlib.decompress(idat); stride = w * bpp; rows = []; prev = bytearray(stride); i = 0
    for y in range(h):
        ft = raw[i]; i += 1; line = bytearray(raw[i:i+stride]); i += stride
        for x in range(stride):
            a = line[x-bpp] if x >= bpp else 0; b = prev[x]; c = prev[x-bpp] if x >= bpp else 0
            if ft == 1: line[x] = (line[x] + a) & 255
            elif ft == 2: line[x] = (line[x] + b) & 255
            elif ft == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif ft == 4:
                p = a + b - c; pa, pb, pc = abs(p-a), abs(p-b), abs(p-c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255
        rows.append(bytes(line)); prev = line
    px = [[(r[x*bpp], r[x*bpp+1], r[x*bpp+2], r[x*bpp+3] if bpp == 4 else 255) for x in range(w)] for r in rows]
    return w, h, px

W, H, PX = decode_png(png1024)

def resample(size):
    out = []
    for y in range(size):
        y0 = int(y * H / size); y1 = max(y0 + 1, int((y + 1) * H / size))
        row = []
        for x in range(size):
            x0 = int(x * W / size); x1 = max(x0 + 1, int((x + 1) * W / size))
            r = g = b = a = 0; n = 0
            for yy in range(y0, y1):
                for xx in range(x0, x1):
                    p = PX[yy][xx]; r += p[0]; g += p[1]; b += p[2]; a += p[3]; n += 1
            row.append((r//n, g//n, b//n, a//n))
        out.append(row)
    return out

def dib(size):
    px = resample(size)
    hdr = struct.pack('<IiiHHIIiiII', 40, size, size * 2, 1, 32, 0, size*size*4 + size*size//8, 0, 0, 0, 0)
    body = bytearray()
    for y in range(size - 1, -1, -1):
        for x in range(size):
            r, g, b, a = px[y][x]
            body += bytes((b, g, r, a))
    mask_stride = ((size + 31) // 32) * 4
    mask = bytes(mask_stride * size)
    return hdr + bytes(body) + mask

f = bytearray(open(exe_path, 'rb').read())
pe = struct.unpack_from('<I', f, 0x3c)[0]
nsec = struct.unpack_from('<H', f, pe + 6)[0]; opt = struct.unpack_from('<H', f, pe + 20)[0]
sec0 = pe + 24 + opt
rsrc = None
for i in range(nsec):
    o = sec0 + i * 40
    if f[o:o+8].rstrip(b'\0') == b'.rsrc':
        vs, va, rs, rp = struct.unpack_from('<IIII', f, o + 8); rsrc = (va, rp)
va, rp = rsrc
def walk(off, path):
    n_named, n_id = struct.unpack_from('<HH', f, rp + off + 12); out = []
    for i in range(n_named + n_id):
        e = rp + off + 16 + i * 8; nm, data = struct.unpack_from('<II', f, e); ident = nm & 0x7fffffff
        if data & 0x80000000: out += walk(data & 0x7fffffff, path + [ident])
        else: out.append((path + [ident], rp + data))
    return out
entries = walk(0, [])
icons = {e[0][1]: e[1] for e in entries if e[0][0] == 3}
groups = [e[1] for e in entries if e[0][0] == 14]
png256 = open(png256, 'rb').read()
for gde in groups:
    grva, gsize = struct.unpack_from('<II', f, gde); go = grva - va + rp
    cnt = struct.unpack_from('<HHH', f, go)[2]
    for i in range(cnt):
        eo = go + 6 + i * 14
        w, h, cc, res, planes, bpp, size, idn = struct.unpack_from('<BBBBHHIH', f, eo)
        w = w or 256
        de = icons[idn]; drva, dsize = struct.unpack_from('<II', f, de); doff = drva - va + rp
        is_png = f[doff:doff+4] == b'\x89PNG'
        if is_png:
            assert len(png256) <= dsize, "256px PNG larger than the slot"
            f[doff:doff+dsize] = png256 + bytes(dsize - len(png256))
            struct.pack_into('<I', f, de + 4, len(png256))
            struct.pack_into('<I', f, eo + 8, len(png256))
            print("png slot", w, "->", len(png256), "bytes")
        else:
            d = dib(w)
            assert len(d) == dsize, (w, len(d), dsize)
            f[doff:doff+dsize] = d
            print("dib slot", w, "ok")
open(exe_path, 'wb').write(f)
print("patched", exe_path)
