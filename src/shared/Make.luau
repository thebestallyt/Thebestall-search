-- Make("Part", { Name = "X", Size = ..., Parent = workspace }, { kinder... })
-- Erstellt eine Instance, setzt Eigenschaften und haengt Kinder an.
-- "Parent" wird immer zuletzt gesetzt (schneller und sicherer).

local function Make(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst: any = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				inst[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

return Make
