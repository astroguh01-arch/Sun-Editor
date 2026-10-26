--!nocheck


local assets = {}

for _, group in {
	script.SunEffectCatalogSingularColors,
	script.SunEffectCatalogLighting,
	script.SunEffectCatalogDoubleColors,
	script.SunEffectCatalogMisc,
} do
	for _, asset in require(group) do
		table.insert(assets, asset)
	end
end

return assets
