-- Baut eine Fantasy-Schatztruhe aus Teilen (fuer die Oeffnungs-Buehne und die Shop-Vorschau).
-- Aufbau: Holzkorpus mit Metallbaendern und Eckbeschlaegen, runder Bretter-Deckel (mit
-- Seitenteilen aus Keilen, damit er beim Aufklappen hohl aussieht), grosses Schloss mit
-- Edelstein, Griffe an den Seiten und ein schmaler Lichtspalt unter dem Deckel.
-- Edelstein, Lichtspalt, Innenleuchten und PointLight nehmen live die aktuelle
-- Seltenheitsfarbe an (SetTrim). Vorderseite der Truhe = -Z (LookVector).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Make = require(Shared:WaitForChild("Make"))

local CrateModel = {}
CrateModel.__index = CrateModel

export type Entry = { part: BasePart, offset: CFrame, kind: string, lid: boolean }

export type ChestTheme = {
	Wood: Color3,
	LidWood: Color3,
	Metal: Color3,
	MetalDark: Color3,
	Accent: Color3,
	Gem: Color3,
}

local C = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)

-- Masse bei scale = 1 (Studs) ------------------------------------------------------
local W = 4.0 -- Breite (X)
local D = 2.8 -- Tiefe (Z)
local FEET = 0.2 -- Hoehe der Fuesse
local BODY_H = 2.0 -- Korpushoehe
local Y0 = FEET -- Unterkante Korpus
local YT = FEET + BODY_H -- Oberkante Korpus
local GAP = 0.06 -- Lichtspalt zwischen Korpus und Deckel
local YS = YT + GAP -- Deckelfuge
local R = D / 2 -- Deckelradius
local N = 5 -- Bretter im Deckel
local HALF = math.pi / (2 * N)
local PLANK_T = 0.22
local LID_LEN = W + 0.06
local TRAY = 0.26 -- Tiefe des Innenraums
local STRAP_X = 1.15 -- Position der Metallbaender

CrateModel.Width = W
CrateModel.Depth = D
CrateModel.Height = YS + R + 0.08

-- Farb-Themen ---------------------------------------------------------------------

local WOODS = {
	Oak = C(178, 122, 72),
	Honey = C(152, 98, 56),
	Walnut = C(106, 68, 48),
	Ebony = C(64, 44, 46),
}

local METALS = {
	Iron = { Metal = C(86, 90, 100), Dark = C(50, 52, 60), Accent = C(214, 162, 72) },
	Steel = { Metal = C(162, 170, 186), Dark = C(94, 100, 114), Accent = C(232, 192, 98) },
	Gold = { Metal = C(236, 180, 64), Dark = C(150, 98, 26), Accent = C(255, 222, 132) },
}

local PRESETS: { [string]: { Wood: string, Metal: string, Gem: Color3 } } = {
	Starter = { Wood = "Oak", Metal = "Iron", Gem = C(74, 212, 118) }, -- Smaragd
	Basic = { Wood = "Honey", Metal = "Iron", Gem = C(70, 150, 255) }, -- Saphir
	Premium = { Wood = "Walnut", Metal = "Steel", Gem = C(178, 98, 255) }, -- Amethyst
	Cosmic = { Wood = "Ebony", Metal = "Gold", Gem = C(255, 70, 100) }, -- Rubin
}

-- Liefert Holz/Metall/Edelstein fuer eine Kiste (auch fuer die Shop-Karten benutzt)
function CrateModel.ThemeFor(crateDef: any): ChestTheme
	local id = tostring(crateDef and crateDef.Id or "")
	local preset = PRESETS[id]
	local price = tonumber(crateDef and crateDef.Price) or 0
	local woodName = if preset then preset.Wood elseif price >= 900 then "Ebony" elseif price >= 300 then "Walnut" else "Honey"
	local metalName = if preset then preset.Metal elseif price >= 900 then "Gold" elseif price >= 300 then "Steel" else "Iron"
	local gem: Color3 = if preset then preset.Gem
		elseif crateDef and typeof(crateDef.TrimColor) == "Color3" then crateDef.TrimColor
		else C(70, 150, 255)
	local wood = WOODS[woodName]
	-- BodyColor der Kiste nur als leichte Toenung des Holzes
	if crateDef and typeof(crateDef.BodyColor) == "Color3" then
		wood = wood:Lerp(crateDef.BodyColor, 0.16)
	end
	local metal = METALS[metalName]
	return {
		Wood = wood,
		LidWood = wood:Lerp(WHITE, 0.06),
		Metal = metal.Metal,
		MetalDark = metal.Dark,
		Accent = metal.Accent,
		Gem = gem,
	}
end

-- Bau ----------------------------------------------------------------------------

-- crateDef: Eintrag aus Shared/Crates. Ist parent ein ViewportFrame, wird eine
-- schlankere Version ohne Innenraum gebaut (der Deckel geht dort nie auf).
function CrateModel.Build(crateDef: any, parent: Instance, scale: number?)
	local s = scale or 1
	local theme = CrateModel.ThemeFor(crateDef)
	local simple = parent:IsA("ViewportFrame") or parent:FindFirstAncestorWhichIsA("ViewportFrame") ~= nil
	local model = Make("Model", { Name = "Chest_" .. tostring(crateDef and crateDef.Id or "?") })
	local list: { Entry } = {}

	local WP = Enum.Material.WoodPlanks
	local WD = Enum.Material.Wood
	local MT = Enum.Material.Metal
	local NEON = Enum.Material.Neon
	local wood, lidWood = theme.Wood, theme.LidWood
	local metal, dark, accent = theme.Metal, theme.MetalDark, theme.Accent

	local function add(className: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, kind: string, props: { [string]: any }?): BasePart
		local p = Instance.new(className) :: BasePart
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = (kind == "wood" or kind == "lid" or kind == "metal") and size.Magnitude > 1.2
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Color = color
		p.Material = material
		if props then
			-- Shape zuerst, damit die Groesse danach nicht verfaelscht wird
			if props.Shape and p:IsA("Part") then
				(p :: Part).Shape = props.Shape
			end
			for k, v in props do
				if k ~= "Shape" then
					(p :: any)[k] = v
				end
			end
		end
		p.Size = size * s
		p.Parent = model
		local isLid = string.sub(kind, 1, 3) == "lid"
		table.insert(list, { part = p, offset = CFrame.new(offset.Position * s) * offset.Rotation, kind = kind, lid = isLid })
		return p
	end

	-- Fuesse -------------------------------------------------------------------
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			add("Part", Vector3.new(0.5, FEET + 0.05, 0.5), CFrame.new(x * (W / 2 - 0.28), (FEET + 0.05) / 2, z * (D / 2 - 0.28)), dark, MT, "metal")
		end
	end

	-- Korpus -------------------------------------------------------------------
	local core: BasePart
	if simple then
		core = add("Part", Vector3.new(W, BODY_H, D), CFrame.new(0, Y0 + BODY_H / 2, 0), wood, WP, "wood")
	else
		-- unten massiv, oben eine flache Wanne (Innenraum, sichtbar wenn offen)
		local coreH = BODY_H - TRAY
		core = add("Part", Vector3.new(W, coreH, D), CFrame.new(0, Y0 + coreH / 2, 0), wood, WP, "wood")
		local wallT = 0.22
		local wy = YT - TRAY / 2
		add("Part", Vector3.new(W, TRAY, wallT), CFrame.new(0, wy, -(D / 2 - wallT / 2)), wood, WP, "wood")
		add("Part", Vector3.new(W, TRAY, wallT), CFrame.new(0, wy, D / 2 - wallT / 2), wood, WP, "wood")
		add("Part", Vector3.new(wallT, TRAY, D - wallT * 2), CFrame.new(-(W / 2 - wallT / 2), wy, 0), wood, WP, "wood")
		add("Part", Vector3.new(wallT, TRAY, D - wallT * 2), CFrame.new(W / 2 - wallT / 2, wy, 0), wood, WP, "wood")
		-- Innenleuchten (Licht von innen)
		add(
			"Part",
			Vector3.new(W - wallT * 2, 0.04, D - wallT * 2),
			CFrame.new(0, YT - TRAY + 0.03, 0),
			theme.Gem,
			NEON,
			"inner",
			{ Transparency = 0.4, CastShadow = false }
		)
		-- ein paar Goldmuenzen im Inneren
		local coinSpots = { { -0.9, 0.3, 12 }, { -0.35, -0.4, -8 }, { 0.5, 0.25, 18 }, { 1.05, -0.3, -14 } }
		for i, c in coinSpots do
			add(
				"Part",
				Vector3.new(0.08, 0.5, 0.5),
				CFrame.new(c[1], YT - TRAY + 0.1 + (i % 2) * 0.04, c[2]) * CFrame.Angles(math.rad(c[3]), 0, math.rad(90)),
				C(255, 200, 70),
				MT,
				"treasure",
				{ Shape = Enum.PartType.Cylinder, CastShadow = false }
			)
		end
	end

	-- Metall: Bodenband, Oberkante, Eckbeschlaege, Baender --------------------
	add("Part", Vector3.new(W + 0.1, 0.24, D + 0.1), CFrame.new(0, Y0 + 0.12, 0), metal, MT, "metal")
	local rimH = 0.18
	local rimY = YT - rimH / 2
	add("Part", Vector3.new(W + 0.1, rimH, 0.1), CFrame.new(0, rimY, -D / 2), metal, MT, "metal")
	add("Part", Vector3.new(W + 0.1, rimH, 0.1), CFrame.new(0, rimY, D / 2), metal, MT, "metal")
	add("Part", Vector3.new(0.1, rimH, D + 0.1), CFrame.new(-W / 2, rimY, 0), metal, MT, "metal")
	add("Part", Vector3.new(0.1, rimH, D + 0.1), CFrame.new(W / 2, rimY, 0), metal, MT, "metal")
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			add("Part", Vector3.new(0.36, BODY_H + 0.02, 0.36), CFrame.new(x * (W / 2 - 0.13), Y0 + BODY_H / 2, z * (D / 2 - 0.13)), metal, MT, "metal")
		end
		-- senkrechte Baender vorne und hinten
		add("Part", Vector3.new(0.34, BODY_H - 0.02, 0.1), CFrame.new(x * STRAP_X, Y0 + BODY_H / 2, -D / 2), metal, MT, "metal")
		add("Part", Vector3.new(0.34, BODY_H - 0.02, 0.1), CFrame.new(x * STRAP_X, Y0 + BODY_H / 2, D / 2), metal, MT, "metal")
	end
	-- Nieten vorne
	local rivetColor = metal:Lerp(WHITE, 0.25)
	for _, x in { -STRAP_X, STRAP_X } do
		for _, y in { Y0 + 0.62, Y0 + 1.22 } do
			add("Part", Vector3.new(0.14, 0.14, 0.14), CFrame.new(x, y, -(D / 2 + 0.06)), rivetColor, MT, "metal", { Shape = Enum.PartType.Ball })
		end
	end
	for _, x in { -1, 1 } do
		add("Part", Vector3.new(0.14, 0.14, 0.14), CFrame.new(x * (W / 2 - 0.13), Y0 + 0.9, -(D / 2 + 0.06)), rivetColor, MT, "metal", { Shape = Enum.PartType.Ball })
	end

	-- Schloss mit Edelstein ------------------------------------------------------
	local lockY = YT - 0.66
	add("Part", Vector3.new(1.22, 1.06, 0.1), CFrame.new(0, lockY, -(D / 2 + 0.05)), dark, MT, "metal")
	add("Part", Vector3.new(1.0, 0.86, 0.08), CFrame.new(0, lockY, -(D / 2 + 0.12)), accent, MT, "metal")
	local gemY = lockY - 0.02
	local diamond = CFrame.Angles(0, 0, math.rad(45))
	add("Part", Vector3.new(0.66, 0.66, 0.08), CFrame.new(0, gemY, -(D / 2 + 0.19)) * diamond, dark, MT, "metal")
	local gem = add(
		"Part",
		Vector3.new(0.46, 0.46, 0.16),
		CFrame.new(0, gemY, -(D / 2 + 0.25)) * diamond,
		theme.Gem,
		Enum.Material.Glass,
		"gem",
		{ Transparency = 0.15, Reflectance = 0.12, CastShadow = false }
	)
	add("Part", Vector3.new(0.22, 0.22, 0.1), CFrame.new(0, gemY, -(D / 2 + 0.27)) * diamond, theme.Gem:Lerp(WHITE, 0.5), NEON, "gemcore", {
		CastShadow = false,
	})

	-- Griffe an den Seiten -------------------------------------------------------
	for _, x in { -1, 1 } do
		local hy = Y0 + BODY_H * 0.6
		add("Part", Vector3.new(0.06, 0.44, 0.92), CFrame.new(x * (W / 2 + 0.06), hy, 0), dark, MT, "metal")
		add("Part", Vector3.new(0.16, 0.13, 0.8), CFrame.new(x * (W / 2 + 0.16), hy - 0.12, 0), metal, MT, "metal")
	end

	-- Lichtspalt unter dem Deckel ---------------------------------------------------
	local gy = YT + GAP / 2
	local gh = GAP + 0.01
	local glowColor = theme.Gem:Lerp(WHITE, 0.25)
	local glowProps = { Transparency = 0.45, CastShadow = false }
	add("Part", Vector3.new(W - 0.2, gh, 0.08), CFrame.new(0, gy, -(D / 2 - 0.02)), glowColor, NEON, "glow", table.clone(glowProps))
	add("Part", Vector3.new(W - 0.2, gh, 0.08), CFrame.new(0, gy, D / 2 - 0.02), glowColor, NEON, "glow", table.clone(glowProps))
	add("Part", Vector3.new(0.08, gh, D - 0.2), CFrame.new(-(W / 2 - 0.02), gy, 0), glowColor, NEON, "glow", table.clone(glowProps))
	add("Part", Vector3.new(0.08, gh, D - 0.2), CFrame.new(W / 2 - 0.02, gy, 0), glowColor, NEON, "glow", table.clone(glowProps))

	-- Deckel: Bretter im Halbkreis ------------------------------------------------
	local plankW = 2 * R * math.tan(HALF) + 0.02
	local plankR = R - PLANK_T / 2
	for i = 1, N do
		local phi = (i - 0.5) * math.pi / N
		local tint = if i % 2 == 0 then Color3.new(0, 0, 0) else WHITE
		add(
			"Part",
			Vector3.new(LID_LEN, PLANK_T, plankW),
			CFrame.new(0, YS + plankR * math.sin(phi), -plankR * math.cos(phi)) * CFrame.Angles(phi - math.pi / 2, 0, 0),
			lidWood:Lerp(tint, 0.05),
			WD,
			"lid"
		)
	end
	-- Seitenteile als Faecher aus Keilen (exakte Halbkreis-Vielecke, innen hohl)
	local capColor = lidWood:Lerp(Color3.new(0, 0, 0), 0.12)
	local fanA = R - 0.04 -- Abstand Mitte -> Sehnenmitte
	local fanH = fanA * math.tan(HALF) -- halbe Sehne
	for _, side in { -1, 1 } do
		local x = side * (LID_LEN / 2 - 0.07)
		local center = Vector3.new(x, YS, 0)
		for i = 1, N do
			local phim = (i - 0.5) * math.pi / N
			local ur = Vector3.new(0, math.sin(phim), -math.cos(phim)) -- nach aussen
			local tang = Vector3.new(0, math.cos(phim), math.sin(phim))
			local m = center + ur * fanA
			for _, dir in { tang, -tang } do
				-- rechter Winkel bei m: lokal +Y entlang der Sehne, lokal -Z zur Mitte
				local yAxis = dir
				local zAxis = ur
				local xAxis = yAxis:Cross(zAxis)
				local pos = m + yAxis * (fanH / 2) - zAxis * (fanA / 2)
				add("WedgePart", Vector3.new(0.14, fanH, fanA), CFrame.fromMatrix(pos, xAxis, yAxis, zAxis), capColor, WD, "lid")
			end
		end
	end
	-- Metallbaender ueber den Deckel
	local bandT = 0.08
	local bandW = 2 * (R + bandT) * math.tan(HALF) + 0.01
	local bandR = R + bandT / 2 - 0.005
	for _, x in { -STRAP_X, STRAP_X } do
		for i = 1, N do
			local phi = (i - 0.5) * math.pi / N
			add(
				"Part",
				Vector3.new(0.36, bandT, bandW),
				CFrame.new(x, YS + bandR * math.sin(phi), -bandR * math.cos(phi)) * CFrame.Angles(phi - math.pi / 2, 0, 0),
				metal,
				MT,
				"lidmetal"
			)
		end
	end
	-- Vorderkante des Deckels + Ueberfalle (haengt ueber das Schloss)
	local edgeZ = R / math.cos(HALF) - 0.03
	add("Part", Vector3.new(LID_LEN + 0.04, 0.14, 0.1), CFrame.new(0, YS + 0.07, -edgeZ), metal, MT, "lidmetal")
	add("Part", Vector3.new(0.46, 0.2, 0.26), CFrame.new(0, YS + 0.06, -(D / 2 + 0.1)), dark, MT, "lidmetal")
	add("Part", Vector3.new(0.34, 0.46, 0.08), CFrame.new(0, YS - 0.18, -(D / 2 + 0.22)), accent, MT, "lidmetal")

	-- Licht im Inneren
	local light = Make("PointLight", {
		Color = theme.Gem,
		Range = 11 * s,
		Brightness = 1,
		Shadows = false,
		Parent = core,
	})

	model.PrimaryPart = core
	model.Parent = parent

	local self = setmetatable({
		Model = model,
		Entries = list,
		Light = light,
		Core = core,
		Gem = gem,
		Theme = theme,
		Scale = s,
		Base = CFrame.new(),
		LidTransform = CFrame.new(),
		-- Scharnier hinten an der Deckelfuge (Drehachse = X)
		LidHinge = CFrame.new(0, YS * s, R * s),
		Cracks = {} :: { Entry },
		TrimColor = theme.Gem,
		GlowLevel = 0,
		_rng = Random.new(),
	}, CrateModel)
	self:SetCFrame(CFrame.new())
	return self
end

-- Positioniert die ganze Truhe (cf = Unterseite Mitte). Deckelteile bekommen zusaetzlich LidTransform.
function CrateModel:SetCFrame(cf: CFrame)
	self.Base = cf
	local lidCf = cf * self.LidTransform
	for _, e in self.Entries do
		e.part.CFrame = (if e.lid then lidCf else cf) * e.offset
	end
	for _, e in self.Cracks do
		e.part.CFrame = cf * e.offset
	end
end

-- Deckel um das hintere Scharnier aufklappen (Winkel in Radiant, positiv = auf)
function CrateModel:SetLidAngle(angle: number)
	local hinge: CFrame = self.LidHinge
	self.LidTransform = hinge * CFrame.Angles(angle, 0, 0) * hinge:Inverse()
	self:SetCFrame(self.Base)
end

-- Weltposition relativ zur Truhe (x, y, z in Truhen-Studs bei scale 1; -z = vorne)
function CrateModel:PointAt(x: number, y: number, z: number): Vector3
	local s: number = self.Scale
	return (self.Base * CFrame.new(x * s, y * s, z * s)).Position
end

function CrateModel:Center(): Vector3
	return self:PointAt(0, YT * 0.62, 0)
end

-- Mitte der Oeffnung (fuer Lichtsaeule, Funken)
function CrateModel:Top(): Vector3
	return self:PointAt(0, YT, 0)
end

local function setColor(part: BasePart, color: Color3, time: number)
	if time > 0 then
		TweenService:Create(part, TweenInfo.new(time, Enum.EasingStyle.Quad), { Color = color }):Play()
	else
		part.Color = color
	end
end

-- Faerbt Edelstein, Lichtspalt, Innenleuchten, Risse und Licht in der Seltenheitsfarbe
function CrateModel:SetTrim(color: Color3, time: number?)
	local t = time or 0
	self.TrimColor = color
	for _, e in self.Entries do
		local k = e.kind
		if k == "gem" then
			setColor(e.part, color, t)
		elseif k == "gemcore" then
			setColor(e.part, color:Lerp(WHITE, 0.5), t)
		elseif k == "glow" or k == "inner" then
			setColor(e.part, color:Lerp(WHITE, 0.25), t)
		end
	end
	for _, e in self.Cracks do
		setColor(e.part, color:Lerp(WHITE, 0.4), t)
	end
	local light: PointLight = self.Light
	if t > 0 then
		TweenService:Create(light, TweenInfo.new(t, Enum.EasingStyle.Quad), { Color = color }):Play()
	else
		light.Color = color
	end
end

-- Nur den Edelstein umfaerben (z.B. langsamer Farbwechsel bei GOETTLICH)
function CrateModel:SetGemColor(color: Color3)
	for _, e in self.Entries do
		if e.kind == "gem" then
			e.part.Color = color
		elseif e.kind == "gemcore" then
			e.part.Color = color:Lerp(WHITE, 0.5)
		end
	end
end

-- Wie stark Licht aus der Truhe dringt (0..1): Lichtspalt dicker/heller, Licht staerker
function CrateModel:SetGlow(level: number, time: number?)
	local l = math.clamp(level, 0, 1)
	local t = time or 0
	local s: number = self.Scale
	self.GlowLevel = l
	local info = TweenInfo.new(math.max(t, 0.01), Enum.EasingStyle.Quad)
	for _, e in self.Entries do
		if e.kind == "glow" then
			local size = e.part.Size
			local thick = (GAP + 0.01 + 0.07 * l) * s
			local goal = { Transparency = 0.45 - 0.42 * l, Size = Vector3.new(size.X, thick, size.Z) }
			if t > 0 then
				TweenService:Create(e.part, info, goal):Play()
			else
				e.part.Transparency = goal.Transparency
				e.part.Size = goal.Size
			end
		elseif e.kind == "inner" then
			e.part.Transparency = 0.4 - 0.3 * l
		end
	end
	local light: PointLight = self.Light
	local goal = { Brightness = 1 + 3 * l, Range = (11 + 9 * l) * s }
	if t > 0 then
		TweenService:Create(light, info, goal):Play()
	else
		light.Brightness = goal.Brightness
		light.Range = goal.Range
	end
end

-- Leuchtender Riss (Zickzack) auf der Vorderseite, Licht dringt durch
function CrateModel:AddCrack(color: Color3)
	local s: number = self.Scale
	local rng: Random = self._rng
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	-- nicht auf dem Schloss starten
	local x = side * rng:NextNumber(0.72, 1.7)
	local y = rng:NextNumber(Y0 + 0.4, YT - 0.4)
	local ang = rng:NextNumber(-math.pi, math.pi)
	local width = 0.1
	local segs = rng:NextInteger(2, 4)
	local crackColor = color:Lerp(WHITE, 0.4)
	for _ = 1, segs do
		local len = rng:NextNumber(0.22, 0.44)
		local nx = math.clamp(x + math.cos(ang) * len, -W / 2 + 0.22, W / 2 - 0.22)
		local ny = math.clamp(y + math.sin(ang) * len, Y0 + 0.28, YT - 0.22)
		local dx, dy = nx - x, ny - y
		local l = math.sqrt(dx * dx + dy * dy)
		if l > 0.05 then
			local p = Make("Part", {
				Size = Vector3.new(l + width, width, 0.03) * s,
				Color = crackColor,
				Material = Enum.Material.Neon,
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Parent = self.Model,
			})
			local offset = CFrame.new((x + nx) / 2 * s, (y + ny) / 2 * s, -(D / 2 + 0.012) * s) * CFrame.Angles(0, 0, math.atan2(dy, dx))
			table.insert(self.Cracks, { part = p, offset = offset, kind = "crack", lid = false })
			p.CFrame = self.Base * offset
		end
		x, y = nx, ny
		ang += rng:NextNumber(-0.95, 0.95)
		width = math.max(0.045, width * 0.72)
	end
end

function CrateModel:LidParts(): { BasePart }
	local out = {}
	for _, e in self.Entries do
		if e.lid then
			table.insert(out, e.part)
		end
	end
	return out
end

function CrateModel:Destroy()
	self.Model:Destroy()
	table.clear(self.Entries)
	table.clear(self.Cracks)
end

return CrateModel
