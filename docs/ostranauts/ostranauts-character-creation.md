# Ostranauts – Character Creation (Reference Memory)

Source: Ostranauts wiki, "Character Creation" page (game data v1.0.0.17). Section numbering follows the wiki's table of contents.
Game terms kept in English to match in-game names. `[us]` = the player character.
Wiki pages: Skills & Hobbies → https://ostranauts.wiki.gg/wiki/Skills, Traits → https://ostranauts.wiki.gg/wiki/Traits

Overview of the flow:
1. **Portrait Creation** – looks and identity.
2. **Build-a-Resume** – spend years of life on: Live Life & Gain Experience, Tweak Skills & Traits, Save Some Money, Seek Ship.
3. **Ship Registration** – submit once a ship is picked; character creation ends.

---

## 1 Portrait Creation
Customize name, pronouns, attraction preferences, skin, hair and many other options. Graffiti & stickers are part of the character creation GUI. Appearance can be changed later at any sink. (Gallery: wiki page "Facial Features".)

### 1.1 Starting Characteristics
Character starts at **18**, already in very poor shape (grew up on an asteroid: feeble, bad eyesight, insomnia, etc.).

| Trait | Description | Effect |
|---|---|---|
| Youthful | feels youthful | Baseline, no effect |
| Feeble | physically weaker than most | G-tol -0.125G, Encumbrance Limit -20%, Combat Damage Modifier -25%, Threat -12, StatMass -10, ThreshStatSecurity -0.1 |
| Fragile | physically easier to harm | G-tol -0.125G, Wound Resistance -20%, Pain Tolerance -20%, Threat -6, ThreshStatSecurity -0.05 |
| Micro-g Hypovolemic | permanently lowered circulating blood | StatBloodHealRate -0.0044, StatWoundHealRate -0.005, StatInfectionHealRate -0.0005, StatFatigueCoeff +0.5, StatSafeTempMin +2.78, StatPassiveRewarmTemp -0.56, Encumbrance limit -12.5%, Hunger Rate +0.15, Hydration Rate +0.15 |
| Immunosuppressed | permanently weakened immune system | Infection Heal Rate -0.2 |
| Insomniac | trouble falling and staying asleep | Sleep Comfort -3 |
| Slow Metabolism | digests food more slowly | 25% slower food & water meter drain |
| Sharp Hearing | hears things others don't | Defense +0.03 |
| Unfit | tired more easily by exertion | G-tol -0.125G, Fatigue Limit -25%, Threat -3, ThreshStatSecurity -0.03 |
| Visual Impaired [sic] | permanent vision impairment | Defense -0.06, Threat -3, Piloting -0.2, ThreshStatSecurity -0.03 |

Starting skills: **Spaceship Engineering** (designing, building, maintaining spacecraft), **Zero-G Ops** (zero-g movement and operations).

Net summary if nothing changed: slower heal rate, -0.375 max G-force tolerance, -25% melee damage, -10 kg body mass, ~15% faster food/water consumption, two basic skills.

### 1.2 Effects of Aging
- Semi-random negative traits gained at **29 (Middle Age)** and **42 (Old Age)**.
- At **47** during creation: forced to Seek Ship, accept the first offer, creation ends.

---

## 2 Build-a-Resume
- Build skills and traits; nearly any character is possible if you accept an older start age or hindrances.
- Some choices grant a ship → ends Build-a-Resume.
- Gaining a positive skill/trait while holding its negative counterpart **removes the negative instead** (e.g. offered "Tough" while "Fragile" → lose "Fragile", don't gain "Tough").

### 2.1 Live Life & Gain Experience
- Costs 1 year: a random narrative encounter = the most significant thing that happened that year. Multiple choices; some need skills/traits (incl. ones gained earlier in chargen) or luck.
- Rewards/penalties: traits, skills, contacts, items, money. Chaotic, but greatest return per year of all buttons. Skill-gated choices are high risk, high reward.
- "Seek Adventure" = same thing.

**SPOILERS below** – every option of every encounter.
Notation: **G** = guaranteed reward, **%** = independent chance roll, "Brig rewards" = Time in the Brig package, "RISK" = see 2.1.9.4.
Skills that appear here but are NOT buyable in Tweak Skills & Traits: Tracking, Intrusion, Forgery, Ranged Archery, Sensor Ops.

#### 2.1.1 King/Queen/Majesty Incognito (6 choices, high-variance social/criminal)
| Choice | Req. | Cash | Rewards | Other |
|---|---|---|---|---|
| Start a Riot | – | +$246 | Skills: Folk Etiquette, Unarmed Melee, Persuasion; Traits: Charismatic, Leader | Bartender Enemy, Manager Enemy; 1 Past Fight injury roll |
| Pick their Pocket | – | +$250 | G: Stealth; %: 25% Tracking, 50% Observant, 50% Patient, 50% Selfish | All four chance rolls independent |
| Just Mug Them | – | +$246 | G: Strong; %: 65% Armed Melee, 65% Unarmed Melee, 65% Ranged Gunpowder, 20% Brave, 20% Cruel, 20% Impatient | Manager Enemy, Bartender Enemy; **always → Time in the Brig** |
| Seduce Them | Matching attraction / available gender branch | $0 | G: Cooking, Dance, Charismatic, Beautiful; %: 40% Oligarch Etiquette | Manager Ex-Lover; gender variants use same reward pattern |
| Get Them Drunk | – | +$850 | Song, Liar, Slovenly | Manager Contact |
| RISK: Hack Them | Hacking | +$2,850 (both branches) | Success: G Software Engineering; % 35% Street Etiquette, 50% Hacking, 35% Stealth, 40% Ambitious, 40% Diligent, 40% Genius, 40% Observant, 40% Shy. Failure: Ambitious, Brave | Manager Enemy on either branch |

#### 2.1.2 Crackdown (5 choices, law-enforcement crackdown)
| Choice | Req. | Cash | Rewards | Other |
|---|---|---|---|---|
| Hide In An Air Vent | – | +$246 | Stealth, Intrusion, Craven | Random Adult Friend |
| Bluff | – | +$500 | Forgery, Acting | – |
| Have Nothing To Hide | – | $0 | Street Etiquette, Honest, Arrogant | Law Enforcement Friend |
| Fake A Pressure Alarm | – | $0 | Hacking, Genius | – |
| RISK: Be A Hero | Unarmed Melee | Success +$1,750 / Failure $0 | Success: Ranged Archery, Brave. Failure: Brig rewards | Success: Law Enforcement Enemy + 1 Past Fight injury roll. Failure: Time in the Brig |

#### 2.1.3 Occupational Hazard (5 choices, engine emergency/evacuation)
| Choice | Req. | Cash | Rewards | Other |
|---|---|---|---|---|
| Hack Engine | – | $0 | Hacking, Genius | Criminal Contact |
| Take the Stick | – | $0 | Spaceship Piloting, EVA Suits | Random Adult Friend; 1 roll on Leg Injury Table |
| Jury Rig Engine | – | -$150 | Mechanical Engineering, Brave, Coordinated | – |
| Troubleshoot Engine | – | +$850 | Spaceship Piloting | – |
| RISK: Abandon Ship! | EVA Suits | Success $0 / Failure -$1,050 | Success: Bingham-12 EVA Suit, Helmet, EVA Battery, O2 Bottle, CO2 Filter. Failure: Scar: Severe Burn | Failure scar is permanent with chronic scar pain |

#### 2.1.4 Daily Grind (6 choices, off-shift activities/side work)
| Choice | Req. | Cash | Rewards | Other |
|---|---|---|---|---|
| Hacking | – | $0 | Hacking | Law Enforcement Enemy; Components: Motherboard, Heat Sink |
| Watch Old Movies | – | $0 | Acting, Observant | Manager Friend |
| Suit Maintenance | – | $0 | EVA Suits, Physics, Patient, Finicky | – |
| Fight Club | – | $0 | Unarmed Melee, Brave, Masochist | Law Enforcement Friend; Name Drop: Law Enforcement Officer; 1 Past Fight injury roll |
| Go Shipspotting | – | +$650 | Sensor Ops, Complacent, Shy | – |
| Electrician Gig | – | +$200 | Electrical Engineering, Patient | – |

#### 2.1.5 Rare Salvage (5 choices, valuable salvage find)
| Choice | Req. | Cash | Rewards | Other |
|---|---|---|---|---|
| Notify Ayotimiwa Corporate | – | $0 | Business Admin, Follower | Manager Contact; Ayotimiwa T-shirt |
| Smuggle It Through the Blackmarket | – | +$200 | Street Etiquette | Criminal Contact, Law Enforcement Enemy; Name Drop: Criminal |
| Bribe Your Boss and Split the Profits | – | +$750 | Oligarch Etiquette | Law Enforcement Enemy; Name Drop: Corporate Manager |
| Smash It and Feel Alive | – | $0 | Armed Melee, Cruel, Pessimist, Strong | Scar: Cargo Accident (chronic scar pain); 1–2 Small Mechanical Parts; independent 50% Motor; independent 50% Heat Sink |
| RISK: Take It For Yourself | Patient | $0 | Success: Miura "Hydra" RCS Intake Regulator (Loose). Failure: Brig rewards | – |

#### 2.1.6 Labor Barge Locker (5 choices, locked crate)
| Choice | Req. | Cash | Rewards | Other |
|---|---|---|---|---|
| RISK: Force the Lock | Strong | Success -$200 / Failure -$2,300 | Success: Laser Torch. Failure: nothing | Success also: Shipbreaker Friend |
| Hack the Lock | – | $0 | Hacking, Leader | Shipbreaker Friend |
| Cut Hole in Crate | – | +$700 | – | Guaranteed Severe Burns → later a permanent Severe Burn scar with chronic scar pain |
| Mislabel Crate | – | $0 | Street Etiquette, Leader | Shipbreaker Friend, Random Adult Friend |
| Report Poor Security | – | $0 | Business Admin, Loyal | Manager Contact; limited-edition Ayotimiwa shoulder bag |

#### 2.1.7 Poker Game (5 choices, Volatile prize ship)
| Choice | Req. | Cash | Rewards | Other |
|---|---|---|---|---|
| RISK: Call the Bluff | Gambling | Success $0 / Failure -$9,000 | Success: Gambling + **Volatile** (legal ownership, ends chargen). Failure: Gambling | – |
| No Thanks...Fold | – | +$900 | Gambling | – |
| Cheat | – | +$1,500 | Hacking | Law Enforcement Enemy; 1 Past Fight injury roll |
| Grab the Key and Run | – | -$6,500 | **Volatile** (stolen, NOT legally owned; ends chargen) | Criminal Enemy, 2 Random Enemies |
| Call Him On A Technicality | – | +$300 | Gambling | – |

#### 2.1.8 Shady Deal (5 choices, criminal scheme)
| Choice | Req. | Cash | Rewards | Other |
|---|---|---|---|---|
| RISK: Join the Scheme | Street Etiquette | Success +$4,500 / Failure $0 direct | Success: no skill/trait. Failure: Brig rewards | Failure also: Random Enemy |
| Gather Intel for Cops | – | $0 | Street Etiquette, Honest | Law Enforcement Friend |
| Backstab Them | – | +$900 | Treacherous | Criminal Enemy |
| Report to Ayotimiwa | – | +$900 | Selfish | Manager Contact, Law Enforcement Friend; limited-edition Ayotimiwa hoodie |
| Instigate Violence | – | +$900 | Armed Melee, Unarmed Melee, Tough | Criminal Enemy; 1 Past Fight injury roll |

#### 2.1.9 Shared Mechanics
Seek Adventure encounters advance the character's life by one year unless otherwise noted. Shared injury, prison and RISK mechanics are listed here once.

##### 2.1.9.1 Past Fight Injuries
Several encounters grant one or more rolls on this table.
| Injury | Chance | Visible during chargen? |
|---|---|---|
| Brawling Scar | 30% | No |
| Knife Scar | 20% | No |
| Strained Back | 15% | Yes |
| Aberrant Wound Healing | 10% | Yes |
| Gunshot Scar | 5% | No |
| Torn ACL | 5% | No |
| Torn MCL | 5% | No |
| Snooker Scar | 3% | No |
| Dart Scar | 3% | No |
| Crossbow Scar | 2% | No |
| Airlock Scar | 2% | No |

##### 2.1.9.2 Leg Injury Table
Occupational Hazard → Take the Stick always grants exactly one (all visible during chargen):
Aberrant Wound Healing 20%, Strained Back 20%, Torn ACL 20%, Torn MCL 20%, Torn Meniscus 20%.

##### 2.1.9.3 Time in the Brig
Shared prison package for every outcome that sends the character to the Brig.
| Component | Result |
|---|---|
| Additional age | +1 to 3 years |
| Past Fight injuries | 1 to 3 rolls on the Past Fight injury table |
| Guaranteed history / skill | Prisoner history; Excavation |
| Handcuff Scar | 90% chance |
| Relationships | Law Enforcement Enemy, Prisoner Friend, Criminal Enemy, Criminal Contact |
| Other | Multiple additional random skill, trait and scar rolls, plus possible chronic conditions |

##### 2.1.9.4 RISK Mechanics
- Seven encounter families have a RISK choice. Entering the encounter has a **50% chance to add a hidden failure token**.
- Choosing a non-RISK option does **not** clear the token. Attempting the RISK branch removes only **one** token → tokens can persist and **stack** across later encounters of the same family.
- "Clean-state nominal 50/50" = success chance with no leftover tokens.
- **Warning:** persistent-token behavior appears unintended. Confirmed in a runtime save for King Incognito; the other six use the same data structure (v1.0.0.17).

| Encounter | RISK choice | Failure token |
|---|---|---|
| King Incognito | Hack Them | IsEncRichHackFailChance |
| Crackdown | Be A Hero | IsEncHeroFailChance |
| Occupational Hazard | Abandon Ship | IsEncPodDisasterFailChance |
| Rare Salvage | Take It For Yourself | IsEncStealFailChance |
| Labor Barge Locker | Force the Lock | IsEncLockFailChance |
| Poker Game | Call the Bluff | IsEncPokerFailChance |
| Shady Deal | Join the Scheme | IsEncShadyDealFailChance |

For each: 50% chance to add on encounter intro; only that encounter's RISK choice removes one.

### 2.2 Tweak Skills & Traits
- Spend/gain Year(s) directly for Skills, Hobbies, Traits. Positive cost adds years; negative cost (e.g. -2) subtracts years.
- Removing an entry reverses the transaction. Can't leave the screen with a negative balance; age can't be reversed once set, but points can be reallocated as long as balance >= 0.
- Opposed traits (e.g. Ambitious vs Complacent): remove the counterpart's Year(s) first.
- Skills = expertise from study/practice, often speed boosts; learnable later by doing/studying. Hobbies = mostly social/conversational flags. Traits = inherent personality/body. Hobbies & traits are very rarely obtainable outside chargen.
- Skills/hobbies/traits can unlock, block or alter checks, interactions, events, dialogue even without a listed numeric modifier.
- Tip (derived): starting negatives (Feeble, Fragile, Unfit, Insomniac, Immunosuppressed, Micro-g Hypovolemic, Visually Impaired) can be removed; removing a negative-cost entry costs its years.

Work-rate legend (abbreviations in skill effects). Work-rate modifiers affect applicable installation, uninstallation, repair and related work actions.
| Abbr. | Work category | Abbr. | Work category |
|---|---|---|---|
| APPS | Appliances | CTRL | Controls |
| FURN | Furniture | HULL | Hull / structure |
| HVAC | Heating, ventilation, and air conditioning | MISC | Miscellaneous |
| POWR | Power | SENS | Sensors |
| SUIT | EVA-suit work | WPNS | Weapons |

#### 2.2.1 Skills
| Skill | Cost (yrs) | Effects |
|---|---|---|
| Business Admin | 2 | Shows exact item value; Business Admin checks (incl. some skilled-labor reqs) |
| Civil Engineering | 3 | APPS/CTRL/FURN/HVAC/MISC +4 |
| Combat Engineering | 3 | APPS/CTRL/FURN/HVAC/SENS/WPNS +4 |
| Construction | 3 | Mining rate +4 (see data note) |
| Electrical Engineering | 3 | APPS/CTRL/POWR/SENS +4 |
| EVA Suits | 3 | SUIT +4; prevents the 45% work-speed penalty in an EVA suit without this skill |
| Excavation | 3 | APPS/CTRL/POWR/SENS +4 (see data note) |
| Mechanical Engineering | 3 | APPS/CTRL/FURN/HVAC/MISC +4 |
| Robotics Engineering | 1 | CTRL/SENS +4 |
| Software Engineering | 1 | Software work rate +4 |
| Spaceship Engineering | 3 | HULL +4 |
| Spaceship Piloting | 3 | Piloting +0.5 |
| Zero-g Ops | 1 | No numeric modifier; Zero-g Ops skill/check flag |

**v1.0.0.17 data note:** Construction → Mining rate +4, Excavation → the APPS/CTRL/POWR/SENS +4 package also used by Electrical Engineering. Possibly swapped/misassigned; runtime-test before trusting.

#### 2.2.2 Hobbies
Listed under the Hobbies heading in-game; many are mainly skill/check flags.
| Hobby | Cost | Effects |
|---|---|---|
| Acting | 1 | Acting checks (social/job/event options) |
| Armed Melee | 2 | Attack dmg +50%, Security thr +10%, Threat +12 |
| Cooking | 1 | Cooking checks |
| Dance | 1 | Dance checks |
| Folk Etiquette | 1 | Working-class social checks |
| Forensic Science | 1 | Forensic Science checks |
| Gambling | 1 | Gambling checks/events incl. Poker Game options |
| Hacking | 2 | Software work rate +4; hacking interactions/checks |
| Military Etiquette | 1 | Military social checks |
| Oligarch Etiquette | 1 | Wealthy-class social checks |
| Persuasion | 1 | Persuasion checks/dialogue |
| Physics | 1 | Physics checks |
| Psychology | 1 | Psychology checks/dialogue/events |
| Ranged Gunpowder Weapons | 1 | Gunpowder ranged proficiency/checks |
| Song | 1 | Song checks (social/job/event options) |
| Stealth | 1 | Stealth checks/sneaking |
| Street Etiquette | 1 | Criminal social checks |
| Unarmed Melee | 2 | Attack dmg +50%, Security thr +10%, Threat +12 |

#### 2.2.3 Traits
"thr" = threshold. Positive threshold modifier = need/stat can deteriorate farther before crossing the threshold; negative = reached sooner.
Rows in wiki order; traits without an opposite have "–" on the right.

| Trait | Cost | Effects | Opposite | Cost | Effects |
|---|---|---|---|---|---|
| Ambitious | 1 | Achievement thr -20% | Complacent | -1 | Achievement thr +20%, Respect thr +20% |
| Apathetic | 2 | Achievement thr +20% | Finicky | -2 | Achievement/Altruism/Autonomy/Contact/Respect/Family/Intimacy/Meaning/Privacy/Satiety/Security/Self Worth/Weird thr -10%; Sleep Comfort thr +25% |
| Beautiful | 1 | Flag only | Ugly | -1 | Flag only |
| Brave | 2 | Security thr +20%, Threat +6 | Craven | -2 | Security thr -20%, Threat -6 |
| Charismatic | 3 | Flag only | Repulsive | -3 | Flag only |
| Chaste | -2 | Intimacy thr +20%; restricts some romance | Lustful | -2 | Intimacy thr -20%; affects romance |
| Comedian | 3 | Respect/Meaning/Self Worth thr +5% | Humorless | -3 | Respect/Meaning/Self Worth thr -5%, Threat +3 |
| Coordinated | 1 | Defense +0.25, Threat +3, Piloting +0.1 | Clumsy | -1 | Defense -0.25, Threat -3, Piloting -0.025 |
| Diligent | 1 | Achievement/Self Worth thr -10% | Quitter | -1 | Achievement/Self Worth thr +10% |
| Fast Healer | 1 | Wound heal +0.025, Blood heal +0.0089, Infection heal +0.2 | Slow Healer | -1 | Wound -0.025, Blood -0.0089, Infection -0.2 |
| Fit | 3 | G-tol +12.5%, Fatigue thr +25%, Security thr +3%, Threat +3 | Unfit | -3 | G-tol -12.5%, Fatigue thr -25%, Security thr -3%, Threat -3 |
| Forgiving | 1 | Flag only | Vengeful | -1 | Flag only |
| Genius | 3 | Flag only | Obtuse | -3 | Flag only |
| Gregarious | 3 | Contact thr -20%, Privacy thr +20% | Shy | -3 | Contact thr +20%, Privacy thr -20% |
| Heavy Sleeper | -1 | Sleep Comfort +2 | Light Sleeper | -1 | Sleep Comfort -2 |
| Honest | 1 | Altruism/Meaning/Self Worth thr -10% | Liar | -1 | Altruism/Meaning/Self Worth thr +10% |
| Humble | 1 | Respect/Self Worth thr +10% | Arrogant | -1 | Self Worth/Respect thr +20% |
| Immunosuppressed | -1 | Infection heal rate -0.2 | – | | |
| Insomniac | -2 | Sleep Comfort -3 | – | | |
| Iron Stomach | 2 | Immune to Gastroenteritis | Weak Stomach | -1 | Can trigger Weak Stomach illness |
| Kind | 3 | Altruism thr -20% | Cruel | -3 | Altruism thr +20%, Threat +6 |
| Leader | 3 | Autonomy thr -20% | Follower | -3 | Autonomy thr +20% |
| Loyal | 1 | Respect/Family/Meaning/Self Worth thr -5% | Treacherous | -1 | Respect/Family/Meaning/Self Worth thr +5%, Threat +3 |
| Masochist | 1 | Pain tol +50%, Security thr +10%, Threat +12 | Agliophobic | -1 | Pain tol -25% |
| Micro-g Hypovolemic | -1 | Blood heal -0.0044, Wound heal -0.005, Infection heal -0.0005, Fatigue gain coeff +0.5, Min safe temp +2.78°C, Passive rewarm -0.56, Encumbrance thr -12.5%, Food & Hydration consumption +15% | – | | |
| Observant | 3 | Defense +0.06, Piloting +0.05 | Oblivious | -3 | Defense -0.06, Threat -3, Piloting -0.1 |
| Optimist | 1 | Achievement/Altruism/Autonomy/Contact/Respect/Family/Intimacy/Meaning/Privacy/Satiety/Security/Self Worth/Weird thr +10%; Sleep Comfort thr +25% | Pessimist | -1 | same needs thr -10%; Sleep Comfort thr +25% |
| Patient | 1 | Achievement/Autonomy thr -20% | Impatient | -1 | Achievement/Autonomy thr -20% (as listed on wiki – likely error) |
| Selfless | 1 | Altruism thr -20% | Selfish | -1 | Altruism thr +20% |
| Sharp Hearing | 1 | Defense +0.03 | Poor Hearing | -1 | Defense -0.03 |
| Slow Metabolism | 1 | Food/Hydration consumption -25% | Fast Metabolism | -1 | Food/Hydration consumption +25% |
| Smoker | -1 | No numeric modifier; applies Smoker flag | – | | |
| Strong | 2 | G-tol +12.5%, Encumbrance thr +50%, Attack dmg +50%, Security thr +10%, Threat +12, Body mass +15 kg | Feeble | -2 | G-tol -12.5%, Encumbrance thr -20%, Attack dmg -25%, Security thr -10%, Threat -12, Body mass -10 kg |
| Stubborn | 1 | Autonomy/Respect/Self Worth thr -10% | Pushover | -1 | Autonomy/Respect/Self Worth thr +10% |
| Temperate | 2 | Satiety thr -30%, Sleep thr +20% | Glutton | -2 | Satiety thr +50%, Sleep thr -20% |
| Tidy | 1 | Achievement/Meaning/Security/Self Worth thr -5% | Slovenly | -1 | Achievement/Meaning/Security/Self Worth thr +5% |
| Tough | 1 | G-tol +12.5%, Wound threshold/resistance +20%, Pain tol +20%, Security thr +10%, Threat +6 | Fragile | -1 | G-tol -12.5%, Wound threshold/resistance -20%, Pain tol -20%, Security thr -5%, Threat -6 |
| Trusting | 1 | Autonomy thr +5%, Family thr -5%, Meaning thr +5%, Threat -3 | Suspicious | -1 | Autonomy thr -5%, Family thr +5%, Meaning thr -5% |
| Visually Impaired | -1 | Defense -0.06, Security thr -3%, Threat -3, Piloting -0.2 | – | | |

#### Sortable Skills/Hobbies/Traits Year(s) Index
All 104 entries grouped by year cost (13 skills, 18 hobbies, 73 traits; values match the tables above).

| Year(s) | Skills | Hobbies | Traits |
|---|---|---|---|
| 3 | Civil Engineering, Combat Engineering, Construction, Electrical Engineering, EVA Suits, Excavation, Mechanical Engineering, Spaceship Engineering, Spaceship Piloting | – | Charismatic, Comedian, Fit, Genius, Gregarious, Kind, Leader, Observant |
| 2 | Business Admin | Armed Melee, Hacking, Unarmed Melee | Apathetic, Brave, Iron Stomach, Strong, Temperate |
| 1 | Robotics Engineering, Software Engineering, Zero-g Ops | Acting, Cooking, Dance, Folk Etiquette, Forensic Science, Gambling, Military Etiquette, Oligarch Etiquette, Persuasion, Physics, Psychology, Ranged Gunpowder Weapons, Song, Stealth, Street Etiquette | Ambitious, Beautiful, Coordinated, Diligent, Fast Healer, Forgiving, Honest, Humble, Loyal, Masochist, Optimist, Patient, Selfless, Sharp Hearing, Slow Metabolism, Stubborn, Tidy, Tough, Trusting |
| -1 | – | – | Agliophobic, Arrogant, Clumsy, Complacent, Fast Metabolism, Fragile, Heavy Sleeper, Immunosuppressed, Impatient, Liar, Light Sleeper, Micro-g Hypovolemic, Pessimist, Poor Hearing, Pushover, Quitter, Selfish, Slovenly, Slow Healer, Smoker, Suspicious, Treacherous, Ugly, Vengeful, Visually Impaired, Weak Stomach |
| -2 | – | – | Chaste, Craven, Feeble, Finicky, Glutton, Insomniac, Lustful |
| -3 | – | – | Cruel, Follower, Humorless, Oblivious, Obtuse, Repulsive, Shy, Unfit |

### 2.3 Save Some Money
- 1 year → about **$300–$600**. Reliable, useful because money is very tight at game start, but very low compared to other options.

### 2.4 Seek Ship
- 1 year → one random starter ship from the pool is offered (setting year: 2079). Decline (spend another year looking) or buy. Buying = take on the ship's loan, ends character creation.
- Starting ship is the main indicator of start difficulty. Key factors: **mortgage amount** (a portion is paid at the end of every shift), **ship size** (storage during salvage), **working life support**.
- First playthrough: restricted pool until the tutorial is completed once (tutorial ends when you travel to a derelict and dock with it). Then the full pool unlocks.

Starter ships:
- Always available: **Dream, TU-70a, TU-76a, TU-77a, Volatile** (Volatile also via Poker Game life event)
- After tutorial: **Box Sled, Lilliput, Melody, Retrofit**

---

## 3 Ship Registration
Once a starting ship is picked (via Seek Adventure or Seek Ship), the **Resume Ready** light turns on → click **Submit** → character creation ends.

## 4 References
Encounter, injury, Brig and RISK data come from wiki contributions dated 8 September 2026 (game data v1.0.0.17).
