extends "res://scripts/simulation/activities/activity.gd"

var mined := false
var shipment: Dictionary = {}

func enter(g, w: Dictionary, proposal) -> bool:
	if not super.enter(g, w, proposal):
		return false
	mined = option.data.get("mined", false)
	shipment = option.data.get("shipment", {})
	if shipment.is_empty():
		shipment = g.claim_delivery(w, option.data)
		if shipment.is_empty():
			return false
	if not g.shipments.has(shipment) or shipment.get("on_belt", false) or shipment.owner not in [-1, w.id]:
		return false
	shipment.owner = w.id
	if not mined:
		w.freight = shipment
	option.data.receiver = shipment.target
	phase = "transport" if shipment.picked else "pickup"
	return true

func valid(g, w: Dictionary) -> bool:
	return (not mined or w.carry > 0) and g.shipments.has(shipment) and not shipment.get("on_belt", false) and shipment.owner == w.id

func tick(g, w: Dictionary, delta: float) -> String:
	# Cancellation can redirect an in-flight shipment, never its physical contents.
	if phase != "pickup" and option.data.get("receiver", shipment.target) != shipment.target:
		if not transport_route(g, w):
			return "failure"
	if phase == "handoff":
		elapsed += delta
		if elapsed < (0.6 if mined else 0.0):
			return "running"
		if destination == shipment.target:
			if mined:
				g.take_carried_ore(w)
				w.ore_delivery = {}
			g.complete_delivery(shipment)
		elif not g.load_belt(w, shipment, destination):
			return "running" if transport_route(g, w, false) else "failure"
		if not mined:
			w.freight = {}
		return "success"
	var reached := navigate(g, w, delta)
	if reached < 0:
		return "failure"
	if reached == 0:
		return "running"
	if phase == "pickup":
		shipment.picked = true
		return "running" if transport_route(g, w) else "failure"
	phase = "handoff"
	elapsed = 0.0
	return "running"

func transport_route(g, w: Dictionary, use_belts := true) -> bool:
	var target: Vector2i = shipment.target
	var leg: Dictionary = g.delivery_route(Vector2i(w.pos.round()), target, use_belts)
	destination = leg.stop
	path = leg.path
	option.data.receiver = target
	phase = "transport"
	return not path.is_empty()

func exit(g, w: Dictionary, reason: String) -> void:
	if not mined and not shipment.is_empty() and not shipment.picked and shipment.owner == w.id:
		g.release_shipment(shipment)
		w.freight = {}
	# Picked cargo remains with its carrier across sleep and other interruptions.
	super.exit(g, w, reason)
