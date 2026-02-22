package box2d


import b2 "vendor:box2d"
import rl "vendor:raylib"

// Enums
Entity_Type :: enum u32 {
	None = 0,
	Ground,
	Bird,
	Target,
}

// Structs
Entity :: struct {
	body_id:  b2.BodyId,
	shape_id: b2.ShapeId,
	extent:   b2.Vec2,
	kind:     Entity_Type,
	color:    rl.Color, // Fallback
	texture:  rl.Texture2D,
	has_tex:  bool,
}

Game_State :: struct {
	entities:     [256]Entity,
	entity_count: u32,
	world_id:     b2.WorldId,

	// Slingshot state
	is_dragging:  bool,
	drag_start:   rl.Vector2,
	bird_index:   u32, // The index of the bird in the entities array

	// Loaded textures
	tex_box:      rl.Texture2D,
	tex_ground:   rl.Texture2D,
	tex_wall:     rl.Texture2D,
}

// Helpers
add_entity :: proc(state: ^Game_State, entity: Entity) -> u32 {
	assert(state != nil)
	assert(state.entity_count < len(state.entities), "Entity limit reached")

	idx := state.entity_count
	state.entities[idx] = entity
	state.entity_count += 1
	return idx
}

create_box :: proc(
	world_id: b2.WorldId,
	position: b2.Vec2,
	rotation: f32,
	extent: b2.Vec2,
	kind: Entity_Type,
	color: rl.Color,
	is_dynamic: bool,
	texture: rl.Texture2D,
	has_tex: bool,
	density: f32,
) -> Entity {
	box: Entity
	box.extent = extent
	box.kind = kind
	box.color = color
	box.texture = texture
	box.has_tex = has_tex

	box_polygon := b2.MakeBox(extent.x, extent.y)
	box_body_def := b2.DefaultBodyDef()
	if is_dynamic {
		box_body_def.type = .dynamicBody
	} else {
		box_body_def.type = .staticBody
	}
	box_body_def.position = position
	box_body_def.rotation = b2.MakeRot(rotation)

	box.body_id = b2.CreateBody(world_id, box_body_def)
	box_shape_def := b2.DefaultShapeDef()
	box_shape_def.material.restitution = 0.5
	box_shape_def.material.friction = 0.3
	box_shape_def.density = density

	box.shape_id = b2.CreatePolygonShape(box.body_id, box_shape_def, box_polygon)

	return box
}

init_game :: proc(state: ^Game_State) {
	assert(state != nil)

	LENGTH_UNITS_PER_METER :: 64
	b2.SetLengthUnitsPerMeter(LENGTH_UNITS_PER_METER)

	world_def := b2.DefaultWorldDef()
	world_def.gravity.y = LENGTH_UNITS_PER_METER * 9.80665
	state.world_id = b2.CreateWorld(world_def)

	// Load textures
	state.tex_box = rl.LoadTexture("res/platformPack_tile047.png")
	state.tex_ground = rl.LoadTexture("res/platformPack_tile001.png")
	state.tex_wall = rl.LoadTexture("res/platformPack_tile040.png")

	reset_game(state)
}

reset_game :: proc(state: ^Game_State) {
	assert(state != nil)

	// Clean up old entities if they exist
	for i: u32 = 0; i < state.entity_count; i += 1 {
		b2.DestroyShape(state.entities[i].shape_id, true)
		b2.DestroyBody(state.entities[i].body_id)
	}
	state.entity_count = 0
	state.is_dragging = false

	// Create ground
	ground_extent := b2.Vec2{1000, 32} // Large enough
	ground_pos := b2.Vec2{1000, 800 - 32} // Assuming 1280x800 window
	ground := create_box(
		state.world_id,
		ground_pos,
		0,
		ground_extent,
		.Ground,
		rl.DARKGREEN,
		false,
		state.tex_ground,
		true,
		1.0,
	)
	add_entity(state, ground)

	// Create a small wall to force arc shots
	wall_extent := b2.Vec2{32, 128}
	wall_pos := b2.Vec2{500, 800 - 32 - 16 - 64} // Positioned between bird and targets
	wall := create_box(
		state.world_id,
		wall_pos,
		0,
		wall_extent,
		.Ground,
		rl.DARKGRAY,
		false,
		state.tex_wall,
		true,
		1.0,
	)
	add_entity(state, wall)

	// Create target "pyramid" structure
	box_extent := b2.Vec2{16, 16}
	start_x: f32 = 1050
	start_y: f32 = 800 - 64 - 16

	rows: u32 = 5
	for row_idx: u32 = 0; row_idx < rows; row_idx += 1 {
		cols := rows - row_idx
		for col_idx: u32 = 0; col_idx < cols; col_idx += 1 {
			offset_x := f32(col_idx) * (box_extent.x * 2.1) + f32(row_idx) * box_extent.x
			pos_x := start_x + offset_x
			pos_y := start_y - f32(row_idx) * (box_extent.y * 2.1)

			box := create_box(
				state.world_id,
				{pos_x, pos_y},
				0,
				box_extent,
				.Target,
				rl.WHITE,
				true,
				state.tex_box,
				true,
				0.2, // Fragile blocks
			)
			add_entity(state, box)
		}
	}

	// Create bird launch pad
	pad_extent := b2.Vec2{32, 64}
	pad_pos := b2.Vec2{150, 800 - 48 - 64} // Positioned on ground
	pad := create_box(
		state.world_id,
		pad_pos,
		0,
		pad_extent,
		.Ground, // Treat as ground collision
		rl.DARKBROWN,
		true,
		rl.LoadTexture("res/platformPack_tile041.png"),
		true,
		1.0,
	)
	add_entity(state, pad)

	// Create bird
	bird_extent := b2.Vec2{16, 16}
	bird_offset_y: f32 = 800 - 32 - 128 - 16 // Ground = 32, Pad = 128 (64*2), Bird = 16
	bird_pos := b2.Vec2{150, bird_offset_y}
	bird := create_box(
		state.world_id,
		bird_pos,
		0,
		bird_extent,
		.Bird,
		rl.RED,
		true,
		rl.LoadTexture("res/platformPack_tile024.png"),
		true,
		2.0, // Heavy bird
	)

	// Fast indexing for bird
	state.bird_index = add_entity(state, bird)
}

deinit_game :: proc(state: ^Game_State) {
	assert(state != nil)

	for i: u32 = 0; i < state.entity_count; i += 1 {
		b2.DestroyShape(state.entities[i].shape_id, true)
		b2.DestroyBody(state.entities[i].body_id)
	}

	rl.UnloadTexture(state.tex_box)
	rl.UnloadTexture(state.tex_ground)
	rl.UnloadTexture(state.tex_wall)

	b2.DestroyWorld(state.world_id)
}

update_physics :: proc(state: ^Game_State, dt: f32) {
	assert(state != nil)
	b2.World_Step(state.world_id, dt, 4)
}

handle_input :: proc(state: ^Game_State) {
	assert(state != nil)

	mouse_pos := rl.GetMousePosition()
	bird_entity := state.entities[state.bird_index]
	bird_pos := b2.Body_GetPosition(bird_entity.body_id)

	bird_screen_pos := rl.Vector2{bird_pos.x, bird_pos.y}

	if rl.IsMouseButtonPressed(.LEFT) {
		// Check if clicked near bird
		dist := rl.Vector2Distance(mouse_pos, bird_screen_pos)
		if dist < 60.0 { 	// Increased hit area
			state.is_dragging = true
			state.drag_start = bird_screen_pos // Anchor to the bird rather than initial click
		}
	} else if rl.IsMouseButtonReleased(.LEFT) {
		if state.is_dragging {
			state.is_dragging = false

			// Calculate impulse (vector from pull to bird start)
			drag_vector := state.drag_start - mouse_pos

			// Cap the drag length visually and mechanically
			max_drag_len: f32 = 150.0
			drag_len := rl.Vector2Length(drag_vector)
			if drag_len > max_drag_len {
				drag_vector = rl.Vector2Normalize(drag_vector) * max_drag_len
			}

			// Wake up the body explicitly
			b2.Body_SetAwake(bird_entity.body_id, true)

			mass := b2.Body_GetMass(bird_entity.body_id)
			// Apply a massive impulse scaled to the drag vector, factoring in the mass (reduce multiplier to make it arc and slower)
			impulse_scale: f32 = mass * 7.5
			impulse := b2.Vec2{drag_vector.x * impulse_scale, drag_vector.y * impulse_scale}
			b2.Body_ApplyLinearImpulseToCenter(bird_entity.body_id, impulse, true)
		}
	}

	// Reset logic
	if rl.IsKeyPressed(.R) {
		reset_game(state)
	}

	btn_rect := rl.Rectangle{10, 50, 100, 30}
	if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse_pos, btn_rect) {
		reset_game(state)
	}
}

draw_entity :: proc(e: Entity) {
	p := b2.Body_GetPosition(e.body_id)
	rec := rl.Rectangle{p.x, p.y, e.extent.x * 2.0, e.extent.y * 2.0}

	rotation := rl.RAD2DEG * b2.Rot_GetAngle(b2.Body_GetRotation(e.body_id))
	origin := rl.Vector2{e.extent.x, e.extent.y}

	if e.has_tex {
		source_rect := rl.Rectangle{0, 0, f32(e.texture.width), f32(e.texture.height)}
		// Handle the texture repeating if the extent is larger, typical for ground
		if e.kind == .Ground {
			source_rect.width = e.extent.x * 2.0
			source_rect.height = e.extent.y * 2.0
		}

		rl.DrawTexturePro(e.texture, source_rect, rec, origin, rotation, rl.WHITE)
	} else {
		rl.DrawRectanglePro(rec, origin, rotation, e.color)
	}

	// Draw outline for clarity
	rl.DrawRectanglePro(rec, origin, rotation, rl.Fade(rl.BLACK, 0.3)) // Optional, for visual clarity.
}

draw_game :: proc(state: ^Game_State) {
	assert(state != nil)

	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(rl.SKYBLUE)

	for i: u32 = 0; i < state.entity_count; i += 1 {
		draw_entity(state.entities[i])
	}

	// Draw slingshot aiming line and trajectory
	if state.is_dragging {
		mouse_pos := rl.GetMousePosition()
		rl.DrawLineEx(mouse_pos, state.drag_start, 4.0, rl.DARKGRAY)

		// Calculate the impulse for trajectory visualization
		drag_vector := state.drag_start - mouse_pos
		max_drag_len: f32 = 150.0
		drag_len := rl.Vector2Length(drag_vector)
		if drag_len > max_drag_len {
			drag_vector = rl.Vector2Normalize(drag_vector) * max_drag_len
		}

		bird_entity := state.entities[state.bird_index]
		mass := b2.Body_GetMass(bird_entity.body_id)
		impulse_scale: f32 = mass * 7.5
		impulse := b2.Vec2{drag_vector.x * impulse_scale, drag_vector.y * impulse_scale}

		// Initial velocity = impulse / mass
		velocity := rl.Vector2{impulse.x / mass, impulse.y / mass}

		// Draw arc
		points_to_draw: u32 = 60
		dt: f32 = 1.0 / 60.0 // Assuming 60 fps

		// Gravity affects velocity every frame
		gravity_str := b2.World_GetGravity(state.world_id)
		gravity := rl.Vector2{gravity_str.x, gravity_str.y}

		current_pos := state.drag_start

		for i: u32 = 0; i < points_to_draw; i += 1 {
			next_pos := rl.Vector2 {
				current_pos.x + velocity.x * dt,
				current_pos.y + velocity.y * dt,
			}

			// Every few points draw a dot
			if i % 4 == 0 {
				rl.DrawCircleV(next_pos, 4.0, rl.Fade(rl.WHITE, 0.7))
			}

			current_pos = next_pos
			velocity.x += gravity.x * dt
			velocity.y += gravity.y * dt
		}
	}

	btn_rect := rl.Rectangle{10, 50, 100, 30}
	rl.DrawRectangleRec(btn_rect, rl.LIGHTGRAY)
	rl.DrawText("Reset [R]", 15, 55, 20, rl.DARKGRAY)

	rl.DrawText("Drag the box backward to launch!", 10, 10, 20, rl.DARKGRAY)
}

main :: proc() {
	width: i32 = 1280
	height: i32 = 800

	rl.InitWindow(width, height, "Box Collider - Box2D")
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)

	state: Game_State
	init_game(&state)
	defer deinit_game(&state)

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		handle_input(&state)
		update_physics(&state, dt)
		draw_game(&state)
	}
}
