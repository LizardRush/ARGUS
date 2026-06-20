# ARGUS
### Advanced Reasoning & Geographic Understanding System

> *Google Maps × Baritone — for Roblox.*

ARGUS is the most advanced client-side navigation and pathfinding system for Roblox. It ignores `PathfindingService` entirely, builds its own navigation graph from live world geometry, finds routes with a custom A\* engine, and then physically drives your character using a technique-based movement system — all from a single executor script.

---

## Features

### Pathfinding
| Feature | Details |
|---|---|
| **Custom A\*** | Pure-Lua A\* with a binary min-heap. No PathfindingService dependency. |
| **Navigation graph** | Built by raycasting against actual world geometry, not navmesh approximations. |
| **3 route biases** | `balanced`, `distance-first`, `risk-avoidance` — scored and the best picked automatically. |
| **Path smoothing** | String-pulling (greedy line-of-sight) removes redundant waypoints; optional Catmull-Rom spline for humanization. |
| **Realtime repair** | Blocked edge → local re-expansion from current position, not a full cold replan. |
| **Partial paths** | When no full route exists, ARGUS returns the furthest partial path found. |
| **Long-distance routing** | Multi-layer 3D heuristic handles vertical navigation naturally. |

### World Analysis
ARGUS raycasts a configurable sphere around the character every scan interval and tags each node:

`floor` · `wall` · `gap` · `slope` · `ladder` · `truss` · `water` · `moving platform` · `conveyor` · `elevator` · `rotating platform` · `door` · `hazard` · `narrow passage`

### Observation System
- Records position/velocity history for every moving object (circular buffer, 120 samples).
- Fits **linear**, **oscillating**, and **circular** motion models via least-squares.
- Predicts future platform positions up to 3 seconds ahead.
- Calculates the optimal jump timing window for moving platforms.

### Movement Technique Database
Every movement type is a self-contained module that implements:

```
CanUse(ctx)             → bool
Execute(ctx)            → bool   (success/fail)
EstimateCost(ctx)       → number
EstimateSuccessRate(ctx) → number (0–1)
DebugInfo(ctx)          → string
```

Built-in techniques:

| Technique | Description |
|---|---|
| `Walk` | Standard ground movement |
| `Jump` | Upward jumps within MaxJumpHeight |
| `SafeFall` | Controlled drops up to MaxFallDistance |
| `GapCross` | Full-speed momentum jumps over gaps |
| `ClimbLadder` | Tagged ladder parts |
| `ClimbTruss` | Roblox TrussPart auto-climb |
| `Swim` | Water terrain navigation |
| `StairClimb` | Small-step jump-assist up stairs |
| `CornerCut` | Diagonal short-cuts on sharp turns |
| `JumpChain` | Bunny-hop chains of consecutive Jump edges |
| `RideElevator` | Board, ride, and exit vertical elevators |
| `RideConveyor` | Ride BodyVelocity conveyor belts |
| `RidePlatform` | Jump onto predicted moving platforms, ride, jump off |

New techniques can be added by registering any table with the five methods above.

### Humanization (anti-detection layer)
- Smooth camera follow with configurable lag factor.
- Random head turns via TweenService (probability-gated per frame).
- Random idle observation pauses (pause → look around → resume).
- ±10% walk-speed variation per segment.
- Sub-100ms anti-robot jitter delays before each movement segment.

### Visualization (toggleable per layer)
| Color | Edge type |
|---|---|
| 🟢 Green | Walk |
| 🟡 Yellow | Jump |
| 🔵 Blue | Climb |
| 🟠 Orange | Advanced / Gap |
| 🟣 Purple | Moving Platform / Elevator |
| 🩷 Pink | Conveyor |
| 🔴 Red | Hazard |
| ⚪ White | Destination |

- **3D Beams** between nodes with `BillboardGui` distance labels.
- **SelectionBox** highlights on current target and destination nodes.
- **2D minimap** (200×200 px overhead panel) updates at 4 Hz.

### Rayfield UI (6 tabs)
| Tab | Contents |
|---|---|
| **Navigation** | Go To Position, Go To Part, Follow Player, Stop, Pause, Recalculate, Export Route |
| **Visualization** | Per-layer toggles, minimap toggle + scale slider |
| **Movement** | Speed multiplier, per-technique enable/disable, humanization controls |
| **Observation** | Live list of tracked moving objects with model type and confidence % |
| **AI** | Route score breakdown, decision rationale, candidate route comparison |
| **Debug** | Live stats overlay: FPS, node/edge count, A\* iterations, scan time, replan count |

---

## Usage

### Executor (recommended)
1. Copy the contents of [`Main.lua`](Main.lua).
2. Paste into your executor and run.

ARGUS downloads all modules from this repository on first run (~3–5 seconds depending on connection).

Supported executors: **Synapse X**, **KRNL**, **Fluxus**, **Script-Ware**, **Delta**, **Hydrogen**, and any executor that exposes `syn.request`, `request()`, or allows `game:HttpGet`.

> **To re-run without doubling up:** ARGUS calls `getgenv().ARGUS_STOP()` on re-execution, cleanly tearing down the previous instance before starting a new one.

### Roblox Studio (LocalScript mode)
1. Place `Main.lua` as a **LocalScript** inside `StarterPlayerScripts`.
2. Recreate the folder hierarchy under it (each file becomes a **ModuleScript** with the same name, inside matching **Folder** instances).
3. Enable `HttpService` → `HttpEnabled = true` (needed for Rayfield).
4. Press **Play**.

---

## Architecture

```
Main.lua  (executor entry point / LocalScript)
│
├── Config.lua                    — all tunable constants
│
├── Core/
│   ├── ObservationSystem.lua     — motion tracking & prediction
│   ├── WorldScanner.lua          — geometry → spatial hash of nodes
│   ├── NavigationGraph.lua       — typed edge graph (Walk/Jump/Climb/…)
│   ├── AStarPathfinder.lua       — custom A* with binary min-heap
│   └── PathSmoother.lua          — string-pulling + Catmull-Rom spline
│
├── Movement/
│   ├── MovementTechDB.lua        — technique registry & dispatcher
│   ├── MovementController.lua    — state machine (Idle→Executing→Stuck)
│   └── Techniques/
│       ├── Walk.lua
│       ├── Jump.lua
│       ├── ClimbLadder.lua
│       ├── ClimbTruss.lua
│       ├── Swim.lua
│       ├── RideElevator.lua
│       ├── RideConveyor.lua
│       ├── RidePlatform.lua
│       ├── SafeFall.lua
│       ├── GapCross.lua
│       ├── StairClimb.lua
│       ├── CornerCut.lua
│       └── JumpChain.lua
│
├── AI/
│   ├── RouteScorer.lua           — weighted multi-criteria route scoring
│   └── AIDecisionSystem.lua      — candidate generation, replanning lifecycle
│
├── Humanization/
│   └── HumanizationSystem.lua    — camera follow, head turns, idle pauses
│
├── Visualization/
│   ├── VisualizationSystem.lua   — 3D beams, labels, SelectionBox (pooled)
│   └── MinimapPanel.lua          — 2D overhead minimap ScreenGui
│
├── UI/
│   └── UISystem.lua              — Rayfield window (6 tabs)
│
└── Debug/
    └── DebugPanel.lua            — live stats overlay ScreenGui
```

### Data flow
```
WorldScanner ──(nodes)──▶ NavigationGraph ──(graph)──▶ AStarPathfinder
                                                              │
                                                    PathSmoother (waypoints)
                                                              │
                                                   AIDecisionSystem
                                                   (scores 3 candidates)
                                                              │
                                                   MovementController
                                                   (dispatches to TechDB)
                                                              │
                                              MovementTechDB → Technique.Execute()
```

---

## Configuration

All constants live in [`Config.lua`](Config.lua). Key values:

| Constant | Default | Description |
|---|---|---|
| `NodeSpacing` | `4` | Studs between grid scan points |
| `ScanRadius` | `50` | World scan radius around character |
| `ScanInterval` | `0.5` | Seconds between full rescans |
| `MaxJumpHeight` | `8` | Max upward jump (studs) |
| `MaxFallDistance` | `20` | Safe fall distance (studs) |
| `MaxJumpHorizontal` | `12` | Max horizontal jump distance |
| `MaxAStarIter` | `5000` | A\* iteration cap before partial-path return |
| `ReplanCooldown` | `0.5` | Min seconds between replans |
| `MaxJitter` | `0.5` | Waypoint XZ noise for humanization |
| `UseFallbackPFS` | `false` | Enable PathfindingService as last resort |

---

## Adding a Custom Movement Technique

Create a new file in `Movement/Techniques/`:

```lua
local MyTech = {}
MyTech.__index = MyTech

function MyTech.new() return setmetatable({}, MyTech) end

function MyTech:CanUse(ctx)
    return ctx.edge.edgeType == "Walk"  -- your condition
end

function MyTech:Execute(ctx)
    ctx.humanoid:MoveTo(ctx.toNode.position)
    task.wait(1)
    return true  -- return false on failure to trigger replan
end

function MyTech:EstimateCost(ctx)     return 1.5 end
function MyTech:EstimateSuccessRate(ctx) return 0.9 end
function MyTech:DebugInfo(ctx)        return "MyTech" end

return MyTech
```

Then in `Main.lua`, register it before the existing techniques:

```lua
local MyTech = loadStep("MyTech", "Movement/Techniques/MyTech.lua")
techDB:Register("MyTech", MyTech.new())
```

The dispatcher automatically picks the highest `successRate / cost` technique that passes `CanUse`.

---

## Performance

- **Scanner**: coroutine-based, yields every 50 iterations — never blocks a frame.
- **Edge builder**: yields every 20 nodes.
- **A\***: runs on a task thread, not the heartbeat.
- **Visualization**: object-pooled Beams/BillboardGuis, diff-based updates at ≤10 Hz.
- **Observation**: model refits at 1 Hz, not per-frame.
- **RaycastParams**: created once, reused across all raycasts.

Typical FPS impact on mid-range hardware: **< 3 FPS** during scanning, **< 1 FPS** during navigation.

---

## License

MIT — do whatever you want, just don't remove the attribution.

---

*Made by [LizardRush](https://github.com/LizardRush)*
