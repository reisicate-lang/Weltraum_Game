# Ostranauts – Power (Reference Memory)

Source: Ostranauts wiki, "Power" page. Section numbering follows the wiki's table of contents. Game terms kept in English.
Wiki base: https://ostranauts.wiki.gg/wiki/
Related: ostranauts-salvaging.md (battery values, life support duration), ostranauts-ship-building.md (conduits on ceiling layer, minimal flyable ship), ostranauts-orders.md (POWR install category).

## 1 Overview
- Many objects need power.
  - **System Components** and some furniture → powered via **conduits** connected to **ship batteries**.
  - **Equipment** (tools etc.) → uses its own batteries, recharged at **charging stations**.
- Some equipment uses little or no power on **standby** and more when **actively working**.
- Losing power in a tool can cause an emergency; **losing ship power is an emergency**. Monitor power as closely as oxygen; always have a backup plan.
- **Conduits** matter just as much: losing power to one area can be as bad as losing all power → plan good cable runs **with redundancy**.
- About to run out of power? **Slow the ship down as much as possible** to avoid crashes.
- Worst case:
  - Call a **PASS shuttle** to the nearest station and buy a small battery to carry back, or
  - Dock with a nearby **derelict** and look for spare batteries.

### 1.1 Power Management
- Batteries are fairly light and cheap but take up space. A **damaged battery loses power and can store less**.
- **One standard-size battery powers a small ship for roughly 3–5 hours.** Add batteries as the ship and component count grow.
- **Power switches** = conduits that can be turned off. Switches or a **Signal Box** can shut off equipment that isn't needed, to save power.
- **Simple backup power system (1×2):** a **Mini XS Ship Battery** facing directly into a **Power Switch** set to **off**. When main power runs out, turn the switch on → roughly **1 hour** of emergency power, or enough to **start a fusion reactor**.
- Later: a **Fusion reactor** with a **Magnetohydrodynamic (MHD) Generator** gives functionally **infinite power** while running.

## 2 Calculating Power Usage
**Power Usage (kW) = PowerInfo Amount (kWh) ÷ TickPeriod (h)**

Where to find the values in the game data files:
| Value | File | Field | How to find it |
|---|---|---|---|
| PowerInfo Amount (kWh per tick) | `powerinfos.json` | `fAmount` | Item's `jsonPI` value in `condowners.json` (or similar) names its PowerInfo |
| TickPeriod (h) | `tickers.json` | `fPeriod` | Item's `aTickers` list in `condowners.json` names its ticker(s); most powered items use **"Power"** |

Example – `ItmHeater01`:
```
"aTickers" : [ "Power" ],
"jsonPI" : "Heater01",
```
- "Power" ticker: fPeriod = 0.000278 h (≈ 1 second).
- "Heater01" PowerInfo: fAmount = 0.0011 kWh.
- → 0.0011 / 0.000278 = **3.9 kW** for the heater.

## 3 List of power consuming devices
(as listed on the wiki; the table looks incomplete, and the battery rows probably show charge/discharge rates rather than consumption)
| Name | Type | Category | Power usage | Power usage (max) |
|---|---|---|---|---|
| AI Cargo | Item | Electronics | 20 kW | 20 kW |
| Azul Disposable BB | Item | Electronics | 0.005 kW | 0.005 kW |
| Compact S Ship Battery | Item | Electronics | 40.48 kW | 40.48 kW |
| Gott Power Tools | Item | Electronics | 0.0576 kW | 0.0576 kW |
| Halvorson Power Tools | Item | Electronics | 0.0576 kW | 0.0576 kW |
| IC Fusion Reactor: Station | Item | FusionParts | 500 kW | – |
| Mini XS Ship Battery | Item | Electronics | 20.24 kW | 20.24 kW |
| Power Cell | Item | Weapons | 0.05 kW | 0.05 kW |
| Ship Battery | Item | Electronics | 80.96 kW | 80.96 kW |
| Weber Laser Torch Battery | Item | Electronics | 0.82 kW | 0.82 kW |

Known from section 2: Heater ≈ 3.9 kW.

## 4 List of power generating devices
(Not yet recorded.) Known so far: Fusion reactor + MHD Generator = functionally infinite power while running.
