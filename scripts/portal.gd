extends RefCounted

const BREAD_PER_BLOCK := 1
var input_blocks: Dictionary = {}
var output_bread := 0
var lent_bread := 0.0
var repaid_principal := 0.0

func lend(amount: float) -> float:
	lent_bread += amount
	return amount

func exchange(ore: int) -> int:
	if ore <= 0:
		return 0
	input_blocks[ore] = input_blocks.get(ore, 0) + 1
	output_bread += BREAD_PER_BLOCK
	return BREAD_PER_BLOCK
