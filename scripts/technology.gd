extends RefCounted

# Each point is a local material batch and paid labor, never a warehouse item.
const INITIAL_BUILDINGS := ["market", "mine", "logging_camp", "bed", "farm", "hunting_ground", "gathering_garden", "mill", "pump", "purifier", "storage_box", "research_bench", "wall", "fence", "door"]
const PROJECTS := {
	"oil_survey": {"name": "石油勘探", "points": 20, "hours": 2.0, "materials": {"iron": 1, 2: 1, 4: 1}, "unlocks": [], "reveals": "oil", "requires": ["chemistry", "mechanical_mining"], "position": Vector2i(4, 8)},
	"tools": {"name": "工具制造", "points": 8, "hours": 2.0, "materials": {2: 1, 4: 1}, "unlocks": ["bench", "workbench"], "requires": [], "position": Vector2i(0, 2)},
	"logistics": {"name": "基础物流", "points": 8, "hours": 1.0, "materials": {1: 1, 4: 1}, "unlocks": ["belt"], "requires": [], "position": Vector2i(0, 0)},
	"population": {"name": "人口", "points": 10, "hours": 2.0, "materials": {1: 2, 2: 1}, "unlocks": ["printer"], "requires": [], "position": Vector2i(1, 0)},
	"finance": {"name": "金融", "points": 12, "hours": 2.0, "materials": {2: 1, 4: 1}, "unlocks": ["bank"], "requires": ["population"], "position": Vector2i(2, 0)},
	"woodworking": {"name": "木材加工", "points": 8, "hours": 1.0, "materials": {7: 1, 4: 1}, "unlocks": ["sawmill"], "requires": ["tools"], "position": Vector2i(1, 1)},
	"metallurgy": {"name": "冶金", "points": 12, "hours": 2.0, "materials": {8: 1, 3: 1}, "unlocks": ["smelter"], "requires": ["tools"], "position": Vector2i(1, 3)},
	"iron_tools": {"name": "铁制工具", "points": 12, "hours": 2.0, "materials": {"iron": 1, "planks": 1}, "unlocks": ["smithy"], "requires": ["woodworking", "metallurgy"], "position": Vector2i(2, 2)},
	"textiles": {"name": "纺织", "points": 12, "hours": 2.0, "materials": {"planks": 1, "wheat": 2}, "unlocks": ["barn", "weaver", "tailor"], "requires": ["woodworking"], "position": Vector2i(2, 1)},
	"brewing": {"name": "酿造", "points": 10, "hours": 2.0, "materials": {"wheat": 2, "raw_water": 1}, "unlocks": ["brewery"], "requires": ["woodworking"], "position": Vector2i(2, 3)},
	"electricity": {"name": "基础电力", "points": 10, "hours": 2.0, "materials": {2: 2, 4: 1}, "unlocks": ["manual_generator", "low_line"], "requires": ["tools"], "position": Vector2i(1, 5)},
	"coal_power": {"name": "煤电与电网", "points": 20, "hours": 2.0, "materials": {2: 2, 3: 1, 4: 1}, "unlocks": ["power_plant", "high_line", "transformer"], "requires": ["electricity"], "position": Vector2i(2, 5)},
	"electric_farming": {"name": "电力农业", "points": 12, "hours": 2.0, "materials": {2: 1, "wheat": 2}, "unlocks": ["grow_light"], "requires": ["electricity"], "position": Vector2i(2, 4)},
	"environment": {"name": "环境", "points": 12, "hours": 2.0, "materials": {4: 1, "raw_water": 2}, "unlocks": ["canteen", "fountain"], "requires": ["electricity"], "position": Vector2i(2, 6)},
	"lighting": {"name": "灯光调控", "points": 12, "hours": 2.0, "materials": {2: 2, 4: 1}, "unlocks": ["spotlight", "daylight"], "requires": ["electricity"], "position": Vector2i(2, 7)},
	"electric_logistics": {"name": "电力物流", "points": 16, "hours": 2.0, "materials": {2: 1, 4: 1}, "unlocks": ["electric_belt"], "requires": ["logistics", "electricity"], "position": Vector2i(3, 6)},
	"mechanical_mining": {"name": "机械采矿", "points": 20, "hours": 2.0, "materials": {"iron": 1, 2: 1, 4: 1}, "unlocks": ["drill"], "requires": ["metallurgy", "coal_power"], "position": Vector2i(3, 5)},
	"chemistry": {"name": "基础化工", "points": 16, "hours": 2.0, "materials": {3: 1, "raw_water": 2, "iron": 1}, "unlocks": ["chemical_plant"], "requires": ["metallurgy"], "position": Vector2i(2, 8)},
	"hygiene": {"name": "清洁卫生", "points": 16, "hours": 2.0, "materials": {"chemicals": 1, "clean_water": 1, "planks": 1}, "unlocks": ["soapworks", "bathhouse", "laundry"], "requires": ["chemistry", "woodworking"], "position": Vector2i(3, 8)},
	"medicine": {"name": "医疗", "points": 20, "hours": 2.0, "materials": {"chemicals": 1, "cloth": 1, "clean_water": 1}, "unlocks": ["pharmacy", "hospital"], "requires": ["chemistry", "textiles"], "position": Vector2i(3, 2)},
}

static func completed(progress: Dictionary, project: String) -> bool:
	return PROJECTS.has(project) and progress.get(project, 0) >= PROJECTS[project].points

static func available(progress: Dictionary, project: String) -> bool:
	if not PROJECTS.has(project) or completed(progress, project): return false
	for required in PROJECTS[project].requires:
		if not completed(progress, required): return false
	return true

static func building_unlocked(progress: Dictionary, kind: String) -> bool:
	if kind in INITIAL_BUILDINGS: return true
	for project in PROJECTS:
		if kind in PROJECTS[project].unlocks: return completed(progress, project)
	return false
