#!/usr/bin/env python3
"""Read-only signature, entropy, and string analysis for router firmware blobs."""

from __future__ import annotations

import argparse
import hashlib
import math
from collections import Counter
from pathlib import Path
import re


MAGICS = {
    "squashfs_le": b"hsqs",
    "squashfs_be": b"sqsh",
    "jffs2_18_85": b"\x19\x85",
    "jffs2_85_19": b"\x85\x19",
    "ubi": b"UBI#",
    "ubifs": b"\x31\x18\x10\x06",
    "uimage": b"\x27\x05\x19\x56",
    "gzip": b"\x1f\x8b",
    "xz": b"\xfd7zXZ\x00",
    "bzip2": b"BZh",
    "trx": b"HDR0",
    "elf": b"\x7fELF",
    "netgear_dni": b"device:",
}

KEYWORDS = (
    "wndr",
    "netgear",
    "u-boot",
    "bootloader",
    "jffs",
    "squash",
    "printer",
    "laserjet",
    "p910nd",
    "usb",
    "readyShare",
    "upnp",
    "ddns",
    "qos",
    "ipv6",
    "genie",
    "firmware",
    "board",
    "openwrt",
    "sihp1020",
    "hp1020",
)


def entropy(data: bytes) -> float:
    if not data:
        return 0.0
    counts = Counter(data)
    length = len(data)
    return -sum((n / length) * math.log2(n / length) for n in counts.values())


def ascii_strings(data: bytes, minimum: int = 8):
    for match in re.finditer(rb"[\x20-\x7e]{%d,}" % minimum, data):
        yield match.start(), match.group().decode("ascii", "replace")


def find_all(data: bytes, magic: bytes, limit: int = 64):
    offsets = []
    position = 0
    while len(offsets) < limit:
        offset = data.find(magic, position)
        if offset < 0:
            break
        offsets.append(offset)
        position = offset + 1
    return offsets


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    parser.add_argument("--block-size", type=int, default=65536)
    parser.add_argument("--min-string", type=int, default=8)
    args = parser.parse_args()

    data = args.image.read_bytes()
    print(f"path={args.image.resolve()}")
    print(f"size={len(data)}")
    print(f"sha256={hashlib.sha256(data).hexdigest()}")
    print("first_256_hex=" + data[:256].hex())

    print("\n[magic offsets]")
    for name, magic in MAGICS.items():
        offsets = find_all(data, magic)
        if offsets:
            print(f"{name}: {offsets}")

    print("\n[high-entropy 64KiB blocks >= 7.5 bits/byte]")
    high_entropy = []
    for offset in range(0, len(data), args.block_size):
        block = data[offset : offset + args.block_size]
        value = entropy(block)
        if value >= 7.5:
            high_entropy.append((offset, value))
    for offset, value in high_entropy[:128]:
        print(f"0x{offset:08x} {value:.4f}")
    print(f"high_entropy_block_count={len(high_entropy)}")

    print("\n[keyword strings]")
    found = 0
    for offset, text in ascii_strings(data, args.min_string):
        lowered = text.lower()
        if any(keyword.lower() in lowered for keyword in KEYWORDS):
            print(f"0x{offset:08x} {text[:240]}")
            found += 1
            if found >= 500:
                break
    print(f"keyword_string_count_shown={found}")


if __name__ == "__main__":
    main()
