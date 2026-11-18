# Ostranauts – Micrometeorites, Emergency Items, Hygiene (Reference Memory)

Source: Ostranauts wiki pages "Micrometeorite", "Oxygen Candle", "\"Ripley\" Temporary Blister Seal Wall" and "Hygiene". Game terms kept in English.
Wiki base: https://ostranauts.wiki.gg/wiki/
Related: ostranauts-ideal-atmosphere.md (airtight hull, finding breaches), ostranauts-ship-building.md (hull).

## 1 Micrometeorite
- Small objects passing through the Solar System at high speed, occasionally hitting planets, stations and ships.
- A strike makes an audible impact noise, shows a momentary white line, and the **game speed returns to ×1**.
- Strong enough to damage **Wall and Floor tiles**, conduits and other equipment in the way → hull breaches, power outages, other issues.
- Protection: **Whipple Framework** (micrometeorite shield; Sundries Kiosk on OKLG, VNCA Mall); **additional wall layers** reduce the chance of a breach; **exterior equipment** (Cargo Netting, Cargo Pods …) can prevent a breach.

## 2 Oxygen Candle
"An emergency, single-use device that, once activated by a spring-actuated hammer, chemically generates oxygen from Lithium perchlorate (LiClO4). Most effective in small, stable compartments."
| Stat | Value |
|---|---|
| Category | LifeSupport |
| Base Price | 360.0 |
| Max. Damage | 8 |
| Molar Volume / Ref | 107.5 |
| Max. Gas Pressure | 20684.0 |
| Gas Temperature | 293.0 |
| Mass | 1.8 |
| Max. Timer | 3600 |
| Volume | 0.03 |
| Scrap | Trash 1 |
Conditions: Airtight Handheld Solid Pocketable EmergencyO2. Interactions: ACTActivateOxygenCandle, DropItem, PickupItem, ACTBash.

## 3 "Ripley" Temporary Blister Seal Wall
Tool to **temporarily seal wall tiles** damaged by micrometeorites or similar impacts; short-term structural integrity and no atmosphere loss.
| Stat | Value |
|---|---|
| Category | Hull |
| Base Price | 79.0 |
| Max. Damage | 2 |
| Max. Gas Pressure | 3000 |
| Max. Install Progress | 10 |
| Mass | 4.0 |
| Max. Timer | 3600 |
| Max. Uninstall Progress | 10 |
| Scrap | Trash 1 |
Conditions: Halvorson Wall SealTemp Installed CheckRoom Solid Sheet.

## 4 Hygiene
- Character condition with a HUD bar (since 0.14). Without cleaning it drops; too low → **Dirty** (later **Filthy**): higher wound infection risk, slower healing, much lower infection recovery.
- **Wearing sealed suits (EVA or pressure) for long periods accelerates hygiene loss** and reduces sleep comfort.
- Cleaning: **Freshen Up** with water (Sink, water containers; uses 1 unit of water); **Hygiene Pack** (consumable kit, turns into trash after one use; sold at station vendors); **Toothbrush** (reusable; freshness buff, must wear off before brushing again).
