-- Baut die komplette Welt per Code: Licht, Terrain-Landschaft und alle Bauten.
-- * Ein sonniges Tal aus Terrain: Wiesen, sanfte Huegel, ein See mit Bach und ringsum
--   felsige Berge mit Schneekappen. Ueberall ist Boden - niemand faellt ins Leere.
-- * Lobby: gemuetliches Lager-Dorf mit Kisten-Altar, Black-Hole-Schrein, Trainingsplatz,
--   Lagerfeuer, Zelten, Marktstaenden und kleinen Fachwerkhaeusern.
-- * Arena: alte Steinruine (Kolosseum) im selben Tal, ca. 600 Studs von der Lobby entfernt.
-- * Baeume, Buesche, Felsen und Blumen werden mit festem Seed verteilt.
-- Alles ausser den Terrain-Voxeln (und den Wolken unter Terrain) liegt in workspace.Map.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Make = require(Shared:WaitForChild("Make"))
local Config = require(Shared:WaitForChild("Config"))

local WorldBuilder = {}

export type WorldInfo = {
	LobbySpawn: CFrame,
	ArenaSpawns: { CFrame },
	DummySpots: { CFrame },
	LobbyCenter: Vector3,
	ArenaCenter: Vector3,
	ArenaRadius: number,
}

local terrain = workspace.Terrain
local C = Color3.fromRGB
local M = Enum.Material
type Mat = typeof(Enum.Material.Grass)
local TAU = math.pi * 2
local SMOOTH = Enum.SurfaceType.Smooth
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- dreht die Zylinderachse (X) nach oben

local L: Vector3 = Config.World.LobbyCenter
local A: Vector3 = Config.World.ArenaCenter
local AR: number = Config.World.ArenaRadius
-- Talboden auf das Terrain-Raster (4 Studs) runden, damit die Wiese exakt flach ist
local GROUND = 4 * math.floor(L.Y / 4 + 0.5)

-- Das Tal ist eine Ellipse zwischen Lobby und Arena, ringsum Berge
local VC = Vector3.new((L.X + A.X) / 2, GROUND, (L.Z + A.Z) / 2)
local VX = 400
local VZ = math.abs(A.Z - L.Z) / 2 + 260

local rng = Random.new(20241)

local PAL = {
	Stone = C(158, 151, 139),
	StoneDark = C(120, 115, 107),
	StoneLight = C(190, 183, 168),
	Moss = C(98, 142, 62),
	Wood = C(126, 88, 56),
	WoodDark = C(88, 60, 40),
	WoodLight = C(168, 122, 78),
	Plank = C(152, 108, 68),
	Iron = C(64, 64, 70),
	Bronze = C(168, 122, 68),
	Gold = C(236, 182, 60),
	Straw = C(222, 188, 108),
	Canvas = C(234, 222, 196),
	Plaster = C(238, 230, 212),
	Roof = C(158, 76, 56),
	Obsidian = C(30, 26, 38),
	Bark = C(104, 74, 50),
	Ink = C(17, 19, 27),
}
local CLOTH = { C(184, 56, 50), C(48, 92, 164), C(230, 176, 60), C(62, 128, 80) }

-- Kanten-Layout der Keile (wird beim Start per Raycast geprueft)
local WEDGE_FLIP = false -- true, falls die hohe Kante eines WedgeParts bei -Z liegt
local APEX = Vector3.new(1, 0, -1) -- obere Ecke, an der die Spitze eines CornerWedgeParts liegt

-- =============================================================================
-- Allgemeine Bau-Helfer
-- =============================================================================

local function at(x: number, z: number, y: number?): Vector3
	return Vector3.new(L.X + x, GROUND + (y or 0), L.Z + z)
end

local function flatLook(from: Vector3, to: Vector3): CFrame
	return CFrame.lookAt(from, Vector3.new(to.X, from.Y, to.Z))
end

-- Verankertes Bauteil ohne Kollision (Kollision nur dort, wo man anstossen soll)
local function shape(className: string, parent: Instance, props: { [string]: any }): BasePart
	local p: BasePart = Make(className, {
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		TopSurface = SMOOTH,
		BottomSurface = SMOOTH,
		Material = M.SmoothPlastic,
	})
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function block(parent: Instance, props: { [string]: any }): Part
	return shape("Part", parent, props) :: Part
end

-- Stehender Zylinder: Unterseite bei "bottom"
local function pillar(parent: Instance, bottom: Vector3, height: number, diameter: number, props: { [string]: any }): Part
	local p = block(parent, props)
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(height, diameter, diameter)
	p.CFrame = CFrame.new(bottom + Vector3.new(0, height / 2, 0)) * UPRIGHT
	return p
end

-- Zylinder zwischen zwei Punkten (Aeste, Balken, Holzstaemme)
local function rod(parent: Instance, a: Vector3, b: Vector3, diameter: number, props: { [string]: any }): Part
	local p = block(parent, props)
	p.Shape = Enum.PartType.Cylinder
	local d = b - a
	p.Size = Vector3.new(math.max(d.Magnitude, 0.05), diameter, diameter)
	if Vector3.new(d.X, 0, d.Z).Magnitude < 0.01 then
		p.CFrame = CFrame.new((a + b) / 2) * UPRIGHT
	else
		-- lookAt richtet -Z auf b, danach liegt X (Zylinderachse) entlang der Strecke
		p.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
	end
	return p
end

local function ball(parent: Instance, center: Vector3, d: number, props: { [string]: any }): Part
	local p = block(parent, props)
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(d, d, d)
	p.CFrame = CFrame.new(center)
	return p
end

-- Keil: hohe senkrechte Seite bei lokal +Z, die Schraege faellt Richtung -Z ab
local function wedge(parent: Instance, cf: CFrame, size: Vector3, props: { [string]: any }): BasePart
	local p = shape("WedgePart", parent, props)
	p.Size = size
	p.CFrame = if WEDGE_FLIP then cf * CFrame.Angles(0, math.pi, 0) else cf
	return p
end

-- Vierseitige Pyramide aus 4 CornerWedgeParts (Spitze bei apexPos, Grundflaeche 2w x 2w)
local function pyramid(parent: Instance, apexPos: Vector3, w: number, h: number, yaw: number, props: { [string]: any })
	for k = 0, 3 do
		local p = shape("CornerWedgePart", parent, props)
		p.Size = Vector3.new(w, h, w)
		p.CFrame = CFrame.new(apexPos)
			* CFrame.Angles(0, yaw + k * math.pi / 2, 0)
			* CFrame.new(-APEX.X * w / 2, -h / 2, -APEX.Z * w / 2)
	end
end

local function pointLight(parent: Instance, color: Color3, range: number, brightness: number, flicker: boolean?): PointLight
	local l = Make("PointLight", {
		Color = color,
		Range = range,
		Brightness = brightness,
		Shadows = false,
		Parent = parent,
	})
	if flicker then
		CollectionService:AddTag(l, "Flicker")
	end
	return l
end

local function nsk(t: number, v: number): NumberSequenceKeypoint
	return NumberSequenceKeypoint.new(t, v)
end

-- Echtes Feuer: heller Kern -> Orange -> Dunkelrot, Glut und optional Rauch
local function addFire(holder: Instance, scale: number, smoke: boolean): Attachment
	local att = Make("Attachment", { Name = "Fire", Parent = holder })
	Make("ParticleEmitter", {
		Name = "Flames",
		Texture = "rbxasset://textures/particles/fire_main.dds",
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C(255, 246, 210)),
			ColorSequenceKeypoint.new(0.3, C(255, 176, 66)),
			ColorSequenceKeypoint.new(1, C(196, 58, 24)),
		}),
		LightEmission = 0.8,
		LightInfluence = 0,
		Size = NumberSequence.new({ nsk(0, 1.4 * scale), nsk(0.5, 1.05 * scale), nsk(1, 0.15 * scale) }),
		Transparency = NumberSequence.new({ nsk(0, 0.2), nsk(0.6, 0.45), nsk(1, 1) }),
		Lifetime = NumberRange.new(0.45, 0.8),
		Rate = 24,
		Speed = NumberRange.new(2.2 * scale, 4 * scale),
		SpreadAngle = Vector2.new(9, 9),
		Acceleration = Vector3.new(0, 2 * scale, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-40, 40),
		EmissionDirection = Enum.NormalId.Top,
		ZOffset = 0.2,
		Parent = att,
	})
	Make("ParticleEmitter", {
		Name = "Embers",
		Texture = "rbxasset://textures/particles/fire_sparks_main.dds",
		Color = ColorSequence.new(C(255, 214, 130), C(255, 112, 40)),
		LightEmission = 1,
		LightInfluence = 0,
		Size = NumberSequence.new({ nsk(0, 0.16 * scale), nsk(1, 0) }),
		Lifetime = NumberRange.new(1, 1.8),
		Rate = 5,
		Speed = NumberRange.new(3 * scale, 6 * scale),
		SpreadAngle = Vector2.new(28, 28),
		Acceleration = Vector3.new(0.8, 0.6, 0.3),
		EmissionDirection = Enum.NormalId.Top,
		Parent = att,
	})
	if smoke then
		Make("ParticleEmitter", {
			Name = "Smoke",
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Color = ColorSequence.new(C(74, 70, 68), C(156, 152, 148)),
			LightEmission = 0,
			LightInfluence = 1,
			Size = NumberSequence.new({ nsk(0, 1.2 * scale), nsk(1, 5.5 * scale) }),
			Transparency = NumberSequence.new({ nsk(0, 1), nsk(0.15, 0.72), nsk(1, 1) }),
			Lifetime = NumberRange.new(3, 5),
			Rate = 3,
			Speed = NumberRange.new(3, 4.5),
			SpreadAngle = Vector2.new(8, 8),
			Acceleration = Vector3.new(1.4, 0.5, 0.4),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-20, 20),
			EmissionDirection = Enum.NormalId.Top,
			Parent = att,
		})
	end
	pointLight(att, C(255, 164, 86), 16 * scale, 1.6, true)
	return att
end

-- Schwebendes Namensschild im Chunky-Stil (farbige Platte, dicke dunkle Kontur)
local function marker(adornee: BasePart, title: string, fill: Color3, lip: Color3, height: number)
	local width = #title * 16 + 40
	pcall(function()
		local size = TextService:GetTextSize(title, 26, Enum.Font.FredokaOne, Vector2.new(1000, 100))
		width = math.ceil(size.X) + 40
	end)
	local gui = Make("BillboardGui", {
		Name = "Marker",
		Size = UDim2.fromOffset(width + 8, 54),
		StudsOffsetWorldSpace = Vector3.new(0, height, 0),
		LightInfluence = 0,
		MaxDistance = 90,
		AlwaysOnTop = false,
		Parent = adornee,
	})
	local lipFrame = Make("Frame", {
		Name = "Lip",
		BackgroundColor3 = lip,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -8),
		Parent = gui,
	})
	Make("UICorner", { CornerRadius = UDim.new(0, 12), Parent = lipFrame })
	Make("UIStroke", { Color = PAL.Ink, Thickness = 3, LineJoinMode = Enum.LineJoinMode.Round, Parent = lipFrame })
	local face = Make("Frame", {
		Name = "Face",
		BackgroundColor3 = fill,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -6),
		Parent = lipFrame,
	})
	Make("UICorner", { CornerRadius = UDim.new(0, 12), Parent = face })
	Make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), C(214, 214, 214)), Parent = face })
	local label = Make("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = title,
		Font = Enum.Font.FredokaOne,
		TextSize = 26,
		TextColor3 = Color3.new(1, 1, 1),
		Parent = face,
	})
	Make("UIStroke", { Color = PAL.Ink, Thickness = 2.5, LineJoinMode = Enum.LineJoinMode.Round, Parent = label })
	return gui
end

-- Aufgemalte Schrift auf einem Holzschild
local function signText(board: BasePart, text: string, face: Enum.NormalId)
	local gui = Make("SurfaceGui", {
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 50,
		LightInfluence = 1,
		MaxDistance = 220,
		ClipsDescendants = true,
		Parent = board,
	})
	local label = Make("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = text,
		Font = Enum.Font.FredokaOne,
		TextScaled = true,
		TextColor3 = C(255, 240, 210),
		Parent = gui,
	})
	Make("UIPadding", {
		PaddingTop = UDim.new(0.16, 0),
		PaddingBottom = UDim.new(0.16, 0),
		PaddingLeft = UDim.new(0.06, 0),
		PaddingRight = UDim.new(0.06, 0),
		Parent = label,
	})
	Make("UIStroke", { Color = C(52, 32, 18), Thickness = 3, LineJoinMode = Enum.LineJoinMode.Round, Parent = label })
end

-- =============================================================================
-- Sperrzonen (hier wachsen keine Baeume / Huegel)
-- =============================================================================

type Zone = { x: number, z: number, r: number }
type Segment = { a: Vector2, b: Vector2, w: number }
local zones: { Zone } = {}
local segments: { Segment } = {}

local function addZone(pos: Vector3, r: number)
	table.insert(zones, { x = pos.X, z = pos.Z, r = r })
end

local function addPolyline(points: { Vector3 }, w: number)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		table.insert(segments, { a = Vector2.new(a.X, a.Z), b = Vector2.new(b.X, b.Z), w = w })
	end
end

local function distToSegment(p: Vector2, a: Vector2, b: Vector2): number
	local ab = b - a
	local len2 = ab:Dot(ab)
	local t = if len2 > 1e-6 then math.clamp((p - a):Dot(ab) / len2, 0, 1) else 0
	return (p - (a + ab * t)).Magnitude
end

local function nearSegment(x: number, z: number, margin: number): boolean
	local p = Vector2.new(x, z)
	for _, s in segments do
		if distToSegment(p, s.a, s.b) < s.w + margin then
			return true
		end
	end
	return false
end

local function blocked(x: number, z: number, margin: number): boolean
	for _, zn in zones do
		local dx, dz = x - zn.x, z - zn.z
		local r = zn.r + margin
		if dx * dx + dz * dz < r * r then
			return true
		end
	end
	local p = Vector2.new(x, z)
	for _, s in segments do
		if distToSegment(p, s.a, s.b) < s.w + margin then
			return true
		end
	end
	return false
end

-- 1 = Rand des Tals (dahinter beginnen die Berge)
local function valleyNorm(x: number, z: number): number
	local dx = (x - VC.X) / VX
	local dz = (z - VC.Z) / VZ
	return math.sqrt(dx * dx + dz * dz)
end

-- Bodenhoehe des Terrains an einer Stelle
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.FilterDescendantsInstances = { terrain }
groundParams.IgnoreWater = false

local function groundAt(x: number, z: number): (number, Mat, Vector3)
	local res = workspace:Raycast(Vector3.new(x, GROUND + 900, z), Vector3.new(0, -1200, 0), groundParams)
	if res then
		return res.Position.Y, res.Material, res.Normal
	end
	return GROUND, M.Grass, Vector3.yAxis
end

-- =============================================================================
-- Feste Orte (alles relativ zu Lobby / Arena)
-- =============================================================================

local SPAWN_POS = at(0, 22)
local SHRINE_POS = at(40, -28)
local TRAIN_POS = at(-50, -26)
local CAMP_POS = at(-46, 20)
local LAKE1 = at(-160, -240)
local LAKE2 = at(-198, -204)
local TOWER_POS = at(52, -300)
local RUINS = { at(-130, -430), at(140, -150), at(236, -470) }
local MENU_CAM = at(100, 118, 52)
local MENU_FOCUS = at(-12, -40, 6)

-- Hauptweg Lobby -> Arena (leicht geschwungen)
local MAIN_PATH: { Vector3 } = {}
do
	local startP = at(0, -33)
	local endP = Vector3.new(A.X, GROUND, A.Z + AR + 40)
	local bends = { 0, 6, 14, -6, -12, 4, 2, 0 }
	for i, off in bends do
		local t = (i - 1) / (#bends - 1)
		local p = startP:Lerp(endP, t)
		table.insert(MAIN_PATH, Vector3.new(p.X + off, GROUND, p.Z))
	end
end
local WEST_PATH = { at(-33, 2), at(-78, -4), at(-104, -70), at(-110, -150), at(-98, -228) }
local SHRINE_PATH = { at(26, -12), SHRINE_POS + Vector3.new(-6, 0, 4) }
local EAST_PATH = { at(33, 0), at(66, -3) }
local SOUTH_PATH = { at(8, 32), at(18, 60) }
local STREAM = { at(-372, -430), at(-320, -392), at(-268, -350), at(-232, -300), at(-205, -258) }

-- =============================================================================
-- Licht & Atmosphaere: sonniger Nachmittag
-- =============================================================================

local function setupLighting()
	Lighting.ClockTime = 14.6
	Lighting.GeographicLatitude = 38
	Lighting.Brightness = 2.6
	Lighting.Ambient = C(80, 84, 98)
	Lighting.OutdoorAmbient = C(134, 136, 148)
	Lighting.EnvironmentDiffuseScale = 0.55
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.ExposureCompensation = 0.1
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3
	Lighting.FogEnd = 100000

	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") or child:IsA("Clouds") then
			child:Destroy()
		end
	end

	Make("Atmosphere", {
		Density = 0.28,
		Offset = 0.2,
		Color = C(198, 216, 236),
		Decay = C(122, 150, 188),
		Glare = 0.25,
		Haze = 1.3,
		Parent = Lighting,
	})
	-- Standard-Himmel (blauer Himmel mit Sonne)
	Make("Sky", {
		StarCount = 3000,
		CelestialBodiesShown = true,
		SunAngularSize = 12,
		MoonAngularSize = 9,
		Parent = Lighting,
	})
	Make("BloomEffect", { Name = "NovaBloom", Intensity = 0.35, Size = 22, Threshold = 1.5, Parent = Lighting })
	Make("SunRaysEffect", { Name = "NovaSunRays", Intensity = 0.06, Spread = 0.55, Parent = Lighting })
	Make("ColorCorrectionEffect", {
		Name = "NovaColor",
		Brightness = 0.02,
		Contrast = 0.07,
		Saturation = 0.12,
		TintColor = C(255, 250, 242),
		Parent = Lighting,
	})

	-- Dynamische Wolken
	pcall(function()
		local old = terrain:FindFirstChildOfClass("Clouds")
		if old then
			old:Destroy()
		end
		Make("Clouds", { Cover = 0.5, Density = 0.55, Color = C(255, 255, 255), Parent = terrain })
	end)
end

local function setupTerrainLook()
	local colors: { [Mat]: Color3 } = {
		[M.Grass] = C(108, 168, 66),
		[M.LeafyGrass] = C(88, 146, 56),
		[M.Ground] = C(132, 102, 72),
		[M.Mud] = C(104, 80, 58),
		[M.Rock] = C(130, 128, 126),
		[M.Slate] = C(112, 112, 118),
		[M.Snow] = C(238, 243, 250),
		[M.Sand] = C(222, 204, 154),
		[M.Cobblestone] = C(160, 154, 142),
		[M.Basalt] = C(54, 50, 60),
	}
	for mat, col in colors do
		pcall(function()
			terrain:SetMaterialColor(mat, col)
		end)
	end
	terrain.WaterColor = C(46, 134, 154)
	terrain.WaterTransparency = 0.55
	terrain.WaterWaveSize = 0.12
	terrain.WaterWaveSpeed = 7
	terrain.WaterReflectance = 0.45
end

-- =============================================================================
-- Terrain
-- =============================================================================

local function safe(fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn("[WorldBuilder] " .. tostring(err))
	end
end

-- Oberste Bodenschicht einfaerben (Form bleibt gleich)
local function paintDisc(pos: Vector3, radius: number, material: Enum.Material, depth: number?)
	local d = depth or 4
	safe(function()
		terrain:FillCylinder(CFrame.new(pos.X, GROUND - d / 2, pos.Z), d, radius, material)
	end)
end

local function paintStrip(a: Vector3, b: Vector3, width: number, material: Enum.Material, depth: number?)
	local d = depth or 4
	local len = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Magnitude
	if len > 0.5 then
		local mid = (a + b) / 2
		safe(function()
			terrain:FillBlock(
				CFrame.lookAt(Vector3.new(mid.X, GROUND - d / 2, mid.Z), Vector3.new(b.X, GROUND - d / 2, b.Z)),
				Vector3.new(width, d, len),
				material
			)
		end)
	end
	paintDisc(b, width / 2, material, d)
end

local function paintPath(points: { Vector3 }, width: number, material: Enum.Material)
	paintDisc(points[1], width / 2, material)
	for i = 1, #points - 1 do
		paintStrip(points[i], points[i + 1], width, material)
	end
end

local function buildBaseGround()
	terrain:Clear()
	-- Riesige flache Wiese (in Kacheln, damit keine Fuellung zu gross wird)
	local sizeX, sizeZ = 2000, VZ * 2 + 1100
	for ix = 0, 1 do
		for iz = 0, 1 do
			local cx = VC.X - sizeX / 4 + ix * sizeX / 2
			local cz = VC.Z - sizeZ / 4 + iz * sizeZ / 2
			safe(function()
				terrain:FillBlock(CFrame.new(cx, GROUND - 12, cz), Vector3.new(sizeX / 2, 24, sizeZ / 2), M.Grass)
			end)
		end
	end
	-- Lobby-Boden
	paintDisc(at(0, 0), 33, M.Slate)
	paintDisc(at(0, 0), 30, M.Cobblestone)
	paintDisc(SHRINE_POS, 13, M.Basalt)
	paintDisc(CAMP_POS, 9, M.Ground)
	safe(function()
		terrain:FillBlock(CFrame.new(TRAIN_POS.X, GROUND - 2, TRAIN_POS.Z), Vector3.new(34, 4, 26), M.Ground)
	end)
	-- Arena-Umgebung: gepflasterter Ring, aussen festgetretene Erde
	paintDisc(A, AR + 40, M.Ground)
	paintDisc(A, AR + 24, M.Cobblestone)
end

-- Ein Berg aus gestapelten Kugeln: gruener Fuss, Felskoerper, Spitze, Schneekappe, Felsnadeln
local function mountain(x: number, z: number, W: number, H: number, foothill: boolean, snow: boolean)
	safe(function()
		if foothill then
			local rA = 1.1 * W
			terrain:FillBall(Vector3.new(x, GROUND + 0.3 * H - rA, z), rA, M.Grass)
		end
		local bx = x + rng:NextNumber(-0.1, 0.1) * W
		local bz = z + rng:NextNumber(-0.1, 0.1) * W
		local rB = if foothill then 0.62 * W else 0.75 * W
		local topB = if foothill then 0.7 * H else 0.62 * H
		terrain:FillBall(Vector3.new(bx, GROUND + topB - rB, bz), rB, M.Rock)
		local rC = 0.32 * W
		local cx = bx + rng:NextNumber(-0.08, 0.08) * W
		local cz = bz + rng:NextNumber(-0.08, 0.08) * W
		terrain:FillBall(Vector3.new(cx, GROUND + H - rC, cz), rC, M.Rock)
		-- zackige Felsplatten an den Flanken
		for _ = 1, 3 do
			local a = rng:NextNumber(0, TAU)
			local d = rng:NextNumber(0.5, 0.7) * W
			local hh = rng:NextNumber(0.3, 0.45) * H
			terrain:FillBlock(
				CFrame.new(bx + math.cos(a) * d, GROUND + hh * 0.3, bz + math.sin(a) * d)
					* CFrame.Angles(rng:NextNumber(-0.35, 0.35), rng:NextNumber(0, math.pi), rng:NextNumber(-0.35, 0.35)),
				Vector3.new(rng:NextNumber(0.15, 0.24) * W, hh, rng:NextNumber(0.12, 0.2) * W),
				if rng:NextNumber() > 0.5 then M.Slate else M.Rock
			)
		end
		if snow then
			terrain:FillBall(Vector3.new(cx, GROUND + H - rC * 0.7, cz), rC * 0.92, M.Snow)
		end
	end)
end

local function buildMountains()
	-- innerer Ring: umschliesst das Tal
	local inner = 22
	for i = 1, inner do
		local a = (i / inner) * TAU + rng:NextNumber(-0.06, 0.06)
		local d = rng:NextNumber(150, 195)
		local W = rng:NextNumber(115, 155)
		local H = rng:NextNumber(150, 245)
		mountain(VC.X + math.cos(a) * (VX + d), VC.Z + math.sin(a) * (VZ + d), W, H, true, H > 180)
		task.wait()
	end
	-- aeusserer Ring: hohe Gipfel im Dunst dahinter
	local outer = 15
	for i = 1, outer do
		local a = ((i + 0.5) / outer) * TAU + rng:NextNumber(-0.06, 0.06)
		local d = rng:NextNumber(370, 420)
		local W = rng:NextNumber(170, 210)
		local H = rng:NextNumber(270, 360)
		mountain(VC.X + math.cos(a) * (VX + d), VC.Z + math.sin(a) * (VZ + d), W, H, false, true)
		task.wait()
	end
end

local function buildMeadowPatches()
	-- dunklere Blattgras-Flecken und ein paar Erdstellen fuer eine lebendige Wiese
	for _ = 1, 28 do
		local x = VC.X + rng:NextNumber(-VX, VX)
		local z = VC.Z + rng:NextNumber(-VZ, VZ)
		local r = rng:NextNumber(18, 46)
		if valleyNorm(x, z) < 1 and not blocked(x, z, r * 0.5) then
			paintDisc(Vector3.new(x, GROUND, z), r, M.LeafyGrass)
		end
	end
	for _ = 1, 10 do
		local x = VC.X + rng:NextNumber(-VX, VX)
		local z = VC.Z + rng:NextNumber(-VZ, VZ)
		local r = rng:NextNumber(5, 10)
		if valleyNorm(x, z) < 0.95 and not blocked(x, z, r + 4) then
			paintDisc(Vector3.new(x, GROUND, z), r, M.Ground)
		end
	end
end

local function buildHills()
	local made, tries = 0, 0
	while made < 14 and tries < 500 do
		tries += 1
		local x = VC.X + rng:NextNumber(-VX, VX)
		local z = VC.Z + rng:NextNumber(-VZ, VZ)
		local R = rng:NextNumber(70, 120)
		local h = rng:NextNumber(8, 22)
		local foot = math.sqrt(R * R - (R - h) * (R - h))
		if valleyNorm(x, z) < 0.95 and not blocked(x, z, foot + 12) then
			safe(function()
				terrain:FillBall(Vector3.new(x, GROUND + h - R, z), R, M.Grass)
			end)
			made += 1
		end
	end
end

local function fillWater(minP: Vector3, maxP: Vector3, depth: number)
	safe(function()
		local region = Region3.new(
			Vector3.new(math.min(minP.X, maxP.X), GROUND - depth, math.min(minP.Z, maxP.Z)),
			Vector3.new(math.max(minP.X, maxP.X), GROUND - 4, math.max(minP.Z, maxP.Z))
		):ExpandToGrid(4)
		terrain:ReplaceMaterial(region, 4, M.Air, M.Water)
	end)
end

local function buildLake()
	-- 1) Sandiger Grund und Strand fuer See und Bach
	safe(function()
		terrain:FillCylinder(CFrame.new(LAKE1.X, GROUND - 10, LAKE1.Z), 20, 63, M.Sand)
		terrain:FillCylinder(CFrame.new(LAKE2.X, GROUND - 10, LAKE2.Z), 20, 50, M.Sand)
	end)
	for i = 1, #STREAM - 1 do
		paintStrip(STREAM[i], STREAM[i + 1], 15, M.Sand, 12)
	end
	paintDisc(STREAM[1], 7.5, M.Sand, 12)
	-- 2) Bachbett ausheben (vom Bergfuss bis in den See)
	for i = 1, #STREAM - 1 do
		local a, b = STREAM[i], STREAM[i + 1]
		local len = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Magnitude
		local mid = (a + b) / 2
		safe(function()
			terrain:FillBlock(
				CFrame.lookAt(Vector3.new(mid.X, GROUND - 4, mid.Z), Vector3.new(b.X, GROUND - 4, b.Z)),
				Vector3.new(9, 8, len),
				M.Air
			)
			terrain:FillCylinder(CFrame.new(a.X, GROUND - 4, a.Z), 8, 4.5, M.Air)
		end)
	end
	-- 3) Seemulden ausheben (nach dem Bach, damit kein Sand im See liegen bleibt)
	safe(function()
		terrain:FillBall(Vector3.new(LAKE1.X, GROUND + 120 - 14, LAKE1.Z), 120, M.Air)
		terrain:FillBall(Vector3.new(LAKE2.X, GROUND + 90 - 11, LAKE2.Z), 90, M.Air)
	end)
	-- 4) Wasser einfuellen (nur in die ausgehobenen Luftloecher unter der Wiese)
	for i = 1, #STREAM - 1 do
		local a, b = STREAM[i], STREAM[i + 1]
		fillWater(
			Vector3.new(math.min(a.X, b.X) - 8, 0, math.min(a.Z, b.Z) - 8),
			Vector3.new(math.max(a.X, b.X) + 8, 0, math.max(a.Z, b.Z) + 8),
			8
		)
	end
	fillWater(LAKE1 - Vector3.new(64, 0, 64), LAKE1 + Vector3.new(64, 0, 64), 16)
	fillWater(LAKE2 - Vector3.new(50, 0, 50), LAKE2 + Vector3.new(50, 0, 50), 16)
end

local function buildPaths()
	paintPath(MAIN_PATH, 10, M.Ground)
	paintPath(WEST_PATH, 7, M.Ground)
	paintPath(SHRINE_PATH, 7, M.Ground)
	paintPath(EAST_PATH, 7, M.Ground)
	paintPath(SOUTH_PATH, 6, M.Ground)
	-- ein paar matschige Stellen auf dem Hauptweg
	for i = 2, #MAIN_PATH - 1, 2 do
		local p = MAIN_PATH[i]
		paintDisc(p + Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-6, 6)), rng:NextNumber(2.5, 4), M.Mud)
	end
end

-- =============================================================================
-- Natur: Baeume, Buesche, Felsen, Blumen
-- =============================================================================

local function jitter(c: Color3, amount: number, r: Random): Color3
	local f = 1 + r:NextNumber(-amount, amount)
	return Color3.new(math.clamp(c.R * f, 0, 1), math.clamp(c.G * f, 0, 1), math.clamp(c.B * f, 0, 1))
end

-- Tanne: Low-Poly-Pyramiden, die nach oben kleiner werden und um 45 Grad gedreht sind
local function pine(parent: Instance, base: Vector3, scale: number, r: Random): Model
	local model = Make("Model", { Name = "Pine" })
	local trunkH = 4.5 * scale
	pillar(model, base - Vector3.new(0, 1, 0), trunkH + 3, 1.5 * scale, {
		Name = "Trunk",
		Material = M.Wood,
		Color = jitter(C(96, 66, 44), 0.08, r),
		CanCollide = true,
	})
	local crown = Make("Model", { Name = "Crown", Parent = model })
	local green = C(44 + r:NextInteger(-6, 6), 98 + r:NextInteger(-12, 10), 58 + r:NextInteger(-6, 6))
	local tiers = r:NextInteger(3, 4)
	local y = base.Y + trunkH
	local w, h = 6.2 * scale, 8 * scale
	local yaw = r:NextNumber(0, math.pi / 2)
	for i = 1, tiers do
		pyramid(crown, Vector3.new(base.X, y + h, base.Z), w, h, yaw, {
			Color = green:Lerp(C(112, 162, 82), (i - 1) / tiers * 0.4),
			Material = M.SmoothPlastic,
			CanQuery = false,
		})
		y += h * 0.52
		w *= 0.74
		h *= 0.86
		yaw += math.pi / 4
	end
	crown.WorldPivot = CFrame.new(base + Vector3.new(0, trunkH, 0))
	CollectionService:AddTag(crown, "Sway")
	model.Parent = parent
	return model
end

-- Laubbaum (Eiche oder Birke): verjuengter Stamm, Aeste, Krone aus Blaetter-Kugeln
local function leafTree(parent: Instance, base: Vector3, scale: number, r: Random, birch: boolean): Model
	local model = Make("Model", { Name = if birch then "Birch" else "Oak" })
	local barkColor = if birch then C(228, 224, 214) else jitter(PAL.Bark, 0.08, r)
	local segs = if birch then { { 1.3, 5 }, { 1.05, 5 }, { 0.8, 4 } } else { { 2.5, 4.2 }, { 1.95, 4 }, { 1.45, 3.4 } }
	local p = base - Vector3.new(0, 0.8, 0)
	local maxLean = if birch then 0.03 else 0.12
	local lean = Vector3.new(r:NextNumber(-maxLean, maxLean), 0, r:NextNumber(-maxLean, maxLean))
	for i, seg in segs do
		local top = p + (Vector3.yAxis + lean) * (seg[2] * scale + (if i == 1 then 0.8 else 0))
		rod(model, p, top + Vector3.new(0, 0.3, 0), seg[1] * scale, {
			Name = "Trunk",
			Material = if birch then M.SmoothPlastic else M.Wood,
			Color = barkColor,
			CanCollide = i == 1,
		})
		p = top
	end
	if birch then
		-- typische dunkle Streifen der Birke
		for _ = 1, 3 do
			local yy = r:NextNumber(1.5, 12) * scale
			local localD = if yy < 5 * scale then 1.3 elseif yy < 10 * scale then 1.05 else 0.8
			pillar(model, base + Vector3.new(lean.X * yy, yy, lean.Z * yy), 0.25 * scale, localD * scale + 0.12, {
				Material = M.SmoothPlastic,
				Color = C(52, 50, 48),
				CanQuery = false,
				CastShadow = false,
			})
		end
	end
	local trunkTop = p
	-- Aeste
	for _ = 1, if birch then 1 else 2 do
		local a = r:NextNumber(0, TAU)
		local from = base + Vector3.new(0, r:NextNumber(5.5, 7.5) * scale, 0) + lean * 6 * scale
		local to = from + Vector3.new(math.cos(a) * 3.6 * scale, 3 * scale, math.sin(a) * 3.6 * scale)
		rod(model, from, to, (if birch then 0.45 else 0.8) * scale, {
			Material = if birch then M.SmoothPlastic else M.Wood,
			Color = barkColor,
			CanQuery = false,
		})
	end
	-- Krone
	local crown = Make("Model", { Name = "Crown", Parent = model })
	local leaf = if birch
		then C(136 + r:NextInteger(-10, 10), 182 + r:NextInteger(-10, 8), 70 + r:NextInteger(-8, 8))
		else C(80 + r:NextInteger(-10, 10), 140 + r:NextInteger(-14, 10), 52 + r:NextInteger(-8, 8))
	local center = trunkTop + Vector3.new(0, (if birch then 3 else 2) * scale, 0)
	ball(crown, center + Vector3.new(0, 1.5 * scale, 0), (if birch then 7.5 else 11.5) * scale, {
		Material = M.LeafyGrass,
		Color = leaf:Lerp(C(150, 196, 90), 0.18),
		CanQuery = false,
	})
	local n = if birch then 4 else r:NextInteger(4, 6)
	for i = 1, n do
		local a = (i / n) * TAU + r:NextNumber(-0.4, 0.4)
		local d = r:NextNumber(3.2, 5) * scale * (if birch then 0.6 else 1)
		local off = Vector3.new(math.cos(a) * d, r:NextNumber(-2.4, 1.2) * scale, math.sin(a) * d)
		if birch then
			off += Vector3.new(0, (i - n / 2) * 1.6 * scale, 0)
		end
		ball(crown, center + off, r:NextNumber(6.5, 9) * scale * (if birch then 0.75 else 1), {
			Material = M.LeafyGrass,
			Color = jitter(leaf, 0.07, r),
			CanQuery = false,
		})
	end
	crown.WorldPivot = CFrame.new(trunkTop)
	CollectionService:AddTag(crown, "Sway")
	model.Parent = parent
	return model
end

local function bush(parent: Instance, base: Vector3, scale: number, r: Random)
	local model = Make("Model", { Name = "Bush" })
	local green = C(66 + r:NextInteger(-8, 8), 122 + r:NextInteger(-12, 10), 48 + r:NextInteger(-6, 6))
	for i = 1, r:NextInteger(2, 3) do
		local d = r:NextNumber(3.2, 5.4) * scale
		local off = if i == 1 then Vector3.zero else Vector3.new(r:NextNumber(-2, 2), 0, r:NextNumber(-2, 2)) * scale
		ball(model, base + off + Vector3.new(0, d * 0.22, 0), d, {
			Material = M.LeafyGrass,
			Color = jitter(green, 0.08, r),
			CanQuery = false,
		})
	end
	model.Parent = parent
end

local function boulder(parent: Instance, base: Vector3, scale: number, r: Random)
	local model = Make("Model", { Name = "Boulder" })
	local grey = C(132, 128, 122)
	for i = 1, r:NextInteger(1, 3) do
		local s = (if i == 1 then r:NextNumber(5, 10) else r:NextNumber(2.5, 4.5)) * scale
		local size = Vector3.new(s * r:NextNumber(0.9, 1.4), s * r:NextNumber(0.6, 0.9), s * r:NextNumber(0.8, 1.2))
		local oa = r:NextNumber(0, TAU)
		local off = if i == 1 then Vector3.zero else Vector3.new(math.cos(oa), 0, math.sin(oa)) * (s + 2.5)
		block(model, {
			Size = size,
			CFrame = CFrame.new(base + off + Vector3.new(0, size.Y * 0.18, 0))
				* CFrame.Angles(r:NextNumber(-0.35, 0.35), r:NextNumber(0, TAU), r:NextNumber(-0.35, 0.35)),
			Material = M.Rock,
			Color = jitter(grey, 0.1, r),
			CanCollide = true,
		})
	end
	model.Parent = parent
end

local FLOWER_COLORS = { C(250, 238, 120), C(255, 255, 255), C(236, 120, 156), C(156, 128, 232), C(255, 160, 70) }
local function flowers(parent: Instance, base: Vector3, r: Random)
	local col = FLOWER_COLORS[r:NextInteger(1, #FLOWER_COLORS)]
	for _ = 1, r:NextInteger(3, 5) do
		local off = Vector3.new(r:NextNumber(-1.8, 1.8), 0.3, r:NextNumber(-1.8, 1.8))
		ball(parent, base + off, r:NextNumber(0.5, 0.75), {
			Name = "Flower",
			Material = M.SmoothPlastic,
			Color = col,
			CanQuery = false,
			CastShadow = false,
		})
	end
end

-- =============================================================================
-- Requisiten: Laternen, Zelte, Staende, Haeuser, Zaeune, Schilder ...
-- =============================================================================

-- Laterne am Holzpfahl; der Arm zeigt Richtung lokal -Z
local function lantern(parent: Instance, cf: CFrame, height: number?)
	local h = height or 8
	local model = Make("Model", { Name = "Lantern" })
	block(model, {
		Name = "Post",
		Size = Vector3.new(0.7, h + 1, 0.7),
		CFrame = cf * CFrame.new(0, (h + 1) / 2 - 1, 0),
		Material = M.Wood,
		Color = PAL.WoodDark,
		CanCollide = true,
	})
	block(model, {
		Size = Vector3.new(0.45, 0.45, 2.6),
		CFrame = cf * CFrame.new(0, h - 0.5, -1.05),
		Material = M.Wood,
		Color = PAL.WoodDark,
	})
	block(model, {
		Size = Vector3.new(0.3, 1.7, 0.3),
		CFrame = cf * CFrame.new(0, h - 1.1, -0.55) * CFrame.Angles(math.rad(-45), 0, 0),
		Material = M.Wood,
		Color = PAL.WoodDark,
	})
	local hang = cf * CFrame.new(0, h - 1.9, -2)
	block(model, { Size = Vector3.new(0.12, 0.6, 0.12), CFrame = hang * CFrame.new(0, 1.15, 0), Material = M.Metal, Color = PAL.Iron })
	block(model, { Size = Vector3.new(1.15, 0.28, 1.15), CFrame = hang * CFrame.new(0, 0.8, 0), Material = M.Metal, Color = PAL.Iron })
	block(model, {
		Size = Vector3.new(0.9, 1.25, 0.9),
		CFrame = hang,
		Material = M.Glass,
		Transparency = 0.35,
		Color = C(255, 214, 150),
		CastShadow = false,
	})
	local core = ball(model, hang.Position, 0.42, {
		Material = M.Neon,
		Color = C(255, 194, 116),
		CastShadow = false,
		CanQuery = false,
	})
	block(model, { Size = Vector3.new(1.05, 0.2, 1.05), CFrame = hang * CFrame.new(0, -0.72, 0), Material = M.Metal, Color = PAL.Iron })
	pointLight(core, C(255, 186, 110), 14, 1, true)
	model.Parent = parent
end

-- Zelt: zwei Keile Ruecken an Ruecken, Eingang zeigt nach lokal +X
local function tent(parent: Instance, cf: CFrame, color: Color3)
	local model = Make("Model", { Name = "Tent" })
	local len, h, half = 8, 5.5, 3.8
	wedge(model, cf * CFrame.new(0, h / 2, -half / 2), Vector3.new(len, h, half), { Material = M.Fabric, Color = color, CanCollide = true })
	wedge(model, cf * CFrame.new(0, h / 2, half / 2) * CFrame.Angles(0, math.pi, 0), Vector3.new(len, h, half), {
		Material = M.Fabric,
		Color = color:Lerp(Color3.new(0, 0, 0), 0.08),
		CanCollide = true,
	})
	-- dunkle Eingangsoeffnung
	local dh, dw = h * 0.62, half * 0.42
	local door = C(58, 44, 36)
	wedge(model, cf * CFrame.new(len / 2 + 0.03, dh / 2, -dw / 2), Vector3.new(0.12, dh, dw), { Material = M.Fabric, Color = door })
	wedge(model, cf * CFrame.new(len / 2 + 0.03, dh / 2, dw / 2) * CFrame.Angles(0, math.pi, 0), Vector3.new(0.12, dh, dw), {
		Material = M.Fabric,
		Color = door,
	})
	-- Firststange
	rod(model, (cf * CFrame.new(-len / 2 - 0.7, h + 0.1, 0)).Position, (cf * CFrame.new(len / 2 + 0.7, h + 0.1, 0)).Position, 0.35, {
		Material = M.Wood,
		Color = PAL.WoodDark,
	})
	for _, x in { -len / 2 - 0.5, len / 2 + 0.5 } do
		rod(model, (cf * CFrame.new(x, 0, 0)).Position, (cf * CFrame.new(x, h + 0.3, 0)).Position, 0.3, {
			Material = M.Wood,
			Color = PAL.WoodDark,
		})
	end
	model.Parent = parent
end

local function barrel(parent: Instance, ground: Vector3)
	pillar(parent, ground, 2.8, 2.2, { Material = M.Wood, Color = C(134, 92, 56), CanCollide = true })
	for _, y in { 0.45, 2.1 } do
		pillar(parent, ground + Vector3.new(0, y, 0), 0.25, 2.3, { Material = M.Metal, Color = PAL.Iron, CanQuery = false })
	end
	pillar(parent, ground + Vector3.new(0, 2.8, 0), 0.06, 1.9, { Material = M.WoodPlanks, Color = PAL.WoodLight, CanQuery = false })
end

local function crate(parent: Instance, cf: CFrame, s: number)
	block(parent, { Size = Vector3.new(s, s, s), CFrame = cf * CFrame.new(0, s / 2, 0), Material = M.WoodPlanks, Color = PAL.Plank, CanCollide = true })
	block(parent, {
		Size = Vector3.new(s + 0.1, 0.22, s + 0.1),
		CFrame = cf * CFrame.new(0, s - 0.15, 0),
		Material = M.Wood,
		Color = PAL.WoodDark,
		CanQuery = false,
	})
end

-- Marktstand: Theke vorne (lokal -Z), gestreiftes Stoffdach
local function stall(parent: Instance, cf: CFrame, roofColor: Color3)
	local model = Make("Model", { Name = "MarketStall" })
	for _, x in { -3.8, 3.8 } do
		block(model, { Size = Vector3.new(0.55, 6.6, 0.55), CFrame = cf * CFrame.new(x, 3.3, -1.9), Material = M.Wood, Color = PAL.Wood, CanCollide = true })
		block(model, { Size = Vector3.new(0.55, 7.6, 0.55), CFrame = cf * CFrame.new(x, 3.8, 1.9), Material = M.Wood, Color = PAL.Wood, CanCollide = true })
	end
	block(model, { Size = Vector3.new(8, 2.8, 1.5), CFrame = cf * CFrame.new(0, 1.4, -1.6), Material = M.WoodPlanks, Color = PAL.Plank, CanCollide = true })
	block(model, { Size = Vector3.new(8.6, 0.3, 2), CFrame = cf * CFrame.new(0, 2.95, -1.6), Material = M.Wood, Color = PAL.WoodLight })
	for i = 0, 3 do
		block(model, {
			Size = Vector3.new(2.25, 0.2, 5.4),
			CFrame = cf * CFrame.new(-3.375 + i * 2.25, 7.15, -0.05) * CFrame.Angles(math.rad(-15), 0, 0),
			Material = M.Fabric,
			Color = if i % 2 == 0 then roofColor else PAL.Canvas,
		})
	end
	-- Ware auf der Theke
	local goods = { C(204, 52, 46), C(250, 150, 40), C(120, 176, 56), C(230, 196, 70) }
	for i = 1, 6 do
		ball(model, (cf * CFrame.new(-3 + i * 0.9, 3.45, -1.6 + rng:NextNumber(-0.4, 0.4))).Position, 0.6, {
			Material = M.SmoothPlastic,
			Color = goods[(i % #goods) + 1],
			CanQuery = false,
			CastShadow = false,
		})
	end
	crate(model, cf * CFrame.new(5.6, 0, -1.2) * CFrame.Angles(0, 0.2, 0), 2)
	crate(model, cf * CFrame.new(5.5, 2, -1.1) * CFrame.Angles(0, -0.15, 0), 1.4)
	barrel(model, (cf * CFrame.new(-5.6, 0, -0.6)).Position)
	model.Parent = parent
end

-- Kleines Fachwerkhaus (Tuer vorne = lokal -Z)
local function cottage(parent: Instance, cf: CFrame, roofColor: Color3)
	local model = Make("Model", { Name = "Cottage" })
	local W, D, H = 12, 10, 7
	block(model, { Size = Vector3.new(W + 0.8, 1.2, D + 0.8), CFrame = cf * CFrame.new(0, 0.3, 0), Material = M.Cobblestone, Color = PAL.Stone, CanCollide = true })
	block(model, { Size = Vector3.new(W, H, D), CFrame = cf * CFrame.new(0, 0.9 + H / 2, 0), Material = M.Plaster, Color = PAL.Plaster, CanCollide = true })
	local top = 0.9 + H
	-- Fachwerk-Balken
	for _, x in { -W / 2, W / 2 } do
		for _, z in { -D / 2, D / 2 } do
			block(model, { Size = Vector3.new(0.8, H, 0.8), CFrame = cf * CFrame.new(x, 0.9 + H / 2, z), Material = M.Wood, Color = PAL.WoodDark })
		end
	end
	for _, z in { -D / 2 - 0.1, D / 2 + 0.1 } do
		block(model, { Size = Vector3.new(W + 0.4, 0.7, 0.35), CFrame = cf * CFrame.new(0, top - 0.3, z), Material = M.Wood, Color = PAL.WoodDark })
		-- Querbalken oberhalb von Tuer und Fenster
		block(model, { Size = Vector3.new(W, 0.5, 0.3), CFrame = cf * CFrame.new(0, 5.95, z + (if z < 0 then -0.05 else 0.05)), Material = M.Wood, Color = PAL.WoodDark })
	end
	-- Satteldach (First entlang X)
	local rh, rd = 4.6, D / 2 + 1.3
	wedge(model, cf * CFrame.new(0, top + rh / 2, -rd / 2), Vector3.new(W + 1.6, rh, rd), { Material = M.ClayRoofTiles, Color = roofColor, CanCollide = true })
	wedge(model, cf * CFrame.new(0, top + rh / 2, rd / 2) * CFrame.Angles(0, math.pi, 0), Vector3.new(W + 1.6, rh, rd), {
		Material = M.ClayRoofTiles,
		Color = roofColor,
		CanCollide = true,
	})
	block(model, { Size = Vector3.new(W + 1.8, 0.5, 0.6), CFrame = cf * CFrame.new(0, top + rh + 0.05, 0), Material = M.Wood, Color = PAL.WoodDark })
	-- Schornstein mit leichtem Rauch
	local chimney = block(model, {
		Size = Vector3.new(1.6, 5, 1.6),
		CFrame = cf * CFrame.new(W * 0.28, top + 3.2, D * 0.22),
		Material = M.Brick,
		Color = C(132, 86, 72),
		CanCollide = true,
	})
	Make("ParticleEmitter", {
		Name = "ChimneySmoke",
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(C(190, 190, 192), C(230, 230, 232)),
		LightEmission = 0,
		Size = NumberSequence.new({ nsk(0, 1), nsk(1, 4.5) }),
		Transparency = NumberSequence.new({ nsk(0, 0.7), nsk(1, 1) }),
		Lifetime = NumberRange.new(3, 4.5),
		Rate = 2,
		Speed = NumberRange.new(2.5, 3.5),
		SpreadAngle = Vector2.new(6, 6),
		Acceleration = Vector3.new(1.2, 0.3, 0.3),
		EmissionDirection = Enum.NormalId.Top,
		Parent = chimney,
	})
	-- Tuer, Fenster mit Laeden, Blumenkasten
	local front = -D / 2 - 0.1
	block(model, { Size = Vector3.new(2.6, 4.4, 0.3), CFrame = cf * CFrame.new(-2.6, 0.9 + 2.2, front), Material = M.WoodPlanks, Color = C(110, 70, 44) })
	ball(model, (cf * CFrame.new(-1.75, 3.1, front - 0.2)).Position, 0.3, { Material = M.Metal, Color = PAL.Gold, CanQuery = false })
	for _, x in { 2.6 } do
		block(model, {
			Size = Vector3.new(2.2, 2, 0.2),
			CFrame = cf * CFrame.new(x, 4.6, front),
			Material = M.Glass,
			Color = C(255, 222, 160),
			Transparency = 0.15,
			CastShadow = false,
		})
		for _, s in { -1, 1 } do
			block(model, {
				Size = Vector3.new(0.9, 2.3, 0.15),
				CFrame = cf * CFrame.new(x + s * 1.6, 4.6, front - 0.1),
				Material = M.WoodPlanks,
				Color = C(70, 112, 150),
			})
		end
		block(model, { Size = Vector3.new(2.6, 0.6, 0.7), CFrame = cf * CFrame.new(x, 3.35, front - 0.35), Material = M.Wood, Color = PAL.Wood })
		for i = -1, 1 do
			ball(model, (cf * CFrame.new(x + i * 0.75, 3.8, front - 0.35)).Position, 0.55, {
				Material = M.SmoothPlastic,
				Color = FLOWER_COLORS[(i + 3) % #FLOWER_COLORS + 1],
				CanQuery = false,
				CastShadow = false,
			})
		end
	end
	model.Parent = parent
end

-- Holzzaun zwischen zwei Bodenpunkten
local function fence(parent: Instance, a: Vector3, b: Vector3)
	local len = (b - a).Magnitude
	local n = math.max(1, math.floor(len / 4.5 + 0.5))
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		block(parent, {
			Size = Vector3.new(0.6, 3.6, 0.6),
			CFrame = CFrame.new(p + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, rng:NextNumber(-0.2, 0.2), rng:NextNumber(-0.03, 0.03)),
			Material = M.Wood,
			Color = PAL.WoodDark,
			CanCollide = true,
		})
	end
	for _, y in { 1.3, 2.6 } do
		block(parent, {
			Size = Vector3.new(0.28, 0.4, len),
			CFrame = CFrame.lookAt(a:Lerp(b, 0.5) + Vector3.new(0, y, 0), b + Vector3.new(0, y, 0)),
			Material = M.Wood,
			Color = PAL.Wood,
			CanCollide = true,
		})
	end
end

-- Wegweiser: Pfahl mit Brettern, die in Zielrichtung zeigen
local function signpost(parent: Instance, ground: Vector3, entries: { { Text: string, Target: Vector3 } })
	local model = Make("Model", { Name = "Signpost" })
	block(model, {
		Size = Vector3.new(0.7, 8, 0.7),
		CFrame = CFrame.new(ground + Vector3.new(0, 3.5, 0)),
		Material = M.Wood,
		Color = PAL.WoodDark,
		CanCollide = true,
	})
	for i, e in entries do
		local dir = Vector3.new(e.Target.X - ground.X, 0, e.Target.Z - ground.Z)
		dir = if dir.Magnitude > 0.01 then dir.Unit else Vector3.xAxis
		local yaw = math.atan2(-dir.Z, dir.X)
		local center = ground + Vector3.new(0, 6.6 - (i - 1) * 1.45, 0) + dir * 2.4
		local board = block(model, {
			Size = Vector3.new(4.6, 1.15, 0.3),
			CFrame = CFrame.new(center) * CFrame.Angles(0, yaw, 0),
			Material = M.WoodPlanks,
			Color = PAL.Plank,
		})
		signText(board, e.Text, Enum.NormalId.Front)
		signText(board, e.Text, Enum.NormalId.Back)
	end
	model.Parent = parent
end

-- =============================================================================
-- Lobby: Lager-Dorf auf der Wiese
-- =============================================================================

local function buildCrateAltar(lobby: Instance)
	local base = at(0, 0)
	pillar(lobby, base - Vector3.new(0, 0.4, 0), 1.6, 16, { Name = "AltarBase", Material = M.Slate, Color = PAL.StoneDark, CanCollide = true })
	pillar(lobby, base + Vector3.new(0, 1, 0), 1.2, 12.5, { Name = "AltarStep", Material = M.Slate, Color = PAL.Stone, CanCollide = true })
	local altar = pillar(lobby, base + Vector3.new(0, 2, 0), 0.9, 10, {
		Name = "CrateAltar",
		Material = M.Slate,
		Color = PAL.StoneLight,
		CanCollide = true,
	})
	pillar(lobby, base + Vector3.new(0, 2.55, 0), 0.25, 10.3, { Material = M.Metal, Color = PAL.Bronze, CanQuery = false })
	local topY = 2.9

	-- Schatztruhe (Front zeigt Richtung Spawn)
	local chest = Make("Model", { Name = "TreasureChest", Parent = lobby })
	local cf = flatLook(base + Vector3.new(0, topY, 0), SPAWN_POS)
	local wood = C(140, 92, 52)
	local body = block(chest, { Name = "Body", Size = Vector3.new(5, 2.8, 3.2), CFrame = cf * CFrame.new(0, 1.4, 0), Material = M.WoodPlanks, Color = wood, CanCollide = true })
	block(chest, {
		Name = "Lid",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(5.06, 3.2, 3.2),
		CFrame = cf * CFrame.new(0, 2.8, 0),
		Material = M.WoodPlanks,
		Color = wood:Lerp(Color3.new(0, 0, 0), 0.1),
		CanCollide = true,
	})
	for _, x in { -1.75, 1.75 } do
		block(chest, { Size = Vector3.new(0.38, 2.86, 3.3), CFrame = cf * CFrame.new(x, 1.42, 0), Material = M.Metal, Color = PAL.Iron })
		block(chest, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 3.32, 3.32), CFrame = cf * CFrame.new(x, 2.8, 0), Material = M.Metal, Color = PAL.Iron })
	end
	block(chest, { Size = Vector3.new(5.1, 0.32, 3.3), CFrame = cf * CFrame.new(0, 0.2, 0), Material = M.Metal, Color = PAL.Iron })
	block(chest, { Size = Vector3.new(5.12, 0.3, 3.32), CFrame = cf * CFrame.new(0, 2.72, 0), Material = M.Metal, Color = PAL.Gold })
	block(chest, { Size = Vector3.new(0.95, 1.1, 0.22), CFrame = cf * CFrame.new(0, 2.5, -1.7), Material = M.Metal, Color = PAL.Gold })
	block(chest, { Size = Vector3.new(0.2, 0.38, 0.06), CFrame = cf * CFrame.new(0, 2.42, -1.83), Material = M.SmoothPlastic, Color = C(30, 22, 16) })
	for _, x in { -2.35, 2.35 } do
		for _, z in { -1.45, 1.45 } do
			block(chest, { Size = Vector3.new(0.5, 0.5, 0.5), CFrame = cf * CFrame.new(x, 0.25, z), Material = M.Metal, Color = PAL.Gold })
		end
	end
	-- warmer Schimmer und ein paar Funken
	pointLight(body, C(255, 196, 110), 12, 1.1)
	Make("ParticleEmitter", {
		Name = "Glints",
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(C(255, 228, 150), C(255, 190, 70)),
		LightEmission = 0.6,
		Size = NumberSequence.new({ nsk(0, 0), nsk(0.3, 0.35), nsk(1, 0) }),
		Transparency = NumberSequence.new(0.1),
		Lifetime = NumberRange.new(1.2, 2),
		Rate = 3,
		Speed = NumberRange.new(0.6, 1.4),
		SpreadAngle = Vector2.new(40, 40),
		EmissionDirection = Enum.NormalId.Top,
		Parent = body,
	})
	-- Muenzen auf dem Sockel
	for i = 1, 7 do
		local a = (i / 7) * TAU + rng:NextNumber(-0.3, 0.3)
		local d = rng:NextNumber(3.3, 4.3)
		local pos = base + Vector3.new(math.cos(a) * d, topY, math.sin(a) * d)
		pillar(lobby, pos, 0.18, if i == 1 then 1.1 else 0.95, {
			Material = M.Metal,
			Color = PAL.Gold,
			CanQuery = false,
			CastShadow = false,
		})
	end

	Make("ProximityPrompt", {
		Name = "OpenCrates",
		ActionText = "Open Crates",
		ObjectText = "Crate Altar",
		KeyboardKeyCode = Enum.KeyCode.E,
		HoldDuration = 0,
		MaxActivationDistance = 14,
		RequiresLineOfSight = false,
		Parent = altar,
	})
	marker(altar, "CRATES", C(255, 187, 40), C(196, 116, 10), 8)
end

local function buildShrine(lobby: Instance)
	local S = SHRINE_POS
	local folder = Make("Model", { Name = "BlackHoleShrineSite", Parent = lobby })
	pillar(folder, S - Vector3.new(0, 0.4, 0), 1.2, 17, { Material = M.Basalt, Color = C(48, 44, 56), CanCollide = true })
	local shrine = pillar(folder, S + Vector3.new(0, 0.6, 0), 0.9, 12, {
		Name = "BlackHoleShrine",
		Material = M.Basalt,
		Color = PAL.Obsidian,
		CanCollide = true,
	})
	-- Stehende Obsidian-Steine (Luecke Richtung Dorfplatz), hinten ein Torbogen
	local toLobby = math.atan2(L.Z - S.Z, L.X - S.X)
	local tops: { [number]: Vector3 } = {}
	for _, step in { 1, 2, 3, 5, 6, 7 } do
		local a = toLobby + step * (TAU / 8)
		local h = if step == 3 or step == 5 then 10 elseif step == 2 or step == 6 then 8 else 6.5
		local pos = S + Vector3.new(math.cos(a) * 7.4, 0, math.sin(a) * 7.4)
		local stone = block(folder, {
			Size = Vector3.new(2.4, h, 1.4),
			CFrame = flatLook(pos + Vector3.new(0, 0.5 + h / 2, 0), S)
				* CFrame.Angles(rng:NextNumber(-0.06, 0.06), 0, rng:NextNumber(-0.05, 0.05)),
			Material = M.Basalt,
			Color = jitter(C(38, 34, 48), 0.12, rng),
			Reflectance = 0.06,
			CanCollide = true,
		})
		tops[step] = (stone.CFrame * CFrame.new(0, h / 2, 0)).Position
	end
	local t3, t5 = tops[3], tops[5]
	if t3 and t5 then
		local mid = (t3 + t5) / 2 + Vector3.new(0, 0.6, 0)
		block(folder, {
			Size = Vector3.new(1.8, 1.4, (t3 - t5).Magnitude + 2.6),
			CFrame = CFrame.lookAt(mid, t5 + Vector3.new(0, 0.6, 0)),
			Material = M.Basalt,
			Color = C(34, 30, 44),
			CanCollide = true,
		})
	end
	-- Das kleine schwarze Loch: dunkler Kern, leicht verzerrender Rand, kreisende Splitter
	local corePos = S + Vector3.new(0, 6.4, 0)
	local core = ball(folder, corePos, 3.2, { Name = "Singularity", Material = M.SmoothPlastic, Color = C(6, 4, 10), CastShadow = false })
	ball(folder, corePos, 4.6, {
		Name = "Lens",
		Material = M.Glass,
		Color = C(110, 82, 168),
		Transparency = 0.82,
		CastShadow = false,
		CanQuery = false,
	})
	local accretion = Make("Model", { Name = "Accretion" })
	local pivot = CFrame.new(corePos) * CFrame.Angles(math.rad(16), 0, math.rad(-10))
	for j = 1, 10 do
		local a = (j / 10) * TAU + rng:NextNumber(-0.15, 0.15)
		local r = rng:NextNumber(3.3, 4.4)
		block(accretion, {
			Size = Vector3.new(rng:NextNumber(0.35, 0.55), rng:NextNumber(0.35, 0.5), rng:NextNumber(0.9, 1.5)),
			CFrame = pivot * CFrame.Angles(0, a, 0) * CFrame.new(r, rng:NextNumber(-0.3, 0.3), 0) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), 0, rng:NextNumber(-0.4, 0.4)),
			Material = M.Basalt,
			Color = if j % 3 == 0 then C(92, 70, 136) else C(52, 40, 80),
			CastShadow = false,
			CanQuery = false,
		})
	end
	accretion.WorldPivot = pivot
	accretion.Parent = folder
	CollectionService:AddTag(accretion, "Spin")
	-- Partikel, die in den Kern gesogen werden (dunkler Dunst + wenige helle Funken)
	local field = ball(folder, corePos, 10, { Name = "PullField", Transparency = 1, CanQuery = false, CastShadow = false })
	Make("ParticleEmitter", {
		Name = "Inflow",
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(C(76, 54, 118), C(18, 12, 28)),
		LightEmission = 0,
		LightInfluence = 0.4,
		Size = NumberSequence.new({ nsk(0, 1.6), nsk(1, 0.2) }),
		Transparency = NumberSequence.new({ nsk(0, 1), nsk(0.3, 0.55), nsk(1, 0.9) }),
		Lifetime = NumberRange.new(1.1, 1.4),
		Rate = 14,
		Speed = NumberRange.new(3.2, 4),
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-60, 60),
		Parent = field,
	})
	Make("ParticleEmitter", {
		Name = "Motes",
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(C(214, 196, 255)),
		LightEmission = 0.4,
		Size = NumberSequence.new({ nsk(0, 0.3), nsk(1, 0) }),
		Lifetime = NumberRange.new(1.1, 1.4),
		Rate = 4,
		Speed = NumberRange.new(3.5, 4.2),
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		Parent = field,
	})
	pointLight(core, C(150, 112, 236), 12, 0.9)
	-- dunkle Kiesel rundherum
	for _ = 1, 8 do
		local a = rng:NextNumber(0, TAU)
		local d = rng:NextNumber(9, 12)
		block(folder, {
			Size = Vector3.new(rng:NextNumber(0.6, 1.4), rng:NextNumber(0.4, 0.8), rng:NextNumber(0.6, 1.2)),
			CFrame = CFrame.new(S + Vector3.new(math.cos(a) * d, 0.15, math.sin(a) * d)) * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 6), 0),
			Material = M.Basalt,
			Color = C(44, 40, 52),
			CanQuery = false,
		})
	end
	Make("ProximityPrompt", {
		Name = "OpenShop",
		ActionText = "View Black Hole",
		ObjectText = "Singularity Shrine",
		KeyboardKeyCode = Enum.KeyCode.E,
		HoldDuration = 0,
		MaxActivationDistance = 14,
		RequiresLineOfSight = false,
		Parent = shrine,
	})
	marker(shrine, "BLACK HOLE", C(150, 96, 255), C(92, 50, 184), 11)
end

local function buildTraining(lobby: Instance): { CFrame }
	local T = TRAIN_POS
	local yard = Make("Model", { Name = "TrainingGround", Parent = lobby })
	local floorTop = GROUND + 0.15
	block(yard, {
		Name = "TrainingFloor",
		Size = Vector3.new(30, 1, 22),
		CFrame = CFrame.new(T.X, floorTop - 0.5, T.Z),
		Material = M.Ground,
		Color = C(138, 106, 74),
		CanCollide = true,
	})
	-- Zaun mit Eingaengen im Osten (zum Dorfplatz) und Sueden (zum Lager)
	local function p(x: number, z: number): Vector3
		return Vector3.new(T.X + x, GROUND, T.Z + z)
	end
	fence(yard, p(-16, -12), p(16, -12))
	fence(yard, p(-16, -12), p(-16, 12))
	fence(yard, p(-16, 12), p(-4, 12))
	fence(yard, p(4, 12), p(16, 12))
	fence(yard, p(16, 12), p(16, 4))
	fence(yard, p(16, -4), p(16, -12))
	for _, gp in { p(16, 4), p(16, -4), p(-4, 12), p(4, 12) } do
		block(yard, { Size = Vector3.new(0.9, 4.6, 0.9), CFrame = CFrame.new(gp + Vector3.new(0, 2.1, 0)), Material = M.Wood, Color = PAL.Wood, CanCollide = true })
		ball(yard, gp + Vector3.new(0, 4.6, 0), 1, { Material = M.Wood, Color = PAL.WoodLight, CanQuery = false })
	end

	-- Plaetze fuer die Trainingspuppen (Strohkreis am Boden)
	local spots = {}
	for i = -1, 1 do
		local pos = p(i * 8, -5)
		pillar(yard, Vector3.new(pos.X, floorTop - 0.05, pos.Z), 0.12, 3.6, {
			Material = M.Fabric,
			Color = PAL.Straw,
			CanQuery = false,
			CastShadow = false,
		})
		local standPos = Vector3.new(pos.X, floorTop + 3.1, pos.Z)
		table.insert(spots, CFrame.lookAt(standPos, standPos + Vector3.new(0, 0, 1)))
	end
	block(yard, {
		Name = "TrainingArea",
		Size = Vector3.new(26, 1, 18),
		CFrame = CFrame.new(T.X, floorTop + 2, T.Z + 1),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})

	-- Waffenstaender
	local rack = p(-11, 8)
	for _, x in { -2, 2 } do
		block(yard, { Size = Vector3.new(0.5, 4, 0.5), CFrame = CFrame.new(rack + Vector3.new(x, 2, 0)), Material = M.Wood, Color = PAL.WoodDark, CanCollide = true })
	end
	block(yard, { Size = Vector3.new(4.6, 0.4, 0.5), CFrame = CFrame.new(rack + Vector3.new(0, 3.4, 0)), Material = M.Wood, Color = PAL.WoodDark })
	block(yard, { Size = Vector3.new(4.6, 0.4, 0.5), CFrame = CFrame.new(rack + Vector3.new(0, 1, 0)), Material = M.Wood, Color = PAL.WoodDark })
	for i = -1, 1 do
		local sword = CFrame.new(rack + Vector3.new(i * 1.3, 2.1, -0.45)) * CFrame.Angles(math.rad(-12), 0, 0)
		block(yard, { Size = Vector3.new(0.35, 3.6, 0.12), CFrame = sword, Material = M.Wood, Color = PAL.WoodLight, CanQuery = false })
		block(yard, { Size = Vector3.new(1.1, 0.22, 0.22), CFrame = sword * CFrame.new(0, 0.7, 0), Material = M.Wood, Color = PAL.WoodDark, CanQuery = false })
	end
	-- Heuballen
	for _, hb in { { 11, 8, 0 }, { 12, 4.4, 0.3 } } do
		local c = p(hb[1], hb[2]) + Vector3.new(0, 1.3, 0)
		rod(yard, c - Vector3.new(1.7, 0, 0), c + Vector3.new(1.7, 0, 0), 2.6, { Material = M.Fabric, Color = PAL.Straw, CanCollide = true })
	end
	rod(yard, p(11.5, 6.2) + Vector3.new(-1.5, 3.4, 0), p(11.5, 6.2) + Vector3.new(1.5, 3.4, 0), 2.2, { Material = M.Fabric, Color = jitter(PAL.Straw, 0.05, rng), CanCollide = true })
	-- Zielscheibe
	local tgt = flatLook(p(-12, -8) + Vector3.new(0, 2.6, 0), p(-12, 0))
	for i, ring in { { 4, PAL.Straw }, { 3, C(196, 52, 46) }, { 2, C(240, 232, 214) }, { 1, C(196, 52, 46) } } do
		block(yard, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6 + i * 0.05, ring[1], ring[1]),
			CFrame = tgt * CFrame.Angles(0, math.rad(90), 0),
			Material = M.Fabric,
			Color = ring[2],
			CanCollide = i == 1,
		})
	end
	for _, x in { -1.2, 1.2 } do
		block(yard, { Size = Vector3.new(0.4, 4.4, 0.4), CFrame = tgt * CFrame.new(x, -0.6, 0.5) * CFrame.Angles(math.rad(-12), 0, 0), Material = M.Wood, Color = PAL.WoodDark })
	end
	-- Schild am Eingang
	local signPos = p(17.2, -6)
	block(yard, { Size = Vector3.new(0.6, 5.2, 0.6), CFrame = CFrame.new(signPos + Vector3.new(0, 2.4, 0)), Material = M.Wood, Color = PAL.WoodDark, CanCollide = true })
	local board = block(yard, {
		Size = Vector3.new(5.4, 1.6, 0.3),
		CFrame = CFrame.lookAt(signPos + Vector3.new(0.4, 4.2, 0), signPos + Vector3.new(10, 4.2, 0)),
		Material = M.WoodPlanks,
		Color = PAL.Plank,
	})
	signText(board, "TRAINING", Enum.NormalId.Front)
	signText(board, "TRAINING", Enum.NormalId.Back)
	marker(board, "TRAINING", C(104, 206, 70), C(55, 137, 36), 3.4)
	return spots
end

local function buildCamp(lobby: Instance)
	local F = CAMP_POS
	local camp = Make("Model", { Name = "Campfire", Parent = lobby })
	for i = 1, 9 do
		local a = (i / 9) * TAU
		local s = rng:NextNumber(1, 1.4)
		block(camp, {
			Size = Vector3.new(s, s * 0.7, s * 0.9),
			CFrame = CFrame.new(F + Vector3.new(math.cos(a) * 2.2, s * 0.25, math.sin(a) * 2.2)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), a, rng:NextNumber(-0.3, 0.3)),
			Material = M.Rock,
			Color = jitter(C(120, 116, 110), 0.1, rng),
			CanCollide = true,
		})
	end
	pillar(camp, F - Vector3.new(0, 0.05, 0), 0.15, 3.4, { Material = M.Slate, Color = C(40, 34, 30), CanQuery = false, CastShadow = false })
	for i = 1, 4 do
		local a = (i / 4) * TAU + 0.4
		rod(camp, F + Vector3.new(math.cos(a) * 1.3, 0.2, math.sin(a) * 1.3), F + Vector3.new(0, 1.9, 0), 0.45, {
			Material = M.Wood,
			Color = C(70, 48, 32),
		})
	end
	local fireAnchor = block(camp, { Name = "FireAnchor", Size = Vector3.new(1, 0.2, 1), CFrame = CFrame.new(F + Vector3.new(0, 0.5, 0)), Transparency = 1, CanQuery = false, CastShadow = false })
	addFire(fireAnchor, 1.15, true)
	-- Sitzbaenke aus Baumstaemmen
	for _, deg in { 30, 150, 270 } do
		local a = math.rad(deg)
		local c = F + Vector3.new(math.cos(a) * 5.4, 0.62, math.sin(a) * 5.4)
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		rod(camp, c - tangent * 2.4, c + tangent * 2.4, 1.3, { Material = M.Wood, Color = PAL.Wood, CanCollide = true })
	end
	-- Zelte rund ums Feuer (Eingang zum Feuer)
	local tentSpots = { { at(-64, 8), PAL.Canvas }, { at(-63, 36), C(176, 96, 66) }, { at(-40, 42), C(108, 128, 88) } }
	for _, t in tentSpots do
		local pos: Vector3 = t[1]
		local dir = Vector3.new(F.X - pos.X, 0, F.Z - pos.Z).Unit
		tent(lobby, CFrame.new(pos) * CFrame.Angles(0, math.atan2(-dir.Z, dir.X), 0), t[2])
	end
	barrel(lobby, at(-56, 27))
	crate(lobby, CFrame.new(at(-54, 30)) * CFrame.Angles(0, 0.4, 0), 1.8)
	-- Feuerholz-Stapel
	for i = 0, 2 do
		local y = 0.45 + (if i == 2 then 0.75 else 0)
		local x = if i == 2 then 0 else (i - 0.5) * 0.9
		rod(lobby, at(-34 + x, 24, y) - Vector3.new(0, 0, 1.4), at(-34 + x, 24, y) + Vector3.new(0, 0, 1.4), 0.85, {
			Material = M.Wood,
			Color = PAL.Bark,
		})
	end
end

local function buildArenaGate(lobby: Instance)
	local g = at(0, -52)
	local gate = Make("Model", { Name = "ArenaGate", Parent = lobby })
	for _, x in { -7, 7 } do
		block(gate, { Size = Vector3.new(1.4, 13, 1.4), CFrame = CFrame.new(g + Vector3.new(x, 5.5, 0)), Material = M.Wood, Color = PAL.WoodDark, CanCollide = true })
		block(gate, { Size = Vector3.new(2, 1.4, 2), CFrame = CFrame.new(g + Vector3.new(x, 0.3, 0)), Material = M.Cobblestone, Color = PAL.Stone, CanCollide = true })
		-- Banner am Pfosten
		block(gate, {
			Size = Vector3.new(1.8, 5, 0.12),
			CFrame = CFrame.new(g + Vector3.new(x, 8.2, 0.78)),
			Material = M.Fabric,
			Color = CLOTH[1],
		})
	end
	block(gate, { Size = Vector3.new(17.5, 1.4, 1.5), CFrame = CFrame.new(g + Vector3.new(0, 11.6, 0)), Material = M.Wood, Color = PAL.Wood })
	block(gate, { Size = Vector3.new(15.2, 0.8, 0.9), CFrame = CFrame.new(g + Vector3.new(0, 10.2, 0)), Material = M.Wood, Color = PAL.WoodDark })
	for _, x in { -3, 3 } do
		block(gate, { Size = Vector3.new(0.15, 1.4, 0.15), CFrame = CFrame.new(g + Vector3.new(x, 9.2, 0)), Material = M.Metal, Color = PAL.Iron })
	end
	local board = block(gate, {
		Size = Vector3.new(8.4, 2.2, 0.35),
		CFrame = CFrame.new(g + Vector3.new(0, 7.6, 0)),
		Material = M.WoodPlanks,
		Color = PAL.Plank,
	})
	signText(board, "ARENA", Enum.NormalId.Front)
	signText(board, "ARENA", Enum.NormalId.Back)
end

local function buildLobby(map: Instance): (CFrame, { CFrame })
	local lobby = Make("Folder", { Name = "Lobby", Parent = map })

	-- Spawn: schlichte Steinplatte mit Bronze-Mitte
	pillar(lobby, SPAWN_POS - Vector3.new(0, 0.3, 0), 0.5, 10, { Material = M.Slate, Color = PAL.StoneLight, CanCollide = true })
	pillar(lobby, SPAWN_POS - Vector3.new(0, 0.3, 0), 0.56, 6.6, { Material = M.Slate, Color = PAL.Stone, CanCollide = true })
	pillar(lobby, SPAWN_POS - Vector3.new(0, 0.3, 0), 0.62, 2.4, { Material = M.Metal, Color = PAL.Bronze, CanCollide = true })
	local spawn = Make("SpawnLocation", {
		Name = "LobbySpawn",
		Size = Vector3.new(8, 1, 8),
		CFrame = CFrame.new(SPAWN_POS + Vector3.new(0, 0.5, 0)),
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Neutral = true,
		Duration = 0,
		Parent = lobby,
	})
	for _, d in spawn:GetChildren() do
		if d:IsA("Decal") then
			d:Destroy()
		end
	end

	buildCrateAltar(lobby)
	buildShrine(lobby)
	local dummySpots = buildTraining(lobby)
	buildCamp(lobby)
	buildArenaGate(lobby)

	-- Marktstaende und Haeuser, alle zum Platz gedreht
	stall(lobby, flatLook(at(40, 14), at(0, 0)), CLOTH[1])
	stall(lobby, flatLook(at(34, 38), at(0, 0)), CLOTH[2])
	cottage(lobby, flatLook(at(-62, -58), at(0, 0)), PAL.Roof)
	cottage(lobby, flatLook(at(74, -4), at(0, 0)), C(120, 84, 70))
	cottage(lobby, flatLook(at(22, 70), at(0, 0)), PAL.Roof)

	-- Laternen rund um den Platz (Arm zeigt zum Platz)
	for _, deg in { 20, 65, 115, 160, 205, 245, 295, 345 } do
		local a = math.rad(deg)
		local pos = at(math.cos(a) * 34.5, math.sin(a) * 34.5)
		lantern(lobby, flatLook(pos, at(0, 0)))
	end

	signpost(lobby, at(9, -40), {
		{ Text = "ARENA", Target = A },
		{ Text = "TRAINING", Target = TRAIN_POS },
		{ Text = "BLACK HOLE", Target = SHRINE_POS },
	})

	-- Blumen, Buesche und ein paar kleine Baeume am Dorfrand
	local occupied: { Zone } = {
		{ x = 0, z = 0, r = 36 },
		{ x = SHRINE_POS.X - L.X, z = SHRINE_POS.Z - L.Z, r = 14 },
		{ x = TRAIN_POS.X - L.X, z = TRAIN_POS.Z - L.Z, r = 21 },
		{ x = CAMP_POS.X - L.X, z = CAMP_POS.Z - L.Z, r = 9 },
		{ x = -64, z = 8, r = 7 },
		{ x = -63, z = 36, r = 7 },
		{ x = -40, z = 42, r = 7 },
		{ x = 40, z = 14, r = 8 },
		{ x = 34, z = 38, r = 8 },
		{ x = -62, z = -58, r = 11 },
		{ x = 74, z = -4, r = 11 },
		{ x = 22, z = 70, r = 11 },
		{ x = 0, z = -52, r = 10 },
		{ x = 9, z = -40, r = 4 },
		{ x = -56, z = 28, r = 4 },
		{ x = -34, z = 24, r = 3 },
	}
	local lr = Random.new(777)
	local nature = Make("Folder", { Name = "LobbyNature", Parent = lobby })
	local function freeSpot(minR: number, maxR: number, clearance: number): Vector3?
		for _ = 1, 30 do
			local a = lr:NextNumber(0, TAU)
			local d = lr:NextNumber(minR, maxR)
			local x, z = math.cos(a) * d, math.sin(a) * d
			local ok = true
			for _, o in occupied do
				if (x - o.x) ^ 2 + (z - o.z) ^ 2 < (o.r + clearance) ^ 2 then
					ok = false
					break
				end
			end
			if ok and not nearSegment(L.X + x, L.Z + z, clearance) then
				table.insert(occupied, { x = x, z = z, r = clearance })
				return at(x, z)
			end
		end
		return nil
	end
	for i = 1, 9 do
		local pos = freeSpot(56, 92, 7)
		if pos then
			leafTree(nature, pos, lr:NextNumber(0.75, 0.95), lr, i % 4 == 0)
		end
	end
	for _ = 1, 18 do
		local pos = freeSpot(38, 92, 2.5)
		if pos then
			bush(nature, pos, lr:NextNumber(0.7, 1), lr)
		end
	end
	for _ = 1, 14 do
		local pos = freeSpot(36, 90, 2.2)
		if pos then
			flowers(nature, pos, lr)
		end
	end
	for _ = 1, 5 do
		local pos = freeSpot(50, 95, 5)
		if pos then
			boulder(nature, pos, lr:NextNumber(0.5, 0.8), lr)
		end
	end

	local spawnLook = CFrame.lookAt(SPAWN_POS + Vector3.new(0, 3.5, 0), at(0, 0, 3.5))
	return spawnLook, dummySpots
end

-- =============================================================================
-- Arena: alte Steinruine (Kolosseum)
-- =============================================================================

local function buildArena(map: Instance): { CFrame }
	local arena = Make("Folder", { Name = "Arena", Parent = map })
	local top = A.Y
	local function polar(a: number, r: number, y: number): Vector3
		return Vector3.new(A.X + math.cos(a) * r, y, A.Z + math.sin(a) * r)
	end
	local function radialCF(a: number, r: number, y: number): CFrame
		-- lokale Z-Achse zeigt nach aussen/innen, X laeuft tangential
		return CFrame.lookAt(polar(a, r, y), Vector3.new(A.X, y, A.Z))
	end

	-- Boden: grosse Steinplatte, 1 Stud ueber der Wiese (eine Stufe, die man hochlaufen kann)
	block(arena, {
		Name = "ArenaFloor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(6, AR * 2, AR * 2),
		CFrame = CFrame.new(A.X, top - 3, A.Z) * UPRIGHT,
		Material = M.Slate,
		Color = C(160, 152, 138),
		CanCollide = true,
	})
	local inlayY = top - 0.07 -- Oberkante der Einlagen: top + 0.08
	-- Randband aus grossen Platten
	local bandN = 40
	for i = 1, bandN do
		local a = (i / bandN) * TAU
		block(arena, {
			Size = Vector3.new(2 * math.pi * 74 / bandN - 0.25, 0.3, 7.6),
			CFrame = radialCF(a, 74, inlayY),
			Material = M.Slate,
			Color = if i % 2 == 0 then C(134, 128, 118) else C(124, 118, 108),
		})
	end
	-- Siegel in der Mitte
	pillar(arena, Vector3.new(A.X, inlayY - 0.15, A.Z), 0.3, 22, { Material = M.Slate, Color = C(192, 182, 160) })
	pillar(arena, Vector3.new(A.X, top - 0.18, A.Z), 0.3, 6, { Material = M.Metal, Color = PAL.Bronze })
	for i = 1, 24 do
		local a = (i / 24) * TAU
		block(arena, {
			Size = Vector3.new(2 * math.pi * 14.5 / 24 - 0.2, 0.3, 2),
			CFrame = radialCF(a, 14.5, inlayY),
			Material = M.Slate,
			Color = C(112, 106, 98),
		})
	end
	for i = 1, 8 do
		local a = (i / 8) * TAU + math.pi / 8
		block(arena, {
			Size = Vector3.new(0.9, 0.3, 12),
			CFrame = radialCF(a, 22, inlayY),
			Material = M.Slate,
			Color = C(118, 112, 104),
		})
	end
	-- abgenutzte Platten (ueberlappen sich nicht)
	local worn: { Vector3 } = {}
	for _ = 1, 40 do
		if #worn >= 16 then
			break
		end
		local a = rng:NextNumber(0, TAU)
		local r = rng:NextNumber(31, 66)
		local pos = polar(a, r, top - 0.1)
		local free = true
		for _, w in worn do
			if (w - pos).Magnitude < 7 then
				free = false
				break
			end
		end
		if free then
			table.insert(worn, pos)
			block(arena, {
				Size = Vector3.new(rng:NextNumber(2, 4.5), 0.3, rng:NextNumber(2, 4.5)),
				CFrame = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0),
				Material = M.Slate,
				Color = jitter(C(146, 138, 124), 0.06, rng),
			})
		end
	end
	-- Grasbueschel am Rand
	for _ = 1, 16 do
		local a = rng:NextNumber(0, TAU)
		block(arena, {
			Size = Vector3.new(rng:NextNumber(1, 1.8), 0.4, rng:NextNumber(0.8, 1.3)),
			CFrame = CFrame.new(polar(a, rng:NextNumber(75.5, 77.2), top + 0.1)) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0),
			Material = M.LeafyGrass,
			Color = PAL.Moss,
			CanQuery = false,
			CastShadow = false,
		})
	end

	-- Eingaenge in vier Richtungen (Sueden zeigt zur Lobby)
	local entrances = { 0, math.pi / 2, math.pi, math.pi * 1.5 }
	local function nearEntrance(a: number, width: number): boolean
		for _, e in entrances do
			local d = math.abs(((a - e + math.pi) % TAU) - math.pi)
			if d < width then
				return true
			end
		end
		return false
	end

	-- Niedrige, verfallene Ringmauer
	local wallN = 48
	local wallR = AR + 3.5
	for i = 1, wallN do
		local a = (i / wallN) * TAU
		if nearEntrance(a, math.rad(7)) then
			continue
		end
		if rng:NextNumber() < 0.24 then
			-- eingestuerzt: nur Geroell
			for _ = 1, 2 do
				local s = rng:NextNumber(1.2, 2.4)
				block(arena, {
					Size = Vector3.new(s * 1.3, s * 0.8, s),
					CFrame = CFrame.new(polar(a + rng:NextNumber(-0.05, 0.05), wallR + rng:NextNumber(-2, 2), GROUND + s * 0.3))
						* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, TAU), rng:NextNumber(-0.4, 0.4)),
					Material = M.Slate,
					Color = jitter(PAL.Stone, 0.08, rng),
					CanCollide = true,
				})
			end
			continue
		end
		local h = rng:NextNumber(2.5, 6.5)
		local segLen = 2 * math.pi * wallR / wallN
		local seg = block(arena, {
			Size = Vector3.new(segLen - 0.2, h + 0.5, 2.6),
			CFrame = radialCF(a, wallR, GROUND - 0.5 + (h + 0.5) / 2) * CFrame.Angles(0, rng:NextNumber(-0.03, 0.03), 0),
			Material = M.Slate,
			Color = jitter(PAL.Stone, 0.07, rng),
			CanCollide = true,
		})
		local roll = rng:NextNumber()
		if roll < 0.3 then
			block(arena, {
				Size = Vector3.new(rng:NextNumber(3, 7), 0.35, 2.75),
				CFrame = seg.CFrame * CFrame.new(rng:NextNumber(-1.5, 1.5), (h + 0.5) / 2 + 0.1, 0),
				Material = M.LeafyGrass,
				Color = PAL.Moss,
				CanQuery = false,
			})
		elseif roll < 0.55 then
			local bh = rng:NextNumber(1.2, 2)
			block(arena, {
				Size = Vector3.new(rng:NextNumber(2, 4), bh, 2.4),
				CFrame = seg.CFrame * CFrame.new(rng:NextNumber(-2.5, 2.5), (h + 0.5) / 2 + bh / 2, 0),
				Material = M.Slate,
				Color = jitter(PAL.Stone, 0.07, rng),
				CanCollide = true,
			})
		end
	end

	-- Zuschauerraenge (stellenweise eingestuerzt)
	local collapsed: { { number } } = {}
	for _ = 1, 3 do
		table.insert(collapsed, { rng:NextNumber(0, TAU), math.rad(rng:NextNumber(12, 20)) })
	end
	local function isCollapsed(a: number): boolean
		for _, c in collapsed do
			if math.abs(((a - c[1] + math.pi) % TAU) - math.pi) < c[2] then
				return true
			end
		end
		return false
	end
	for tier = 1, 3 do
		local r = AR + 9 + (tier - 1) * 4.6
		local h = 1.6 * tier
		local n = 52
		for i = 1, n do
			local a = (i / n) * TAU
			if nearEntrance(a, math.rad(8)) or isCollapsed(a + tier * 0.05) then
				continue
			end
			block(arena, {
				Size = Vector3.new(2 * math.pi * r / n + 0.15, h + 0.5, 4.8),
				CFrame = radialCF(a, r, GROUND - 0.5 + (h + 0.5) / 2),
				Material = M.Slate,
				Color = jitter(C(150, 144, 132), 0.06, rng),
				CanCollide = true,
			})
		end
	end

	-- Torboegen aussen herum, einige eingestuerzt; Banner an den intakten
	local archR = AR + 28
	local bannerCount = 0
	for i = 0, 11 do
		local a = ((i + 0.5) / 12) * TAU
		local cf = radialCF(a, archR, GROUND)
		local broken = rng:NextNumber() < 0.33
		local heights = { 15, 15 }
		if broken then
			heights[rng:NextInteger(1, 2)] = rng:NextNumber(5, 9)
		end
		for k, x in { -3.8, 3.8 } do
			block(arena, {
				Size = Vector3.new(2.6, heights[k] + 0.5, 2.6),
				CFrame = cf * CFrame.new(x, (heights[k] + 0.5) / 2 - 0.5, 0),
				Material = M.Slate,
				Color = jitter(C(164, 156, 142), 0.05, rng),
				CanCollide = true,
			})
		end
		if broken then
			block(arena, {
				Size = Vector3.new(10.4, 2.2, 3),
				CFrame = cf * CFrame.new(rng:NextNumber(-3, 3), 1.1, rng:NextNumber(5, 8)) * CFrame.Angles(0, rng:NextNumber(-0.6, 0.6), rng:NextNumber(-0.15, 0.15)),
				Material = M.Slate,
				Color = C(150, 142, 130),
				CanCollide = true,
			})
		else
			block(arena, {
				Size = Vector3.new(10.4, 2.2, 3),
				CFrame = cf * CFrame.new(0, 15.6, 0),
				Material = M.Slate,
				Color = C(156, 148, 134),
				CanCollide = true,
			})
			if bannerCount < 6 then
				bannerCount += 1
				local cloth = CLOTH[(bannerCount % 2) + 1]
				-- Banner haengt auf der Innenseite (lokal -Z zeigt zur Mitte)
				local bcf = cf * CFrame.new(0, 10.6, -1.65)
				block(arena, { Size = Vector3.new(3.6, 7.6, 0.14), CFrame = bcf, Material = M.Fabric, Color = cloth, CanQuery = false })
				block(arena, { Size = Vector3.new(3.8, 0.35, 0.3), CFrame = bcf * CFrame.new(0, 3.7, 0), Material = M.Metal, Color = PAL.Gold, CanQuery = false })
				block(arena, {
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(0.18, 1.8, 1.8),
					CFrame = bcf * CFrame.new(0, 0.6, -0.1) * CFrame.Angles(0, math.rad(90), 0),
					Material = M.Metal,
					Color = PAL.Gold,
					CanQuery = false,
				})
			end
		end
	end

	-- Feuerschalen am Rand der Kampfflaeche
	for i = 0, 7 do
		local a = (i / 8) * TAU + math.pi / 8
		local base = polar(a, AR - 3, top)
		pillar(arena, base, 3, 1.7, { Material = M.Slate, Color = PAL.StoneDark, CanCollide = true })
		local bowl = pillar(arena, base + Vector3.new(0, 3, 0), 0.7, 2.6, { Material = M.Metal, Color = PAL.Iron, CanCollide = true })
		local fireHolder = block(arena, { Size = Vector3.new(0.5, 0.2, 0.5), CFrame = bowl.CFrame * CFrame.new(0.45, 0, 0), Transparency = 1, CanQuery = false, CastShadow = false })
		addFire(fireHolder, 0.75, i % 2 == 0)
	end

	-- Deckung: alte Saeulen (teils abgebrochen), umgestuerzte Saeulentrommeln, niedrige Mauerreste
	local colHeights = { 14, 6, 11, 8, 13, 5 }
	for i = 1, 6 do
		local a = math.rad(15 + (i - 1) * 60)
		local base = polar(a, 44, top)
		local H = colHeights[i]
		block(arena, { Size = Vector3.new(5.6, 1, 5.6), CFrame = CFrame.new(base + Vector3.new(0, 0.3, 0)), Material = M.Slate, Color = PAL.StoneDark, CanCollide = true })
		pillar(arena, base + Vector3.new(0, 0.8, 0), H, 4, { Material = M.Slate, Color = jitter(C(176, 168, 152), 0.04, rng), CanCollide = true })
		if H >= 10 then
			block(arena, { Size = Vector3.new(5, 1, 5), CFrame = CFrame.new(base + Vector3.new(0, 0.8 + H + 0.5, 0)), Material = M.Slate, Color = PAL.StoneLight, CanCollide = true })
		else
			block(arena, {
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1.6, 4, 4),
				CFrame = CFrame.new(base + Vector3.new(0.4, 0.8 + H + 0.5, 0)) * CFrame.Angles(0.25, 0, math.rad(90) + 0.2),
				Material = M.Slate,
				Color = C(170, 162, 146),
				CanCollide = true,
			})
		end
		if i % 2 == 0 then
			local drumBase = polar(a + 0.16, 37, top + 1.9)
			local da = rng:NextNumber(0, TAU)
			local dir = Vector3.new(math.cos(da), 0, math.sin(da))
			local len = rng:NextNumber(6, 8)
			rod(arena, drumBase - dir * len / 2, drumBase + dir * len / 2, 3.8, { Material = M.Slate, Color = C(168, 160, 146), CanCollide = true })
		end
	end
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		local cf = radialCF(a, 29, top + 1.4)
		block(arena, { Size = Vector3.new(9, 3, 1.8), CFrame = cf, Material = M.Slate, Color = jitter(PAL.Stone, 0.05, rng), CanCollide = true })
		block(arena, {
			Size = Vector3.new(3.2, 1.2, 1.8),
			CFrame = cf * CFrame.new(if i % 2 == 0 then 2.9 else -2.9, 2.1, 0),
			Material = M.Slate,
			Color = jitter(PAL.Stone, 0.05, rng),
			CanCollide = true,
		})
	end

	-- Startpunkte im Kreis, Blick zur Mitte
	local spawns = {}
	for i = 1, 12 do
		local a = (i / 12) * TAU
		local pos = polar(a, 60, top + 3.2)
		table.insert(spawns, CFrame.lookAt(pos, Vector3.new(A.X, pos.Y, A.Z)))
	end
	return spawns
end

-- =============================================================================
-- Tal: Weg-Laternen, Wachturm, Ruinen, Steg, Natur
-- =============================================================================

local function snap(pos: Vector3): Vector3
	local y = groundAt(pos.X, pos.Z)
	return Vector3.new(pos.X, y, pos.Z)
end

local function buildValleyProps(map: Instance)
	local valley = Make("Folder", { Name = "Valley", Parent = map })

	-- Laternen am Hauptweg (abwechselnd links/rechts)
	local travelled, nextAt, side = 0, 45, 1
	for i = 1, #MAIN_PATH - 1 do
		local a, b = MAIN_PATH[i], MAIN_PATH[i + 1]
		local seg = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local len = seg.Magnitude
		while nextAt <= travelled + len and len > 0 do
			local p = a + seg.Unit * (nextAt - travelled)
			local perp = Vector3.new(-seg.Unit.Z, 0, seg.Unit.X) * side
			local pos = snap(p + perp * 7)
			if (pos - A).Magnitude > AR + 45 then
				lantern(valley, flatLook(pos, p), 7.5)
			end
			side = -side
			nextAt += 75
		end
		travelled += len
	end

	-- Holz-Wachturm
	do
		local base = snap(TOWER_POS)
		local tower = Make("Model", { Name = "Watchtower", Parent = valley })
		for _, x in { -3, 3 } do
			for _, z in { -3, 3 } do
				block(tower, { Size = Vector3.new(1, 20, 1), CFrame = CFrame.new(base + Vector3.new(x, 9, z)), Material = M.Wood, Color = PAL.WoodDark, CanCollide = true })
			end
		end
		for _, side2 in { -3, 3 } do
			rod(tower, base + Vector3.new(-3, 2, side2), base + Vector3.new(3, 12, side2), 0.4, { Material = M.Wood, Color = PAL.Wood })
			rod(tower, base + Vector3.new(side2, 2, -3), base + Vector3.new(side2, 12, 3), 0.4, { Material = M.Wood, Color = PAL.Wood })
		end
		block(tower, { Size = Vector3.new(8.4, 0.8, 8.4), CFrame = CFrame.new(base + Vector3.new(0, 15.4, 0)), Material = M.WoodPlanks, Color = PAL.Plank, CanCollide = true })
		for _, r2 in { { 0, -3.9, 8.4, 0.3 }, { 0, 3.9, 8.4, 0.3 }, { -3.9, 0, 0.3, 8.4 }, { 3.9, 0, 0.3, 8.4 } } do
			block(tower, { Size = Vector3.new(r2[3], 0.4, r2[4]), CFrame = CFrame.new(base + Vector3.new(r2[1], 17.6, r2[2])), Material = M.Wood, Color = PAL.Wood, CanCollide = true })
		end
		pyramid(tower, base + Vector3.new(0, 24.5, 0), 5.4, 5.6, 0, { Material = M.RoofShingles, Color = C(118, 74, 52) })
		lantern(tower, CFrame.new(base + Vector3.new(0, 15.8, -3.6)), 2.6)
	end

	-- Ruinen auf der Wiese
	for idx, rp in RUINS do
		local base = snap(rp)
		local ruin = Make("Model", { Name = "Ruin", Parent = valley })
		local yaw = rng:NextNumber(0, TAU)
		local cf = CFrame.new(base) * CFrame.Angles(0, yaw, 0)
		local h1, h2 = rng:NextNumber(9, 12), rng:NextNumber(4, 7)
		for k, x in { -4.5, 4.5 } do
			local h = if k == 1 then h1 else h2
			block(ruin, { Size = Vector3.new(4.2, 1, 4.2), CFrame = cf * CFrame.new(x, 0.2, 0), Material = M.Slate, Color = PAL.StoneDark, CanCollide = true })
			pillar(ruin, (cf * CFrame.new(x, 0.6, 0)).Position, h, 3, { Material = M.Slate, Color = jitter(C(176, 168, 152), 0.05, rng), CanCollide = true })
		end
		if idx % 2 == 1 then
			block(ruin, {
				Size = Vector3.new(12, 1.8, 2.8),
				CFrame = cf * CFrame.new(-1.5, 1, 4.5) * CFrame.Angles(0, 0.35, 0.12),
				Material = M.Slate,
				Color = C(156, 148, 134),
				CanCollide = true,
			})
		end
		rod(ruin, (cf * CFrame.new(3, 1.4, -5)).Position, (cf * CFrame.new(8, 1.4, -3)).Position, 2.8, { Material = M.Slate, Color = C(170, 162, 148), CanCollide = true })
		block(ruin, { Size = Vector3.new(7, 2.4, 1.6), CFrame = cf * CFrame.new(-7, 1.1, -3) * CFrame.Angles(0, 0.8, 0), Material = M.Slate, Color = PAL.Stone, CanCollide = true })
		block(ruin, { Size = Vector3.new(4, 0.35, 1.7), CFrame = cf * CFrame.new(-7, 2.45, -3) * CFrame.Angles(0, 0.8, 0), Material = M.LeafyGrass, Color = PAL.Moss, CanQuery = false })
	end

	-- Holzsteg am See
	do
		local shore = Vector3.new(LAKE1.X + 58, GROUND, LAKE1.Z)
		local dock = Make("Model", { Name = "Dock", Parent = valley })
		local deckY = GROUND + 0.3
		for i = -2, 2 do
			block(dock, {
				Size = Vector3.new(24, 0.4, 1),
				CFrame = CFrame.new(shore + Vector3.new(-12, deckY - GROUND - 0.2, i * 1.15)),
				Material = M.WoodPlanks,
				Color = jitter(PAL.Plank, 0.06, rng),
				CanCollide = true,
			})
		end
		for _, x in { -3, -12, -21.5 } do
			for _, z in { -3, 3 } do
				block(dock, { Size = Vector3.new(0.8, 10, 0.8), CFrame = CFrame.new(shore + Vector3.new(x, -4.5, z)), Material = M.Wood, Color = PAL.WoodDark, CanCollide = true })
			end
		end
		lantern(dock, CFrame.new(shore + Vector3.new(-23, deckY - GROUND, 2.6)) * CFrame.Angles(0, math.rad(90), 0), 5)
		-- kleines Ruderboot
		local boatCF = CFrame.new(shore + Vector3.new(-16, -3.6, 6.5)) * CFrame.Angles(0, 0.3, 0)
		block(dock, { Size = Vector3.new(7, 1.2, 3), CFrame = boatCF, Material = M.WoodPlanks, Color = C(132, 90, 56), CanCollide = true })
		wedge(dock, boatCF * CFrame.new(-4.2, 0, 0) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(3, 1.2, 1.4), { Material = M.WoodPlanks, Color = C(132, 90, 56) })
	end

	-- Felsbrocken an der Quelle des Bachs
	for _ = 1, 4 do
		local p = STREAM[1] + Vector3.new(rng:NextNumber(-12, 12), 0, rng:NextNumber(-12, 12))
		boulder(valley, snap(p), rng:NextNumber(0.6, 1.1), rng)
	end
end

local function scatterNature(map: Instance)
	local folder = Make("Folder", { Name = "Nature", Parent = map })
	local nr = Random.new(4242)
	local placed: { Zone } = {}
	local function spaced(x: number, z: number, r: number): boolean
		for _, p in placed do
			local min = p.r + r
			if (x - p.x) ^ 2 + (z - p.z) ^ 2 < min * min then
				return false
			end
		end
		return true
	end
	-- prueft Sperrzonen, Abstand und Gelaende (kein Wasser, kein Fels, nicht zu steil)
	local function spot(x: number, z: number, r: number, maxNorm: number): Vector3?
		if valleyNorm(x, z) > maxNorm or blocked(x, z, r) or not spaced(x, z, r) then
			return nil
		end
		local y, mat, normal = groundAt(x, z)
		if mat ~= M.Grass and mat ~= M.LeafyGrass and mat ~= M.Ground then
			return nil
		end
		if normal.Y < 0.86 then
			return nil
		end
		table.insert(placed, { x = x, z = z, r = r })
		return Vector3.new(x, y, z)
	end
	local function randomPoint(): (number, number)
		return VC.X + nr:NextNumber(-VX * 1.12, VX * 1.12), VC.Z + nr:NextNumber(-VZ * 1.12, VZ * 1.12)
	end

	local made = 0
	local function tree(pos: Vector3, nearEdge: boolean)
		local roll = nr:NextNumber()
		if nearEdge or roll < 0.3 then
			pine(folder, pos, nr:NextNumber(1.05, 1.85), nr)
		elseif roll < 0.78 then
			leafTree(folder, pos, nr:NextNumber(0.95, 1.4), nr, false)
		else
			leafTree(folder, pos, nr:NextNumber(0.95, 1.25), nr, true)
		end
		made += 1
		if made % 20 == 0 then
			task.wait()
		end
	end

	-- Waldgruppen
	local clusters, tries = 0, 0
	while clusters < 12 and tries < 300 do
		tries += 1
		local cx, cz = randomPoint()
		if valleyNorm(cx, cz) < 1.05 and not blocked(cx, cz, 20) then
			clusters += 1
			local edge = valleyNorm(cx, cz) > 0.72
			local count = nr:NextInteger(5, 9)
			local planted = 0
			for _ = 1, count * 4 do
				if planted >= count then
					break
				end
				local a = nr:NextNumber(0, TAU)
				local d = nr:NextNumber(0, 46)
				local pos = spot(cx + math.cos(a) * d, cz + math.sin(a) * d, 6, 1.12)
				if pos then
					tree(pos, edge and nr:NextNumber() < 0.85)
					planted += 1
				end
			end
		end
	end
	-- einzelne Baeume, Tannen am Bergfuss
	for _ = 1, 160 do
		if made >= 100 then
			break
		end
		local x, z = randomPoint()
		local pos = spot(x, z, 6, 1.12)
		if pos then
			tree(pos, valleyNorm(x, z) > 0.85)
		end
	end
	-- Buesche, Felsen, Blumen
	local bushes, rocks, blooms = 0, 0, 0
	for _ = 1, 600 do
		if bushes >= 55 and rocks >= 42 and blooms >= 16 then
			break
		end
		local x, z = randomPoint()
		local kind = nr:NextNumber()
		if kind < 0.45 and bushes < 55 then
			local pos = spot(x, z, 3, 1.05)
			if pos then
				bush(folder, pos, nr:NextNumber(0.8, 1.3), nr)
				bushes += 1
			end
		elseif kind < 0.8 and rocks < 42 then
			local pos = spot(x, z, 5, 1.15)
			if pos then
				boulder(folder, pos, nr:NextNumber(0.6, 1.6), nr)
				rocks += 1
			end
		elseif blooms < 16 then
			local pos = spot(x, z, 3, 0.9)
			if pos then
				flowers(folder, pos, nr)
				blooms += 1
			end
		end
	end
end

-- Pruefen, wie WedgePart / CornerWedgePart im Raum liegen (Raycast gegen Testteile)
local function probeShapes(parent: Instance)
	local origin = CFrame.new(L.X, GROUND + 3000, L.Z + 6000)
	local w = shape("WedgePart", parent, { Size = Vector3.new(4, 4, 4), CFrame = origin, Transparency = 1 })
	local cw = shape("CornerWedgePart", parent, { Size = Vector3.new(4, 4, 4), CFrame = origin * CFrame.new(30, 0, 0), Transparency = 1 })
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { w, cw }
	local function hitY(part: BasePart, lx: number, lz: number): number?
		local o = part.CFrame * Vector3.new(lx, 6, lz)
		local res = workspace:Raycast(o, Vector3.new(0, -12, 0), params)
		return if res then res.Position.Y else nil
	end
	pcall(function()
		local front, back = hitY(w, 0, -1.6), hitY(w, 0, 1.6)
		if front and back and math.abs(front - back) > 0.5 then
			WEDGE_FLIP = front > back
		end
		local best, bestY = APEX, -math.huge
		for _, sx in { 1, -1 } do
			for _, sz in { 1, -1 } do
				local y = hitY(cw, sx * 1.6, sz * 1.6)
				if y and y > bestY then
					bestY = y
					best = Vector3.new(sx, 0, sz)
				end
			end
		end
		if bestY > -math.huge then
			APEX = best
		end
	end)
	w:Destroy()
	cw:Destroy()
end

local function registerZones()
	addZone(L, 100)
	addZone(A, AR + 50)
	addZone(LAKE1, 70)
	addZone(LAKE2, 56)
	addZone(TOWER_POS, 14)
	for _, rp in RUINS do
		addZone(rp, 16)
	end
	addZone(MENU_CAM, 30)
	addPolyline(MAIN_PATH, 9)
	addPolyline(WEST_PATH, 7)
	addPolyline(SHRINE_PATH, 5)
	addPolyline(EAST_PATH, 5)
	addPolyline(SOUTH_PATH, 5)
	addPolyline(STREAM, 9)
	-- freie Sicht fuer die Menue-Kamera (auf den Dorfplatz und ueber den See)
	addPolyline({ MENU_CAM, MENU_FOCUS }, 24)
	addPolyline({ MENU_CAM, LAKE1 }, 22)
end

-- =============================================================================
-- Start
-- =============================================================================

function WorldBuilder.Build(): WorldInfo
	setupLighting()
	setupTerrainLook()
	local existing = workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end
	local map = Make("Folder", { Name = "Map", Parent = workspace })
	registerZones()
	probeShapes(map)

	-- 1) Boden zuerst, damit frueh joinende Spieler nicht fallen
	buildBaseGround()
	local lobbySpawn, dummySpots = buildLobby(map)
	task.wait()
	local arenaSpawns = buildArena(map)
	task.wait()

	-- 2) Landschaft
	buildMeadowPatches()
	buildHills()
	task.wait()
	buildLake()
	buildPaths()
	task.wait()
	buildMountains()

	-- 3) Deko im Tal, dann die Natur verteilen (braucht fertiges Terrain fuer Raycasts)
	buildValleyProps(map)
	task.wait()
	scatterNature(map)

	-- Kamera fuer das Startmenue: Blick ueber das Dorf, den See und die Berge
	local cam = block(map, {
		Name = "MenuCamera",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.lookAt(MENU_CAM, MENU_FOCUS),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	cam:SetAttribute("MenuFocus", MENU_FOCUS)

	return {
		LobbySpawn = lobbySpawn,
		ArenaSpawns = arenaSpawns,
		DummySpots = dummySpots,
		LobbyCenter = L,
		ArenaCenter = A,
		ArenaRadius = AR,
	}
end

return WorldBuilder
