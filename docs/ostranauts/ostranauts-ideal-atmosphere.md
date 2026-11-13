# Ostranauts – Ideal Atmosphere (Reference Memory)

Source: Ostranauts wiki, "Ideal Atmosphere" page. Game terms kept in English.
Wiki base: https://ostranauts.wiki.gg/wiki/

## 1 Ideal Atmosphere
- Goal: as Earth-like as possible.
- **No hyperoxia in Ostranauts** → pure O2 atmosphere is safe.
- Nitrogen is optional but useful: much cheaper than O2 and "pads out" the atmosphere to reach 100 kPa.

| Factor | Target | Notes | Input/Output of one human |
|---|---|---|---|
| O2 (molecular oxygen) | ~20 kPa | Vital. Below 20 kPa → hypoxia. Use a pump with an attached O2 canister to make rooms breathable, or wear a functional EVA Suit. | – |
| N2 (molecular nitrogen) | ~80 kPa (optional) | Helps keep a comfortable 100 kPa total and minimizes the effects of CO2 buildup. | – |
| CO2 (carbon dioxide) | ≤ 0.5 kPa | Keep minimal; too much → hypercapnia (CO2 poisoning). | ~8 kPa per tile per hour (as listed on the wiki) |
| Total pressure | ~100 kPa | 20 kPa O2 + 80 kPa N2 | – |
| Temperature | 290–300 K (17–27 °C / 63–80 °F) | Clothing and especially space suits insulate → tolerate a wider range. | – |
| Chemical hazards | None | Venus atmosphere is full of toxic chemicals: damages non-plastic hull pieces and airways (→ Chemical Pneumonitis). Remove contaminants with a Contaminant AtmoScrubber. | – |

## 2 Airtight Compartments
- A compartment holds pressure only with an airtight **hull**: undamaged walls and floors, no openings.
- Gas escapes through opened doors, open vents and any damaged hull piece.
- **Floors are required under door tiles** (even when closed), but not under walls or larger machinery that creates its own seal.
- Diagonal walls are airtight.

### Finding hull breaches
If pumping into an enclosed compartment doesn't hold pressure:
- Look for visible gas puffs.
- Press **X** → damage overlay; damaged objects show red.
- Damaged walls may not be obvious → watch for light escaping as you move.
- Damaged floors under installed equipment are harder to spot.
- Hover over tiles: damaged tiles show a tilde (**~**); right-click to cycle through objects on a tile and inspect them.

## 3 HVAC Systems
Parts used to manage atmosphere once compartments are airtight (wiki: System_Components#HVAC).
- Machines can be left **On** (constant full force), but that usually causes problems unattended.
- Best practice: set machines to **Auto** and control them with **pressure alarms** / thermostats.

### Pressure
- **Air Pump** – moves gas from an installed canister (or room) into a room (or into a canister).
- **O2 / N2 Pressure Alarms** – control the air pumps.
- **CO2 Pressure Alarm** – activates the CO2 scrubber(s).
- **O2 / N2 / CO2 Canisters** – supply or contain gas.
- **Wall vents** – allow airflow between isolated rooms that should be pressurized.
- **CO2 AtmoScrubber** – needs a receiving canister on its outflow tile (to hold CO2 for disposal) and a **CO2 Scrubber Cartridge**.

### Temperature
- **Heater** and **Cooler** – must be linked to a **Thermostat** alarm, otherwise they can create dangerous temperatures.
- **Thermostat** – controls heater/cooler.
- Gas released from a canister is **very cold** → put a heater in rooms with pumps.

### Hazardous gases
- **Contaminant AtmoScrubber** controlled by a **Contaminants Pressure Alarm** scrubs hazardous gases into a **Gas Canister** (works like the CO2 scrubber).

### What a basic ship actually needs
- **Cooler:** usually unnecessary; mainly needed with a **Fusion** reactor or heat-generating cargo.
- **CO2 scrubber:** can be redundant on ships that vent their atmosphere often (no proper airlock, or no long-term passengers).

### Typical auto setup per pressurized room (summary)
- O2 canister + Air Pump (Auto) + O2 Pressure Alarm (~20 kPa)
- N2 canister + Air Pump (Auto) + N2 Pressure Alarm (~80 kPa, optional)
- CO2 AtmoScrubber (Auto) + CO2 Pressure Alarm (≤0.5 kPa) + receiving canister on outflow tile + scrubber cartridge
- Heater (+ Cooler if needed) linked to a Thermostat (290–300 K)
- Wall vents to share air between connected rooms
- Optional: Contaminant AtmoScrubber + Contaminants Pressure Alarm + Gas Canister

## 4 Space Suit Atmosphere Management
Airtight suits hold their own internal atmosphere until the helmet or suit is removed.
- **Pressure Suit:** traps a small volume of the room's air when sealed (helmet on). O2 depletes and CO2 builds up → "refresh" often in a safe compartment by taking the helmet off and putting it back on.
- **EVA Suit:** undamaged, with full **O2 bottle**, **battery** and **CO2 filter** → automatically keeps a safe internal atmosphere (injects O2, removes CO2).

## 5 Gas Management Layout example
(The wiki shows an example layout image here; not reproducible as text.)
