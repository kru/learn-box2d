package box2d

import "core:fmt"
import "core:math"

import b2 "vendor:box2d"
import rl "vendor:raylib"


Entity :: struct {
	body_id:      b2.BodyId,
	shape_id:     b2.ShapeId,
	extent:       b2.Vec2,
	texture:      rl.Texture,
	texture_rect: rl.Rectangle,
}

destroy_entity :: proc(e: Entity) {
	b2.DestroyShape(e.shape_id, true)
	b2.DestroyBody(e.body_id)
}

draw_entity :: proc(e: Entity) {
	p := b2.Body_GetPosition(e.body_id)
	rec := rl.Rectangle{p.x, p.y, e.extent.x * 2, e.extent.y * 2}
	rotation := rl.RAD2DEG * b2.Rot_GetAngle(b2.Body_GetRotation(e.body_id))
	rl.DrawTexturePro(e.texture, e.texture_rect, rec, e.extent, rotation, {255, 255, 255, 255})
}

box_texture: rl.Texture
create_box :: proc(world_id: b2.WorldId, position: b2.Vec2, rotation: f32) -> Entity {
	box: Entity
	box.extent = b2.Vec2{16, 16}

	box_polygon := b2.MakeBox(box.extent.x, box.extent.y)
	box_body_def := b2.DefaultBodyDef()
	box_body_def.type = .dynamicBody
	box_body_def.position = position
	box_body_def.rotation = b2.MakeRot(rotation)

	box.body_id = b2.CreateBody(world_id, box_body_def)
	box_shape_def := b2.DefaultShapeDef()
	box_shape_def.material.restitution = 0.5
	box.shape_id = b2.CreatePolygonShape(box.body_id, box_shape_def, box_polygon)

	box.texture = box_texture
	box.texture_rect = {0, 0, f32(box_texture.width), f32(box_texture.height)}

	return box
}

ground_texture: rl.Texture
create_ground :: proc(world_id: b2.WorldId, position: b2.Vec2) -> Entity {
	ground: Entity
	ground.extent = b2.Vec2{2560, 32}

	ground_body_def := b2.DefaultBodyDef()
	ground_body_def.type = .staticBody
	ground_body_def.position = position

	ground.body_id = b2.CreateBody(world_id, ground_body_def)
	ground_shape_def := b2.DefaultShapeDef()
	ground_shape_def.material.friction = 1.0
	ground_polygon := b2.MakeBox(ground.extent.x, ground.extent.y)
	ground.shape_id = b2.CreatePolygonShape(ground.body_id, ground_shape_def, ground_polygon)
	ground.texture = ground_texture
	ground.texture_rect = {0, 0, ground.extent.x, ground.extent.y}

	return ground
}

main :: proc() {
	rl.InitWindow(2560, 1080, "Box2D Idea")
	defer rl.CloseWindow()

	rl.SetTargetFPS(144)

	box_texture = rl.LoadTexture("res/platformPack_tile047.png")
	defer rl.UnloadTexture(box_texture)
	ground_texture = rl.LoadTexture("res/platformPack_tile001.png")
	defer rl.UnloadTexture(ground_texture)

	LENGTH_UNITS_PER_METER :: 128
	b2.SetLengthUnitsPerMeter(LENGTH_UNITS_PER_METER)

	world_def := b2.DefaultWorldDef()

	world_def.gravity.y = LENGTH_UNITS_PER_METER * 9.80665
	world_id := b2.CreateWorld(world_def)
	defer b2.DestroyWorld(world_id)

	entities := make([dynamic]Entity)
	defer delete(entities)
	defer for e in entities {
		destroy_entity(e)
	}
	for i in 0 ..< 100 {
		x := f32(i)
		pos_x := 900 + 100 * math.mod(x, 8) + 50 * math.sin(x)
		pos_y := 10 + 200 * x / 8
		fmt.printfln("idx: %d, pos_x: %.2f, pos_y: %.2f", i, pos_x, pos_y)
		append(&entities, create_box(world_id, {pos_x, pos_y}, x))
	}

	ground := create_ground(world_id, {0, 1024 + 32 - 1})
	defer destroy_entity(ground)

	append(&entities, ground)

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		b2.World_Step(world_id, dt, 4)
		rl.BeginDrawing()
		rl.ClearBackground({128, 190, 255, 255})

		for e in entities {
			draw_entity(e)
		}

		draw_entity(ground)

		rl.EndDrawing()
	}
}
