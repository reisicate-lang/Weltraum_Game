# Ostranauts – Flying (Reference Memory)

Source: Ostranauts wiki, "Flying" page. Section numbering follows the wiki's table of contents. Game terms kept in English.
Note: parts of this wiki page reference older game versions (UI v0.14.3.8, POIs v0.14.5.14); other memory files use v1.0.0.17 data.
Wiki base: https://ostranauts.wiki.gg/wiki/
Related: ostranauts-ship-building.md (2.2 thrust rating Y = mass/thrusters), ostranauts-power.md (fusion/MHD), ostranauts-ship-ownership.md (antenna/transponder), ostranauts-character-creation.md (Piloting modifiers of traits/skills), ostranauts-ideal-atmosphere.md (Venus chemicals).

> "You know what? You're doing it. Screw this life prying metal warts off heaps of junk for your crumbs of daily bread. From now on, you call the shots. Just as soon as you can get this thing flying again..." ― Ostranauts

## Intro / General
- Flying a ship is the main way to travel between points of interest.
- **Polaris "Standard Navigation Console" Nav Station** = main ship control. Needs power and good condition.
  - Occasionally enters an **"error" mode** that blocks all use until the player spends time **debugging** it.
  - Installing **more than one** nav console doesn't help: the error is on a **timer affecting all units**.
- **Hidden "Piloting" stat** of whoever controls the ship:
  - Low piloting → random variation, e.g. **VCRS suddenly drifts** from what you set (can also be the target moving).
  - Improves with time and experience.
  - Starts low; lowered by traits, drugs, sickness, sleep deprivation, malnutrition, old age.
  - Raised by being **well-rested** and traits **Coordinated** and **Observant** (also skill Spaceship Piloting +0.5, see character creation file).
- **Anchoring / relative velocity:** all position and speed is relative (e.g. sitting still in the boneyard ≈ 14 km/s relative to Venus).
  - Undocked ships slowly drift away or get pulled in by the nearest body's gravity.
  - Best: get as close as possible to **zero relative velocity**, check with the **map fast-forward** (top left of nav UI).

---

## 1 In-Game Tutorial

### 1.1 "DON'T CRASH" note
Shown the first time you use a nav station.

Controls:
| Key | Action |
|---|---|
| R | Stop ship rotation |
| W / S | Forward / backward |
| A / D | Left / right |
| Q / E | Rotate counter-clockwise (left) / clockwise (right) |

Docking checklist:
1. Left-click target.
2. Rotate to **[BRG] = 0** (= 360).
3. Fly to target (leave room to slow down).
4. When **[RNG] < 5 km**: switch to docking screen → **COMMS → HAIL SHIP** → select target → **Request clearance**.
5. Line up rings; approach at **[VREL] < 100 m/s**.
6. When lights are green → click **CLAMPS**.
7. Bismertnaya shots for everyone!

Cheat sheet:
| Abbr. | Meaning |
|---|---|
| VREL | Relative velocity |
| VCRS | Cross velocity (sideways) |
| RNG | Range |
| BRG | Bearing (0/360 = dead ahead) |
| Delta V | Remaining fuel (in m/s) |
| RCS | Reaction control system (thrust) |
| ETA | Estimated time to arrival |

### 1.2 Step-By-Step Tutorial
Start: public sleeping area on **K-Leg (kLEG)**, a station on asteroid **1036 Ganymed**; then you're sent to the ship chosen in character creation. Goals at the Nav Console:
1. **Switch to Comms Controls** (button on right side of nav console).
2. **Open Comms:** Hail Ship → select **OKLG**.
3. **Request Undocking Clearance**, press **CLAMPS**.
4. **Switch to Nav Screen** (Nav Controls button, left side of docking console). Optional: mute the Proximity Alarm.
5. **Target K-Leg Station:** click the white diamond **OKLG**.
6. **Calibrate clockwise thrust:** E.
7. **Calibrate counter-clockwise thrust:** Q until spinning counter-clockwise.
8. **Stop spin:** hold R.
9. **Aim at OKLG:** BRG near 0.
10. **Calibrate rear thrust:** S up to **400 m/s VREL**.
11. **Calibrate forward thrust:** W to reduce VREL **below 10 m/s**.
12. **Calibrate right thrust:** D up to **400 m/s VCRS**.
13. **Calibrate left thrust:** A to reduce VCRS **below 100 m/s**.
14. **Target a derelict:** zoom out (Minus), click a **\*** in the boneyard.
15. **Travel to docking range:** RNG < 5 km, VREL and VCRS near 0.
16. **Switch to Comms Controls.**
17. **Gain clearance to dock:** Hail Ship, choose the closest "???", initiate docking.
18. **Dock with derelict:** align rings, W to approach, **CLAMPS** when **Clamp Align** light is green.

Completing the tutorial (docking with a derelict) unlocks the full starter ship pool (see character creation file, 2.4).

---

## 2 Nav Console UI

### 2.1 Navigation Screen
Control center: navigation, RCS control, system overview, warnings, transponder.
| Panel | Function |
|---|---|
| MAP CONTROLS | **Fast forward map** (simulates future object positions); **Quick zoom** (5 presets, left = closest); **No wake zones** (shows where torch drive can't be used); **Tracking mode** (what the map follows); **Ship labels**; **Focus** (switch control between map and ship) |
| WARNINGS | **ANT FAULT** – antenna missing/unpowered/damaged. **XPDR FAULT** – transponder missing/unpowered/damaged. **TRACK WARN** – another ship (pirate or security) is targeting you; dismissable; prepare to be boarded. **PROX WARN** – within 5 km of another object; dismissable or permanently mutable |
| LONG RANGE COURSE PLOT | Torch drive autopilot for distances > 5000 km (see 3.2.1) |
| MAP | Left: digital map (planets & orbits, stations, nearby ships). Right: info panel |
| TRANSPONDER/IFF | Your name & callsign, ship make & model, whether you have an active salvage license |
| DIAGNOSTICS | **Ship logs** (log report of all docking and collision events); **Print status** (ship status, incl. ship **mass**) |
| TORCH DRIVE | Manual torch drive controls (see 3.2) |
| CONTROLS | Manual ship/map controls. **Station keeping** toggle: auto-points at the selected object and brings VREL to 0 |
| FLIGHT DYNAMICS MONITOR | Effects of nearby planets: gravity pull, atmospheric friction/drag, angle of attack |
| MANEUVER DRIVE | Switch between standard **RCS** and **rotor** system (for atmospheres). RCS **throttle** reduces excessive G-force or allows precise velocity changes; linked to the throttle slider on the Docking & COMMS screen |

### 2.2 Docking & COMMS Screen
Right of the main nav screen. Records all communications.
- **POLARIS MFD (Multi Function Display):** switches between docking interface and comms display. While docking, the bottom section mirrors the maneuver drive throttle slider → precise docking without switching screens.
- **COMMS CONTROL:** side buttons select the option they point to.
  - Hail targets are sorted **by distance**; a **selected target always appears first** (top left).
  - To dock you must hail a ship/station **within 5 km** (proximity alarm range).
  - Then **request docking clearance**, or **announce intention to forcefully dock**.

---

## 3 Sources of Thrust
- Every thrust system needs a **minimum output** for the ship's mass, but has an **upper limit** because humans only survive so much G-force.
- Physics: F = m·a; acceleration = change of velocity vector (m/s²); heavy + fast = big impact damage.
- Nav Station reports thrust as **G-force** (acceleration): **1 G ≈ 9.81 m/s²** (≈ 10 m/s² for quick math).

### 3.1 RCS (Reaction control system)
- Only system at game start.
- Compressed gas (usually **N2**, **O2** works in a pinch) sprayed in one of **4 directions** from **thrusters**, fed by an **intake** (**RCS Intake Regulator: Kang "2202"** or **Hydra**).
- **Thruster position on the ship doesn't matter**, as long as it's powered and properly installed.
- Cheap to run, but low fuel density and expensive to scale: canisters deplete fast and must be **swapped manually**; limited by how many canisters you carry → refuel at stations or salvage more.
- Flight pattern: short/sustained bursts to speed up or slow down, long **drift** phase between.
- More thrusters → more thrust. More intakes → more fuel available. **Hydra accepts 4 tanks** instead of 1.
- Throttle slider (nav or docking screen) limits thrust.
- **One thruster ≈ 57 kN.** For **3 G**: **one thruster per ~1950 kg** of ship mass. Mass via **Print Status**.

### 3.2 Torch Drive
Advanced thrust powered by a **fusion reactor**. Differences from RCS:
1. **Fuel:** reactor fuel tanks (**deuterium** and **He3**) are large and heavy, but run the reactor for days, maybe weeks.
2. **Control:** can be left on unsupervised, but **only pushes forward** (blue arrow on ship center). No strafing/reversing; use RCS to strafe, change trajectory or rotate.
3. **Wake Zones:** areas around stations where the torch drive is **disabled**. Approach at a safe velocity before entering, or the sudden loss of control can cause a crash.
- Safe-thrust limiter can be overridden (switch under the other red cover) for manual and autopilot, but high G can make you pass out or get thrown around and injured.
- **Only one reactor per ship can contribute to thrust** at a time.

#### 3.2.1 Autopilot
- **Pause the game while plotting**, otherwise it won't work properly and will likely fail to engage.
- The game currently **overestimates** reactor fuel use for a journey.
- Only for distances **> 5000 km**; can't plot or activate **inside a wake zone**.
- Three phases: **acceleration → drift (torch off) → deceleration** (matches target's speed; aims at where the target will be).
- You set the **acceleration limit** and **drift duration**; it estimates fuel and travel time.
  - Low acceleration limit → reactor burns longer → more fuel. Upper limit = what your body survives.
  - Short drift → more fuel, less time; long drift → less fuel, more time. Compromise as needed.
- Should arrive slow enough for RCS to take over — but not always. **Verify with the map fast-forward** that you can stop before hitting the target.
- You can take manual control anytime; to re-engage autopilot you must **re-plot**.

#### Manual torch control
- Reactor on → nav station **TORCH DRIVE** panel (bottom left) → open red switch cover, flip switch.
- Two sliders: **Cycle** (how open the thrust port is = main thrust control) and **Flow** (fuel flow rate); watch the **Core Temp** light:
  | Core temp | Meaning |
  |---|---|
  | Green | Correct – keep it here |
  | Red (too hot) | Risk of **explosion** |
  | Yellow (cold) | Less thrust, inefficient fuel use; too cold → reactor **shuts off** |
- Without enough Flow for the Cycle setting, the core cools down.
- More **pairs of Pellet Feeder Assemblies + Laser Arrays** on the reactor → higher max fuel flow. One pair comfortably supports a **medium** ship; larger/heavier ships may want more.
- Tip: Cycle fixed but accelerometer **slowly decreasing** → Flow too low, core cooling. Accelerometer **slowly increasing** → core heating up.

#### Atmospheric Propulsion (W.I.P. on wiki)
- Venus (likely first destination after Ganymed) has a thick atmosphere near the planet → **drag** (increases with speed).
- Use **rotors** and **aerodynamic panels**. Aero panels reduce drag; rotors keep you aloft and move you forward/back by angling the ship.
- **Flight Dynamics Monitor** (under the transponder panel) shows drag, lift and angle of attack.

---

## 4 Locale Navigation

### 4.1 Starting/Tutorial Area
- **1036 Ganymed** asteroid, **kLEG** station. Everything moves slowly relative to you; little gravity or atmosphere → mostly straight lines A→B.
- Ganymed's gravity is tiny but real: ships too close **get pulled in and destroyed**.
- Micrometeors are very rare here.
- Suggested speed **~200 m/s** (faster = less time, more fuel). Rarely above 1 km/s. No speed limit, but **high-speed docking damages the ship**.
- At 200 m/s, when the **5 km proximity alarm** sounds you have **~25 s** to impact; a **3 G** ship goes 200→0 m/s in **~7 s**.
- **kLEG charges per hour while docked** → consider a slow drift on the way back to repair salvage or sleep.

### 4.2 Interplanetary Travel
- Needed to progress the story: leave 1036 Ganymed's orbit.
- Huge differences in speed and distance → **only viable option is the Torch Drive**.
- Micrometeors are **very common** in open space.
- Duration depends on fuel spending and orbital positions: days, weeks or months. **First trip to Venus ≈ a little under a week.**

### 4.3 Venus
- Much larger than the starting asteroid; rotates quickly; strong gravity.
- CO2-rich atmosphere with **sulfuric acid droplets** that slowly melt **non-plastic hulls**.
- Reaching the **three stations closer to the planet** requires an **aerodynamic, acid-resistant** ship.
- **VORB** = only station safely outside the atmosphere; orbits Venus rapidly → hard to dock for inexperienced pilots.
- At VORB: buy a new ship, scavenge nearby derelicts to build/upgrade, or (expensive, slow) pay for a **ferry** to the lower stations.

### 4.4 Other POIs
- As of v0.14.5.14 only the starting area and Venus are fleshed out. Other POIs have placeholder stations: visit family, sightseeing, or gigs.

## 5 Polaris Navigation Console User Guide (Version 0.11)
(Not yet recorded.)
