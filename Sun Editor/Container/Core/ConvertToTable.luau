--!nocheck


local require = require(script:FindFirstAncestor("Container").Require)

local RigTraversal = require("RigTraversal")

local function readEasing(obj, moon)
	local sunEasingKeyData = nil
	local easeFolder = obj:FindFirstChild("Ease")
	if easeFolder then
		local typeValue = easeFolder:FindFirstChild("Type")
		if typeValue then
			sunEasingKeyData = {
				EasingStyle = typeValue.Value,
			}
			if easeFolder:GetAttribute("NativePose") then
				local ok, style = pcall(function()
					return Enum.PoseEasingStyle[typeValue.Value]
				end)
				if ok then
					sunEasingKeyData.EasingStyle = style
				end
			end

			local paramsFolder = easeFolder:FindFirstChild("Params")
			if paramsFolder then
				local p = {}
				for _, val in ipairs(paramsFolder:GetChildren()) do
					if val:IsA("ValueBase") then
						p[val.Name] = val.Value
					end
				end

				sunEasingKeyData.EasingDirection = p.Direction
				sunEasingKeyData.Overshoot = p.Overshoot
				sunEasingKeyData.Amplitude = p.Amplitude
				sunEasingKeyData.Period = p.Period
				if p.X1 ~= nil or p.Y1 ~= nil or p.X2 ~= nil or p.Y2 ~= nil then
					sunEasingKeyData.BezierPoints = {
						p.X1 or 0,
						p.Y1 or 0,
						p.X2 or 1,
						p.Y2 or 1,
					}
				end
			end
		end
	end

	if sunEasingKeyData and moon and not easeFolder:GetAttribute("NativePose") then
		sunEasingKeyData.MoonEasing = true
		if sunEasingKeyData.EasingStyle == "Elastic" then
			sunEasingKeyData.Amplitude = sunEasingKeyData.Amplitude or 1
			sunEasingKeyData.Period = sunEasingKeyData.Period or 0.3
		elseif sunEasingKeyData.EasingStyle == "Back" then
			sunEasingKeyData.Overshoot = sunEasingKeyData.Overshoot or 1.70158
		end
	end

	return sunEasingKeyData
end

return function(AnimationInstance: KeyframeSequence, motorMap)
	if AnimationInstance == nil then
		error("AnimationInstance can't be nil")
	end

	if typeof(AnimationInstance) ~= "Instance" then
		return {}
	end

	local moon = not (
		AnimationInstance:GetAttribute("SunPoseSpace")
		or AnimationInstance:GetAttribute("SunBaked") ~= nil
		or AnimationInstance:GetAttribute("SunHadArmature") ~= nil
		or AnimationInstance:FindFirstChild("SunKeyframeData")
	)
	local detachedJointNames = {}
	local unparentedFolder = AnimationInstance:FindFirstChild("SunUnparentedMotors")
	if unparentedFolder then
		for _, ref in ipairs(unparentedFolder:GetChildren()) do
			local name = ref.Name
			if
				ref:IsA("ObjectValue")
				and ref.Value
				and ref.Value:IsA("Motor6D")
				and ref.Value.Part1
			then
				name = ref.Value.Part1.Name
			end

			if name and name ~= "" then
				detachedJointNames[name] = true
			end
		end
	end

	local fallbackAllowed = AnimationInstance:GetAttribute("SunBaked") == true
		and AnimationInstance:GetAttribute("SunPoseSpace") == "Canonical"
		and AnimationInstance:GetAttribute("SunMasterControl") ~= true
		and not AnimationInstance:FindFirstChild("SunAnimationLayers")
		and not AnimationInstance:FindFirstChild("SunPhysicsData")
		and not AnimationInstance:FindFirstChild("SunCurveModifiers")
	local authored = {}
	local KeyFrames = AnimationInstance:GetKeyframes()
	local names, duplicate = {}, {}
	for _, frame in KeyFrames do
		for _, pose in frame:GetDescendants() do
			if pose:IsA("Pose") then
				local path = RigTraversal.poseKey(pose)
				if names[pose.Name] and names[pose.Name] ~= path then
					duplicate[pose.Name] = true
				end

				names[pose.Name] = path
			end
		end
	end

	local Sequence = table.create(#KeyFrames)
	local fps = AnimationInstance:GetAttribute("FPS")
	local exactTiming = typeof(fps) == "number" and fps >= 1 and fps <= 1000 and fps % 1 == 0

	for _, keyframe: Keyframe in KeyFrames do
		local Frame = {}
		Frame.Time = keyframe.Time
		local exactFrame = keyframe:GetAttribute("SunExactFrame")
		if
			exactTiming
			and typeof(exactFrame) == "number"
			and exactFrame >= 0
			and exactFrame < math.huge
		then
			Frame.Time = exactFrame / fps
		end

		Frame.Data = {}
		Frame.Events = {}

		for _, obj in keyframe:GetDescendants() do
			if obj:IsA("KeyframeMarker") then
				table.insert(Frame.Events, {
					Name = obj.Name,
					Value = obj.Value,
				})
			end

			if obj:IsA("Pose") then
				if obj.Weight == 0 then
					continue
				end

				local jointKey = (duplicate[obj.Name] or motorMap and not motorMap[obj.Name])
						and RigTraversal.poseKey(obj)
					or obj.Name

				local sunEasingKeyData = AnimationInstance:GetAttribute("SunBaked") ~= true
						and readEasing(obj, moon)
					or nil

				local worldCFrame = nil
				local worldVal = obj:FindFirstChild("DetachedWorldCFrame")
				if worldVal and worldVal:IsA("CFrameValue") then
					worldCFrame = worldVal.Value
				end

				if fallbackAllowed then
					local track = authored[jointKey]
					if not track then
						track = { first = obj.CFrame, weight = obj.Weight, keys = {} }
						authored[jointKey] = track
					end

					if not track.first:FuzzyEq(obj.CFrame, 1e-6) or track.weight ~= obj.Weight then
						track.moving = true
					end

					if
						obj:GetAttribute("SunParented") == false
						or obj:GetAttribute("SunIK") == true
						or obj:GetAttribute("SunHS") == true
						or obj:GetAttribute("SunR6Control") ~= nil
						or worldCFrame ~= nil
						or detachedJointNames[obj.Name]
					then
						track.unsafe = true
					end

					local value = obj:GetAttribute("SunLocalPose")
					if typeof(value) == "CFrame" then
						if track.firstAuthored and not track.firstAuthored:FuzzyEq(value, 1e-6) then
							track.authoredMoving = true
						end

						track.firstAuthored = track.firstAuthored or value
						table.insert(track.keys, { frame = Frame, value = value, pose = obj })
					end
				end

				Frame.Data[jointKey] = {
					CFrame = obj.CFrame,
					Weight = obj.Weight,
					PoseEasingStyle = obj.EasingStyle,
					PoseEasingDirection = obj.EasingDirection,
					SunEasingKeyData = sunEasingKeyData,
					WorldCFrame = worldCFrame,
				}
			end
		end

		table.insert(Sequence, Frame)
	end

	table.sort(Sequence, function(a, b)
		return a.Time < b.Time
	end)

	local recovery = {}
	for name, track in authored do
		if
			track.moving
			or track.unsafe
			or not track.authoredMoving
			or #track.keys < 2
			or track.weight ~= 1
		then
			continue
		end

		local unique = {}
		local valid = true
		for _, key in track.keys do
			if unique[key.frame.Time] then
				valid = false
				break
			end

			unique[key.frame.Time] = true
		end

		if valid then
			recovery[name] = true
		end
	end

	return Sequence,
		AnimationInstance.Loop,
		AnimationInstance.Priority,
		detachedJointNames,
		recovery
end
