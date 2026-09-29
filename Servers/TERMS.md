# Server Terms

Every term the servers in this folder use, and what it means. Names in code follow these terms exactly.

## Architecture

| Term | Meaning |
|---|---|
| **Server** | One of the `G_` autoloads (`G_ChunkingServer`, `G_HitServer`, `G_TargetingServer`). Each one only reads and writes the shared data; no server ever calls another one. |
| **Core server** | `A_CoreServer`, the abstract base every server extends. It owns all shared entity data as `static var`s, plus the entity lifecycle. It holds no queries. |
| **Lifecycle** | `A_CoreServer.register()`, `pre_unregister()`, `unregister()` and `release_removed_ids()`. Always called on `A_CoreServer` itself, never through a server. |
| **Shared data** | The `static var`s on `A_CoreServer`. All servers see the same arrays, because static data exists once per class, not per instance. |
| **Scratch data** | Temporary per-query state (search bests, hit buffers, visit stamps). It lives as instance vars on the one server that uses it, never on `A_CoreServer`. |
| **`NO_ID`** | `-1`. Stored wherever an entity id, slot, chunk, target or curve id points nowhere. |

## Naming scheme of the shared data

The prefix of a shared array names **what it is indexed by**:

| Prefix | Indexed by | Example |
|---|---|---|
| `_entity…` / `_isEntity…` | entity id | `_entityPosition[id]` |
| `_slot…` | membership slot | `_slotChunk[slot]` |
| `_chunk…` | chunk id | `_chunkFirstSlot[chunk]` |
| `_teamChunk…` | `team * CHUNK_COUNT + chunk` | `_teamChunkGroups` |
| `_teamColumn…` | `team * CHUNK_COLUMNS + column` | `_teamColumnMembershipCount` |
| `_team…` / `_teamMap…` | team | `_teamMapGroups[team]` |
| `_curve…` | curve id | `_curveUserCount[curveId]` |

Linked chains always use the same words: `First…` is the head of a chain, `…Next` / `…Prev` are the links.

## Entities

| Term | Meaning |
|---|---|
| **Entity** | Anything registered on the servers: units, buildings, obstacles. |
| **Entity id** | The index an entity is stored under in every shared array. Handed out by `register()`, reused after release. |
| **Team** | `C_CoreServer.TEAM`. Entities of one team never hit or target each other. |
| **Opponent** | An entity of any other team. |
| **Entity groups** | Bitmask of what an entity *is* (e.g. ground unit, building). Targeting searches for these. |
| **Radius** | The size of an entity. Decides which chunks it stands in and how big it is to hits. |
| **Pending removal** | After `pre_unregister()`: the entity still acts, but can no longer be targeted or hit. |
| **Removed** | After `unregister()`: the entity is gone from the chunk index and every chain, but its id stays locked. |
| **Released** | After `release_removed_ids()`: the id is free and the next `register()` may reuse it. |
| **Inert** | An entity registered without hit profile and targeting data: no hit or targeted groups, never flees. It still stands on the index and can be targeted. |

## Chunk index

| Term | Meaning |
|---|---|
| **Chunk** | One square cell of the map grid, `CHUNK_SIZE` wide. Chunk id = `row * CHUNK_COLUMNS + column`. |
| **Column / row** | Grid coordinates of a chunk. A column is also the middle aggregation level, because the two bases face each other along x. |
| **Chunk area** | A rectangle of chunks as `Vector4i(minColumn, minRow, maxColumn, maxRow)`. An entity stands in every chunk of the area its radius covers. |
| **Empty chunk area** | `EMPTY_CHUNK_AREA = (0, 0, -1, -1)`: covers no chunk. Held by fresh and removed entities. |
| **Membership** | "Entity X stands in chunk Y". Stored in one **membership slot**. |
| **Slot** | Always means *membership slot*. Each slot sits in two chains at once: the chain of its chunk and the chain of its entity. |
| **Center chunk** | The one chunk an entity's position falls into. Every entity sits in exactly one **center chain**, so a chunk walk over centers sees each entity once. |
| **Membership count** | How many memberships a team has in a chunk or column. An entity counts once per chunk it stands in, so a column counts a tall entity once per row. The hit server skips chunks and columns where it is 0. |
| **Group mask** | OR of the entity groups a team has in a chunk, column or on the whole map. Searches use it to skip empty space: map → column → chunk. |
| **Merge / rebuild** | Adding an entity *merges* its groups into the masks. Removing one *rebuilds* them, which stops early once the old value is reached. |
| **Column span** | `_teamMinColumn` to `_teamMaxColumn`: the leftmost and rightmost column a team occupies. |

## Hit system

| Term | Meaning |
|---|---|
| **Hit** | One area attack: circle, directional rect or sector (cake slice). |
| **Emitter** | The entity a hit comes from. |
| **Hit groups / hurt groups** | A hit connects only if the emitter's *hit groups* overlap the target's *hurt groups*. Separate bit space from the entity groups. |
| **Stop groups** | Hurt groups that end an *ordered* hit at the first target carrying them (e.g. a shield). |
| **Height band** | Vertical extent `(bottom, top)` above the ground, of an entity or of a hit. Both have to overlap. Ground position is the 2D x/y. |
| **Sample height** | The height a hit is measured at on a target: the middle of the hit's band, clamped into the target's band. |
| **Radius curve** | Optional `Curve` giving the radius over the height. Its domain spans the height band, its `max_value` is the full radius. |
| **Curve id** | Index of one stored radius curve. Entities sharing a curve share its id. |
| **Radius factor** | A baked curve sample divided by the curve's `max_value`, clamped to 0–1. Radius at a height = radius × factor. |
| **Effective radius** | The radius a target offers at the sample height. |
| **Preferred target** | Checked first when a hit may land exactly once. Only if it misses are the chunks searched. |
| **Candidate** | An entity near the shape that passed team, removal, group and height checks. |
| **Accepted target** | A candidate whose silhouette reaches into the shape. |
| **Sort key** | Per accepted target. Lower lands first in an ordered hit. |
| **Ordered hit** | A hit whose targets land in shape order (`RECT_ORDER`, `SECTOR_ORDER`, or center-outwards for circles). Only ordered hits apply stop groups. |
| **Dispatch** | Handing the landed hits to the targets' **module managers**. Happens from a snapshot, so a module manager may fire hits or remove entities meanwhile. |
| **Impact** | Where a hit lands on a target's silhouette, as `(x, y, height)`. |
| **Visit stamp** | Per-gather counter that makes "already collected?" one integer compare. |

## Targeting system

| Term | Meaning |
|---|---|
| **State** | `C_TargetingServer.STATE`: `SEARCH`, `APPROACH`, `COMBAT` or `FLEE`. |
| **Target** | The entity an entity currently goes after, or `NO_ID`. |
| **Targeter** | An entity that targets a given entity. All targeters of one target form its **targeter chain**. The **targeter count** is the crowding count. |
| **Searcher** | The entity running a search. |
| **Targeted groups** | Entity groups an entity may go after. **Priority targeted groups** are preferred over normal ones. |
| **Search radius (chunks)** | How many chunk **rings** around the searcher's center chunk a search covers. Ring 0 is the center chunk itself. |
| **Chunk distance** | Steps between two center chunks; a diagonal step costs `DIAGONAL_CHUNK_COST`. |
| **Flee radius (chunks)** | A targeter within this chunk distance makes the entity flee. `NEVER_FLEE` turns fleeing off. |
| **Combat range** | Real distance to the target's silhouette at which approaching turns into combat. |
| **Base x / march x** | The x a team retreats to / marches towards when it has no target. |
| **Forward sign** | `+1` or `-1`: the direction a team marches along x. Decides what counts as **behind**. |
| **Focus** | A focus target scores a bonus for searchers, unless the searcher is **ignoring focus**. |
| **Invisible** | Hidden from searchers that cannot target invisible entities. Turning invisible drops those targeters. |
| **Score** | Closeness + focus + behind + mutual − crowding, weighted by the `WEIGHT_` constants. |
| **Settled** | A search stops early once no further ring could beat the best score found. |
| **Move destination** | Where an entity should head this tick: the target, its base, or the march x. |
