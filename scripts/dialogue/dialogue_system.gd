## Gespräche und Tätigkeiten auf den Stationen. Geschichten kommen über
## Menschen: Kontakte antworten in kurzen Sätzen, nicht in Textbildschirmen.
## Jede Option braucht passende Fähigkeiten (Etikette, Überzeugen ...) oder Hobbys.
extends Node

const CONTACTS := {
	"tycho": {"name": "Gus, Schrotthändler", "style": "folk", "talk": "talk_folk"},
	"karman": {"name": "Aurel Lindqvist, Bankier", "style": "oligarch_et", "talk": "talk_oligarch"},
	"l4": {"name": "Vex, Schieberin", "style": "street", "talk": "talk_street"},
}

var claim_discount := false
var rate_lowered := false

func reset() -> void:
	claim_discount = false
	rate_lowered = false

func speaker() -> CrewMember:
	return EconomySystem.trader()

## Optionen an der aktuellen Station: [{id, text, ok, why}]
func options() -> Array:
	var st := PhysicsSystem.station()
	if st.is_empty():
		return []
	var c := speaker()
	var out: Array = []
	var con: Dictionary = CONTACTS.get(st.id, {})
	if not con.is_empty():
		var lvl := SkillSystem.progress(c, con.style)
		var unlock := HobbySystem.unlocks(c, con.talk) or c.contacts.any(func(x): return con.name.split(",")[0] in x)
		out.append({"id": "chat", "text": "Mit %s plaudern" % con.name, "ok": true, "why": ""})
		match st.id:
			"tycho":
				out.append({"id": "tip", "text": "Gus nach einem lohnenden Wrack fragen", "ok": (lvl >= 30.0 or unlock) and not claim_discount, "why": "Volksetikette 30 % oder Hobby Geschichte"})
			"karman":
				out.append({"id": "rate", "text": "Mit Lindqvist über die Kreditrate reden", "ok": lvl >= 40.0 and not rate_lowered, "why": "Oberschicht-Etikette 40 %"})
			"l4":
				out.append({"id": "smuggle", "text": "Vex nach Schmuggelware fragen (2 Kisten, 100 Cr)", "ok": lvl >= 30.0 or unlock, "why": "Straßenetikette 30 %, Hobby Kartenspiel oder Kontakt Vex"})
	out.append({"id": "deal", "text": "Bessere Preise für heute aushandeln", "ok": true, "why": ""})
	out.append({"id": "song", "text": "In der Bar singen (2 Stunden)", "ok": true, "why": ""})
	out.append({"id": "dance", "text": "In der Bar tanzen (2 Stunden)", "ok": true, "why": ""})
	out.append({"id": "acting", "text": "In der Bar ein Stück spielen (2 Stunden)", "ok": true, "why": ""})
	out.append({"id": "gamble", "text": "Würfeln um 50 Cr", "ok": EconomySystem.credits >= 50, "why": "50 Cr nötig"})
	return out

## Option ausführen. Gibt die Antwort (Dialogzeile) zurück.
func choose(id: String) -> String:
	var st := PhysicsSystem.station()
	var c := speaker()
	var con: Dictionary = CONTACTS.get(st.get("id", ""), {})
	var social := TraitSystem.factor(c, "social")
	match id:
		"chat":
			SkillSystem.train(c, con.talk, 10.0 * social)
			c.stress = maxf(0.0, c.stress - 5.0)
			return {"tycho": "Gus: „Das Trümmerfeld spuckt immer noch Kriegsschrott aus. Pass auf Plünderer auf.“",
				"karman": "Lindqvist: „Pünktliche Raten, und wir bleiben Freunde.“",
				"l4": "Vex: „Hier fragt keiner nach Papieren. Solange du nicht fragst, wer ich bin.“"}.get(st.id, "")
		"tip":
			SkillSystem.train(c, "talk_folk", 15.0)
			claim_discount = true
			return "Gus: „Für dich? Das nächste Bergungsrecht kriegst du zum halben Preis.“"
		"rate":
			SkillSystem.train(c, "talk_oligarch", 15.0)
			SkillSystem.train(c, "negotiate", 10.0)
			var chance := 0.3 + SkillSystem.effect(c, "negotiate") + SkillSystem.effect(c, "talk_oligarch") * 0.3
			if SkillSystem.mastered(c, "oligarch_et") or randf() < chance * social:
				rate_lowered = true
				EconomySystem.payment_factor = 0.85 if not SkillSystem.mastered(c, "oligarch_et") else 0.7
				return "Lindqvist: „Nun gut. Ab jetzt eine kleinere Rate. Enttäuschen Sie mich nicht.“"
			return "Lindqvist: „Ich fürchte, da kann ich nichts machen.“"
		"smuggle":
			if EconomySystem.credits < 100 or EconomySystem.terminal() == null:
				return "Vex: „Komm wieder, wenn du flüssig bist.“"
			EconomySystem.credits -= 100
			EconomySystem.book("Schmuggelware von Vex", -100)
			EconomySystem.terminal().inv.add("contraband", 2, 90.0)
			SkillSystem.train(c, "talk_street", 10.0)
			return "Vex: „Zwei Kisten, liegen im Terminal. Verkauf sie hier auf L4, woanders kontrollieren sie.“"
		"deal":
			SkillSystem.train(c, "negotiate", 10.0)
			var bonus := 0.03 + SkillSystem.effect(c, "negotiate") * 0.2 * social
			EconomySystem.deal_bonus = bonus
			EconomySystem.deal_until = (floorf(GameState.time / 1440.0) + 1.0) * 1440.0
			return "%s handelt %d %% bessere Preise für heute aus." % [c.display_name, int(bonus * 100.0)]
		"song", "dance", "acting":
			var skill_id := {"song": "song", "dance": "dance", "acting": "acting"}[id] as String
			var income := int((15.0 + 120.0 * SkillSystem.effect(c, "perform_income") * randf_range(0.6, 1.2)) * (2.0 if id == "dance" and SkillSystem.mastered(c, "dance") else 1.0))
			EconomySystem.credits += income
			EconomySystem.book("Gage in der Bar", income)
			SkillSystem.train(c, {"song": "perform_song", "dance": "perform_dance", "acting": "perform_acting"}[id], 120.0)
			c.away_until = GameState.time + 120.0
			c.stress = maxf(0.0, c.stress - SkillSystem.effect(c, "stress_relief") * 20.0)
			return "%s tritt auf (%s) und bekommt %d Cr Gage." % [c.display_name, SkillSystem.skill(skill_id).skill_name, income]
		"gamble":
			EconomySystem.credits -= 50
			SkillSystem.train(c, "gamble", 20.0)
			var win := randf() < 0.42 + SkillSystem.effect(c, "gamble_edge")
			if win:
				EconomySystem.credits += 100
				EconomySystem.book("Würfelgewinn", 50)
				return "%s gewinnt beim Würfeln 50 Cr." % c.display_name
			EconomySystem.book("Würfelverlust", -50)
			return "%s verliert 50 Cr beim Würfeln." % c.display_name
	return ""

## Schmuggelware verkaufen: Kontrolle möglich (Heimlichkeit, Schauspiel helfen)
func smuggle_check(c: CrewMember) -> bool:
	var st := PhysicsSystem.station()
	var risk := 0.15 if st.get("black", false) else 0.45
	risk *= 1.0 - minf(0.9, SkillSystem.effect(c, "smuggle") + SkillSystem.effect(c, "bluff") * 0.5)
	if SkillSystem.mastered(c, "stealth"):
		risk *= 0.1
	SkillSystem.train(c, "smuggle", 10.0)
	SkillSystem.train(c, "bluff", 5.0)
	return randf() >= risk

## Psychologie: Gespräch mit einem Crewmitglied senkt dessen Stress
func counsel(counselor: CrewMember, target: CrewMember) -> String:
	var amount := 8.0 + SkillSystem.effect(counselor, "counsel") * 40.0
	if SkillSystem.mastered(counselor, "psychology"):
		amount += 20.0
	target.stress = maxf(0.0, target.stress - amount)
	SkillSystem.train(counselor, "counsel", 15.0)
	SkillSystem.train(counselor, "calm", 5.0)
	return "%s spricht mit %s. Stress −%d." % [counselor.display_name, target.display_name, int(amount)]
