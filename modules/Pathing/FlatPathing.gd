class_name FlatPathing

## Flat-index reachability for the observation path. Works directly on cell
## indices (no Field objects) so it is ~orders of magnitude cheaper than the
## object-based Pathing.dijkstra. All movement costs are 1 (TerrainField), so
## Dijkstra collapses to BFS.
##
## Topology is static during an episode except when the Dock completes, which
## flips GameData.builders_walk_on_water and makes WATER cells walkable. Callers
## must rebuild the neighbor table (and invalidate any caches) when that flag
## changes.

static func build_neighbor_table(grid: TerrainFieldGrid, walk_on_water: bool) -> Array[PackedInt32Array]:
	var columns: int = grid.columns
	var rows: int = grid.rows
	var table: Array[PackedInt32Array] = []
	table.resize(columns * rows)
	for cell_flat in range(columns * rows):
		var pos := Vector2i(cell_flat % columns, cell_flat / columns)
		var neighbors := PackedInt32Array()
		for dir in TerrainFieldGrid.EVEN_R_DIRECTIONS if (pos.y & 1) == 0 else TerrainFieldGrid.ODD_R_DIRECTIONS:
			var neighbor := grid.get_field_at(pos + dir)
			if neighbor == null:
				continue
			if _is_reachable(neighbor, walk_on_water):
				neighbors.append(neighbor.grid_position.x + columns * neighbor.grid_position.y)
		table[cell_flat] = neighbors
	return table

static func bfs_mask(start_flat: int, neighbors: Array[PackedInt32Array], n_cells: int = 192) -> PackedByteArray:
	var visited := PackedByteArray()
	visited.resize(n_cells)
	visited[start_flat] = 1
	var queue: Array[int] = [start_flat]
	var head := 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		for next_flat in neighbors[current]:
			if visited[next_flat] == 0:
				visited[next_flat] = 1
				queue.append(next_flat)
	return visited

static func _is_reachable(field: TerrainField, walk_on_water: bool) -> bool:
	if field.walkable:
		return true
	return walk_on_water and field.terrain_type == Terrain.TerrainType.WATER
