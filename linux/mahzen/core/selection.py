"""Izgarada dikdörtgenle seçim ve önizlemede gezinme için arayüzden bağımsız hesaplar."""

from __future__ import annotations

Rect = tuple[float, float, float, float]  # x, y, genişlik, yükseklik

MARQUEE_THRESHOLD = 4  # piksel; bundan kısa sürükleme tıklama sayılır
AUTOSCROLL_EDGE = 48  # görünür alanın kenarına bu kadar yaklaşınca kaydırma başlar
AUTOSCROLL_MAX = 28  # kare başına en fazla kaydırma (piksel)


def rect_from_points(start: tuple[float, float], current: tuple[float, float]) -> Rect:
    return (min(start[0], current[0]), min(start[1], current[1]),
            abs(current[0] - start[0]), abs(current[1] - start[1]))


def intersects(a: Rect, b: Rect) -> bool:
    return a[0] <= b[0] + b[2] and b[0] <= a[0] + a[2] and a[1] <= b[1] + b[3] and b[1] <= a[1] + a[3]


def marquee_selection(base: set, frames: dict, rect: Rect) -> set:
    """Dikdörtgene değen öğeler seçilir. `base` (Ctrl/Shift ile korunan seçim) verilirse dikdörtgendekiler
    onun içinde tersine çevrilir (macOS Finder ve macOS sürümüyle aynı)."""
    return set(base) ^ {key for key, frame in frames.items() if intersects(frame, rect)}


def autoscroll_speed(y: float, height: float) -> float:
    """İmlecin görünür alandaki konumuna göre kare başına kaydırma: kenara yaklaştıkça hızlanır."""
    if y < AUTOSCROLL_EDGE:
        return -min(AUTOSCROLL_MAX, (AUTOSCROLL_EDGE - y) * 0.6)
    if y > height - AUTOSCROLL_EDGE:
        return min(AUTOSCROLL_MAX, (y - (height - AUTOSCROLL_EDGE)) * 0.6)
    return 0.0


def point_from_result(result) -> tuple[float, float] | None:
    """GTK'nin nokta dönüşümü sonucunu (x, y) yapar. Sürüme göre `compute_point` (ok, Graphene.Point) ya da
    Graphene.Point, kullanımdan kalkan `translate_coordinates` ise (ok, x, y) ya da (x, y) döndürür."""
    if result is None or result is False:
        return None
    parts = result if isinstance(result, tuple) else (result,)
    if parts and isinstance(parts[0], bool):
        if not parts[0]:
            return None
        parts = parts[1:]
    if len(parts) == 1 and hasattr(parts[0], "x") and hasattr(parts[0], "y"):
        return float(parts[0].x), float(parts[0].y)
    if len(parts) == 2 and all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in parts):
        return float(parts[0]), float(parts[1])
    return None


def rect_from_result(result) -> Rect | None:
    """`compute_bounds` sonucunu (x, y, genişlik, yükseklik) yapar: (ok, Graphene.Rect) ya da Graphene.Rect."""
    if result is None or result is False:
        return None
    parts = result if isinstance(result, tuple) else (result,)
    if parts and isinstance(parts[0], bool):
        if not parts[0]:
            return None
        parts = parts[1:]
    if len(parts) == 1 and hasattr(parts[0], "get_x"):
        r = parts[0]
        return float(r.get_x()), float(r.get_y()), float(r.get_width()), float(r.get_height())
    return None


def step_position(position: int, delta: int, count: int) -> int | None:
    """Önizlemede önceki/sonraki dosyanın sırası; uçlarda döngü yapmaz (None)."""
    target = position + delta
    return target if 0 <= target < count else None
