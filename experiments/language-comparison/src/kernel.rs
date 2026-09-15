// Rust port of the search kernel benchmark. See kernel/SPEC.md.
const COLS: i32 = 32; const ROWS: i32 = 32; const REACH: i32 = 4; const SEARCH_GROUPS: i64 = 7;
const W_CLOSE: f64 = 1.0; const W_FOCUS: f64 = 6.0; const W_BEHIND: f64 = 3.0;
const W_CROWD: f64 = 1.5; const W_MUTUAL: f64 = 4.0; const DIAG: f64 = 1.45;

pub struct World {
    state: u32, n: i32,
    team: Vec<u8>, flags: Vec<u8>, groups: Vec<i64>,
    ccol: Vec<i32>, crow: Vec<i32>, target: Vec<i32>, crowd: Vec<i32>, center_next: Vec<i32>,
    center_head: Vec<i32>, chunk_groups: Vec<i64>, col_groups: Vec<i64>, map_groups: Vec<i64>,
}

impl World {
    pub fn new() -> Self { World { state: 12345, n: 0,
        team: vec![], flags: vec![], groups: vec![], ccol: vec![], crow: vec![],
        target: vec![], crowd: vec![], center_next: vec![], center_head: vec![],
        chunk_groups: vec![], col_groups: vec![], map_groups: vec![] } }

    #[inline] fn rand01(&mut self) -> f64 {
        self.state ^= self.state << 13; self.state ^= self.state >> 17; self.state ^= self.state << 5;
        (self.state >> 8) as f64 / 16777216.0
    }

    pub fn build(&mut self, count: i32) {
        self.n = count; self.state = 12345;
        let n = count as usize;
        self.team = vec![0; n]; self.flags = vec![0; n]; self.groups = vec![0; n];
        self.ccol = vec![0; n]; self.crow = vec![0; n]; self.target = vec![-1; n];
        self.crowd = vec![0; n]; self.center_next = vec![-1; n];
        self.center_head = vec![-1; (COLS*ROWS) as usize];
        self.chunk_groups = vec![0; (2*COLS*ROWS) as usize];
        self.col_groups = vec![0; (2*COLS) as usize];
        self.map_groups = vec![0; 2];
        for i in 0..count {
            let t = i % 2;
            let front = 4096.0 * if t == 0 { 0.35 } else { 0.65 };
            let x = (front + (self.rand01() - 0.5) * 2.0 * 655.36).clamp(0.0, 4095.0);
            let y = (self.rand01() * 4096.0).clamp(0.0, 4095.0);
            let g: i64 = 1i64 << (i % 3);
            let iu = i as usize;
            self.team[iu] = t as u8; self.groups[iu] = g; self.flags[iu] = 0;
            let c = ((x / 128.0).floor() as i32).clamp(0, COLS-1);
            let r = ((y / 128.0).floor() as i32).clamp(0, ROWS-1);
            self.ccol[iu] = c; self.crow[iu] = r;
            let cid = r * COLS + c;
            self.center_next[iu] = self.center_head[cid as usize];
            self.center_head[cid as usize] = i;
            self.chunk_groups[(t*COLS*ROWS + cid) as usize] |= g;
            self.col_groups[(t*COLS + c) as usize] |= g;
            self.map_groups[t as usize] |= g;
        }
    }

    #[inline] fn map_has(&self, t: i32) -> bool {
        (0..2).any(|o| o != t && (self.map_groups[o as usize] & SEARCH_GROUPS) != 0) }
    #[inline] fn col_has(&self, t: i32, c: i32) -> bool {
        (0..2).any(|o| o != t && (self.col_groups[(o*COLS + c) as usize] & SEARCH_GROUPS) != 0) }
    #[inline] fn chunk_has(&self, t: i32, cid: i32) -> bool {
        (0..2).any(|o| o != t && (self.chunk_groups[(o*COLS*ROWS + cid) as usize] & SEARCH_GROUPS) != 0) }

    pub fn run(&mut self) -> i64 {
        for s in 0..self.n {
            let su = s as usize;
            let t = self.team[su] as i32;
            if !self.map_has(t) { self.target[su] = -1; continue; }
            let col = self.ccol[su]; let row = self.crow[su]; let sf = self.flags[su] as i32;
            let fwd = if t == 0 { 1 } else { -1 };
            let mut best_id: i32 = -1; let mut best_score: f64 = 0.0;
            let max_bonus = W_BEHIND + W_MUTUAL + W_FOCUS;
            for ring in 0..=REACH {
                let bound = (REACH - ring) as f64 * W_CLOSE + max_bonus;
                if best_id != -1 && best_score >= bound { break; }
                let (l, rr, tt, bb) = (col-ring, col+ring, row-ring, row+ring);
                let mut c = l.max(0);
                while c <= rr.min(COLS-1) {
                    if !self.col_has(t, c) { c += 1; continue; }
                    let edge = c == l || c == rr;
                    let r0 = if edge { tt.max(0) } else { tt };
                    let r1 = if edge { bb.min(ROWS-1) } else { bb };
                    let step = if edge { 1 } else { (bb - tt).max(1) };
                    let mut r = r0;
                    while r <= r1 {
                        if r < 0 || r >= ROWS { r += step; continue; }
                        let cid = r * COLS + c;
                        if !self.chunk_has(t, cid) { r += step; continue; }
                        let mut k = self.center_head[cid as usize];
                        while k != -1 {
                            let ku = k as usize;
                            if self.team[ku] as i32 == t { k = self.center_next[ku]; continue; }
                            if (self.groups[ku] & SEARCH_GROUPS) == 0 { k = self.center_next[ku]; continue; }
                            if (self.flags[ku] & 1) != 0 && (sf & 2) == 0 { k = self.center_next[ku]; continue; }
                            let dc = (self.ccol[ku] - col).abs(); let dr = (self.crow[ku] - row).abs();
                            let d = dc.min(dr);
                            let dist = (dc.max(dr) - d) as f64 + d as f64 * DIAG;
                            let mut sc = (REACH as f64 - dist) * W_CLOSE;
                            if (self.flags[ku] & 4) != 0 && (sf & 8) == 0 { sc += W_FOCUS; }
                            if (self.ccol[ku] - col) * fwd < 0 { sc += W_BEHIND; }
                            if self.target[ku] == s { sc += W_MUTUAL; }
                            sc -= self.crowd[ku] as f64 * W_CROWD;
                            if best_id == -1 || sc > best_score || (sc == best_score && k < best_id) {
                                best_score = sc; best_id = k;
                            }
                            k = self.center_next[ku];
                        }
                        r += step;
                    }
                    c += 1;
                }
            }
            if self.target[su] != -1 { let o = self.target[su] as usize; self.crowd[o] -= 1; }
            self.target[su] = best_id;
            if best_id != -1 { self.crowd[best_id as usize] += 1; }
        }
        (0..self.n).map(|s| self.target[s as usize] as i64 + 1).sum()
    }
}

fn main() {
    use std::time::Instant;
    for n in [500, 1000, 3000, 5000] {
        let t0 = Instant::now();
        let mut sum = 0i64; let mut reps = 0;
        while t0.elapsed().as_secs_f64() < 0.2 {
            let mut w = World::new(); w.build(n); sum = w.run(); reps += 1;
        }
        let total = t0.elapsed().as_secs_f64();
        println!("n={:5}  checksum={}  reps={}  us/search={:.3}",
                 n, sum, reps, total / reps as f64 / n as f64 * 1e6);
    }
}
