@tool
extends VBoxContainer

## Current active editor screen name: "2D", "3D", or "Game".
## Set by the EditorPlugin whenever main_screen_changed fires.
var current_screen := "2D"

var _tree: Tree
var _export_txt_check: CheckBox
var _status_label: Label


func _ready() -> void:
    _build_ui()
    # Populate after one frame so EditorInterface is fully ready.
    call_deferred("refresh_nodes")


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
    name = "AnnotatedScreenshot"
    custom_minimum_size = Vector2(220, 300)

    var refresh_btn := Button.new()
    refresh_btn.text = "↺  Refresh Nodes"
    refresh_btn.tooltip_text = "Re-scan the current scene and refresh the node list."
    refresh_btn.pressed.connect(refresh_nodes)
    add_child(refresh_btn)

    _tree = Tree.new()
    _tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _tree.hide_root = true
    _tree.select_mode = Tree.SELECT_SINGLE
    _tree.item_edited.connect(_on_tree_item_edited)
    add_child(_tree)

    add_child(HSeparator.new())

    _export_txt_check = CheckBox.new()
    _export_txt_check.text = "Also export .txt file"
    add_child(_export_txt_check)

    var capture_btn := Button.new()
    capture_btn.text = "📷  Take Screenshot"
    capture_btn.pressed.connect(_on_capture_pressed)
    add_child(capture_btn)

    _status_label = Label.new()
    _status_label.text = ""
    _status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
    add_child(_status_label)


# ---------------------------------------------------------------------------
# Node scanning
# ---------------------------------------------------------------------------

func refresh_nodes() -> void:
    _tree.clear()
    _tree.create_item()  # hidden root

    var scene_root = EditorInterface.get_edited_scene_root()
    if scene_root == null:
        _status_label.text = "No scene open."
        return

    _status_label.text = ""
    _add_all_nodes_flat(scene_root)


func _add_all_nodes_flat(node: Node) -> void:
    _add_node_to_tree(node)
    for child in node.get_children():
        _add_all_nodes_flat(child)


func _add_node_to_tree(node: Node) -> void:
    var item := _tree.create_item(_tree.get_root())
    item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
    item.set_text(0, node.name + "  [" + node.get_class() + "]")
    item.set_checked(0, true)
    item.set_editable(0, true)
    item.set_metadata(0, node.get_path())
    item.collapsed = true

    var cur_cat_item: TreeItem = null
    var cur_cat_name := ""
    var cur_group_item: TreeItem = null
    var cur_group_key := ""  # cat_name + "|" + group_label

    for e in _collect_ordered_props(node):
        var pname: String = e["pname"]
        var prop = e["prop_info"]
        var category: String = e["category"]
        var group_label: String = e["group_label"]
        var prefix: String = e["prefix"]

        # -- Category item (child of node) --
        if category != cur_cat_name:
            cur_cat_name = category
            cur_group_item = null
            cur_group_key = ""
            if not category.is_empty():
                var cat_item := _tree.create_item(item)
                cat_item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
                cat_item.set_text(0, category)
                cat_item.set_checked(0, true)
                cat_item.set_editable(0, true)
                cat_item.set_custom_color(0, Color(1.0, 0.60, 0.2))
                cat_item.set_metadata(0, {"cat": category})
                cat_item.collapsed = true
                cur_cat_item = cat_item
            else:
                cur_cat_item = null

        # -- Group item (child of category, or node if uncategorised) --
        var group_parent := cur_cat_item if cur_cat_item != null else item
        var new_group_key := cur_cat_name + "|" + group_label
        if new_group_key != cur_group_key:
            cur_group_key = new_group_key
            if not group_label.is_empty():
                var group_item := _tree.create_item(group_parent)
                group_item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
                group_item.set_text(0, group_label)
                group_item.set_checked(0, true)
                group_item.set_editable(0, true)
                group_item.set_custom_color(0, Color(0.95, 0.35, 0.35))
                group_item.set_metadata(0, null)
                group_item.collapsed = true
                cur_group_item = group_item
            else:
                cur_group_item = null

        # -- Property item (child of group > category > node) --
        var prop_parent: TreeItem
        if cur_group_item != null:
            prop_parent = cur_group_item
        elif cur_cat_item != null:
            prop_parent = cur_cat_item
        else:
            prop_parent = item

        var val = node.get(pname)
        var prop_item := _tree.create_item(prop_parent)
        prop_item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
        prop_item.set_checked(0, true)
        prop_item.set_editable(0, true)

        var display_name := _friendly_prop_name(_strip_group_prefix(pname, prefix))
        if val is Resource and _resource_has_editor_props(val):
            prop_item.set_text(0, display_name + "  [" + val.get_class() + "]")
            prop_item.set_custom_color(0, Color(1.0, 0.55, 0.3))
            prop_item.set_metadata(0, {"container": pname})
            _add_resource_props_to_tree(prop_item, pname, val)
        else:
            prop_item.set_text(0, display_name + ": " + _format_enum_value(prop, val))
            prop_item.set_metadata(0, pname)


# ---------------------------------------------------------------------------
# Resource sub-property tree helpers
# ---------------------------------------------------------------------------

func _resource_has_editor_props(resource: Resource) -> bool:
    for prop in resource.get_property_list():
        if not (prop["usage"] & PROPERTY_USAGE_EDITOR):
            continue
        var pname: String = prop["name"]
        if not pname.is_empty() and pname != "script" and not pname.begins_with("metadata/"):
            return true
    return false


## Adds the inspector-visible properties of a resource as child tree items.
## All leaf item metadata is stored as "resource_prop/sub_prop" strings.
func _add_resource_props_to_tree(parent_item: TreeItem, res_pname: String, resource: Resource) -> void:
    var cur_cat_item: TreeItem = null
    var cur_cat_name := ""
    var cur_group_item: TreeItem = null
    var cur_group_key := ""

    for e in _collect_ordered_props(resource):
        var pname: String = e["pname"]
        var prop = e["prop_info"]
        var category: String = e["category"]
        var group_label: String = e["group_label"]
        var gpfx: String = e["prefix"]

        # -- Category item --
        if category != cur_cat_name:
            cur_cat_name = category
            cur_group_item = null
            cur_group_key = ""
            if not category.is_empty():
                var cat_item := _tree.create_item(parent_item)
                cat_item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
                cat_item.set_text(0, category)
                cat_item.set_checked(0, true)
                cat_item.set_editable(0, true)
                cat_item.set_custom_color(0, Color(1.0, 0.60, 0.2))
                cat_item.set_metadata(0, {"cat": category})
                cat_item.collapsed = true
                cur_cat_item = cat_item
            else:
                cur_cat_item = null

        # -- Group item --
        var group_parent := cur_cat_item if cur_cat_item != null else parent_item
        var new_group_key := cur_cat_name + "|" + group_label
        if new_group_key != cur_group_key:
            cur_group_key = new_group_key
            if not group_label.is_empty():
                var group_item := _tree.create_item(group_parent)
                group_item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
                group_item.set_text(0, group_label)
                group_item.set_checked(0, true)
                group_item.set_editable(0, true)
                group_item.set_custom_color(0, Color(0.95, 0.35, 0.35))
                group_item.set_metadata(0, null)
                group_item.collapsed = true
                cur_group_item = group_item
            else:
                cur_group_item = null

        # -- Sub-property item --
        var prop_parent: TreeItem
        if cur_group_item != null:
            prop_parent = cur_group_item
        elif cur_cat_item != null:
            prop_parent = cur_cat_item
        else:
            prop_parent = parent_item

        var val = resource.get(pname)
        var sub_item := _tree.create_item(prop_parent)
        sub_item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
        sub_item.set_checked(0, true)
        sub_item.set_editable(0, true)
        sub_item.set_text(0, _friendly_prop_name(_strip_group_prefix(pname, gpfx)) + ": " + _format_enum_value(prop, val))
        sub_item.set_metadata(0, res_pname + "/" + pname)


# ---------------------------------------------------------------------------
# Selection query
# ---------------------------------------------------------------------------

## Returns { NodePath: [prop_path, ...] } for all checked leaf properties.
## prop_path is either "prop_name" or "resource_prop/sub_prop".
func get_selection() -> Dictionary:
    var result := {}
    var root_item := _tree.get_root()
    if root_item == null:
        return result

    var node_item := root_item.get_first_child()
    while node_item != null:
        if node_item.is_checked(0):
            var node_path: NodePath = node_item.get_metadata(0)
            var props: Array[String] = []
            _collect_leaf_props(node_item, props)
            if not props.is_empty():
                result[node_path] = props
        node_item = node_item.get_next()
    return result


## Recursively collects checked leaf prop-path strings from a tree item's children.
## Recurses through category and group headers automatically.
func _collect_leaf_props(parent: TreeItem, out: Array[String]) -> void:
    var child := parent.get_first_child()
    while child != null:
        var meta = child.get_metadata(0)
        if meta is String:
            # Leaf property.
            if child.is_checked(0):
                out.append(meta)
        elif meta is Dictionary and meta.has("container"):
            # Resource container — only recurse if checked.
            if child.is_checked(0):
                _collect_leaf_props(child, out)
        else:
            # Category ({"cat":...}) or group header (null) — always recurse.
            _collect_leaf_props(child, out)
        child = child.get_next()


# ---------------------------------------------------------------------------
# Tree cascade toggle
# ---------------------------------------------------------------------------

func _on_tree_item_edited() -> void:
    var item := _tree.get_edited()
    if item == null:
        return
    var meta = item.get_metadata(0)
    var checked := item.is_checked(0)

    # Node item, category, group header, or resource container:
    # cascade the new state to every descendant.
    var is_node := item.get_parent() == _tree.get_root()
    var is_cat = meta is Dictionary and meta.has("cat")
    var is_group := meta == null
    var is_container = meta is Dictionary and meta.has("container")
    if is_node or is_cat or is_group or is_container:
        _cascade_to_children(item, checked)


## Sets checked state on all descendants recursively.
func _cascade_to_children(item: TreeItem, checked: bool) -> void:
    var child := item.get_first_child()
    while child != null:
        child.set_checked(0, checked)
        _cascade_to_children(child, checked)
        child = child.get_next()


# ---------------------------------------------------------------------------
# Capture
# ---------------------------------------------------------------------------

func _on_capture_pressed() -> void:
    _status_label.text = "Capturing…"
    await get_tree().process_frame

    var selection := get_selection()
    if selection.is_empty():
        _status_label.text = "Nothing selected — check at least one property."
        return

    var scene_root := EditorInterface.get_edited_scene_root()
    if scene_root == null:
        _status_label.text = "No scene open."
        return

    var annotator := preload("res://addons/annotated_screenshot/annotator.gd").new()
    add_child(annotator)

    var path: String = await annotator.capture(
            selection, scene_root, _export_txt_check.button_pressed, current_screen)

    annotator.queue_free()

    if not path.is_empty():
        _status_label.text = "Saved:\n" + path
    else:
        _status_label.text = "Capture failed. Check output for errors."


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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


func _value_to_string(val) -> String:
    if val == null:
        return "null"
    var s := str(val)
    if s.length() > 60:
        s = s.substr(0, 57) + "…"
    return s


## Converts a snake_case property name to a human-readable Title Case label.
func _friendly_prop_name(pname: String) -> String:
    var words := pname.split("_")
    var parts: PackedStringArray = []
    for word: String in words:
        if not word.is_empty():
            parts.append(word[0].to_upper() + word.substr(1))
    return " ".join(parts)


## Returns the human-readable string for a value given its property info dict.
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
