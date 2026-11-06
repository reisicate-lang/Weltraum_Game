## Einfache Geräusche, im Code erzeugt (keine Sounddateien nötig):
## Alarm bei Gefahr, leises Signal bei Meldungen, Klicken beim Bauen.
extends Node

var _players: Array[AudioStreamPlayer] = []
var _sounds := {}
var _last_click := 0

func _ready() -> void:
	_sounds.alarm = _tone([880.0, 660.0, 880.0, 660.0], 0.12, 0.35)
	_sounds.info = _tone([660.0, 990.0], 0.07, 0.2)
	_sounds.click = _tone([220.0], 0.04, 0.25)
	for k in 4:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	EventBus.toast.connect(func(_t, kind): play("alarm" if kind == "bad" else "info"))
	EventBus.ship_changed.connect(func():
		if Time.get_ticks_msec() - _last_click > 150:
			_last_click = Time.get_ticks_msec()
			play("click"))

## Erzeugt einen kurzen Klang aus mehreren Tönen (16-Bit, Mono)
func _tone(freqs: Array, length: float, volume: float) -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	for f in freqs:
		var n := int(rate * length)
		for i in n:
			var env := minf(1.0, minf(i, n - i) / (rate * 0.01))
			var v := int(sin(TAU * f * i / rate) * volume * env * 32767.0)
			data.append(v & 0xFF)
			data.append((v >> 8) & 0xFF)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w

func play(name: String) -> void:
	if not _sounds.has(name):
		return
	for p in _players:
		if not p.playing:
			p.stream = _sounds[name]
			p.play()
			return
