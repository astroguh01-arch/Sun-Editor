--!nocheck


local require = require(script:FindFirstAncestor("Container").Require)

local Http = game:GetService("HttpService")
local Paths = {}
local Preview = require("RigPreview")

function Paths.of(object, root, localOnly)
	if not localOnly then
		object, root = Preview.original(object), Preview.original(root)
	end

	local path = {}
	while object and object ~= root do
		local parent = object.Parent
		if not parent then
			return nil
		end

		local index = 0
		for _, child in parent:GetChildren() do
			if child.Name == object.Name and child.ClassName == object.ClassName then
				index += 1
			end

			if child == object then
				break
			end
		end

		table.insert(path, 1, { object.Name, object.ClassName, index })
		object = parent
	end

	return object == root and Http:JSONEncode(path) or nil
end

function Paths.resolve(root, path)
	local object = root
	for _, step in Http:JSONDecode(path) do
		local count, found = 0, nil
		for _, child in object:GetChildren() do
			if child.Name == step[1] and child.ClassName == step[2] then
				count += 1
				if count == step[3] then
					found = child
					break
				end
			end
		end

		if not found then
			return nil
		end

		object = found
	end

	return Preview.localOf(object)
end

function Paths.motor(motor, rig, liveIdentity)
	if typeof(motor) == "table" and motor.IsSunProperty then
		return "property:" .. motor.PropertyId
	end

	if typeof(motor) == "table" and motor.IsSunMasterControl then
		return "master"
	end

	if liveIdentity and typeof(motor) == "table" and motor.IsSunR6Control then
		local owner = Paths.motor(motor.Owner, rig)
		return owner and "r6:" .. motor:GetAttribute("SunR6Control") .. ":" .. owner
	end

	local part = motor.Part1
	local id = part and part:GetAttribute("SunArmatureBoneId")
	if id then
		return "armature:" .. id
	end

	if part then
		local path = Paths.of(part, rig)
			or typeof(motor) == "table"
				and motor.IsSunR6Control
				and Paths.of(part, rig, true)
		if path then
			return path
		end

		local linked = require("TrackOrganizationStorage").bindingPath(rig, part)
		if linked then
			return "joint:" .. Http:JSONEncode(linked)
		end
	end

	return nil
end

function Paths.excluded(object, root)
	while object and object ~= root do
		if
			object:IsA("LuaSourceContainer")
			or object:IsA("KeyframeSequence")
			or object.Name == "AnimSaves"
			or object:GetAttribute("SunPartRigRoot")
			or object:GetAttribute("SunGeneratedVisual")
			or object:GetAttribute("SunArmatureSkinningHelper")
		then
			return true
		end

		object = object.Parent
	end

	return false
end

return Paths
