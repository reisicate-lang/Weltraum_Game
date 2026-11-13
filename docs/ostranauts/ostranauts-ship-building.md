# Ostranauts – Ship Building (Reference Memory)

Source: Ostranauts wiki, "Ship Building" page. Section numbering follows the wiki's table of contents. Game terms kept in English.
Wiki base: https://ostranauts.wiki.gg/wiki/
Related: ostranauts-ideal-atmosphere.md (airtight compartments, HVAC), ostranauts-ship-ownership.md (registration, transponder).

---

## 1 Basic Mechanics

### 1.1 Tiles and Layers
Grid-based; each tile has several layers:
| Layer | Used by |
|---|---|
| Subfloor (abstract, not used directly by player) | Space objects need for abstract reasons, e.g. Subfloor Bins opening, fusion fuel tank piping |
| Floor | Mostly airtight flooring; also storage like Subfloor Bins or Cargo Web |
| Lower space (above floor) | Equipment, loose objects, storage racking, the player |
| Upper space (above floor) | Lights, vents, overhead storage bins, air pumps |
| Ceiling (abstract) | Only power conduits; does not need to be sealed by hull |

Walls take both upper and lower space; most other objects take only one.

### 1.2 Hull
- Hull = walls + floors. Brands differ in stats, but **all hull pieces connect to each other**.
- Ships don't have to be airtight, but at least one pressurized space is beneficial for safety.
- Floors **under walls**: not needed to hold air.
  - Recommended under **interior walls**, so those walls can later be moved without pressure loss.
  - Optional under **exterior walls**: raises effective HP of the tile and stops micrometeors penetrating far.
  - Every floor tile adds **mass**.
- Sources: mostly salvaged from **derelicts**; any ship/station works if you can handle occupants/security. Small quantities (incl. rarer types) at **Kiosks** around **OKLG** station.
- No crafting or hull customization system currently.

### 1.3 Rooms
- Room types have equipment requirements/restrictions, used mainly for **buying/selling value**. Equipment works and NPCs use it regardless of room ("wrong room" doesn't matter for gameplay).
- Rooms still serve as a useful checklist. Common rooms:
  - **Airlock / Towing Room** – small room at the front airlock door to minimize pressure loss when boarding/leaving. Becomes a Towing Room with a **Towing Brace** (Ryokka "T7N").
  - **Bridge** (open or closed) – holds the **Navigation Console**. If only one room can be pressurized, make it this one.
  - **Engineering Room** – any mix of RCS intakes, HVAC equipment, power storage. RCS thrusters can go on any exterior wall without affecting room designations.
  - **Living Spaces** – beds, toilets, food/water/hygiene storage, recreation.
  - **Cargo Room** – holds salvage in transport; racks or large floor space.
- One big room (or no walls) is allowed but hard/expensive to keep pressurized and looks bad.
- Gas **instantly equalizes** through open space; through open doors/vents it **leaks slowly** based on pressure difference and capacity.
- AI seeks out supplies (food, water) when needed. Most activities except **sleeping** and **personal hygiene** can be done in an EVA suit.

### 1.4 Ship Name
Needs: powered **Polaris "Standard Navigation Console" Nav Station** aboard, a **PDA**, and a **Ship Broker Kiosk**.
1. Stand near the Nav Station (don't use it) → select **"Link to PDA"**.
2. In the PDA, click the Nav Station on the left → shows ship ID details (the link-confirm button can be ignored for renaming).
3. Click the **pencil icon** next to "Vessel Name", type the new name, confirm, exit.
4. Update the public record with **Ogiso's Register**: at a station with a **Ship Broker Kiosk**, use the **Ship Rating** service and accept the automated assessment → new rating + legally registers the new name.

---

## 2 Ship Value
Only matters when building ships to sell. Any ship (incl. starter ship) can be shrunk, expanded or fully rebuilt, but sometimes starting over is better.
**Cannot be changed:** the **front airlock door** and the **hull registry ID** (e.g. J-YV16).

### 2.1 Value Multiplier
- Rooms **multiply the value** of everything installed in them.
- More zoned and specialized rooms → higher ship value.

### 2.2 Ship Rating
Format **W-X-Y-ZZZZ** = condition – specialized room count – maneuverability – size. Used when buying/selling; gives info without docking. Calculate it at a **Ship Broker Kiosk** (e.g. Commercial District / Azikiwe Commercial of K-Leg).

**W – Condition** (average condition of all installed parts):
| Condition | Rank |
|---|---|
| 100% | A |
| 95–99% | B |
| 80–95% | C |
| 50–80% | D |
| < 50% | E |

**X – Rooms:** number of unique rooms.

**Y – Thrust** (mass ÷ number of thrusters):
| Mass per thruster | Rank |
|---|---|
| < 300 | A |
| up to 500 | B |
| up to 750 | C |
| up to 1500 | D |
| > 1500 | E |

**ZZZZ – Size** (width × length in tiles; each tile = 1/3 m per the wiki):
| Area (tiles) | Size class |
|---|---|
| < 250 | Small |
| up to 900 | Medium |
| up to 1600 | Lunamax |
| up to 2300 | Ceresmax |
| up to 3000 | Titanmax |
| up to 3700 | Very Large |
| > 3700 | Ultra Large |

---

## 3 Building Tips

### 3.1 Planning
- Build **placeholders** are good for planning, but don't leave many long-term (except on another ship): the AI keeps retrying incomplete tasks → slows unrelated work; too many queued tasks → lag.
- External tools: grid paper, third-party grid planners, Excel.

### 3.2 Material Collecting
- **Floors and conduits** of the same type stack to **5**, fit in backpacks or tote bags, and those bags fit in other containers.
- **9 Black Wing "KOMPART" backpacks in a Rakow Smart Crate** → carry up to **720 floors/conduits in one hand**.
- Installed or loose **racks**: 3 bags per tile = **240 items per tile**.
- **Walls and System Components don't stack**; storable only in racks, a dolly, or on the floor.
- Loose items add to ship mass → good practice:
  1. Leave bags of floors/conduits stashed on a station; carry only a few essential walls/components.
  2. To build/expand: lay out the floor plan from stockpile, make the ship minimally flyable (**Nav Station, ≥1 thruster + intake, antenna, transponder, battery**).
  3. Fly to a previously explored derelict and salvage its walls and extra machinery.
- A ship's make/model on the nav console map roughly tells its size and what wall types it has.

---

## 4 Example Tutorial
Required tools (same as for salvaging):
| Tool type | Purpose | Options |
|---|---|---|
| Structure Cutter | Uninstall hull sections for reuse | Horang "PlastHak" Hacksaw, Gott Angle Grinder, Weber 'Lance' Laser Torch |
| Welding tool | Install hull pieces, repair most items | Halvorson Friction Stir Welder, Weber 'Lance' Laser Torch |
| Soldering tool | – | Gott Soldering Iron, Weber 'Lance' Laser Torch |
| Screwdriver | Install/uninstall most system components and furniture | Horang "PlaScrew" Screwdriver, Gott Power Drill |
| Space suit | Work in vacuum | **Pressure Suit** + light (Phoebus Work Lamp or Renbao "Portal" PDA), **or EVA Suit** (built-in light, O2, CO2 filtration) |

Note: the **Weber 'Lance' Laser Torch** covers cutting, welding and soldering.

### 4.1 Preparation
- Example: extend a **Testudo Melody** to the south with a small **3×3 room**. Needs **20 floor sections and 11 walls**.
- Remove equipment/items in the way (here: a **cooler**, which blocks wall building).
- Saving pieces:
  - Floors under walls can be skipped — only do this for **exterior** walls (avoid surprise decompression if an interior wall is removed later).
  - **Outer corner walls can be skipped** since diagonal walls are airtight.

### 4.2 Using The Orders menu
1. Side bar → **Build** icon → **Hull** menu → pick generic **FLOOR** (any available floor) or a specific floor. **R** = rotate, **left click** = place placeholder.
2. Misplaced? **Orders** tab on the side bar → **Cancel** order.
3. Placeholders can be placed in advance to plan future expansions.
4. Toggle **Auto** behavior → character installs the floors.
- Build orders only work on the ship **you are standing on**. If placing fails, check you're on the correct side of the airlock.
5. Build **walls** the same way (Orders menu or manually via the Actions Menu).
- **Wall placeholders block movement** → leave at least one wall section open for access.
- Finally move the last wall section inside the build area and install it **from the inside**.

### 4.3 Link Rooms
1. Double-check the new room has no holes to the outside.
2. Uninstall one wall between new and old space → new area fills with atmosphere.
3. With a working HVAC system, the pressure drop triggers the **O2 alarm**, which activates the linked **air pump** and restores the atmosphere.
→ Extension complete.
