-- Import partial functions from upstream intl.lua
local locale = {}
local cache = {}
function get_languages()
	local languages = {}

	for _, lang in ipairs(comma_split(options.languages)) do
		if (lang == 'slang') then
			local slang = mp.get_property_native('slang')
			if slang then
				itable_append(languages, slang)
			end
		else
			languages[#languages +1] = lang
		end
	end

	return languages
end
---@param path string
function get_locale_from_json(path)
	local expand_path = mp.command_native({'expand-path', path})

	local meta, meta_error = utils.file_info(expand_path)
	if not meta or not meta.is_file then
		return nil
	end

	local json_file = io.open(expand_path, 'r')
	if not json_file then
		return nil
	end

	local json = json_file:read('*all')
	json_file:close()

	local json_table = utils.parse_json(json)
	return json_table
end
---@param text string
function t(text, a)
	if not text then return '' end
	local key = text
	if a then key = key .. '|' .. a end
	if cache[key] then return cache[key] end
	cache[key] = string.format(locale[text] or text, a or '')
	return cache[key]
end


ulang = {

	-- context_menu_default
	_cm_load = 'Load',
	_cm_file_browser = 'File Browser',
	_cm_import_sid = 'Import Subtitle',
	_cm_navigation = 'Navigation',
	_cm_playlist = 'Playlist',
	_cm_edition_list = 'Edition List',
	_cm_chapter_list = 'Chapter List',
	_cm_vid_list = 'Video Track List',
	_cm_aid_list = 'Audio Track List',
	_cm_sid_list = 'Subtitle Track List',
	_cm_playlist_shuffle = 'Shuffle Playlist',
	_cm_ushot = 'Screenshot (with subs, no OSD)',
	_cm_video = 'Video',
	_cm_decoding_api = 'Toggle Decoding Mode',
	_cm_deband_toggle = 'Toggle Deband',
	_cm_deint_toggle = 'Toggle Deinterlace',
	_cm_icc_toggle = 'Toggle Auto Color Calibration',
	_cm_corpts_toggle = 'Toggle Timestamp Parsing Mode',
	_cm_tools = 'Tools',
	_cm_keybinding = 'Keybinding List',
	_cm_stats_toggle = 'Toggle Persistent Stats',
	_cm_console_on = 'Show Console',
	_cm_border_toggle = 'Toggle Window Border',
	_cm_ontop_toggle = 'Toggle Always On Top',
	_cm_audio_device = 'Audio Output Device List',
	_cm_stream_quality = 'Stream Quality',
	_cm_show_file_dir = 'Open File Location',
	_cm_show_config_dir = 'Open Config Directory',
	_cm_stop = 'Stop',
	_cm_quit = 'Quit mpv',

	-- no-border-title
	_border_title= 'No File Loaded',

	-- track_loaders sub_menu menu_data
	_sid_menu = 'Subtitle',
	_aid_menu = 'Audio',
	_vid_menu = 'Video',
	_import_id_menu = 'Import ',
	_import_id_footnote = 'Paste URL to load file Ctrl+v. Go up Alt+UP',

--	_menu_item_empty_title = 'Empty',
	_menu_search = 'Type and press Ctrl+ENTER to search',
	_menu_search2 = 'Type to search',

	_input_empty = 'input-bindings is empty',
	_error = 'Error, see console',
	_clipboard_osd = 'Copied to clipboard',
	_clipboard_osd2 = 'Nothing to copy',

	_sid_submenu_title = 'Subtitle Track List',
	_sid_submenu_label1 = 'Toggle Secondary Subtitle',
	_sid_submenu_label2 = 'Reload',
	_sid_submenu_label3 = 'Remove',
--	_sid_sec_submenu_title = 'Secondary Subtitle List',
	_aid_submenu_title = 'Audio Track List',
	_vid_submenu_title = 'Video Track List',
	_xid_submenu_footnote = 'Click again to disable. Paste URL to add Ctrl+v',
	_playlist_submenu_title = 'Playlist',
	_playlist_submenu_footnote = 'Paste URL to add file Ctrl+v. Reorder Ctrl+UP/DOWN/PGUP/PGDWN/HOME/END',
	_playlist_submenu_label1 = 'Move Up',
	_playlist_submenu_label2 = 'Move Down',
	_playlist_submenu_label3 = 'Remove',
	_playlist_submenu_label4 = 'Delete',
	_chapter_list_submenu_title = 'Chapter List',
	_chapter_list_submenu_item_title = 'Unnamed Chapter ',
	_edition_list_submenu_title = 'Edition List',
	_edition_list_submenu_item_title = 'Edition',
	_stream_quality_submenu_title = 'Stream Quality',
	_audio_device_submenu_title = 'Audio Output Device List',
	_audio_device_submenu_item_title = 'Auto',

--	_dlsub_download = 'Download',
	_dlsub_searchol = 'Search Online',
	_dlsub_searchol_label = 'Open in Browser',
--	_dlsub_invalid_response = 'Invalid JSON response',
--	_dlsub_process_exit = 'Process exit code',
--	_dlsub_unknown_err = 'Unknown error',
	_dlsub_err = 'Error',
	_dlsub_err2 = 'See console',
	_dlsub_fin = 'Downloaded and loaded',
--	_dlsub_fin2 = 'Load subtitle',
	_dlsub_remain = 'Downloads remaining today',
	_dlsub_reset = 'Reset',
	_dlsub_foreign = 'Foreign parts only',
	_dlsub_hearing = 'Hearing impaired',
	_dlsub_result0 = 'No results',
	_dlsub_page_prev = 'Previous Page',
	_dlsub_page_next = 'Next Page',
	_dlsub_2search = 'Press ENTER to search',
	_dlsub_enter_query = 'Enter query',

	_submenu_import = 'Import',
	_submenu_load_file = 'Open File',
--	_submenu_id_disabled = 'Disabled',
	_submenu_id_hint = 'Channels',
	_submenu_id_forced = 'Forced',
	_submenu_id_default = 'Default',
	_submenu_id_external = 'External',
	_submenu_id_title = 'Track ',
	_submenu_file_browser_label1 = 'Add to Playlist',
	_submenu_file_browser_label2 = 'Load Directory as Playlist',
	_submenu_file_browser_item_hint = 'Drive List',
	_submenu_file_browser_item_hint2 = 'Parent Directory',
	_submenu_file_browser_item2_hint = 'Drive',
	_submenu_file_browser_title = 'Drive List',

	-- built-in_shortcut
	_button01 = 'Menu',
	_button02 = 'Subtitle',
	_button03 = 'Audio',
	_button04 = 'Audio Device',
	_button05 = 'Video',
	_button06 = 'Playlist',
	_button07 = 'Chapter',
	_button08 = 'Edition',
	_button09 = 'Stream Quality',
	_button10 = 'Load File',
	_button11 = 'Playlist/File Browser',
	_button12 = 'Previous',
	_button13 = 'Next',
	_button14 = 'First',
	_button15 = 'Last',
	_button16 = 'Loop Playlist',
	_button17 = 'Loop File',
	_button18 = 'Shuffle',
	_button19 = 'Auto Load',
	_button20 = 'Toggle Fullscreen',

	_button_ext01 = 'Play/Pause',
	_button_ext02 = 'Play/Pause',
	_button_ext03 = 'Previous',
	_button_ext04 = 'Next',
	_button_ext05 = 'Window Border',
	_button_ext06 = 'On Top',
	_button_ext07 = 'Hardware Decode',
	_button_ext08 = 'Original Size',
	_button_ext09 = 'Deband',
	_button_ext10 = 'Deinterlace',
	_button_ext11 = 'Screenshot',
	_button_ext12 = 'Statistics',
	_button_ext13 = 'Timeline Preview',

}

opt.read_options(ulang, "uosc_lang")
