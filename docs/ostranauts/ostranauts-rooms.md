# Ostranauts – Rooms (Reference Memory)

Source: Ostranauts wiki, "Rooms" page. Game terms kept in English.
Wiki base: https://ostranauts.wiki.gg/wiki/
Related: ostranauts-ship-building.md (1.3 Rooms, 2 Ship Value / Ship Rating).

## Basics
- A **room** = any enclosed area: surrounded on all sides by straight and/or diagonal walls, doors, airlock doors, etc.
- Room type is **assigned automatically** from contents, size and pressurization.
- Many room types **multiply the sales value of their contents** by a modifier. **Loose items and uninstalled equipment don't count.**
- Rule of thumb: the more specialized the room, the higher the modifier.
- Room type has almost no gameplay effect (equipment works anywhere); it matters for buying/selling value.

## Room Types
**Checked in the order listed**: the first matching type wins. E.g. a pressurized room with ≥4 tiles and a Reactor → Reactor Room; without a Reactor but with a Nav Station → Bridge (the wiki's example says Bridge (Open); by the list order it becomes Bridge (Closed) first if none of that type's forbidden items are present, otherwise Bridge (Open)).
Size = number of enclosed floor tiles, occupied or not.

| # | Room | Requirement | Forbidden | Pressurized? | Min size (tiles) | Value modifier |
|---|---|---|---|---|---|---|
| 1 | Reactor Room | IC Reactor | – | Yes | 4 | 1.6 |
| 2 | Bridge (Closed) | Nav Station | RCS Distributor, Recreation Items, Wellness Items, Toilet, IC Reactor, Bed | Yes | 4 | 1.5 |
| 3 | Towing Room | Towing Brace | – | Yes | 2 | 1.6 |
| 4 | Bridge (Open) | Nav Station | – | Yes | 4 | 1.3 |
| 5 | Airlock | Docking System | RCS Distributor, Ship Battery, Recreation Items, Wellness Items, Toilet, IC Reactor, Nav Station, Bed | Yes | 3 | 1.5 |
| 6 | Engineering | Engineering Item (Canister, Charger, Ship Battery, RCS Distributor) | – | Yes | 4 | 1.4 |
| 7 | Wellness Room | 2× Wellness Items (Fridge, Sink, Treadmill, Strength Trainer) | Toilet, IC Reactor, Bed | Yes | 4 | 1.9 |
| 8 | Recreational Room | Table, Fridge, Recreation Items (Terminal, TV, Bartop) | IC Reactor | Yes | 10 | 1.9 |
| 9 | Luxury Quarters | Bed, 2× Storage Bins, Light, Chair | Toilet, IC Reactor, Canister, Ship Battery, Hatch, RTA "Recharge Tank Assembly" (CO2/O2/N2 canister) | Yes | 12 | **2.0** |
| 10 | Bathroom | Toilet, Sink | – | Yes | 4 | 1.8 |
| 11 | Galley | Table, 4× Chairs, Fridge | Toilet, IC Reactor, Bed | Yes | 6 | 1.8 |
| 12 | Basic Quarters | Bed, Storage Bin, Light | Toilet, IC Reactor, Canister | Yes | 8 | 1.8 |
| 13 | Passenger Room (Medium) | 8× Chairs | Toilet, Sink, IC Reactor, Canister | Yes | 32 | 1.6 |
| 14 | Passenger Room (Small) | 4× Chairs | Toilet, Sink, IC Reactor, Canister | Yes | 16 | 1.4 |
| 15 | Gas Cargo Room | 6× Canisters | – | Yes | 12 | 1.2 |
| 16 | Cargo Room | 6× Cargo Containers (Bins, Racks) | – | Yes | 6 | 1.2 |
| 17 | Cargo Space (Exterior) | 6× Exterior Cargo Containers (Cargo Webs, Bins) | – | **No** | 6 | 1.05 |
| – | Blank (no specialization) | Enclosed area | – | Yes | N/A | 1.0 |

## Practical notes (derived from the table)
- Highest modifiers: Luxury Quarters 2.0; Wellness Room / Recreational Room 1.9; Bathroom / Galley / Basic Quarters 1.8.
- Because order matters, an item from an earlier type can "steal" the room: e.g. any **IC Reactor** makes it a Reactor Room; a **Nav Station** makes it a Bridge; a **Canister/Ship Battery/Charger/RCS Distributor** makes it Engineering before Wellness/Quarters etc. are checked. Keep engineering items out of living rooms.
- **Fridge** counts as a Wellness Item → a room with Fridge + Sink (and no Toilet/Bed/IC Reactor) becomes a Wellness Room before Recreational Room or Galley is checked.
- A Toilet + Sink room becomes a Bathroom only if no earlier type matches; Toilet is forbidden in most other living rooms.
- Cargo Space (Exterior) is the only type that doesn't need pressure.
- More distinct room types also raise the X value of the Ship Rating (see ostranauts-ship-building.md, 2.2).
