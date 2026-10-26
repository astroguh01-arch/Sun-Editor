--!nocheck


local require = require(script:FindFirstAncestor("Container").Require)

local CoreGui = game:GetService("CoreGui")

local Config = require("Config")

local UI = {}

local resolved = false

local function resolve(sunScript: Instance)
	if resolved then
		return UI
	end


	local ServerScript = sunScript
	local Values = ServerScript.Values

	UI.PluginActiveBool = Values.PluginActive
	UI.ClosingEvent = Values.Closing

	UI.RequestEvent = ServerScript:WaitForChild("Players"):WaitForChild("RequestEvent")
	UI.AnimSavesTemplate = ServerScript:WaitForChild("Players"):WaitForChild("AnimSaves")

	local SunGUI, MiscGUI = require("PluginShell").getUI(sunScript)
	UI.MiscGUI = MiscGUI
	UI.SunGUI = SunGUI

	local floating = SunGUI:FindFirstChild("SunFloatingVisibility")
	UI.RootFrame = SunGUI:FindFirstChild("Frame")
		or floating and floating:FindFirstChild("Frame")
	UI.Dropdowns = SunGUI:FindFirstChild("Dropdowns")
		or floating and floating:FindFirstChild("Dropdowns")
	local Tabs = UI.RootFrame.Tabs
	local Components = UI.RootFrame.Components
	UI.Tabs = Tabs
	UI.Components = Components

	local PrimaryFrame = Tabs:WaitForChild("Primary")
	local FramesFolder = PrimaryFrame:WaitForChild("Frames")
	local MainFrame = FramesFolder.MainSurface

	UI.PrimaryFrame = PrimaryFrame
	UI.FramesFolder = FramesFolder
	UI.MainFrame = MainFrame

	-- Restore menus changed by the old sidebar experiment before any module
	-- resolves or binds their controls. The old experiment left vertical,
	-- full-width buttons inside a 100%-width AutoSize frame; those dimensions
	-- become circular when the frame returns to the horizontal title bar.
	local BRAND_RAIL_WIDTH = 60
	local HEADER_HEIGHT = 50

	local function makeSolarRail(host: Instance, caption: string)
		local rail = host:FindFirstChild("SunBrandRail")
		if not rail then
			rail = Instance.new("Frame")
			rail.Name = "SunBrandRail"
			rail.Parent = host
		end
		rail.AnchorPoint = Vector2.zero
		rail.Position = UDim2.fromOffset(0, HEADER_HEIGHT)
		rail.Size = UDim2.new(0, BRAND_RAIL_WIDTH, 1, -HEADER_HEIGHT)
		rail.BackgroundColor3 = Color3.fromRGB(13, 10, 8)
		rail.BackgroundTransparency = 0
		rail.BorderSizePixel = 0
		rail.Active = false
		rail.ClipsDescendants = true
		rail.ZIndex = 5
		rail:SetAttribute("SunBrandRail", true)
		rail:ClearAllChildren()

		local edge = Instance.new("Frame")
		edge.Name = "SolarSeam"
		edge.AnchorPoint = Vector2.new(1, 0)
		edge.Position = UDim2.new(1, 0, 0, 0)
		edge.Size = UDim2.new(0, 1, 1, 0)
		edge.BackgroundColor3 = Color3.fromRGB(111, 61, 23)
		edge.BackgroundTransparency = 0.22
		edge.BorderSizePixel = 0
		edge.Active = false
		edge.ZIndex = 6
		edge.Parent = rail

		local logo = Instance.new("Frame")
		logo.Name = "EclipseMark"
		logo.AnchorPoint = Vector2.new(0.5, 0)
		logo.Position = UDim2.new(0.5, 0, 0, 20)
		logo.Size = UDim2.fromOffset(34, 34)
		logo.BackgroundColor3 = Color3.fromRGB(255, 146, 51)
		logo.BorderSizePixel = 0
		logo.Active = false
		logo.ZIndex = 6
		logo.Parent = rail
		local logoCorner = Instance.new("UICorner")
		logoCorner.CornerRadius = UDim.new(1, 0)
		logoCorner.Parent = logo
		local logoGradient = Instance.new("UIGradient")
		logoGradient.Color = ColorSequence.new(Color3.fromRGB(255, 210, 115), Color3.fromRGB(245, 104, 24))
		logoGradient.Rotation = 35
		logoGradient.Parent = logo

		-- The Animator gets a moving orbital insignia while the Projects
		-- landing rail keeps its calm, static brand mark.
		if caption == "MOTION" then
			local TweenService = game:GetService("TweenService")
			local orbitPath = Instance.new("Frame")
			orbitPath.Name = "AnimatedOrbit"
			orbitPath.AnchorPoint = Vector2.new(0.5, 0.5)
			orbitPath.Position = UDim2.new(0.5, 0, 0, 37)
			orbitPath.Size = UDim2.fromOffset(48, 20)
			orbitPath.Rotation = -28
			orbitPath.BackgroundTransparency = 1
			orbitPath.BorderSizePixel = 0
			orbitPath.Active = false
			orbitPath.ZIndex = 8
			orbitPath.Parent = rail
			local orbitCorner = Instance.new("UICorner")
			orbitCorner.CornerRadius = UDim.new(1, 0)
			orbitCorner.Parent = orbitPath
			local orbitStroke = Instance.new("UIStroke")
			orbitStroke.Thickness = 1
			orbitStroke.Color = Color3.fromRGB(255, 211, 142)
			orbitStroke.Transparency = 0.18
			orbitStroke.Parent = orbitPath
			local satellite = Instance.new("Frame")
			satellite.Name = "Satellite"
			satellite.AnchorPoint = Vector2.new(0.5, 0.5)
			satellite.Position = UDim2.new(1, -3, 0.32, 0)
			satellite.Size = UDim2.fromOffset(6, 6)
			satellite.BackgroundColor3 = Color3.fromRGB(255, 170, 76)
			satellite.BorderSizePixel = 0
			satellite.Active = false
			satellite.ZIndex = 9
			satellite.Parent = orbitPath
			local satelliteCorner = Instance.new("UICorner")
			satelliteCorner.CornerRadius = UDim.new(1, 0)
			satelliteCorner.Parent = satellite
			TweenService:Create(orbitPath, TweenInfo.new(7, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
				Rotation = 332,
			}):Play()
		end

		local eclipse = Instance.new("Frame")
		eclipse.Name = "Eclipse"
		eclipse.AnchorPoint = Vector2.new(0.5, 0.5)
		eclipse.Position = UDim2.new(0.60, 0, 0.40, 0)
		eclipse.Size = UDim2.fromOffset(20, 20)
		eclipse.BackgroundColor3 = Color3.fromRGB(28, 17, 11)
		eclipse.BorderSizePixel = 0
		eclipse.Active = false
		eclipse.ZIndex = 7
		eclipse.Parent = logo
		local eclipseCorner = Instance.new("UICorner")
		eclipseCorner.CornerRadius = UDim.new(1, 0)
		eclipseCorner.Parent = eclipse

		for i = 1, 3 do
			local orbit = Instance.new("Frame")
			orbit.Name = "Orbit" .. i
			orbit.AnchorPoint = Vector2.new(0.5, 0.5)
			orbit.Position = UDim2.new(0.5, 0, 0, 111)
			orbit.Size = UDim2.fromOffset(18 + i * 9, 18 + i * 9)
			orbit.BackgroundTransparency = 1
			orbit.BorderSizePixel = 0
			orbit.Active = false
			orbit.ZIndex = 6
			orbit.Parent = rail
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = orbit
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 1
			stroke.Color = Color3.fromRGB(255, 147, 54)
			stroke.Transparency = 0.42 + i * 0.13
			stroke.Parent = orbit
		end

		local core = Instance.new("Frame")
		core.Name = "OrbitCore"
		core.AnchorPoint = Vector2.new(0.5, 0.5)
		core.Position = UDim2.new(0.5, 0, 0, 111)
		core.Size = UDim2.fromOffset(6, 6)
		core.BackgroundColor3 = Color3.fromRGB(255, 177, 76)
		core.BorderSizePixel = 0
		core.Active = false
		core.ZIndex = 7
		core.Parent = rail
		local coreCorner = Instance.new("UICorner")
		coreCorner.CornerRadius = UDim.new(1, 0)
		coreCorner.Parent = core

		local wordmark = Instance.new("TextLabel")
		wordmark.Name = "Wordmark"
		wordmark.AnchorPoint = Vector2.new(0.5, 0)
		wordmark.Position = UDim2.new(0.5, 0, 0, 153)
		wordmark.Size = UDim2.new(1, -6, 0, 18)
		wordmark.BackgroundTransparency = 1
		wordmark.Font = Enum.Font.GothamBold
		wordmark.Text = "SUN"
		wordmark.TextColor3 = Color3.fromRGB(255, 206, 146)
		wordmark.TextSize = 10
		wordmark.Active = false
		wordmark.ZIndex = 7
		wordmark.Parent = rail

		local captionLabel = Instance.new("TextLabel")
		captionLabel.Name = "RailCaption"
		captionLabel.AnchorPoint = Vector2.new(0.5, 1)
		captionLabel.Position = UDim2.new(0.5, 0, 1, -15)
		captionLabel.Size = UDim2.new(1, -10, 0, 40)
		captionLabel.BackgroundTransparency = 1
		captionLabel.Font = Enum.Font.GothamMedium
		captionLabel.Text = caption .. "\nSTUDIO"
		captionLabel.TextColor3 = Color3.fromRGB(143, 114, 88)
		captionLabel.TextSize = 8
		captionLabel.TextWrapped = true
		captionLabel.Active = false
		captionLabel.ZIndex = 7
		captionLabel.Parent = rail
		return rail
	end

		local function normalizeMenuBar(host: Instance)
		local bar = host:FindFirstChild("Bar")
		if not bar then return nil end
		local rail = host:FindFirstChild("ProjectNavigationRail")
			or host:FindFirstChild("ToolNavigationRail")
		local menu = bar:FindFirstChild("MenuButtons")
		-- Restore a menu that was already moved into our rail by an earlier
		-- plugin session before the rail is rebuilt. This makes close/reopen safe.
		if not menu then
			local brandRail = host:FindFirstChild("SunBrandRail")
			local storedMenu = brandRail and brandRail:FindFirstChild("AnimatorMenuButtons")
			if storedMenu then
				storedMenu.Name = "MenuButtons"
				storedMenu.Parent = bar
				menu = storedMenu
			end
		end
		if rail then
			local moved = rail:FindFirstChild("NavigationItems", true)
			if moved and not menu then
				moved.Name = "MenuButtons"
				moved.Parent = bar
				menu = moved
			end
			rail:Destroy()
		end
		if not menu then return nil end

		menu.Visible = true
		menu.Active = false
		menu.AnchorPoint = Vector2.zero
		menu.Position = UDim2.fromOffset(0, 0)
		menu.Size = UDim2.new(0, 0, 1, 0)
		menu.AutomaticSize = Enum.AutomaticSize.X
		menu.BackgroundTransparency = 1
		menu.ClipsDescendants = false
		local layout = menu:FindFirstChildOfClass("UIListLayout")
		if not layout then
			layout = Instance.new("UIListLayout")
			layout.Parent = menu
		end
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 4)
		for _, button in menu:GetChildren() do
			if button:IsA("GuiButton") then
				button.AutomaticSize = Enum.AutomaticSize.X
				button.Size = UDim2.fromOffset(0, 28)
				button.Position = UDim2.fromOffset(0, 0)
				button.Active = true
				button.AutoButtonColor = true
				button.BackgroundTransparency = 0
				local label = button:FindFirstChildWhichIsA("TextLabel", true)
				if label then
					label.AnchorPoint = Vector2.zero
					label.AutomaticSize = Enum.AutomaticSize.None
					local width = math.max(56, math.ceil(label.TextBounds.X + 22), #label.Text * 8 + 18)
					label.Position = UDim2.fromOffset(0, 0)
					label.Size = UDim2.fromOffset(width, 28)
					label.TextXAlignment = Enum.TextXAlignment.Center
					label.TextYAlignment = Enum.TextYAlignment.Center
				end
			end
		end
		return menu
	end

	local primaryMenu = normalizeMenuBar(PrimaryFrame)
	UI.PrimaryBrandRail = makeSolarRail(PrimaryFrame, "PROJECTS")
	PrimaryFrame:SetAttribute("SunBrandRailWidth", BRAND_RAIL_WIDTH)
	PrimaryFrame:SetAttribute("SunHeaderHeight", HEADER_HEIGHT)
	if not primaryMenu then
		error("Sun Editor could not restore the Projects menu buttons")
	end

	-- Give the project landing screen the same deliberate workspace layout.
	if PrimaryFrame:GetAttribute("SunEditorialLayoutVersion") ~= 10 then
		PrimaryFrame:SetAttribute("SunEditorialLayout", true)
		PrimaryFrame:SetAttribute("SunEditorialLayoutVersion", 10)
		PrimaryFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		PrimaryFrame.Size = UDim2.fromOffset(980, 620)
		local projectBar = PrimaryFrame:WaitForChild("Bar")
		local projectAppearance = projectBar:WaitForChild("Appearence")
		projectAppearance.Title.Text = "SUN / PROJECTS"
		projectAppearance.Title.Position = UDim2.fromOffset(38, 0)
		projectAppearance.Title.Size = UDim2.new(0, 124, 1, 0)
		projectBar.AnchorPoint = Vector2.new(0.5, 0)
		projectBar.Position = UDim2.new(0.5, 0, 0, 0)
		projectBar.Size = UDim2.new(1, -2, 0, 50)
		projectBar.BackgroundColor3 = Color3.fromRGB(20, 16, 13)
		projectBar.BackgroundTransparency = 0
		local barCorner = projectBar:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
		barCorner.CornerRadius = UDim.new(0, 11)
		barCorner.Parent = projectBar
		local barStroke = projectBar:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
		barStroke.Thickness = 1
		barStroke.Transparency = 0.35
		barStroke.Color = Color3.fromRGB(143, 82, 34)
		barStroke.Parent = projectBar

		MainFrame.Position = UDim2.fromOffset(BRAND_RAIL_WIDTH, HEADER_HEIGHT)
		MainFrame.Size = UDim2.new(1, -BRAND_RAIL_WIDTH, 1, -HEADER_HEIGHT)
		local pagePadding = MainFrame:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
		pagePadding.PaddingTop = UDim.new(0, 10)
		pagePadding.PaddingBottom = UDim.new(0, 10)
		pagePadding.PaddingLeft = UDim.new(0, 12)
		pagePadding.PaddingRight = UDim.new(0, 12)
		pagePadding.Parent = MainFrame
		local pageLayout = MainFrame:FindFirstChildOfClass("UIListLayout")
		if pageLayout then pageLayout.Padding = UDim.new(0, 12) end

		local function surfaceCard(frame, background, radius)
			frame.BackgroundColor3 = background
			frame.BackgroundTransparency = 0
			frame.ClipsDescendants = true
			local corner = frame:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, radius)
			corner.Parent = frame
			local outline = frame:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
			outline.Thickness = 1
			outline.Transparency = 0.48
			outline.Color = Color3.fromRGB(82, 54, 34)
			outline.Parent = frame
			local padding = frame:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
			padding.PaddingTop = UDim.new(0, 12)
			padding.PaddingBottom = UDim.new(0, 12)
			padding.PaddingLeft = UDim.new(0, 12)
			padding.PaddingRight = UDim.new(0, 12)
			padding.Parent = frame
		end

		local recentCard = MainFrame:WaitForChild("Left")
		local createCard = MainFrame:WaitForChild("Center")
		local savedCard = MainFrame:WaitForChild("Right")
		surfaceCard(recentCard, Color3.fromRGB(18, 15, 13), 10)
		surfaceCard(createCard, Color3.fromRGB(27, 21, 17), 12)
		surfaceCard(savedCard, Color3.fromRGB(18, 15, 13), 10)
		for _, panel in { recentCard, createCard, savedCard } do
			local heading = panel:FindFirstChild("Label1")
			if heading and heading:IsA("TextLabel") then
				heading.Font = Enum.Font.GothamSemibold
				heading.TextSize = 13
				heading.TextColor3 = Color3.fromRGB(245, 232, 216)
			end
		end
		local welcome = createCard:FindFirstChild("Label1")
		local hint = createCard:FindFirstChild("Label2")
		if welcome then
			welcome.Font = Enum.Font.GothamSemibold
			welcome.TextSize = 21
			welcome.TextColor3 = Color3.fromRGB(255, 238, 214)
		end
		if hint then
			hint.Font = Enum.Font.Gotham
			hint.TextSize = 12
			hint.TextColor3 = Color3.fromRGB(190, 160, 132)
		end
		local createButton = createCard:FindFirstChild("ProjectCreator")
		if createButton then
			createButton.BackgroundColor3 = Color3.fromRGB(244, 132, 36)
			createButton.TextColor3 = Color3.fromRGB(17, 11, 7)
			createButton.Font = Enum.Font.GothamSemibold
			local buttonCorner = createButton:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
			buttonCorner.CornerRadius = UDim.new(0, 8)
			buttonCorner.Parent = createButton
		end
	end

	local connectionFrame = Tabs:FindFirstChild("Connection")
	if connectionFrame then
		connectionFrame:Destroy()
	end

	local PrimaryDragFrame = PrimaryFrame:FindFirstChild("Drag")
	if PrimaryDragFrame then
		UI.PrimaryDragFrame = PrimaryDragFrame
		UI.PrimaryDragButton = PrimaryDragFrame:FindFirstChild("DragButton")
	end

	local CenterFrame = MainFrame.Center
	local RightFrame = MainFrame.Right
	UI.CenterFrame = CenterFrame
	UI.RightFrame = RightFrame
	UI.ProjectCreator_BTN = CenterFrame.ProjectCreator
	UI.Label1_LBL = CenterFrame.Label1
	UI.Label2_LBL = CenterFrame.Label2

	local AlertFrame = Components.Alert
	UI.AlertFrame = AlertFrame
	UI.AgreeButton = AlertFrame.Buttons.Agree
	UI.DisagreeButton = AlertFrame.Buttons.Disagree
	UI.HeaderLabel = AlertFrame.Information.Header.Header
	UI.DescriptionLabel = AlertFrame.Information.Description

	UI.NotificationFrame = Components.Notification.Main

	UI.FrameButton = RightFrame.ScrollingFrame
	UI.TemplateButton = RightFrame.ScrollingFrame.Template

	local animatorHost = Tabs:FindFirstChild("SunTransformVisibility") or Tabs
	local AnimatorFrame = animatorHost:FindFirstChild("Animator")
		or Tabs:FindFirstChild("Animator")
	if not AnimatorFrame then
		error("Sun Editor could not find the Animator window under Tabs")
	end
	local AnimatorFrames = AnimatorFrame:WaitForChild("Frames")
	UI.AnimatorFrame = AnimatorFrame
	UI.AnimatorFrames = AnimatorFrames
	local animatorMenu = normalizeMenuBar(AnimatorFrame)
	UI.AnimatorBrandRail = makeSolarRail(AnimatorFrame, "MOTION")
	AnimatorFrame:SetAttribute("SunBrandRailWidth", BRAND_RAIL_WIDTH)
	AnimatorFrame:SetAttribute("SunHeaderHeight", HEADER_HEIGHT)
	if not animatorMenu then
		error("Sun Editor could not restore the Animator menu buttons")
	end
	UI.AnimatorMenuButtons = animatorMenu

	-- Keep the original menu buttons and their click bindings, but give the
	-- Animator a narrow icon dock that expands over the workspace on hover.
	local animatorRail = UI.AnimatorBrandRail
	animatorRail.ClipsDescendants = false
	animatorRail.ZIndex = 25
	animatorMenu.Parent = animatorRail
	animatorMenu.Name = "AnimatorMenuButtons"
	animatorMenu.AnchorPoint = Vector2.zero
	animatorMenu.Position = UDim2.fromOffset(6, 205)
	animatorMenu.Size = UDim2.fromOffset(48, 0)
	animatorMenu.AutomaticSize = Enum.AutomaticSize.Y
	animatorMenu.BackgroundTransparency = 1
	animatorMenu.ClipsDescendants = false
	animatorMenu.ZIndex = 30
	local animatorMenuLayout = animatorMenu:FindFirstChildOfClass("UIListLayout")
	animatorMenuLayout.FillDirection = Enum.FillDirection.Vertical
	animatorMenuLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	animatorMenuLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	animatorMenuLayout.SortOrder = Enum.SortOrder.LayoutOrder
	animatorMenuLayout.Padding = UDim.new(0, 5)
	local commandGlyphs = {
		File = "▤",
		Edit = "✎",
		Tools = "⌘",
		Rig = "◈",
		View = "◉",
		Settings = "⚙",
		Item = "◇",
	}
	local TweenService = game:GetService("TweenService")
	local function setExpanded(button, expanded)
		local width = expanded and 156 or 44
		TweenService:Create(button, TweenInfo.new(0.16, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(width, 36),
			BackgroundColor3 = expanded and Color3.fromRGB(57, 34, 20) or Color3.fromRGB(30, 23, 18),
		}):Play()
		local label = button:FindFirstChild("RailCaption")
		if label then
			TweenService:Create(label, TweenInfo.new(0.12), { TextTransparency = expanded and 0 or 1 }):Play()
		end
	end
	local function styleCommandButton(button)
		if not button:IsA("GuiButton") then return end
		local sourceLabel = button:FindFirstChildWhichIsA("TextLabel", true)
		local labelText = sourceLabel and sourceLabel.Text or (button:IsA("TextButton") and button.Text) or button.Name
		local labelKey = string.match(labelText, "%a+") or "Item"
		local glyph = button:FindFirstChild("RailGlyph")
		if not glyph then
			glyph = Instance.new("TextLabel")
			glyph.Name = "RailGlyph"
		end
			glyph.AnchorPoint = Vector2.new(0, 0.5)
			glyph.Position = UDim2.new(0, 0, 0.5, 0)
			glyph.Size = UDim2.fromOffset(44, 36)
			glyph.BackgroundTransparency = 1
			glyph.Font = Enum.Font.GothamSemibold
			glyph.Text = commandGlyphs[labelKey] or string.upper(string.sub(labelKey, 1, 1))
			glyph.TextColor3 = Color3.fromRGB(255, 179, 94)
			glyph.TextSize = 17
			glyph.Active = false
			glyph.ZIndex = 33
			glyph.Parent = button

		local captionLabel = button:FindFirstChild("RailCaption")
		if not captionLabel then
			captionLabel = Instance.new("TextLabel")
			captionLabel.Name = "RailCaption"
		end
			captionLabel.Position = UDim2.fromOffset(43, 0)
			captionLabel.Size = UDim2.new(1, -51, 1, 0)
			captionLabel.BackgroundTransparency = 1
			captionLabel.Font = Enum.Font.GothamMedium
			captionLabel.Text = labelText
			captionLabel.TextColor3 = Color3.fromRGB(255, 235, 211)
			captionLabel.TextSize = 12
			captionLabel.TextXAlignment = Enum.TextXAlignment.Left
			captionLabel.TextTransparency = 1
			captionLabel.Active = false
			captionLabel.ZIndex = 34
		captionLabel.Text = labelText
		captionLabel.Parent = button

		if sourceLabel and sourceLabel ~= glyph and sourceLabel ~= captionLabel then sourceLabel.Visible = false end
		if button:IsA("TextButton") then button.Text = "" end
		button.AnchorPoint = Vector2.zero
		button.Size = UDim2.fromOffset(44, 36)
		button.Position = UDim2.fromOffset(0, 0)
		button.AutomaticSize = Enum.AutomaticSize.None
		button.BackgroundColor3 = Color3.fromRGB(30, 23, 18)
		button.BackgroundTransparency = 0
		button.BorderSizePixel = 0
		button.Active = true
		button.Interactable = true
		button.AutoButtonColor = false
		button.ZIndex = 32
		local buttonCorner = button:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 9)
		buttonCorner.Parent = button
		local buttonStroke = button:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
		buttonStroke.Thickness = 1
		buttonStroke.Color = Color3.fromRGB(116, 70, 38)
		buttonStroke.Transparency = 0.45
		buttonStroke.Parent = button
		if not button:GetAttribute("SunRailStyled") then
			button:SetAttribute("SunRailStyled", true)
			button.MouseEnter:Connect(function() setExpanded(button, true) end)
			button.MouseLeave:Connect(function() setExpanded(button, false) end)
		end
	end
	for _, button in animatorMenu:GetChildren() do styleCommandButton(button) end
	if not animatorMenu:GetAttribute("SunRailChildBinding") then
		animatorMenu:SetAttribute("SunRailChildBinding", true)
		animatorMenu.ChildAdded:Connect(function(button)
			task.defer(function()
				if button.Parent == animatorMenu and button:IsA("GuiButton") then
					-- Clones inherit UI attributes but not event connections.
					button:SetAttribute("SunRailStyled", nil)
					styleCommandButton(button)
				end
			end)
		end)
	end

	local AnimatorDragFrame = AnimatorFrame:FindFirstChild("Drag")
	if AnimatorDragFrame then
		UI.AnimatorDragFrame = AnimatorDragFrame
		UI.AnimatorDragButton = AnimatorDragFrame:FindFirstChild("DragButton")
	end

	local AnimatorBarFrame = AnimatorFrame:WaitForChild("Bar")
	UI.AnimatorBarFrame = AnimatorBarFrame


	UI.ReturnButton = AnimatorFrame.Bar.ControlButtons.ExitButton
	UI.ExportButton = AnimatorFrame.Bar.ControlButtons.ExportButton
	UI.SaveButton = AnimatorFrame.Bar.ControlButtons:FindFirstChild("SaveButton")
	UI.LoopButton = AnimatorFrames.Main.Content.LeftDiv.TopContainer.LeftDiv.Loop
	UI.AddRigButton =
		AnimatorFrames.Main.Content.LeftDiv.TopContainer.LeftDiv:FindFirstChild("AddRig")
	UI.RecordButton =
		AnimatorFrames.Main.Content.LeftDiv.TopContainer.LeftDiv:FindFirstChild("Record")
	UI.PlayButton =
		AnimatorFrames.Main.Content.LeftDiv.TopContainer.LeftDiv:FindFirstChild("Play")
	UI.ReverseButton =
		AnimatorFrames.Main.Content.LeftDiv.TopContainer.LeftDiv:FindFirstChild("Reverse")
	UI.SnapButton =
		AnimatorFrames.Main.Content.LeftDiv.TopContainer.LeftDiv:FindFirstChild("Snap")

	UI.FPSLabel = AnimatorFrames.Main.Content.LeftDiv.TopContainer.RightDiv.Time.FramesPerSecond
	UI.TimeLabel = AnimatorFrames.Main.Content.LeftDiv.TopContainer.RightDiv.Time.Time
	UI.ProjectNameTextBox =
		AnimatorFrames.Main.Content.LeftDiv.TopContainer.RightDiv.ProjectName.Edit
	UI.ProjectNameTextBox.PlaceholderText = "New Animation"
	UI.ProjectNameTextBox.ClearTextOnFocus = false

	local header = AnimatorFrames.Main.Content.LeftDiv.TopContainer
	header.LeftDiv.AutomaticSize = Enum.AutomaticSize.None
	header.LeftDiv.Size = UDim2.new(0, 168, 1, 0)
	for _, button in { UI.AddRigButton, UI.PlayButton, UI.ReverseButton, UI.LoopButton, UI.RecordButton, UI.SnapButton } do
		if button then
			button.Size = UDim2.fromOffset(24, 24)
		end
	end

	header.RightDiv.AutomaticSize = Enum.AutomaticSize.None
	header.RightDiv.Size = UDim2.new(1, -172, 1, 0)
	header.RightDiv.ClipsDescendants = true
	header.RightDiv.ProjectName.Size = UDim2.new(1, 0, 0, 14)
	header.RightDiv.Time.Size = UDim2.new(1, 0, 0, 16)
	for _, label in { UI.TimeLabel, UI.FPSLabel } do
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.new(0, 0, 1, 0)
		label.TextSize = 10
		label.TextYAlignment = Enum.TextYAlignment.Center
	end

	local headerLayout = header.RightDiv:FindFirstChildOfClass("UIListLayout")
	if headerLayout then
		headerLayout.Padding = UDim.new(0, 0)
	end

	UI.ProjectNameTextBox.AutomaticSize = Enum.AutomaticSize.None
	UI.ProjectNameTextBox.Position = UDim2.fromOffset(0, 0)
	UI.ProjectNameTextBox.Size = UDim2.fromScale(1, 1)
	UI.ProjectNameTextBox.TextTruncate = Enum.TextTruncate.AtEnd

	local TopSlider = AnimatorFrames.Main.BottomContainer.TopSlider.Drag
	UI.TopSlider = TopSlider
	UI.LeftDrag = TopSlider.LeftDrag
	UI.RightDrag = TopSlider.RightDrag

	local AnimatorMain = AnimatorFrames.Main
	local LeftDiv = AnimatorMain.Content.LeftDiv
	local RightDiv = AnimatorMain.Content.RightDiv
	UI.AnimatorMain = AnimatorMain
	UI.LeftDiv = LeftDiv
	UI.RightDiv = RightDiv

	-- Keep the existing two-column editor structure intact. Experimental
	-- section headers and toolbar relocation obscured the rig controls.
	if AnimatorFrame:GetAttribute("SunEditorialLayoutVersion") ~= 11 then
		AnimatorFrame:SetAttribute("SunEditorialLayout", true)
		AnimatorFrame:SetAttribute("SunEditorialLayoutVersion", 11)
		AnimatorFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		AnimatorFrame.Size = UDim2.fromOffset(980, 620)

		local appBar = AnimatorFrame:WaitForChild("Bar")
		local animatorAppearance = appBar:WaitForChild("Appearence")
		animatorAppearance.Title.Text = "SUN / ORBITAL MOTION"
		animatorAppearance.Title.Position = UDim2.fromOffset(38, 0)
		animatorAppearance.Title.Size = UDim2.new(0, 190, 1, 0)
		appBar.AnchorPoint = Vector2.new(0.5, 0)
		appBar.Position = UDim2.new(0.5, 0, 0, 0)
		appBar.Size = UDim2.new(1, -2, 0, HEADER_HEIGHT)
		appBar.BackgroundColor3 = Color3.fromRGB(20, 16, 13)
		appBar.BackgroundTransparency = 0
		local appBarCorner = appBar:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
		appBarCorner.CornerRadius = UDim.new(0, 11)
		appBarCorner.Parent = appBar
		local appBarStroke = appBar:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
		appBarStroke.Thickness = 1
		appBarStroke.Transparency = 0.35
		appBarStroke.Color = Color3.fromRGB(143, 82, 34)
		appBarStroke.Parent = appBar

		AnimatorMain.Position = UDim2.fromOffset(BRAND_RAIL_WIDTH, HEADER_HEIGHT)
		AnimatorMain.Size = UDim2.new(1, -BRAND_RAIL_WIDTH, 1, -HEADER_HEIGHT)
		local content = AnimatorMain:WaitForChild("Content")
		local contentPadding = content:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
		contentPadding.PaddingTop = UDim.new(0, 10)
		contentPadding.PaddingBottom = UDim.new(0, 8)
		contentPadding.PaddingLeft = UDim.new(0, 12)
		contentPadding.PaddingRight = UDim.new(0, 12)
		contentPadding.Parent = content
		local contentLayout = content:FindFirstChildOfClass("UIListLayout")
		if contentLayout then contentLayout.Padding = UDim.new(0, 10) end

		LeftDiv.Size = UDim2.new(0, 248, 1, 0)
		LeftDiv.BackgroundColor3 = Color3.fromRGB(18, 15, 13)
		LeftDiv.BackgroundTransparency = 0
		LeftDiv.ClipsDescendants = true
		local sidebarCorner = LeftDiv:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
		sidebarCorner.CornerRadius = UDim.new(0, 10)
		sidebarCorner.Parent = LeftDiv
		local sidebarStroke = LeftDiv:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
		sidebarStroke.Thickness = 1
		sidebarStroke.Transparency = 0.45
		sidebarStroke.Color = Color3.fromRGB(102, 63, 34)
		sidebarStroke.Parent = LeftDiv

		local rigListContainer = LeftDiv:WaitForChild("RigListContainer")
		local toolbar = LeftDiv:WaitForChild("TopContainer")
		local function ensureRigSectionHeader()
			local card = LeftDiv:FindFirstChild("RigSectionHeader")
			if not card then
				card = Instance.new("Frame")
				card.Name = "RigSectionHeader"
				card.BackgroundColor3 = Color3.fromRGB(34, 25, 19)
				card.BorderSizePixel = 0
				card.Active = false
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0, 7)
				corner.Parent = card
				local stripe = Instance.new("Frame")
				stripe.Name = "Accent"
				stripe.BorderSizePixel = 0
				stripe.BackgroundColor3 = Color3.fromRGB(255, 139, 43)
				stripe.Position = UDim2.fromOffset(10, 10)
				stripe.Size = UDim2.new(0, 3, 1, -20)
				stripe.Active = false
				stripe.Parent = card
				local stripeCorner = Instance.new("UICorner")
				stripeCorner.CornerRadius = UDim.new(1, 0)
				stripeCorner.Parent = stripe
				local title = Instance.new("TextLabel")
				title.Name = "SectionTitle"
				title.BackgroundTransparency = 1
				title.Position = UDim2.fromOffset(22, 7)
				title.Size = UDim2.new(1, -30, 0, 17)
				title.Font = Enum.Font.GothamSemibold
				title.Text = "RIGS & TRACKS"
				title.TextSize = 11
				title.TextColor3 = Color3.fromRGB(255, 235, 215)
				title.TextXAlignment = Enum.TextXAlignment.Left
				title.Active = false
				title.Parent = card
				local detail = Instance.new("TextLabel")
				detail.Name = "SectionDetail"
				detail.BackgroundTransparency = 1
				detail.Position = UDim2.fromOffset(22, 25)
				detail.Size = UDim2.new(1, -30, 0, 14)
				detail.Font = Enum.Font.Gotham
				detail.Text = "Select a rig to edit its motion"
				detail.TextSize = 9
				detail.TextColor3 = Color3.fromRGB(185, 153, 126)
				detail.TextXAlignment = Enum.TextXAlignment.Left
				detail.Active = false
				detail.Parent = card
			end
			card.LayoutOrder = -2
			card.Size = UDim2.new(1, 0, 0, 48)
			card.Active = false
			return card
		end
		ensureRigSectionHeader()
		toolbar.Parent = LeftDiv
		toolbar.LayoutOrder = -1
		toolbar.Size = UDim2.new(1, 0, 0, 44)
		rigListContainer.LayoutOrder = 0
		rigListContainer.Size = UDim2.new(1, 0, 1, -116)
		local sidebarLayout = LeftDiv:FindFirstChildOfClass("UIListLayout")
		if sidebarLayout then
			sidebarLayout.Padding = UDim.new(0, 8)
			sidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
		end

		local timeline = RightDiv:WaitForChild("TimelineContainer")
		local timelineLayout = RightDiv:FindFirstChildOfClass("UIListLayout")
		if timelineLayout then timelineLayout.Padding = UDim.new(0, 8) end
		timeline.LayoutOrder = 0
		timeline.BackgroundColor3 = Color3.fromRGB(15, 12, 10)
		timeline.BackgroundTransparency = 0
		local timelineCorner = timeline:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
		timelineCorner.CornerRadius = UDim.new(0, 10)
		timelineCorner.Parent = timeline
		local timelineStroke = timeline:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
		timelineStroke.Thickness = 1
		timelineStroke.Transparency = 0.48
		timelineStroke.Color = Color3.fromRGB(86, 55, 35)
		timelineStroke.Parent = timeline

		local bottom = AnimatorMain:WaitForChild("BottomContainer")
		bottom.Size = UDim2.new(1, 0, 0, 38)
		bottom.BackgroundColor3 = Color3.fromRGB(23, 17, 13)
		bottom.BackgroundTransparency = 0
		local bottomCorner = bottom:FindFirstChildOfClass("UICorner")
		if bottomCorner then bottomCorner.CornerRadius = UDim.new(0, 9) end
	end

	local TimelineContainer = RightDiv.TimelineContainer
	local Scale = TimelineContainer.Scale
	local Fit = Scale.Fit
	local KeysRoot = Scale.Keys
	local Misc = Scale.Misc
	UI.TimelineContainer = TimelineContainer
	UI.Scale = Scale
	UI.SelectionBox = Scale:FindFirstChild("SelectionBox")
	UI.Fit = Fit
	UI.KeysRoot = KeysRoot
	UI.Misc = Misc

	local GuidesFolder = Misc.Guides
	UI.GuidesFolder = GuidesFolder
	UI.GuideTemplate = GuidesFolder.Guide0

	local TickFrame = Misc.TickFrame
	TickFrame:WaitForChild("Position"):WaitForChild("Line"):SetAttribute("ThemeBg", "Div")
	local TickNumberContainer = TickFrame.Number
	UI.TickFrame = TickFrame
	UI.TickNumberContainer = TickNumberContainer
	UI.TickTemplate = TickNumberContainer.Tick0

	local TopSelector = TickNumberContainer.TopSelector
	UI.TopSelector = TopSelector
	UI.TopSelectorLabel = TopSelector.TextLabel
	UI.DragBarHitbox = TimelineContainer.DragBarHitbox

	local SelectorContainer = Scale.SelectorContainer
	UI.SelectorContainer = SelectorContainer
	UI.Selector = SelectorContainer.Selector

	local TrackContainer = KeysRoot.TemplateFrame
	UI.TrackContainer = TrackContainer
	UI.TrackTemplate = TrackContainer:FindFirstChild("TrackContainers")
		:FindFirstChild("TrackTemplate")

	local RigListScroll = LeftDiv.RigListContainer.RigContainerScroll
	UI.RigListScroll = RigListScroll
	UI.RigItemTemplate = RigListScroll.ItemTemplate

	local BarFrame = PrimaryFrame:WaitForChild("Bar")
	UI.BarFrame = BarFrame

	local MenuButtons = BarFrame:WaitForChild("MenuButtons")
	UI.MenuButtons = MenuButtons
	local riggingButton = MenuButtons:FindFirstChild("RiggingButton")
	if riggingButton then
		riggingButton:Destroy()
	end

	UI.ArmatureButton = MenuButtons:FindFirstChild("ArmatureButton")

	local ControlButtons = BarFrame:WaitForChild("ControlButtons")
	UI.ControlButtons = ControlButtons
	UI.ExitButton = ControlButtons:WaitForChild("ExitButton")

	UI.AxisPackage = {
		PositionAxis = SunGUI.Axis.Position,
		RotationAxis = SunGUI.Axis.Rotation,
	}

	resolved = true
	return UI
end

local function isAnimatorActive(loading)
	local state = require("State")
	if
		state.LoadingProject
		and not (loading == true and state.ProjectLoadThread == coroutine.running())
	then
		return false
	end

	return UI.SunGUI ~= nil
		and UI.SunGUI.Parent ~= nil
		and UI.SunGUI.Enabled == true
		and UI.SunGUI:GetAttribute("SunConfirmationOpen") ~= true
		and UI.AnimatorFrame ~= nil
		and (UI.AnimatorFrame.Visible == true or require("State").CameraPoseMode == true)
end

UI.resolve = resolve
UI.isAnimatorActive = isAnimatorActive

return UI

