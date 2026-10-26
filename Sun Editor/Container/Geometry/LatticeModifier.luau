--!nocheck

local require = require(script:FindFirstAncestor("Container").Require)
local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")
local Selection = game:GetService("Selection")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local MeshAccess = require("MeshAccess")
local Paths = require("Paths")
local Modifier = {}

local PREFIX = "SunLattice:"
local MAX_POINTS = 216
local MAX_VERTICES = 150000
local rigs = setmetatable({}, { __mode = "k" })
local gui, panel, markerFolder, active, refs
local buttons = {}
local connections = {}
local stateConnections = {}
local selectedPoint
local orbitTween

local function disconnectAll()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function hex(text)
	return (text:gsub(".", function(char)
		return string.format("%02x", string.byte(char))
	end))
end

local function unhex(text)
	if type(text) ~= "string" or #text == 0 or #text % 2 ~= 0 or text:find("[^%x]") then
		return nil
	end
	local bytes = table.create(#text / 2)
	for index = 1, #text, 2 do
		bytes[#bytes + 1] = string.char(tonumber(text:sub(index, index + 1), 16))
	end
	return table.concat(bytes)
end

local function parseTrack(id)
	if type(id) ~= "string" then
		return nil
	end
	local encoded, index = id:match("^SunLattice:([%x]+):(%d+)$")
	local idText = unhex(encoded)
	index = tonumber(index)
	if not idText or not index or index < 1 then
		return nil
	end
	return idText, index
end

local loadLattice

local function rootFolder(rig, create)
	local folder = rig and rig:FindFirstChild("SunLatticeData")
	if not folder and create then
		folder = Instance.new("Folder")
		folder.Name = "SunLatticeData"
		folder:SetAttribute("SunLatticeData", true)
		folder.Parent = rig
	end
	return folder
end

local function ensureCache(rig)
	local cached = rigs[rig]
	if cached then
		return cached
	end
	cached = { lattices = {}, byId = {} }
	rigs[rig] = cached
	local folder = rootFolder(rig, false)
	if not folder then
		return cached
	end
	for _, child in folder:GetChildren() do
		if child:IsA("Folder") and child:GetAttribute("SunLattice") == true then
			local state = loadLattice(rig, child)
			if state then
				table.insert(cached.lattices, state)
				cached.byId[state.id] = state
			end
		end
	end
	return cached
end

local function createFallbackBox(part)
	local half = part.Size * 0.5
	local mesh = AssetService:CreateEditableMesh()
	assert(mesh, "Roblox could not allocate EditableMesh geometry for this part")
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

local function meshFor(part, link)
	assert(part and part:IsA("MeshPart") and part.Parent, "Choose a MeshPart")
	local content = part.MeshContent
	local mesh
	local alreadyLinked = false
	local generatedFallback = false
	local sourceType = content.SourceType
	if sourceType == Enum.ContentSourceType.None then
		-- Imported MeshParts in older places can expose MeshId while MeshContent
		-- is empty. Resolve the legacy URI before reporting that geometry is absent.
		local meshId = tostring(part.MeshId)
		if meshId ~= "" then
			local ok, uriContent = pcall(Content.fromUri, meshId)
			if ok then
				content = uriContent
				sourceType = content.SourceType
			end
		end
		if sourceType == Enum.ContentSourceType.None then
			-- SUN rigs may contain placeholder MeshParts with no asset geometry.
			-- Give them editable box geometry matching their bounds so the lattice
			-- workflow also works for generated body placeholders.
			mesh = createFallbackBox(part)
			generatedFallback = true
		end
	end
	if not mesh then
		local object = content.Object
		if sourceType == Enum.ContentSourceType.Object and object and object:IsA("EditableMesh") then
			mesh = object
			alreadyLinked = true
		else
			mesh = MeshAccess.open(content)
		end
	end
	assert(mesh and mesh:IsA("EditableMesh"), "Roblox did not provide EditableMesh geometry")
	if link and not alreadyLinked then
		local staging = AssetService:CreateMeshPartAsync(Content.fromObject(mesh), {
			CollisionFidelity = part.CollisionFidelity,
			RenderFidelity = part.RenderFidelity,
		})
		local size, texture = part.Size, part.TextureContent
		local ok, message = pcall(function()
			staging.TextureContent = texture
			part:ApplyMesh(staging)
			part.Size = size
			part.TextureContent = texture
		end)
		staging:Destroy()
		assert(ok, "Could not attach editable geometry: " .. tostring(message))
	end
	return mesh, generatedFallback
end

loadLattice = function(rig, folder)
	local id = folder:GetAttribute("LatticeId")
	local baseFrame = folder:GetAttribute("BaseFrame")
	local baseSize = folder:GetAttribute("BaseSize")
	local nx, ny, nz = folder:GetAttribute("CountU"), folder:GetAttribute("CountV"), folder:GetAttribute("CountW")
	local pointsFolder = folder:FindFirstChild("Points")
	local meshFolder = folder:FindFirstChild("Meshes")
	if type(id) ~= "string" or typeof(baseFrame) ~= "CFrame" or typeof(baseSize) ~= "Vector3"
		or type(nx) ~= "number" or type(ny) ~= "number" or type(nz) ~= "number"
		or not pointsFolder or not meshFolder then
		return nil
	end
	local state = {
		id = id, rig = rig, folder = folder, baseFrame = baseFrame, baseSize = baseSize,
		nx = nx, ny = ny, nz = nz, points = {}, restPoints = {}, appliedPoints = {}, meshes = {}, dirty = {},
		enabled = folder:GetAttribute("Enabled") ~= false,
		showNumbers = folder:GetAttribute("ShowNumbers") ~= false,
	}
	for index = 1, nx * ny * nz do
		local value = pointsFolder:FindFirstChild(string.format("P%04d", index))
		if not value or not value:IsA("Vector3Value") then
			return nil
		end
		local position = value:GetAttribute("RestPosition")
		if typeof(position) ~= "Vector3" then
			position = value.Value
		end
		state.points[index] = position
		state.restPoints[index] = position
		state.appliedPoints[index] = position
	end
	for _, item in meshFolder:GetChildren() do
		if item:IsA("StringValue") then
			local ok, data = pcall(HttpService.JSONDecode, HttpService, item.Value)
			if ok and type(data) == "table" and type(data.Path) == "string" and type(data.Vertices) == "table"
				and #data.Vertices % 7 == 0 then
				local part = Paths.resolve(rig, data.Path)
				if part and part:IsA("MeshPart") then
					local meshOk, mesh = pcall(meshFor, part, true)
					if meshOk then
						local records = table.create(#data.Vertices / 7)
						for at = 1, #data.Vertices, 7 do
							local vertexId = data.Vertices[at]
							local localPosition = Vector3.new(data.Vertices[at + 1], data.Vertices[at + 2], data.Vertices[at + 3])
							-- Persisted base positions are the deformation source of truth.
							-- Restore them on reopen so a saved preview pose cannot compound.
							if mesh:GetPosition(vertexId) ~= localPosition then
								mesh:SetPosition(vertexId, localPosition)
							end
							table.insert(records, {
								id = vertexId, base = localPosition,
								weight = { data.Vertices[at + 4], data.Vertices[at + 5], data.Vertices[at + 6] },
								appliedDelta = Vector3.zero,
							})
						end
						table.insert(state.meshes, { part = part, mesh = mesh, vertices = records })
					end
				end
			end
		end
	end
	return state
end

local function resolve(rig, id, index)
	local cache = ensureCache(rig)
	local state = cache.byId[id]
	assert(state and index <= state.nx * state.ny * state.nz, "Lattice control point is missing")
	return state
end

local function bernstein(degree, t)
	local out = table.create(degree + 1)
	local oneMinus = 1 - t
	for i = 0, degree do
		local coefficient = 1
		for k = 1, i do
			coefficient = coefficient * (degree - k + 1) / k
		end
		out[i + 1] = coefficient * (t ^ i) * (oneMinus ^ (degree - i))
	end
	return out
end

local function flushLattice(state)
	local dirtyIndices = {}
	for index in state.dirty do
		table.insert(dirtyIndices, index)
	end
	if #dirtyIndices == 0 then
		return
	end
	table.sort(dirtyIndices)
	for _, binding in state.meshes do
		local part, mesh = binding.part, binding.mesh
		if not part.Parent then
			continue
		end
		for _, vertex in binding.vertices do
			local u, v, w = vertex.weight[1], vertex.weight[2], vertex.weight[3]
			-- Only vertices inside the cage participate. This keeps nearby meshes
			-- outside the configured volume unchanged.
			if u < 0 or u > 1 or v < 0 or v > 1 or w < 0 or w > 1 then
				continue
			end
			local xWeights = bernstein(state.nx - 1, math.clamp(u, 0, 1))
			local yWeights = bernstein(state.ny - 1, math.clamp(v, 0, 1))
			local zWeights = bernstein(state.nz - 1, math.clamp(w, 0, 1))
			local world = part.CFrame:PointToWorldSpace(mesh:GetPosition(vertex.id))
			local delta = Vector3.zero
			for _, index in dirtyIndices do
				local ix = (index - 1) % state.nx + 1
				local iy = math.floor((index - 1) / state.nx) % state.ny + 1
				local iz = math.floor((index - 1) / (state.nx * state.ny)) + 1
				local weight = xWeights[ix] * yWeights[iy] * zWeights[iz]
				if weight > 1e-8 then
					delta += (state.points[index] - state.appliedPoints[index]) * weight
				end
			end
			if delta.Magnitude > 1e-7 then
				local localPosition = part.CFrame:PointToObjectSpace(world + delta)
				if mesh:GetPosition(vertex.id) ~= localPosition then
					mesh:SetPosition(vertex.id, localPosition)
				end
				vertex.appliedDelta += delta
			end
		end
	end
	for _, index in dirtyIndices do
		state.appliedPoints[index] = state.points[index]
	end
	table.clear(state.dirty)
end

function Modifier.flush(rig)
	local cache = rig and ensureCache(rig)
	if not cache then
		return
	end
	for _, state in cache.lattices do
		if state.enabled then
			flushLattice(state)
		end
	end
	if active and active.rig == rig then
		for _, row in buttons do
			local position = active.points[row.index]
			if position and row.part.Parent then row.part.Position = position end
		end
	end
end

function Modifier.preparePose(rig)
	local cache = rig and ensureCache(rig)
	if not cache then
		return
	end
	for _, state in cache.lattices do
		table.clear(state.dirty)
		for index, position in state.restPoints do
			state.points[index] = position
			state.appliedPoints[index] = position
		end
		for _, binding in state.meshes do
			if binding.part.Parent then
				for _, vertex in binding.vertices do
					local delta = vertex.appliedDelta or Vector3.zero
					if delta.Magnitude > 1e-7 then
						local current = binding.mesh:GetPosition(vertex.id)
						local localPosition = binding.part.CFrame:PointToObjectSpace(
							binding.part.CFrame:PointToWorldSpace(current) - delta
						)
						if current ~= localPosition then
							binding.mesh:SetPosition(vertex.id, localPosition)
						end
						vertex.appliedDelta = Vector3.zero
					end
				end
			end
		end
	end
end

function Modifier.isTrack(id)
	return parseTrack(id) ~= nil
end

function Modifier.definition(rig, id)
	local latticeId, index = parseTrack(id)
	if not latticeId then
		return nil
	end
	local ok, state = pcall(resolve, rig, latticeId, index)
	if not ok then
		return nil
	end
	return { id = id, label = string.format("Lattice %s · point %d", state.folder.Name, index), kind = "Vector3" }
end

function Modifier.catalog(rig)
	local definitions = {}
	for _, state in ensureCache(rig).lattices do
		for index = 1, state.nx * state.ny * state.nz do
			local id = PREFIX .. hex(state.id) .. ":" .. tostring(index)
			table.insert(definitions, { id = id, label = "Lattice " .. state.folder.Name .. " · point " .. index, kind = "Vector3" })
		end
	end
	return definitions
end

function Modifier.read(rig, id)
	local latticeId, index = parseTrack(id)
	local state = resolve(rig, latticeId, index)
	return state.points[index]
end

function Modifier.write(rig, id, position)
	assert(typeof(position) == "Vector3", "Lattice control point must be a Vector3")
	local latticeId, index = parseTrack(id)
	local state = resolve(rig, latticeId, index)
	if state.points[index] ~= position then
		state.points[index] = position
		state.dirty[index] = true
	end
end

function Modifier.setEnabled(state, enabled)
	assert(state and state.folder and state.folder.Parent, "Choose a lattice first")
	enabled = enabled == true
	if state.enabled == enabled then return end
	state.enabled = true
	for index in state.points do
		state.dirty[index] = true
		if not enabled then
			state.points[index] = state.restPoints[index]
		end
	end
	Modifier.flush(state.rig)
	state.enabled = enabled
	state.folder:SetAttribute("Enabled", enabled)
end

local function removeLatticeTracks(rig, latticeId, timeline)
	local Properties = require("Properties")
	local raw = timeline and timeline:GetState()
	for _, motor in Properties.list(rig, true) do
		local id = parseTrack(motor.PropertyId)
		if id == latticeId then
			local bucket = raw and raw.Keyframes[motor]
			if bucket and timeline then
				local keys = {}
				for _, key in bucket do table.insert(keys, key) end
				for _, key in keys do timeline:DeleteKeyframe(key) end
			end
			if raw then
				raw.Keyframes[motor] = nil
				raw.DefaultPose[motor] = nil
				raw.ParentingDefaults[motor] = nil
				raw.MotorByPart[motor.Part1] = nil
			end
			if motor.Part1 and motor.Part1.Parent then motor.Part1:Destroy() end
		end
	end
end

function Modifier.remove(state)
	assert(state and state.folder and state.folder.Parent, "Choose a lattice first")
	local rig, cache = state.rig, ensureCache(state.rig)
	local timeline = refs and refs.State and refs.State.Timeline
	Modifier.preparePose(rig)
	removeLatticeTracks(rig, state.id, timeline)
	state.folder:Destroy()
	cache.byId[state.id] = nil
	local at = table.find(cache.lattices, state)
	if at then table.remove(cache.lattices, at) end
	local dataFolder = rootFolder(rig, false)
	if dataFolder and #dataFolder:GetChildren() == 0 then dataFolder:Destroy() end
	if timeline then
		timeline:InvalidateMotorListCache()
		if refs.RefreshStructure then refs.RefreshStructure() end
		timeline:ApplyPoseAtTime(rig, timeline:GetState().CurrentTime)
		timeline:UpdatePlayhead()
	end
	if refs and refs.State then refs.State.currentProjectSaved = false end
end

function Modifier.clear(rig)
	assert(rig and rig.Parent, "Open a SUN animation project first")
	local cache = ensureCache(rig)
	local states = table.clone(cache.lattices)
	for _, state in states do
		Modifier.remove(state)
	end
	return #states
end

local function dimensions(u, v, w)
	u, v, w = math.floor(tonumber(u) or 2), math.floor(tonumber(v) or 2), math.floor(tonumber(w) or 2)
	assert(u >= 2 and v >= 2 and w >= 2, "Each lattice dimension must be at least 2")
	assert(u <= 6 and v <= 6 and w <= 6 and u * v * w <= MAX_POINTS, "Lattice supports up to 216 control points")
	return u, v, w
end

local function selectedMeshes(selection, rig)
	local result, seen = {}, {}
	local function add(part)
		if part:IsA("MeshPart") and part ~= rig and part:IsDescendantOf(rig) and not seen[part] then
			seen[part] = true
			table.insert(result, part)
		end
	end
	for _, item in selection do
		if item:IsA("Model") then
			for _, descendant in item:GetDescendants() do add(descendant) end
		else
			add(item)
		end
	end
	return result
end

local function corners(part, callback)
	local half = part.Size * 0.5
	for _, x in { -half.X, half.X } do
		for _, y in { -half.Y, half.Y } do
			for _, z in { -half.Z, half.Z } do
				callback(part.CFrame:PointToWorldSpace(Vector3.new(x, y, z)))
			end
		end
	end
end

local function selectionCenter(selection, rig)
	local selectedParts, seen = {}, {}
	local function add(part)
		if part:IsA("BasePart") and (part == rig or part:IsDescendantOf(rig)) and not seen[part] then
			seen[part] = true
			table.insert(selectedParts, part)
		end
	end
	for _, item in selection do
		if item:IsA("Model") then
			for _, descendant in item:GetDescendants() do add(descendant) end
		else
			add(item)
		end
	end
	assert(#selectedParts > 0, "Select a part or model inside the active rig to position the cage")
	local minimum, maximum = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, part in selectedParts do
		corners(part, function(point)
			minimum = Vector3.new(math.min(minimum.X, point.X), math.min(minimum.Y, point.Y), math.min(minimum.Z, point.Z))
			maximum = Vector3.new(math.max(maximum.X, point.X), math.max(maximum.Y, point.Y), math.max(maximum.Z, point.Z))
		end)
	end
	return (minimum + maximum) * 0.5
end

local function partOverlapsBox(part, center, size)
	local low, high = center - size * 0.5, center + size * 0.5
	local partLow, partHigh = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	corners(part, function(point)
		partLow = Vector3.new(math.min(partLow.X, point.X), math.min(partLow.Y, point.Y), math.min(partLow.Z, point.Z))
		partHigh = Vector3.new(math.max(partHigh.X, point.X), math.max(partHigh.Y, point.Y), math.max(partHigh.Z, point.Z))
	end)
	return partHigh.X >= low.X and partLow.X <= high.X
		and partHigh.Y >= low.Y and partLow.Y <= high.Y
		and partHigh.Z >= low.Z and partLow.Z <= high.Z
end

function Modifier.create(rig, selection, countU, countV, countW, cageSizeX, cageSizeY, cageSizeZ)
	assert(rig and rig.Parent, "Open a SUN animation project first")
	local nx, ny, nz = dimensions(countU, countV, countW)
	local size = Vector3.new(tonumber(cageSizeX) or 0, tonumber(cageSizeY) or 0, tonumber(cageSizeZ) or 0)
	assert(size.X >= 0.1 and size.Y >= 0.1 and size.Z >= 0.1, "Set cage width, height, and depth to at least 0.1 studs")
	assert(size.X <= 2048 and size.Y <= 2048 and size.Z <= 2048, "Cage dimensions cannot exceed 2048 studs")
	local center = selectionCenter(selection, rig)
	local baseFrame = CFrame.new(center)
	local unique, meshes, vertexCount = {}, {}, 0
	local candidates = {}
	if rig:IsA("MeshPart") then table.insert(candidates, rig) end
	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("MeshPart") then table.insert(candidates, descendant) end
	end
	for _, part in candidates do
		if not unique[part] and partOverlapsBox(part, center, size) then
			unique[part] = true
			local mesh = meshFor(part, true)
			local ids = mesh:GetVertices()
			vertexCount += #ids
			assert(vertexCount <= MAX_VERTICES, "Lattice binding is limited to 150,000 vertices for responsive editing")
			table.insert(meshes, { part = part, mesh = mesh, ids = ids })
		end
	end
	assert(#meshes > 0, "No MeshParts overlap this cage. Increase its size or move the cage center.")
	assert(vertexCount * nx * ny * nz <= 10000000, "This lattice would exceed the deformation budget; reduce grid resolution or bind fewer vertices")
	for _, existing in ensureCache(rig).lattices do
		for _, oldBinding in existing.meshes do
			assert(not unique[oldBinding.part], oldBinding.part.Name .. " is already bound to another lattice")
		end
	end
	local id = HttpService:GenerateGUID(false)
	local root = rootFolder(rig, true)
	local folder = Instance.new("Folder")
	folder.Name = "Lattice_" .. id:sub(1, 8)
	folder:SetAttribute("SunLattice", true)
	folder:SetAttribute("LatticeId", id)
	folder:SetAttribute("BaseFrame", baseFrame)
	folder:SetAttribute("BaseSize", size)
	folder:SetAttribute("CountU", nx)
	folder:SetAttribute("CountV", ny)
	folder:SetAttribute("CountW", nz)
	folder:SetAttribute("Enabled", true)
	folder:SetAttribute("ShowNumbers", true)
	local pointsFolder = Instance.new("Folder")
	pointsFolder.Name = "Points"
	pointsFolder.Parent = folder
	local meshFolder = Instance.new("Folder")
	meshFolder.Name = "Meshes"
	meshFolder.Parent = folder
	local state = { id = id, rig = rig, folder = folder, baseFrame = baseFrame, baseSize = size, nx = nx, ny = ny, nz = nz, points = {}, restPoints = {}, appliedPoints = {}, meshes = {}, dirty = {}, enabled = true, showNumbers = true }
	for z = 1, nz do
		for y = 1, ny do
			for x = 1, nx do
				local index = #state.points + 1
				local localPosition = Vector3.new(
					-size.X * 0.5 + size.X * (x - 1) / (nx - 1),
					-size.Y * 0.5 + size.Y * (y - 1) / (ny - 1),
					-size.Z * 0.5 + size.Z * (z - 1) / (nz - 1)
				)
				local position = baseFrame:PointToWorldSpace(localPosition)
				state.points[index], state.restPoints[index], state.appliedPoints[index] = position, position, position
				local value = Instance.new("Vector3Value")
				value.Name = string.format("P%04d", index)
				value.Value = position
				value:SetAttribute("RestPosition", position)
				value.Parent = pointsFolder
			end
		end
	end
	for index, binding in meshes do
		local path = Paths.of(binding.part, rig, true)
		assert(path, "Could not store a stable path for " .. binding.part.Name)
		local data = { Path = path, Vertices = {} }
		local records = table.create(#binding.ids)
		for _, vertexId in binding.ids do
			local localPosition = binding.mesh:GetPosition(vertexId)
			local q = baseFrame:PointToObjectSpace(binding.part.CFrame:PointToWorldSpace(localPosition))
			data.Vertices[#data.Vertices + 1] = vertexId
			local weight = { q.X / size.X + 0.5, q.Y / size.Y + 0.5, q.Z / size.Z + 0.5 }
			data.Vertices[#data.Vertices + 1] = localPosition.X
			data.Vertices[#data.Vertices + 1] = localPosition.Y
			data.Vertices[#data.Vertices + 1] = localPosition.Z
			data.Vertices[#data.Vertices + 1] = weight[1]
			data.Vertices[#data.Vertices + 1] = weight[2]
			data.Vertices[#data.Vertices + 1] = weight[3]
			table.insert(records, { id = vertexId, base = localPosition, weight = weight, appliedDelta = Vector3.zero })
		end
		local value = Instance.new("StringValue")
		value.Name = string.format("Mesh%03d", index)
		value.Value = HttpService:JSONEncode(data)
		value.Parent = meshFolder
		table.insert(state.meshes, { part = binding.part, mesh = binding.mesh, vertices = records })
	end
	folder.Parent = root
	local cache = ensureCache(rig)
	table.insert(cache.lattices, state)
	cache.byId[id] = state
	return state
end

function Modifier.bind(rig, state, parts)
	assert(state and state.rig == rig, "Choose a lattice first")
	local already = {}
	for _, binding in state.meshes do already[binding.part] = true end
	local selected = selectedMeshes(parts, rig)
	for _, other in ensureCache(rig).lattices do
		if other ~= state then
			for _, binding in other.meshes do
				if table.find(selected, binding.part) then
					error(binding.part.Name .. " is already bound to another lattice")
				end
			end
		end
	end
	local added = 0
	for _, part in selected do
		if part:IsA("MeshPart") and part ~= rig and part:IsDescendantOf(rig) and not already[part] then
			local mesh = meshFor(part, true)
			local ids = mesh:GetVertices()
			local vertexCount = #ids
			for _, binding in state.meshes do vertexCount += #binding.vertices end
			assert(vertexCount <= MAX_VERTICES, "Lattice binding is limited to 150,000 vertices")
			assert(vertexCount * state.nx * state.ny * state.nz <= 10000000, "This binding would exceed the deformation budget")
			local path = Paths.of(part, rig, true)
			assert(path, "Could not store a stable path for " .. part.Name)
			local data = { Path = path, Vertices = {} }
			local records = {}
			for _, vertexId in ids do
				local localPosition = mesh:GetPosition(vertexId)
				local q = state.baseFrame:PointToObjectSpace(part.CFrame:PointToWorldSpace(localPosition))
				local weight = { q.X / state.baseSize.X + 0.5, q.Y / state.baseSize.Y + 0.5, q.Z / state.baseSize.Z + 0.5 }
				for _, scalar in { vertexId, localPosition.X, localPosition.Y, localPosition.Z, weight[1], weight[2], weight[3] } do table.insert(data.Vertices, scalar) end
				table.insert(records, { id = vertexId, base = localPosition, weight = weight, appliedDelta = Vector3.zero })
			end
			local value = Instance.new("StringValue")
			value.Name = string.format("Mesh%03d", #state.meshes + 1)
			value.Value = HttpService:JSONEncode(data)
			value.Parent = state.folder.Meshes
			table.insert(state.meshes, { part = part, mesh = mesh, vertices = records })
			already[part] = true
			added += 1
		end
	end
	assert(added > 0, "Select new MeshParts inside the active SUN rig to bind")
	return added
end

local function make(class, parent, name, properties)
	local item = Instance.new(class)
	item.Name = name
	for key, value in properties do item[key] = value end
	item.Parent = parent
	return item
end

local function clearMarkers()
	for _, row in buttons do
		if row.handle and row.handle.Parent then row.handle:Destroy() end
	end
	if markerFolder then markerFolder:Destroy(); markerFolder = nil end
	table.clear(buttons)
end

local function pointIndex(x, y, z, state)
	return (z - 1) * state.nx * state.ny + (y - 1) * state.nx + x
end

local function drawState(state)
	clearMarkers()
	if not state then return end
	markerFolder = Instance.new("Folder")
	markerFolder.Name = "SunLatticePreview"
	markerFolder.Parent = workspace
	local attachments = {}
	for index, position in state.points do
		local part = make("Part", markerFolder, "Point" .. index, {
			Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false,
			Transparency = 1, Size = Vector3.one * 0.05, CFrame = CFrame.new(position),
		})
		local attachment = make("Attachment", part, "Point", {})
		attachments[index] = attachment
		local handle = Instance.new("SphereHandleAdornment")
		handle.Name = "LatticePointHandle"
		handle.Adornee = part
		handle.Radius = 0.09
		handle.Color3 = index == selectedPoint and Color3.fromRGB(255, 225, 143) or Color3.fromRGB(245, 151, 66)
		handle.Transparency = 0.05
		handle.AlwaysOnTop = true
		handle.ZIndex = 9
		handle.Parent = workspace.CurrentCamera or workspace
		table.insert(buttons, { index = index, part = part, handle = handle })
			if state.showNumbers then
				local tag = make("BillboardGui", markerFolder, "PointNumber" .. index, {
					Adornee = part,
					AlwaysOnTop = true,
					LightInfluence = 0,
					MaxDistance = 1000,
					Size = UDim2.fromOffset(34, 20),
					StudsOffsetWorldSpace = Vector3.new(0, 0.15, 0),
				})
				make("TextLabel", tag, "Index", {
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = Color3.fromRGB(34, 21, 13),
					BackgroundTransparency = 0.12,
					BorderSizePixel = 0,
					Text = string.format("%03d", index),
					TextColor3 = Color3.fromRGB(255, 155, 54),
					TextStrokeColor3 = Color3.fromRGB(24, 16, 11),
					TextStrokeTransparency = 0.2,
					Font = Enum.Font.GothamBold,
					TextSize = 12,
				})
			end
	end
	local function connect(a, b)
		local beam = make("Beam", markerFolder, "LatticeEdge", {
			Attachment0 = attachments[a], Attachment1 = attachments[b],
			Width0 = 0.025, Width1 = 0.025, FaceCamera = true,
			Color = ColorSequence.new(Color3.fromRGB(246, 156, 73)),
			Transparency = NumberSequence.new(0.2),
			LightEmission = 0.15,
		})
		return beam
	end
	for z = 1, state.nz do
		for y = 1, state.ny do
			for x = 1, state.nx do
				local index = pointIndex(x, y, z, state)
				if x < state.nx then connect(index, pointIndex(x + 1, y, z, state)) end
				if y < state.ny then connect(index, pointIndex(x, y + 1, z, state)) end
				if z < state.nz then connect(index, pointIndex(x, y, z + 1, state)) end
			end
		end
	end
end

function Modifier.open()
	if panel and panel.Parent then
		panel.Visible = not panel.Visible
		if panel.Visible then
			if orbitTween then orbitTween:Play() end
			drawState(active)
		else
			if orbitTween then orbitTween:Pause() end
			clearMarkers()
		end
		return
	end
	local screen = refs and refs.ScreenGui
	if not screen or not screen.Parent then return end
	panel = make("Frame", screen, "LatticeModifierPanel", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -18, 0.5, 0),
		Size = UDim2.fromOffset(360, 610), BackgroundColor3 = Color3.fromRGB(17, 15, 13),
		BorderSizePixel = 0, Active = true, ZIndex = 90,
	})
	make("UICorner", panel, "Corner", { CornerRadius = UDim.new(0, 9) })
	make("UIStroke", panel, "Stroke", { Color = Color3.fromRGB(178, 91, 34), Thickness = 1.2 })
	local panelScale = make("UIScale", panel, "IntroScale", { Scale = 0.97 })
	local function card(name, position, size, accent)
		local frame = make("Frame", panel, name, {
			Position = position, Size = size, BackgroundColor3 = Color3.fromRGB(27, 22, 18),
			BorderSizePixel = 0, ZIndex = 90,
		})
		make("UICorner", frame, "Corner", { CornerRadius = UDim.new(0, 8) })
		make("UIStroke", frame, "Stroke", { Color = Color3.fromRGB(72, 49, 32), Thickness = 1, Transparency = 0.25 })
		if accent then
			local rail = make("Frame", frame, "SunAccent", {
				Position = UDim2.fromOffset(0, 10), Size = UDim2.new(0, 3, 1, -20),
				BackgroundColor3 = Color3.fromRGB(255, 157, 58), BorderSizePixel = 0, ZIndex = 91,
			})
			make("UICorner", rail, "Corner", { CornerRadius = UDim.new(1, 0) })
		end
		return frame
	end
	local header = make("Frame", panel, "SolarHeader", {
		Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 0, 68),
		BackgroundColor3 = Color3.fromRGB(105, 48, 22), BorderSizePixel = 0, ZIndex = 90,
	})
	make("UICorner", header, "Corner", { CornerRadius = UDim.new(0, 9) })
	make("UIGradient", header, "SolarGradient", {
		Rotation = 0,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(183, 82, 30)),
			ColorSequenceKeypoint.new(0.52, Color3.fromRGB(96, 43, 24)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(41, 29, 22)),
		}),
	})
	local sun = make("Frame", header, "SunCore", {
		Position = UDim2.fromOffset(18, 15), Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = Color3.fromRGB(255, 178, 70), BorderSizePixel = 0, ZIndex = 92,
	})
	make("UICorner", sun, "Corner", { CornerRadius = UDim.new(1, 0) })
	make("UIStroke", sun, "Corona", { Color = Color3.fromRGB(255, 225, 156), Thickness = 2, Transparency = 0.15 })
	local orbit = make("Frame", header, "OrbitRing", {
		Position = UDim2.fromOffset(5, 6), Size = UDim2.fromOffset(60, 52),
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 91,
	})
	make("UICorner", orbit, "Corner", { CornerRadius = UDim.new(1, 0) })
	make("UIStroke", orbit, "OrbitLine", { Color = Color3.fromRGB(255, 211, 137), Thickness = 1, Transparency = 0.28 })
	local planet = make("Frame", orbit, "OrbitingPlanet", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 29, 0.5, 0),
		Size = UDim2.fromOffset(7, 7), BackgroundColor3 = Color3.fromRGB(255, 235, 192), BorderSizePixel = 0, ZIndex = 93,
	})
	make("UICorner", planet, "Corner", { CornerRadius = UDim.new(1, 0) })
	orbitTween = TweenService:Create(orbit, TweenInfo.new(8, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 })
	orbitTween:Play()
	card("CageCard", UDim2.fromOffset(8, 72), UDim2.new(1, -16, 0, 128), true)
	card("BindingCard", UDim2.fromOffset(8, 204), UDim2.new(1, -16, 0, 152), false)
	card("PointCard", UDim2.fromOffset(8, 360), UDim2.new(1, -16, 0, 239), true)
	local introTween = TweenService:Create(panelScale, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Scale = 1 })
	introTween:Play()
	make("TextLabel", panel, "Title", {
		Position = UDim2.fromOffset(77, 11), Size = UDim2.new(1, -125, 0, 23), BackgroundTransparency = 1,
		Text = "SUN  /  DEFORM LAB", TextColor3 = Color3.fromRGB(255, 231, 195),
		Font = Enum.Font.GothamBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 92,
	})
	make("TextLabel", header, "HeaderCaption", {
		Position = UDim2.fromOffset(78, 34), Size = UDim2.new(1, -100, 0, 18), BackgroundTransparency = 1,
		Text = "SHAPE A VOLUME  ·  ANIMATE THE CAGE", TextColor3 = Color3.fromRGB(255, 200, 143),
		Font = Enum.Font.GothamMedium, TextSize = 8, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 92,
	})
	local close = make("TextButton", panel, "Close", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(28, 26),
		BackgroundColor3 = Color3.fromRGB(55, 36, 27), Text = "×", TextColor3 = Color3.fromRGB(255, 235, 210),
		Font = Enum.Font.GothamBold, TextSize = 18, ZIndex = 93,
	})
	table.insert(connections, close.Activated:Connect(function()
		panel.Visible = false
		if orbitTween then orbitTween:Pause() end
		clearMarkers()
	end))
	make("TextLabel", panel, "Hint", {
		Position = UDim2.fromOffset(77, 51), Size = UDim2.new(1, -100, 0, 14), BackgroundTransparency = 1,
		Text = "MeshParts inside the sized cage bind automatically.",
		TextColor3 = Color3.fromRGB(255, 220, 177), Font = Enum.Font.Gotham, TextSize = 9,
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 91,
	})
	make("TextLabel", panel, "DensityHeading", {
		Position = UDim2.fromOffset(14, 76), Size = UDim2.new(1, -28, 0, 14), BackgroundTransparency = 1,
		Text = "01   CAGE RESOLUTION", TextColor3 = Color3.fromRGB(255, 177, 91),
		Font = Enum.Font.GothamBold, TextSize = 9, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 91,
	})
	local counts = {}
	for index, label in { "Across · U", "Vertical · V", "Depth · W" } do
		local x = 14 + (index - 1) * 106
		make("TextLabel", panel, "CountLabel" .. label, {
			Position = UDim2.fromOffset(x, 92), Size = UDim2.fromOffset(100, 12),
			BackgroundTransparency = 1, Text = label, TextColor3 = Color3.fromRGB(235, 196, 147),
			Font = Enum.Font.GothamMedium, TextSize = 9, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 91,
		})
		local countKey = ({ ["Across · U"] = "Across", ["Vertical · V"] = "Vertical", ["Depth · W"] = "Depth" })[label]
		counts[countKey] = make("TextBox", panel, "Count" .. countKey, {
			Position = UDim2.fromOffset(x, 106), Size = UDim2.fromOffset(100, 26),
			BackgroundColor3 = Color3.fromRGB(50, 37, 28), TextColor3 = Color3.fromRGB(245, 232, 214),
			Text = "2", PlaceholderText = "points", ClearTextOnFocus = false, Font = Enum.Font.Gotham, TextSize = 11, ZIndex = 91,
		})
	end
	make("TextLabel", panel, "SizeHeading", {
		Position = UDim2.fromOffset(14, 138), Size = UDim2.new(1, -28, 0, 14), BackgroundTransparency = 1,
		Text = "02   CAGE DIMENSIONS  /  STUDS", TextColor3 = Color3.fromRGB(255, 177, 91),
		Font = Enum.Font.GothamBold, TextSize = 9, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 91,
	})
	local sizes = {}
	for index, axis in { "Width", "Height", "Depth" } do
		local x = 14 + (index - 1) * 106
		make("TextLabel", panel, "SizeLabel" .. axis, {
			Position = UDim2.fromOffset(x, 154), Size = UDim2.fromOffset(100, 12),
			BackgroundTransparency = 1, Text = axis, TextColor3 = Color3.fromRGB(235, 196, 147),
			Font = Enum.Font.GothamMedium, TextSize = 9, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 91,
		})
		sizes[axis] = make("TextBox", panel, "CageSize" .. axis, {
			Position = UDim2.fromOffset(x, 168), Size = UDim2.fromOffset(100, 26),
			BackgroundColor3 = Color3.fromRGB(50, 37, 28), TextColor3 = Color3.fromRGB(245, 232, 214),
			Text = "8", ClearTextOnFocus = false, Font = Enum.Font.Gotham, TextSize = 11, ZIndex = 91,
		})
	end
	local create = make("TextButton", panel, "Create", {
		Position = UDim2.fromOffset(14, 202), Size = UDim2.new(1, -28, 0, 30),
		BackgroundColor3 = Color3.fromRGB(221, 147, 67), Text = "✦   BUILD CAGE  +  BIND ENCLOSED MESHES", TextColor3 = Color3.fromRGB(34, 22, 13),
		Font = Enum.Font.GothamBold, TextSize = 10, ZIndex = 91,
	})
	local bind = make("TextButton", panel, "Bind", {
		Position = UDim2.fromOffset(14, 268), Size = UDim2.new(1, -28, 0, 28),
		BackgroundColor3 = Color3.fromRGB(57, 43, 32), Text = "＋   BIND SELECTED MESHPARTS", TextColor3 = Color3.fromRGB(239, 221, 197),
		Font = Enum.Font.GothamMedium, TextSize = 10, ZIndex = 91,
	})
	local numberToggle = make("TextButton", panel, "NumberedCage", {
		Position = UDim2.fromOffset(14, 235), Size = UDim2.new(1, -28, 0, 28),
		BackgroundColor3 = Color3.fromRGB(69, 40, 20), Text = "NUMBERED CAGE  ·  ON",
		TextColor3 = Color3.fromRGB(255, 168, 75), Font = Enum.Font.GothamBold, TextSize = 10, ZIndex = 91,
	})
	local list = make("ScrollingFrame", panel, "Lattices", {
		Position = UDim2.fromOffset(14, 300), Size = UDim2.new(1, -28, 0, 55),
		BackgroundColor3 = Color3.fromRGB(17, 15, 13), BorderSizePixel = 0, ScrollBarThickness = 4,
		CanvasSize = UDim2.new(), ZIndex = 91,
	})
	make("UIListLayout", list, "Layout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder })
	local toggle = make("TextButton", panel, "EnableModifier", {
		Position = UDim2.fromOffset(14, 362), Size = UDim2.fromOffset(126, 24),
		BackgroundColor3 = Color3.fromRGB(54, 43, 33), Text = "LATTICE: ON", TextColor3 = Color3.fromRGB(239, 221, 197),
		Font = Enum.Font.GothamBold, TextSize = 10, ZIndex = 91,
	})
	local removeSelected = make("TextButton", panel, "RemoveSelected", {
		Position = UDim2.fromOffset(145, 362), Size = UDim2.fromOffset(91, 24),
		BackgroundColor3 = Color3.fromRGB(83, 43, 25), Text = "REMOVE", TextColor3 = Color3.fromRGB(255, 174, 103),
		Font = Enum.Font.GothamBold, TextSize = 9, ZIndex = 91,
	})
	local clearAll = make("TextButton", panel, "ClearAll", {
		Position = UDim2.fromOffset(239, 362), Size = UDim2.fromOffset(87, 24),
		BackgroundColor3 = Color3.fromRGB(69, 32, 24), Text = "CLEAR ALL", TextColor3 = Color3.fromRGB(255, 145, 110),
		Font = Enum.Font.GothamBold, TextSize = 9, ZIndex = 91,
	})
	local pointList = make("ScrollingFrame", panel, "Points", {
		Position = UDim2.fromOffset(14, 391), Size = UDim2.new(1, -28, 0, 78),
		BackgroundColor3 = Color3.fromRGB(17, 15, 13), BorderSizePixel = 0, ScrollBarThickness = 4,
		CanvasSize = UDim2.new(), ZIndex = 91,
	})
	local pointLayout = make("UIListLayout", pointList, "Layout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder })
	local selectedLabel = make("TextLabel", panel, "SelectedPoint", {
		Position = UDim2.fromOffset(14, 472), Size = UDim2.new(1, -28, 0, 20), BackgroundTransparency = 1,
		Text = "Control point: none", TextColor3 = Color3.fromRGB(247, 187, 105), Font = Enum.Font.GothamBold,
		TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 91,
	})
	local inputs = {}
	for index, axis in { "X", "Y", "Z" } do
		local input = make("TextBox", panel, "Position" .. axis, {
			Position = UDim2.fromOffset(14 + (index - 1) * 101, 495), Size = UDim2.fromOffset(94, 27),
			BackgroundColor3 = Color3.fromRGB(50, 37, 28), TextColor3 = Color3.fromRGB(245, 232, 214),
			Text = "0", ClearTextOnFocus = false, Font = Enum.Font.Gotham, TextSize = 11, ZIndex = 91,
		})
		inputs[axis] = input
	end
	local key = make("TextButton", panel, "Key", {
		Position = UDim2.fromOffset(14, 530), Size = UDim2.new(1, -28, 0, 34),
		BackgroundColor3 = Color3.fromRGB(221, 147, 67), Text = "KEY POINT AT PLAYHEAD", TextColor3 = Color3.fromRGB(34, 22, 13),
		Font = Enum.Font.GothamBold, TextSize = 11, ZIndex = 91,
	})
	local status = make("TextLabel", panel, "Status", {
		Position = UDim2.fromOffset(14, 568), Size = UDim2.new(1, -28, 0, 24), BackgroundTransparency = 1,
		Text = "Choose a rig and MeshPart selection", TextColor3 = Color3.fromRGB(183, 169, 151),
		Font = Enum.Font.Gotham, TextSize = 9, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 91,
	})
	local function roundControl(instance, radius, strokeColor)
		make("UICorner", instance, "Corner", { CornerRadius = UDim.new(0, radius) })
		if strokeColor then
			make("UIStroke", instance, "Outline", { Color = strokeColor, Thickness = 1, Transparency = 0.35 })
		end
	end
	local function animateButton(button)
		local resting = button.BackgroundColor3
		roundControl(button, 6, Color3.fromRGB(111, 72, 43))
		local tween
		table.insert(connections, button.MouseEnter:Connect(function()
			if tween then tween:Cancel() end
			tween = TweenService:Create(button, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundColor3 = resting:Lerp(Color3.fromRGB(255, 190, 111), 0.18),
			})
			tween:Play()
		end))
		table.insert(connections, button.MouseLeave:Connect(function()
			if tween then tween:Cancel() end
			tween = TweenService:Create(button, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundColor3 = resting,
			})
			tween:Play()
		end))
	end
	for _, button in { close, create, numberToggle, bind, toggle, removeSelected, clearAll, key } do
		animateButton(button)
	end
	for _, input in { counts.Across, counts.Vertical, counts.Depth, sizes.Width, sizes.Height, sizes.Depth, inputs.X, inputs.Y, inputs.Z } do
		roundControl(input, 5, Color3.fromRGB(104, 70, 43))
	end
	roundControl(list, 6, Color3.fromRGB(82, 57, 37))
	roundControl(pointList, 6, Color3.fromRGB(82, 57, 37))
	local rig, cache
	local function selectState(state, preservePoint)
		for _, connection in stateConnections do connection:Disconnect() end
		table.clear(stateConnections)
		active = state
		selectedPoint = preservePoint
		toggle.Text = state and (state.enabled and "LATTICE: ON  ·  CLICK TO DISABLE" or "LATTICE: OFF  ·  CLICK TO ENABLE") or "LATTICE: SELECT A CAGE"
		removeSelected.Active = state ~= nil
		removeSelected.AutoButtonColor = state ~= nil
		removeSelected.TextTransparency = state and 0 or 0.45
		numberToggle.Text = state and (state.showNumbers and "NUMBERED CAGE  ·  ON" or "NUMBERED CAGE  ·  OFF") or "NUMBERED CAGE  ·  CREATE A CAGE FIRST"
		numberToggle.TextColor3 = state and (state.showNumbers and Color3.fromRGB(255, 168, 75) or Color3.fromRGB(190, 155, 125)) or Color3.fromRGB(190, 155, 125)
		drawState(state)
		for _, child in list:GetChildren() do if child:IsA("TextButton") then child:Destroy() end end
		for _, stateRow in cache and cache.lattices or {} do
			local row = make("TextButton", list, "Choose_" .. stateRow.id, {
				Size = UDim2.new(1, -4, 0, 28), BackgroundColor3 = stateRow == state and Color3.fromRGB(91, 56, 31) or Color3.fromRGB(39, 31, 25),
				Text = string.format("  %s  ·  %d × %d × %d  ·  %d mesh(es)", stateRow.folder.Name, stateRow.nx, stateRow.ny, stateRow.nz, #stateRow.meshes),
				TextColor3 = Color3.fromRGB(236, 222, 204), Font = Enum.Font.Gotham, TextSize = 10,
				TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = #list:GetChildren(), ZIndex = 92,
			})
			table.insert(stateConnections, row.Activated:Connect(function() selectState(stateRow) end))
		end
		for _, child in pointList:GetChildren() do if child:IsA("TextButton") then child:Destroy() end end
		if not state then return end
		for index, position in state.points do
			local row = make("TextButton", pointList, "ControlPoint" .. index, {
				Size = UDim2.new(1, -4, 0, 24), BackgroundColor3 = Color3.fromRGB(39, 31, 25),
				Text = string.format("  Point %03d      % .3f   % .3f   % .3f", index, position.X, position.Y, position.Z),
				TextColor3 = Color3.fromRGB(236, 222, 204), Font = Enum.Font.Code, TextSize = 10,
				TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = index, ZIndex = 92,
			})
			table.insert(stateConnections, row.Activated:Connect(function()
				selectedPoint = index
				selectedLabel.Text = "Control point " .. index .. " · drag its orange handle"
				local p = state.points[index]
				inputs.X.Text, inputs.Y.Text, inputs.Z.Text = tostring(p.X), tostring(p.Y), tostring(p.Z)
				drawState(state)
			end))
		end
		pointList.CanvasSize = UDim2.fromOffset(0, #state.points * 26)
	end
	local function currentRig()
		return refs.GetRig and refs.GetRig() or refs.State.currentRig
	end
	table.insert(connections, create.Activated:Connect(function()
		local success, result = xpcall(function()
			rig = currentRig()
			cache = ensureCache(rig)
			local state = Modifier.create(
				rig,
				Selection:Get(),
				counts.Across.Text,
				counts.Vertical.Text,
				counts.Depth.Text,
				sizes.Width.Text,
				sizes.Height.Text,
				sizes.Depth.Text
			)
			selectState(state)
			status.Text = string.format("Cage covers %g × %g × %g studs · bound %d MeshPart(s)", state.baseSize.X, state.baseSize.Y, state.baseSize.Z, #state.meshes)
			return state
		end, debug.traceback)
		if not success then status.Text = tostring(result):match("^[^\n]+") or "Could not create lattice"; warn("[SUN Lattice] " .. tostring(result)) end
	end))
	table.insert(connections, bind.Activated:Connect(function()
		local success, result = pcall(function()
			assert(active, "Create or select a lattice first")
			local added = Modifier.bind(active.rig, active, Selection:Get())
			selectState(active)
			status.Text = "Bound " .. added .. " additional MeshPart(s)"
		end)
		if not success then status.Text = tostring(result):match("^[^\n]+") or "Unable to bind meshes" end
	end))
	table.insert(connections, numberToggle.Activated:Connect(function()
		if not active then
			status.Text = "Create or select a lattice to show its numbered cage"
			return
		end
		active.showNumbers = not active.showNumbers
		active.folder:SetAttribute("ShowNumbers", active.showNumbers)
		selectState(active, selectedPoint)
		status.Text = active.showNumbers and "Orange numbered cage is visible in the viewport" or "Point numbers are hidden; orange cage remains visible"
	end))
	table.insert(connections, toggle.Activated:Connect(function()
		local success, message = pcall(function()
			assert(active, "Create or select a lattice first")
			Modifier.setEnabled(active, not active.enabled)
			local timeline = refs.State.Timeline
			local time = timeline:GetState().CurrentTime
			timeline:ApplyPoseAtTime(active.rig, time)
			timeline:UpdatePlayhead()
			selectState(active, selectedPoint)
		end)
		if not success then status.Text = tostring(message):match("^[^\n]+") or "Could not toggle lattice" end
	end))
	table.insert(connections, removeSelected.Activated:Connect(function()
		local state = active
		if not state then
			status.Text = "Select a lattice to remove it"
			return
		end
		local success, message = pcall(function()
			Modifier.remove(state)
			cache = ensureCache(state.rig)
			active = nil
			selectState(cache.lattices[1])
			status.Text = "Removed lattice and its control-point animation tracks"
		end)
		if not success then status.Text = tostring(message):match("^[^\n]+") or "Could not remove lattice" end
	end))
	table.insert(connections, clearAll.Activated:Connect(function()
		local targetRig = currentRig()
		local cacheNow = targetRig and ensureCache(targetRig)
		if not cacheNow or #cacheNow.lattices == 0 then
			status.Text = "This rig has no lattices to clear"
			return
		end
		if clearAll:GetAttribute("Armed") ~= true then
			clearAll:SetAttribute("Armed", true)
			clearAll.Text = "CLICK AGAIN"
			status.Text = "Click CLEAR ALL again within 4 seconds to remove every lattice on this rig"
			task.delay(4, function()
				if clearAll.Parent and clearAll:GetAttribute("Armed") then
					clearAll:SetAttribute("Armed", false)
					clearAll.Text = "CLEAR ALL"
				end
			end)
			return
		end
		clearAll:SetAttribute("Armed", false)
		clearAll.Text = "CLEAR ALL"
		local success, result = pcall(Modifier.clear, targetRig)
		if success then
			cache = ensureCache(targetRig)
			selectState(cache.lattices[1])
			status.Text = string.format("Cleared %d lattice(s) and their animation tracks", result)
		else
			status.Text = tostring(result):match("^[^\n]+") or "Could not clear lattices"
		end
	end))
	local function keySelectedPoint()
		local success, result = xpcall(function()
			assert(active and selectedPoint, "Select a control point first")
			local pointNumber = selectedPoint
			local x, y, z = tonumber(inputs.X.Text), tonumber(inputs.Y.Text), tonumber(inputs.Z.Text)
			assert(x and y and z, "Enter numeric X, Y and Z values")
			local id = PREFIX .. hex(active.id) .. ":" .. tostring(pointNumber)
			local Properties = require("Properties")
			local timeline = refs.State.Timeline
			local raw = timeline:GetState()
			local motor = Properties.enable(active.rig, id, true, raw)
			if refs.RefreshStructure then refs.RefreshStructure() end
			local value = Vector3.new(x, y, z)
			Modifier.write(active.rig, id, value)
			Modifier.flush(active.rig)
			local frame = refs.GetFrame and refs.GetFrame() or timeline:TimeToFrame(raw.CurrentTime)
			timeline:RecordKeyframeForMotorAtCurrentTime(active.rig, motor, CFrame.new(value), { PropertyValue = value, Frame = frame })
			timeline:ApplyPoseAtTime(active.rig, raw.CurrentTime)
			timeline:UpdatePlayhead()
			selectState(active, pointNumber)
			status.Text = string.format("Point %d keyed at frame %d", pointNumber, frame)
		end, debug.traceback)
		if not success then status.Text = tostring(result):match("^[^\n]+") or "Unable to key control point"; warn("[SUN Lattice] " .. tostring(result)) end
	end
	table.insert(connections, key.Activated:Connect(keySelectedPoint))
	table.insert(connections, pointLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		pointList.CanvasSize = UDim2.fromOffset(0, pointLayout.AbsoluteContentSize.Y + 4)
	end))
	local function getPointFromScreen(point, mode)
		local camera = workspace.CurrentCamera
		if not camera or not active then return nil end
		local nearest, minDistance
		for _, row in buttons do
			local screenPoint, visible
			if mode == "viewport" or mode == "pluginViewport" then
				screenPoint, visible = camera:WorldToViewportPoint(row.part.Position)
			else
				screenPoint, visible = camera:WorldToScreenPoint(row.part.Position)
			end
			if visible and screenPoint.Z > 0 then
				local dx, dy = screenPoint.X - point.X, screenPoint.Y - point.Y
				local distance = dx * dx + dy * dy
				if distance < 1024 and (not minDistance or distance < minDistance) then nearest, minDistance = row.index, distance end
			end
		end
		return nearest
	end
	local function overPanel(point)
		local p, s = panel.AbsolutePosition, panel.AbsoluteSize
		return point.X >= p.X and point.X <= p.X + s.X and point.Y >= p.Y and point.Y <= p.Y + s.Y
	end
	local dragging
	local pluginMouse = refs.Plugin and refs.Plugin:GetMouse()
	local function pointerCandidates()
		local screen, inset = UserInputService:GetMouseLocation(), GuiService:GetGuiInset()
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
		local screen = UserInputService:GetMouseLocation()
		if mode == "viewport" then
			local inset = GuiService:GetGuiInset()
			return Vector2.new(screen.X - inset.X, screen.Y - inset.Y)
		end
		return screen
	end
	local function overPanelAtPointer()
		local point = UserInputService:GetMouseLocation()
		local p, s = panel.AbsolutePosition, panel.AbsoluteSize
		return point.X >= p.X and point.X <= p.X + s.X and point.Y >= p.Y and point.Y <= p.Y + s.Y
	end
	local function pointOnDragPlane(camera, point, origin, normal, mode)
		local isViewport = mode == "viewport" or mode == "pluginViewport"
		local ray = isViewport and camera:ViewportPointToRay(point.X, point.Y)
			or camera:ScreenPointToRay(point.X, point.Y)
		local denominator = ray.Direction:Dot(normal)
		if math.abs(denominator) < 1e-6 then return nil end
		local distance = (origin - ray.Origin):Dot(normal) / denominator
		if distance < 0 then return nil end
		return ray.Origin + ray.Direction * distance
	end
	local function beginPointDrag(fromPluginMouse)
		if dragging or not panel.Visible or not active then return end
		if overPanelAtPointer() or UserInputService:GetFocusedTextBox() then return end
		local timeline = refs.State and refs.State.Timeline
		if timeline and timeline:GetState().Playing then return end
		local camera = workspace.CurrentCamera
		if not camera then return end
		local point, coordinateMode, index
		for _, candidate in pointerCandidates() do
			local candidateIndex = getPointFromScreen(candidate.point, candidate.mode)
			if candidateIndex then
				point, coordinateMode, index = candidate.point, candidate.mode, candidateIndex
				break
			end
		end
		if not index then return end
		local planePoint = active.points[index]
		local planeNormal = camera.CFrame.LookVector
		local projected = pointOnDragPlane(camera, point, planePoint, planeNormal, coordinateMode)
		if not projected then return end
		selectedPoint = index
		dragging = {
			index = index, planePoint = planePoint, normal = planeNormal, coordinateMode = coordinateMode,
			offset = planePoint - projected, start = point, state = active,
		}
		drawState(active)
		selectedLabel.Text = "Control point " .. index .. " · drag its orange handle"
		inputs.X.Text, inputs.Y.Text, inputs.Z.Text = tostring(active.points[index].X), tostring(active.points[index].Y), tostring(active.points[index].Z)
	end
	local function movePointDrag()
		if not dragging then return end
		local camera = workspace.CurrentCamera
		local point = pointerForMode(dragging.coordinateMode)
		if not camera or not point then return end
		local projected = pointOnDragPlane(camera, point, dragging.planePoint, dragging.normal, dragging.coordinateMode)
		if not projected then return end
		local position = projected + dragging.offset
		if (position - active.points[dragging.index]).Magnitude < 1e-5 then return end
		local id = PREFIX .. hex(active.id) .. ":" .. tostring(dragging.index)
		Modifier.write(active.rig, id, position)
		Modifier.flush(active.rig)
		selectedLabel.Text = string.format("Moving point %d  ·  %.2f, %.2f, %.2f", dragging.index, position.X, position.Y, position.Z)
		for _, row in buttons do if row.index == dragging.index then row.part.Position = position end end
		inputs.X.Text, inputs.Y.Text, inputs.Z.Text = tostring(position.X), tostring(position.Y), tostring(position.Z)
	end
	local function endPointDrag()
		if not dragging then return end
		local drag = dragging
		dragging = nil
		selectedPoint = drag.index
		if drag.state ~= active then return end
		keySelectedPoint()
	end
	if pluginMouse then
		table.insert(connections, pluginMouse.Button1Down:Connect(function() beginPointDrag(true) end))
		table.insert(connections, pluginMouse.Move:Connect(movePointDrag))
		table.insert(connections, pluginMouse.Button1Up:Connect(endPointDrag))
	end
	table.insert(connections, UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then beginPointDrag(false) end
	end))
	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then movePointDrag() end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then endPointDrag() end
	end))
	table.insert(connections, RunService.RenderStepped:Connect(function()
		if dragging then movePointDrag() end
	end))
	local function refreshRig()
		local nextRig = currentRig()
		if nextRig ~= rig then
			rig = nextRig
			cache = rig and ensureCache(rig)
			local states = cache and cache.lattices or {}
			selectState(states[1])
			status.Text = #states > 0 and (tostring(#states) .. " lattice(s) loaded") or "Set cage size, select a model, then build the cage"
		end
	end
	table.insert(connections, Selection.SelectionChanged:Connect(function()
		refreshRig()
	end))
	refreshRig()
end

function Modifier.init(newRefs)
	Modifier.destroy()
	refs = newRefs
	if refs.ScreenGui then
		table.insert(connections, refs.ScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not refs.ScreenGui.Enabled then
				if orbitTween then orbitTween:Pause() end
				clearMarkers()
			elseif panel and panel.Visible then
				if orbitTween then orbitTween:Play() end
				drawState(active)
			end
		end))
	end
	if refs.Plugin then
		table.insert(connections, refs.Plugin.Unloading:Connect(function()
			Modifier.destroy()
		end))
	end
end

function Modifier.destroy()
	-- Remove preview deformation before a reload/unload. The lattice's original
	-- mesh is retained, and the next session can safely reapply its animation.
	for rig in rigs do
		pcall(Modifier.preparePose, rig)
	end
	if orbitTween then orbitTween:Cancel(); orbitTween = nil end
	if panel then panel:Destroy(); panel = nil end
	clearMarkers()
	disconnectAll()
	table.clear(rigs)
	active, selectedPoint = nil, nil
	refs = nil
end

return Modifier

