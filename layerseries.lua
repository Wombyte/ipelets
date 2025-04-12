label = "Layer Series"

about = [[
Create series of layers with different options.
]]

revertOriginal = _G.revertOriginal


local function mainWindow(model)
   if model.ui.win == nil then
      return model.ui
   else
      return model.ui:win()
   end
end
   
local function getActiveLayerIndex(page, view)
	local layerName = page:active(view)
	for i,name in pairs(page:layers()) do
		if name == layerName then
			return i
		end
	end
end

local function copyView(page, curView, newView)
	local curShownLayers = page:layers()
	page:insertView(newView, page:active(curView))
	for _, layer in ipairs(curShownLayers) do
		if page:visible(curView, layer) then
			page:setVisible(newView, layer, true)
		end
	end
end

local function createLayerSeries(page, curView, layerNames, numberOfLayers, onlyLayers)
	local activeLayerIndex = getActiveLayerIndex(page, curView)
		
	if onlyLayers then
		for i,name in ipairs(layerNames) do
			page:addLayer(name)
			page:moveLayer(name, activeLayerIndex + i)
		end
		return
	end

	-- create <seriesNumber> many copies of the current view
	for i = 1,numberOfLayers do 
		copyView(page, curView, curView + i)
	end

	-- create new layers and set visibility
	for i,name in ipairs(layerNames) do
		page:addLayer(name)
		for j = i,(page:countViews()-curView) do
			page:setVisible(curView + j, name, true)
		end
		page:moveLayer(name, activeLayerIndex + i)
		page:setActive(curView + i, name)
	end
end


---

local function askForSeriesData(model)
   local dialog = ipeui.Dialog(mainWindow(model), "Input name and size of the layer series.")
   dialog:add("seriesNameLabel", "label", { label="Name:" }, 1, 1, 1, 1)
   dialog:add("seriesName", "input", {}, 1, 2, 1, 3)
   dialog:add("seriesNumberLabel", "label", { label="Size:" }, 2, 1, 1, 1)
   dialog:add("seriesNumber", "input", {}, 2, 2, 1, 3)
   dialog:add("seriesStartLabel", "label", { label="Start:" }, 3, 1, 1, 1)
   dialog:add("seriesStartNumber", "input", {}, 3, 2, 1, 3)
   dialog:add("onlyLayers", "checkbox", { label="Create only Layers", }, 4, 1, 1, 4)
   dialog:add("cancel", "button", { label="&Cancel", action="reject" }, 5, 1, 1, 2)
   dialog:add("ok", "button", { label="&Ok", action="accept" }, 5, 3, 1, 2)
   local accepted = dialog:execute()

   local seriesName = dialog:get("seriesName")
   if seriesName == "" then return end

   local seriesNumber = dialog:get("seriesNumber")
   if seriesNumber == "" or seriesNumber:find("%D") then return end

   local seriesStartNumber = dialog:get("seriesStartNumber")
   if seriesStartNumber == "" or seriesStartNumber:find("%D") then return end

   return accepted, seriesName, tonumber(seriesNumber), tonumber(seriesStartNumber), dialog:get("onlyLayers")
end

local function layerNamesFromPrefix(prefix, numberOfLayers, startNumber)
    local names = {}
	local sanitizedPrefix, _ = string.gsub(prefix, " ", "_")
    for i = startNumber,startNumber+numberOfLayers-1 do
		local layerName = sanitizedPrefix .. "_" .. i
        table.insert(names, layerName)
    end
    return names
end

function fromPrefix(model)
	local accepted, seriesName, seriesNumber, seriesStartNumber, onlyLayers = askForSeriesData(model)
	if not accepted then 
		return
	end
	if not seriesName then 
		model:warning("Please insert a valid series name")
		return
	end

	local t = { 
		label = "create layer series from prefix+number",
	    pno = model.pno,
		vno = model.vno,
		selection = model:selection(),
		original = model:page():clone(),
		seriesName = seriesName,
		seriesNumber = seriesNumber,
		seriesStartNumber = seriesStartNumber,
		onlyLayers = onlyLayers,
		undo = _G.revertOriginal,
   	}

	t.redo = function (t, doc)
		local page = doc[t.pno]
		local curView = t.vno

		local layerNames = layerNamesFromPrefix(t.seriesName, t.seriesNumber, t.seriesStartNumber)
		createLayerSeries(page, curView, layerNames, t.seriesNumber, t.onlyLayers)
	end

	model:register(t)
end

---

local function askForOnlyLayers(model)
   local dialog = ipeui.Dialog(mainWindow(model), "Do you want to create views too?")
   dialog:add("onlyLayers", "checkbox", { label="Create only Layers", }, 1, 1, 1, 4)
   dialog:add("cancel", "button", { label="&Cancel", action="reject" }, 2, 1, 1, 2)
   dialog:add("ok", "button", { label="&Ok", action="accept" }, 2, 3, 1, 2)
   local accepted = dialog:execute()

   return accepted, dialog:get("onlyLayers")
end

local function all_trim(s)
   return s:match( "^%s*(.-)%s*$" )
end

local function splitStringByBackslash(inputString)
    local lines = {}
	local size = 0
    for line in inputString:gmatch("[^\r\n]+") do
		local sanitized, _ = string.gsub(all_trim(line), " ", "_")
        table.insert(lines, sanitized)
		size = size + 1
    end
    return lines, size
end

function fromParagraph(model)
	local page = model:page()
	local prim = page:primarySelection()
  	if not prim or page[prim]:type() ~= "text" then
		model:warning("Please select a paragraph.")
		return
	end
	local origText = page[prim]
	local layerNames, numberOfLayers = splitStringByBackslash(origText:text())

	local accepted, onlyLayers = askForOnlyLayers(model)
	if not accepted then 
		return 
	end

	local t = { 
		label = "create layer series from paragraph",
	    pno = model.pno,
		vno = model.vno,
		selection = model:selection(),
		original = model:page():clone(),
		layerNames = layerNames,
		numberOfLayers = numberOfLayers,
		onlyLayers = onlyLayers,
		paragraphObjNum = prim,
		undo = _G.revertOriginal,
   	}

	t.redo = function (t, doc)
		local page = doc[t.pno]
		local curView = t.vno
		
		createLayerSeries(page, curView, t.layerNames, t.numberOfLayers, t.onlyLayers)

		page:remove(t.paragraphObjNum)

	end

	model:register(t)
end



methods = {
  { label = "from Prefix+Number", run=fromPrefix},
  { label = "from Paragraph", run=fromParagraph}
}