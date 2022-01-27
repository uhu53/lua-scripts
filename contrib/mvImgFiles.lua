--[[
    mvImgFiles.lua

    - 'Move Image Files' to a directory of choice and remove the associated
	   images from lighttable - Moves *.xmp and orphan *.<raw> files 
    - Possibility to undo a move of the image files and restore the associated images in lighttable
]]
--[[	 

	 The script shall make the functionality of darktable (dt) easier to act
	 as a general purpose raw image viewer and image selection tool .

	 * when you press a hot key - suggested is 'alt+d' - the script removes
	   the selected images in lighttable and moves the associated image
	   files to a directory of your choice - default is 'delImg' under the
	   image directory. The script moves *.xmp and orphan *.<raw> files.

	*  you have to define the hotkey under: dt preferences / hotkeys / lua scripts
	   / mvImgFiles

	*  you can change the target directory 'delImg' under: dt preferences / 
	   lua options / 'remove target directory'

	 * the script features under 'selected images' a button 'undo last
	   mvImgFiles'. It works like the undo function of an editor
	   (ctrl-z). It moves the image files of the last 'alt+d' action back to
	   the image directory, puts in lighttable the associated images in
	   place and sets the selection to them. A next press of the button
	   'undo last mvImgFiles' puts the images of the yet last move action in
	   place.

	 * this button works per darktable session.

	 * however you can easily put back manually the removed images of a
	   previous session: 

	   * in a file browser move any image files under the specific 'remove
	     target directory' back to the image directory

	   * run the dt-function 'add to library' on the entire image directory as a
	     whole to force a rebuild of the lighttable view. 

	   * That's it, the "missed" images are in place again.
]]

local dt = require "darktable"
local du = require "lib/dtutils"
local df = require "lib/dtutils.file"
local dtsys = require "lib/dtutils.system"
local gettext = dt.gettext
local gui = dt.gui
local dbg = require "darktable.debug"
local pkg = require "package"

local dbg = false
local rdbg = false
if rdbg then
	mobdbg = require('mobdebug')																-- remote dbg with zbstudio
	mobdbg.start()
end

local script_data = {}
script_data.destroy = nil																		-- function to destory the script
script_data.destroy_method = nil																-- set to hide for libs since we can't destroy them commpletely yet, otherwise leave as nil
script_data.restart = nil																		-- how to restart the (lib) script after it's been hidden - i.e. make it visible again

--[[
	table mvdImgFilesT
	fields: nrOfMveAction, {srcPath, fileName, dstPath}
]]
local mvdImgFilesT = {}

local MODULE_NAME = 'mvImgFiles'

-- Path Separator PS
local PS = dt.configuration.running_os == "windows" and "\\" or "/"

local DELDIR = dt.preferences.read(MODULE_NAME, "deldir", "string")

if du.check_min_api_version("7.0.0", MODULE_NAME) ~= nil then
	dt.print("minimal api_version is: '7.0.0';\nversion found: "..dt.configuration.api_version_string)
	dt.print("Aborting...")
	return
end

;																										-- ----------------------
local function destroy()																		-- destroy
;																										-- ----------------------
	dt.destroy_event(MODULE_NAME, "shortcut") 
	dt.gui.libs.image.destroy_action(MODULE_NAME)
	if dbg then pkg.loaded[MODULE_NAME] = false end
end

;																										-- ----------------------
local function doNothing()																		-- doNothing
;																										-- ----------------------
	return
end

;																										-- ----------------------
local function chkMvPath(imgPath)															-- chkMvPath
;																										-- ---------------------
	local mvPath = imgPath..DELDIR
	mvPath = df.sanitize_filename(mvPath)
	if (df.check_if_file_exists(mvPath)) == false then
		local rslt = df.mkdir(mvPath)															-- ?? how to check rslt?
	end
end	

;																										-- ----------------------
local function mvImgFiles(event, shortcut)												-- mvImgFiles
;																										-- ----------------------
	if rdbg then mobdbg.on(); end

	local nrMveAction = #mvdImgFilesT + 1
;																										-- ----------------------
	local function mvBaseFile(srcDir, imgFName)											-- --- mvBaseFile
;																										-- ----------------------
		local imgName = string.gsub(imgFName, "%.%w%w%w$", "")
		local jpgFile = imgName..".JPG"

		local rslt
		local delDir = srcDir..DELDIR
		local nrOfFiles = 0
		local listCmd = "ls -1 "..srcDir..PS..imgName..".*"
		local findRslt = io.popen(listCmd)
		for line in findRslt:lines() do
			nrOfFiles = nrOfFiles + 1
		end
		if nrOfFiles == 1 then
			rslt = df.file_move(srcDir..PS..imgFName, delDir)
			table.insert(mvdImgFilesT[nrMveAction], {srcDir, imgFName, delDir})
			if df.check_if_file_exists(srcDir..PS..".."..PS..jpgFile) then
				df.file_move(srcDir..PS..".."..PS..jpgFile, delDir)
				table.insert(mvdImgFilesT[nrMveAction], {srcDir..PS, jpgFile, delDir})
			end
		end
		return
;																										-- ----------------------
	end																								-- --- end MvBaseFile
;																										-- ----------------------

	mvdImgFilesT[nrMveAction] = {}

	if not (dt.gui.current_view()) == "lighttable" then
		dt.print("active only in lighttable view")
		return
	end
	
	local imgsT
	if #dt.gui.selection() ~= 0 then
		imgsT = dt.gui.selection()
	else 
		imgsT = dt.gui.action_images
	end
	dt.gui.selection(imgsT)

	if imgsT[1] == nil then
		dt.print("no image selected")
		return
	end
	chkMvPath(imgsT[1].path)


	local askW = dt.new_widget("combobox")													-- to be done: ASK

	local srcDir, baseName, jpgFile, curImgName, oldImgName, sidecarName, sidecarFNamePath, rslt
	local delDir = DELDIR
	local msg = ".DNG, .DNG.xmp, .."..PS..".JPG moved to "..delDir..":\n"
	local pat = "[^"..PS.."]*$"
	local first = true

	for _,img in pairs(dt.gui.action_images) do
		srcDir = img.path
		delDir = img.path..DELDIR
		sidecarFNamePath = img.sidecar														-- a string
		
		sidecarName = string.match(img.sidecar, pat)
		curImgName = string.gsub(img.filename, "%.xmp$", "")
		curImgName = string.gsub(curImgName, "_%d%d(%.%w%w%w)$", "%1")
		if dbg then
			dt.print_log("fName: "..img.filename.. " sideCar: "..img.sidecar.. " duplIdx: "..img.duplicate_index)
			dt.print_log("database: "..tostring(dt.database.get_image(img.id)))
		end
		if first then
			oldImgName = curImgName
			first = false
		end

		if curImgName ~= oldImgName then
			mvBaseFile(srcDir, oldImgName, nrMveAction)
			oldImgName = curImgName
		end

		img.delete(img)																			-- remove from database
		rslt = df.file_move(sidecarFNamePath, delDir)
		table.insert(mvdImgFilesT[nrMveAction], {srcDir, sidecarName, delDir})
	end
	mvBaseFile(srcDir, curImgName, nrMveAction)
	dt.database.import(srcDir)
	if rdbg then doNothing() end
end

;																										-- ----------------------
local function undoMove(event, someVar)													-- undoMove
;																										-- ----------------------
   local reactvdImgsT = {}
	local srcDir, dstDir, curImgFName, oldImgFName, 									-- cur/oldImgFName the sidecar- or raw-img file
		curImgName, oldImgName, 																-- the base raw-img file name
		sdCarFName, oldSdCarFName,
		imgO, id, sdCarName
	local first = true
	local imgGrp = {}
	local pat = "[^"..PS.."]*$"

	local function reInsertImg(imgName, reactvdImgsT, oldSidecarFName)
		if rdbg then mobdbg.on() end

		imgO = dt.database.import(dstDir..PS..imgName)									-- imgO = the group header img
		imgGrp = imgO.get_group_members(imgO)
		for idx, img in ipairs(imgGrp) do
			img.delete(img)																		-- force a subsequent import of the
		end
		imgO = dt.database.import(dstDir..PS..imgName)									-- get the head of the newly imported img.group 
		imgGrp = imgO.get_group_members(imgO)															--     img.ids of the associated versions
		for idx, img in ipairs(imgGrp) do
			sdCarName = string.match(img.sidecar, pat)
			if sdCarName == oldSidecarFName then
				table.insert(reactvdImgsT, img)
			end
		end
		return reactvdImgsT
	end

	if rdbg then mobdbg.on(); end

	local idx = #mvdImgFilesT
	if idx == 0 then
		dt.print("There are NO moved imgFiles")
		return
	end

	for _, mvInfo in ipairs(mvdImgFilesT[idx]) do
		srcDir = mvInfo[3]
		curImgFName = mvInfo[2]
		dstDir = mvInfo[1]
		df.file_move(srcDir..PS..curImgFName, dstDir)

		if not string.match(string.upper(curImgFName), "%.JPG$") then					-- mvd .JPG-files
			sdCarFName = curImgFName
			curImgName = string.gsub(curImgFName, "%.xmp$", "")
			curImgName = string.gsub(curImgName, "_%d%d(%.%w%w%w)$", "%1")
			if first then 
				oldImgName = curImgName
				oldSdCarFName = sdCarFName
				first = false
			end
			if curImgName ~= oldImgName then
				reactvdImgsT = reInsertImg(oldImgName, reactvdImgsT, oldSdCarFName)
				oldImgName = curImgName
				oldSdCarFName = sdCarFName
			end
		end
	end
	reactvdImgsT = reInsertImg(curImgName, reactvdImgsT, oldSdCarFName)
	dt.gui.selection(reactvdImgsT)
	mvdImgFilesT[idx] = nil																		-- table.remove(t,idx) does not work reliably
	if rdbg then doNothing() end
end

;																										-- Register
;																										-- ----------------------
dt.register_event(MODULE_NAME, "shortcut", mvImgFiles, MODULE_NAME)

dt.register_event(
	MODULE_NAME, "exit",
	function() 	
		mvdImgFilesT = {}
	end
)

dt.gui.libs.image.register_action(
	MODULE_NAME, "undo last "..MODULE_NAME,
	function(event, mvdImgFilesT) undoMove(event, someVar) end,
	"undo"..MODULE_NAME
)

local delDirDefault = "."..PS.."delImg"
dt.preferences.register(
	MODULE_NAME,
	"deldir",
	"string",
	"remove target directory",
	"where to move unwanted image files",
	delDirDefault
)

--script_data.destroy_method = "hide"
script_data.destroy = destroy
--script_data.show = show
--script_data.restart = restart

return script_data
