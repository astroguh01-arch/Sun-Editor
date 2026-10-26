--!nocheck

local require = require(script:FindFirstAncestor("Container").Require)
local LimbIK = require("LimbIK")
local LimbSolver = require("LimbSolver")
local MotorMath = require("MotorMath")
local Parenting = require("Parenting")
local Preferences = require("Preferences")

local EnvironmentalSnap = {}

local rayParamsCache = setmetatable({}, { __mode = "k" })
local filterRevision = 0

-- Preview content can live under CurrentCamera, not directly under Workspace.
-- Track only preview-container lifecycle changes so ordinary rig edits do not
-- invalidate every cached ray filter.
local function isPreviewContainer(instance)
	return instance:IsA("Folder") and (
		instance:GetAttribute("SunLocalLivePreview") == true
		or instance:GetAttribute("SunEffectsFolder") == true
		or instance.Name == "SunLivePreview"
		or instance.Name == "SunLocalPreview"
	)
end

workspace.DescendantAdded:Connect(function(instance)
	if isPreviewContainer(instance) then
		filterRevision += 1
	end
end)
workspace.DescendantRemoving:Connect(function(instance)
	if isPreviewContainer(instance) then
		filterRevision += 1
	end
end)

local function buildFilter(rig, extraFilter)
	local filter = { rig }
	for _, descendant in workspace:GetDescendants() do
		if isPreviewContainer(descendant) then
			table.insert(filter, descendant)
		end
	end
	for _, item in ipairs(extraFilter or {}) do
		if item and item.Parent then
			table.insert(filter, item)
		end
	end
	return filter
end

local function getRayParams(rig, extraFilter)
	local params
	local filter
	if extraFilter then
		params = RaycastParams.new()
		filter = buildFilter(rig, extraFilter)
	else
		local cached = rayParamsCache[rig]
		if not cached then
			cached = { params = RaycastParams.new(), revision = -1, filter = nil }
			rayParamsCache[rig] = cached
		end
		if cached.revision ~= filterRevision then
			cached.filter = buildFilter(rig)
			cached.revision = filterRevision
		end
		params = cached.params
		filter = cached.filter
	end
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.FilterDescendantsInstances = filter
	return params
end

function EnvironmentalSnap.isEnabled(rig)
	if not rig then
		return false
	end
	if rig:GetAttribute("EnvironmentalSnapping") ~= nil then
		return rig:GetAttribute("EnvironmentalSnapping") == true
	end
	local pref = Preferences.get("EnvironmentalSnapping")
	if pref ~= nil then
		return pref == true
	end
	return true
end

function EnvironmentalSnap.setEnabled(rig, enabled)
	if rig then
		rig:SetAttribute("EnvironmentalSnapping", enabled == true)
	end
end

local function keyframeOverride(entry, time)
	local timeline = require("RawState").Timeline
	local fps = timeline and timeline.FPS
	if not timeline or type(fps) ~= "number" or fps <= 0 then
		return nil
	end

	local frame = math.floor(time * fps + 0.5)
	local found, enabled = false, false
	for _, motor in ipairs(entry.motors or {}) do
		local bucket = timeline.Keyframes[motor]
		local key = bucket and bucket[frame]
		if key and type(key.EnvironmentalSnap) == "boolean" then
			found = true
			enabled = enabled or key.EnvironmentalSnap
		end
	end

	if found then
		return enabled
	end
	return nil
end

local function applyFootPlanting(rig, chain, entry, params, weight, snapState)
	local footMotor = chain.motors[#chain.motors]
	if not footMotor or not footMotor.Part1 or not footMotor.Part0 then
		return false
	end

	local map = entry.map
	local footWorldCF = Parenting.worldOf(footMotor, map)
	local footSize = footMotor.Part1.Size
	local soleOffset = Vector3.new(0, -footSize.Y * 0.5, 0)
	local legLength = 0
	for index = 1, #chain.motors - 1 do
		local segment = chain.motors[index].Part1
		if segment then
			legLength += segment.Size.Y
		end
	end
	legLength = math.max(legLength, footSize.Y, 1)

	local sampleOffsets = {
		Vector3.zero,
		Vector3.new(footSize.X * 0.4, 0, 0),
		Vector3.new(-footSize.X * 0.4, 0, 0),
		Vector3.new(0, 0, footSize.Z * 0.4),
		Vector3.new(0, 0, -footSize.Z * 0.4),
	}
	local contactPosition, normalSum, hitCount = Vector3.zero, Vector3.zero, 0
	for _, offset in ipairs(sampleOffsets) do
		local sample = (footWorldCF * CFrame.new(soleOffset + offset)).Position
		local hit = workspace:Raycast(
			sample + Vector3.new(0, 0.25, 0),
			Vector3.new(0, -(legLength + footSize.Y + 0.75), 0),
			params
		)
		if hit and hit.Normal.Y > 0.1 then
			contactPosition += hit.Position
			normalSum += hit.Normal.Unit
			hitCount += 1
		end
	end
	if hitCount == 0 or normalSum.Magnitude < 1e-4 then
		return false
	end

	contactPosition /= hitCount
	local hitNormal = normalSum.Unit
	local baseRotation = footWorldCF - footWorldCF.Position
	local align = LimbSolver.rotationBetween(Vector3.yAxis, hitNormal)
	local alignedRotation = align * baseRotation
	local blend = math.clamp(weight, 0, 1)
	local targetRotation = baseRotation:Lerp(alignedRotation, blend)
	local contactFootPosition = contactPosition - targetRotation:VectorToWorldSpace(soleOffset)
	local targetFootPos = footWorldCF.Position:Lerp(contactFootPosition, blend)

	local rootPart = rig:FindFirstChild("HumanoidRootPart")
	local bodyPart = rig:FindFirstChild("LowerTorso") or rig:FindFirstChild("Torso")
	local rootMotor = bodyPart and map[bodyPart]
	if rootMotor and rootMotor.Part0 ~= rootPart then
		rootMotor = nil
	end

	-- If contact is beyond the leg's reach, translate the shared body root toward
	-- the contact first. This prevents IK from pulling the foot away from its leg.
	local maxReach = math.max(legLength * 0.94, footSize.Y * 0.6)
	local ikTargetPos = targetFootPos
	if chain.kind == "R6" then
		-- R6 IK targets the end of its single leg segment, while R15 targets
		-- the foot part center. Shift the R6 target from center to sole.
		ikTargetPos += targetRotation:VectorToWorldSpace(soleOffset)
	end
	local hip = select(1, LimbIK.geometry(chain))
	local toTarget = ikTargetPos - hip
	if toTarget.Magnitude > maxReach and rootMotor and rootMotor.Part0 then
		snapState.rootShift = snapState.rootShift or Vector3.zero
		snapState.maxRootShift = math.max(snapState.maxRootShift or 0, legLength * 2.0)
		local wantedShift = toTarget.Unit * (toTarget.Magnitude - maxReach * 0.97)
		local cumulative = snapState.rootShift + wantedShift
		if cumulative.Magnitude > snapState.maxRootShift then
			cumulative = cumulative.Unit * snapState.maxRootShift
		end
		local worldShift = cumulative - snapState.rootShift
		if worldShift.Magnitude > 1e-4 then
			local localShift = rootMotor.Part0.CFrame:VectorToObjectSpace(worldShift * blend)
			local rotation = rootMotor.C0 - rootMotor.C0.Position
			rootMotor.C0 = CFrame.new(rootMotor.C0.Position + localShift) * rotation
			snapState.rootShift += worldShift * blend
			footWorldCF = Parenting.worldOf(footMotor, map)
			targetFootPos = footWorldCF.Position:Lerp(contactFootPosition, blend)
			ikTargetPos = targetFootPos
			if chain.kind == "R6" then
				ikTargetPos += targetRotation:VectorToWorldSpace(soleOffset)
			end
			hip = select(1, LimbIK.geometry(chain))
		end
	end

	-- Keep the final endpoint strictly inside a comfortable IK reach envelope.
	local reachVector = ikTargetPos - hip
	if reachVector.Magnitude > maxReach then
		ikTargetPos = hip + reachVector.Unit * maxReach
		if chain.kind == "R6" then
			targetFootPos = ikTargetPos - targetRotation:VectorToWorldSpace(soleOffset)
		else
			targetFootPos = ikTargetPos
		end
	end
	local targetFootCF = CFrame.new(ikTargetPos) * targetRotation
	local kneeFwd = footWorldCF.LookVector
	local pole = CFrame.new(ikTargetPos + kneeFwd * 3 + Vector3.new(0, 1, 0))
	return LimbIK.solve(chain, targetFootCF, pole) == true
end

local function applyObjectGripping(chain, entry, params, weight)
	local handMotor = chain.motors[#chain.motors]
	if not handMotor or not handMotor.Part1 or not handMotor.Part0 then
		return false
	end

	local map = entry.map
	local handWorldCF = Parenting.worldOf(handMotor, map)
	local palmCenter = handWorldCF.Position
	local reachDir = handWorldCF.LookVector
	local probeRay = workspace:Raycast(palmCenter - reachDir * 0.3, reachDir * 2.8, params)
	if not probeRay or not probeRay.Instance or not probeRay.Instance:IsA("BasePart") then
		return false
	end

	local hitPart = probeRay.Instance
	local hitPos = probeRay.Position
	local hitNormal = probeRay.Normal
	local handSize = handMotor.Part1.Size
	local targetHandPos = hitPos + hitNormal * (handSize.Y * 0.4 * weight)
	local alignRot = LimbSolver.rotationBetween(handWorldCF.UpVector, -hitNormal)
	local targetHandCF = CFrame.new(targetHandPos) * alignRot * (handWorldCF - handWorldCF.Position)
	local isRight = chain.motors[1].Name:find("Right") ~= nil
	local elbowPole = CFrame.new(targetHandPos - reachDir * 2 + handWorldCF.RightVector * (if isRight then 2 else -2))
	local solved = LimbIK.solve(chain, targetHandCF, elbowPole) == true
	if not solved then
		return false
	end

	local objSize = hitPart.Size
	local localNormal = hitPart.CFrame:VectorToObjectSpace(hitNormal)
	local thickness = math.abs(localNormal.X) * objSize.X + math.abs(localNormal.Y) * objSize.Y + math.abs(localNormal.Z) * objSize.Z
	thickness = math.clamp(thickness, 0.2, 3.0)
	local wrapAngle = math.clamp(math.pi / (1.5 + thickness * 1.5), 0.2, 1.25) * weight
	for _, m in entry.motors do
		if m.Part0 == handMotor.Part1 and m.Part1 then
			local name = m.Part1.Name:lower()
			if name:find("thumb") or name:find("index") or name:find("middle") or name:find("ring") or name:find("pinky") or name:find("finger") then
				m.C0 = m.C0 * CFrame.Angles(wrapAngle, 0, 0)
			end
		end
	end
	return true
end

local function applyLeanAndTilt(rig, entry, params, weight)
	local rootPart = rig:FindFirstChild("HumanoidRootPart")
		or rig:FindFirstChild("LowerTorso")
		or (rig.PrimaryPart and rig.PrimaryPart ~= rig:FindFirstChild("Head") and rig.PrimaryPart)
		or rig:FindFirstChild("Torso")
	if not rootPart then
		return false
	end

	local rootCF = rootPart.CFrame
	local center = rootCF.Position
	local offsets = {
		Vector3.zero,
		rootCF.LookVector * 1.5,
		-rootCF.LookVector * 1.5,
		rootCF.RightVector * 1.2,
		-rootCF.RightVector * 1.2,
	}
	local normalSum, normalCount = Vector3.zero, 0
	local slopeSum, slopeWeight = Vector3.zero, 0
	for _, offset in ipairs(offsets) do
		local origin = center + offset + Vector3.new(0, 8, 0)
		local hit = workspace:Raycast(origin, Vector3.new(0, -16, 0), params)
		if hit and hit.Normal.Y > 0.15 then
			local normal = hit.Normal.Unit
			normalSum += normal
			normalCount += 1
			-- Flat ground should not cancel the incline when a foot/root sample
			-- also lands on a wedge. Give the actual slope samples more influence.
			local inclineWeight = math.clamp(1 - normal.Y, 0, 1)
			if inclineWeight > 1e-3 then
				slopeSum += normal * inclineWeight
				slopeWeight += inclineWeight
			end
		end
	end

	if normalCount == 0 then
		return false
	end
	local normalSource = slopeWeight > 1e-3 and slopeSum or normalSum
	if normalSource.Magnitude < 1e-4 then
		return false
	end
	local slopeNormal = normalSource.Unit
	-- Calculate the surface rotation in world space, then express its axis in
	-- the waist joint's Part0 space before writing Motor6D.C0.
	local worldTilt = LimbSolver.rotationBetween(rootCF.UpVector, slopeNormal)
	local axisWorld, angle = worldTilt:ToAxisAngle()
	angle = math.clamp(angle, 0, math.rad(35)) * 0.45 * math.clamp(weight, 0, 1)
	if angle < math.rad(0.25) then
		return false
	end

	local map = entry.map
	local upperTorso = rig:FindFirstChild("UpperTorso")
	local torso = rig:FindFirstChild("Torso")
	-- entry.map is indexed by Part1 instances, not part names.
	local waistMotor = (upperTorso and map[upperTorso]) or (torso and map[torso])
	if waistMotor and waistMotor.Part0 then
		local axisLocal = waistMotor.Part0.CFrame:VectorToObjectSpace(axisWorld)
		if axisLocal.Magnitude > 1e-4 then
			local baseRotation = waistMotor.C0 - waistMotor.C0.Position
			waistMotor.C0 = CFrame.new(waistMotor.C0.Position)
				* CFrame.fromAxisAngle(axisLocal.Unit, angle)
				* baseRotation
			return true
		end
	end
	return false
end

function EnvironmentalSnap.apply(rig, time, options)
	if not rig or not rig.Parent or not rig:IsDescendantOf(workspace) then
		return false
	end

	local entry = LimbIK.getRig(rig)
	if not entry then
		return false
	end

	local keyframeEnabled = keyframeOverride(entry, time)
	local enabled = options and options.Force == true
		or (if keyframeEnabled ~= nil then keyframeEnabled else EnvironmentalSnap.isEnabled(rig))
	if not enabled then
		return false
	end

	local weight = math.clamp(rig:GetAttribute("EnvironmentalSnapWeight") or 1.0, 0, 1)
	if weight <= 0 then
		return false
	end

	local params = getRayParams(rig, options and options.IgnoreInstances)
	local solved = applyLeanAndTilt(rig, entry, params, weight) == true
	local snapState = { rootShift = Vector3.zero, maxRootShift = 0 }
	for _, chain in entry.chains do
		if chain.limb == "Leg" then
			solved = applyFootPlanting(rig, chain, entry, params, weight, snapState) or solved
		elseif chain.limb == "Arm" then
			solved = applyObjectGripping(chain, entry, params, weight) or solved
		end
	end
	return solved
end


return EnvironmentalSnap


