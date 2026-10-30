"""Near-duplicate photos across datasets, so copies never straddle the split.

Algorithm
---------
1. Every photo gets two difference hashes (dHash): 64 bits from a 9x8
   greyscale thumbnail and 256 bits from a 17x16 one. A resized or
   re-encoded copy of a photo keeps almost the same hash.
2. Candidates: two hashes within 5 bits of 64 must agree exactly on at
   least one of four 16-bit bands (pigeonhole principle), so photos are
   bucketed by each band instead of comparing all n^2 pairs.
3. A candidate pair is confirmed on the 64-bit distance and then on the
   finer 256-bit one: plain white backgrounds make coarse hashes collide.
4. Confirmed pairs merge their capture groups with union-find. A size cap
   stops chains of look-alike photos from forming one giant group.
"""

from __future__ import annotations

from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor

import numpy as np
import pandas as pd
from PIL import Image, ImageOps


def dhash(path: str) -> tuple[int, np.ndarray]:
    """64-bit difference hash (for finding candidates) and a 256-bit one (for confirming)."""
    with Image.open(path) as im:
        g = ImageOps.exif_transpose(im).convert("L")
        small = np.asarray(g.resize((9, 8), Image.BILINEAR), dtype=np.int16)
        big = np.asarray(g.resize((17, 16), Image.BILINEAR), dtype=np.int16)
    bits = (small[:, 1:] > small[:, :-1]).flatten()
    return int(sum(1 << i for i, b in enumerate(bits) if b)), (big[:, 1:] > big[:, :-1]).flatten()


class UnionFind:
    """Disjoint sets of group ids with path halving and a size per set."""

    def __init__(self, sizes: dict[str, int]):
        self.parent = {g: g for g in sizes}
        self.size = dict(sizes)

    def find(self, g: str) -> str:
        while self.parent[g] != g:
            self.parent[g] = self.parent[self.parent[g]]
            g = self.parent[g]
        return g

    def union(self, a: str, b: str, max_size: int) -> bool:
        """Merges the sets of `a` and `b` unless the result would exceed `max_size`."""
        ra, rb = self.find(a), self.find(b)
        if ra == rb or self.size[ra] + self.size[rb] > max_size:
            return False
        self.parent[rb] = ra
        self.size[ra] += self.size[rb]
        return True


def _hamming(a: int, b: int) -> int:
    return bin(a ^ b).count("1")


def merge_near_duplicates(df: pd.DataFrame, max_distance: int = 5, max_fine: int = 16,
                          max_group: int = 300) -> pd.DataFrame:
    """Returns `df` (columns `src`, `group`) with near-identical photos in one group."""
    with ThreadPoolExecutor(8) as ex:
        hashes = list(ex.map(dhash, df.src))
    coarse = np.array([h for h, _ in hashes], dtype=np.uint64)
    fine = np.array([f for _, f in hashes])
    groups = df.group.to_numpy()
    sets = UnionFind(df.group.value_counts().to_dict())

    merged = 0
    for band in range(4):
        buckets = defaultdict(list)
        for i, v in enumerate((coarse >> np.uint64(16 * band)) & np.uint64(0xFFFF)):
            buckets[int(v)].append(i)
        for members in buckets.values():
            members = np.array(members)
            for pos in range(len(members) - 1):
                i, rest = members[pos], members[pos + 1:]
                near = rest[[_hamming(int(coarse[i]), int(coarse[j])) <= max_distance for j in rest]]
                if len(near):
                    near = near[(fine[near] != fine[i]).sum(1) <= max_fine]
                merged += sum(sets.union(groups[i], groups[j], max_group) for j in near)

    out = df.assign(group=[sets.find(g) for g in groups])
    print(f"near-duplicate check: merged {merged} group pairs; {out.group.nunique()} groups remain, "
          f"largest {out.group.value_counts().iloc[0]}")
    return out
