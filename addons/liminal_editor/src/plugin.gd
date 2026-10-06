@tool
class_name LMPlugin extends EditorPlugin

var map_importer_plugin: LMMapImporter
var map_export_plugin: LMMapExportPlugin
var entity_def_inspector: LMEntityDefinitionInspector
var lm_submenu: PopupMenu
var _entity_wizard: Control
var _float_window: Window
var _wizard_is_floating: bool = false
var _main_screen_wrapper: Control
var _import_btn: Button
var _adopted_last_sync: PackedStringArray = []
var _sync_in_flight: bool = false

static var editor_importing: bool = false

const CFG_KEY_ENTITY_DIRS: String = "liminal_editor/general/entity_directories"
const CFG_KEY_MATERIAL_DIRS: String = "liminal_editor/general/material_directories"
const CFG_KEY_WORKSPACE_FOLDER: String = "liminal_editor/general/workspace_folder"
const CFG_KEY_GEO_TAGS: String = "liminal_editor/general/geometry_tags"
const CFG_KEY_SETUP_COMPLETE: String = "liminal_editor/internal/setup_complete"

const EDITOR_CFG_KEY_WELCOME_DISABLED: String = "liminal_editor/welcome_disabled"
const EDITOR_CFG_KEY_WIZARD_FLOATING: String = "liminal_editor/wizard_floating"
const EDITOR_CFG_KEY_SIDEBAR_VISIBLE: String = "liminal_editor/sidebar_visible"

const TOOL_SUBMENU_ID_TOGGLE_AUTOEXPORT = 1
const TOOL_SUBMENU_ID_REBUILD = 2
const TOOL_SUBMENU_ID_SYNC_ENTITIES = 3
const TOOL_SUBMENU_ID_SYNC_MATERIALS = 4
const TOOL_SUBMENU_ID_FORCE_RESYNC = 5

enum SyncScope { ALL, ENTITIES, MATERIALS }


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "Entities"


func _get_plugin_icon() -> Texture2D:
	return load("res://addons/liminal_editor/icons/icon_entity_code.svg")


func _make_visible(visible: bool) -> void:
	if _main_screen_wrapper and not (visible and _wizard_is_floating):
		_main_screen_wrapper.visible = visible
	if visible and _wizard_is_floating:
		if _float_window:
			_float_window.show()
			_float_window.grab_focus()
		get_editor_interface().set_main_screen_editor("3D")


func setup_config() -> void:
	if !ProjectSettings.has_setting(CFG_KEY_ENTITY_DIRS):
		ProjectSettings.set(CFG_KEY_ENTITY_DIRS, [])
	if !ProjectSettings.has_setting(CFG_KEY_WORKSPACE_FOLDER):
		ProjectSettings.set(CFG_KEY_WORKSPACE_FOLDER, "res://_blender")
	if !ProjectSettings.has_setting(CFG_KEY_MATERIAL_DIRS):
		ProjectSettings.set(CFG_KEY_MATERIAL_DIRS, [])
	if !ProjectSettings.has_setting(CFG_KEY_GEO_TAGS):
		ProjectSettings.set(CFG_KEY_GEO_TAGS, [])
	if !ProjectSettings.has_setting(CFG_KEY_SETUP_COMPLETE):
		ProjectSettings.set(CFG_KEY_SETUP_COMPLETE, false)
	if !ProjectSettings.has_setting(LMTimings.CFG_KEY_ENABLED):
		ProjectSettings.set(LMTimings.CFG_KEY_ENABLED, false)

	ProjectSettings.add_property_info({
		"name": CFG_KEY_ENTITY_DIRS,
		"type": TYPE_ARRAY,
		"hint": PROPERTY_HINT_TYPE_STRING,
		"hint_string": "%d/%d:" % [TYPE_STRING, PROPERTY_HINT_DIR]
	})
	ProjectSettings.add_property_info({
		"name": CFG_KEY_WORKSPACE_FOLDER,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_DIR
	})
	ProjectSettings.add_property_info({
		"name": CFG_KEY_MATERIAL_DIRS,
		"type": TYPE_ARRAY,
		"hint": PROPERTY_HINT_TYPE_STRING,
		"hint_string": "%d/%d:" % [TYPE_STRING, PROPERTY_HINT_DIR]
	})
	ProjectSettings.add_property_info({
		"name": CFG_KEY_GEO_TAGS,
		"type": TYPE_ARRAY,
		"hint": PROPERTY_HINT_TYPE_STRING,
		"hint_string": "%d/%d:" % [TYPE_STRING, PROPERTY_HINT_NONE]
	})
	ProjectSettings.add_property_info({
		"name": LMTimings.CFG_KEY_ENABLED,
		"type": TYPE_BOOL,
	})

	var editor_settings := EditorInterface.get_editor_settings()
	if !editor_settings.has_setting(EDITOR_CFG_KEY_WELCOME_DISABLED):
		editor_settings.set_setting(EDITOR_CFG_KEY_WELCOME_DISABLED, false)
	editor_settings.add_property_info({
		"name": EDITOR_CFG_KEY_WELCOME_DISABLED,
		"type": TYPE_BOOL,
	})
	if !editor_settings.has_setting(EDITOR_CFG_KEY_WIZARD_FLOATING):
		editor_settings.set_setting(EDITOR_CFG_KEY_WIZARD_FLOATING, false)
	editor_settings.add_property_info({
		"name": EDITOR_CFG_KEY_WIZARD_FLOATING,
		"type": TYPE_BOOL,
	})
	if !editor_settings.has_setting(EDITOR_CFG_KEY_SIDEBAR_VISIBLE):
		editor_settings.set_setting(EDITOR_CFG_KEY_SIDEBAR_VISIBLE, true)
	editor_settings.add_property_info({
		"name": EDITOR_CFG_KEY_SIDEBAR_VISIBLE,
		"type": TYPE_BOOL,
	})


func _save_lm_manifest(lm_manifest: Dictionary, save_path: String) -> bool:
	if lm_manifest.has("revision"):
		push_warning("Manifest should not contain revision field. Removing it.")
		lm_manifest.erase("revision")

	var f: FileAccess
	var revision: int = 0

	if FileAccess.file_exists(save_path):
		f = FileAccess.open(save_path, FileAccess.READ_WRITE)
		var existing_json: Variant = JSON.parse_string(f.get_as_text())
		if existing_json is Dictionary:
			var current_manifest: Dictionary = existing_json
			if current_manifest.has("revision"):
				revision = current_manifest["revision"]
				current_manifest.erase("revision")
			if lm_manifest.recursive_equal(current_manifest, 10):
				print("[LM] Skip exporting manifest. No changes detected")
				return true
			f.seek(0)
	else:
		f = FileAccess.open(save_path, FileAccess.WRITE)

	revision += 1
	lm_manifest.set("revision", revision)
	var s: String = JSON.stringify(lm_manifest, "	")
	f.resize(s.length())
	f.store_string(s)
	f.close()
	print("[LM] Exported manifest to %s" % save_path)
	return true


func create_lm_entities(scope: SyncScope = SyncScope.ALL, force: bool = false) -> void:
	if _sync_in_flight:
		push_warning("[LM] A sync is already running; ignoring this request.")
		return
	_sync_in_flight = true
	await _sync_workspace(scope, force)
	_sync_in_flight = false


func _sync_workspace(scope: SyncScope, force: bool) -> void:
	var efs := get_editor_interface().get_resource_filesystem()
	while efs.is_scanning() or editor_importing:
		await get_tree().process_frame
	LMTimings.begin("sync_workspace")
	_adopted_last_sync = []
	var dst_dir: String = ProjectSettings.get_setting(CFG_KEY_WORKSPACE_FOLDER)
	if !DirAccess.dir_exists_absolute(dst_dir):
		print("Liminal Editor: Creating output dir ", dst_dir)
		DirAccess.make_dir_recursive_absolute(dst_dir)

	var ctx := LiminalEditor.create_schema_context()
	ctx.report.workspace_path = ProjectSettings.globalize_path(dst_dir)
	ctx.sync_cache = LMSyncCache.open()
	if force:
		ctx.sync_cache.clear()

	if scope != SyncScope.MATERIALS:
		var models_dir: String = dst_dir.path_join("models")
		if !DirAccess.dir_exists_absolute(models_dir):
			DirAccess.make_dir_recursive_absolute(models_dir)
		if !FileAccess.file_exists(models_dir.path_join(".gdignore")):
			var models_gdignore := FileAccess.open(models_dir.path_join(".gdignore"), FileAccess.WRITE)
			models_gdignore.close()

		LMTimings.start("entity_scan")
		var src_dirs: Array = ProjectSettings.get_setting(CFG_KEY_ENTITY_DIRS)
		for src_dir in src_dirs:
			if !src_dir || src_dir.is_empty() : continue
			if !DirAccess.dir_exists_absolute(src_dir):
				push_warning("Liminal Editor: Directory %s doesn't exist. Ignoring" % src_dir)
				ctx.report.add_config_error("Entity directory does not exist: %s" % src_dir)
				continue
			LiminalEditor.create_lm_entities_from_dir(src_dir, ctx)
		LMTimings.stop("entity_scan")

		if ctx.entity_definitions.is_empty():
			push_warning("Liminal Editor: No entities found in entity directories.")
			ctx.report.add_config_error("No entities found in any configured entity directory")
			LMTimings.finish()
			ctx.report.print_report()
			return

		var lm_manifest := LiminalEditor.create_empty_manifest()
		lm_manifest.set("entities", ctx.entity_definitions)
		lm_manifest.set("types", ctx.choice_definitions)
		lm_manifest.set("geo_tags", _collect_geo_tags())
		var out_json_path: String = dst_dir + "/entities.json"
		_save_lm_manifest(lm_manifest, out_json_path)

	if scope != SyncScope.ENTITIES:
		_adopted_last_sync = await LMMaterialImport.ingest(dst_dir, ctx.report)

		var all_materials: Dictionary = LMMaterialUtils.find_all_material_resources()
		var materials_dir: String = dst_dir.path_join("materials")
		if !DirAccess.dir_exists_absolute(materials_dir):
			DirAccess.make_dir_recursive_absolute(materials_dir)
			var gdignore := FileAccess.open(materials_dir.path_join(".gdignore"), FileAccess.WRITE)
			gdignore.close()
		var mat_glb_path: String = materials_dir.path_join("mat.glb")

		var mat_sources: Array = []
		for base_dir in all_materials:
			for rel in all_materials[base_dir]:
				if (rel as String).get_extension() == "tres":
					mat_sources.append((base_dir as String).path_join(rel))
		var mat_fp: String = LMSyncCache.fingerprint(
			mat_sources, [LMMaterialUtils.PREVIEW_SIZE, LMMaterialUtils.PREVIEW_GRID])

		if ctx.sync_cache.is_fresh(mat_glb_path, mat_fp):
			print("[LM] Materials unchanged - skipping mat.glb rebuild (%d source(s))." % mat_sources.size())
		else:
			LMTimings.start("materials_total")
			var mat_err: Variant = await LMMaterialUtils.export_materials_glb(all_materials, mat_glb_path, ctx.report)
			LMTimings.stop("materials_total")
			if mat_err == OK:
				ctx.sync_cache.record(mat_glb_path, mat_fp)

	ctx.sync_cache.save()
	LMTimings.finish()
	ctx.report.print_report()


func _collect_geo_tags() -> Array:
	var raw: Array = ProjectSettings.get_setting(CFG_KEY_GEO_TAGS, [])
	var out: Array = []
	for t in raw:
		var s: String = str(t).strip_edges()
		if not s.is_empty() and not out.has(s):
			out.append(s)
	return out


func submenu_pressed(id: int) -> void:
	match id:
		TOOL_SUBMENU_ID_REBUILD:
			_show_export_in_progress()
			await create_lm_entities()
			_show_export_complete()
			_maybe_show_adoption_notice()
		TOOL_SUBMENU_ID_SYNC_ENTITIES:
			_show_export_in_progress()
			await create_lm_entities(SyncScope.ENTITIES)
			_show_export_complete()
		TOOL_SUBMENU_ID_SYNC_MATERIALS:
			_show_export_in_progress()
			await create_lm_entities(SyncScope.MATERIALS)
			_show_export_complete()
			_maybe_show_adoption_notice()
		TOOL_SUBMENU_ID_FORCE_RESYNC:
			_show_export_in_progress()
			await create_lm_entities(SyncScope.ALL, true)
			_show_export_complete()
			_maybe_show_adoption_notice()

func _show_export_in_progress() -> void:
	print("[LM] Starting entity definitions export...")

func _show_export_complete() -> void:
	var toast := LMToastNotification.new()
	var root = get_editor_interface().get_base_control()
	root.add_child(toast)

func _maybe_show_adoption_notice() -> void:
	if _adopted_last_sync.is_empty():
		return
	var names := _adopted_last_sync
	_adopted_last_sync = []

	var dlg := AcceptDialog.new()
	dlg.title = "Materials Adopted"
	dlg.dialog_text = _adoption_notice_text(names)
	dlg.add_button("Show in FileSystem", true, "show_fs")
	dlg.custom_action.connect(func(action: StringName) -> void:
		if action == "show_fs":
			EditorInterface.get_file_system_dock().navigate_to_path(LMMaterialImport.IMPORTED_DIR + "/")
	)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	get_editor_interface().get_base_control().add_child(dlg)
	dlg.popup_centered()

func _adoption_notice_text(names: PackedStringArray) -> String:
	var shown := names
	var extra := 0
	if names.size() > 12:
		shown = names.slice(0, 12)
		extra = names.size() - 12
	var text := "Adopted %d material(s) into %s:\n" % [names.size(), LMMaterialImport.IMPORTED_DIR]
	for n in shown:
		text += "  • %s\n" % n
	if extra > 0:
		text += "  … and %d more\n" % extra
	text += "\nThese were imported with default settings. Review texture roles/"
	text += "filtering, cull mode, and naming before production use."
	return text

func _get_addon_path() -> String:
	return get_script().resource_path.get_base_dir().get_base_dir()

func _first_time_setup() -> void:
	var addon_path := _get_addon_path()

	var entity_dirs: Array = ProjectSettings.get_setting(CFG_KEY_ENTITY_DIRS)
	var builtin_entities_dir := addon_path.path_join("resources/builtin_entities")
	if not entity_dirs.has(builtin_entities_dir):
		entity_dirs.append(builtin_entities_dir)
		ProjectSettings.set(CFG_KEY_ENTITY_DIRS, entity_dirs)

	var material_dirs: Array = ProjectSettings.get_setting(CFG_KEY_MATERIAL_DIRS)
	var builtin_materials_dir := addon_path.path_join("resources/materials")
	if not material_dirs.has(builtin_materials_dir):
		material_dirs.append(builtin_materials_dir)
		ProjectSettings.set(CFG_KEY_MATERIAL_DIRS, material_dirs)

func _show_welcome_window() -> void:
	var welcome: LMWelcomeWindow = LMWelcomeWindow.new()
	var editor_settings := EditorInterface.get_editor_settings()
	welcome.set_welcome_disabled(editor_settings.get_setting(EDITOR_CFG_KEY_WELCOME_DISABLED))
	welcome.dont_show_changed.connect(func(disabled: bool) -> void:
		editor_settings.set_setting(EDITOR_CFG_KEY_WELCOME_DISABLED, disabled)
	)
	get_editor_interface().get_base_control().add_child(welcome)
	welcome.popup_centered()

func _enter_tree() -> void:
	setup_config()

	var efs_signals := get_editor_interface().get_resource_filesystem()
	efs_signals.resources_reimporting.connect(_on_resources_reimporting)
	efs_signals.resources_reimported.connect(_on_resources_reimported)

	var first_time: bool = !ProjectSettings.get_setting(CFG_KEY_SETUP_COMPLETE)
	if first_time:
		_first_time_setup()
	ProjectSettings.set(CFG_KEY_SETUP_COMPLETE, true)
	ProjectSettings.save()

	var welcome_disabled: bool = EditorInterface.get_editor_settings().get_setting(EDITOR_CFG_KEY_WELCOME_DISABLED)
	if first_time or !welcome_disabled:
		_show_welcome_window()

	map_importer_plugin = LMMapImporter.new()
	add_import_plugin(map_importer_plugin)

	map_export_plugin = LMMapExportPlugin.new()
	add_export_plugin(map_export_plugin)

	_main_screen_wrapper = Control.new()
	_main_screen_wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main_screen_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_screen_wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	get_editor_interface().get_editor_main_screen().add_child(_main_screen_wrapper)
	_main_screen_wrapper.hide()

	var base_ctrl := get_editor_interface().get_base_control()
	_entity_wizard = LMEntityWizard.new()
	_entity_wizard.editor_interface = get_editor_interface()
	_entity_wizard.lm_plugin = self
	_entity_wizard.export_callable = func() -> void:
		_show_export_in_progress()
		await create_lm_entities()
		_show_export_complete()
	_entity_wizard.show_callable = _show_wizard
	_entity_wizard.hide_callable = _hide_wizard
	_entity_wizard.toggle_float_callable = _toggle_wizard_float
	_entity_wizard._base_control = base_ctrl
	_wizard_is_floating = EditorInterface.get_editor_settings().get_setting(EDITOR_CFG_KEY_WIZARD_FLOATING)
	if _wizard_is_floating:
		_setup_float_mode()
	else:
		_setup_dock_mode()
	_entity_wizard.setup()

	entity_def_inspector = LMEntityDefinitionInspector.new()
	entity_def_inspector.open_entity_callable = func(def: LMEntityDefinition) -> void:
		_entity_wizard.open(def)
	add_inspector_plugin(entity_def_inspector)

	lm_submenu = PopupMenu.new()
	lm_submenu.id_pressed.connect(submenu_pressed)
	lm_submenu.add_item("Sync Workspace", TOOL_SUBMENU_ID_REBUILD, KEY_R | KEY_SHIFT | KEY_CTRL)
	lm_submenu.add_item("Sync Entities Only", TOOL_SUBMENU_ID_SYNC_ENTITIES)
	lm_submenu.add_item("Sync Materials Only", TOOL_SUBMENU_ID_SYNC_MATERIALS)
	lm_submenu.add_separator()
	lm_submenu.add_item("Force Full Resync", TOOL_SUBMENU_ID_FORCE_RESYNC)
	lm_submenu.set_item_tooltip(lm_submenu.get_item_index(TOOL_SUBMENU_ID_FORCE_RESYNC),
		"Clear the sync cache and rebuild every preview model and the materials GLB.")

	add_tool_submenu_item("Liminal Editor", lm_submenu)

	_import_btn = Button.new()
	_import_btn.text = "Import LMMap"
	_import_btn.icon = load("res://addons/liminal_editor/icons/icon_lm_import.svg")
	_import_btn.tooltip_text = "Import all LM Map nodes in this scene."
	_import_btn.pressed.connect(_on_import_pressed)
	_import_btn.hide()
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _import_btn)
	scene_changed.connect(_on_scene_changed)
	_refresh_import_button(get_editor_interface().get_edited_scene_root())


func _on_resources_reimporting(_resources: PackedStringArray) -> void:
	editor_importing = true


func _on_resources_reimported(_resources: PackedStringArray) -> void:
	editor_importing = false


func _on_scene_changed(scene_root: Node) -> void:
	_refresh_import_button(scene_root)


func _refresh_import_button(scene_root: Node) -> void:
	var should_be_visible: bool = not _find_all_lm_maps(scene_root).is_empty()
	print("Scene changed: ", should_be_visible)
	_import_btn.visible = should_be_visible


func _find_all_lm_maps(node: Node) -> Array[LMMap]:
	var result: Array[LMMap] = []
	if node == null:
		return result
	if node is LMMap:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_all_lm_maps(child))
	return result


func _on_import_pressed() -> void:
	for lm_map in _find_all_lm_maps(get_editor_interface().get_edited_scene_root()):
		lm_map.run_import()


func _setup_dock_mode() -> void:
	_wizard_is_floating = false
	_entity_wizard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main_screen_wrapper.add_child(_entity_wizard)


func _setup_float_mode() -> void:
	_wizard_is_floating = true
	_float_window = Window.new()
	_float_window.title = "Entity Wizard"
	_float_window.min_size = Vector2i(960, 350)
	_float_window.size = Vector2i(960, 820)
	_float_window.close_requested.connect(func() -> void: _toggle_wizard_float())
	get_editor_interface().get_base_control().add_child(_float_window)
	_float_window.add_child(_entity_wizard)
	_entity_wizard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var main_pos := DisplayServer.window_get_position()
	var main_size := DisplayServer.window_get_size()
	_float_window.position = main_pos + (main_size - _float_window.size) / 2


func _show_wizard() -> void:
	if _wizard_is_floating:
		if _float_window:
			_float_window.show()
			_float_window.grab_focus()
	else:
		get_editor_interface().set_main_screen_editor(_get_plugin_name())


func _hide_wizard() -> void:
	if _wizard_is_floating:
		if _float_window:
			_float_window.hide()


func _toggle_wizard_float() -> void:
	var was_visible: bool = _wizard_is_floating \
		and _float_window != null and _float_window.visible \
		or not _wizard_is_floating and _entity_wizard.visible
	if _wizard_is_floating:
		if _float_window:
			_float_window.hide()
			_float_window.remove_child(_entity_wizard)
			_float_window.queue_free()
			_float_window = null
		_setup_dock_mode()
	else:
		_main_screen_wrapper.remove_child(_entity_wizard)
		_setup_float_mode()
	EditorInterface.get_editor_settings().set_setting(EDITOR_CFG_KEY_WIZARD_FLOATING, _wizard_is_floating)
	if was_visible:
		_show_wizard()


func _exit_tree() -> void:
	var efs_signals := get_editor_interface().get_resource_filesystem()
	efs_signals.resources_reimporting.disconnect(_on_resources_reimporting)
	efs_signals.resources_reimported.disconnect(_on_resources_reimported)
	editor_importing = false

	remove_import_plugin(map_importer_plugin)
	map_importer_plugin = null

	remove_export_plugin(map_export_plugin)
	map_export_plugin = null

	remove_inspector_plugin(entity_def_inspector)
	entity_def_inspector = null

	if _entity_wizard:
		_entity_wizard.cleanup()
		if _wizard_is_floating and _float_window:
			_float_window.remove_child(_entity_wizard)
			_float_window.queue_free()
			_float_window = null
		_entity_wizard.queue_free()
		_entity_wizard = null

	if _main_screen_wrapper:
		_main_screen_wrapper.queue_free()
		_main_screen_wrapper = null

	remove_tool_menu_item("Liminal Editor")

	scene_changed.disconnect(_on_scene_changed)
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _import_btn)
	_import_btn.queue_free()
	_import_btn = null
