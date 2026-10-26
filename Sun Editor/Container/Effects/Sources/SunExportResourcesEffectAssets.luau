--!nocheck


local catalog = script.Parent.Parent.EffectCatalog
local parts = { "return function(require)\nreturn {\n" }

for _, group in {
	catalog.SunEffectCatalogSingularColors,
	catalog.SunEffectCatalogLighting,
	catalog.SunEffectCatalogDoubleColors,
	catalog.SunEffectCatalogMisc,
} do
	local records = group:GetChildren()
	table.sort(records, function(a, b)
		return a.Name < b.Name
	end)
	for _, record in records do
		local source = record.Source
		local body = source:match("^%-%-!nocheck%s+return%s+([%s%S]+)$")
		assert(body, "Invalid bundled effect record: " .. record:GetFullName())
		table.insert(parts, body:gsub("%s+$", "") .. ",\n")
	end
end

table.insert(parts, "}\nend\n")
return table.concat(parts)
