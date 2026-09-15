// C# port of the search kernel benchmark. See kernel/SPEC.md.
using System;

public class World {
    const int COLS = 32, ROWS = 32, REACH = 4; const long SEARCH_GROUPS = 7;
    const double W_CLOSE = 1.0, W_FOCUS = 6.0, W_BEHIND = 3.0, W_CROWD = 1.5, W_MUTUAL = 4.0, DIAG = 1.45;

    uint state = 12345; int n;
    byte[] team, flags; long[] groups;
    int[] ccol, crow, target, crowd, centerNext, centerHead;
    long[] chunkGroups, colGroups, mapGroups;

    double Rand01() {
        state ^= state << 13; state ^= state >> 17; state ^= state << 5;
        return (state >> 8) / 16777216.0;
    }

    public void Build(int count) {
        n = count; state = 12345;
        team = new byte[n]; flags = new byte[n]; groups = new long[n];
        ccol = new int[n]; crow = new int[n]; target = new int[n];
        crowd = new int[n]; centerNext = new int[n];
        for (int i = 0; i < n; i++) { target[i] = -1; centerNext[i] = -1; }
        centerHead = new int[COLS * ROWS];
        for (int i = 0; i < centerHead.Length; i++) centerHead[i] = -1;
        chunkGroups = new long[2 * COLS * ROWS];
        colGroups = new long[2 * COLS];
        mapGroups = new long[2];
        for (int i = 0; i < n; i++) {
            int t = i % 2;
            double front = 4096.0 * (t == 0 ? 0.35 : 0.65);
            double x = Math.Clamp(front + (Rand01() - 0.5) * 2.0 * 655.36, 0.0, 4095.0);
            double y = Math.Clamp(Rand01() * 4096.0, 0.0, 4095.0);
            long g = 1L << (i % 3);
            team[i] = (byte)t; groups[i] = g; flags[i] = 0;
            int c = Math.Clamp((int)Math.Floor(x / 128.0), 0, COLS - 1);
            int r = Math.Clamp((int)Math.Floor(y / 128.0), 0, ROWS - 1);
            ccol[i] = c; crow[i] = r;
            int cid = r * COLS + c;
            centerNext[i] = centerHead[cid]; centerHead[cid] = i;
            chunkGroups[t * COLS * ROWS + cid] |= g;
            colGroups[t * COLS + c] |= g;
            mapGroups[t] |= g;
        }
    }

    bool MapHas(int t) { for (int o = 0; o < 2; o++) if (o != t && (mapGroups[o] & SEARCH_GROUPS) != 0) return true; return false; }
    bool ColHas(int t, int c) { for (int o = 0; o < 2; o++) if (o != t && (colGroups[o * COLS + c] & SEARCH_GROUPS) != 0) return true; return false; }
    bool ChunkHas(int t, int cid) { for (int o = 0; o < 2; o++) if (o != t && (chunkGroups[o * COLS * ROWS + cid] & SEARCH_GROUPS) != 0) return true; return false; }

    public long Run() {
        for (int s = 0; s < n; s++) {
            int t = team[s];
            if (!MapHas(t)) { target[s] = -1; continue; }
            int col = ccol[s], row = crow[s], sf = flags[s];
            int fwd = (t == 0) ? 1 : -1;
            int bestId = -1; double bestScore = 0.0;
            double maxBonus = W_BEHIND + W_MUTUAL + W_FOCUS;
            for (int ring = 0; ring <= REACH; ring++) {
                double bound = (REACH - ring) * W_CLOSE + maxBonus;
                if (bestId != -1 && bestScore >= bound) break;
                int L = col - ring, R = col + ring, T = row - ring, B = row + ring;
                for (int c = Math.Max(L, 0); c <= Math.Min(R, COLS - 1); c++) {
                    if (!ColHas(t, c)) continue;
                    bool edge = (c == L || c == R);
                    int r0 = edge ? Math.Max(T, 0) : T;
                    int r1 = edge ? Math.Min(B, ROWS - 1) : B;
                    int step = edge ? 1 : Math.Max(B - T, 1);
                    for (int r = r0; r <= r1; r += step) {
                        if (r < 0 || r >= ROWS) continue;
                        int cid = r * COLS + c;
                        if (!ChunkHas(t, cid)) continue;
                        for (int k = centerHead[cid]; k != -1; k = centerNext[k]) {
                            if (team[k] == t) continue;
                            if ((groups[k] & SEARCH_GROUPS) == 0) continue;
                            if ((flags[k] & 1) != 0 && (sf & 2) == 0) continue;
                            int dc = Math.Abs(ccol[k] - col), dr = Math.Abs(crow[k] - row);
                            int d = Math.Min(dc, dr);
                            double dist = (Math.Max(dc, dr) - d) + d * DIAG;
                            double sc = (REACH - dist) * W_CLOSE;
                            if ((flags[k] & 4) != 0 && (sf & 8) == 0) sc += W_FOCUS;
                            if ((ccol[k] - col) * fwd < 0) sc += W_BEHIND;
                            if (target[k] == s) sc += W_MUTUAL;
                            sc -= crowd[k] * W_CROWD;
                            if (bestId == -1 || sc > bestScore || (sc == bestScore && k < bestId)) {
                                bestScore = sc; bestId = k;
                            }
                        }
                    }
                }
            }
            if (target[s] != -1) crowd[target[s]] -= 1;
            target[s] = bestId;
            if (bestId != -1) crowd[bestId] += 1;
        }
        long sum = 0;
        for (int s = 0; s < n; s++) sum += (long)target[s] + 1;
        return sum;
    }
}
