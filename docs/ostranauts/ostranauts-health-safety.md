# Ostranauts – Health and Safety (Reference Memory)

Source: Ostranauts wiki page "Health and Safety" (under construction, last edit 26 March 2026; stats verified against game files v0.14.5.18). Game terms kept in English.
Wiki base: https://ostranauts.wiki.gg/wiki/
Related: ostranauts-first-aid.md (injuries, diseases), ostranauts-ideal-atmosphere.md (gas targets, contaminant alarm).

## 1 Gas Pressure (2.1)
| Condition | Range (O2) | Effects |
|---|---|---|
| Norm Atmo | O2 > 16 kPa | none |
| Thin Atmo | O2 3–16 kPa | Gasping |
| Void Atmo | O2 < 3 kPa | Gasping, Ebullism |
A pressure suit put on in vacuum does nothing; a powered EVA suit still needs time to fill with oxygen.

## 2 Gas Temperature (2.2)
Cold < 22.85 °C (body temperature drops) · Mild 22.85–25.85 °C (stable) · Hot > 25.85 °C (body temperature rises).

## 3 Body Temperature (2.3)
| Condition | Range | Effects |
|---|---|---|
| Froze to Death | < 20.05 °C | dead |
| Hypothermia | 20.05–27.85 °C | wound heal −0.01, infection heal −0.001, defense −0.05, blood heal −0.0089, threat −6; security thr −20 %, intimacy thr −25 % |
| Freezing | 27.85–32.25 °C | wound heal −0.005, infection heal −0.0005, defense −0.02, blood heal −0.0044; security thr −10 % |
| Cold | 32.25–35.65 °C | none |
| Comfortable | 35.65–37.75 °C | none |
| Overheating | 37.75–38.85 °C | none |
| Heat Exhaustion | 38.85–41.15 °C | hydration rate +0.5, defense −0.02, sleep comfort −6, piloting −0.0025 |
| Heat Stroke | 41.15–42.55 °C | "Dizzy", hydration rate +1, defense −0.05, threat −6, piloting −0.005 |
| Organ Failure | > 42.55 °C | dead |

## 4 G-force (4.7)
1 G = 9.81 m/s². Rapid changes (incl. collisions) throw characters around; more carried mass = more risk.
Tolerance: Fit/Strong/Tough +12.5 % each (Unfit/Feeble/Fragile −12.5 %), Gravusine +50 % (+25 % wearing off), Compression Leggings +3.125 %, lying prone +75 %, any chair (incl. nav station) +12.5 %, Passenger Seat +25 %.
| Condition | G | Effects |
|---|---|---|
| Microgravity | 0–0.00005 | none |
| Normal Gravity | 0.00005–4 | encumbrance from carried weight |
| G-LOC | 4–9 | G-LOC warning, fatigue +50 %, defense −0.03, start losing consciousness |
| Supergravic | 9–35 | fatigue +100 %, defense −0.03, rapidly losing consciousness, minor damage |
| Hypergravic | > 35 | fatigue +100 %, defense −0.03, rapidly losing consciousness, significant damage |

## 5 Malnutrition (4.8)
"StatFood" ticks up by 1 per hour (modified by cold, blood loss, fatigue, infection, drugs; lowered by unconsciousness, atrophy).
| Condition | StatFood | Effects |
|---|---|---|
| Well-Fed | 0–7 | none |
| Stomach Growling | 7–72 | none |
| Malnourished | 72–650 | wound heal −0.005, infection heal −0.05, defense −0.05, blood heal −0.0045, encumbrance −0.125, satiety thr −25 %, fatigue thr −0.25, piloting −0.005 … |
| Starving | 650–1350 | wound heal −0.01, infection heal −0.1, defense −0.1, blood heal −0.0089, encumbrance −0.25, satiety thr −45 %, fatigue thr −45 %, piloting −0.01 … |
| Starved | > 1350 | death |

## 6 Gas Hazards (4.9)
### 6.1 CO2
Pressure: safe 0–0.3 kPa · warning 0.3–3 · unsafe > 3.
| Poisoning | kPa | Description |
|---|---|---|
| Malaise | 0.5–1 | feels vaguely unwell and flushed |
| Mild Hypercapnia | 1–1.5 (variant "2a" 1.2–2) | mild hypercapnia |
| Moderate Hypercapnia | 2–3.066 | |
| Advanced Hypercapnia | 3.066–5.066 | |
| Severe Hypercapnia | 5.066–8 | dizzy |
| Critical Hypercapnia | 8–9 | muscle tremors, body shutting down |
| Lethal Hypercapnia | > 9 | asphyxiating, death soon |
### 6.2 Sulfuric Acid (H2SO4)
Pressure: safe < 0.0001 · warning 0.0001–1 · unsafe > 1. Poisoning: Stinging Throat and Eyes 0.0001–0.1 · Burning Throat and Eyes 0.1–1 · Lethal Sulfuric Acid Inhalation > 1 (death imminent).
### 6.3 Methane
Present, but not implemented.
### 6.4 Ammonia (NH3)
Pressure: safe < 0.1 · warning 0.1–1 · unsafe > 1. Poisoning: Stinging Throat and Eyes 0.003–0.05 · Burning Throat and Eyes 0.05–1 · Lethal Ammonia Inhalation > 1 (death imminent).

## 7 In this game
- CO2 stages and contaminant stages (NH3 rows; one combined contaminant gas) as above; damage per hour our choice: Advanced 3, Severe 10 (+ dizzy, movement ×0.75), Critical 60, Lethal 600; Burning 2, Lethal Inhalation 300. Working suits protect.
- Void Atmo (O2 < 3 kPa) without a suit: Ebullism, pain +10 (First Aid 3.6), lasts 30 minutes after (our choice).
- Body temperature: the nine stages above. Air below 22.85 °C pulls the body temperature down, above 25.85 °C up; equilibrium 37 °C − 0.1 per °C of air below 22.85 (×0.5 with a thermal jacket) + 0.05 per °C above 25.85, approached at 1/h; suits keep the air mild (all rates our choice). Effects: Froze to Death and Organ Failure deadly; Hypothermia healing ×0.5, Freezing ×0.75 (our mapping of the wiki's heal-rate penalties); Heat Exhaustion hydration +0.5, Heat Stroke hydration +1 and dizzy (movement ×0.75). The old flat damage below 35 / above 39.5 °C is gone.
- G-force and malnutrition stages are recorded only, not yet used.
