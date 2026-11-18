# Ostranauts – Bulk Trading (Reference Memory)

Source: Ostranauts wiki pages "Bulk Trading" (Main Mechanics, last edit 11 September 2026) and "Cargo Pod" (+ Climate-Controlled, Radiation-shielded, Specialty). Game terms kept in English.
Wiki base: https://ostranauts.wiki.gg/wiki/
Related: ostranauts-trading.md (5 Bulk Trading summary), ostranauts-residential-status.md (station codes, visa discount).

## 1 Overview
- The **System market** uses the **Cargo Kiosk** (Cargo Trade Kiosk) to exchange goods with your **cargo pods**. **19 stations** use this system.
- Needs cargo pods aboard. In Port Azikiwe the kiosk is around the corner from Fuel Services and Ferry Services.
- Buying: select the pod for the goods, then the good in the Station Market list. Goods the pod cannot hold (e.g. Consumer Goods need radiation protection) are greyed out. Buy/Sell slider sets the amount; the maximum depends on the weight of each good.
- **Each cargo pod holds at most 1000 kg**; most goods cannot fill a pod completely because their unit weights do not divide 1000 evenly. One good per selected pod.
- Selling: select a pod with a good, slider towards Sell, confirm.
- The Cargo Kiosk UI shows a **Visa Discount status** (citizens get a discount; amount not stated).

## 2 Cargo Pods
| Pod | Base Price | Damaged | Mass |
|---|---|---|---|
| Cargo Pod (standard) | 5000 | 1000 | 50.0 |
| Cargo Pod: Climate-Controlled | 12000 | 2400 | 50.0 |
| Cargo Pod: Radiation-shielded | 12000 | 2400 | 50.0 |
| Cargo Pod: Specialty (both) | 20000 | 4000 | 50.0 |
- Standard pod dismantles into: Component: Motherboard 1, Scrap Aluminum 8, Scrap Steel 4, Small Mechanical Parts 10, Trash 2. Repair with Screwdriver/Drill and Welder, no materials.
- Pods sell for about **44 % less when sold from a (barter) zone** ($27k → $15k); bring them to the cargo kiosk individually.

## 3 Station Market
- '+' or '-': the station buys and sells the good; '/' (empty here): neither stocks nor buys it.
- One sign = 0–34 %, two = 35–55 %, three = 56–80 %. Trade goods vary **±19 %**.
- Stations produce, consume or convert goods. Example: BCRS and JFTS produce Volatiles, MHNG converts Volatiles to Life Support, OKLG_FLOT consumes Life Support → '-' = produced (cheaper), '+' = consumed (dearer).
- Every station has a finite **market size** (the number after the sign). Large economies (MTRS, SVIR) sell more than small stations can take.
- EJDR_GEO prices follow EJDR, MTAM follows MTRS (not exactly 1:1).
- Station types/locations: BCER ground Ceres · BCRS orbital Ceres · EJDR ground Luna · HQCH orbital Mercury · JATL ground Europa · JFTS ground Ganymede · JPTN orbital Europa · MHNG orbital Mars · MLAB ground Mars · MSUZ orbital Mars · MTRS ground Mars · MVOL ground Deimos · OKLG ground 1036 Ganymed · OKLG_FLOT orbital (stationary) 1036 Ganymed · SVIR ground Titan · VCBR, VENC, VNCA aerostats Venus · VORB orbital (fast) Venus.

| Good | BCER | BCRS | EJDR | HQCH | JATL | JFTS | JPTN | MHNG | MLAB | MSUZ | MTRS | MVOL | OKLG | OKLG_FLOT | SVIR | VCBR | VENC | VNCA | VORB |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Consumer Goods | + 110 | +++ 660 | +++ 880 | -- 180 | / | +++ 1320 | / | --- 3300 | -- 2200 | / | --- 13200 | / | +++ 500 | / | / | / | +++ 1100 | - 3300 | -+ 3300 |
| Control Systems | / | / | / | / | / | / | / | / | / | / | / | - 330 | - 500 | / | +++ 8800 | + 130 | +++ 1100 | ++ 3300 | +++ 3300 |
| D2O | / | +++ 660 | / | / | --- 220 | / | --- 500 | / | / | / | ++ 13200 | / | / | / | -- 8800 | / | / | / | ++ 2000 |
| Electronics | +++ 110 | / | / | / | +++ 220 | ++ 1320 | + 500 | - 3300 | - 2200 | - 500 | +++ 13200 | ++ 330 | / | / | / | + 130 | / | / | -+ 130 |
| Food | / | +++ 660 | +++ 880 | ++ 180 | / | / | / | --- 3300 | +++ 2200 | --- | --- 13200 | / | +++ 500 | +++ 100 | / | / | +++ 1100 | / | -+ 1100 |
| Furniture | / | +++ 660 | / | / | / | - 1320 | -- 500 | / | / | - 500 | / | / | - 500 | - 100 | +++ 8800 | / | / | / | +++ |
| Fusion Parts | / | / | / | / | - 220 | / | / | / | / | / | - 13200 | - 330 | / | / | +++ 8800 | / | / | / | +++ 2000 |
| He3 | / | -+ 660 | - 1760 | / | / | / | / | / | / | / | +++ 13200 | / | / | / | - | / | / | / | +++ 2000 |
| Hull Parts | / | --- 660 | -- 880 | / | / | / | / | / | / | / | / | --- 330 | -- 500 | --- 100 | +++ 8800 | - 130 | -+ 1100 | - 3300 | - 3300 |
| HVAC | / | / | / | / | ++ 220 | / | + 500 | / | - 2200 | / | / | / | / | / | +++ 8800 | - 130 | - 1100 | - 3300 | -+ 3300 |
| Industrial Products | / | +++ 660 | +++ 880 | ++ 360 | ++ 220 | +++ 1320 | + 500 | / | +++ 2200 | +++ 500 | ++ 13200 | - 330 | +++ 500 | / | - 8800 | + 130 | / | -+ 3300 | - 3300 |
| Intoxicants | + 110 | +++ 660 | +++ 880 | +++ 180 | / | / | / | -- 3300 | / | / | - 13200 | / | / | - 100 | / | / | / | --- 3300 | -+ 3300 |
| Life Support Goods | + 110 | +++ 660 | +++ 880 | ++ 180 | -- 220 | / | / | --- 3300 | / | / | --- 13200 | --- 330 | +++ 500 | +++ 100 | +++ 8800 | / | / | --- 3300 | -+ 3300 |
| Luxury Goods | / | / | + 880 | / | / | / | / | +++ 3300 | / | / | - 13200 | / | / | / | - 8800 | / | - 1100 | +++ 3300 | ++ 3300 |
| Media | --- 110 | +++ 660 | +++ 880 | / | / | +++ 1320 | +++ 500 | +++ 3300 | +++ 2200 | / | - 13200 | / | +++ 500 | / | / | / | - 1100 | - 3300 | -+ 3300 |
| Medical Items | / | +++660 | / | ++ 180 | ++ 220 | +++ 1320 | / | +++ 3300 | ++ 2200 | / | - 13200 | -- 660 | / | / | +++ 8800 | / | / | / | / |
| Metals | / | --- 660 | / | -- 180 | ++ 220 | +++ 1320 | +++ 500 | / | / | +++ 500 | +++ 13200 | +++ 330 | / | / | +++ 8800 | / | / | +++ 3300 | +++ 3300 |
| Ores | / | ++ 660 | / | --- 720 | / | --- 1320 | / | / | / | / | / | / | -- 500 | / | / | / | / | / | / |
| Plastics | / | / | / | / | / | +++ 1320 | / | / | / | +++ 500 | +++ 13200 | +++ 330 | / | / | / | + 130 | --- 1100 | --- 3300 | -+ 3300 |
| Science | / | / | / | --- 180 | --- 220 | / | - 500 | - 3300 | / | - 500 | / | + 660 | / | / | +++ 8800 | -- 390 | +++ 1100 | / | -+ 1100 |
| Sensor Components | / | / | / | / | - 220 | / | / | / | / | / | - 13200 | --- 330 | - 500 | / | ++ 8800 | +++ 130 | / | +++ 3300 | -+ 3300 |
| Space Suits | - 110 | / | / | / | / | - 1320 | - 500 | / | / | --- 500 | / | / | / | / | - | / | / | / | ++2000 |
| Textiles | +++ 110 | / | / | / | / | + 1320 | + 500 | + 3300 | --- 2200 | / | - 13200 | / | / | / | ++ 8800 | / | + 1100 | --- 3300 | -+ 3300 |
| Tools | / | / | / | ++ 360 | / | - 1320 | --- 500 | / | / | - 500 | ++ 13200 | - 330 | +++ 500 | / | +++ 8800 | / | / | / | / |
| Trash | / | --- 660 | --- 880 | +++ 720 | / | ---1320 | / | --- 3300 | --- 2200 | / | / | / | / | ++ 400 | --- 8800 | / | --- 1100 | --- 3300 | -+ 3300 |
| Volatiles | --- 440 | --- 660 | / | / | / | - 1320 | --- 500 | + 3300 | / | / | +++ 13200 | +++ 330 | / | / | - 8800 | / | / | +++ 3300 | -+ 3300 |
| Water | - 110 | +++ 660 | +++ 880 | / | --- 880 | +++ 1320 | / | -+ 3300 | / | +++ 500 | +++ 13200 | / | / | +++ 100 | -- 8800 | / | + 1100 | + 3300 | + 3300 |
| Weapons | + 110 | +++ 660 | / | ++ 180 | / | - 1320 | / | / | / | / | +++ 13200 | - 330 | / | - 100 | +++ 8800 | / | / | / | / |

## 4 Goods information
| Name | Price | Stock max | Mass kg | Needs |
|---|---|---|---|---|
| Consumer Goods | 19.47 | 3300 | 0.34 | Radiation |
| Control Systems | 80404.72 | 3300 | 110.67 | – |
| D2O | 202.20 | 2000 | 105.00 | Climate |
| Electronics | 2464.72 | 130 | 12.10 | Radiation |
| Food | 151.40 | 1100 | 0.20 | Radiation + Climate |
| Furniture | 937.61 | 500 | 22.00 | – |
| Fusion Parts | 42481.12 | 2000 | 303.09 | Climate |
| He3 | 1391.40 | 2000 | 1.30 | Climate |
| Hull Parts | 130.77 | 3300 | 11.47 | – |
| HVAC | 4151.78 | 3300 | 29.89 | Radiation |
| Industrial Products | 9763.33 | 3300 | 56.14 | – |
| Intoxicants | 10.51 | 3300 | 0.13 | Radiation + Climate |
| Life Support Goods | 278.22 | 3300 | 50.18 | Radiation + Climate |
| Luxury Goods | 14809.72 | 3300 | 72.78 | Radiation + Climate |
| Media | 852.68 | 3300 | 2.66 | Radiation |
| Medical Items | – | – | – | – |
| Metals | 2.89 | 3300 | 1.00 | – |
| Ores | – | – | – | – |
| Plastics | 46.00 | 3300 | 0.30 | Climate |
| Science | 5000.00 | 1100 | 25.00 | Radiation + Climate |
| Sensor Components | 5450.50 | 3300 | 2.36 | Radiation |
| Space Suits | 6950.23 | 2000 | 29.10 | Radiation |
| Textiles | 5221.52 | 3300 | 0.38 | Radiation |
| Tools | 2540 | – | 19 | – |
| Trash | 0.08 | 3300 | 0.14 | – |
| Volatiles | 1000.00 | 3300 | 8.00 | Climate |
| Water | – | – | – | – |
| Weapons | 1545 | – | 0.81 | Radiation |
(The wiki's price column also shows a current change in %, e.g. Control Systems +78 %, omitted here.)

## 5 Trade routes (wiki examples)
- OKLG → Control Systems → VORB
- VORB → Industrial Products → OKLG
- SVIR → Luxury Goods → VORB
- EJDR → He3 → VORB

## 6 Tips
- Buy low, sell high. Consider travel costs: a long trip may burn more fuel than the profit.
