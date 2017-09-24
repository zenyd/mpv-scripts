local utils = require 'mp.utils'
require 'mp.options'

options = {}
options.down_dir = ""
options.sub_language = "eng"

if package.config:sub(1,1) == "/" then
	options.subselect_path = utils.join_path(os.getenv("HOME"), ".config/mpv/scripts/subselect.py")
	ops = "unix"
else
	options.subselect_path = utils.join_path(os.getenv("APPDATA"), "mpv\\scripts\\subselect.py")
	ops = "win"
end

function fixsub(path)
	f = io.open(path, "r")
	if f == nil then
		return
	end
	content = f:read("*all")
	f:close()
	write = false
	content = content:gsub("%s*%-%->%s*",
		function(w)
			if w:len() < 5 then
				write = true
				return " --> "
			end
		end, 1)
	if not write then
		return
	end
	f = io.open(path, "w")
	f:write(content)
	f:flush()
	f:close()
end

function set_down_dir(ddir)
	if ddir == "" then
		if mp.get_property_native("path", ""):find("://") ~= nil then
			if ops == "win" then
				ddir = utils.join_path(os.getenv("USERPROFILE"), "Downloads")
			else
				ddir = os.getenv("HOME")
			end
		else
			ddir = utils.split_path(mp.get_property_native("path", ""))
			if  ops == "win" then
				if ddir:find("^%a:") == nil then
					ddir = utils.join_path(os.getenv("USERPROFILE"), "Downloads")
				end
			else
				if ddir:find("^/") == nil then
					ddir = os.getenv("HOME")
				end
			end
		end
	end
	return ddir
end

function get_python_binary()
	python = nil
	python_version = utils.subprocess({ args = { "python", "--version" }})
	if python_version.status < 0 then
		mp.osd_message("python not found")
	else
		if python_version.stdout:find("3%.") ~= nil then
			python = "python"
		else
			python_version = utils.subprocess({ args = { "python3", "--version" }})
			if python_version.status < 0 then
				mp.osd_message("python3 not installed")
			else
				python = "python3"
			end
		end
	end
	return python
end

function search_subs()
	read_options(options)
	ddir = set_down_dir(options.down_dir)
	video = mp.get_property_native("media-title", "")
	python = get_python_binary()
	if python ~= nil then
		ret = utils.subprocess({ args = { python, options.subselect_path, video, ddir, options.sub_language }})
	else
		return
	end
	if string.find(ret.stdout, ".") ~= nil then
		mp.osd_message("loading subtitle: "..ret.stdout)
		subtitle_path = utils.join_path(ddir, ret.stdout)
		fixsub(subtitle_path)
		mp.commandv("sub-add", subtitle_path)
	else
		mp.osd_message("No subtitles found")
	end
end

mp.add_key_binding("alt+u", "subselect", search_subs)