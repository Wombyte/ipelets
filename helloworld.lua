label = "My Helpers"

about = [[
A set of helper ipelets
]]

revertOriginal = _G.revertOriginal

function connectDots(model)
	local page = model:page()
	-- check selection
	local marks = {}
	for i,obj,sel,layer in page:objects() do
		if obj:symbol():sub(1,5) == "mark/" and sel ~= nil then
			marks[#marks + 1] = obj:matrix() * obj:position()
		end
	end
	if #marks ~= 2 then 
		model:warning("Please select exactly two marks.")
		return
	end
	-- create connection
	local seg = { type="curve", closed=true }
	seg[1] = { type="segment", marks[1], marks[2] }
	local edge = ipe.Path(model.attributes, { seg } )
	model:creation("create Edge", edge)
end

function splitStringByBackslash(inputString, model)
    local lines = {}
    for line in inputString:gmatch("([^\n]*)\n?") do
		if line ~= "" then
        	table.insert(lines, line)
		end
    end
    return lines
end

function extract_attributes(obj, model)
    local attr = {}

    local keys = {
		"pathmode", "stroke", "fill", "dashstyle", "pen", "farrow", "rarrow", 
		"farrowshape", "rarrowshape", "symbolsize", "textsize", "transformabletext",
		"textstyle", "opacity", "tiling", "decoration", "minipage",
		"width", "horizontalalignment", "verticalalignment", "linejoin",
		"linecap", "fillrule", "pinned", "transformations"
	}
	
    for _, key in ipairs(keys) do
        local value = obj:get(key)
        if value ~= nil and value ~= "undefined" then
			attr[key] = value
		end
    end

    return attr
end

function splitText(model)
	local page = model:page()
	local prim = page:primarySelection()
  	if not prim or page[prim]:type() ~= "text" then
		model:warning("Please select a paragraph.")
		return
	end

	local origText = page[prim]
	local lines = splitStringByBackslash(origText:text(), model)

	local t = { 
		label = "Split Text",
	    pno = model.pno,
	    vno = model.vno,
	    original = model:page():clone(),
		lines = lines,
		textObjNum = prim,
	    undo = _G.revertOriginal,
	}
   	t.redo = function (t, doc)
		local page = doc[t.pno]
		local origText = page[t.textObjNum]
		local attr = extract_attributes(origText, model)
		local matrix = origText:matrix()
		local pos = matrix * origText:position()
		local layer = page.layerOf(page, t.textObjNum)
      	for i,line in ipairs(lines) do
			local text = ipe.Text(attr, line, ipe.Vector(pos.x,pos.y))
			local transMat = ipe.Translation(i * 16, - i * 16)
			text:setMatrix(matrix * transMat)
			page:insert(nil, text, 1, layer)
		end
		page:remove(t.textObjNum)
		model:runLatex()
   	end
   	model:register(t)
end

-- cut paragraphs

function isSingleLineSegment(model, obj)
	if obj:type() ~= "path" then
		model:warning("Please have a single line as primary selection")
		return
	end
	local shape = obj:shape()
	if #shape ~= 1 then
		model:warning("Please have a single line as primary selection")
		return
	end
	local subpath = shape[1]
	if subpath.type ~= "curve" or #subpath ~= 1 then
		model:warning("Please have a single line as primary selection")
		return 
	end
	local line = subpath[1]
	if line.type ~= "segment" then
		model:warning("Please have a single line as primary selection")
		return
	end
	return line, obj:matrix()
end

function cutParagraphs(model)
	local page = model:page()
	local prim = page:primarySelection()
	if not prim then model:warning("No Selection") return end

	local line, matrix = isSingleLineSegment(model, page[prim])
	if not line then return end

	if line[1].y == line[2].y then
		model:warning("The selected line may not be horizontal")
		return
	end

	local a = matrix * line[1]
	local b = matrix * line[2]

	local function getCrossX(y) return a.x + ((y - a.y) / (b.y - a.y)) * (b.x - a.x) end

	local t = { 
		label = "Cut Paragraphs",
	    pno = model.pno,
	    vno = model.vno,
	    original = model:page():clone(),
	    getCrossX = getCrossX,
		lineObjNum = prim,
	    undo = _G.revertOriginal,
	}
   	t.redo = function (t, doc)
		local page = doc[t.pno]
      	for i, obj, sel, _ in page:objects() do
			if sel and obj:type() == "text" and obj:get("minipage") == true then
				local pos = obj:matrix() * obj:position()
				local _, height, _ = obj:dimensions()
				local crossX = math.min(t.getCrossX(pos.y), t.getCrossX(pos.y - height))
				page:setAttribute(i, "width", crossX - pos.x)
			end
		end
		page:remove(t.lineObjNum)
		model:runLatex()
   	end
   	model:register(t)
end

-- curly Bracket

function isRect(obj)
	if obj:type() ~= "path" then return end
	local shape = obj:shape()

	if #shape ~= 1 then return end
	local subpath = shape[1]

	if subpath.type ~= "curve" or not subpath.closed or #subpath ~= 3 then return end
	for _,segment in ipairs(subpath) do
		if segment.type ~= "segment" then return end
	end
	local a = obj:matrix() * subpath[1][1]
	local b = obj:matrix() * subpath[2][1]
	local c = obj:matrix() * subpath[3][1]
	local d = obj:matrix() * subpath[3][2]

	local left = math.min(a.x, b.x, c.x, d.x)
	local right = math.max(a.x, b.x, c.x, d.x)
	local bottom = math.min(a.y, b.y, c.y, d.y)
	local top = math.max(a.y, b.y, c.y, d.y)

	return left, right, bottom, top
end

local function arc(center, radius, v1, v2)
	local a = ipe.Arc(ipe.Matrix(radius, 0, 0, radius, center.x, center.y))
	return { type="curve", closed=false; { type="arc", arc=a; v1, v2 } }
end

local function segment(a, b)
	return { type="curve", closed=false; { type="segment", a, b } }
end

local function mainWindow(model)
   if model.ui.win == nil then
      return model.ui
   else
      return model.ui:win()
   end
end

local function ask_for_direction(model)
   local dialog = ipeui.Dialog(mainWindow(model), "Select a direction.")
   local dirs = { "left", "right", "bottom", "top" }
   dialog:add("direction", "combo", dirs, 1, 1, 1, 2)
   dialog:add("ok", "button", { label="&Ok", action="accept" }, 2, 2)
   dialog:add("cancel", "button", { label="&Cancel", action="reject" }, 2, 1)
   local r = dialog:execute()
   if not r then return end
   return dirs[dialog:get("direction")]
end

local function rightBracketData(left, right, bottom, top) 
	local halfWidth = (left + right) / 2 - left
	local halfHeight = (bottom + top) / 2 - bottom

	return halfWidth, {
		ipe.Vector(left, top),
		ipe.Vector(left, top - halfWidth),
		ipe.Vector(left + halfWidth, top - halfWidth),
		ipe.Vector(left + halfWidth, top - halfHeight + halfWidth),
		ipe.Vector(right, top - halfHeight + halfWidth),
		ipe.Vector(right, top - halfHeight),
		ipe.Vector(right, top - halfHeight - halfWidth),
		ipe.Vector(left + halfWidth, bottom + halfHeight - halfWidth),
		ipe.Vector(left + halfWidth, bottom + halfWidth),
		ipe.Vector(left, bottom + halfWidth),
		ipe.Vector(left, bottom)
	}
end

local function leftBracketData(left, right, bottom, top) 
	local halfWidth = (left + right) / 2 - left
	local halfHeight = (bottom + top) / 2 - bottom

	return halfWidth, {
		ipe.Vector(right, bottom),
		ipe.Vector(right, bottom + halfWidth),
		ipe.Vector(right - halfWidth, bottom + halfWidth), -- knot
		ipe.Vector(right - halfWidth, bottom + halfHeight - halfWidth), -- knot
		ipe.Vector(left, bottom + halfHeight - halfWidth),
		ipe.Vector(left, bottom + halfHeight), -- knot
		ipe.Vector(left, bottom + halfHeight + halfWidth),
		ipe.Vector(right - halfWidth, top - halfHeight + halfWidth), -- knot
		ipe.Vector(right - halfWidth, top - halfWidth), -- knot
		ipe.Vector(right, top - halfWidth),
		ipe.Vector(right, top)
	}
end

local function bottomBracketData(left, right, bottom, top) 
	local halfWidth = (left + right) / 2 - left
	local halfHeight = (bottom + top) / 2 - bottom

	return halfHeight, {
		ipe.Vector(right, top),
		ipe.Vector(right - halfHeight, top),
		ipe.Vector(right - halfHeight, top - halfHeight), -- knot
		ipe.Vector(right - halfWidth + halfHeight, bottom + halfHeight), -- knot
		ipe.Vector(right - halfWidth + halfHeight, bottom),
		ipe.Vector(right - halfWidth, bottom), -- knot
		ipe.Vector(left + halfWidth - halfHeight, bottom),
		ipe.Vector(left + halfWidth - halfHeight, bottom + halfHeight), -- knot
		ipe.Vector(left + halfHeight, top - halfHeight), -- knot
		ipe.Vector(left + halfHeight, top),
		ipe.Vector(left, top)
	}
end

local function topBracketData(left, right, bottom, top) 
	local halfWidth = (left + right) / 2 - left
	local halfHeight = (bottom + top) / 2 - bottom

	return halfHeight, {
		ipe.Vector(left, bottom),
		ipe.Vector(left + halfHeight, bottom),
		ipe.Vector(left + halfHeight, bottom + halfHeight), -- knot
		ipe.Vector(left + halfWidth - halfHeight, top - halfHeight), -- knot
		ipe.Vector(left + halfWidth - halfHeight, top),
		ipe.Vector(left + halfWidth, top), -- knot
		ipe.Vector(right - halfWidth + halfHeight, top),
		ipe.Vector(right - halfWidth + halfHeight, top +- halfHeight), -- knot
		ipe.Vector(right - halfHeight, bottom + halfHeight), -- knot
		ipe.Vector(right - halfHeight, bottom),
		ipe.Vector(right, bottom)
	}
end

function curlyBracket(model)
	local page = model:page()
	local prim = page:primarySelection()
	if not prim then model:warning("No Selection") return end
	
	local left, right, bottom, top = isRect(page[prim])
	if not left then 
		model:warning("Please have a rectangle as primary selection 3")
		return 
	end

	local dir = ask_for_direction(model)
	if not dir then return end

	local dataFunctions = {
		right=rightBracketData,
		left=leftBracketData,
		bottom=bottomBracketData,
		top=topBracketData
	}

	local func = dataFunctions[dir]
	if (not func) then return end
	
	local radius, p = func(left, right, bottom, top)

	local t = { 
		label = "Create Curly Bracket",
	    pno = model.pno,
	    vno = model.vno,
	    original = model:page():clone(),
	    radius = radius,
		p = p,
		rectObjNum = prim,
	    undo = _G.revertOriginal,
	}
   	t.redo = function (t, doc)
		local page = doc[t.pno]
		local bracket = ipe.Path(model.attributes, { 
			arc(t.p[2], t.radius, t.p[3], t.p[1]),
			segment(t.p[3], t.p[4]),
			arc(t.p[5], t.radius, t.p[4], t.p[6]),
			arc(t.p[7], t.radius, t.p[6], t.p[8]),
			segment(t.p[8], t.p[9]),
			arc(t.p[10], t.radius, t.p[11],t.p[9])
		} )
		page:insert(nil, bracket, 1, page.layerOf(page, t.rectObjNum))
		page:remove(t.rectObjNum)
   	end
   	model:register(t)
end





methods = {
  { label = "Connect dots", run=connectDots },
  { label = "Split Text", run=splitText },
  { label = "Cut Paragraphs", run=cutParagraphs },
  { label = "Curly Bracket", run=curlyBracket }
}
