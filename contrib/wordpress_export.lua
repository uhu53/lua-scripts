--[[
  This file is part of darktable,
  Copyright 2019 by Tobias Jakobs.

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]
--[[
darktable Wordpress export script

ADDITIONAL SOFTWARE NEEDED FOR THIS SCRIPT
* curl 

USAGE
* require this script from your main Lua file

]]

local dt = require "darktable"
local du = require "lib/dtutils"
local df = require "lib/dtutils.file"
local ds = require "lib/dtutils.string"
local dsys = require "lib/dtutils.system"

local gettext = dt.gettext

local PS = dt.configuration.running_os == "windows" and "\\" or "/"

du.check_min_api_version("5.0.0", wordpress_export) 

-- Tell gettext where to find the .mo file translating messages for a particular domain
gettext.bindtextdomain("wordpress_export",dt.configuration.config_dir.."/lua/locale/")

local function _(msgid)
  return gettext.dgettext("wordpress_export", msgid)
end

local function show_status(storage, image, format, filename, number, total, high_quality, extra_data)
  dt.print(string.format(_("Export Image %i/%i"), number, total))
end

-- Add duplicate index to filename
-- image.filename does not have index, exported_image has index
function addDuplicateIndex( index, filename )
  if index > 0 then
    filename = filename.."_"
    if index < 10 then
      filename = filename.."0"
    end
    filename = filename..index
  end

  return filename 
end

local function export(storage, image_table, extra_data)

  local curlPath 
  if dt.configuration.running_os == "linux" then
    curlPath = 'curl'
  else
    curlPath = dt.preferences.read("wordpress_export","curlPath","string")
  end

  if not df.check_if_bin_exists(curlPath) then
    dt.print_error(_("curl not found"))
    return
  end
  dt.print_log("Will try to export to WordPress")

  local imageFoldername
  exportDirectory = dt.preferences.read("wordpress_export","ExportDirectory","string")
  -- Creates dir if not exsists
  imageFoldername = "files"..PS
  df.mkdir(df.sanitize_filename(exportDirectory..PS..imageFoldername))

  for image,exported_image in pairs(image_table) do
    -- Extract filename, e.g DSC9784.ARW -> DSC9784
    filename = string.upper(string.gsub(image.filename,"%.%w*", ""))
    -- Handle duplicates
    filename = addDuplicateIndex( image.duplicate_index, filename )
    -- Extract extension from exported image (user can choose JPG or PNG), e.g DSC9784.JPG -> .JPG
    extension = string.match(exported_image,"%.%w*$")

    local image_title, image_description, image_longitude, image_latitude, image_exif_datetime_taken, image_creator
    if (image.title and image.title ~= "") then
      image_title = ds.escape_xml_characters(image.title)
    else
      image_title = filename..extension
    end
    
    image_description = ds.escape_xml_characters(image.description)
    image_longitude   = string.gsub(tostring(image.longitude),",", ".")
    image_latitude 	  = string.gsub(tostring(image.latitude),",", ".")
    image_exif_datetime_taken = string.gsub(image.exif_datetime_taken," ", "T")
    image_creator     = ds.escape_xml_characters(image.creator)
  end
 
  local sendToWordPressCommand = "curl DO SOMETHING"  --ToDo
  dsys.external_command(sendToWordPressCommand)

end

-- Preferences

local defaultDir = ''
if dt.configuration.running_os == "windows" then
  defaultDir = os.getenv("USERPROFILE")
elseif dt.configuration.running_os == "macos" then
  defaultDir =  os.getenv("home")
else
  local handle = io.popen("xdg-user-dir DESKTOP")
  defaultDir = handle:read()
  handle:close()
end

dt.preferences.register("wordpress_export",
  "ExportDirectory",
  "directory",
  _("WordPress export: Export directory"),
  _("A directory that will be used to export the files"),
  defaultDir )

if dt.configuration.running_os ~= "linux" then  
  dt.preferences.register("wordpress_export", 
    "curlPath",	-- name
	"file",	-- type
	_("WordPress export: curl binary Location"),	-- label
	_("Install location of curl[.exe]. Requires restart to take effect."),	-- tooltip
	"curl")	-- default
end  


--https://www.darktable.org/lua-api/ar01s02s54.html.php
local post_titel = dt.new_widget("entry")
{
    text = _("Titel"), 
    placeholder = "placeholder",
    editable = true,
    tooltip = _("Tooltip Text"),
    reset_callback = function(self) self.text = "text" end
}

local post_category = dt.new_widget("entry")
{
    text = _("Category"), 
    placeholder = "placeholder",
    editable = true,
    tooltip = _("Tooltip Text"),
    reset_callback = function(self) self.text = "text" end
}

local post_tags = dt.new_widget("entry")
{
    text = _("Tags"), 
    placeholder = "placeholder",
    editable = true,
    tooltip = _("Tooltip Text"),
    reset_callback = function(self) self.text = "text" end
}

local widgets_list = {}

--if not df.check_if_bin_exists("curl") then
--  table.insert(widgets_list, df.executable_path_widget({"curl"}))
--end
table.insert(widgets_list, post_titel)
table.insert(widgets_list, post_category)
table.insert(widgets_list, post_tags)



local module_widget = dt.new_widget("box") {
  orientation = "vertical",
  table.unpack(widgets_list)
}

-- Register
dt.register_storage("wordpress_export",
					_("WordPress Export"), 
					nil, 
					export,
					nil,
					nil,
					module_widget)

-- vim: shiftwidth=2 expandtab tabstop=2 cindent syntax=lua
-- kate: hl Lua;
