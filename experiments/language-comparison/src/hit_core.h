// Hit resolution half of the benchmark: entities occupy every chunk their radius
// touches, and every entity fires one hit per frame from a fixed mix.
#pragma once
#include <vector>
#include <cstdint>
#include <cmath>
#include <algorithm>

namespace hitkernel {

constexpr int COLS = 32, ROWS = 32;
constexpr double CHUNK = 128.0;
constexpr double RADII[4] = {12.0, 24.0, 40.0, 90.0};
// fixed mix, by entity index % 10, so the proportions hold at every entity count
constexpr double SINGLE_R = 64.0, CAPPED_R = 128.0, BLAST_R = 192.0;
constexpr int CAPPED_MAX = 5;

struct World {
    uint32_t state = 12345;
    int n = 0;
    std::vector<uint8_t> team;
    std::vector<double> px, py, radius;
    std::vector<int32_t> chunkHead, slotEntity, slotNext;   // touched chunk chains
    std::vector<int32_t> stamp;
    int32_t curStamp = 0;
    // scratch, reused exactly like the shipped server does
    std::vector<int32_t> cand; std::vector<double> key; std::vector<int32_t> order;

    double rand01() {
        state ^= state << 13; state ^= state >> 17; state ^= state << 5;
        return double(state >> 8) / 16777216.0;
    }

    void build(int count) {
        n = count; state = 12345;
        team.assign(n, 0); px.assign(n, 0); py.assign(n, 0); radius.assign(n, 0);
        stamp.assign(n, 0); curStamp = 0;
        chunkHead.assign(COLS * ROWS, -1);
        slotEntity.clear(); slotNext.clear();
        for (int i = 0; i < n; ++i) {
            int t = i % 2;
            double front = 4096.0 * (t == 0 ? 0.35 : 0.65);
            double x = std::clamp(front + (rand01() - 0.5) * 2.0 * 655.36, 0.0, 4095.0);
            double y = std::clamp(rand01() * 4096.0, 0.0, 4095.0);
            team[i] = uint8_t(t); px[i] = x; py[i] = y; radius[i] = RADII[i % 4];
            double r = radius[i];
            int c0 = std::clamp(int(std::floor((x - r) / CHUNK)), 0, COLS - 1);
            int c1 = std::clamp(int(std::floor((x + r) / CHUNK)), 0, COLS - 1);
            int r0 = std::clamp(int(std::floor((y - r) / CHUNK)), 0, ROWS - 1);
            int r1 = std::clamp(int(std::floor((y + r) / CHUNK)), 0, ROWS - 1);
            for (int rr = r0; rr <= r1; ++rr)
                for (int cc = c0; cc <= c1; ++cc) {
                    int cid = rr * COLS + cc;
                    slotEntity.push_back(i);
                    slotNext.push_back(chunkHead[cid]);
                    chunkHead[cid] = int32_t(slotEntity.size()) - 1;
                }
        }
    }

    // returns landed*1000003 + sum of hit entity ids
    int64_t run_hits() {
        int64_t landed = 0, idSum = 0;
        for (int e = 0; e < n; ++e) {
            int kind = e % 10;
            double R; int maxHits; bool ordered;
            if (kind < 6)      { R = SINGLE_R; maxHits = 1;          ordered = true;  }
            else if (kind < 9) { R = CAPPED_R; maxHits = CAPPED_MAX; ordered = true;  }
            else               { R = BLAST_R;  maxHits = -1;         ordered = false; }
            double ox = px[e], oy = py[e];
            int t = team[e];
            cand.clear(); key.clear();
            ++curStamp;
            int c0 = std::clamp(int(std::floor((ox - R) / CHUNK)), 0, COLS - 1);
            int c1 = std::clamp(int(std::floor((ox + R) / CHUNK)), 0, COLS - 1);
            int r0 = std::clamp(int(std::floor((oy - R) / CHUNK)), 0, ROWS - 1);
            int r1 = std::clamp(int(std::floor((oy + R) / CHUNK)), 0, ROWS - 1);
            for (int cc = c0; cc <= c1; ++cc)
                for (int rr = r0; rr <= r1; ++rr) {
                    int cid = rr * COLS + cc;
                    for (int sl = chunkHead[cid]; sl != -1; sl = slotNext[sl]) {
                        int k = slotEntity[sl];
                        if (stamp[k] == curStamp) continue;
                        stamp[k] = curStamp;
                        if (team[k] == t) continue;
                        double dx = px[k] - ox, dy = py[k] - oy;
                        double reach = R + radius[k];
                        double d2 = dx * dx + dy * dy;
                        if (d2 > reach * reach) continue;
                        cand.push_back(k); key.push_back(d2);
                    }
                }
            int m = int(cand.size());
            if (m == 0) continue;
            int limit = (maxHits < 0) ? m : std::min(maxHits, m);
            if (ordered && limit < m) {
                order.resize(m);
                for (int i = 0; i < m; ++i) order[i] = i;
                // insertion sort, ties resolved by index, same as GDScript side
                for (int i = 1; i < m; ++i) {
                    int v = order[i]; int j = i;
                    while (j > 0 && key[order[j-1]] > key[v]) { order[j] = order[j-1]; --j; }
                    order[j] = v;
                }
                for (int i = 0; i < limit; ++i) { ++landed; idSum += cand[order[i]]; }
            } else {
                for (int i = 0; i < limit; ++i) { ++landed; idSum += cand[i]; }
            }
        }
        return landed * 1000003 + idSum;
    }
};

} // namespace hitkernel
