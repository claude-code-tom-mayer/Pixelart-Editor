# Search kernel benchmark spec

Every implementation builds the SAME world from a seed and runs the SAME search,
then returns a checksum. Identical checksums prove the ports agree.

## Constants
COLS=32 ROWS=32 CHUNK=128.0 TEAMS=2 REACH=4 SEARCH_GROUPS=0b111
W_CLOSE=1.0 W_FOCUS=6.0 W_BEHIND=3.0 W_CROWD=1.5 W_MUTUAL=4.0 DIAG=1.45
FORWARD = [+1, -1]

## RNG - xorshift32, seed 12345
state ^= state<<13; state ^= state>>17; state ^= state<<5   (all on uint32)
rand01() = (state >>> 8) / 16777216.0        // top 24 bits

## World build, entity i in 0..N-1
team   = i % 2
front  = 4096.0 * (team==0 ? 0.35 : 0.65)
x      = clamp(front + (rand01()-0.5) * 2.0 * 655.36, 0, 4095)
y      = clamp(rand01() * 4096.0, 0, 4095)
groups = 1 << (i % 3)
flags  = 0
target[i] = -1 ; targeterCount[i] = 0
col = clamp(floor(x/128), 0, 31) ; row = clamp(floor(y/128), 0, 31)
chunk = row*32 + col
// push onto the SHARED centre chain of that chunk (head insert)
centerNext[i] = centerHead[chunk] ; centerHead[chunk] = i
chunkGroups[team*1024 + chunk] |= groups
colGroups  [team*32   + col]   |= groups
mapGroups  [team]              |= groups

## Search, for each entity s in 0..N-1 in order
if no opposing team has (mapGroups & SEARCH_GROUPS): target[s] = -1 ; continue
bestId = -1 ; bestScore = 0
maxBonus = W_BEHIND + W_MUTUAL + W_FOCUS
for ring in 0..REACH:
    bound = (REACH-ring)*W_CLOSE + maxBonus
    if bestId != -1 and bestScore >= bound: break
    L=col-ring R=col+ring T=row-ring B=row+ring
    for c in max(L,0)..min(R,31):
        if no opposing team has (colGroups[t*32+c] & SEARCH_GROUPS): continue
        rows = (c==L || c==R) ? [max(T,0)..min(B,31)] : [T,B] where 0<=r<32
        for r in rows:
            cid = r*32+c
            if no opposing team has (chunkGroups[t*1024+cid] & SEARCH_GROUPS): continue
            for k = centerHead[cid]; k != -1; k = centerNext[k]:
                if team[k] == team[s]: continue
                if (groups[k] & SEARCH_GROUPS) == 0: continue
                if (flags[k] & 1) != 0 and (flags[s] & 2) == 0: continue
                dc = abs(ccol[k]-col) ; dr = abs(crow[k]-row)
                d  = min(dc,dr) ; straight = max(dc,dr)-d
                dist = straight + d*DIAG
                score = (REACH - dist) * W_CLOSE
                if (flags[k] & 4) != 0 and (flags[s] & 8) == 0: score += W_FOCUS
                if (ccol[k]-col) * FORWARD[team[s]] < 0: score += W_BEHIND
                if target[k] == s: score += W_MUTUAL
                score -= targeterCount[k] * W_CROWD
                if bestId == -1 or score > bestScore or (score == bestScore and k < bestId):
                    bestScore = score ; bestId = k
// assign, maintaining crowding for later searchers
if target[s] != -1: targeterCount[target[s]] -= 1
target[s] = bestId
if bestId != -1: targeterCount[bestId] += 1

## Result
checksum = sum over s of (target[s] + 1)     // int64
