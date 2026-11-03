extends RefCounted

# Common need scales and a bounded forecast, not activity/category priorities.
const FOOD_WEIGHT := 2.0
const FATIGUE_WEIGHT := 2.0
const MOOD_WEIGHT := 3.0
const POLLUTION_WEIGHT := 3.0
const CLOTHING_WEIGHT := 0.5
const FORECAST_HOURS := 8.0
const TIME_COST := 0.3
const TIME_VALUE := 0.3
const SUPPLY_VALUE := 0.6
const CAPACITY_VALUE := 0.5
const TASK_PROGRESS_VALUE := 0.15
const WALK_SPEED := 3.0
const MEAL_HUNGER := 70.0
const SLEEP_START := 0.2
const BORROW_FOOD_NEED := 0.7
const BORROW_FOOD_RESERVE := 10.0
const REVIEW_HOURS := 1.0
const INERTIA_BONUS := 0.15
const INERTIA_HOURS := 2.0
