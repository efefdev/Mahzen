"""Küçük bir QR kod üreticisi (ISO/IEC 18004): bayt kipi, M düzeyi hata düzeltme.

“Telefonda Göster” adresini QR koda çevirmek için; dağıtımlarda ek bir paket gerektirmesin diye saf Python.
Çıktı, `True` = koyu olan kare bir modül matrisidir (sessiz bölge dahil değildir).
"""

from __future__ import annotations

# Sürüm başına (dizin = sürüm, 0 kullanılmaz) M düzeyi için blok başına hata düzeltme baytı ve blok sayısı.
_ECC_PER_BLOCK = [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26,
                  28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28]
_BLOCKS = [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25,
           26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49]
_FORMAT_ECL_M = 0  # biçim bilgisindeki iki bit: L=1, M=0, Q=3, H=2


def _raw_modules(version: int) -> int:
    result = (16 * version + 128) * version + 64
    if version >= 2:
        align = version // 7 + 2
        result -= (25 * align - 10) * align - 55
        if version >= 7:
            result -= 36
    return result


def _data_codewords(version: int) -> int:
    return _raw_modules(version) // 8 - _ECC_PER_BLOCK[version] * _BLOCKS[version]


def _gf_mul(x: int, y: int) -> int:
    z = 0
    for i in reversed(range(8)):
        z = (z << 1) ^ ((z >> 7) * 0x11D)
        z ^= ((y >> i) & 1) * x
    return z & 0xFF


def _rs_divisor(degree: int) -> list[int]:
    result = [0] * (degree - 1) + [1]
    root = 1
    for _ in range(degree):
        for j in range(degree):
            result[j] = _gf_mul(result[j], root)
            if j + 1 < degree:
                result[j] ^= result[j + 1]
        root = _gf_mul(root, 0x02)
    return result


def _rs_remainder(data: list[int], divisor: list[int]) -> list[int]:
    result = [0] * len(divisor)
    for b in data:
        factor = b ^ result.pop(0)
        result.append(0)
        for i, coef in enumerate(divisor):
            result[i] ^= _gf_mul(coef, factor)
    return result


def _alignment_positions(version: int) -> list[int]:
    if version == 1:
        return []
    count = version // 7 + 2
    size = version * 4 + 17
    step = (version * 8 + count * 3 + 5) // (count * 4 - 4) * 2
    return list(reversed([size - 7 - i * step for i in range(count - 1)] + [6]))


def _mask_bit(mask: int, x: int, y: int) -> bool:
    return [
        (x + y) % 2 == 0,
        y % 2 == 0,
        x % 3 == 0,
        (x + y) % 3 == 0,
        (x // 3 + y // 2) % 2 == 0,
        x * y % 2 + x * y % 3 == 0,
        (x * y % 2 + x * y % 3) % 2 == 0,
        ((x + y) % 2 + x * y % 3) % 2 == 0,
    ][mask]


class _Builder:
    def __init__(self, version: int):
        self.version = version
        self.size = version * 4 + 17
        self.dark = [[False] * self.size for _ in range(self.size)]
        self.function = [[False] * self.size for _ in range(self.size)]

    def set_function(self, x: int, y: int, dark: bool) -> None:
        self.dark[y][x] = dark
        self.function[y][x] = True

    def draw_function_patterns(self) -> None:
        size = self.size
        for i in range(size):
            self.set_function(6, i, i % 2 == 0)
            self.set_function(i, 6, i % 2 == 0)
        for cx, cy in ((3, 3), (size - 4, 3), (3, size - 4)):
            for dy in range(-4, 5):
                for dx in range(-4, 5):
                    x, y = cx + dx, cy + dy
                    if 0 <= x < size and 0 <= y < size:
                        self.set_function(x, y, max(abs(dx), abs(dy)) not in (2, 4))
        positions = _alignment_positions(self.version)
        last = len(positions) - 1
        for i, ay in enumerate(positions):
            for j, ax in enumerate(positions):
                if (i, j) in ((0, 0), (0, last), (last, 0)):
                    continue
                for dy in range(-2, 3):
                    for dx in range(-2, 3):
                        self.set_function(ax + dx, ay + dy, max(abs(dx), abs(dy)) != 1)
        self.draw_format(0)
        if self.version >= 7:
            rem = self.version
            for _ in range(12):
                rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
            bits = self.version << 12 | rem
            for i in range(18):
                bit = (bits >> i) & 1 == 1
                a, b = size - 11 + i % 3, i // 3
                self.set_function(a, b, bit)
                self.set_function(b, a, bit)

    def draw_format(self, mask: int) -> None:
        data = _FORMAT_ECL_M << 3 | mask
        rem = data
        for _ in range(10):
            rem = (rem << 1) ^ ((rem >> 9) * 0x537)
        bits = (data << 10 | rem) ^ 0x5412
        bit = lambda i: (bits >> i) & 1 == 1  # noqa: E731
        for i in range(6):
            self.set_function(8, i, bit(i))
        self.set_function(8, 7, bit(6))
        self.set_function(8, 8, bit(7))
        self.set_function(7, 8, bit(8))
        for i in range(9, 15):
            self.set_function(14 - i, 8, bit(i))
        size = self.size
        for i in range(8):
            self.set_function(size - 1 - i, 8, bit(i))
        for i in range(8, 15):
            self.set_function(8, size - 15 + i, bit(i))
        self.set_function(8, size - 8, True)

    def draw_codewords(self, data: list[int]) -> None:
        size = self.size
        i = 0
        right = size - 1
        while right >= 1:
            if right == 6:
                right = 5
            for vert in range(size):
                for j in range(2):
                    x = right - j
                    upward = (right + 1) & 2 == 0
                    y = size - 1 - vert if upward else vert
                    if not self.function[y][x] and i < len(data) * 8:
                        self.dark[y][x] = (data[i >> 3] >> (7 - (i & 7))) & 1 == 1
                        i += 1
            right -= 2

    def apply_mask(self, mask: int) -> None:
        for y in range(self.size):
            for x in range(self.size):
                if not self.function[y][x] and _mask_bit(mask, x, y):
                    self.dark[y][x] = not self.dark[y][x]

    def penalty(self) -> int:
        size, dark = self.size, self.dark
        score = 0
        lines = [row for row in dark] + [[dark[y][x] for y in range(size)] for x in range(size)]
        finder_a = [True, False, True, True, True, False, True, False, False, False, False]
        finder_b = finder_a[::-1]
        for line in lines:
            run = 1
            for k in range(1, size + 1):
                if k < size and line[k] == line[k - 1]:
                    run += 1
                else:
                    if run >= 5:
                        score += 3 + (run - 5)
                    run = 1
            for k in range(size - 10):
                window = line[k:k + 11]
                if window == finder_a or window == finder_b:
                    score += 40
        for y in range(size - 1):
            for x in range(size - 1):
                c = dark[y][x]
                if c == dark[y][x + 1] == dark[y + 1][x] == dark[y + 1][x + 1]:
                    score += 3
        total = size * size
        black = sum(sum(row) for row in dark)
        score += abs(black * 20 - total * 10) // total * 10
        return score


def _codewords(text: bytes, version: int) -> list[int]:
    count_bits = 8 if version <= 9 else 16
    capacity = _data_codewords(version) * 8
    bits: list[int] = []

    def append(value: int, length: int) -> None:
        bits.extend((value >> i) & 1 for i in reversed(range(length)))

    append(0b0100, 4)
    append(len(text), count_bits)
    for b in text:
        append(b, 8)
    if len(bits) > capacity:
        raise ValueError("data too long for this QR version")
    append(0, min(4, capacity - len(bits)))
    append(0, -len(bits) % 8)
    pad = 0xEC
    while len(bits) < capacity:
        append(pad, 8)
        pad ^= 0xEC ^ 0x11
    data = [int("".join(map(str, bits[i:i + 8])), 2) for i in range(0, len(bits), 8)]

    blocks_count, ecc_len = _BLOCKS[version], _ECC_PER_BLOCK[version]
    raw = _raw_modules(version) // 8
    short_count = blocks_count - raw % blocks_count
    short_len = raw // blocks_count
    divisor = _rs_divisor(ecc_len)
    blocks = []
    k = 0
    for i in range(blocks_count):
        length = short_len - ecc_len + (0 if i < short_count else 1)
        dat = data[k:k + length]
        k += length
        ecc = _rs_remainder(dat, divisor)
        if i < short_count:
            dat = dat + [0]
        blocks.append(dat + ecc)
    result = []
    for i in range(len(blocks[0])):
        for j, block in enumerate(blocks):
            if i != short_len - ecc_len or j >= short_count:
                result.append(block[i])
    return result


def encode(text: str | bytes, version: int | None = None, mask: int | None = None) -> list[list[bool]]:
    """Metni QR modül matrisine çevirir. Sürüm verilmezse sığan en küçük sürüm, maske verilmezse
    en düşük cezalı maske seçilir."""
    data = text.encode("utf-8") if isinstance(text, str) else bytes(text)
    if version is None:
        for v in range(1, 41):
            if 4 + (8 if v <= 9 else 16) + 8 * len(data) <= _data_codewords(v) * 8:
                version = v
                break
        else:
            raise ValueError("data too long for a QR code")
    codewords = _codewords(data, version)
    best = None
    for m in ([mask] if mask is not None else range(8)):
        builder = _Builder(version)
        builder.draw_function_patterns()
        builder.draw_codewords(codewords)
        builder.apply_mask(m)
        builder.draw_format(m)
        score = builder.penalty() if mask is None else 0
        if best is None or score < best[0]:
            best = (score, builder)
    return best[1].dark
