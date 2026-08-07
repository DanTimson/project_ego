class_name TacticalCoordinateAdapter
extends RefCounted

const ROOT_THREE := 1.7320508075688772

var origin: Vector2 = Vector2.ZERO
var radius: float = 36.0


func _init(p_origin: Vector2 = Vector2.ZERO, p_radius: float = 36.0) -> void:
	origin = p_origin
	radius = p_radius


func cell_to_pixel(cell: Vector2i) -> Vector2:
	return origin + Vector2(
		radius * ROOT_THREE * (float(cell.x) + 0.5 * float(cell.y & 1)),
		radius * 1.5 * float(cell.y))


func cell_polygon(cell: Vector2i) -> PackedVector2Array:
	var points := PackedVector2Array()
	var centre := cell_to_pixel(cell)
	for corner in 6:
		var angle := deg_to_rad(60.0 * float(corner) - 30.0)
		points.append(centre + Vector2(cos(angle), sin(angle)) * (radius - 2.0))
	return points


func pixel_to_cell(pixel: Vector2, width: int, height: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for row in height:
		for col in width:
			var cell := Vector2i(col, row)
			var distance_squared := pixel.distance_squared_to(cell_to_pixel(cell))
			if distance_squared < best_distance:
				best_distance = distance_squared
				best = cell
	return best if best_distance <= radius * radius else Vector2i(-1, -1)
