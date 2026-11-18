## Residential status after Ostranauts "Residential Status": visas bought at an Embassy Services
## Kiosk, citizenship benefits and home ownership. Prices and requirements from the wiki, 1:1.
## The wiki's factions do not exist in this game; they are mapped to its stations (our choice):
##   Tycho = K-Leg (Ayotimiwa Ship Breaking Co.), Kármán Ring = Galilean Confederacy,
##   Habitat L4 = CCRE, Hephaistos = Xinhua (wiki: only an Investor visa).
## The player starts as an illegal occupant of K-Leg (wiki). Citizens get a discount on bulk
## trading (the wiki names no amount: 10 %) and may buy a home there for 5 000 000 Cr:
## unlimited power and a dedicated docking port (no docking fee) while docked there.
class_name Residency
extends RefCounted

const JURISDICTIONS := {
	"tycho": {"name": "K-Leg", "faction": "Ayotimiwa Ship Breaking Co.",
		"visas": {"investor": 5000000, "skilled": 750000},
		"skills": ["business", "civil", "construction", "spaceship"]},
	"karman": {"name": "Kármán Ring", "faction": "Galilean Confederacy",
		"visas": {"investor": 5000000, "skilled": 750000, "local": 500000, "national": 250000},
		"skills": ["civil", "electrical", "excavation"], "rep": "consortium"},
	"l4": {"name": "Habitat L4", "faction": "CCRE",
		"visas": {"investor": 5000000, "skilled": 750000, "local": 500000, "national": 250000},
		"skills": ["civil", "electrical", "excavation"], "rep": "syndicate"},
	"hephaistos": {"name": "Hephaistos", "faction": "Xinhua", "visas": {"investor": 5000000}},
}
const VISA_NAMES := {"investor": "Investor", "skilled": "Skilled Labor", "local": "Local Sponsored", "national": "National Service"}
## Local Sponsored: a friendly resident vouches for you – here: reputation with the station's faction
const LOCAL_REP := 50.0
const HOME_PRICE := 5000000
const CITIZEN_BULK := 0.1

static var visas := {}    ## station id -> visa id
static var homes := {}    ## station id -> true

static func reset() -> void:
	visas.clear()
	homes.clear()

static func to_data() -> Dictionary:
	return {"visas": visas, "homes": homes.keys()}

static func from_data(d: Dictionary) -> void:
	reset()
	var v: Dictionary = d.get("visas", {})
	for k in v:
		visas[String(k)] = String(v[k])
	for h in d.get("homes", []):
		homes[String(h)] = true

static func citizen(station: String) -> bool:
	return visas.has(station)

static func status_text() -> String:
	if visas.is_empty():
		return "Residential status: illegal occupant of K-Leg"
	var parts: PackedStringArray = []
	for s in visas:
		parts.append("%s (%s visa%s)" % [JURISDICTIONS[s].name, VISA_NAMES[visas[s]], ", home" if homes.has(s) else ""])
	return "Citizen of " + ", ".join(parts)

## The wiki: the K-Leg kiosk at K-Leg itself does not process applications
static func kiosk_processes(here: String, juris: String) -> bool:
	return not (here == "tycho" and juris == "tycho")

## Reason why this visa cannot be bought right now ("" = possible)
static func visa_reason(c: CrewMember, here: String, juris: String, visa: String) -> String:
	var j: Dictionary = JURISDICTIONS.get(juris, {})
	if j.is_empty() or not j.visas.has(visa):
		return "Not offered by this faction."
	if citizen(juris):
		return "You already hold a visa there."
	if not kiosk_processes(here, juris):
		return "This kiosk does not process K-Leg applications; apply at another station."
	match visa:
		"skilled":
			var ok := false
			for s in j.skills:
				ok = ok or SkillSystem.acquired(c, s)
			if not ok:
				var names: PackedStringArray = []
				for s in j.skills:
					names.append(SkillSystem.skill(s).skill_name)
				return "Needs one of: " + ", ".join(names)
		"local":
			if float(QuestSystem.reputation.get(String(j.rep), 0.0)) < LOCAL_REP:
				return "Needs a friendly resident to vouch for you (reputation %d with %s)." % [int(LOCAL_REP), QuestSystem.FACTIONS[j.rep].name]
		"national":
			return "Needs Operational Service in the Ceres warzone (not in this game)."
	if EconomySystem.credits < int(j.visas[visa]):
		return "Costs %d Cr." % int(j.visas[visa])
	return ""

static func buy_visa(c: CrewMember, juris: String, visa: String) -> bool:
	var here := String(PhysicsSystem.station().get("id", ""))
	var why := visa_reason(c, here, juris, visa)
	if why != "":
		GameState.toast(why, "bad")
		return false
	var cost := int(JURISDICTIONS[juris].visas[visa])
	EconomySystem.credits -= cost
	visas[juris] = visa
	EconomySystem.book("%s visa: %s" % [VISA_NAMES[visa], JURISDICTIONS[juris].name], -cost)
	GameState.toast("You are now a citizen of %s (%s visa)." % [JURISDICTIONS[juris].name, VISA_NAMES[visa]])
	return true

static func home_reason(here: String) -> String:
	if not JURISDICTIONS.has(here):
		return "There is no Real Estate Kiosk here."
	if homes.has(here):
		return "You already own a home here."
	if not citizen(here):
		return "Only citizens may buy a home here."
	if EconomySystem.credits < HOME_PRICE:
		return "Costs %d Cr." % HOME_PRICE
	return ""

static func buy_home() -> bool:
	var here := String(PhysicsSystem.station().get("id", ""))
	var why := home_reason(here)
	if why != "":
		GameState.toast(why, "bad")
		return false
	EconomySystem.credits -= HOME_PRICE
	homes[here] = true
	EconomySystem.book("Home bought: " + JURISDICTIONS[here].name, -HOME_PRICE)
	GameState.toast("Your home at %s: unlimited power and your own docking port while docked here." % JURISDICTIONS[here].name)
	return true

static func at_home() -> bool:
	return homes.has(PhysicsSystem.docked)

## Price factor on bulk trading at a station where you are a citizen
static func bulk_factor(station: String, selling: bool) -> float:
	if not citizen(station):
		return 1.0
	return 1.0 + CITIZEN_BULK if selling else 1.0 - CITIZEN_BULK
