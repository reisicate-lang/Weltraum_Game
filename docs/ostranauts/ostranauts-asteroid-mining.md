# Ostranauts – Asteroid Mining (Reference Memory)

Source: Ostranauts wiki, "Asteroid Mining" page (under construction, last edit 25 October 2026). Game terms kept in English.
Wiki base: https://ostranauts.wiki.gg/wiki/
Related: ostranauts-orders.md (MINE action), ostranauts-trading.md (5 Bulk Trading – minerals are NOT bulk goods), ostranauts-residential-status.md (BCER Port Mojave, BCRS Ring Station).

## 1 Mining
- The Belt (between Mars and Jupiter) holds mineral-rich asteroids; raw resources are mainly sold at **BCER (Port Mojave)** or **BCRS (Zhonghuamen Terminal)**.
- Asteroids have **no docking ports**: the player **tethers** to an asteroid (works like docking, places the ship next to a randomly generated asteroid cluster).
- Excavation with handheld tools or explosives:
  | Tool | Effect |
  |---|---|
  | Gott Mining Tool | Basic powered mining implement, mines most deposits; **+0.1 fatigue per use**; needs Gott battery |
  | Halvorson Mining Tool | Improved, more expensive mining laser; **+0.05 fatigue per use**; needs Halvorson battery |
  | Weber 'Sap' Mining Charge | Compact low-yield precision charge for controlled excavation |
  | Weber 'Core' Explosive | High-yield charge for rapidly displacing regolith |
- Explosives must be placed and armed, then move to a safe distance. Damaged explosives have a fail-safe kill-switch; poorly maintained charges are a hazard to the player and nearby vessels.
- Possible yields: Iron, Olivine (magnesium), Carbon, Silicates, Platinum, Iridium, Palladium, Cobalt, Gold, Wolfram (iron, manganese, tungsten), Hydrates (water source), Void Opal, Gangue Material.

### 1.1 Gott Mining Tool (wiki page "Gott Mining Tool")
"A Gott handheld power mining pick with inertial compensators. Baseline tool to mine most mineral deposits in micro-gravity."
| Stat | Value |
|---|---|
| Category | Tools |
| Base Price | 2500.0 |
| Max. Damage | 6.0 |
| Max. Dismantle Progress | 130.0 |
| Mass | 8.0 |
| Dismantle (50 % each) | Component: Heat Sink 1, Component: Motor 1, Small Electronic Parts 1, Small Mechanical Parts 1 |
| Repair | Screwdriver/Drill + Soldering Iron, no materials |
| Inventory | 1×2 slots; needs a charged **Gott brand battery** |
The "Halvorson Mining Tool" page has no content yet.

## 2 Storage and Transport
- Mined minerals are **physical items**, sold through **faction kiosks**, not via Cargo Pods.
- Store in backpacks, load backpacks onto carts; heavily loaded carts are hard to move and slow you down.

## 3 Mining Orders
PDA → Orders → **Mine** → mark asteroid tiles. With **AutoTask** the character mines them with an available mining tool.

## 4 Reputation Gain from Sales
Selling minerals to a faction kiosk raises reputation with that faction: about **+1 point per $12,000** of sale value (shown to one decimal place).

## 5 Mineral Yield and Value
- Each unit weighs **10 kg**, except **Regolith** and **Meteoric Iron** (20 kg) and **Gangue Material** (3 kg).
- Values depend on condition: (Refurbished, Worn), (Refurbished, Used), (Refurbished, Like New); Gangue has no condition.
- Sold for USD or faction **Scrip** at the faction kiosks on BCRS and BCER; other vendors may pay less.

| Mineral | Worn (USD / Scrip) | Used | Like New | Pristine? |
|---|---|---|---|---|
| Methane Ice | | | | 20 (24.84 kg) |
| Regolith | 16.63 / 0.83 | 24.94 / 1.25 | 33.25 / 1.66 | 35 |
| Ore: Carbon/Carbides | 47.03 / 2.35 | 70.54 / 3.53 | 94.05 / 4.70 | 99 |
| Ore: Hydrates | 71.25 / 3.56 | 106.88 / 5.34 | 142.50 / 7.13 | 150 |
| Gangue Material | | | | 150 |
| Ore: Olivine | | | | 180 |
| Ore: Silicates | 95 / 4.75 | 142.50 / 7.13 | 190 / 9.50 | 200 |
| Meteoric Iron | | | 337.5 / 16.03 | 450 |
| Water Ice | | | 1,140 / 57 | 1,200 (24.7 kg) |
| Ore: Wolfram | | | | 2,000 |
| Ore: Cobalt | | | | 4,000 |
| Ore: Palladium | | | | 8,000 |
| Ore: Gold | | | | 10,000 |
| Ore: Iridium | | | | 12,000 |
| Ore: Platinum | | | | 15,000 |
| Ore: Void Opal | | 79,800 / 3,990 | 106,400 / 5,320 | 112,000 |

Derived: Worn ≈ 47.5 %, Used ≈ 71 %, Like New ≈ 95 % of the pristine value; Scrip ≈ 1/20 of USD.
