// Language independent core of the search kernel benchmark. See kernel/SPEC.md.
#pragma once
#include <vector>
#include <cstdint>
#include <cmath>
#include <algorithm>

namespace kernel {

constexpr int COLS = 32, ROWS = 32, REACH = 4, SEARCH_GROUPS = 7;
constexpr double W_CLOSE = 1.0, W_FOCUS = 6.0, W_BEHIND = 3.0, W_CROWD = 1.5, W_MUTUAL = 4.0, DIAG = 1.45;

struct World {
    uint32_t state = 12345;
    int n = 0;
    std::vector<uint8_t> team, flags;
    std::vector<int64_t> groups;
    std::vector<int32_t> ccol, crow, target, crowd, centerNext;
    std::vector<int32_t> centerHead;
    std::vector<int64_t> chunkGroups, colGroups, mapGroups;

    double rand01() {
        state ^= state << 13; state ^= state >> 17; state ^= state << 5;
        return double(state >> 8) / 16777216.0;
    }

    void build(int count) {
        n = count; state = 12345;
        team.assign(n, 0); flags.assign(n, 0); groups.assign(n, 0);
        ccol.assign(n, 0); crow.assign(n, 0); target.assign(n, -1);
        crowd.assign(n, 0); centerNext.assign(n, -1);
        centerHead.assign(COLS * ROWS, -1);
        chunkGroups.assign(2 * COLS * ROWS, 0);
        colGroups.assign(2 * COLS, 0);
        mapGroups.assign(2, 0);
        for (int i = 0; i < n; ++i) {
            int t = i % 2;
            double front = 4096.0 * (t == 0 ? 0.35 : 0.65);
            double x = std::clamp(front + (rand01() - 0.5) * 2.0 * 655.36, 0.0, 4095.0);
            double y = std::clamp(rand01() * 4096.0, 0.0, 4095.0);
            int64_t g = int64_t(1) << (i % 3);
            team[i] = uint8_t(t); groups[i] = g; flags[i] = 0;
            int c = std::clamp(int(std::floor(x / 128.0)), 0, COLS - 1);
            int r = std::clamp(int(std::floor(y / 128.0)), 0, ROWS - 1);
            ccol[i] = c; crow[i] = r;
            int cid = r * COLS + c;
            centerNext[i] = centerHead[cid]; centerHead[cid] = i;
            chunkGroups[t * COLS * ROWS + cid] |= g;
            colGroups[t * COLS + c] |= g;
            mapGroups[t] |= g;
        }
    }

    inline bool mapHas(int t) const {
        for (int o = 0; o < 2; ++o) if (o != t && (mapGroups[o] & SEARCH_GROUPS)) return true;
        return false;
    }
    inline bool colHas(int t, int c) const {
        for (int o = 0; o < 2; ++o) if (o != t && (colGroups[o * COLS + c] & SEARCH_GROUPS)) return true;
        return false;
    }
    inline bool chunkHas(int t, int cid) const {
        for (int o = 0; o < 2; ++o) if (o != t && (chunkGroups[o * COLS * ROWS + cid] & SEARCH_GROUPS)) return true;
        return false;
    }

    int64_t run() {
        for (int s = 0; s < n; ++s) {
            int t = team[s];
            if (!mapHas(t)) { target[s] = -1; continue; }
            int col = ccol[s], row = crow[s], sf = flags[s];
            int fwd = (t == 0) ? 1 : -1;
            int bestId = -1; double bestScore = 0.0;
            const double maxBonus = W_BEHIND + W_MUTUAL + W_FOCUS;
            for (int ring = 0; ring <= REACH; ++ring) {
                double bound = (REACH - ring) * W_CLOSE + maxBonus;
                if (bestId != -1 && bestScore >= bound) break;
                int L = col - ring, R = col + ring, T = row - ring, B = row + ring;
                for (int c = std::max(L, 0); c <= std::min(R, COLS - 1); ++c) {
                    if (!colHas(t, c)) continue;
                    bool edge = (c == L || c == R);
                    int r0 = edge ? std::max(T, 0) : T;
                    int r1 = edge ? std::min(B, ROWS - 1) : B;
                    int step = edge ? 1 : std::max(B - T, 1);
                    for (int r = r0; r <= r1; r += step) {
                        if (r < 0 || r >= ROWS) continue;
                        int cid = r * COLS + c;
                        if (!chunkHas(t, cid)) continue;
                        for (int k = centerHead[cid]; k != -1; k = centerNext[k]) {
                            if (team[k] == t) continue;
                            if ((groups[k] & SEARCH_GROUPS) == 0) continue;
                            if ((flags[k] & 1) != 0 && (sf & 2) == 0) continue;
                            int dc = std::abs(ccol[k] - col), dr = std::abs(crow[k] - row);
                            int d = std::min(dc, dr);
                            double dist = double(std::max(dc, dr) - d) + double(d) * DIAG;
                            double sc = (double(REACH) - dist) * W_CLOSE;
                            if ((flags[k] & 4) != 0 && (sf & 8) == 0) sc += W_FOCUS;
                            if ((ccol[k] - col) * fwd < 0) sc += W_BEHIND;
                            if (target[k] == s) sc += W_MUTUAL;
                            sc -= double(crowd[k]) * W_CROWD;
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
        int64_t sum = 0;
        for (int s = 0; s < n; ++s) sum += int64_t(target[s]) + 1;
        return sum;
    }
};

} // namespace kernel
