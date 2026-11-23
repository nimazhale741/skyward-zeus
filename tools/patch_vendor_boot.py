#!/usr/bin/env python3
"""Give a zeus vendor_boot image a cnss2 that stops waiting for DMS.

cnss2's cnss_setup_dms_mac() asks the modem's DMS service for the WLAN MAC
200 times, 50 ms apart, before giving up and reading persist/wlan_mac.bin.
A recovery has no modem, so it wastes ~10 s at every boot. This rewrites the
retry count in the module the vendor_boot ramdisk carries, without changing
the image layout: the ramdisk is recompressed with LZ4 HC to exactly the size
the image declares, and every other byte stays where it was.

Only use it on vendor_boot images from the phone it belongs to (same ROM
build as the running system); the modules inside are tied to that kernel.

Usage:
    python patch_vendor_boot.py vendor_boot.img vendor_boot-dmsfix.img

Needs the `lz4` package for the high-compression encoder:
    pip install lz4

Afterwards, from a recovery with root adb:
    adb push vendor_boot-dmsfix.img /sdcard/
    adb shell su -c 'dd if=/sdcard/vendor_boot-dmsfix.img of=/dev/block/by-name/vendor_boot_a bs=1M && sync'
    adb reboot
Keep a backup of the old image first.
"""
import argparse
import struct
import sys

LZ4_MAGIC = 0x184C2102
CMN_W0_11 = 0x31002C00  # cmn w0, #0xb   (-EAGAIN)
MOV_W0_50 = 0x52800640  # mov w0, #0x32  (50 ms)
SUBS_W1 = 0x71000400    # subs wN, wN, #1 is matched by mask below


def align(n, unit):
    return (n + unit - 1) // unit * unit


def lz4_decode(src):
    if len(src) < 8 or struct.unpack_from("<I", src)[0] != LZ4_MAGIC:
        raise SystemExit("the ramdisk is not an lz4 legacy stream")
    pos, out = 4, bytearray()
    while pos + 4 <= len(src):
        (csize,) = struct.unpack_from("<I", src, pos)
        pos += 4
        if csize == 0:
            break
        end = pos + csize
        if end > len(src):
            raise SystemExit("an lz4 block runs past the stream")
        while pos < end:
            token = src[pos]
            pos += 1
            lit = token >> 4
            if lit == 15:
                while True:
                    b = src[pos]
                    pos += 1
                    lit += b
                    if b != 255:
                        break
            out += src[pos:pos + lit]
            pos += lit
            if pos >= end:
                break
            offset = src[pos] | (src[pos + 1] << 8)
            pos += 2
            mlen = (token & 0xF) + 4
            if (token & 0xF) == 15:
                while True:
                    b = src[pos]
                    pos += 1
                    mlen += b
                    if b != 255:
                        break
            start = len(out) - offset
            if start < 0:
                raise SystemExit("an lz4 match points before the output")
            if offset >= mlen:
                out += out[start:start + mlen]
            else:
                for i in range(mlen):
                    out.append(out[start + i])
    return bytes(out)


def lz4_encode(data, block, level):
    try:
        import lz4.block as lb
    except ImportError:
        raise SystemExit("needs the lz4 package: pip install lz4")
    out = bytearray(struct.pack("<I", LZ4_MAGIC))
    for at in range(0, len(data), block):
        chunk = data[at:at + block]
        comp = lb.compress(chunk, mode="high_compression", compression=level, store_size=False)
        out += struct.pack("<I", len(comp)) + comp
    return bytes(out)


def cpio_parse(buf):
    entries, pos = [], 0
    while True:
        if buf[pos:pos + 6] != b"070701":
            raise SystemExit("not a newc cpio archive at offset %d" % pos)
        f = [int(buf[pos + 6 + 8 * i:pos + 14 + 8 * i], 16) for i in range(13)]
        ino, mode, uid, gid, nlink, mtime, size, dmaj, dmin, rmaj, rmin, namesize, _ = f
        name_at = pos + 110
        name = buf[name_at:name_at + namesize - 1].decode("utf-8", "surrogateescape")
        data_at = align(name_at + namesize, 4)
        data = buf[data_at:data_at + size]
        pos = align(data_at + size, 4)
        if name == "TRAILER!!!":
            return entries
        entries.append({
            "name": name, "ino": ino, "mode": mode, "uid": uid, "gid": gid,
            "nlink": nlink, "mtime": mtime, "dev": (dmaj, dmin), "rdev": (rmaj, rmin),
            "data": data,
        })


def cpio_build(entries):
    out = bytearray()

    def add(e):
        name = e["name"].encode("utf-8", "surrogateescape") + b"\0"
        data = e["data"]
        fields = (e["ino"], e["mode"], e["uid"], e["gid"], e["nlink"], e["mtime"],
                  len(data), e["dev"][0], e["dev"][1], e["rdev"][0], e["rdev"][1], len(name), 0)
        out.extend(b"070701" + b"".join(b"%08x" % v for v in fields))
        out.extend(name)
        out.extend(b"\0" * (align(len(out), 4) - len(out)))
        out.extend(data)
        out.extend(b"\0" * (align(len(out), 4) - len(out)))

    for e in entries:
        add(e)
    add({"name": "TRAILER!!!", "ino": 0, "mode": 0, "uid": 0, "gid": 0, "nlink": 1,
         "mtime": 0, "dev": (0, 0), "rdev": (0, 0), "data": b""})
    return bytes(out)


def patch_module(ko, verbose=True):
    """Find the movz #200 / cmn w0,#0xb / msleep loop and make it one round."""
    def is_movz(insn):
        return (insn & 0xFFE00000) == 0x52800000

    def movz_imm(insn):
        return (insn >> 5) & 0xFFFF

    def is_cmn_w0_11(insn):
        # cmn w0, #0xb: ADDS wzr, w0, #11 — Rd is wzr, so the low 5 bits are 31.
        return (insn & 0xFF800000) == 0x31000000 and ((insn >> 10) & 0xFFF) == 0xB and (insn & 0x1F) == 31

    for at in range(0, len(ko) - 4, 4):
        (insn,) = struct.unpack_from("<I", ko, at)
        if not is_cmn_w0_11(insn):
            continue
        # the count is set a few instructions before the compare
        for back in range(at - 4, max(-1, at - 4 * 24), -4):
            (cand,) = struct.unpack_from("<I", ko, back)
            if not is_movz(cand) or movz_imm(cand) != 200:
                continue
            # after the compare comes the 50 ms sleep and the countdown
            tail = [struct.unpack_from("<I", ko, at + 4 * i)[0] for i in range(1, 5) if at + 4 * i + 4 <= len(ko)]
            if not any(is_movz(t) and movz_imm(t) == 50 for t in tail):
                continue
            subs = [struct.unpack_from("<I", ko, at + 4 * i)[0] for i in range(1, 7) if at + 4 * i + 4 <= len(ko)]
            if not any((t & 0xFF800000) == 0x71000000 and ((t >> 10) & 0xFFF) == 1 for t in subs):
                continue
            patched = (cand & ~(0xFFFF << 5)) | (1 << 5)
            struct.pack_into("<I", ko, back, patched)
            if verbose:
                print("patched cnss2 at module offset %#x: movz #200 -> #1 (loop at %#x)" % (back, at))
            return ko, back, at
    raise SystemExit("could not find the DMS retry loop in cnss2.ko (different build?)")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input")
    ap.add_argument("output")
    args = ap.parse_args()

    img = bytearray(open(args.input, "rb").read())
    if img[:8] != b"VNDRBOOT":
        raise SystemExit("not a vendor_boot image (magic %r)" % bytes(img[:8]))
    page, = struct.unpack_from("<I", img, 12)
    ramdisk_size, = struct.unpack_from("<I", img, 24)
    header_size, = struct.unpack_from("<I", img, 2096)
    if header_size < 28 or header_size > page:
        header_size = 2128
    start = align(header_size, page)
    raw = bytes(img[start:start + ramdisk_size])
    if len(raw) != ramdisk_size:
        raise SystemExit("the image is shorter than its vendor_ramdisk_size")
    cpio = lz4_decode(raw)
    entries = cpio_parse(cpio)
    target = None
    for e in entries:
        if e["name"] == "lib/modules/cnss2.ko":
            target = e
            break
    if target is None:
        raise SystemExit("the ramdisk carries no lib/modules/cnss2.ko")
    ko = bytearray(target["data"])
    if (struct.unpack_from("<I", ko, 0)[0] & 0xFFFFFFFF) != 0x464C457F:
        raise SystemExit("cnss2.ko is not an ELF file")
    _, offset, _ = patch_module(ko)
    target["data"] = bytes(ko)
    new_cpio = cpio_build(entries)

    enc = None
    for block in (8 << 20, 4 << 20, 1 << 20):
        for level in (12, 9):
            candidate = lz4_encode(new_cpio, block, level)
            if len(candidate) <= ramdisk_size:
                enc = candidate
                print("lz4 block %d MiB, level %d: %d of %d bytes" % (block >> 20, level, len(candidate), ramdisk_size))
                break
        if enc:
            break
    if enc is None:
        raise SystemExit("could not compress the ramdisk back into %d bytes" % ramdisk_size)
    stream = enc + b"\0" * (ramdisk_size - len(enc))
    img[start:start + ramdisk_size] = stream
    open(args.output, "wb").write(bytes(img))

    # check what we wrote: the stream must decode to the patched archive,
    # and the module inside it must carry the new instruction.
    back = lz4_decode(stream)
    assert back == new_cpio, "the recompressed ramdisk does not decode to the new archive"
    check = {e["name"]: e for e in cpio_parse(back)}
    cell = struct.unpack_from("<I", check["lib/modules/cnss2.ko"]["data"], offset)[0]
    assert ((cell >> 5) & 0xFFFF) == 1, "the patched instruction did not survive"
    print("wrote %s: ramdisk %d bytes, cnss2 patched at %#x, %d entries" %
          (args.output, ramdisk_size, offset, len(entries)))


if __name__ == "__main__":
    main()