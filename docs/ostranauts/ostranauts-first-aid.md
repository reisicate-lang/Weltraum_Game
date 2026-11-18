# Ostranauts – First Aid (Reference Memory)

Source: Ostranauts wiki page "First Aid" plus the item pages of the treatments (pills, Scrap Cloth, Splint). Game terms kept in English.
Wiki base: https://ostranauts.wiki.gg/wiki/
Related: ostranauts-emergencies.md (Hygiene: Dirty raises the infection risk), ostranauts-character-creation.md (healing traits, scars, Past Fight injuries).

## 1 Health Issues
- **Cuts**: break in the skin (bladed weapons, gunshots) → **bleeding**, possibly **infection**.
- **Blunt trauma**: mostly **bruises**; severe forms are **fractures, sprains** and internal damage.
- **Fractures & Sprains**: bone and muscle damage → very severe pain, slows the character directly.
- **Infections**: untreated cuts can get infected. A dirty bandage, bad **Hygiene** or **Immunosuppressed** raise the risk. Severe infection shows white-red fluid on the wound; it severely delays healing and can kill.
- **Pneumonia** (lungs; can follow torso wounds): cough, fever, pain. **Chemical Pneumonitis** (inhaled poisonous gas): much more dangerous.
- **Blood loss**: bleeding or alcohol poisoning. Compounding: the less blood, the slower it regenerates; raises food and water need. **Internal bleeding** from internal injuries or radiation; poisons also reduce blood.
- **Disease**: bacteria, viruses, toxic gas, genetic conditions.

### 1.1 Chronic Conditions
- **Crippled limb** (an arm or leg that takes too much damage is permanently damaged):
  - Crippled arm: **Work Speed −50 %**, Encumbrance threshold −10 %, Threat −24.
  - Crippled leg: **Movement Speed −50 %**, Encumbrance threshold −10 %, Threat −24.
- **Brands**: permanent skin markings that flare up with pain; most removable at a first aid kiosk (not "Thief" and "Pirate").

### 1.2 Lethal Conditions
Asphyxiation · body temperature · malnutrition/dehydration · sustained G-LOC · **blood loss** (hypovolemic shock) · poisoning / **fatal infection** · critical internal damage: cardiac arrest (upper torso), pulmonary hemorrhage (lower torso, instant), severe brain trauma (head, instant).

## 2 Treatments
### 2.1 First Aid
Applied through the inventory window; pills by clicking them; splints, cloths and disinfectants by dragging them onto the body part.
- **Pain**: first sign of an injury, fades as it heals; dulled by painkillers.
- **Cuts**: dirty and clean **cloths stop the blood loss**. Optionally disinfect with a liquid applied to the wound:
  | Liquid | Effect |
  |---|---|
  | Water | Disinfect 50 % |
  | Label 99 Rice Wine | Disinfect 40 %, cut +0.03, infection rate +5 % |
  | Bismertnaya Vodka | Disinfect 80 %, cut +0.06 |
  | Moretti Coffee | Disinfect 20 %, infection rate +5 % |
- **Bruises**: avoid further damage.
- **Fractures & Sprains**: avoid further damage at all costs or risk losing the limb; a **splint** aids healing and prevents an incorrectly healed injury.
- **Infection**: clean the wound, take **antibiotics**.
- **Disease**: food, water, antibiotics; anti-nausea pills only remove nausea.
- **Organ trauma**: urgent medical assistance.

### 2.2 Medical Assistance
- Sleeping on a **powered medical bed**: wound healing +20 %, blood healing +0.45 %, infection healing +5 %, pain threshold +10 %.
- **Nanorobotic First Aid** at a Self Care Kiosk: "Immunostimulant", wound heal +40 %, blood heal +0.0133; later wound +15 %, blood +0.45 %.
- Medications: anti-nausea cures nausea · **standard painkiller** pain threshold +20 % (+10 % while wearing off) · **prescription painkiller** +70 % (+35 %) · **antibiotics**: "Immunostimulant", **infection heal rate +20 %**, cure Cholera, Gastroenteritis, Pneumonia, Hepatitis stage 1.

### 2.3 Treatment items (item pages)
| Item | Base Price | Mass |
|---|---|---|
| Pill: Van Buren "Amoxicillin" Antibiotic | 14.30 | 0.0003 |
| Pill: PharmaCon "Cavilo" Pain Relief (standard) | 5.80 | 0.0003 |
| Pill: Van Buren "Hydrocodone" Pain Relief (prescription) | 16.80 | 0.0003 |
| Scrap Cloth (Clean) | 2.40 | 0.025 |
| Splint | 148.95 | 1.11 |

## 3 Detailed Information
### 3.1 Injuries
Concussion: temporary Insomniac, Obtuse, Oblivious; 40 % nausea, 40 % vomiting, 80 % headache, 60 % dizzy; many need thresholds ×0.5.
Bleeding conditions by injury bleed rate: Minor, Moderate, Severe. Internal bleeding: hydration rate +0.1, blood rate +0.111.

### 3.2 Blood (blood supply lost, %)
| Lost | Condition | Effects |
|---|---|---|
| 0–15 | No Blood Loss | none |
| 15–30 | Minor Blood Loss | blood/wound/infection heal slower, fatigue +50 %, safe temp min +2.78, encumbrance −15 %, **food and hydration rate +0.15**, security threshold −10 % |
| 30–40 | Severe Blood Loss | slower healing, **fatigue +100 %**, safe temp min +5.56, encumbrance −25 %, **food and hydration +0.25**, defense −0.1, sleep threshold −95 %, security −25 % |
| > 40 | **Hypovolemic Shock** | **death** |

### 3.3 Infection
Limb infection: < 0.25 minor, 0.25–0.5 moderate, > 0.5 severe.
| Whole-body level | Condition | Effects |
|---|---|---|
| 0–35 | Healthy | none |
| 35–65 | Infection | 60 % feverish, encumbrance −12.5 %, fatigue threshold −25 %, defense −0.02, **fatigue gain +50 %**, **food/hydration +0.25**, **hygiene rate +0.5**, slower wound/blood/infection healing, safe temp range narrower by 2.78 °C |
| 65–95 | **Sepsis** | feverish, blood threshold −10 %, encumbrance −25 %, fatigue threshold −50 %, **fatigue gain +100 %**, food/hydration +0.25, hygiene rate +1, much slower healing, safe temp range narrower by 19.44 °C |
| > 95 | **Septic Shock** | **death** |

### 3.4 Disease
Pneumonia (stages 1–3: cough, pain +10, infection), Pneumonitis from NH3/H2SO4 (severe coughing, dyspnea, coughing blood), Gastroenteritis (Iron Stomach counters it; 50 % from "Filthy" hygiene), Cholera, Hepatitis (stages with pain and infection rates).

### 3.5 Traits
Fast Healer: wound +0.025, blood +0.0089, infection +0.2 · Slow Healer: the opposite · Micro-g Hypovolemic: wound −0.5 %, blood −0.44 %, infection −0.05 % · Immunosuppressed: infection −0.2.
Unconscious: wound heal +0.05, infection heal +0.2, blood heal +0.0089, food/hydration −0.5, defense −1.0, piloting −0.1.

### 3.6 Pain (0 none … 70 shock)
Abdominal pains +30 (severe +76) · blisters +10 (move −25 %) · ebullism (space without suit) +10 · headache +10 (mild +5) · **fractured rib +10** · chronic bad hands +26 (work −20 %) · chronic bad knee +26 (move −20 %) · mangled hand +8 (work −10 %) · chronic scar pain +30 · herniated disc +15 · severe pneumonia/pneumonitis +10 · **severe burns +10** (infection +10, wound heal −0.005, hygiene rate +0.25, sleep comfort −3).
