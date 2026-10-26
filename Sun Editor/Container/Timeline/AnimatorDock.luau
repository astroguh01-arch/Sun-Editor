--!nocheck


local require = require(script:FindFirstAncestor("Container").Require)

local DockHost = require("DockHost")

local Input = require("UserInputService")
local Theme = require("Theme")
local FX = require("WindowFX")
local Motion = require("Motion")
local Menu = require("MenuBar")
local State = require("State")
local Data = require("ProjectData")
local Dock = { MINIMUM = Vector2.new(548, 182) }
local ui, plugin, widget, host, docked, busy, destroyed, reopenDock
local saved, moved, connections, buttons = {}, {}, {}, {}
local generation = 0
local preferenceKey

local function connect(signal, callback)
	table.insert(connections, signal:Connect(callback))
end

function Dock.isDocked()
	return docked == true
end

function Dock.presentationWidget()
	return docked and widget or nil
end

local function ready(target)
	if not target or not target.Enabled then
		return false
	end

	local size = target.AbsoluteSize
	return size.X > 0 and size.Y > 0
end

local function decorate(value)
	for _, frame in { ui.PrimaryFrame, ui.AnimatorFrame } do
		frame:SetAttribute("SunDocked", value)
		for _, child in frame:GetChildren() do
			if child:IsA("GuiObject") and child.Name:match("^SunResizeHandle_") then
				child.Visible = not value
			end
		end
	end

	for _, button in buttons do
		button:SetAttribute("Docked", value)
	end
end

local function restoreFloating()
	docked = false
	pcall(Input.detach)
	for object, parent in moved do
		pcall(function()
			object.Parent = parent
		end)
	end

	table.clear(moved)
	for object, rect in saved do
		pcall(function()
			object.AnchorPoint = rect.anchor
			object.Position = rect.position
			object.Size = rect.size
		end)
	end

	table.clear(saved)
	pcall(decorate, false)
	if widget then
		pcall(function()
			widget.Enabled = false
		end)
	end
end

local function fit()
	if not docked or not ready(widget) then
		return
	end

	local size = widget.AbsoluteSize
	for _, frame in { ui.PrimaryFrame, ui.AnimatorFrame } do
		frame.AnchorPoint = Vector2.zero
		frame.Position = UDim2.new()
		frame.Size =
			UDim2.fromOffset(math.max(Dock.MINIMUM.X, size.X), math.max(Dock.MINIMUM.Y, size.Y))
	end
end

local function sync()
	if destroyed or busy then
		return
	end

	local show = ui.SunGUI.Enabled and not State.PresentationHidden
	if reopenDock and show then
		reopenDock = false
		task.spawn(function()
			Dock.setDocked(true)
		end)
	elseif widget then
		widget.Enabled = docked and show
		if docked and show then
			pcall(function()
				widget:RequestRaise()
			end)
		end

		if docked and show and not ready(widget) then
			restoreFloating()
			task.spawn(function()
				Dock.setDocked(true)
			end)
		end
	end
end

local function move(object)
	if not object or moved[object] then
		return
	end

	moved[object] = object.Parent
	object.Parent = widget
end

local function keepFloatingVisible()
	local area = ui.SunGUI.AbsoluteSize
	if area.X <= 0 or area.Y <= 0 then
		return
	end

	for _, frame in { ui.PrimaryFrame, ui.AnimatorFrame } do
		if frame.Visible then
			local position = frame.AbsolutePosition - ui.SunGUI.AbsolutePosition
			local size = frame.AbsoluteSize
			local delta = Vector2.new(
				math.clamp(position.X, 0, math.max(0, area.X - size.X)),
				math.clamp(position.Y, 0, math.max(0, area.Y - size.Y))
			) - position
			if delta.Magnitude > 0 then
				frame.Position += UDim2.fromOffset(
					delta.X / Motion.scale(frame),
					delta.Y / Motion.scale(frame)
				)
			end
		end
	end
end

local function ensureReady(target, current)
	local opened = DockHost.show(target, current)
	return opened, "Studio did not open the dock. Sun is still available as a floating window."
end

function Dock.setDocked(value)
	value = value == true
	if destroyed then
		return false
	end

	if busy then
		if not value then
			generation += 1
			restoreFloating()
			busy = false
			Data.setSetting(preferenceKey, false)
		end

		return false
	end

	if value == docked and not reopenDock then
		return true
	end

	reopenDock = false
	if not value then
		generation += 1
		restoreFloating()
		Data.setSetting(preferenceKey, false)
		return true
	end

	if not ui.SunGUI.Enabled or State.PresentationHidden then
		reopenDock = true
		return false
	end

	generation += 1
	local request = generation

	local function current()
		return request == generation
			and not destroyed
			and ui.SunGUI.Parent ~= nil
			and ui.SunGUI.Enabled
			and not State.PresentationHidden
	end

	busy = true
	local prepared = widget ~= nil
	local ok, err = xpcall(function()
		for _, frame in { ui.PrimaryFrame, ui.AnimatorFrame, host } do
			saved[frame] =
				{ position = frame.Position, size = frame.Size, anchor = frame.AnchorPoint }
		end

		if not widget then
			local created = DockHost.acquire(
				plugin,
				"SunAnimatorMain",
				DockWidgetPluginGuiInfo.new(
					Enum.InitialDockState.Bottom,
					true,
					true,
					720,
					320,
					Dock.MINIMUM.X,
					Dock.MINIMUM.Y
				)
			)
			if not current() then
				DockHost.release(created)
				error("Docking cancelled")
			end

			widget = created
			widget.Title = "Sun Animator"
			widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			widget:BindToClose(function()
				if busy then
					generation += 1
					restoreFloating()
					busy = false
					Data.setSetting(preferenceKey, false)
				else
					if not State.LoadingProject and not State.Timeline:IsExportLocked() then
						require("Project").finalizeCurrentManipulation()
					end

					ui.SunGUI.Enabled = false
					sync()
				end
			end)
			connect(widget:GetPropertyChangedSignal("AbsoluteSize"), function()
				fit()
				if
					docked
					and not busy
					and ui.SunGUI.Enabled
					and not State.PresentationHidden
					and not ready(widget)
				then
					task.defer(function()
						if
							not destroyed
							and docked
							and not busy
							and widget.Enabled
							and not ready(widget)
						then
							restoreFloating()
							Data.setSetting(preferenceKey, false)
							warn("Sun dock became unavailable. Restored the floating editor.")
						end
					end)
				end
			end)
			Theme.addRoot(widget)
			prepared = true
		end

		local opened, reason = ensureReady(widget, current)
		assert(opened, reason)
		Menu.close()
		if State.UIHelpers and State.UIHelpers.hoverDialog then
			State.UIHelpers.hoverDialog:disappear()
		end

		for _, frame in { ui.PrimaryFrame, ui.AnimatorFrame } do
			FX.clear(frame)
			local scale = frame:FindFirstChildOfClass("UIScale")
			if scale then
				scale.Scale = 1
			end
		end

		move(host)
		host.AnchorPoint = Vector2.zero
		host.Position = UDim2.new()
		host.Size = UDim2.fromScale(1, 1)
		for _, name in { "Hover", "Dropdowns", "MenuBarDropdowns" } do
			local floating = ui.SunGUI:FindFirstChild("SunFloatingVisibility")
			move(ui.SunGUI:FindFirstChild(name) or floating and floating:FindFirstChild(name))
		end

		docked = true
		fit()
		Input.attach(widget)
		decorate(true)
		task.wait()
		assert(current(), "Docking cancelled")
		assert(
			ready(widget) and host.AbsoluteSize.X > 0 and host.AbsoluteSize.Y > 0,
			"Dock content did not become visible"
		)
		Data.setSetting(preferenceKey, true)
	end, debug.traceback)
	if request ~= generation or destroyed then
		return false
	end

	busy = false
	if not ok then
		restoreFloating()
		if not prepared and widget then
			pcall(function()
				DockHost.release(widget)
			end)
			widget = nil
		end

		pcall(Data.setSetting, preferenceKey, false)
		warn("Sun docking: " .. tostring(err))
		return false
	end

	return true
end

function Dock.destroy()
	if destroyed then
		return
	end

	generation += 1
	destroyed = true
	restoreFloating()
	busy = false
	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
	if widget then
		DockHost.release(widget)
		widget = nil
	end

	State.AnimatorDock = nil
end

function Dock.layoutHeader(frame)
	local bar = frame.Bar
	local controls = bar.ControlButtons
	bar.AutomaticSize = Enum.AutomaticSize.None
	bar.BorderSizePixel = 0
	if bar.Size.X.Scale == 1 then
		bar.Size = UDim2.new(1, -2, bar.Size.Y.Scale, bar.Size.Y.Offset)
		bar.Position = UDim2.new(
			bar.AnchorPoint.X,
			1 - 2 * bar.AnchorPoint.X,
			bar.Position.Y.Scale,
			bar.Position.Y.Offset
		)
	end

	local menu = frame == ui.AnimatorFrame and ui.AnimatorMenuButtons
		or bar:FindFirstChild("MenuButtons")
	if menu and menu.Parent == bar then
		menu.Visible = true
		menu.Active = false
		menu.AnchorPoint = Vector2.zero
		menu.AutomaticSize = Enum.AutomaticSize.X
		menu.Size = UDim2.new(0, 0, 1, 0)
		menu.ClipsDescendants = false
		local menuLayout = menu:FindFirstChildOfClass("UIListLayout")
		if not menuLayout then
			menuLayout = Instance.new("UIListLayout")
			menuLayout.Parent = menu
		end
		menuLayout.FillDirection = Enum.FillDirection.Horizontal
		menuLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		menuLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
		menuLayout.Padding = UDim.new(0, 4)
		for _, button in menu:GetChildren() do
			if button:IsA("GuiButton") then
				button.Visible = true
				button.Active = true
				button.Interactable = true
				button.AutoButtonColor = true
				button.AnchorPoint = Vector2.zero
				button.Position = UDim2.fromOffset(0, 0)
				button.AutomaticSize = Enum.AutomaticSize.X
				button.Size = UDim2.new(button.Size.X.Scale, button.Size.X.Offset, 0, 28)
				button.ZIndex = math.max(button.ZIndex, bar.ZIndex + 2)
				for _, child in button:GetDescendants() do
					if child:IsA("GuiObject") then
						child.Active = false
					child.ZIndex = math.max(child.ZIndex, button.ZIndex + 1)
					end
				end
			end
		end
	end

	local appearance = bar:FindFirstChild("Appearence")
	if appearance then
		local padding = appearance:FindFirstChildOfClass("UIPadding")
		if padding then
			padding.PaddingLeft = UDim.new(0, 0)
		end
	end

	if appearance then
		local title = appearance:FindFirstChild("Title")
		if title and title:IsA("GuiObject") then
			title.Size = UDim2.new(title.Size.X.Scale, title.Size.X.Offset, 0, 28)
		end
	end

	local count = 0
	for _, button in controls:GetChildren() do
		if button:IsA("GuiButton") then
			count += 1
			button.AutomaticSize = Enum.AutomaticSize.None
			button.Size = UDim2.fromOffset(28, 28)
			for _, icon in button:GetDescendants() do
				if icon:IsA("ImageLabel") then
					icon.AnchorPoint = Vector2.new(0.5, 0.5)
					icon.Position = UDim2.fromScale(0.5, 0.5)
					icon.Size = UDim2.fromOffset(22, 22)
					icon.ScaleType = Enum.ScaleType.Fit
				end
			end
		end
	end

	controls.AutomaticSize = Enum.AutomaticSize.None
	controls.AnchorPoint = Vector2.new(1, 0.5)
	controls.Position = UDim2.new(1, -4, 0.5, 0)
	controls.Size = UDim2.fromOffset(count * 28 + math.max(0, count - 1) * 4, 28)
	local layout = controls:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.Padding = UDim.new(0, 4)
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.HorizontalFlex = Enum.UIFlexAlignment.None
		layout.VerticalFlex = Enum.UIFlexAlignment.None
	end
end

function Dock.attach(options, owner)
	ui, plugin = options, owner
	preferenceKey = "SunAnimator_MainDockedV2_" .. tostring(game.PlaceId)
	destroyed, docked, busy = false, false, false
	reopenDock = false
	host = ui.RootFrame
	State.AnimatorDock = Dock
	for _, frame in { ui.PrimaryFrame, ui.AnimatorFrame } do
		local bar = frame:FindFirstChild("Bar")
		local menu = frame == ui.AnimatorFrame and ui.AnimatorMenuButtons
			or bar and bar:FindFirstChild("MenuButtons")
		if not menu then
			warn("Sun Animator: menu bar controls are missing for " .. frame:GetFullName() .. "; dock controls were skipped")
			continue
		end
		local controls = bar:FindFirstChild("ControlButtons")
		if not controls then
			warn("Sun Animator: window controls are missing for " .. frame:GetFullName() .. "; dock controls were skipped")
			continue
		end
		local template = controls:FindFirstChild("SaveButton")
			or controls:FindFirstChildWhichIsA("GuiButton")
		local button = template:Clone()
		button.Name = "DockButton"
		button.LayoutOrder = -4
		for _, child in button:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		if button:IsA("ImageButton") then
			button.Image = ""
		end

		local templateIcon = template:FindFirstChildWhichIsA("ImageLabel", true)
		local icon = templateIcon and templateIcon:Clone() or Instance.new("ImageLabel")
		icon.Name = "DockIcon"
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Size = templateIcon and templateIcon.Size or UDim2.fromOffset(22, 22)
		icon.BackgroundTransparency = 1
		icon.Image = "rbxassetid://82540310696094"
		icon.ImageRectOffset = Vector2.zero
		icon.ImageRectSize = Vector2.zero
		if not templateIcon then
			icon.ImageColor3 = Color3.fromRGB(38, 26, 52)
		end

		icon:SetAttribute("ThemeImg", "CtrlIc")
		icon.Parent = button
		button.Parent = controls
		table.insert(buttons, button)
		button.Activated:Connect(function()
			Dock.setDocked(not docked)
		end)
		State.UIHelpers.hoverDialog:latchToInstance(button, function()
			return docked and "Undock Sun" or "Dock Sun"
		end)
		local constraint = frame:FindFirstChild("SunMinimumSize")
			or Instance.new("UISizeConstraint")
		constraint.Name = "SunMinimumSize"
		constraint.MinSize = Dock.MINIMUM
		constraint.Parent = frame
		frame.Size = UDim2.fromOffset(
			math.max(Dock.MINIMUM.X, frame.Size.X.Offset),
			math.max(Dock.MINIMUM.Y, frame.Size.Y.Offset)
		)
		local layout = bar:FindFirstChildOfClass("UIListLayout")
		if layout then
			layout:Destroy()
		end

		Dock.layoutHeader(frame)

		local appearance = bar:FindFirstChild("Appearence")
		if appearance then
			appearance.Position = UDim2.fromOffset(frame == ui.AnimatorFrame and 44 or 4, 0)
			appearance.Size = UDim2.fromOffset(0, 28)
			appearance.AutomaticSize = Enum.AutomaticSize.X
		end

		local menuInRail = frame == ui.AnimatorFrame and menu.Parent ~= bar
		local divider = bar:FindFirstChild("Div") or Instance.new("Frame")
		divider.Name = "Div"
		divider.Visible = not menuInRail
		divider.AutomaticSize = Enum.AutomaticSize.None
		divider.AnchorPoint = Vector2.new(0, 0.5)
		divider.Size = UDim2.fromOffset(14, 28)
		divider.BackgroundTransparency = 1
		divider.BorderSizePixel = 0
		local line = divider:FindFirstChild("Frame") or Instance.new("Frame")
		line.Name = "Frame"
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Position = UDim2.fromScale(0.5, 0.5)
		line.Size = UDim2.fromOffset(2, 16)
		line.BorderSizePixel = 0
		line:SetAttribute("ThemeBg", "Div")
		line.Parent = divider
		divider.Parent = bar
		Theme.applyTree(divider)
		local menu = frame == ui.AnimatorFrame and ui.AnimatorMenuButtons
			or bar:FindFirstChild("MenuButtons")
		if not menu then
			warn("Sun Animator: menu bar disappeared during dock setup")
			continue
		end
		if menu.Parent == bar then
			menu.AutomaticSize = Enum.AutomaticSize.X
			menu.Size = UDim2.fromOffset(0, 28)
		end
		local menuScale
		if menu.Parent == bar then
			menuScale = Instance.new("UIScale")
			menuScale.Name = "HeaderMenuScale"
			menuScale.Parent = menu
		end

		local function placeMenu()
			if menu.Parent ~= bar or not menuScale then return end
			local scale = math.max(0.001, frame.AbsoluteSize.X / math.max(1, frame.Size.X.Offset))
			local titleEnd = (appearance and appearance.AbsoluteSize.X / scale or 95) + 4
			divider.Position = UDim2.new(0, titleEnd, 0.5, 0)
			menu.Position = UDim2.fromOffset(titleEnd + 14, 0)
			local width = menu.AbsoluteSize.X / math.max(0.001, menuScale.Scale * scale)
			if width > 0 then
				local available = (controls.AbsolutePosition.X - menu.AbsolutePosition.X) / scale
					- 4
				local factor = math.clamp(available / width, 0.65, 1)
				if math.abs(menuScale.Scale - factor) > 0.001 then
					menuScale.Scale = factor
				end
			end
		end

		if appearance and menu.Parent == bar then
			connect(appearance:GetPropertyChangedSignal("AbsoluteSize"), placeMenu)
		end

		if menu.Parent == bar then
			connect(menu:GetPropertyChangedSignal("AbsoluteSize"), placeMenu)
			connect(frame:GetPropertyChangedSignal("AbsoluteSize"), placeMenu)
			placeMenu()
		end
		Theme.applyTree(button)
	end

	connect(ui.SunGUI:GetPropertyChangedSignal("Enabled"), sync)
	connect(ui.SunGUI.Destroying, Dock.destroy)
	connect(plugin.Unloading, Dock.destroy)
	plugin.Unloading:Once(Input.destroy)
	if Data.getSetting(preferenceKey) == true then
		Dock.setDocked(true)
	end
end

return Dock

