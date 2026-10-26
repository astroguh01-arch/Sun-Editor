--!nocheck


local require = require(script:FindFirstAncestor("Container").Require)

local Tool = require("Tool")
local Chrome = require("Chrome")
local FX = require("WindowFX")
local Theme = require("Theme")
local Physics = require("Physics")

local function physicalClips()
	local result = {}
	for _, clip in Physics.list() do
		if clip.settings.kind ~= "SmartBone" and clip.settings.kind ~= "BoneDynamics" then
			table.insert(result, clip)
		end
	end

	return result
end

local RunService = game:GetService("RunService")
local Scene = require("Scene")
local Forces = require("Forces")
local Preferences = require("Preferences")
local Notice = require("Notification")
local Window = {}

local function notify(message)
	Notice.show("PHYSICS", message)
end

local refs, window, warning, controls
local revision = 0
local connections = {}

local function numberText(value)
	if typeof(value) ~= "number" then
		return tostring(value)
	end

	return (string.format("%.3f", value):gsub("0+$", ""):gsub("%.$", ""))
end

local function errorText(err)
	local full = tostring(err)
	if full:find("simulation canceled because playback started", 1, true) then
		return "Playback started. Pause it, then simulate again."
	end

	if full:find("simulation canceled", 1, true) then
		return "Canceled. Your animation hasn't changed."
	end

	local message = full:match("^[^\r\n]+") or "Couldn't simulate. Try again."
	while true do
		local stripped, count = message:gsub("^.-:%d+:%s*", "", 1)
		if count == 0 then
			break
		end

		message = stripped
	end

	if #message > 400 then
		return "Couldn't simulate. Check the selected rig and try again."
	end

	return message
end

function Window.isOpen()
	return window ~= nil or warning ~= nil
end

function Window.getFrame()
	return window and window.frame
end

function Window.isEditorOpen()
	return window ~= nil
end

function Window.close(immediate)
	controls = nil
	if warning then
		local old = warning
		warning = nil
		old:close(immediate)
	end

	if refs then
		refs.State.PhysicsSimulating = false
		Physics.preview(false)
	end

	Forces.close()
	if refs and refs.State.GreasePencil and refs.State.GreasePencil.closePhysics then
		refs.State.GreasePencil.closePhysics()
	end

	revision += 1
	if window then
		local old = window
		window = nil
		old:close(immediate)
	end

	require("SceneSync").hide()
end

function Window.destroy()
	require("SceneSync").destroy()
	Window.close(true)
	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
end

function Window.state()
	return controls and controls.state() or {}
end

function Window.run()
	if not refs or not refs.Active() then
		return false
	end

	if refs and refs.State.Timeline:IsExportLocked() then
		return false
	end

	if not controls then
		Window.open()
	end

	if not controls then
		return false
	end

	require("SceneSync").finish(false)
	controls.run()
	return true
end

function Window.includeFrame(frame)
	if controls then
		controls.includeFrame(frame)
	end
end

function Window.jump(frame)
	if refs and refs.State.Timeline:IsExportLocked() then
		return
	end

	if not refs or refs.State.PhysicsSimulating then
		return
	end

	local timeline = refs.State.Timeline
	local raw = timeline:GetState()
	raw.Playing = false
	timeline:EnsureTimelineEnd(frame)
	raw.CurrentTime = frame / raw.FPS
	timeline:UpdatePlayhead()
	if refs.State.currentRig then
		timeline:ApplyPoseAtTime(refs.State.currentRig, raw.CurrentTime)
	end
end

function Window.play()
	if not refs or not refs.Active() then
		return false
	end

	if controls then
		controls.play()
	end
end

local function openWindow()
	if window then
		if window.closed ~= true and window.frame and window.frame.Parent then
			return window.frame
		end

		-- The old UI may have been destroyed by Roblox or by a plugin reload.
		-- Drop its stale handle so this call builds a fresh window from scratch.
		window = nil
		controls = nil
	end

	if not refs or not refs.Active() then
		return
	end

	if Preferences.get("PhysicsAcknowledged") ~= true then
		if warning then
			if warning.closed ~= true and warning.frame and warning.frame.Parent then
				return warning.frame
			end

			warning = nil
		end

		local message =
			"<b>!! VERY experimental</b>\n\nPhysics is still pretty rough, and some of the settings get advanced. Save your project before trying it.\n\nAdd the rigs or parts you want, then simulate. You can play the result before baking it into keys. Your simulations live in this window.\n\nThings might act weird. Please report faults in our Community Server. Find the link on our Creator Store page."
		local textHeight = game:GetService("TextService"):GetTextSize(
			message:gsub("<[^>]+>", ""),
			16,
			Enum.Font.RobotoMono,
			Vector2.new(432, 10000)
		).Y
		warning = Tool.new(
			refs,
			"SunPhysicsWarning",
			"PHYSICS",
			Vector2.new(460, textHeight + 108),
			false,

			function()
				warning = nil
			end
		)
		local host, frame = warning, warning.frame
		local body = Tool.label(
			frame,
			"Message",
			message,
			UDim2.fromOffset(14, 42),
			UDim2.new(1, -28, 1, -98)
		)
		body.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
		body.TextSize = 16
		body.RichText = true
		body.TextColor3 = Color3.new(1, 1, 1)
		body.TextTransparency = 0.12
		body.TextYAlignment = Enum.TextYAlignment.Top
		local cancel, cancelText = Tool.button(
			frame,
			"Cancel",
			"CANCEL",
			UDim2.new(0, 14, 1, -48),
			UDim2.fromOffset(210, 34),

			function()
				host:close()
			end
		)
		cancelText.TextSize = 14
		cancelText.TextTransparency = 0.15
		local proceed, proceedText = Tool.button(
			frame,
			"Proceed",
			"PROCEED",
			UDim2.new(0, 236, 1, -48),
			UDim2.fromOffset(210, 34),

			function()
				local ok = Preferences.set("PhysicsAcknowledged", true)
				if not ok then
					body.Text = "Couldn't save that preference. Close this window and try again."
					return
				end

				host:close(true)
				Window.open()
			end
		)
		proceedText.TextSize = 14
		proceedText.TextTransparency = 0.15
		proceed:SetAttribute("ThemeBg", "MenuSel")
		return frame
	end

	local raw = refs.State.Timeline:GetState()
	window = Tool.new(refs, "SunPhysics", "PHYSICS LAB", Vector2.new(720, 740), false, function()
		window = nil
		controls = nil
		revision += 1
		refs.State.PhysicsSimulating = false
		Physics.preview(false)
		Forces.close()
		if refs.State.GreasePencil and refs.State.GreasePencil.closePhysics then
			refs.State.GreasePencil.closePhysics()
		end

		require("SceneSync").hide()
	end)
	local host, frame = window, window.frame
	local mode, chosen, busy = "Ragdoll", nil, false
	local progress = "CANCEL"
	local hold, setHold
	local listed, repaint, simulate, bake, remove
	local activePanel, openPanel, closePanel
	local clipButtons = {}
	local inputs, tabs = {}, {}

	local function label(parent, name, text, x, y, width, height)
		local object = Tool.label(
			parent,
			name,
			text,
			UDim2.fromOffset(x, y),
			UDim2.fromOffset(width, height or 22)
		)
		object.ZIndex = parent.ZIndex + 3
		return object
	end

	local function panel(parent, name, x, y, width, height)
		local object = Tool.make("Frame", parent, name, {
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(width, height),
			BorderSizePixel = 0,
			ZIndex = 12,
		})
		object:SetAttribute("ThemeBg", "Pnl")
		Tool.make("UICorner", object, "Corner", { CornerRadius = UDim.new(0, 9) })
		local stroke =
			Tool.make("UIStroke", object, "Outline", { Thickness = 1, Transparency = 0.48 })
		stroke:SetAttribute("ThemeStrk", "Strk")
		local accent = Tool.make("Frame", object, "SunAccent", {
			Position = UDim2.fromOffset(0, 12),
			Size = UDim2.new(0, 3, 1, -24),
			BorderSizePixel = 0,
			ZIndex = object.ZIndex + 1,
		})
		accent:SetAttribute("ThemeBg", "MenuSel")
		Tool.make("UICorner", accent, "Corner", { CornerRadius = UDim.new(1, 0) })
		return object
	end

	local function section(parent, name, text, x, y, width)
		local marker = Tool.make("Frame", parent, name .. "Accent", {
			Position = UDim2.fromOffset(x, y + 4),
			Size = UDim2.fromOffset(3, 12),
			BorderSizePixel = 0,
			ZIndex = parent.ZIndex + 2,
		})
		marker:SetAttribute("ThemeBg", "MenuSel")
		Tool.make("UICorner", marker, "Corner", { CornerRadius = UDim.new(1, 0) })
		local title = label(parent, name, text, x + 10, y, width - 10, 20)
		title.TextSize = 11
		title.TextTransparency = 0
		return title
	end

	local function hint(parent, name, text, x, y, width, height)
		local object = label(parent, name, text, x, y, width, height)
		object.TextSize = 11
		object.TextTransparency = 0.2
		return object
	end

	-- Physics Lab is laid out as a small simulation workspace: a branded
	-- orbital header, a setup column, a dynamics bay, and a full-width library.
	local hero = panel(frame, "LabHeader", 12, 44, 696, 96)
	hero.SunAccent.Size = UDim2.fromOffset(3, 68)
	hero.SunAccent.Position = UDim2.fromOffset(0, 14)
	local orbit = Tool.make("Frame", hero, "OrbitMark", {
		Position = UDim2.fromOffset(18, 17),
		Size = UDim2.fromOffset(58, 58),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 13,
	})
	Tool.make("UICorner", orbit, "Circle", { CornerRadius = UDim.new(1, 0) })
	local orbitStroke = Tool.make("UIStroke", orbit, "Orbit", {
		Thickness = 2,
		Transparency = 0.15,
	})
	orbitStroke:SetAttribute("ThemeStrk", "MenuSel")
	local core = Tool.make("Frame", orbit, "SunCore", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(16, 16),
		BorderSizePixel = 0,
		ZIndex = 14,
	})
	core:SetAttribute("ThemeBg", "MenuSel")
	Tool.make("UICorner", core, "Circle", { CornerRadius = UDim.new(1, 0) })
	local satellite = Tool.make("Frame", orbit, "Satellite", {
		Position = UDim2.new(0.72, 0, 0.14, 0),
		Size = UDim2.fromOffset(7, 7),
		BorderSizePixel = 0,
		ZIndex = 15,
	})
	satellite:SetAttribute("ThemeBg", "Txt")
	Tool.make("UICorner", satellite, "Circle", { CornerRadius = UDim.new(1, 0) })
	local labTitle = label(hero, "LabTitle", "PHYSICS LAB", 91, 18, 200, 24)
	labTitle.TextSize = 18
	labTitle.FontFace = Chrome.FONT
	local labSubtitle = label(hero, "LabSubtitle", "Build a setup. Tune the forces. Preview the motion.", 92, 46, 300, 28)
	labSubtitle.TextSize = 11
	labSubtitle.TextTransparency = 0.22
	local phase = label(hero, "LabPhase", "01   SETUP     /     02   DYNAMICS     /     03   RUN", 92, 74, 310, 14)
	phase.TextSize = 9
	phase.TextTransparency = 0.32
	local bar = panel(hero, "Mode", 416, 31, 264, 34)
	for i, value in { "Ragdoll", "Objects" } do
		local button = Tool.make("TextButton", bar, value, {
			Text = value,
			Position = UDim2.new((i - 1) / 2, 3, 0, 3),
			Size = UDim2.new(0.5, -6, 1, -6),
			BorderSizePixel = 0,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			FontFace = Chrome.FONT,
			TextSize = 12,
			ZIndex = 14,
		})
		button:SetAttribute("ThemeTxt", "Txt")
		Tool.make("UICorner", button, "Corner", { CornerRadius = UDim.new(0, 4) })
		tabs[value] = button
		button.Activated:Connect(function()
			if busy or mode == value then
				return
			end

			for _, clip in physicalClips() do
				for motor in Scene.get().entries do
					if clip.tracks[motor] then
						notify(
							"Remove the object from the Simulations list before switching to "
								.. value
								.. "."
						)
						return
					end
				end
			end

			mode = value
			chosen = nil
			Scene.setMode(value)
			if setHold then
				setHold(value == "Objects")
			end

			repaint()
		end)
	end

	local participants = panel(frame, "Participants", 12, 154, 340, 128)
	section(participants, "ParticipantsTitle", "01  /  PARTICIPANTS", 10, 5, 145)
	local target = label(participants, "Target", "", 165, 5, 162, 20)
	target.TextWrapped = false
	target.TextTruncate = Enum.TextTruncate.AtEnd
	target.TextSize = 11
	target.TextXAlignment = Enum.TextXAlignment.Right

	local function setupAction(callback)
		if busy then
			return
		end

		local ok, err = pcall(callback)
		if not ok then
			notify(errorText(err))
		end

		repaint()
	end

	Tool.button(
		participants,
		"AddSelected",
		"ADD SELECTED",
		UDim2.fromOffset(10, 31),
		UDim2.fromOffset(154, 24),

		function()
			setupAction(function()
				Scene.add(mode)
			end)
		end
	)
	Tool.button(
		participants,
		"ClearParticipants",
		"CLEAR LIST",
		UDim2.fromOffset(174, 31),
		UDim2.fromOffset(154, 24),

		function()
			setupAction(function()
				Scene.clear()
			end)
		end
	)
	local guide = Tool.button(
		participants,
		"GreasePencil",
		"ANNOTATE",
		UDim2.fromOffset(10, 61),
		UDim2.fromOffset(112, 24),

		function()
			setupAction(function()
				assert(#Scene.entries() > 0, "add a rig or parts first")
				local selected = Scene.selectedGuideMotors()
				local motor = selected[1] or Scene.guideMotor()
				assert(motor, "add a rig or object first")
				local choices, names = {}, {}
				for _, entry in Scene.entries() do
					table.insert(choices, entry.motor)
					names[entry.motor] = entry.rig.Name .. " / " .. entry.motor.Part1.Name
				end

				refs.State.GreasePencil.close()
				refs.State.GreasePencil.open(motor, function(target, points, easing, targets)
					assert(not host.closed, "Reopen Physics to apply the path")
					local hadGuide = #Scene.paths() > 0
					Scene.setGuides(targets or { target }, points, easing)
					setHold(false)
					if not hadGuide then
						inputs.pathEnd.Text = inputs.last.Text
					end

					repaint()
				end, {
					targets = choices,
					multiple = true,
					selected = #selected > 0 and selected or { motor },
					label = function(target)
						return names[target]
					end,
					clear = Scene.clearGuide,
				})
			end)
		end
	)
	local clearGuide = Tool.button(
		participants,
		"ClearGuide",
		"CLEAR PATHS",
		UDim2.fromOffset(128, 61),
		UDim2.fromOffset(102, 24),

		function()
			setupAction(Scene.clearGuide)
		end
	)
	local forces = Tool.button(
		participants,
		"Forces",
		"FORCES",
		UDim2.fromOffset(236, 61),
		UDim2.fromOffset(91, 24),

		function()
			setupAction(Forces.open)
		end
	)

	local function field(parent, name, title, value, x, y, width)
		label(parent, name .. "Label", title, x, y, width, 20)
		local box = Tool.field(
			parent,
			name,
			numberText(value),
			UDim2.fromOffset(x, y + 22),
			UDim2.fromOffset(width, 26)
		)
		inputs[name] = box
		require("NumericInput").bind(box, {
			step = (name == "first" or name == "last" or name == "pathEnd") and 1 or 0.1,
			integer = name == "first" or name == "last" or name == "pathEnd",
			enabled = function()
				return not busy
			end,
		})
		return box
	end

	local first = math.floor(raw.CurrentTime * raw.FPS + 0.5)
	local timing = panel(frame, "Timing", 12, 294, 340, 144)
	section(timing, "TimingSection", "02  /  TIMING & PATH", 10, 5, 210)
	field(timing, "first", "Start frame", first, 10, 28, 88)
	field(
		timing,
		"last",
		"End frame",
		math.max(first + 1, refs.State.Timeline:GetMaxFrame()),
		106,
		28,
		88
	)
	field(timing, "speed", "Speed (x)", 1, 202, 66, 82)
	local here = Tool.button(
		timing,
		"StartHere",
		"USE PLAYHEAD",
		UDim2.fromOffset(222, 5),
		UDim2.fromOffset(106, 24),

		function()
			if busy then
				return
			end

			local state = refs.State.Timeline:GetState()
			local at = math.floor(state.CurrentTime * state.FPS + 0.5)
			local length = math.max(
				1,
				(tonumber(inputs.last.Text) or at + 1) - (tonumber(inputs.first.Text) or at)
			)
			local pathLength = math.max(
				1,
				(tonumber(inputs.pathEnd.Text) or at + length) - (tonumber(inputs.first.Text) or at)
			)
			inputs.first.Text = tostring(at)
			inputs.last.Text = tostring(at + length)
			inputs.pathEnd.Text = tostring(at + pathLength)
		end
	)
	local pathTiming = Tool.make("Frame", timing, "PathTiming", {
		Position = UDim2.fromOffset(10, 82),
		Size = UDim2.fromOffset(320, 52),
		BackgroundTransparency = 1,
		ZIndex = 12,
	})
	field(pathTiming, "pathEnd", "Path end", tonumber(inputs.last.Text), 0, 0, 150)
	field(pathTiming, "pathLaunch", "Launch speed", 0, 162, 0, 150)
	local dynamicsHeading = section(frame, "DynamicsSection", "03  /  DYNAMICS BAY", 364, 154, 344)
	dynamicsHeading.Visible = false
	frame.DynamicsSectionAccent.Visible = false
	local extra = panel(frame, "ExtraSettings", 364, 176, 344, 262)
	extra.Visible = true
	field(extra, "gravity", "Gravity", workspace.Gravity, 10, 8, 98)
	field(extra, "bounce", "Bounce", 0.1, 122, 8, 98)
	field(extra, "friction", "Friction", 0.6, 234, 8, 98)
	for i, axis in { "X", "Y", "Z" } do
		field(extra, axis, "Push " .. axis, 0, 10 + (i - 1) * 112, 62, 98)
	end

	local function checkbox(name, title, text, x, value)
		local button = Tool.make("TextButton", extra, name, {
			Text = "",
		Position = UDim2.fromOffset(x, 118),
			Size = UDim2.fromOffset(150, 24),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			ZIndex = 13,
		})
		label(button, "Label", title, 23, 0, 127)
		local box = Tool.make("Frame", button, "Box", {
			Position = UDim2.fromOffset(0, 4),
			Size = UDim2.fromOffset(16, 16),
			BorderSizePixel = 0,
			ZIndex = 14,
		})
		box:SetAttribute("ThemeBg", "TopBtn")
		local outline = Tool.make("UIStroke", box, "Outline", { Thickness = 1 })
		outline:SetAttribute("ThemeStrk", "Strk")
		local fill = Tool.make("Frame", box, "Fill", {
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.fromOffset(8, 8),
			BorderSizePixel = 0,
			ZIndex = 15,
			Visible = value,
		})
		fill:SetAttribute("ThemeBg", "Txt")
		for _, item in { box, fill } do
			Tool.make("UICorner", item, "Corner", { CornerRadius = UDim.new(0, 2) })
		end

		hint(extra, name .. "Hint", text, x, 140, 150, 30)
		button.Activated:Connect(function()
			if not busy then
				value = not value
				fill.Visible = value
			end
		end)
		return function()
			return value
		end, function(nextValue)
			value = nextValue
			fill.Visible = value
		end
	end

	local inherit, setInherit =
		checkbox("Inherit", "Keep motion", "preserve animation speed and spin", 10, true)
	local collision, setCollision = checkbox(
		"SelfCollision",
		"Self collision",
		"limbs can bump into each other",
		180,
		false
	)
	hold, setHold = checkbox(
		"Hold",
		"Stay still until hit",
		"holds the starting pose until a force reaches it",
		10,
		false
	)
	extra.Hold.Position = UDim2.fromOffset(10, 174)
	extra.Hold.Size = UDim2.fromOffset(150, 24)
	extra.Hold.Label.Size = UDim2.fromOffset(127, 22)
	extra.HoldHint.Position = UDim2.fromOffset(10, 196)
	extra.HoldHint.Size = UDim2.fromOffset(155, 30)
	local detached, setDetached =
		checkbox("Detached", "Detached limbs", "ragdoll limbs fall separately", 180, false)
	extra.Detached.Position = UDim2.fromOffset(180, 174)
	extra.DetachedHint.Position = UDim2.fromOffset(180, 196)
	extra.DetachedHint.Size = UDim2.fromOffset(150, 30)
	local previews = section(frame, "PreviewsTitle", "SIMULATION LIBRARY", 12, 454, 420)
	previews.TextSize = 11
	local fresh = Tool.button(
		frame,
		"NewPreview",
		"NEW SIM",
		UDim2.fromOffset(584, 450),
		UDim2.fromOffset(124, 28),

		function()
			if busy then
				return
			end

			chosen = nil
			Scene.clear()
			repaint()
		end
	)
	local clips = Tool.make("ScrollingFrame", frame, "Clips", {
		Position = UDim2.fromOffset(12, 482),
		Size = UDim2.fromOffset(696, 186),
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 12,
	})
	clips:SetAttribute("ThemeBg", "Pnl")
	Tool.make("UICorner", clips, "Corner", { CornerRadius = UDim.new(0, 4) })
	local stroke = Tool.make("UIStroke", clips, "Outline", { Thickness = 1, Transparency = 0.35 })
	stroke:SetAttribute("ThemeStrk", "Strk")
	Tool.make("UIPadding", clips, "Padding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
	})
	Tool.make(
		"UIListLayout",
		clips,
		"Layout",
		{ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3) }
	)

	local function action(callback)
		local ok, err = pcall(callback)
		if not ok then
			notify(errorText(err))
		end

		repaint()
	end

	local function openClip(clip)
		chosen, mode = clip, clip.settings.mode
		Scene.useClip(clip)
		inputs.speed.Text = numberText(clip.settings.speed or 1)
		inputs.pathEnd.Text = numberText(clip.settings.pathEnd or clip.last)
		inputs.pathLaunch.Text = numberText(clip.settings.pathLaunch or 0)
		for name, box in inputs do
			if clip.settings[name] ~= nil then
				box.Text = numberText(clip.settings[name])
			end
		end

		local push = clip.settings.velocity or Vector3.zero
		inputs.X.Text, inputs.Y.Text, inputs.Z.Text =
			numberText(push.X), numberText(push.Y), numberText(push.Z)
		setHold(clip.settings.hold == true)
		setInherit(clip.settings.inherit == true)
		setCollision(clip.settings.selfCollision == true)
		setDetached(clip.settings.detached == true)
		repaint()
	end

	local function dirty()
		if not chosen then
			return false
		end

		if Scene.forcesChanged(chosen) or Scene.guideChanged(chosen) then
			return true
		end

		if (chosen.settings.hold == true) ~= hold() then
			return true
		end

		if
			chosen.settings.mode ~= mode
			or chosen.settings.inherit ~= inherit()
			or chosen.settings.selfCollision ~= collision()
			or (chosen.settings.detached == true) ~= detached()
		then
			return true
		end

		for name, box in inputs do
			if name == "X" or name == "Y" or name == "Z" then
				if tonumber(box.Text) ~= (chosen.settings.velocity or Vector3.zero)[name] then
					return true
				end
			elseif (name ~= "pathEnd" and name ~= "pathLaunch") or #Scene.paths() > 0 then
				local value = chosen.settings[name]
				if name == "speed" then
					value = value or 1
				elseif name == "pathEnd" then
					value = value or chosen.last
				elseif name == "pathLaunch" then
					value = value or 0
				end

				if tonumber(box.Text) ~= value then
					return true
				end
			end
		end

		local count = 0
		for motor in Scene.get().entries do
			if not chosen.tracks[motor] then
				return true
			end

			count += 1
		end

		local previous = 0
		for _ in chosen.tracks do
			previous += 1
		end

		return count ~= previous
	end

	local function run()
		if busy then
			revision += 1
			return
		end

		local settings = {
			mode = mode,
			inherit = inherit(),
			selfCollision = collision(),
			hold = hold(),
			detached = detached(),
		}
		for name, box in inputs do
			settings[name] = tonumber(box.Text)
		end

		for _, name in { "first", "last", "speed", "gravity", "bounce", "friction", "X", "Y", "Z" } do
			if not settings[name] then
				notify("Fill in the empty fields with numbers first.")
				repaint()
				return
			end
		end

		if #Scene.paths() > 0 and (not settings.pathEnd or not settings.pathLaunch) then
			notify("Enter the path end frame and launch speed.")
			repaint()
			return
		end

		settings.velocity = Vector3.new(settings.X, settings.Y, settings.Z)
		local rangeError = Forces.rangeError(settings.first, settings.last)
		if rangeError then
			notify(rangeError)
			repaint()
			return
		end

		revision += 1
		local token = revision
		busy = true
		refs.State.PhysicsSimulating = true
		progress = "CANCEL · 0%"
		repaint()
		task.spawn(function()
			local update = 0
			local ok, result = pcall(Physics.simulate, settings, function(current)
				assert(not host.closed and token == revision, "simulation canceled")
				if
					os.clock() - update >= 0.05
					or current == settings.first
					or current == settings.last
				then
					progress = string.format(
						"CANCEL · %d%%",
						math.clamp(
							math.floor(
								(current - settings.first)
									/ math.max(1, settings.last - settings.first)
									* 100
							),
							0,
							100
						)
					)
					update = os.clock()
				end
			end, chosen)
			refs.State.PhysicsSimulating = false
			if host.closed then
				return
			end

			busy = false
			if ok then
				chosen = result
			else
				notify(errorText(result))
			end

			repaint()
		end)
	end

	controls = {
		run = run,
		state = function()
			local ready = next(Scene.get().entries) ~= nil
			return {
				busy = busy,
				ready = ready,
				preview = chosen ~= nil,
				dirty = dirty(),
				playing = raw.Playing,
				first = tonumber(inputs.first.Text),
				last = tonumber(inputs.last.Text),
			}
		end,
		includeFrame = function(at)
			if busy then
				return
			end

			inputs.first.Text = tostring(math.min(tonumber(inputs.first.Text) or at, at))
			inputs.last.Text = tostring(math.max(tonumber(inputs.last.Text) or at + 1, at + 1))
			repaint()
		end,
		play = function()
			if busy then
				return
			end

			if refs.State.Timeline:IsExportLocked() then
				return
			end

			if raw.Playing then
				raw.Playing = false
				return
			end

			if not chosen or dirty() then
				return
			end

			Window.jump(chosen.first)
			refs.State.Timeline:StartPlayback()
		end,
	}
	simulate = Tool.button(
		frame,
		"Simulate",
		"SIMULATE",
		UDim2.fromOffset(12, 688),
		UDim2.fromOffset(224, 32),
		Window.run
	)
	bake = Tool.button(
		frame,
		"Bake",
		"BAKE KEYS",
		UDim2.fromOffset(248, 688),
		UDim2.fromOffset(224, 32),

		function()
			if not chosen or busy or dirty() then
				return
			end

			revision += 1
			local token = revision
			busy = true
			refs.State.PhysicsSimulating = true
			progress = "CANCEL BAKE"
			repaint()
			task.spawn(function()
				local ok, result = pcall(Physics.bake, chosen, function()
					assert(not host.closed and token == revision, "simulation canceled")
				end)
				refs.State.PhysicsSimulating = false
				busy = false
				if host.closed then
					return
				end

				if ok then
					chosen = nil
				else
					notify(errorText(result))
				end

				repaint()
			end)
		end
	)
	remove = Tool.button(
		frame,
		"Play",
		"PLAY",
		UDim2.fromOffset(484, 688),
		UDim2.fromOffset(224, 32),
		Window.play
	)

	-- A compact dashboard keeps the common workflow visible. Detailed controls
	-- live in focused popups so the lab is calm until the user asks to tune it.
	local dashboard = Tool.make("Frame", frame, "LabDashboard", {
		Position = UDim2.fromOffset(12, 154),
		Size = UDim2.fromOffset(696, 514),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 12,
	})
	local tileSummaries = {}
	local function dashboardTile(name, title, subtitle, x, y, width, callback)
		local button = Tool.make("TextButton", dashboard, name, {
			Text = "",
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(width, 100),
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Active = true,
			ZIndex = 13,
		})
		button:SetAttribute("ThemeBg", "Pnl")
		Tool.make("UICorner", button, "Corner", { CornerRadius = UDim.new(0, 10) })
		local stroke = Tool.make("UIStroke", button, "Outline", {
			Thickness = 1,
			Transparency = 0.48,
		})
		stroke:SetAttribute("ThemeStrk", "Strk")
		local accent = Tool.make("Frame", button, "Accent", {
			Position = UDim2.fromOffset(0, 14),
			Size = UDim2.fromOffset(3, 72),
			BorderSizePixel = 0,
			ZIndex = 14,
		})
		accent:SetAttribute("ThemeBg", "MenuSel")
		Tool.make("UICorner", accent, "Corner", { CornerRadius = UDim.new(1, 0) })
		local eyebrow = Tool.label(button, "Eyebrow", title, UDim2.fromOffset(18, 15), UDim2.fromOffset(width - 36, 20))
		eyebrow.TextSize = 13
		eyebrow.ZIndex = 15
		local summary = Tool.label(button, "Summary", subtitle, UDim2.fromOffset(18, 43), UDim2.fromOffset(width - 36, 32))
		summary.TextSize = 11
		summary.TextTransparency = 0.25
		summary.TextTruncate = Enum.TextTruncate.AtEnd
		summary.ZIndex = 15
		local openHint = Tool.label(button, "OpenHint", "OPEN  ↗", UDim2.new(1, -82, 1, -25), UDim2.fromOffset(68, 14))
		openHint.TextSize = 9
		openHint.TextTransparency = 0.28
		openHint.TextXAlignment = Enum.TextXAlignment.Right
		openHint.ZIndex = 15
		tileSummaries[name] = summary
		button.Activated:Connect(callback)
		return button
	end

	local tileParticipants = dashboardTile("ParticipantsTile", "01  /  PARTICIPANTS", "Add a rig or object", 0, 0, 340, function()
		if openPanel then openPanel("participants") end
	end)
	local tileTiming = dashboardTile("TimingTile", "02  /  TIMING & PATH", "Choose frames and motion", 356, 0, 340, function()
		if openPanel then openPanel("timing") end
	end)
	local tileDynamics = dashboardTile("DynamicsTile", "03  /  DYNAMICS BAY", "Gravity, bounce, friction, and collision", 0, 112, 340, function()
		if openPanel then openPanel("dynamics") end
	end)
	local tileLibrary = dashboardTile("LibraryTile", "SIMULATION LIBRARY", "Saved previews and results", 356, 112, 340, function()
		if openPanel then openPanel("library") end
	end)
	local statusPanel = panel(dashboard, "SimulationStatus", 0, 236, 696, 250)
	statusPanel.ZIndex = 13
	statusPanel.SunAccent.Position = UDim2.fromOffset(0, 18)
	statusPanel.SunAccent.Size = UDim2.fromOffset(3, 70)
	local statusLabel = label(statusPanel, "StatusLabel", "SIMULATION STATUS", 20, 18, 360, 20)
	statusLabel.TextSize = 11
	local statusTitle = label(statusPanel, "StatusTitle", "Ready to build a simulation", 20, 58, 640, 34)
	statusTitle.TextSize = 21
	statusTitle.FontFace = Chrome.FONT
	local statusDetail = label(statusPanel, "StatusDetail", "Open Participants to choose a rig or object, then tune the motion and run a preview.", 20, 101, 640, 48)
	statusDetail.TextSize = 12
	statusDetail.TextTransparency = 0.24
	local statusRule = Tool.make("Frame", statusPanel, "StatusRule", {
		Position = UDim2.fromOffset(20, 174),
		Size = UDim2.new(1, -40, 0, 1),
		BorderSizePixel = 0,
		ZIndex = 15,
	})
	statusRule:SetAttribute("ThemeBg", "Strk")
	local statusFoot = label(statusPanel, "StatusFoot", "SETUP  →  TUNE  →  SIMULATE", 20, 190, 540, 18)
	statusFoot.TextSize = 10
	statusFoot.TextTransparency = 0.35

	local modal = Tool.make("TextButton", frame, "LabModalBackdrop", {
		Text = "",
		Position = UDim2.fromOffset(0, 140),
		Size = UDim2.new(1, 0, 1, -140),
		BackgroundColor3 = Color3.fromRGB(5, 5, 7),
		BackgroundTransparency = 0.38,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = true,
		Visible = false,
		ZIndex = 45,
	})
	local dialog = Tool.make("Frame", modal, "LabDialog", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(520, 250),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Active = true,
		ZIndex = 55,
	})
	dialog:SetAttribute("ThemeBg", "Pnl")
	Tool.make("UICorner", dialog, "Corner", { CornerRadius = UDim.new(0, 12) })
	local dialogStroke = Tool.make("UIStroke", dialog, "Outline", { Thickness = 1, Transparency = 0.28 })
	dialogStroke:SetAttribute("ThemeStrk", "Strk")
	local dialogAccent = Tool.make("Frame", dialog, "SunAccent", {
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.fromOffset(3, 36),
		BorderSizePixel = 0,
		ZIndex = 56,
	})
	dialogAccent:SetAttribute("ThemeBg", "MenuSel")
	local dialogTitle = Tool.label(dialog, "DialogTitle", "PARTICIPANTS", UDim2.fromOffset(20, 14), UDim2.fromOffset(390, 28))
	dialogTitle.TextSize = 16
	dialogTitle.ZIndex = 57
	local dialogSub = Tool.label(dialog, "DialogSub", "Tune this part of your simulation", UDim2.fromOffset(20, 39), UDim2.fromOffset(420, 18))
	dialogSub.TextSize = 10
	dialogSub.TextTransparency = 0.32
	dialogSub.ZIndex = 57
	local dialogClose, dialogCloseLabel = Tool.button(dialog, "DialogClose", "CLOSE  ×", UDim2.new(1, -102, 0, 14), UDim2.fromOffset(84, 28), function()
		if closePanel then closePanel() end
	end)
	dialogClose.ZIndex = 58
	dialogCloseLabel.ZIndex = 59
	local dialogRule = Tool.make("Frame", dialog, "DialogRule", {
		Position = UDim2.fromOffset(20, 62),
		Size = UDim2.new(1, -40, 0, 1),
		BorderSizePixel = 0,
		ZIndex = 57,
	})
	dialogRule:SetAttribute("ThemeBg", "Strk")

	local elevatedZ = setmetatable({}, { __mode = "k" })
	local function elevateTree(root)
		local function elevate(node)
			if node:IsA("GuiObject") then
				if elevatedZ[node] == nil then elevatedZ[node] = node.ZIndex end
				node.ZIndex = elevatedZ[node] + 50
			end
		end
		elevate(root)
		for _, node in root:GetDescendants() do elevate(node) end
	end
	local function restoreTree(root)
		local function restore(node)
			if elevatedZ[node] ~= nil then
				node.ZIndex = elevatedZ[node]
				elevatedZ[node] = nil
			end
		end
		restore(root)
		for _, node in root:GetDescendants() do restore(node) end
	end
	local popupHome = {
		participants = { participants, UDim2.fromOffset(178, 74), UDim2.fromOffset(340, 128) },
		timing = { timing, UDim2.fromOffset(178, 74), UDim2.fromOffset(340, 144) },
		dynamics = { extra, UDim2.fromOffset(176, 74), UDim2.fromOffset(344, 262) },
		library = { clips, UDim2.fromOffset(12, 72), UDim2.fromOffset(672, 190) },
	}
	local popupObjects = { participants, timing, extra, clips, previews, fresh }
	local function restoreDashboard()
		for _, object in popupObjects do
			if object.Parent == dialog then object.Parent = frame end
			object.Visible = false
		end
		participants.Position = UDim2.fromOffset(12, 154)
		timing.Position = UDim2.fromOffset(12, 294)
		extra.Position = UDim2.fromOffset(364, 176)
		previews.Position = UDim2.fromOffset(12, 454)
		fresh.Position = UDim2.fromOffset(584, 450)
		clips.Position = UDim2.fromOffset(12, 482)
		clips.Size = UDim2.fromOffset(696, 186)
		for _, object in popupObjects do restoreTree(object) end
	end
	closePanel = function()
		if not activePanel then return end
		activePanel = nil
		restoreDashboard()
		modal.Visible = false
	end
	openPanel = function(name)
		restoreDashboard()
		activePanel = name
		modal.Visible = true
		local config = {
			participants = { "01  /  PARTICIPANTS", "Choose which rig or parts take part in the simulation.", UDim2.fromOffset(520, 230), participants },
			timing = { "02  /  TIMING & PATH", "Set the frame range, speed, and optional motion path.", UDim2.fromOffset(520, 246), timing },
			dynamics = { "03  /  DYNAMICS BAY", "Shape gravity, surface response, pushes, and collisions.", UDim2.fromOffset(520, 364), extra },
			library = { "SIMULATION LIBRARY", "Select a saved simulation to preview, update, bake, or remove.", UDim2.fromOffset(696, 300), clips },
		}
		local selected = config[name]
		if not selected then closePanel(); return end
		dialogTitle.Text = selected[1]
		dialogSub.Text = selected[2]
		dialog.Size = selected[3]
		local content = selected[4]
		content.Parent = dialog
		content.Visible = true
		if name == "library" then
			previews.Parent = dialog
			previews.Visible = true
			previews.Position = UDim2.fromOffset(20, 68)
			fresh.Parent = dialog
			fresh.Visible = true
			fresh.Position = UDim2.new(1, -144, 0, 66)
			fresh.Size = UDim2.fromOffset(124, 28)
			content.Position = UDim2.fromOffset(12, 98)
			content.Size = UDim2.new(1, -24, 1, -112)
		else
			local home = popupHome[name]
			content.Position = home[2]
			content.Size = home[3]
		end
		elevateTree(content)
		if name == "library" then
			elevateTree(previews)
			elevateTree(fresh)
		end
	end
	for _, object in popupObjects do object.Visible = false end
	modal.Activated:Connect(function()
		closePanel()
	end)
	local inputService = game:GetService("UserInputService")
	table.insert(host.connections, inputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Escape then closePanel() end
	end))
	Theme.applyTree(dashboard)
	repaint = function()
		if host.closed then
			return
		end

		if refs.State.LoadingProject then
			return
		end

		if not refs.Active() then
			if
				not refs.ScreenGui.Parent
				or not refs.ScreenGui.Enabled
			then
				Window.close()
			else
				host.gui.Enabled = false
			end

			return
		end

		host.gui.Enabled = true
		local list = physicalClips()
		if chosen and not table.find(list, chosen) then
			chosen = nil
		end

		if listed ~= list then
			listed = list
			for _, child in clips:GetChildren() do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end

			if #list == 0 then
				local empty = hint(clips, "Empty", "No simulations yet", 0, 0, 386, 28)
				empty.Size = UDim2.new(1, -4, 0, 28)
				empty.TextWrapped = false
				empty.TextTruncate = Enum.TextTruncate.AtEnd
			end

			clipButtons = {}
			for i, clip in list do
				local row = Tool.make("Frame", clips, "Clip" .. i, {
					Size = UDim2.new(1, -4, 0, 28),
					BackgroundTransparency = 1,
					LayoutOrder = i,
					ZIndex = 13,
				})
				local button, title = Tool.button(
					row,
					"Select",
					i .. ". " .. clip.name .. "  |  " .. clip.first .. " - " .. clip.last,
					UDim2.new(),
					UDim2.new(1, -80, 1, 0),

					function()
						if not busy then
							openClip(clip)
						end
					end
				)
				button:SetAttribute("PhysicsClipId", clip.id)
				table.insert(clipButtons, button)
				title.TextWrapped = false
				title.TextTruncate = Enum.TextTruncate.AtEnd
				title.TextSize = 11
				Tool.button(
					row,
					"Remove",
					"REMOVE",
					UDim2.new(1, -74, 0, 0),
					UDim2.fromOffset(74, 28),

					function()
						if busy then
							return
						end

						action(function()
							Physics.remove(clip)
							if chosen == clip then
								chosen = nil
							end
						end)
					end
				)
			end

			Theme.applyTree(clips)
		end

		for _, button in clipButtons do
			local active = chosen and button:GetAttribute("PhysicsClipId") == chosen.id
			local color = active and "MenuSel" or "TopBtn"
			if button:GetAttribute("ThemeBg") ~= color then
				button:SetAttribute("ThemeBg", color)
				Theme.applyInstance(button)
			end

			FX.setRestingProperty(button, "BackgroundTransparency", active and 0 or 0.4)
		end

		for value, button in tabs do
			FX.setRestingProperty(button, "BackgroundTransparency", mode == value and 0 or 1)
			button.BackgroundColor3 = Theme.get("TopBtn", Color3.fromRGB(30, 60, 65))
			button.Interactable = not busy
		end

		local valid, rig, motors = pcall(Physics.targets, mode)
		local registered = 0
		for _ in Scene.get().entries do
			registered += 1
		end

		target.Text = registered > 0 and registered .. " participants ready"
			or "Add a rig or object to start a simulation"
		guide.TextLabel.Text = #Scene.paths() > 0 and "EDIT DRAWN PATHS" or "ANNOTATE"
		clearGuide.Interactable = not busy and #Scene.paths() > 0
		forces.TextLabel.Text = "FORCES (" .. #Scene.get().forces .. ")"
		for _, button in { guide, forces } do
			button.Interactable = not busy
		end

		local playing = refs.State.Timeline:GetState().Playing
		simulate.Interactable = busy or valid and not playing
		simulate:SetAttribute("Ready", simulate.Interactable)
		simulate.TextLabel.Text = busy and progress or chosen and "UPDATE SIM" or "SIMULATE"
		bake.Interactable = not busy and not playing and chosen ~= nil and not dirty()
		remove.Interactable = not busy and (playing or chosen ~= nil and not dirty())
		remove.TextLabel.Text = playing and "STOP" or "PLAY"
		for _, button in { bake, remove } do
			button:SetAttribute("Ready", button.Interactable)
		end

		for button, primary in
			{ [simulate] = chosen == nil or dirty(), [bake] = chosen ~= nil and not dirty() }
		do
			local color = primary and "MenuSel" or "TopBtn"
			if button:GetAttribute("ThemeBg") ~= color then
				button:SetAttribute("ThemeBg", color)
				Theme.applyInstance(button)
			end

			button:SetAttribute("Primary", primary)
		end

		fresh.Interactable = not busy
		here.Interactable = not busy
		for _, box in inputs do
			box.TextEditable = not busy
		end

		local hasPath = #Scene.paths() > 0
		for _, name in { "pathEnd", "pathLaunch" } do
			inputs[name].TextEditable = not busy and hasPath
		end

		pathTiming.Visible = true
		if not activePanel then
			extra.Position = UDim2.fromOffset(364, 176)
			previews.Position = UDim2.fromOffset(12, 454)
			fresh.Position = UDim2.fromOffset(584, 450)
			clips.Position = UDim2.fromOffset(12, 482)
			clips.Size = UDim2.fromOffset(696, 186)
		elseif activePanel == "library" then
			elevateTree(clips)
		end
		for i, button in { simulate, bake, remove } do
			button.Position = UDim2.fromOffset(12 + (i - 1) * 236, 688)
			button.Size = UDim2.fromOffset(224, 32)
		end
		phase.Text = string.format("01   SETUP  ·  %d READY     /     02   DYNAMICS     /     03   %s",
			registered, busy and "RUNNING" or (chosen and "PREVIEW" or "RUN"))
		tileSummaries.ParticipantsTile.Text = registered > 0 and target.Text or "Select a rig or object to simulate"
		tileSummaries.TimingTile.Text = string.format("Frames %s–%s   ·   speed %sx", inputs.first.Text, inputs.last.Text, inputs.speed.Text)
		tileSummaries.DynamicsTile.Text = string.format("Gravity %s   ·   bounce %s   ·   friction %s", inputs.gravity.Text, inputs.bounce.Text, inputs.friction.Text)
		tileSummaries.LibraryTile.Text = #list == 0 and "No saved simulations yet" or tostring(#list) .. " saved simulation" .. (#list == 1 and "" or "s")
		if busy then
			statusTitle.Text = "Simulation running"
			statusDetail.Text = progress .. "  ·  You can cancel by pressing Simulate again."
		elseif chosen then
			statusTitle.Text = chosen.name .. (dirty() and "  ·  needs update" or "  ·  preview ready")
			statusDetail.Text = string.format("Frames %d–%d  ·  %s mode  ·  %d participants", chosen.first, chosen.last, chosen.settings.mode, registered)
		else
			statusTitle.Text = registered > 0 and "Setup ready for a preview" or "Ready to build a simulation"
			statusDetail.Text = registered > 0 and "Choose a frame range and tune the dynamics, then press Simulate." or "Open Participants to choose a rig or object, then tune the motion and run a preview."
		end
	end

	local elapsed = 0
	table.insert(
		host.connections,
		RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed > 0.2 then
				elapsed = 0
				repaint()
			end
		end)
	)
	local unsubscribe = Theme.onChanged(repaint)
	frame.Destroying:Once(unsubscribe)
	Physics.preview(true)
	local existing = physicalClips()
	if #existing > 0 then
		openClip(existing[#existing])
	else
		repaint()
	end

	require("SceneSync").refresh()
	return frame
end

-- Window construction is intentionally guarded. A bad UI property or a
-- missing dependency should never strand a half-built, blank Physics window.
function Window.open()
	local ok, result = xpcall(openWindow, debug.traceback)
	if ok then
		return result
	end

	local failedWindow = window
	window = nil
	controls = nil
	revision += 1
	if refs then
		refs.State.PhysicsSimulating = false
	end
	if failedWindow then
		pcall(function()
			failedWindow:close(true)
		end)
	end
	pcall(Physics.preview, false)
	pcall(Forces.close)
	pcall(function()
		require("SceneSync").hide()
	end)
	warn("[Sun Physics Lab] Window setup failed:\n" .. tostring(result))
	pcall(notify, "Physics Lab couldn't finish opening. Check Studio Output for the setup error, then try again.")
	return nil
end

function Window.toggle()
	if Window.isOpen() then
		Window.close()
	else
		Window.open()
	end
end

function Window.init(options)
	Window.destroy()
	refs = options
	Physics.init(options)
	Forces.init(options)
	refs.State.Physics = Window
	Physics.preview(false)
	require("SceneSync").init(options)
	table.insert(
		connections,
		options.ScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not options.ScreenGui.Enabled then
				Window.close()
			end
		end)
	)
	table.insert(connections, options.ScreenGui.Destroying:Connect(Window.destroy))
	table.insert(connections, options.Plugin.Unloading:Connect(Window.destroy))
end

function Window.hasProjectData()
	local session = Scene.get()
	return next(session.entries or {}) ~= nil
		or next(session.forces or {}) ~= nil
		or next(session.guides or {}) ~= nil
		or session.guide ~= nil
end

function Window.write(save)
	Scene.write(save)
end

function Window.load(save)
	require("SmartBone").close()
	require("customRest").close()
	Window.close(true)
	Scene.load(save)
end

return Window

