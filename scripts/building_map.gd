extends RefCounted

# Placement is authoritative; cell and origin lookup tables are derived indexes.
var placements: Dictionary = {}
var _cells: Dictionary = {}
var _origins: Dictionary = {}

func place(id: int, origin: Vector2i, cells: Array[Vector2i]) -> void:
	remove(id)
	placements[id] = {"origin": origin, "cells": cells.duplicate()}
	index_placement(id)

func remove(id: int) -> void:
	if not placements.has(id): return
	var placement: Dictionary = placements[id]
	for cell in placement.cells:
		_cells[cell].erase(id)
		if _cells[cell].is_empty(): _cells.erase(cell)
	_origins[placement.origin].erase(id)
	if _origins[placement.origin].is_empty(): _origins.erase(placement.origin)
	placements.erase(id)

func origin(id: int) -> Vector2i:
	return placements[id].origin

func at_origin(p: Vector2i) -> Array:
	return _origins.get(p, [])

func at_cell(p: Vector2i) -> Array:
	return _cells.get(p, [])

func rebuild() -> void:
	_cells.clear()
	_origins.clear()
	for id in placements: index_placement(id)

func clear() -> void:
	placements.clear()
	_cells.clear()
	_origins.clear()

func index_placement(id: int) -> void:
	var placement: Dictionary = placements[id]
	if not _origins.has(placement.origin): _origins[placement.origin] = []
	_origins[placement.origin].append(id)
	for cell in placement.cells:
		if not _cells.has(cell): _cells[cell] = []
		_cells[cell].append(id)
