--!nocheck

local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local SolarLoadingScreen = {}
local activeScreen
local activeCanvas
local activeStatus
local orbitConnection
local generation = 0

local function make(className, parent, name, properties)
	local instance = Instance.new(className)
	instance.Name = name
	for property, value in properties do
		instance[property] = value
	end
	instance.Parent = parent
	return instance
end

local function round(instance, radius)
	make("UICorner", instance, "Round", { CornerRadius = UDim.new(1, 0) })
end

local function stopOrbit()
	if orbitConnection then
		orbitConnection:Disconnect()
		orbitConnection = nil
	end
end

function SolarLoadingScreen.isVisible()
	return activeScreen ~= nil and activeScreen.Parent ~= nil and activeScreen.Enabled
end

function SolarLoadingScreen.setStatus(text)
	if activeStatus and activeStatus.Parent then
		activeStatus.Text = tostring(text or "Loading")
	end
end

function SolarLoadingScreen.show(owner, status)
	if not owner or not owner.Parent then
		return false
	end

	generation += 1
	local token = generation
	stopOrbit()
	if activeScreen then
		activeScreen:Destroy()
	end

	local id = tostring(owner:GetAttribute("SunInstance") or owner.Name):gsub("[^%w_]", "")
	local screen = make("ScreenGui", CoreGui, "_SunSolarLoading_" .. id, {
		DisplayOrder = 10000,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	activeScreen = screen
	local canvas = make("CanvasGroup", screen, "Fade", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 0,
		BorderSizePixel = 0,
		ZIndex = 1,
	})
	activeCanvas = canvas
	make("Frame", canvas, "Backdrop", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(10, 8, 11),
		BackgroundTransparency = 0.035,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 1,
	})

	local center = make("Frame", canvas, "SolarSystem", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.46, 0),
		Size = UDim2.fromOffset(500, 390),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
	})

	local function orbit(name, width, height, rotation, color, transparency)
		local ring = make("Frame", center, name, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(250, 150),
			Size = UDim2.fromOffset(width, height),
			Rotation = rotation,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 3,
		})
		round(ring, 1)
		make("UIStroke", ring, "OrbitLine", {
			Color = color,
			Thickness = 1,
			Transparency = transparency,
		})
	end

	orbit("InnerOrbit", 174, 94, -24, Color3.fromRGB(238, 151, 74), 0.48)
	orbit("MiddleOrbit", 258, 142, 21, Color3.fromRGB(198, 139, 89), 0.60)
	orbit("OuterOrbit", 352, 190, -13, Color3.fromRGB(137, 111, 98), 0.72)

	local sunHalo = make("Frame", center, "SunHalo", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(250, 150),
		Size = UDim2.fromOffset(74, 74),
		BackgroundColor3 = Color3.fromRGB(255, 125, 42),
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		ZIndex = 5,
	})
	round(sunHalo, 1)
	local sun = make("Frame", center, "Sun", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(250, 150),
		Size = UDim2.fromOffset(46, 46),
		BackgroundColor3 = Color3.fromRGB(255, 159, 55),
		BorderSizePixel = 0,
		ZIndex = 7,
	})
	round(sun, 1)
	make("UIGradient", sun, "Flare", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 222, 133)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(238, 93, 34)),
		}),
		Rotation = 35,
	})

	local planetSpecs = {
		{ radius = 3, orbitX = 87, orbitY = 47, speed = 1.05, phase = 0.8, color = Color3.fromRGB(255, 213, 154) },
		{ radius = 5, orbitX = 129, orbitY = 71, speed = -0.73, phase = 2.1, color = Color3.fromRGB(244, 130, 72) },
		{ radius = 7, orbitX = 176, orbitY = 95, speed = 0.49, phase = 4.0, color = Color3.fromRGB(119, 167, 210) },
		{ radius = 4, orbitX = 129, orbitY = 71, speed = 0.91, phase = 5.4, color = Color3.fromRGB(214, 183, 136) },
	}
	local planets = {}
	for i, spec in ipairs(planetSpecs) do
		local planet = make("Frame", center, "Planet" .. i, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(250, 150),
			Size = UDim2.fromOffset(spec.radius * 2, spec.radius * 2),
			BackgroundColor3 = spec.color,
			BorderSizePixel = 0,
			ZIndex = 8,
		})
		round(planet, 1)
		planets[i] = { object = planet, spec = spec }
	end

	local wordmark = make("TextLabel", center, "Wordmark", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(250, 268),
		Size = UDim2.fromOffset(240, 30),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "SUN",
		TextColor3 = Color3.fromRGB(255, 229, 199),
		TextSize = 18,
		ZIndex = 4,
	})
	local status = make("TextLabel", center, "Status", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(250, 303),
		Size = UDim2.fromOffset(380, 22),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = tostring(status or "Loading project"),
		TextColor3 = Color3.fromRGB(186, 160, 138),
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 4,
	})
	activeStatus = status
	local progressTrack = make("Frame", center, "ProgressTrack", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(250, 343),
		Size = UDim2.fromOffset(190, 3),
		BackgroundColor3 = Color3.fromRGB(61, 43, 34),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 4,
	})
	round(progressTrack, 1)
	local progress = make("Frame", progressTrack, "Glow", {
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(0.32, 1),
		BackgroundColor3 = Color3.fromRGB(255, 151, 59),
		BorderSizePixel = 0,
		ZIndex = 5,
	})
	round(progress, 1)

	local progressTween = TweenService:Create(progress, TweenInfo.new(0.85, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Position = UDim2.new(0.68, 0, 0, 0),
	})
	progressTween:Play()

	local elapsed = 0
	orbitConnection = RunService.RenderStepped:Connect(function(dt)
		if token ~= generation or not center.Parent then
			stopOrbit()
			return
		end
		elapsed += dt
		for _, planetData in ipairs(planets) do
			local spec = planetData.spec
			local angle = elapsed * spec.speed + spec.phase
			planetData.object.Position = UDim2.fromOffset(
				250 + math.cos(angle) * spec.orbitX,
				150 + math.sin(angle) * spec.orbitY
			)
		end
	end)

	return true
end

function SolarLoadingScreen.hide()
	if not activeScreen then
		return
	end
	local screen, canvas = activeScreen, activeCanvas
	activeScreen, activeCanvas, activeStatus = nil, nil, nil
	generation += 1
	stopOrbit()
	if canvas and canvas.Parent then
		local tween = TweenService:Create(canvas, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			GroupTransparency = 1,
		})
		tween:Play()
		Debris:AddItem(screen, 0.32)
	else
		screen:Destroy()
	end
end

function SolarLoadingScreen.destroy()
	local screen = activeScreen
	activeScreen, activeCanvas, activeStatus = nil, nil, nil
	generation += 1
	stopOrbit()
	if screen then
		screen:Destroy()
	end
end

return SolarLoadingScreen

