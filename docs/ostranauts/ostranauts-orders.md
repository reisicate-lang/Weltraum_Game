# Ostranauts – Orders (Reference Memory)

Source: Ostranauts wiki, "Orders" page. Section numbering follows the wiki's table of contents. Game terms kept in English.
Wiki base: https://ostranauts.wiki.gg/wiki/
Related: ostranauts-ship-building.md (4.2 Using The Orders menu), ostranauts-crew.md (3 Controlling Crewmembers).

## 1 Overview
- Orders automate **construction, maintenance and salvaging** by assigning tasks to the AI.
- **AutoTask** on → the player character also performs assigned tasks automatically, like other crew.
- Tasks are only done during **Work shifts**, never during **Untime**.
- Orders can only be assigned to the ship the character is **currently aboard**.

## 2 Order Types
- **Install** and **Orders** menus have separate buttons but share the **Crew Orders & Building** interface.
  - **Install menu** → places construction placeholders.
  - **Orders menu** → assigns tasks to existing objects (repair, uninstall, dismantle, …).
- Tasks are done automatically with AutoTask or by available crew. Characters fetch required **tools and materials** when available.
- Tasks that can't be done (missing resources, inaccessible location, other restrictions) are **skipped**.
- **R** rotates construction placeholders; rotation **resets after each placement**.

## 3 Install Menu
Eight categories (same abbreviations as the skill work-rate categories, see ostranauts-character-creation.md 2.2). Long sections have scroll bars.
| Category | Contents |
|---|---|
| HULL | Structural parts: walls, floors, doors, conduits |
| HVAC | Atmosphere systems: pumps, scrubbers, gas canisters |
| POWR | Electrical: power generation, storage, distribution, switches, lighting |
| SENS | Sensors and alarms, e.g. O2 and N2 alarms |
| CTRL | Control systems: navigation, RCS equipment |
| FURN | Furniture: chairs, tables, beds |
| APPS | Appliances / functional equipment: refrigerators, exercise machines |
| MISC | Everything that fits nowhere else |

## 4 Orders Menu
Two selections: an **Action** (what task) and an **object Filter** (which objects can be targeted). Only objects matching the active filter(s) in the selection are affected (e.g. UNIN with WALL + FLOOR selected only uninstalls walls and floors).
Click a single tile, or hold and drag to target many tiles.

### 4.1 Filter
| Filter | Targets |
|---|---|
| WALL | All walls |
| FLOOR | All floors |
| CONDUIT | All conduits |
| CAN | All canisters |
| EQUIP | All equipment, incl. furniture and lights |
| LOOSE | Anything uninstalled, incl. non-equipment items |

### 4.2 Action
| Action | Effect |
|---|---|
| CANC | Removes **all** orders from the selected tile, incl. build orders |
| UNIN | Uninstalls installed items |
| SCRA | Scrap: quickly breaks down an item |
| REPR | Repairs damaged items and restores worn items to max condition |
| DISM | Carefully dismantles objects to recover **maximum components** |
| HAUL | Marks loose items for transport to an appropriate Haul **Zone** |
| MINE | Marks rocks/asteroid tiles for excavation (see Asteroid Mining) |
| LOAD | Assigns reloading of ship-mounted weapons with compatible ammunition |

Tip (derived): SCRA is fast, DISM is slower but yields more components. Use DISM on valuable salvage.
