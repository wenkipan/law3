extends RefCounted

var items: Dictionary = {}
var wastewater_load := 0.0

func quantity(item) -> float:
	return items.get(item, 0.0)

func contents() -> Dictionary:
	return items.duplicate()

func is_empty() -> bool:
	return wastewater_load <= 0 and items.values().all(func(amount): return amount <= 0)

func add(item, amount: float) -> void:
	items[item] = maxf(0.0, quantity(item) + amount)

func take(item, amount: float) -> Dictionary:
	amount = minf(maxf(0.0, amount), quantity(item))
	if amount <= 0: return {}
	var pollution := take_waste(amount, quantity(item)) if is_same(item, "wastewater") else 0.0
	add(item, -amount)
	return {"item": item, "amount": amount, "pollution": pollution}

func put(goods: Dictionary) -> void:
	add(goods.item, goods.amount)
	if is_same(goods.item, "wastewater"): wastewater_load += goods.get("pollution", 0.0)

func take_waste(amount: float, stock: float) -> float:
	var load := wastewater_load * clampf(amount / stock, 0, 1) if stock > 0 else 0.0
	wastewater_load = maxf(0.0, wastewater_load - load)
	return load

func transfer_to(other: RefCounted) -> void:
	if is_same(self, other): return
	for item in items:
		other.add(item, items[item])
	other.wastewater_load += wastewater_load
	items.clear()
	wastewater_load = 0.0
