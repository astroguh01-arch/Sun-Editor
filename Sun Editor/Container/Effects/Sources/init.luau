--!nocheck


local require = require(script:FindFirstAncestor("Container").Require)

local function source(module)
	local text = module.Source
	local start = text:find("return function(require)", 1, true)
	assert(start, "Unexpected export module shape: " .. module.Name)
	return text:sub(start)
end

local sources = {
	["Helpers/CameraProjection"] = source(script.SunExportHelpersCameraProjection),
	["Helpers/SunVFX"] = source(script.SunExportHelpersSunVFX),
	["Helpers/SunVFXLegacy"] = source(script.SunExportHelpersSunVFXLegacy),
	["Helpers/EffectLayer"] = source(script.SunExportHelpersEffectLayer),
	["Helpers/EffectObjects"] = source(script.SunExportHelpersEffectObjects),
	["Helpers/EffectVFXSurface"] = source(script.SunExportHelpersEffectVFXSurface),
	["Helpers/EmitData"] = source(script.SunExportHelpersEmitData),
	["Helpers/SubtitleData"] = source(script.SunExportHelpersSubtitleData),
	["Resources/EffectAssets"] = require(script.SunExportResourcesEffectAssets),
	["Runtime/Geometry"] = source(script.SunExportRuntimeGeometry),
	["Runtime/Letterbox"] = source(script.SunExportRuntimeLetterbox),
	["Runtime/Player"] = source(script.SunExportRuntimePlayer),
	["Runtime/Cutscene"] = source(script.SunExportRuntimeCutscene),
	["Runtime/Preload"] = source(script.SunExportRuntimePreload),
	["Subsystems/EventCleanup"] = source(script.SunExportSubsystemsEventCleanup),
	["Subsystems/EventClock"] = source(script.SunExportSubsystemsEventClock),
	["Subsystems/EventFlipbook"] = source(script.SunExportSubsystemsEventFlipbook),
	["Subsystems/EventOrientation"] = source(script.SunExportSubsystemsEventOrientation),
	["Subsystems/EventParticles"] = source(script.SunExportSubsystemsEventParticles),
	["Subsystems/SubtitleRenderer"] = source(script.SunExportSubsystemsSubtitleRenderer),
}

for _, name in { "SunRGB", "SunOklab", "SunPromise", "SunShake", "SunDrawing" } do
	local library = script:FindFirstAncestor("Container").Shared[name]
	sources["Shared/" .. name] = "return function(require)\n" .. library.Source .. "\nend\n"
end

return sources
