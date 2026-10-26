--!nocheck


local require = require(script:FindFirstAncestor("Container").Require)

local DockHost = require("DockHost")
local Chrome = require("Chrome")
local Surface = require("Surface")
local FX = require("WindowFX")
local Theme = require("Theme")
local Tool = {}

function Tool.make(class, parent, name, props)
	local object = Instance.new(class)
	object.Name = name
	for key, value in props do
		object[key] = value
	end

	object.Parent = parent
	return object
end

function Tool.label(parent, name, text, position, size)
	local label = Tool.make("TextLabel", parent, name, {
		Text = text,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		FontFace = Chrome.FONT,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(235, 228, 242),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	})
	label:SetAttribute("ThemeTxt", "Txt")
	return label
end

local function neutralHover(button)
	button.AutoButtonColor = false
	local overlay = Instance.new("Frame")
	local tweenService = game:GetService("TweenService")
	local scale = button:FindFirstChild("NeutralHoverScale") or Instance.new("UIScale")
	scale.Name = "NeutralHoverScale"
	scale.Scale = 1
	scale.Parent = button
	overlay.Name = "HoverFill"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(1, 1, 1)
	overlay.BackgroundTransparency = 0.93
	overlay.BorderSizePixel = 0
	overlay.Active = false
	overlay.Visible = false
	overlay.ZIndex = button.ZIndex + 1
	overlay.Parent = button
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = overlay
	local function animate(target, transparency, scaleValue)
		tweenService:Create(target, TweenInfo.new(0.14, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { BackgroundTransparency = transparency }):Play()
		tweenService:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Scale = scaleValue }):Play()
	end
	button.MouseEnter:Connect(function()
		overlay.Visible = true
		animate(overlay, 0.83, 1.035)
	end)
	button.MouseLeave:Connect(function()
		animate(overlay, 1, 1)
		task.delay(0.15, function() if overlay.Parent and overlay.BackgroundTransparency > 0.98 then overlay.Visible = false end end)
	end)
	button.MouseButton1Down:Connect(function() animate(overlay, 0.72, 0.975) end)
	button.MouseButton1Up:Connect(function() animate(overlay, 0.83, 1.035) end)
end

function Tool.button(parent, name, text, position, size, callback)
	local button, label
	if parent:GetAttribute("SunTabBar") then
		button = Tool.make("TextButton", parent, name, {
			Text = "",
			Position = position,
			Size = size,
			BackgroundColor3 = Color3.fromRGB(45, 27, 56),
			BorderSizePixel = 0,
			AutoButtonColor = true,
			ZIndex = parent.ZIndex + 3,
		})
		button:SetAttribute("ThemeBg", "TopBtn")
		Tool.make("UICorner", button, "Corner", { CornerRadius = UDim.new(0, 4) })
		label = Tool.label(button, "TextLabel", text, UDim2.new(), UDim2.fromScale(1, 1))
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.ZIndex = button.ZIndex + 1
		neutralHover(button)
		Theme.applyTree(button)
	else
		button, label = Chrome.menuButton(parent, name, text, position, size)
	end

	label.TextSize = 12
	label.TextTransparency = 0.1
	if callback then
		button.Activated:Connect(callback)
	end

	return button, label
end

function Tool.field(parent, name, text, position, size, numericOptions)
	local shell = Tool.make("Frame", parent, name, {
		Position = position,
		Size = size,
		BorderSizePixel = 0,
		ZIndex = parent.ZIndex + 2,
		BackgroundColor3 = Color3.fromRGB(180, 75, 10),
	})
	shell:SetAttribute("ThemeBg", "TopBtn")
	Tool.make("UICorner", shell, "Corner", { CornerRadius = UDim.new(0, 6) })
	local stroke = Tool.make("UIStroke", shell, "Outline", {
		Color = Color3.fromRGB(69, 41, 93),
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		BorderStrokePosition = Enum.BorderStrokePosition.Inner,
		StrokeSizingMode = Enum.StrokeSizingMode.FixedSize,
		ZIndex = 2,
	})
	stroke:SetAttribute("ThemeStrk", "Strk")
	stroke.Transparency = 0.42
	local tweenService = game:GetService("TweenService")
	local function setFocusStyle(focused)
		tweenService:Create(stroke, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = focused and 0.05 or 0.42,
			Thickness = focused and 1.5 or 1,
		}):Play()
	end
	local box = Tool.make("TextBox", shell, "Value", {
		Text = tostring(text),
		Size = UDim2.new(1, -10, 1, 0),
		Position = UDim2.fromOffset(5, 0),
		BackgroundTransparency = 1,
		FontFace = Chrome.FONT,
		TextSize = 13,
		TextColor3 = Color3.new(1, 1, 1),
		ClearTextOnFocus = false,
		ZIndex = shell.ZIndex + 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	box:SetAttribute("ThemeTxt", "Txt")
	box.Focused:Connect(function() setFocusStyle(true) end)
	box.FocusLost:Connect(function() setFocusStyle(false) end)
	if type(text) == "number" then
		require("NumericInput").bind(box, numericOptions or {
			step = (
				name:lower():find("frame")
				or name:lower():find("fps")
				or name:lower():find("duration")
				or name:lower():find("spacing")
				or name:lower():find("stride")
				or name:lower():find("interval")
			)
					and 1
				or 0.1,
		})
	end

	return box
end

function Tool.new(refs, name, title, size, dockable, onClose, options)
	local self = { connections = {}, closed = false, busy = false }
	local gui = Tool.make("ScreenGui", refs.ScreenGui.Parent, name, {
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = refs.ScreenGui.DisplayOrder + 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	gui:SetAttribute("SunOwnedUI", true)
	local frame = Tool.make("Frame", gui, "Window", {
		Size = UDim2.fromOffset(size.X, size.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Active = true,
		ZIndex = 10,
	})
	Tool.make("UISizeConstraint", frame, "MinimumSize", { MinSize = size })
	Surface.fill(frame)
	local header, _, drag = Chrome.header(frame, title, nil, dockable and 115 or 42)
	local dockText
	self.gui, self.frame = gui, frame
	local root = refs.ScreenGui
	local rootFrame = root:FindFirstChild("Frame", true)
	local components = rootFrame and rootFrame:FindFirstChild("Components")
	local ui = require("UI")
	local animator = ui.SunGUI == root and ui.AnimatorFrame or nil
	local mainMenu = options and options.AllowMainMenu and ui.SunGUI == root and ui.PrimaryFrame
		or nil
	local alert = components and components:FindFirstChild("Alert")

	local function syncModal()
		if not gui.Parent then
			return
		end

		local enabled = not self.closed
			and root.Enabled
			and root.Parent ~= nil
			and root:GetAttribute("SunConfirmationOpen") ~= true
			and not (alert and alert.Visible)
			and (
				not animator
				or (animator.Visible and not animator:GetAttribute("SunHUDHidden"))
				or (mainMenu and mainMenu.Visible)
			)
		if gui.Enabled ~= enabled then
			gui.Enabled = enabled
		end
	end

	table.insert(
		self.connections,
		root:GetAttributeChangedSignal("SunConfirmationOpen"):Connect(syncModal)
	)
	if alert then
		table.insert(self.connections, alert:GetPropertyChangedSignal("Visible"):Connect(syncModal))
	end

	table.insert(self.connections, root:GetPropertyChangedSignal("Enabled"):Connect(syncModal))
	if animator then
		table.insert(
			self.connections,
			animator:GetPropertyChangedSignal("Visible"):Connect(syncModal)
		)
		table.insert(
			self.connections,
			animator:GetAttributeChangedSignal("SunHUDHidden"):Connect(syncModal)
		)
	end

	if mainMenu then
		table.insert(
			self.connections,
			mainMenu:GetPropertyChangedSignal("Visible"):Connect(syncModal)
		)
	end

	syncModal()

	function self:undock()
		self.docked = false
		frame.Parent = gui
		frame.Size = UDim2.fromOffset(size.X, size.Y)
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		if self.widget then
			self.widget.Enabled = false
		end

		if dockText then
			dockText.Text = "DOCK"
		end
	end

	function self:dock()
		if self.busy or self.closed then
			return
		end

		if self.docked then
			self:undock()
			return
		end

		self.busy = true
		local ok, err = pcall(function()
			if not self.widget then
				local widget = DockHost.acquire(
					refs.Plugin,
					name,
					DockWidgetPluginGuiInfo.new(
						Enum.InitialDockState.Right,
						true,
						true,
						size.X,
						size.Y,
						size.X,
						size.Y
					)
				)
				if self.closed then
					DockHost.release(widget)
					return
				end

				self.widget = widget
				widget.Title = title
				widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
				self.canvas = Tool.make("ScrollingFrame", widget, "Content", {
					Size = UDim2.fromScale(1, 1),
					CanvasSize = UDim2.new(),
					AutomaticCanvasSize = Enum.AutomaticSize.XY,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ScrollBarThickness = 4,
				})
				widget:BindToClose(function()
					self:close()
				end)
				Theme.addRoot(widget)
				table.insert(
					self.connections,
					widget:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
						if
							self.docked
							and not self.busy
							and not self.closed
							and widget.Enabled
							and (widget.AbsoluteSize.X <= 0 or widget.AbsoluteSize.Y <= 0)
						then
							self:undock()
						end
					end)
				)
			end

			assert(
				DockHost.show(self.widget, function()
					return not self.closed
				end),
				"Studio could not open the dock"
			)
			FX.clear(frame)
			local scale = frame:FindFirstChildOfClass("UIScale")
			if scale then
				scale.Scale = 1
			end

			frame.Parent = self.canvas
			frame.AnchorPoint = Vector2.zero
			frame.Position = UDim2.new()
			frame.Size = UDim2.fromScale(1, 1)
			self.docked = true
			dockText.Text = "UNDOCK"
		end)
		self.busy = false
		if not ok and not self.closed then
			self:undock()
			warn(tostring(err))
		end
	end

	local disposed = false
	local closingFrame
	local lifetime = {}

	local function dispose()
		if disposed then
			return
		end

		disposed = true
		for _, connection in lifetime do
			connection:Disconnect()
		end

		table.clear(lifetime)
		FX.clear(frame)
		if closingFrame then
			FX.clear(closingFrame)
		end

		if self.widget then
			DockHost.release(self.widget)
			self.widget = nil
		end

		gui:Destroy()
	end

	function self:close(immediate)
		if self.closed then
			if immediate then
				dispose()
			end

			return
		end

		self.closed = true
		local animate = not immediate
			and not (options and options.AnimateClose == false)
			and not self.docked
			and gui.Enabled
			and gui.Parent ~= nil
		frame.Interactable = false
		for _, object in frame:GetDescendants() do
			if object:IsA("TextBox") and object:IsFocused() then
				object:ReleaseFocus()
			end
		end

		for _, connection in self.connections do
			connection:Disconnect()
		end

		table.clear(self.connections)
		if animate then
			closingFrame = frame:Clone()
			closingFrame.Name = "ClosingWindow"
			local visuals = closingFrame:GetDescendants()
			table.insert(visuals, closingFrame)
			for _, visual in visuals do
				for attribute in visual:GetAttributes() do
					if attribute:sub(1, 5) == "Theme" then
						visual:SetAttribute(attribute, nil)
					end
				end
			end

			closingFrame.Parent = frame.Parent
			FX.clear(frame)
			frame.Visible = false
		end

		local notified, closeError = true, nil
		if onClose then
			notified, closeError = pcall(onClose)
		end

		if not disposed then
			if animate then
				FX.shrink(closingFrame, dispose)
			else
				dispose()
			end
		end

		if not notified then
			warn("[Sun] Tool close: " .. tostring(closeError))
		end
	end

	table.insert(
		lifetime,
		root.Destroying:Connect(function()
			self:close(true)
		end)
	)
	table.insert(
		lifetime,
		gui.Destroying:Connect(function()
			self:close(true)
		end)
	)
	table.insert(
		lifetime,
		root:GetPropertyChangedSignal("Enabled"):Connect(function()
			if self.closed and not root.Enabled then
				dispose()
			end
		end)
	)
	if refs.Plugin and refs.Plugin.Unloading then
		table.insert(
			lifetime,
			refs.Plugin.Unloading:Connect(function()
				self:close(true)
			end)
		)
	end

	Chrome.close(header, function()
		self:close()
	end)
	if dockable then
		local button
		button, dockText = Tool.button(
			header,
			"Dock",
			"DOCK",
			UDim2.new(1, -102, 0, 4),
			UDim2.fromOffset(66, 20),

			function()
				self:dock()
			end
		)
	end

	Chrome.bindDrag(frame, drag, {
		clamp = true,
		disabled = function()
			return self.closed or self.docked or self.busy
		end,
	})
	require("Motion").watchFloatingGui(gui)
	Theme.addRoot(gui)
	task.defer(function()
		if not self.closed then
			Theme.applyTree(frame)
			FX.pop(frame)
		end
	end)
	return self
end

return Tool
