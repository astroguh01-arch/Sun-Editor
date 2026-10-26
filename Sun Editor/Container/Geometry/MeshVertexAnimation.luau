--!nocheck

local require = require(script:FindFirstAncestor("Container").Require)

local AssetService = game:GetService("AssetService")
local Selection = game:GetService("Selection")
local NativeInput = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local MeshAccess = require("MeshAccess")
local Paths = require("Paths")
local Vertex = {}

local PREFIX = "SunVertex:"
local editable = setmetatable({}, { __mode = "k" })
local resolvedTracks = setmetatable({}, { __mode = "k" })
local archiveCache = setmetatable({}, { __mode = "k" })
local window
local marker
local vertexHandles = {}
local refreshVertexWindow
local activeVertex
local refs = {}
local connections, lifecycleConnections, rowConnections = {}, {}, {}

local function packPath(path)
	return (path:gsub(".", function(char)
		return string.format("%02x", string.byte(char))
	end))
end

local function unpackPath(encoded)
	if type(encoded) ~= "string" or #encoded % 2 ~= 0 or encoded:find("[^%x]") then
		return nil
	end

	local bytes = table.create(#encoded / 2)
	for index = 1, #encoded, 2 do
		bytes[#bytes + 1] = string.char(tonumber(encoded:sub(index, index + 1), 16))
	end
	return table.concat(bytes)
end

local function createBoxMesh(part)
	local half = part.Size * 0.5
	local mesh = AssetService:CreateEditableMesh()
	assert(mesh, "Roblox could not allocate editable geometry for this part")
	local vertices = {
		mesh:AddVertex(Vector3.new(-half.X, -half.Y, -half.Z)),
		mesh:AddVertex(Vector3.new(half.X, -half.Y, -half.Z)),
		mesh:AddVertex(Vector3.new(half.X, half.Y, -half.Z)),
		mesh:AddVertex(Vector3.new(-half.X, half.Y, -half.Z)),
		mesh:AddVertex(Vector3.new(-half.X, -half.Y, half.Z)),
		mesh:AddVertex(Vector3.new(half.X, -half.Y, half.Z)),
		mesh:AddVertex(Vector3.new(half.X, half.Y, half.Z)),
		mesh:AddVertex(Vector3.new(-half.X, half.Y, half.Z)),
	}
	for _, triangle in {
		{ 1, 3, 2 }, { 1, 4, 3 },
		{ 5, 6, 7 }, { 5, 7, 8 },
		{ 1, 5, 8 }, { 1, 8, 4 },
		{ 2, 3, 7 }, { 2, 7, 6 },
		{ 4, 8, 7 }, { 4, 7, 3 },
		{ 1, 2, 6 }, { 1, 6, 5 },
	} do
		mesh:AddTriangle(vertices[triangle[1]], vertices[triangle[2]], vertices[triangle[3]])
	end
	return mesh
end

function Vertex.parseId(id)
	if type(id) ~= "string" then
		return nil
	end
	local vertexId, encoded = id:match("^SunVertex:(%d+):([%x]+)$")
	local path = unpackPath(encoded)
	if not vertexId or not path then
		return nil
	end
	return tonumber(vertexId), path
end

function Vertex.isTrack(id)
	return Vertex.parseId(id) ~= nil
end

function Vertex.trackId(part, rig, vertexId)
	assert(part and part:IsA("MeshPart"), "Select a MeshPart")
	assert(part == rig or part:IsDescendantOf(rig), "The mesh must be inside the active animation rig")
	local path = Paths.of(part, rig)
	assert(path, "Could not create a stable path to the mesh")
	return PREFIX .. tostring(vertexId) .. ":" .. packPath(path)
end

local function resolveTrack(rig, id)
	local vertexId, path = Vertex.parseId(id)
	assert(vertexId and path, "Invalid vertex animation track")
	local cache = resolvedTracks[rig]
	if not cache then
		cache = {}
		resolvedTracks[rig] = cache
	end
	local resolved = cache[id]
	if not resolved or not resolved.part.Parent or not resolved.part:IsDescendantOf(rig) then
		local part = Paths.resolve(rig, path)
		assert(part and part:IsA("MeshPart"), "The animated mesh is missing from this rig")
		resolved = { part = part, vertexId = vertexId }
		cache[id] = resolved
	end
	return resolved.part, resolved.vertexId
end

local function meshFor(part)
	assert(part and part:IsA("MeshPart") and part.Parent, "MeshPart is unavailable")
	local record = editable[part]
	if record and record.mesh and part.Parent then
		return record.mesh
	end

	local content = part.MeshContent
	local sourceType = content.SourceType
	local generatedFallback = false
	if sourceType == Enum.ContentSourceType.None then
		-- Some imported MeshParts expose an empty MeshContent value while the
		-- legacy MeshId still contains the asset URI. Use that URI as a fallback.
		local meshId = tostring(part.MeshId)
		if meshId ~= "" then
			local ok, uriContent = pcall(Content.fromUri, meshId)
			if ok then
				content = uriContent
				sourceType = content.SourceType
			end
		end
	end
	local object = content.Object
	local mesh
	local alreadyLinked = false
	if sourceType == Enum.ContentSourceType.None then
		-- Generated R6/R15 body placeholders can be MeshParts with no MeshId.
		-- Give them a box mesh matching their current bounds so vertex editing
		-- remains usable without an imported asset.
		mesh = createBoxMesh(part)
		generatedFallback = true
	elseif sourceType == Enum.ContentSourceType.Object and object and object:IsA("EditableMesh") then
		mesh = object
		alreadyLinked = true
	else
		mesh = MeshAccess.open(content)
		assert(mesh, "Roblox did not return editable mesh geometry")
	end
	if not alreadyLinked then
		local staging = AssetService:CreateMeshPartAsync(Content.fromObject(mesh), {
			CollisionFidelity = part.CollisionFidelity,
			RenderFidelity = part.RenderFidelity,
		})
		pcall(function()
			staging.TextureContent = part.TextureContent
		end)
		local linked, linkError = pcall(function()
			part:ApplyMesh(staging)
		end)
		staging:Destroy()
		assert(linked, "Roblox could not link the EditableMesh to this MeshPart: " .. tostring(linkError))
	end

	editable[part] = { mesh = mesh, generatedFallback = generatedFallback }
	return mesh
end

function Vertex.read(rig, id)
	local part, vertexId = resolveTrack(rig, id)
	local mesh = meshFor(part)
	return mesh:GetPosition(vertexId)
end

function Vertex.write(rig, id, position)
	assert(typeof(position) == "Vector3", "Vertex positions must be Vector3 values")
	local part, vertexId = resolveTrack(rig, id)
	local mesh = meshFor(part)
	if mesh:GetPosition(vertexId) ~= position then
		mesh:SetPosition(vertexId, position)
	end
	if activeVertex and activeVertex.rig == rig and activeVertex.trackId == id and marker then
		marker.CFrame = CFrame.new(position)
	end
end

function Vertex.definition(rig, id)
	local vertexId, path = Vertex.parseId(id)
	if not vertexId then
		return nil
	end
	local part
	pcall(function()
		part = resolveTrack(rig, id)
	end)
	return {
		id = id,
		label = string.format("%s · vertex %d", part and part.Name or "Mesh", vertexId),
		kind = "Vector3",
	}
end

local function readArchive(sequence)
	if archiveCache[sequence] ~= nil then
		return archiveCache[sequence] or nil
	end
	local folder = sequence and sequence:FindFirstChild("SunProperties")
	if not folder then
		archiveCache[sequence] = false
		return nil
	end
	local Chunks = require("ChunkStore")
	local Document = require("Document")
	local data = Document.unpack(Chunks.read(folder))
	local vertexRows = {}
	for _, row in data.tracks or {} do
		if Vertex.isTrack(row.id) and row.enabled ~= false and row.disabled ~= true then
			table.insert(vertexRows, row)
			local keys = {}
			for _, key in row.keys or {} do
				local value = typeof(key.PropertyValue) == "Vector3" and key.PropertyValue
					or key.C0 and key.C0.Position
				local keyTime = tonumber(key.Time) or tonumber(key.Frame)
				if not key.Disabled and typeof(value) == "Vector3" and keyTime ~= nil then
					table.insert(keys, {
						time = keyTime,
						value = value,
						easing = key.EasingStyle,
						direction = key.EasingDirection,
					})
				end
			end
			table.sort(keys, function(a, b)
				return a.time < b.time
			end)
			row._sunVertexKeys = keys
		end
	end
	data._sunVertexTracks = vertexRows
	archiveCache[sequence] = data
	return data
end

local function sample(row, time)
	local keys = row._sunVertexKeys or {}
	local low, high = 1, #keys + 1
	while low < high do
		local middle = math.floor((low + high) / 2)
		if keys[middle] and keys[middle].time <= time then
			low = middle + 1
		else
			high = middle
		end
	end
	local previous, following = keys[low - 1], keys[low]
	if not previous then
		return following and following.value or row.default
	end
	if not following or following.time <= previous.time then
		return previous.value
	end
	local alpha = math.clamp((time - previous.time) / (following.time - previous.time), 0, 1)
	if previous.easing and previous.easing ~= "Linear" then
		local Easing = require("Easing")
		local ok, eased = pcall(Easing.apply, alpha, {
			EasingStyle = previous.easing,
			EasingDirection = previous.direction or "InOut",
		})
		if ok and typeof(eased) == "number" then
			alpha = eased
		end
	end
	return previous.value:Lerp(following.value, alpha)
end

function Vertex.applySequence(sequence, rig, time)
	if not sequence or not rig then
		return false
	end
	local ok, data = pcall(readArchive, sequence)
	if not ok or not data then
		return false
	end
	local applied = false
	for _, row in data._sunVertexTracks or {} do
		local success, value = pcall(sample, row, time)
		if success and typeof(value) == "Vector3" then
			local written = pcall(Vertex.write, rig, row.id, value)
			applied = applied or written
		end
	end
	return applied
end

function Vertex.restoreSequence(sequence, rig)
	local ok, data = pcall(readArchive, sequence)
	if not ok or not data then
		return
	end
	for _, row in data._sunVertexTracks or {} do
		if typeof(row.default) == "Vector3" then
			pcall(Vertex.write, rig, row.id, row.default)
		end
	end
end

local function make(class, parent, name, properties)
	local item = Instance.new(class)
	item.Name = name
	for key, value in properties do
		item[key] = value
	end
	item.Parent = parent
	return item
end

local function clearConnections(list)
	for _, connection in list do
		connection:Disconnect()
	end
	table.clear(list)
end

local function close()
	clearConnections(connections)
	clearConnections(rowConnections)
	refreshVertexWindow = nil
	for _, handle in vertexHandles do
		handle:Destroy()
	end
	table.clear(vertexHandles)
	if marker then
		marker:Destroy()
		marker = nil
	end
	activeVertex = nil
	if window then
		window:Destroy()
		window = nil
	end
end

function Vertex.open()
	if window and window.Parent then
		window.Visible = not window.Visible
		if marker then marker.Visible = window.Visible and marker.Adornee ~= nil end
		for _, handle in vertexHandles do
			handle.Visible = window.Visible
		end
		if window.Visible and refreshVertexWindow then
			refreshVertexWindow()
		end
		return
	end
	local screen = refs.ScreenGui
	if not screen or not screen.Parent then
		return
	end
	local panel = make("Frame", screen, "SunMeshVertexPanel", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -22, 0.5, 0),
		Size = UDim2.fromOffset(340, 440), BackgroundColor3 = Color3.fromRGB(28, 22, 17),
		BorderSizePixel = 0, Active = true, ZIndex = 80,
	})
	window = panel
	make("UICorner", panel, "Corner", { CornerRadius = UDim.new(0, 10) })
	make("UIStroke", panel, "Stroke", { Color = Color3.fromRGB(119, 72, 34), Thickness = 1 })
	local header = make("Frame", panel, "Header", {
		Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = Color3.fromRGB(43, 29, 19), BorderSizePixel = 0, ZIndex = 81,
	})
	make("TextLabel", header, "Title", {
		Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -58, 1, 0), BackgroundTransparency = 1,
		Text = "MESH VERTEX ANIMATION", TextColor3 = Color3.fromRGB(247, 187, 105),
		Font = Enum.Font.GothamBold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 82,
	})
	local closeButton = make("TextButton", header, "Close", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = Color3.fromRGB(74, 43, 24), Text = "×", TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold, TextSize = 18, ZIndex = 82,
	})
	table.insert(connections, closeButton.Activated:Connect(close))
	make("TextLabel", panel, "Hint", {
		Position = UDim2.fromOffset(14, 52), Size = UDim2.new(1, -28, 0, 34), BackgroundTransparency = 1,
		Text = "Click a mesh vertex in the viewport to select it. Drag to move; release to key at the playhead.",
		TextColor3 = Color3.fromRGB(195, 181, 165), Font = Enum.Font.Gotham, TextSize = 11,
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 81,
	})
	local meshLabel = make("TextLabel", panel, "MeshLabel", {
		Position = UDim2.fromOffset(14, 90), Size = UDim2.new(1, -28, 0, 24), BackgroundTransparency = 1,
		Text = "No MeshPart selected", TextColor3 = Color3.fromRGB(230, 219, 202), Font = Enum.Font.GothamMedium,
		TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 81,
	})
	local filter = make("TextBox", panel, "VertexFilter", {
		Position = UDim2.fromOffset(14, 117), Size = UDim2.new(1, -28, 0, 26),
		BackgroundColor3 = Color3.fromRGB(49, 36, 26), TextColor3 = Color3.fromRGB(245, 232, 214),
		PlaceholderText = "Filter by vertex ID", Text = "", ClearTextOnFocus = false,
		Font = Enum.Font.Gotham, TextSize = 11, ZIndex = 81,
	})
	make("UICorner", filter, "Corner", { CornerRadius = UDim.new(0, 5) })
	local list = make("ScrollingFrame", panel, "Vertices", {
		Position = UDim2.fromOffset(14, 148), Size = UDim2.new(1, -28, 0, 148), BackgroundColor3 = Color3.fromRGB(19, 17, 15),
		BorderSizePixel = 0, ScrollBarThickness = 5, CanvasSize = UDim2.new(), ZIndex = 81,
	})
	make("UICorner", list, "Corner", { CornerRadius = UDim.new(0, 6) })
	local layout = make("UIListLayout", list, "Layout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder })
	local selectedLabel = make("TextLabel", panel, "SelectedVertex", {
		Position = UDim2.fromOffset(14, 302), Size = UDim2.new(1, -28, 0, 22), BackgroundTransparency = 1,
		Text = "Vertex: none", TextColor3 = Color3.fromRGB(247, 187, 105), Font = Enum.Font.GothamBold,
		TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 81,
	})
	local inputs = {}
	for index, axis in { "X", "Y", "Z" } do
		local box = make("TextBox", panel, "Position" .. axis, {
			Position = UDim2.fromOffset(14 + (index - 1) * 101, 330), Size = UDim2.fromOffset(94, 30),
			BackgroundColor3 = Color3.fromRGB(49, 36, 26), TextColor3 = Color3.fromRGB(245, 232, 214),
			PlaceholderText = axis, Text = "0", ClearTextOnFocus = false, Font = Enum.Font.Gotham,
			TextSize = 12, ZIndex = 81,
		})
		make("UICorner", box, "Corner", { CornerRadius = UDim.new(0, 5) })
		inputs[axis] = box
	end
	local keyButton = make("TextButton", panel, "KeyVertex", {
		Position = UDim2.fromOffset(14, 372), Size = UDim2.new(1, -28, 0, 42),
		BackgroundColor3 = Color3.fromRGB(221, 147, 67), Text = "KEY VERTEX AT PLAYHEAD",
		TextColor3 = Color3.fromRGB(34, 22, 13), Font = Enum.Font.GothamBold, TextSize = 12, ZIndex = 81,
	})
	make("UICorner", keyButton, "Corner", { CornerRadius = UDim.new(0, 6) })
	local status = make("TextLabel", panel, "Status", {
		Position = UDim2.fromOffset(14, 418), Size = UDim2.new(1, -28, 0, 18), BackgroundTransparency = 1,
		Text = "Choose a vertex", TextColor3 = Color3.fromRGB(183, 169, 151), Font = Enum.Font.Gotham,
		TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 81,
	})

	local rig, meshPart, vertexId
	local allIds = {}
	local visibleHandleCount = 0
	local rowById = {}
	local handleById = {}
	local drag
	local pluginMouse

	local function clearVertexHandles()
		for _, handle in vertexHandles do
			handle:Destroy()
		end
		table.clear(vertexHandles)
		table.clear(handleById)
	end

	local function showVertexHandles(mesh)
		clearVertexHandles()
		if not panel.Visible or not meshPart or not meshPart.Parent then
			return
		end
		local camera = workspace.CurrentCamera
		local visibleCount = 0
		local maxHandles = 4000
		for index, id in allIds do
			if visibleCount >= maxHandles then break end
			local handle = Instance.new("SphereHandleAdornment")
			handle.Name = "SunVertexPoint_" .. tostring(id)
			handle.Adornee = meshPart
			handle.CFrame = CFrame.new(mesh:GetPosition(id))
			handle.Radius = 0.06
			handle.Color3 = Color3.fromRGB(255, 190, 91)
			handle.Transparency = 0.08
			handle.AlwaysOnTop = true
			handle.ZIndex = 8
			handle.Visible = true
			handle.Parent = camera or workspace
			visibleCount += 1
			vertexHandles[visibleCount] = handle
			handleById[id] = handle
		end
		if #allIds > visibleCount then
			status.Text = string.format("Showing %d of %d vertex handles; filter the list to navigate", visibleCount, #allIds)
		end
		return visibleCount
	end

	marker = Instance.new("SphereHandleAdornment")
	marker.Name = "SunMeshVertexHandle"
	marker.Radius = 0.11
	marker.Color3 = Color3.fromRGB(255, 184, 76)
	marker.Transparency = 0.1
	marker.AlwaysOnTop = true
	marker.ZIndex = 10
	marker.Visible = false
	marker.Parent = workspace.CurrentCamera or workspace

	local function updateMarker(position)
		if not marker or not meshPart or not vertexId then
			if marker then marker.Visible = false end
			return
		end
		local ok, mesh = pcall(meshFor, meshPart)
		if not ok then
			marker.Visible = false
			return
		end
		marker.Adornee = meshPart
		marker.CFrame = CFrame.new(position or mesh:GetPosition(vertexId))
		marker.Parent = workspace.CurrentCamera or workspace
		marker.Visible = true
		local selectedHandle = handleById[vertexId]
		if selectedHandle then
			selectedHandle.CFrame = CFrame.new(position or mesh:GetPosition(vertexId))
			selectedHandle.Color3 = Color3.fromRGB(255, 239, 174)
			selectedHandle.Radius = 0.075
		end
	end

	local function selectVertex(id, mesh)
		for _, handle in handleById do
			handle.Color3 = Color3.fromRGB(255, 190, 91)
			handle.Radius = 0.045
		end
		vertexId = id
		activeVertex = {
			rig = rig,
			trackId = Vertex.trackId(meshPart, rig, id),
		}
		local p = mesh:GetPosition(id)
		selectedLabel.Text = "Vertex " .. id .. " · drag in viewport to move"
		inputs.X.Text, inputs.Y.Text, inputs.Z.Text = tostring(p.X), tostring(p.Y), tostring(p.Z)
		status.Text = "Click and drag this vertex in the 3D viewport"
		updateMarker(p)
	end

	local function keyPosition(value, existingMotor)
		local success, message = xpcall(function()
			assert(meshPart and meshPart.Parent and rig and rig.Parent, "Select a MeshPart in the current rig")
			assert(vertexId ~= nil, "Choose a vertex from the list or click it in the viewport")
			local id = Vertex.trackId(meshPart, rig, vertexId)
			local timeline = refs.State.Timeline
			assert(timeline, "Open an animation before keying a vertex")
			local raw = timeline:GetState()
			local frame = refs.GetFrame and refs.GetFrame() or timeline:TimeToFrame(raw.CurrentTime)
			local motor = existingMotor or require("Properties").enable(rig, id, true, raw)
			Vertex.write(rig, id, value)
			inputs.X.Text, inputs.Y.Text, inputs.Z.Text = tostring(value.X), tostring(value.Y), tostring(value.Z)
			updateMarker(value)
			if rowById[vertexId] then
				rowById[vertexId].Text = string.format("  %d     %.3f   %.3f   %.3f", vertexId, value.X, value.Y, value.Z)
			end
			refs.RefreshStructure()
			timeline:RecordKeyframeForMotorAtCurrentTime(meshPart, motor, CFrame.new(value), {
				PropertyValue = value,
				Frame = frame,
			})
			timeline:ApplyPoseAtTime(rig, raw.CurrentTime)
			timeline:UpdatePlayhead()
			status.Text = "Vertex " .. vertexId .. " keyed at frame " .. tostring(frame)
			return motor
		end, debug.traceback)
		if not success then
			status.Text = tostring(message):match("^[^\n]+") or "Unable to key this vertex"
			warn("[Sun Mesh Vertex Animation] " .. tostring(message))
			return false
		end
		return true, message
	end

	local function fillList()
		clearConnections(rowConnections)
		table.clear(rowById)
		for _, child in list:GetChildren() do
			if child ~= layout and not child:IsA("UICorner") then child:Destroy() end
		end
		local previousMesh = meshPart
		local selection = Selection:Get()
		local chosen = selection[1]
		meshPart = chosen and chosen:IsA("MeshPart") and chosen or nil
		if not meshPart and chosen then meshPart = chosen:FindFirstAncestorWhichIsA("MeshPart") end
		if previousMesh ~= meshPart then
			vertexId = nil
			activeVertex = nil
			clearVertexHandles()
			if marker then marker.Visible = false end
		end
		rig = refs.GetRig and refs.GetRig() or nil
		if not meshPart or not rig or (meshPart ~= rig and not meshPart:IsDescendantOf(rig)) then
			meshLabel.Text = "Select a MeshPart inside the active rig"
			vertexId = nil
			return
		end
		meshLabel.Text = meshPart:GetFullName()
		local ok, mesh = pcall(meshFor, meshPart)
		if not ok then
			status.Text = tostring(mesh):match("^[^\n]+") or "Unable to load mesh geometry"
			return
		end
		allIds = mesh:GetVertices()
		if #allIds == 0 then
			status.Text = "Editable geometry has no vertices"
			return
		end
		table.sort(allIds)
		visibleHandleCount = showVertexHandles(mesh)
		local query = filter.Text:lower():gsub("%s+", "")
		local matching = {}
		for _, id in allIds do
			if query == "" or tostring(id):find(query, 1, true) then
				table.insert(matching, id)
			end
		end
		local limit = math.min(#matching, 300)
		for index = 1, limit do
			local id = matching[index]
			local position = mesh:GetPosition(id)
			local button = make("TextButton", list, "Vertex_" .. id, {
				Size = UDim2.new(1, -6, 0, 27), BackgroundColor3 = Color3.fromRGB(36, 29, 23),
				Text = string.format("  %d     %.3f   %.3f   %.3f", id, position.X, position.Y, position.Z),
				TextColor3 = Color3.fromRGB(224, 212, 193), Font = Enum.Font.Code, TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = index, ZIndex = 82,
			})
			rowById[id] = button
			button:SetAttribute("VertexId", id)
			table.insert(rowConnections, button.Activated:Connect(function()
				selectVertex(id, mesh)
			end))
		end
		list.CanvasSize = UDim2.fromOffset(0, limit * 30)
		local listStatus = #matching > limit
			and ("Showing first " .. limit .. " matches; filter by ID to narrow the list")
			or (tostring(#matching) .. " of " .. tostring(#allIds) .. " vertices shown")
		if visibleHandleCount < #allIds then
			listStatus ..= string.format(" · %d handles shown", visibleHandleCount)
		end
		status.Text = listStatus
	end
	refreshVertexWindow = fillList
	table.insert(connections, Selection.SelectionChanged:Connect(fillList))
	table.insert(connections, filter.FocusLost:Connect(fillList))
	table.insert(connections, layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 4)
	end))
	table.insert(connections, keyButton.Activated:Connect(function()
		local x, y, z = tonumber(inputs.X.Text), tonumber(inputs.Y.Text), tonumber(inputs.Z.Text)
		if not x or not y or not z then
			status.Text = "Enter numeric X, Y, and Z values"
			return
		end
		keyPosition(Vector3.new(x, y, z))
	end))

	local function pointerCandidates()
		local screen, inset = NativeInput:GetMouseLocation(), GuiService:GetGuiInset()
		local candidates = {
			{ point = screen, mode = "screen" },
			{ point = Vector2.new(screen.X - inset.X, screen.Y - inset.Y), mode = "viewport" },
		}
		if pluginMouse then
			local point = Vector2.new(pluginMouse.X, pluginMouse.Y)
			table.insert(candidates, { point = point, mode = "pluginViewport" })
			table.insert(candidates, { point = point, mode = "pluginScreen" })
		end
		return candidates
	end
	local function pointerForMode(mode)
		if (mode == "pluginViewport" or mode == "pluginScreen") and pluginMouse then
			return Vector2.new(pluginMouse.X, pluginMouse.Y)
		end
		local screen = NativeInput:GetMouseLocation()
		if mode == "viewport" then
			local inset = GuiService:GetGuiInset()
			return Vector2.new(screen.X - inset.X, screen.Y - inset.Y)
		end
		return screen
	end

	local function planePoint(camera, point, origin, normal, mode)
		local isViewport = mode == "viewport" or mode == "pluginViewport"
		local ray = isViewport and camera:ViewportPointToRay(point.X, point.Y)
			or camera:ScreenPointToRay(point.X, point.Y)
		local denominator = ray.Direction:Dot(normal)
		if math.abs(denominator) < 1e-6 then return nil end
		return ray.Origin + ray.Direction * ((origin - ray.Origin):Dot(normal) / denominator)
	end

	local function screenPoint()
		return NativeInput:GetMouseLocation()
	end

	local function nearestVertex(candidates)
		local camera = workspace.CurrentCamera
		if not camera or not meshPart or not meshPart.Parent then return nil end
		local ok, mesh = pcall(meshFor, meshPart)
		if not ok then
			status.Text = tostring(mesh):match("^[^\n]+") or "Unable to load mesh geometry"
			return nil
		end
		local closestId, closestWorld, closestDistance, closestPoint, closestMode
		for id in handleById do
			local localPosition = mesh:GetPosition(id)
			local worldPosition = meshPart.CFrame:PointToWorldSpace(localPosition)
			local screenPosition, screenVisible = camera:WorldToScreenPoint(worldPosition)
			local viewportPosition, viewportVisible = camera:WorldToViewportPoint(worldPosition)
			for _, candidate in candidates do
				local isViewport = candidate.mode == "viewport" or candidate.mode == "pluginViewport"
				local projected = isViewport and viewportPosition or screenPosition
				local visible = isViewport and viewportVisible or screenVisible
				if visible and projected.Z > 0 then
					local deltaX, deltaY = projected.X - candidate.point.X, projected.Y - candidate.point.Y
					local distance = deltaX * deltaX + deltaY * deltaY
					if distance <= 784 and (not closestDistance or distance < closestDistance) then
						closestId, closestWorld, closestDistance = id, worldPosition, distance
						closestPoint, closestMode = candidate.point, candidate.mode
					end
				end
			end
		end
		return closestId, closestWorld, mesh, closestPoint, closestMode
	end

	local function endDrag()
		if not drag then return end
		local completed = drag
		drag = nil
		if completed.changed then
			local keyed = keyPosition(completed.position, completed.motor)
			if not keyed then
				pcall(Vertex.write, completed.rig, completed.trackId, completed.original)
				updateMarker(completed.original)
			end
		end
	end

	pluginMouse = refs.Plugin and refs.Plugin:GetMouse()
	local function beginVertexDrag(fromPluginMouse)
		if drag or not panel.Visible then return end
		if NativeInput:GetFocusedTextBox() then return end
		local screen = screenPoint()
		local panelPosition, panelSize = panel.AbsolutePosition, panel.AbsoluteSize
		if screen.X >= panelPosition.X and screen.X <= panelPosition.X + panelSize.X
			and screen.Y >= panelPosition.Y and screen.Y <= panelPosition.Y + panelSize.Y then return end
		local timeline = refs.State and refs.State.Timeline
		if not meshPart or not timeline or timeline:GetState().Playing then return end
		local id, worldPosition, mesh, point, coordinateMode = nearestVertex(pointerCandidates())
		if not id then return end
		selectVertex(id, mesh)
		for vertexId, handle in handleById do
			if vertexId ~= id then
				handle.Color3 = Color3.fromRGB(255, 190, 91)
				handle.Radius = 0.045
			end
		end
		local camera = workspace.CurrentCamera
		local normal = camera.CFrame.LookVector
		local onPlane = planePoint(camera, point, worldPosition, normal, coordinateMode)
		if onPlane then
			drag = {
				id = id, rig = rig, part = meshPart, camera = camera, mesh = mesh,
				original = mesh:GetPosition(id), position = mesh:GetPosition(id),
				worldOffset = worldPosition - onPlane, planeOrigin = worldPosition,
				planeNormal = normal, start = point, changed = false, coordinateMode = coordinateMode,
				trackId = Vertex.trackId(meshPart, rig, id),
			}
			status.Text = "Dragging vertex " .. id .. " · release to key"
		end
	end
	local function moveVertexDrag()
		if not drag then return end
		if workspace.CurrentCamera ~= drag.camera or not drag.part.Parent then
			endDrag()
			return
		end
			local point = pointerForMode(drag.coordinateMode)
		if (point - drag.start).Magnitude < 2 then return end
		if not drag.motor then
			local raw = refs.State.Timeline:GetState()
			drag.motor = require("Properties").enable(drag.rig, drag.trackId, true, raw)
		end
		local onPlane = planePoint(drag.camera, point, drag.planeOrigin, drag.planeNormal, drag.coordinateMode)
		if not onPlane then return end
		local worldPosition = onPlane + drag.worldOffset
		local localPosition = drag.part.CFrame:PointToObjectSpace(worldPosition)
		if localPosition ~= drag.position then
			local applied, applyError = pcall(function()
				drag.mesh:SetPosition(drag.id, localPosition)
			end)
			if not applied then
				local detail = tostring(applyError)
				status.Text = "Mesh deformation failed: " .. (detail:match("^[^\n]+") or detail)
				return
			end
			drag.position = localPosition
			drag.changed = true
			inputs.X.Text, inputs.Y.Text, inputs.Z.Text = tostring(localPosition.X), tostring(localPosition.Y), tostring(localPosition.Z)
			updateMarker(localPosition)
		end
	end
	if pluginMouse then
		table.insert(connections, pluginMouse.Button1Down:Connect(function() beginVertexDrag(true) end))
		table.insert(connections, pluginMouse.Move:Connect(moveVertexDrag))
		table.insert(connections, pluginMouse.Button1Up:Connect(endDrag))
	end
	table.insert(connections, NativeInput.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then beginVertexDrag(false) end
	end))
	table.insert(connections, NativeInput.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then moveVertexDrag() end
	end))
	table.insert(connections, NativeInput.InputEnded:Connect(function(input)
		if drag and input.UserInputType == Enum.UserInputType.MouseButton1 then endDrag() end
	end))
	table.insert(connections, RunService.RenderStepped:Connect(function()
		if drag then moveVertexDrag() end
	end))
	table.insert(connections, NativeInput.InputBegan:Connect(function(input)
		if drag and input.KeyCode == Enum.KeyCode.Escape then
			pcall(function() drag.mesh:SetPosition(drag.id, drag.original) end)
			updateMarker(drag.original)
			drag = nil
			status.Text = "Vertex drag cancelled"
		end
	end))
	fillList()
end

function Vertex.init(newRefs)
	Vertex.destroy()
	refs = newRefs
	if refs.ScreenGui then
		table.insert(lifecycleConnections, refs.ScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not refs.ScreenGui.Enabled then close() end
		end))
		table.insert(lifecycleConnections, refs.ScreenGui.Destroying:Connect(close))
	end
	if refs.Plugin then
		table.insert(lifecycleConnections, refs.Plugin.Unloading:Connect(close))
	end
end

function Vertex.close()
	close()
end

function Vertex.destroy()
	close()
	clearConnections(lifecycleConnections)
	table.clear(refs)
end

return Vertex

