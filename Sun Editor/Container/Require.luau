--!nocheck

local Container = script.Parent
local index
local nameConnections = setmetatable({}, { __mode = "k" })
local legacyNames = {
	M = "MatrixMath",
	fov = "CameraProjection",
	root = "StorageRoots",
	context = "ExportContext",
	snapshot = "SceneSnapshot",
}

-- These ModuleScripts are source-sync namespaces, not runtime dependencies.
local moduleGroups = {
	Shared = true,
	Storage = true,
	Timeline = true,
	Rigging = true,
	Geometry = true,
	Camera = true,
	Core = true,
	Animation = true,
	Effects = true,
	Input = true,
	Interface = true,
	Utility = true,
}

local function isNamespace(instance)
	return instance.Parent == Container and moduleGroups[instance.Name] == true
end

local function addName(map, name, module)
	local previous = map[name]
	if previous and previous ~= module then
		error(string.format(
			'Ambiguous SUN module name "%s": %s and %s',
			name,
		tostring(previous),
		tostring(module)
	), 0)
	end
	map[name] = module
end

local function buildIndex()
	local map = {}
	local descendants = {}
	for _, descendant in Container:GetDescendants() do
		if descendant and descendant.Parent then
			table.insert(descendants, descendant)
		end
	end
	table.sort(descendants, function(a, b)
		if not a then
			return false
		elseif not b then
			return true
		end
		return a:GetFullName() < b:GetFullName()
	end)

	for _, descendant in descendants do
		if descendant and descendant.Parent and descendant:IsA("ModuleScript") and descendant ~= script and not isNamespace(descendant) then
			addName(map, descendant.Name, descendant)
		end
	end

	-- Preserve the optional Sun/Eclipse family aliases while keeping exact names
	-- authoritative. Only add aliases when no explicitly named module exists.
	for name, module in map do
		local alias
		if name:sub(1, 3) == "Sun" then
			alias = "Eclipse" .. name:sub(4)
		elseif name:sub(1, 7) == "Eclipse" then
			alias = "Sun" .. name:sub(8)
		end
		if alias and map[alias] == nil then
			map[alias] = module
		end
	end

	return map
end

local function watchName(instance)
	if not instance or not instance.Parent or not instance:IsA("ModuleScript") or instance == script or isNamespace(instance) then
		return
	end
	if not nameConnections[instance] then
		nameConnections[instance] = instance:GetPropertyChangedSignal("Name"):Connect(function()
			index = nil
		end)
	end
end

for _, descendant in Container:GetDescendants() do
	watchName(descendant)
end

Container.DescendantAdded:Connect(function(descendant)
	index = nil
	watchName(descendant)
end)
Container.DescendantRemoving:Connect(function()
	index = nil
end)

local function resolve(target)
	if typeof(target) == "Instance" then
		assert(
			target:IsA("ModuleScript") and target:IsDescendantOf(Container),
			"Sun requires a bundled ModuleScript"
		)
		return require(target)
	end

	assert(type(target) == "string", "Sun module names must be strings")
	if not index then
		index = buildIndex()
	end

	local module = index[target] or index[legacyNames[target]]
	if not module then
		error("Unknown Sun module: " .. target, 2)
	end
	return require(module)
end

return resolve

