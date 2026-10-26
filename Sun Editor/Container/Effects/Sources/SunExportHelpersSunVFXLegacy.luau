-- Sun-owned VFX runtime; legacy third-party factories removed.
return function(require)
return function(env, emitChild)
	local game = env.game or game
	local workspace = env.workspace or workspace
	local task = env.task or task
	local Instance = env.Instance or Instance
	local math = env.math or math
	local api = { scopes = {}, _live = {}, _pending = {}, _closed = false }
	local terrain = workspace.Terrain
	local runService = game:GetService("RunService")

	local function number(value, fallback)
		if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
			return value
		end
		return fallback
	end

	local function range(value, fallback)
		if typeof(value) == "NumberRange" then
			return value.Min + math.random() * (value.Max - value.Min)
		end
		return number(value, fallback)
	end

	local function cloneSafe(source)
		local wasArchivable = source.Archivable
		source.Archivable = true
		local ok, result = pcall(function() return source:Clone() end)
		source.Archivable = wasArchivable
		if not ok or not result then return nil end
		result.Archivable = false
		for _, descendant in result:GetDescendants() do
			if descendant:IsA("LuaSourceContainer") then descendant:Destroy() end
		end
		for _, descendant in { result, table.unpack(result:GetDescendants()) } do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanTouch = false
				descendant.CanQuery = false
			end
		end
		return result
	end

	local function pivotOf(object)
		if object:IsA("BasePart") then return object.CFrame end
		if object:IsA("Model") then return object:GetPivot() end
		if object:IsA("Attachment") then return object.WorldCFrame end
		return CFrame.new()
	end

	local function setPivot(object, cf)
		if object:IsA("BasePart") then object.CFrame = cf
		elseif object:IsA("Model") then object:PivotTo(cf) end
	end

	local function track(output, lifetime, updater)
		local token = { output = output }
		self = api
		api._live[token] = true
		local elapsed = 0
		local connection
		connection = runService.Heartbeat:Connect(function(dt)
			if api._closed or not output.Parent then
				connection:Disconnect(); api._live[token] = nil
				if output.Parent then output:Destroy() end
				return
			end
			elapsed += dt
			local alpha = math.clamp(elapsed / math.max(lifetime, 0.001), 0, 1)
			if updater then
				local ok = pcall(updater, dt, elapsed, alpha)
				if not ok then connection:Disconnect(); api._live[token] = nil; output:Destroy(); return end
			end
			if elapsed >= lifetime then
				connection:Disconnect(); api._live[token] = nil; output:Destroy()
			end
		end)
		return token
	end

	local function emitTransformed(item)
		local template = item:FindFirstChild("RenderTemplate")
		local config = item:FindFirstChildWhichIsA("Configuration")
		if not template or (config and config:GetAttribute("Enabled") == false) then return end
		local count = math.clamp(math.floor(number(item:GetAttribute("EmitCount"), config and number(config:GetAttribute("EmitCount"), config and number(config:GetAttribute("Rate"), 1) or 1) or 1)), 1, 100)
		local lifeRange = config and config:GetAttribute("Lifetime")
		local speedRange = config and config:GetAttribute("Speed")
		local acceleration = config and config:GetAttribute("Acceleration")
		if typeof(acceleration) ~= "Vector3" then acceleration = Vector3.zero end
		local origin = pivotOf(item)
		local link = item:FindFirstChild("Link")
		if link and link:IsA("ObjectValue") and link.Value then origin = pivotOf(link.Value) end
		for index = 1, count do
			local visual = cloneSafe(template)
			if not visual then continue end
			visual.Parent = terrain
			local lifetime = math.max(0.05, range(lifeRange, 1))
			local speed = range(speedRange, 0)
			local direction = origin.UpVector
			local spread = config and config:GetAttribute("SpreadAngle")
			if typeof(spread) == "Vector2" then
				local rx = math.rad((math.random() - 0.5) * spread.X)
				local rz = math.rad((math.random() - 0.5) * spread.Y)
				direction = (origin * CFrame.Angles(rx, 0, rz)).UpVector
			end
			local start = origin * CFrame.new(0, 0.025 * index, 0)
			local position = start.Position
			local velocity = direction * speed
			setPivot(visual, start)
			track(visual, lifetime, function(dt, elapsed)
				local drag = math.max(0, number(config and config:GetAttribute("Drag"), 0))
				velocity = (velocity + acceleration * dt) * math.exp(-drag * dt)
				position += velocity * dt
				local cf = CFrame.new(position) * start.Rotation
				local rotation = config and config:GetAttribute("Rotation")
				if typeof(rotation) == "Vector3" then
					cf *= CFrame.Angles(math.rad(rotation.X * elapsed), math.rad(rotation.Y * elapsed), math.rad(rotation.Z * elapsed))
				end
				setPivot(visual, cf)
			end)
		end
	end

	local function emitNative(item)
		local output = cloneSafe(item)
		if not output then return end
		output.Name = "SunVFX Output"
		output.Parent = item.Parent or terrain
		local delay = math.max(0, number(item:GetAttribute("EmitDelay"), 0))
		task.delay(delay, function()
			if api._closed or not output.Parent then return end
			if output:IsA("ParticleEmitter") then
				output.Enabled = false
				local scale = number(item:GetAttribute("TimeScale_Start"), item.TimeScale)
				output.TimeScale = math.max(0.01, scale)
				output:Emit(math.clamp(math.floor(number(item:GetAttribute("EmitCount"), 1)), 0, 10000))
				local duration = math.max(0, number(item:GetAttribute("EmitDuration"), 0))
				if duration > 0 then output.Enabled = true; task.delay(duration, function() if output.Parent then output.Enabled = false end end) end
				track(output, math.max(0.1, item.Lifetime.Max / math.max(output.TimeScale, 0.01) + duration))
			else
				output.Enabled = true
				local duration = math.max(0.05, number(item:GetAttribute("EmitDuration"), number(item:GetAttribute("EffectDuration"), number(item:GetAttribute("Duration"), 0.25))))
				if output:IsA("Trail") then duration = math.max(duration, output.Lifetime) end
				task.delay(duration, function() if output.Parent then output.Enabled = false end end)
				track(output, duration + (output:IsA("Trail") and output.Lifetime or 0.1))
			end
		end)
	end

	local function emitSimpleModel(model)
		local start = model:FindFirstChild("Start")
		local finish = model:FindFirstChild("End")
		if start and finish then
			local count = math.clamp(math.floor(number(model:GetAttribute("EmitCount"), 1)), 1, 100)
			local duration = math.max(0.05, number(model:GetAttribute("EffectDuration"), 0.5))
			for index = 1, count do
				local visual = cloneSafe(start)
				if visual then
					visual.Parent = terrain
					local a, b = pivotOf(start), pivotOf(finish)
					track(visual, duration, function(_, _, alpha) setPivot(visual, a:Lerp(b, alpha)) end)
				end
			end
			return
		end
		local spin = model:GetAttribute("SpinRotation")
		if typeof(spin) == "Vector3" then
			local visual = cloneSafe(model)
			if visual then
				visual.Parent = terrain
				local base = pivotOf(model)
				local duration = math.max(0.05, number(model:GetAttribute("EffectDuration"), 1))
				track(visual, duration, function(_, elapsed) setPivot(visual, base * CFrame.Angles(math.rad(spin.X * elapsed), math.rad(spin.Y * elapsed), math.rad(spin.Z * elapsed))) end)
			end
		end
	end

	function api:emit(item)
		if self._closed or not item or not item.Parent then return end
		local ok, err = pcall(function()
			if item:GetAttribute("Transformed") == true then
				emitTransformed(item)
			elseif item:IsA("ParticleEmitter") or item:IsA("Beam") or item:IsA("Trail") or item:IsA("Light") then
				emitNative(item)
			elseif item:IsA("Model") then
				emitSimpleModel(item)
			elseif item:HasTag("BezierParticle") then
				local part = item:IsA("BasePart") and item or item:FindFirstChildWhichIsA("BasePart")
				if part then local output = cloneSafe(part); if output then output.Parent = terrain; track(output, math.max(0.05, number(item:GetAttribute("EffectDuration"), 0.5))) end end
			end
		end)
		if not ok and env.warn then env.warn("SunVFX replacement: " .. tostring(err)) end
	end

	function api:active()
		return next(self._live) ~= nil or next(self._pending) ~= nil
	end

	function api:Destroy()
		if self._closed then return end
		self._closed = true
		for pending in self._pending do
			if pending.output and pending.output.Parent then pending.output:Destroy() end
			self._pending[pending] = nil
		end
		for token in self._live do
			if token.output and token.output.Parent then token.output:Destroy() end
			self._live[token] = nil
		end
	end

	return api
end




end
