--!nocheck


local require = require(script:FindFirstAncestor("Container").Require)
local RigTraversal = require("RigTraversal")
local Cleanup = {}
local named = {
	_SunAnimator_Axis = true,
	_SunAnimator_DragGuides = true,
	SunAnimator_MotionPath = true,
	SunGreasePencil = true,
	SunDrawings = true,
}

local function protected(object, scope)
	local parent = object.Parent
	while parent and parent ~= scope do
		if parent:IsA("LuaSourceContainer") or parent:IsA("ViewportFrame") then
			return true
		end

		parent = parent.Parent
	end

	return false
end

function Cleanup.owned(object)
	if
		(object.Name == "Scale" or object.Name == "SunPropertyScale") and object:IsA("Model")
	then
		local expected = {
			Core = true,
			["+X"] = true,
			["-X"] = true,
			["+Y"] = true,
			["-Y"] = true,
			["+Z"] = true,
			["-Z"] = true,
		}
		local children = object:GetChildren()
		if #children == 7 then
			local matches = true
			for _, child in children do
				if not child:IsA("BasePart") or not expected[child.Name] then
					matches = false
					break
				end

				expected[child.Name] = nil
			end

			if matches and next(expected) == nil then
				return true
			end
		end
	end

	if
		object:GetAttribute("SunTransientAxis") == true
		or object:GetAttribute("SunAnimator_BonesFolder") == true
		or object:GetAttribute("SunCameraDisplay") == true
		or object:GetAttribute("SunPropertyGizmo") == true
	then
		return true
	end

	if object:IsA("Bone") and type(object:GetAttribute("SunR6Control")) == "string" then
		local owner = object:FindFirstChild("SunR6Owner")
		return owner ~= nil and owner:IsA("ObjectValue")
	end

	if named[object.Name] and (object:IsA("Model") or object:IsA("Folder")) then
		return true
	end

	return false
end

function Cleanup.run(scope)
	scope = scope or workspace
	local targets = {}
	for _, object in RigTraversal.descendants(scope) do
		if not protected(object, scope) then
			if object:IsA("Decal") then
				local texture = object:GetAttribute("SunFaceOriginalTexture")
				if object:GetAttribute("SunFaceCreated") == true then
					table.insert(targets, object)
				elseif type(texture) == "string" then
					object.Texture = texture
					object:SetAttribute("SunFaceOriginalTexture", nil)
				end
			elseif Cleanup.owned(object) then
				table.insert(targets, object)
			end
		end
	end

	local count = 0
	for _, object in targets do
		if object.Parent then
			object:Destroy()
			count += 1
		end
	end

	return count
end

return Cleanup
