@tool
extends Node

## Captures the active editor viewport, composites a property panel below it,
## and saves the result to res://screenshots/.

const LINE_H        := 36   # pixels reserved per property row (accommodates 1-2 wrapped lines)
const HEADER_H      := 26   # pixels for the node-name header row
const CAT_H         := 20   # pixels for a class-category label
const GROUP_H       := 16   # pixels for an inline group/subgroup header label
const PADDING       := 8    # inner margin inside each column
const NODES_PER_ROW := 5    # fixed number of node columns per panel row


## Main entry point.  Returns the path the PNG was saved to, or "" on error.
func capture(
		selection: Dictionary,
		scene_root: Node,
		export_txt: bool,
		screen: String) -> String:

	# --- 1. Grab the viewport image ---
	var vp_image: Image = await _get_viewport_image(screen)
	if vp_image == null:
		push_error("AnnotatedScreenshot: Could not capture the '%s' viewport." % screen)
		return ""

	var vp_w := vp_image.get_width()
	var vp_h := vp_image.get_height()

	# --- 2. Resolve node paths → property data ---
	var node_data: Array[Dictionary] = []
	for raw_path in selection:
		var node_path := raw_path as NodePath
		var node := _resolve_node(scene_root, node_path)
		if node == null:
			push_warning("AnnotatedScreenshot: Node not found: " + str(node_path))
			continue
		var entry := {"name": str(node.name), "props": []}

		# Build a fast lookup of which direct props and resource sub-props are selected.
		var sel_direct := {}
		var sel_res: Dictionary = {}  # res_pname -> { sub_pname: true }
		for prop_path: String in selection[raw_path]:
			var slash := prop_path.find("/")
			if slash != -1:
				var rp := prop_path.substr(0, slash)
				var sp := prop_path.substr(slash + 1)
				if not sel_res.has(rp):
					sel_res[rp] = {}
				sel_res[rp][sp] = true
			else:
				sel_direct[prop_path] = true

		# Walk properties in Inspector order (most-derived class first).
		for e in _collect_ordered_props(node):
			var pname: String = e["pname"]

			if sel_direct.has(pname):
				var val = node.get(pname)
				entry["props"].append({
					"label": _friendly_prop_name(_strip_group_prefix(pname, e["prefix"])),
					"value": _format_enum_value(e["prop_info"], val),
					"group": e["group_label"],
					"category": e["category"],
				})

			elif sel_res.has(pname):
				# Resource container — walk its own ordered props.
				var resource = node.get(pname)
				if not resource is Resource:
					continue
				var sub_sel: Dictionary = sel_res[pname]
				for re in _collect_ordered_props(resource):
					if sub_sel.has(re["pname"]):
						var sub_pname: String = re["pname"]
						var group_label = pname if re["group_label"].is_empty() \
								else pname + " / " + re["group_label"]
						entry["props"].append({
							"label": _friendly_prop_name(_strip_group_prefix(sub_pname, re["prefix"])),
							"value": _format_enum_value(re["prop_info"], resource.get(sub_pname)),
							"group": group_label,
							"category": re["category"] if not re["category"].is_empty() else pname,
						})
		node_data.append(entry)

	if node_data.is_empty():
		push_error("AnnotatedScreenshot: No valid nodes resolved from selection.")
		return ""

	# --- 3. Render the annotation panel ---
	var panel_image: Image = await _render_panel(node_data, vp_w)
	if panel_image == null:
		push_error("AnnotatedScreenshot: Panel rendering failed.")
		return ""
	var panel_h := panel_image.get_height()

	# --- 4. Composite viewport on top, panel on bottom ---
	var final_img := Image.create(vp_w, vp_h + panel_h, false, Image.FORMAT_RGB8)

	var src_vp := vp_image
	if src_vp.get_format() != Image.FORMAT_RGB8:
		src_vp = src_vp.duplicate()
		src_vp.convert(Image.FORMAT_RGB8)
	final_img.blit_rect(src_vp, Rect2i(0, 0, vp_w, vp_h), Vector2i(0, 0))

	var src_panel := panel_image
	if src_panel.get_format() != Image.FORMAT_RGB8:
		src_panel = src_panel.duplicate()
		src_panel.convert(Image.FORMAT_RGB8)
	final_img.blit_rect(src_panel, Rect2i(0, 0, vp_w, panel_h), Vector2i(0, vp_h))

	# --- 5. Save PNG ---
	var timestamp := Time.get_datetime_string_from_system(false, true)\
			.replace(":", "-").replace("T", "_")
	var dir_path := ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(dir_path)
	var file_path := dir_path + "/annotated_" + timestamp + ".png"

	var err := final_img.save_png(file_path)
	if err != OK:
		push_error("AnnotatedScreenshot: save_png failed (error %d)." % err)
		return ""

	# --- 6. Optional .txt companion ---
	if export_txt:
		var txt_path := file_path.replace(".png", ".txt")
		var f := FileAccess.open(txt_path, FileAccess.WRITE)
		if f:
			for entry: Dictionary in node_data:
				f.store_line("=== %s ===" % entry["name"])
				for prop: Dictionary in entry["props"]:
					f.store_line("  %s: %s" % [prop["label"], prop["value"]])
				f.store_line("")
			f.close()

	return file_path


# ---------------------------------------------------------------------------
# Viewport capture
# ---------------------------------------------------------------------------

func _get_viewport_image(screen: String) -> Image:
	if screen == "Game":
		return await _get_game_screenshot()

	var vp: Viewport = null
	match screen:
		"2D":
			vp = EditorInterface.get_editor_viewport_2d()
		"3D":
			vp = EditorInterface.get_editor_viewport_3d(0)

	if vp != null and vp.get_texture() != null:
		# Force the rendering server to flush all pending draw calls so the
		# texture contains the current frame's pixels before we read it.
		RenderingServer.force_draw(false)
		await RenderingServer.frame_post_draw
		return vp.get_texture().get_image()

	# Fallback: grab the whole primary screen.
	push_warning("AnnotatedScreenshot: Falling back to screen capture.")
	return DisplayServer.screen_get_image(0)


## Captures the Game view by screenshotting the monitor the editor is on and
## cropping to the main-screen dock (toolbar + game area).
func _get_game_screenshot() -> Image:
	# Find which screen the Godot editor window currently lives on, then grab
	# only that monitor instead of blindly taking screen 0.
	var godot_screen_idx := DisplayServer.window_get_current_screen(0)
	var full_screen := DisplayServer.screen_get_image(godot_screen_idx)

	# get_editor_main_screen() is the VBoxContainer that holds the toolbar tabs
	# (2D / 3D / Script / Game / AssetLib) plus the content area directly below
	# them.  This is the region we want to capture.
	var main_screen_ctrl := EditorInterface.get_editor_main_screen()
	if main_screen_ctrl == null:
		push_warning("AnnotatedScreenshot: get_editor_main_screen() returned null; returning full-screen image.")
		return full_screen

	# get_global_rect() is in editor-window-local logical pixels.
	# window_get_position() gives the window top-left in global desktop pixels.
	# screen_get_position() gives the monitor top-left in global desktop pixels.
	# Subtracting the monitor origin turns desktop coordinates into monitor-local
	# coordinates that match the pixel grid of screen_get_image().
	var window_pos    := Vector2i(DisplayServer.window_get_position(0))
	var screen_origin := Vector2i(DisplayServer.screen_get_position(godot_screen_idx))
	var local_rect    := main_screen_ctrl.get_global_rect()
	var screen_rect   := Rect2i(
		window_pos - screen_origin + Vector2i(local_rect.position),
		Vector2i(local_rect.size)
	)

	# Clamp to monitor bounds to avoid out-of-range blits.
	var monitor_bounds := Rect2i(Vector2i.ZERO, full_screen.get_size())
	screen_rect = screen_rect.intersection(monitor_bounds)

	if screen_rect.size.x <= 0 or screen_rect.size.y <= 0:
		push_warning("AnnotatedScreenshot: Computed game view rect is empty; returning full-screen image.")
		return full_screen

	var cropped := Image.create(screen_rect.size.x, screen_rect.size.y, false, full_screen.get_format())
	cropped.blit_rect(full_screen, screen_rect, Vector2i.ZERO)
	return cropped


# ---------------------------------------------------------------------------
# Panel rendering via SubViewport
# ---------------------------------------------------------------------------

func _render_panel(node_data: Array[Dictionary], width: int) -> Image:
	# Fixed layout: exactly NODES_PER_ROW columns per row.
	var col_w := int(width / NODES_PER_ROW)

	# Split node_data into chunks of NODES_PER_ROW.
	var rows: Array[Array] = []
	var i := 0
	while i < node_data.size():
		rows.append(node_data.slice(i, i + NODES_PER_ROW))
		i += NODES_PER_ROW

	# Calculate total panel height by summing each row's tallest column.
	var panel_h := 0
	for row: Array in rows:
		panel_h += _row_height(row)

	# --- Build SubViewport ---
	var sv := SubViewport.new()
	sv.size = Vector2i(width, panel_h)
	sv.transparent_bg = false

	# Background.
	var bg := ColorRect.new()
	bg.color = Color(0.15, 0.15, 0.15)
	bg.size = Vector2(width, panel_h)
	sv.add_child(bg)

	# Outer VBoxContainer stacks rows vertically.
	var outer_vbox := VBoxContainer.new()
	outer_vbox.position = Vector2.ZERO
	outer_vbox.size = Vector2(width, panel_h)
	outer_vbox.add_theme_constant_override("separation", 0)
	sv.add_child(outer_vbox)

	for row: Array in rows:
		var row_h := _row_height(row)

		# Thin separator between rows (skip before the first row).
		if outer_vbox.get_child_count() > 0:
			var row_sep := HSeparator.new()
			outer_vbox.add_child(row_sep)

		# HBoxContainer holds one VBoxContainer per column in this row.
		var hbox := HBoxContainer.new()
		hbox.custom_minimum_size = Vector2(width, row_h)
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_theme_constant_override("separation", 0)
		outer_vbox.add_child(hbox)

		for entry: Dictionary in row:
			var vbox := VBoxContainer.new()
			vbox.custom_minimum_size = Vector2(col_w - PADDING, 0)
			vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			vbox.add_theme_constant_override("separation", 2)

			# Vertical separator between columns (skip before the first column).
			if hbox.get_child_count() > 0:
				var col_sep := VSeparator.new()
				hbox.add_child(col_sep)

			# Node name header.
			var title := Label.new()
			title.text = entry["name"] as String
			title.add_theme_font_size_override("font_size", 13)
			title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
			vbox.add_child(title)

			var sep := HSeparator.new()
			vbox.add_child(sep)

			# Property rows — wrapping enabled so text never clips horizontally.
			var last_category := ""
			var last_group := ""
			for prop: Dictionary in entry["props"]:
				# Insert a class-category label when the category changes.
				var category: String = prop.get("category", "")
				if category != last_category and not category.is_empty():
					var clbl := Label.new()
					clbl.text = category
					clbl.add_theme_font_size_override("font_size", 11)
					clbl.add_theme_color_override("font_color", Color(1.0, 0.60, 0.2))
					clbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					vbox.add_child(clbl)
					var csep := HSeparator.new()
					vbox.add_child(csep)
					last_category = category
					last_group = ""

				# Insert a group header label whenever the group changes.
				var group: String = prop.get("group", "")
				if group != last_group and not group.is_empty():
					var glbl := Label.new()
					glbl.text = group
					glbl.add_theme_font_size_override("font_size", 10)
					glbl.add_theme_color_override("font_color", Color(0.95, 0.35, 0.35))
					glbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					vbox.add_child(glbl)
					last_group = group

				var lbl := Label.new()
				lbl.text = "%s: %s" % [prop["label"], prop["value"]]
				lbl.add_theme_font_size_override("font_size", 11)
				lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
				lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				vbox.add_child(lbl)

			hbox.add_child(vbox)

	# Add to the editor base control so the SubViewport is in the scene tree
	# and will be processed by the rendering server.
	# Start with UPDATE_DISABLED so no premature render fires before the
	# SubViewport is registered and its contents are laid out.
	sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	EditorInterface.get_base_control().add_child(sv)

	# Wait one process frame so the scene tree registers the new node and the
	# layout pass runs.  Then flip to UPDATE_ONCE to schedule exactly one render
	# pass, and await frame_post_draw to let the GPU complete it.
	await get_tree().process_frame
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw

	var img := sv.get_texture().get_image()
	sv.queue_free()
	return img


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _row_height(row: Array) -> int:
	var max_h := 0
	for entry: Dictionary in row:
		var h := PADDING + HEADER_H
		var last_category := ""
		var last_group := ""
		for prop: Dictionary in entry["props"]:
			var category: String = prop.get("category", "")
			if category != last_category and not category.is_empty():
				h += CAT_H + 4  # label + separator
				last_category = category
				last_group = ""
			var group: String = prop.get("group", "")
			if group != last_group and not group.is_empty():
				h += GROUP_H
				last_group = group
			h += LINE_H
		h += PADDING
		max_h = max(max_h, h)
	return max_h


## Collects inspector-visible properties of an Object into a flat ordered list
## with category blocks reversed so the most-derived class comes first,
## matching the Inspector panel display order.
## Each element: { category, group_label, prefix, prop_info, pname }
func _collect_ordered_props(obj: Object) -> Array:
	var by_category: Array = []
	var cur_cat := {"cat": "", "entries": []}
	var cur_group := ""
	var cur_group_prefix := ""
	var cur_subgroup := ""
	var cur_subgroup_prefix := ""

	for prop in obj.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_CATEGORY:
			by_category.append(cur_cat)
			cur_cat = {"cat": prop["name"], "entries": []}
			cur_group = ""
			cur_group_prefix = ""
			cur_subgroup = ""
			cur_subgroup_prefix = ""
			continue
		if prop["usage"] & PROPERTY_USAGE_GROUP:
			cur_group = prop["name"]
			cur_group_prefix = prop.get("hint_string", "")
			cur_subgroup = ""
			cur_subgroup_prefix = ""
			continue
		if prop["usage"] & PROPERTY_USAGE_SUBGROUP:
			cur_subgroup = prop["name"]
			cur_subgroup_prefix = prop.get("hint_string", "")
			continue
		if not (prop["usage"] & PROPERTY_USAGE_EDITOR):
			continue
		var pname: String = prop["name"]
		if pname.is_empty() or pname == "script" or pname.begins_with("metadata/"):
			continue

		var group_label := cur_group
		var effective_prefix := cur_group_prefix
		if not cur_subgroup.is_empty():
			group_label = cur_subgroup if cur_group.is_empty() \
					else cur_group + " / " + cur_subgroup
			if not cur_subgroup_prefix.is_empty():
				effective_prefix = cur_subgroup_prefix

		cur_cat["entries"].append({
			"group_label": group_label,
			"prefix": effective_prefix,
			"prop_info": prop,
			"pname": pname,
		})

	by_category.append(cur_cat)
	by_category.reverse()

	var result: Array = []
	for cat_data in by_category:
		for e in cat_data["entries"]:
			e["category"] = cat_data["cat"]
			result.append(e)
	return result


## Strips the group's display prefix from a raw property name.
func _strip_group_prefix(pname: String, prefix: String) -> String:
	if not prefix.is_empty() and pname.begins_with(prefix):
		return pname.substr(prefix.length())
	return pname


## Converts a snake_case property name to a human-readable Title Case label.
func _friendly_prop_name(pname: String) -> String:
	var words := pname.split("_")
	var parts: PackedStringArray = []
	for word: String in words:
		if not word.is_empty():
			parts.append(word[0].to_upper() + word.substr(1))
	return " ".join(parts)


func _value_to_string(val) -> String:
	if val == null:
		return "null"
	var s := str(val)
	if s.length() > 120:
		s = s.substr(0, 117) + "…"
	return s


## Resolves PROPERTY_HINT_ENUM to the option label and PROPERTY_HINT_FLAGS to
## a comma-separated list of active flag names; falls back to _value_to_string.
func _format_enum_value(prop_info: Dictionary, val) -> String:
	var hint: int = prop_info.get("hint", 0)
	var hint_str: String = prop_info.get("hint_string", "")
	if hint == PROPERTY_HINT_ENUM and not hint_str.is_empty():
		var int_val := int(val)
		var idx := 0
		for option: String in hint_str.split(","):
			option = option.strip_edges()
			var colon := option.rfind(":")
			if colon != -1:
				var num := option.substr(colon + 1).strip_edges()
				if num.is_valid_int() and int(num) == int_val:
					return option.substr(0, colon).strip_edges()
			else:
				if idx == int_val:
					return option
			idx += 1
	elif hint == PROPERTY_HINT_FLAGS and not hint_str.is_empty():
		var int_val := int(val)
		if int_val == 0:
			return "None"
		var active: PackedStringArray = []
		var i := 0
		for option: String in hint_str.split(","):
			option = option.strip_edges()
			var colon := option.rfind(":")
			var bit_val: int
			if colon != -1:
				var num := option.substr(colon + 1).strip_edges()
				bit_val = int(num) if num.is_valid_int() else (1 << i)
				option = option.substr(0, colon).strip_edges()
			else:
				bit_val = 1 << i
			if int_val & bit_val:
				active.append(option)
			i += 1
		if not active.is_empty():
			return ", ".join(active)
	return _value_to_string(val)


func _resolve_node(scene_root: Node, path: NodePath) -> Node:
	# get_node_or_null on scene_root works for relative paths from the root.
	var node := scene_root.get_node_or_null(path)
	if node:
		return node
	# If the path equals the scene root's own path, return the root itself.
	if path == scene_root.get_path():
		return scene_root
	# Try from the tree root in case an absolute path was stored.
	if scene_root.is_inside_tree():
		return scene_root.get_tree().root.get_node_or_null(path)
	return null
