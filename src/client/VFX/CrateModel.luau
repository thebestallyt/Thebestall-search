-- Baut eine 3D-Kiste aus Teilen (fuer die Oeffnungs-Buehne und die Shop-Vorschau).
-- Die Neon-Kanten koennen live umgefaerbt werden (Seltenheits-Upgrades!).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Make = require(Shared:WaitForChild("Make"))

local CrateModel = {}
CrateModel.__index = CrateModel

export type Entry = { part: BasePart, offset: CFrame, kind: string }

local GOLD = Color3.fromRGB(255, 200, 70)

local function newPart(parent: Instance, size: Vector3, color: Color3, material: EnumItem, kind: string, list: { Entry }, offset: CFrame): BasePart
	local p = Make("Part", {
		Size = size,
		Color = color,
		Material = material,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = kind == "body" or kind == "lid",
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		Parent = parent,
	})
	table.insert(list, { part = p, offset = offset, kind = kind })
	return p
end

-- crateDef: Eintrag aus Shared/Crates
function CrateModel.Build(crateDef: any, parent: Instance, scale: number?)
	local s = scale or 1
	local model = Make("Model", { Name = "Crate_" .. tostring(crateDef.Id) })
	local list: { Entry } = {}
	local trim: Color3 = crateDef.TrimColor
	local body: Color3 = crateDef.BodyColor
	local mat = crateDef.Material
	local neon = Enum.Material.Neon

	local function add(size: Vector3, offset: CFrame, color: Color3, material: EnumItem, kind: string): BasePart
		return newPart(model, size * s, color, material, kind, list, CFrame.new(offset.Position * s) * offset.Rotation)
	end

	add(Vector3.new(4, 3, 3), CFrame.new(0, 1.5, 0), body, mat, "body")
	-- Kanten
	for _, x in { -1.92, 1.92 } do
		for _, z in { -1.42, 1.42 } do
			add(Vector3.new(0.34, 3.06, 0.34), CFrame.new(x, 1.5, z), trim, neon, "trim")
		end
	end
	for _, y in { 0.16, 2.84 } do
		add(Vector3.new(4.06, 0.3, 0.3), CFrame.new(0, y, -1.42), trim, neon, "trim")
		add(Vector3.new(4.06, 0.3, 0.3), CFrame.new(0, y, 1.42), trim, neon, "trim")
		add(Vector3.new(0.3, 0.3, 3.06), CFrame.new(-1.92, y, 0), trim, neon, "trim")
		add(Vector3.new(0.3, 0.3, 3.06), CFrame.new(1.92, y, 0), trim, neon, "trim")
	end
	add(Vector3.new(0.26, 2.1, 0.08), CFrame.new(-0.9, 1.5, -1.53), trim, neon, "trim")
	add(Vector3.new(0.26, 2.1, 0.08), CFrame.new(0.9, 1.5, -1.53), trim, neon, "trim")
	-- Schloss
	add(Vector3.new(0.95, 1.05, 0.18), CFrame.new(0, 2.35, -1.58), GOLD, Enum.Material.Metal, "lock")
	add(Vector3.new(0.24, 0.42, 0.08), CFrame.new(0, 2.3, -1.68), trim, neon, "trim")
	-- Deckel
	add(Vector3.new(4.3, 0.9, 3.3), CFrame.new(0, 3.45, 0), body:Lerp(Color3.new(1, 1, 1), 0.06), mat, "lid")
	add(Vector3.new(4.34, 0.24, 0.16), CFrame.new(0, 3.45, -1.66), trim, neon, "lidtrim")
	add(Vector3.new(4.34, 0.24, 0.16), CFrame.new(0, 3.45, 1.66), trim, neon, "lidtrim")
	add(Vector3.new(0.16, 0.24, 3.34), CFrame.new(-2.16, 3.45, 0), trim, neon, "lidtrim")
	add(Vector3.new(0.16, 0.24, 3.34), CFrame.new(2.16, 3.45, 0), trim, neon, "lidtrim")
	add(Vector3.new(0.28, 0.1, 1.9), CFrame.new(0, 3.92, 0) * CFrame.Angles(0, math.rad(45), 0), trim, neon, "lidtrim")
	add(Vector3.new(0.28, 0.1, 1.9), CFrame.new(0, 3.92, 0) * CFrame.Angles(0, math.rad(-45), 0), trim, neon, "lidtrim")
	add(Vector3.new(0.7, 0.12, 0.7), CFrame.new(0, 3.95, 0) * CFrame.Angles(0, math.rad(45), 0), GOLD, neon, "lidtrim")

	local core = list[1].part
	local light = Make("PointLight", { Color = trim, Range = 14 * s, Brightness = 2.5, Shadows = false, Parent = core })

	model.PrimaryPart = core
	model.Parent = parent

	local self = setmetatable({
		Model = model,
		Entries = list,
		Light = light,
		Scale = s,
		Base = CFrame.new(),
		LidTransform = CFrame.new(),
		Cracks = {} :: { Entry },
	}, CrateModel)
	return self
end

-- Positioniert die ganze Kiste (Base = Unterseite Mitte)
function CrateModel:SetCFrame(cf: CFrame)
	self.Base = cf
	local lidT = self.LidTransform
	for _, e in self.Entries do
		if e.kind == "lid" or e.kind == "lidtrim" then
			e.part.CFrame = cf * lidT * e.offset
		else
			e.part.CFrame = cf * e.offset
		end
	end
	for _, e in self.Cracks do
		e.part.CFrame = cf * e.offset
	end
end

-- Faerbt alle Neon-Kanten um
function CrateModel:SetTrim(color: Color3, time: number?)
	local info = TweenInfo.new(time or 0.25, Enum.EasingStyle.Quad)
	for _, e in self.Entries do
		if e.kind == "trim" or e.kind == "lidtrim" then
			if time and time > 0 then
				TweenService:Create(e.part, info, { Color = color }):Play()
			else
				e.part.Color = color
			end
		end
	end
	for _, e in self.Cracks do
		TweenService:Create(e.part, info, { Color = color }):Play()
	end
	TweenService:Create(self.Light, info, { Color = color }):Play()
end

-- Leuchtender Riss auf der Vorderseite
function CrateModel:AddCrack(color: Color3)
	local s = self.Scale
	local x = (math.random() - 0.5) * 2.6
	local y = 0.6 + math.random() * 1.8
	local len = 0.8 + math.random() * 1.2
	local p = Make("Part", {
		Size = Vector3.new(0.12, len, 0.06) * s,
		Color = color,
		Material = Enum.Material.Neon,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = self.Model,
	})
	local offset = CFrame.new(x * s, y * s, -1.53 * s) * CFrame.Angles(0, 0, math.rad(math.random(-60, 60)))
	table.insert(self.Cracks, { part = p, offset = offset, kind = "crack" })
	p.CFrame = self.Base * offset
end

function CrateModel:LidParts(): { BasePart }
	local out = {}
	for _, e in self.Entries do
		if e.kind == "lid" or e.kind == "lidtrim" then
			table.insert(out, e.part)
		end
	end
	return out
end

function CrateModel:Destroy()
	self.Model:Destroy()
end

return CrateModel
