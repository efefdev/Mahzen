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


def step_position(position: int, delta: int, count: int) -> int | None:
    """Önizlemede önceki/sonraki dosyanın sırası; uçlarda döngü yapmaz (None)."""
    target = position + delta
    return target if 0 <= target < count else None
