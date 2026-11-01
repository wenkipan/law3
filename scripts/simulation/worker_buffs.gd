extends RefCounted

# Timed effects refresh rather than stack. Conditions are derived from actual possessions
# and mood, so removing equipment cannot leave a stale bonus behind.
const ALE_HOURS := 4.0
const ALE_MOOD := 20.0
const ALE_RECOVERY := 20.0
const ALE_RATE := 0.8
const CLOTHES_MOOD := 15.0
const BATH_EFFECT_HOURS := 8.0
const BATH_MOOD := 15.0
const TOOL_RATE := 1.3
var timed: Dictionary = {}

func apply(id: String, seconds: float) -> void:
	timed[id] = maxf(0.0, seconds)

func remaining(id: String) -> float:
	return timed.get(id, 0.0)

func advance(seconds: float) -> void:
	for id in timed.keys():
		timed[id] -= seconds
		if timed[id] <= 0: timed.erase(id)

func mood_bonus(w: Dictionary) -> float:
	return (ALE_MOOD if remaining("tipsy") > 0 else 0.0) + clothes_mood(w) + (BATH_MOOD if remaining("bathed") > 0 else 0.0)

func clothes_mood(w: Dictionary) -> float:
	return CLOTHES_MOOD * clampf(w.clothes_cleanliness / 100.0, 0.0, 1.0) if w.equipment.get("clothes", 0) > 0 else 0.0

func carry_capacity(w: Dictionary) -> int:
	return 2 if w.backpack_uses > 0 else 1

func work_rate(g, w: Dictionary, activity: String, station: String) -> float:
	# Duty cycles represent wall-clock operation, not accelerated manufacturing.
	if station in g.GENERATOR_KINDS or station == "transformer": return 1.0
	var rate: float = w.mood.work_rate(mood_bonus(w))
	if remaining("tipsy") > 0: rate *= ALE_RATE
	if activity == "mine" and w.gun_uses > 0: rate *= g.GUN_MINING_RATE
	if activity == "produce" and g.tool_work(station) and w.equipment.get("tools", 0) > 0: rate *= TOOL_RATE
	return rate

func fatigue_factor(g, w: Dictionary) -> float:
	# A carried drink is consumed by the bounded overlay before labor starts.
	return 1.0 - g.WATER_FATIGUE_REDUCTION if remaining("hydrated") > 0 or w.water > 0 else 1.0

func display_effects(g, w: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if w.gun_uses > 0:
		result.append({"id": "gun", "item": "bench", "name": "矿枪",
			"description": "挖掘速度 +%.0f%%\n剩余耐久 %d 格" % [(g.GUN_MINING_RATE - 1) * 100, w.gun_uses]})
	if w.backpack_uses > 0:
		result.append({"id": "backpack", "item": "workbench", "name": "背包",
			"description": "携带方块 +1\n剩余耐久 %d 次" % w.backpack_uses})
	if remaining("hydrated") > 0:
		result.append({"id": "hydrated", "item": "clean_water", "name": "饮水",
			"description": "劳动疲劳增长 -%.0f%%\n剩余 %.1fh" % [g.WATER_FATIGUE_REDUCTION * 100, remaining("hydrated") / g.HOUR_SECONDS]})
	if remaining("tipsy") > 0:
		result.append({"id": "tipsy", "item": "ale", "name": "酒意",
			"description": "心情 +%.0f\n劳动效率 -%.0f%%\n剩余 %.1fh" % [ALE_MOOD, (1 - ALE_RATE) * 100, remaining("tipsy") / g.HOUR_SECONDS]})
	if w.equipment.get("clothes", 0) > 0:
		result.append({"id": "clothes", "item": "clothes", "name": "穿着衣物",
			"description": "清洁度 %.1f / 100\n心情 +%.1f\n剩余 %.1fh" % [w.clothes_cleanliness, clothes_mood(w), w.equipment.clothes / g.HOUR_SECONDS]})
	if remaining("bathed") > 0:
		result.append({"id": "bathed", "icon": "bath", "name": "沐浴",
			"description": "心情 +%.0f\n剩余 %.1fh" % [BATH_MOOD, remaining("bathed") / g.HOUR_SECONDS]})
	if w.equipment.get("tools", 0) > 0:
		result.append({"id": "tools", "item": "tools", "name": "铁工具",
			"description": "农田劳动/加工效率 +%.0f%%\n剩余耐久 %d 次劳动阶段" % [(TOOL_RATE - 1) * 100, w.equipment.tools]})
	if g.worker_special_items(w).has("loan"):
		result.append({"id": "loan", "item": "loan", "name": g.item_name("loan"),
			"description": "每笔劳动收入最多 %.0f%% 自动还款\n先还本金，再还利息\n还清前不能追加借款\n不购买清水、麦酒或清洁用品，不使用澡堂" % (g.LOAN_REPAYMENT_RATE * 100)})
	var mood_rate: float = w.mood.work_rate(mood_bonus(w))
	if not is_equal_approx(mood_rate, 1.0):
		result.append({"id": "mood", "icon": "mood-high" if mood_rate > 1 else "mood-low",
			"name": "心情高昂" if mood_rate > 1 else "心情低落",
			"description": "劳动效率 %+.1f%%" % ((mood_rate - 1) * 100)})
	return result
