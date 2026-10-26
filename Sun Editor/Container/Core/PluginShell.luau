--!nocheck


local require = require(script:FindFirstAncestor("Container").Require)

local CoreGui = game:GetService("CoreGui")
local EventPlayback = require("EventPlayback")

local WindowFX = require("WindowFX")

local Visibility = require("Visibility")
local State = require("State")
local PluginShell = {}

local attached = false
local attachedSource, mainGui, helpersGui

function PluginShell.getUI(source)
	assert(
		attachedSource == source and mainGui and helpersGui,
		"Sun UI is not attached to this plugin"
	)
	return mainGui, helpersGui
end

local function attach(plugin: any, sunScript: Instance)
	if attached then
		return
	end

	attached = true
	WindowFX.recoverClosingTools(CoreGui)

	local SunUI = sunScript:WaitForChild("Sun")
	local MiscUI = sunScript:WaitForChild("Miscellaneous")
	local ValuesFolder = sunScript:WaitForChild("Values")
	local PlayersFolder = sunScript:WaitForChild("Players")

	local RequestEvent = PlayersFolder:WaitForChild("RequestEvent")
	local PluginActiveBool = ValuesFolder:WaitForChild("PluginActive")
	local ClosingEvent = ValuesFolder:FindFirstChild("Closing")

	local AlertFrame =
		SunUI:WaitForChild("Frame"):WaitForChild("Components"):WaitForChild("Alert")

	local token = game:GetService("HttpService"):GenerateGUID(false)
	local edition = sunScript.Name:lower():find("experimental", 1, true) and "Experimental" or "Animator"
	local build = "v1.0956-10-15-2026"
	attachedSource, mainGui, helpersGui = sunScript, SunUI, MiscUI
	for _, gui in { SunUI, MiscUI } do
		gui:SetAttribute("SunInstance", token)
		gui:SetAttribute("SunBuild", build)
		gui:SetAttribute("SunBuildId", sunScript:GetAttribute("SunBuild"))
		gui:SetAttribute("SunSource", sunScript:GetFullName())
		gui.Enabled = false
	end

	SunUI.Name = "Sun Animator [" .. edition .. "] " .. token
	MiscUI.Name = "Sun Helpers [" .. edition .. "] " .. token
	SunUI.Parent = CoreGui
	MiscUI.Parent = CoreGui
	Visibility.init(plugin, SunUI, MiscUI)

	local toolbar = plugin:CreateToolbar("Sun " .. edition)

	local button = toolbar:CreateButton(
		"Sun " .. edition,
		"Open Sun " .. edition .. " · " .. build,
		"rbxassetid://85519215606222"
	)

	local miscButton = toolbar:CreateButton(
		"Rigs",
		"Open " .. edition .. " Rigs · " .. build,
		"rbxassetid://85519215606222"
	)

	button.ClickableWhenViewportHidden = true
	miscButton.ClickableWhenViewportHidden = true

	local function isAlertOpen(): boolean
		return SunUI.Enabled and AlertFrame.Visible
	end

	local activeLock = false

	local function clearNativeSelection()
		local ignore = State.ignoreSelectionChanged
		State.ignoreSelectionChanged = true
		game:GetService("Selection"):Set({})
		State.ignoreSelectionChanged = ignore
	end

	local function updatePluginState()
		local shouldBeActive = PluginActiveBool.Value == true

		pcall(function()
			button:SetActive(shouldBeActive)
		end)

		if shouldBeActive and not State.WorkspaceSelection then
			activeLock = true
			plugin:Activate(true)
		else
			activeLock = false
			plugin:Deactivate()
		end
	end

	local function getVisibleSunWindow()
		local floating = SunUI:FindFirstChild("SunFloatingVisibility")
		local frame = SunUI:FindFirstChild("Frame")
			or floating and floating:FindFirstChild("Frame")
		local tabs = frame and frame:FindFirstChild("Tabs")
		if not tabs then
			return nil
		end

		local transformHost = tabs:FindFirstChild("SunTransformVisibility")
		local animator = tabs:FindFirstChild("Animator")
			or transformHost and transformHost:FindFirstChild("Animator")
		if animator and animator.Visible then
			return animator
		end

		local primary = tabs:FindFirstChild("Primary")
		if primary and primary.Visible then
			return primary
		end

		return nil
	end

	button.Click:Connect(function()
		if State.PresentationHidden then
			Visibility.setHidden(false)
			return
		end

		if isAlertOpen() then
			return
		end

		if SunUI.Enabled and getVisibleSunWindow() then
			local inProject = RequestEvent:Invoke("IsInProject")

			if inProject then
				RequestEvent:Invoke("RequestCloseProject")
				return
			end

			WindowFX.shrink(getVisibleSunWindow(), function()
				SunUI.Enabled = false
			end)
			return
		end

		if not getVisibleSunWindow() then
			local floating = SunUI:FindFirstChild("SunFloatingVisibility")
			local frame = SunUI:FindFirstChild("Frame")
				or (floating and floating:FindFirstChild("Frame"))
			local tabs = frame and frame:FindFirstChild("Tabs")
			local primary = tabs and tabs:FindFirstChild("Primary")
			local transformHost = tabs and tabs:FindFirstChild("SunTransformVisibility")
			local animator = (tabs and tabs:FindFirstChild("Animator"))
				or (transformHost and transformHost:FindFirstChild("Animator"))

			if primary then
				primary.Visible = true
			elseif animator then
				animator.Visible = true
			end
		end

		SunUI.Enabled = true
	end)

	miscButton.Click:Connect(function()
		if State.PresentationHidden then
			Visibility.setHidden(false)
			return
		end

		if isAlertOpen() then
			return
		end

		if MiscUI.Enabled then
			WindowFX.shrink(MiscUI:FindFirstChild("HelperFrame"), function()
				MiscUI.Enabled = false
			end)
		else
			if State.HelperMenu then
				State.HelperMenu.captureSelection()
			end

			MiscUI.Enabled = true
		end
	end)

	PluginActiveBool:GetPropertyChangedSignal("Value"):Connect(function()
		if PluginActiveBool.Value then
			if State.WorkspaceSelection then
				State.setWorkspaceSelection(false)
				return
			end

			clearNativeSelection()
		end

		updatePluginState()
	end)

	plugin.Unloading:Connect(function()
		activeLock = false
		EventPlayback.clear()
		if ClosingEvent then
			ClosingEvent:Fire()
		end

		SunUI:Destroy()
		MiscUI:Destroy()
	end)

	function State.setWorkspaceSelection(enabled, selectTool, preserveSelection)
		enabled = enabled == true
		if State.WorkspaceSelection == enabled then
			if enabled and selectTool then
				plugin:SelectRibbonTool(Enum.RibbonTool.Select, UDim2.new())
			end

			return
		end

		local timeline = State.Timeline and State.Timeline:GetState()
		if enabled and (State.LoadingProject or timeline and timeline.Exporting) then
			return
		end

		if enabled then
			require("Project").finalizeCurrentManipulation()
			if timeline and timeline.Playing then
				require("Project").stopAllAnimations()
			end
		end

		if not enabled and not preserveSelection then
			clearNativeSelection()
		end

		State.WorkspaceSelection = enabled
		if State.Axis then
			State.Axis:ClearAxis()
			if not enabled and State.Axis:GetSelectedBone() then
				State.Axis:RefreshAxis()
			end
		end

		if State.Rig then
			for _, rig in State.getAllRigs() do
				State.Rig:LockRigLimbs(rig, not enabled)
			end
		end

		updatePluginState()
		if enabled and selectTool then
			plugin:SelectRibbonTool(Enum.RibbonTool.Select, UDim2.new())
		end
	end

	local input = require("UserInputService")
	input.InputBegan:Connect(function(event)
		if
			State.WorkspaceSelection
			and event.UserInputType == Enum.UserInputType.MouseButton1
			and input.pointerOverUI()
		then
			State.setWorkspaceSelection(false, false, true)
		end
	end)
	plugin.Deactivation:Connect(function()
		if activeLock and PluginActiveBool.Value then
			State.setWorkspaceSelection(true)
		end
	end)

	updatePluginState()
end

PluginShell.attach = attach

return PluginShell
