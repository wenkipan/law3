extends RefCounted

# Rules use game hours; the simulation supplies actual experiences, not scene nodes.
const LIMIT := 100.0
const RECOVERY_PER_HOUR := 1.5
const BED_GAIN_PER_HOUR := 6.0
const COMFORTABLE_MEAL_GAIN := 18.0
const NOISY_SLEEP_LOSS_PER_HOUR := 8.0
const NOISY_MEAL_LOSS := 12.0
const MACHINE_NOISE := {
	"power_plant": {"radius": 3, "strength": 1.0},
	"drill": {"radius": 3, "strength": 1.0},
	"electric_belt": {"radius": 1, "strength": 0.4},
}
const WORK_STRESS := {"power_plant": 9.0, "transformer": 6.0, "drill": 9.0}
const EFFICIENCY_THRESHOLD := 10.0
const MAX_EFFICIENCY_CHANGE := 0.15
const SHOP_ENTER := 25.0
const SHOP_EXIT := 15.0
const LOW_SHOP_ENTER := -25.0
const LOW_SHOP_EXIT := -15.0
const AVOID_ENTER := -45.0
const AVOID_EXIT := -20.0
const AVOID_AFTER_HOURS := 2.0

var value := 0.0
var low_hours := 0.0
var avoids_machines := false
var shopping := 0

func advance(hours: float) -> void:
	value = move_toward(value, 0.0, RECOVERY_PER_HOUR * hours)
	if value <= AVOID_ENTER:
		low_hours += hours
		if low_hours >= AVOID_AFTER_HOURS:
			avoids_machines = true
	else:
		low_hours = 0.0
	if value >= AVOID_EXIT:
		avoids_machines = false
	if shopping > 0 and value < SHOP_EXIT:
		shopping = 0
	elif shopping < 0 and value > LOW_SHOP_EXIT:
		shopping = 0
	if value >= SHOP_ENTER:
		shopping = 1
	elif value <= LOW_SHOP_ENTER:
		shopping = -1

func experience(amount: float) -> void:
	value = clampf(value + amount, -LIMIT, LIMIT)

func worked(kind: String, hours: float) -> void:
	experience(-WORK_STRESS.get(kind, 0.0) * hours)

func slept(hours: float, bed_hours: float, noise: float) -> void:
	experience(BED_GAIN_PER_HOUR * bed_hours - NOISY_SLEEP_LOSS_PER_HOUR * noise * hours)

func ate_meal(meal_fraction: float, comfortable: bool, noise: float) -> void:
	var comfort := COMFORTABLE_MEAL_GAIN if comfortable else 0.0
	experience((comfort - NOISY_MEAL_LOSS * noise) * meal_fraction)

func accepts_work(kind: String) -> bool:
	return not avoids_machines or not WORK_STRESS.has(kind)

func work_rate() -> float:
	var strength := maxf(0.0, absf(value) - EFFICIENCY_THRESHOLD) / (LIMIT - EFFICIENCY_THRESHOLD)
	return 1.0 + signf(value) * minf(1.0, strength) * MAX_EFFICIENCY_CHANGE

func water_limit(capacity: int) -> int:
	return 1 if shopping < 0 else capacity
