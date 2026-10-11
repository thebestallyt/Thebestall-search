-- Baut die komplette Welt per Code: Licht, Lobby (schwebende Insel) und Arena.
-- So funktioniert das Spiel ohne vorgefertigte Map-Dateien direkt nach dem Start.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Make = require(Shared:WaitForChild("Make"))
local Config = require(Shared:WaitForChild("Config"))

local WorldBuilder = {}

local rng = Random.new(1337)

local COLORS = {
	Floor = Color3.fromRGB(34, 30, 52),
	FloorDark = Color3.fromRGB(22, 19, 34),
	Rock = Color3.fromRGB(28, 24, 40),
	Cyan = Color3.fromRGB(0, 225, 255),
	Magenta = Color3.fromRGB(255, 60, 200),
	Purple = Color3.fromRGB(150, 70, 255),
	Gold = Color3.fromRGB(255, 200, 70),
}

export type WorldInfo = {
	LobbySpawn: CFrame,
	ArenaSpawns: { CFrame },
	DummySpots: { CFrame },
	LobbyCenter: Vector3,
	ArenaCenter: Vector3,
	ArenaRadius: number,
}

-- Hilfsfunktionen ---------------------------------------------------------

local function block(parent: Instance, props: { [string]: any }): Part
	local p = Make("Part", {
		Anchored = true,
		CanCollide = true,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		Material = Enum.Material.Slate,
		Color = COLORS.Floor,
		Parent = parent,
	})
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function neon(parent: Instance, props: { [string]: any }): Part
	local p = block(parent, props)
	p.Material = Enum.Material.Neon
	p.CanCollide = props.CanCollide == true
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

-- Zylinder-Scheibe, deren Oberseite auf "top" liegt
local function disc(parent: Instance, top: Vector3, radius: number, height: number, props: { [string]: any }?): Part
	local p = block(parent, props or {})
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(height, radius * 2, radius * 2)
	p.CFrame = CFrame.new(top - Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	return p
end

-- Ring aus Bloecken um "center" (liegend)
local function ring(
	parent: Instance,
	center: Vector3,
	radius: number,
	width: number,
	height: number,
	segments: number,
	props: { [string]: any },
	isNeon: boolean?
): { Part }
	local parts = {}
	local segLen = (2 * math.pi * radius / segments) * 1.04
	for i = 1, segments do
		local a = (i / segments) * math.pi * 2
		local pos = center + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
		local p = if isNeon then neon(parent, props) else block(parent, props)
		p.Size = Vector3.new(segLen, height, width)
		p.CFrame = CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z))
		table.insert(parts, p)
	end
	return parts
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	return Make("PointLight", {
		Color = color,
		Range = range,
		Brightness = brightness,
		Shadows = false,
		Parent = parent,
	})
end

local function floatingIsland(parent: Instance, top: Vector3, radius: number)
	-- Unterseite der Insel: gestapelte, schmaler werdende Felsen
	local layers = {
		{ r = 0.92, h = 9 },
		{ r = 0.72, h = 12 },
		{ r = 0.5, h = 14 },
		{ r = 0.28, h = 16 },
		{ r = 0.12, h = 14 },
	}
	local y = top.Y - 6
	for _, layer in layers do
		disc(parent, Vector3.new(top.X, y, top.Z), radius * layer.r, layer.h, {
			Material = Enum.Material.Rock,
			Color = COLORS.Rock,
			CanCollide = false,
		})
		y -= layer.h
	end
	-- Haengende Kristalle
	for _ = 1, 14 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(0.2, 0.8) * radius
		local len = rng:NextNumber(8, 22)
		local c = neon(parent, {
			Size = Vector3.new(2.2, len, 2.2),
			Color = if rng:NextNumber() > 0.5 then COLORS.Cyan else COLORS.Magenta,
			Transparency = 0.15,
		})
		c.CFrame = CFrame.new(top + Vector3.new(math.cos(a) * d, -10 - len / 2 - (1 - d / radius) * 20, math.sin(a) * d))
			* CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, math.pi), rng:NextNumber(-0.25, 0.25))
			* CFrame.Angles(0, math.rad(45), 0)
	end
end

local function floatingRocks(parent: Instance, center: Vector3, minR: number, maxR: number, count: number)
	for _ = 1, count do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(minR, maxR)
		local s = rng:NextNumber(4, 13)
		local model = Make("Model", { Name = "FloatingRock", Parent = parent })
		local rock = block(model, {
			Size = Vector3.new(s, s * rng:NextNumber(0.6, 1.1), s * rng:NextNumber(0.7, 1.2)),
			Material = Enum.Material.Rock,
			Color = COLORS.Rock,
			CanCollide = false,
			CanQuery = false,
		})
		rock.CFrame = CFrame.new(center + Vector3.new(math.cos(a) * d, rng:NextNumber(-25, 30), math.sin(a) * d))
			* CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6))
		model.PrimaryPart = rock
		if rng:NextNumber() > 0.45 then
			local crystal = neon(model, {
				Size = Vector3.new(1.6, s * 0.9, 1.6),
				Color = if rng:NextNumber() > 0.5 then COLORS.Cyan else COLORS.Purple,
			})
			crystal.CFrame = rock.CFrame * CFrame.new(0, s * 0.5, 0) * CFrame.Angles(0.3, 0, 0.2)
		end
		CollectionService:AddTag(model, "Float")
	end
end

local function billboard(parent: BasePart, text: string, color: Color3, offset: number, size: number?)
	local gui = Make("BillboardGui", {
		Size = UDim2.fromScale(size or 14, (size or 14) * 0.25),
		StudsOffset = Vector3.new(0, offset, 0),
		AlwaysOnTop = false,
		LightInfluence = 0,
		MaxDistance = 160,
		Parent = parent,
	})
	Make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = text,
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
		TextColor3 = color,
		TextStrokeTransparency = 0.4,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		Parent = gui,
	})
	return gui
end

-- Dekorative Kiste (die echte Kisten-Animation baut der Client selbst)
local function decorCrate(parent: Instance, cf: CFrame, scale: number, bodyColor: Color3, trimColor: Color3): Model
	local model = Make("Model", { Name = "DecorCrate", Parent = parent })
	local body = block(model, {
		Name = "Body",
		Size = Vector3.new(4, 3, 3) * scale,
		CFrame = cf,
		Material = Enum.Material.Metal,
		Color = bodyColor,
		CanCollide = false,
	})
	model.PrimaryPart = body
	local lid = block(model, {
		Size = Vector3.new(4.2, 0.9, 3.2) * scale,
		CFrame = cf * CFrame.new(0, 1.9 * scale, 0),
		Material = Enum.Material.Metal,
		Color = bodyColor:Lerp(Color3.new(1, 1, 1), 0.08),
		CanCollide = false,
	})
	for _, x in { -1.6, 1.6 } do
		neon(model, { Size = Vector3.new(0.3, 3.1, 3.1) * scale, CFrame = cf * CFrame.new(x * scale, 0, 0), Color = trimColor })
	end
	neon(model, { Size = Vector3.new(4.25, 0.25, 3.25) * scale, CFrame = cf * CFrame.new(0, 1.45 * scale, 0), Color = trimColor })
	neon(model, { Size = Vector3.new(0.8, 0.8, 0.25) * scale, CFrame = cf * CFrame.new(0, 1.2 * scale, -1.6 * scale), Color = COLORS.Gold })
	light(body, trimColor, 18, 2)
	local _ = lid
	return model
end

-- Licht & Atmosphaere ------------------------------------------------------

local function setupLighting()
	Lighting.ClockTime = 0.5
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(30, 26, 52)
	Lighting.OutdoorAmbient = Color3.fromRGB(80, 66, 120)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true

	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end

	Make("Atmosphere", {
		Density = 0.3,
		Offset = 0.12,
		Color = Color3.fromRGB(130, 100, 210),
		Decay = Color3.fromRGB(50, 26, 96),
		Glare = 0.35,
		Haze = 1.4,
		Parent = Lighting,
	})
	Make("Sky", {
		StarCount = 6000,
		CelestialBodiesShown = true,
		MoonAngularSize = 16,
		Parent = Lighting,
	})
	Make("BloomEffect", { Name = "NovaBloom", Intensity = 1.1, Size = 30, Threshold = 0.86, Parent = Lighting })
	Make("ColorCorrectionEffect", {
		Name = "NovaColor",
		Brightness = 0.03,
		Contrast = 0.12,
		Saturation = 0.2,
		TintColor = Color3.fromRGB(242, 236, 255),
		Parent = Lighting,
	})
	Make("SunRaysEffect", { Intensity = 0.05, Spread = 0.6, Parent = Lighting })
end

-- Lobby -------------------------------------------------------------------

local function buildLobby(map: Instance): (CFrame, { CFrame })
	local L = Config.World.LobbyCenter
	local R = Config.World.LobbyRadius
	local lobby = Make("Folder", { Name = "Lobby", Parent = map })

	disc(lobby, L, R, 6, { Name = "Floor", Material = Enum.Material.Slate, Color = COLORS.Floor })
	floatingIsland(lobby, L, R)

	-- Randbeleuchtung
	ring(lobby, L + Vector3.new(0, 0.1, 0), R - 0.6, 0.9, 0.5, 56, { Color = COLORS.Cyan }, true)
	ring(lobby, L + Vector3.new(0, -3, 0), R + 0.3, 0.6, 0.6, 56, { Color = COLORS.Magenta, Transparency = 0.2 }, true)

	-- Bodenmuster
	ring(lobby, L + Vector3.new(0, 0.03, 0), 22, 0.35, 0.1, 40, { Color = COLORS.Cyan, Transparency = 0.25 }, true)
	ring(lobby, L + Vector3.new(0, 0.03, 0), 46, 0.35, 0.1, 64, { Color = COLORS.Magenta, Transparency = 0.25 }, true)
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2 + math.pi / 8
		local mid = L + Vector3.new(math.cos(a) * 34, 0.03, math.sin(a) * 34)
		local line = neon(lobby, { Size = Vector3.new(0.3, 0.1, 23), Color = COLORS.Purple, Transparency = 0.35 })
		line.CFrame = CFrame.lookAt(mid, Vector3.new(L.X, mid.Y, L.Z))
	end

	-- Kisten-Altar in der Mitte
	local altarTop = L + Vector3.new(0, 2, 0)
	local altar = disc(lobby, altarTop, 8, 2, { Name = "CrateAltar", Material = Enum.Material.Marble, Color = COLORS.FloorDark })
	ring(lobby, altarTop + Vector3.new(0, 0.05, 0), 7.6, 0.5, 0.15, 32, { Color = COLORS.Gold }, true)
	local crate = decorCrate(lobby, CFrame.new(altarTop + Vector3.new(0, 4.5, 0)), 1.5, Color3.fromRGB(52, 56, 84), COLORS.Cyan)
	CollectionService:AddTag(crate, "Float")
	CollectionService:AddTag(crate, "Spin")
	local prompt = Make("ProximityPrompt", {
		Name = "OpenCrates",
		ActionText = "Open Crates",
		ObjectText = "Crate Altar",
		KeyboardKeyCode = Enum.KeyCode.E,
		HoldDuration = 0,
		MaxActivationDistance = 14,
		RequiresLineOfSight = false,
		Parent = altar,
	})
	local _ = prompt
	billboard(altar, "🎁 CRATES", COLORS.Gold, 11, 12)

	-- Schwarzes-Loch-Schrein (Robux Shop)
	local shrinePos = L + Vector3.new(38, 0, -26)
	local shrine = disc(lobby, shrinePos + Vector3.new(0, 1.5, 0), 7, 1.5, {
		Name = "BlackHoleShrine",
		Material = Enum.Material.Basalt,
		Color = Color3.fromRGB(14, 10, 22),
	})
	ring(lobby, shrinePos + Vector3.new(0, 1.55, 0), 6.6, 0.45, 0.15, 30, { Color = COLORS.Purple }, true)
	local core = block(lobby, {
		Name = "HoleCore",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(5, 5, 5),
		CFrame = CFrame.new(shrinePos + Vector3.new(0, 8, 0)),
		Color = Color3.new(0, 0, 0),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	local glow = neon(lobby, {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(6.4, 6.4, 6.4),
		CFrame = core.CFrame,
		Color = COLORS.Purple,
		Transparency = 0.65,
	})
	local diskModel = Make("Model", { Name = "HoleDisk", Parent = lobby })
	local diskParts = ring(diskModel, Vector3.zero, 6.5, 1.4, 0.15, 28, { Color = Color3.fromRGB(255, 140, 50) }, true)
	local diskRoot = neon(diskModel, { Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CFrame = CFrame.new() })
	diskModel.PrimaryPart = diskRoot
	local _d = diskParts
	diskModel:PivotTo(CFrame.new(shrinePos + Vector3.new(0, 8, 0)) * CFrame.Angles(math.rad(18), 0, math.rad(8)))
	CollectionService:AddTag(diskModel, "Spin")
	light(core, COLORS.Purple, 24, 3)
	local _g = glow
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
	billboard(shrine, "🕳️ BLACK HOLE", Color3.fromRGB(200, 150, 255), 14, 12)

	-- Trainingsplatz
	local trainCenter = L + Vector3.new(-36, 0, -22)
	block(lobby, {
		Name = "TrainingPad",
		Size = Vector3.new(30, 0.4, 22),
		CFrame = CFrame.new(trainCenter + Vector3.new(0, 0.2, 0)),
		Material = Enum.Material.Concrete,
		Color = COLORS.FloorDark,
	})
	for _, off in { Vector3.new(15, 0, 0), Vector3.new(-15, 0, 0) } do
		neon(lobby, { Size = Vector3.new(0.4, 0.5, 22), CFrame = CFrame.new(trainCenter + off + Vector3.new(0, 0.3, 0)), Color = COLORS.Gold })
	end
	for _, off in { Vector3.new(0, 0, 11), Vector3.new(0, 0, -11) } do
		neon(lobby, { Size = Vector3.new(30, 0.5, 0.4), CFrame = CFrame.new(trainCenter + off + Vector3.new(0, 0.3, 0)), Color = COLORS.Gold })
	end
	local sign = block(lobby, {
		Size = Vector3.new(1, 1, 1),
		Transparency = 1,
		CanCollide = false,
		CFrame = CFrame.new(trainCenter + Vector3.new(0, 1, -11)),
	})
	billboard(sign, "🎯 TRAINING DUMMIES", COLORS.Gold, 7, 14)

	local dummySpots = {}
	for i = -1, 1 do
		local pos = trainCenter + Vector3.new(i * 8, 3.5, -4)
		table.insert(dummySpots, CFrame.lookAt(pos, pos + Vector3.new(0, 0, 1)))
	end

	-- Arena-Portal (Deko)
	local portalPos = L + Vector3.new(0, 11, -54)
	local portal = Make("Model", { Name = "ArenaPortal", Parent = lobby })
	local segs = 36
	for i = 1, segs do
		local a = (i / segs) * math.pi * 2
		local p = neon(portal, {
			Size = Vector3.new(1.2, 1.2, 2.2),
			Color = COLORS.Purple:Lerp(COLORS.Magenta, (math.sin(a * 2) + 1) / 2),
		})
		p.CFrame = CFrame.new(portalPos + Vector3.new(math.cos(a) * 10, math.sin(a) * 10, 0)) * CFrame.Angles(0, 0, a)
	end
	local inner = neon(portal, {
		Name = "PortalInner",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 19, 19),
		CFrame = CFrame.new(portalPos) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(90, 30, 170),
		Transparency = 0.45,
	})
	light(inner, COLORS.Purple, 30, 3)
	Make("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(COLORS.Magenta, COLORS.Cyan),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(1.2, 2),
		Rate = 30,
		Speed = NumberRange.new(-6, -3),
		Shape = Enum.ParticleEmitterShape.Disc,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		LightEmission = 1,
		Parent = inner,
	})
	block(portal, {
		Size = Vector3.new(14, 2, 6),
		CFrame = CFrame.new(L + Vector3.new(0, 1, -54)),
		Material = Enum.Material.Basalt,
		Color = COLORS.FloorDark,
	})
	billboard(inner, "⚔️ ARENA", COLORS.Magenta, 14, 12)

	-- Saeulen mit Kristallen am Rand
	for i = 1, 10 do
		local a = (i / 10) * math.pi * 2 + 0.2
		local base = L + Vector3.new(math.cos(a) * (R - 8), 0, math.sin(a) * (R - 8))
		local pillar = block(lobby, {
			Size = Vector3.new(3.5, 16, 3.5),
			CFrame = CFrame.new(base + Vector3.new(0, 8, 0)),
			Material = Enum.Material.Slate,
			Color = COLORS.FloorDark,
		})
		local _ = pillar
		neon(lobby, {
			Size = Vector3.new(3.8, 0.5, 3.8),
			CFrame = CFrame.new(base + Vector3.new(0, 12, 0)),
			Color = if i % 2 == 0 then COLORS.Cyan else COLORS.Magenta,
		})
		local crystal = neon(lobby, {
			Size = Vector3.new(2, 4.5, 2),
			CFrame = CFrame.new(base + Vector3.new(0, 20, 0)) * CFrame.Angles(0, 0, math.rad(45)) * CFrame.Angles(math.rad(45), 0, 0),
			Color = if i % 2 == 0 then COLORS.Cyan else COLORS.Magenta,
		})
		light(crystal, crystal.Color, 22, 2)
		CollectionService:AddTag(crystal, "Spin")
		CollectionService:AddTag(crystal, "Float")
	end

	floatingRocks(lobby, L, R + 20, R + 70, 16)

	-- Spawn
	local spawnPos = L + Vector3.new(0, 0.2, 38)
	local spawn = Make("SpawnLocation", {
		Name = "LobbySpawn",
		Size = Vector3.new(12, 0.4, 12),
		CFrame = CFrame.new(spawnPos),
		Anchored = true,
		Neutral = true,
		Duration = 0,
		Material = Enum.Material.Neon,
		Color = COLORS.Cyan,
		Transparency = 0.55,
		TopSurface = Enum.SurfaceType.Smooth,
		Parent = lobby,
	})
	local _s = spawn
	return CFrame.lookAt(spawnPos + Vector3.new(0, 3.5, 0), L + Vector3.new(0, 3.5, 0)), dummySpots
end

-- Arena -------------------------------------------------------------------

local function buildArena(map: Instance): { CFrame }
	local A = Config.World.ArenaCenter
	local R = Config.World.ArenaRadius
	local arena = Make("Folder", { Name = "Arena", Parent = map })

	disc(arena, A, R, 8, { Name = "Floor", Material = Enum.Material.Basalt, Color = Color3.fromRGB(32, 27, 44) })
	floatingIsland(arena, A, R)

	-- Innere Kampfflaeche (leicht anders gefaerbt)
	disc(arena, A + Vector3.new(0, 0.02, 0), 40, 0.5, {
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(40, 34, 58),
	})

	-- Runen-Kreis in der Mitte
	ring(arena, A + Vector3.new(0, 0.06, 0), 12, 0.5, 0.12, 36, { Color = COLORS.Gold }, true)
	ring(arena, A + Vector3.new(0, 0.06, 0), 13.4, 0.18, 0.12, 40, { Color = COLORS.Gold, Transparency = 0.3 }, true)
	ring(arena, A + Vector3.new(0, 0.06, 0), 39.6, 0.45, 0.12, 64, { Color = COLORS.Magenta, Transparency = 0.15 }, true)
	ring(arena, A + Vector3.new(0, 0.06, 0), 62, 0.4, 0.12, 80, { Color = COLORS.Cyan, Transparency = 0.25 }, true)
	for i = 1, 12 do
		local a = (i / 12) * math.pi * 2
		local mid = A + Vector3.new(math.cos(a) * 26.5, 0.06, math.sin(a) * 26.5)
		local line = neon(arena, { Size = Vector3.new(0.25, 0.12, 26), Color = COLORS.Purple, Transparency = 0.3 })
		line.CFrame = CFrame.lookAt(mid, Vector3.new(A.X, mid.Y, A.Z))
	end
	local centerGem = neon(arena, {
		Name = "CenterGem",
		Size = Vector3.new(2.5, 2.5, 2.5),
		CFrame = CFrame.new(A + Vector3.new(0, 30, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
		Color = COLORS.Gold,
	})
	light(centerGem, COLORS.Gold, 60, 1.5)
	CollectionService:AddTag(centerGem, "Spin")
	CollectionService:AddTag(centerGem, "Float")

	-- Randmauer mit Neonkante
	ring(arena, A + Vector3.new(0, 1.3, 0), R - 0.8, 1.4, 2.6, 72, {
		Material = Enum.Material.Basalt,
		Color = Color3.fromRGB(20, 17, 28),
	})
	ring(arena, A + Vector3.new(0, 2.65, 0), R - 0.8, 1.5, 0.2, 72, { Color = COLORS.Cyan }, true)
	ring(arena, A + Vector3.new(0, -4, 0), R + 0.2, 0.7, 0.7, 72, { Color = COLORS.Magenta, Transparency = 0.15 }, true)

	-- Saeulen als Deckung
	for i = 1, 6 do
		local a = (i / 6) * math.pi * 2 + math.pi / 6
		local base = A + Vector3.new(math.cos(a) * 46, 0, math.sin(a) * 46)
		local height = 22 + (i % 2) * 6
		block(arena, {
			Size = Vector3.new(7, height, 7),
			CFrame = CFrame.new(base + Vector3.new(0, height / 2, 0)),
			Material = Enum.Material.Basalt,
			Color = Color3.fromRGB(26, 22, 36),
		})
		for _, h in { 3, height - 4 } do
			local band = neon(arena, {
				Size = Vector3.new(7.4, 0.6, 7.4),
				CFrame = CFrame.new(base + Vector3.new(0, h, 0)),
				Color = if i % 2 == 0 then COLORS.Cyan else COLORS.Magenta,
			})
			light(band, band.Color, 18, 1.4)
		end
		local cap = block(arena, {
			Size = Vector3.new(6, 3, 6),
			CFrame = CFrame.new(base + Vector3.new(0, height + 2.5, 0)) * CFrame.Angles(math.rad(12), math.rad(30), math.rad(-8)),
			Material = Enum.Material.Basalt,
			Color = Color3.fromRGB(26, 22, 36),
			CanCollide = false,
		})
		CollectionService:AddTag(cap, "Float")
	end

	floatingRocks(arena, A, R + 22, R + 75, 22)

	-- Spawnpunkte im Kreis, Blick zur Mitte
	local spawns = {}
	for i = 1, 12 do
		local a = (i / 12) * math.pi * 2
		local pos = A + Vector3.new(math.cos(a) * 58, 3.5, math.sin(a) * 58)
		table.insert(spawns, CFrame.lookAt(pos, Vector3.new(A.X, pos.Y, A.Z)))
	end
	return spawns
end

local function buildSkyDecor(map: Instance)
	local decor = Make("Folder", { Name = "Sky", Parent = map })
	-- Riesiger Planet mit Ring im Hintergrund
	local planetPos = Vector3.new(950, 240, 320)
	local planet = neon(decor, {
		Name = "Planet",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(460, 460, 460),
		CFrame = CFrame.new(planetPos),
		Color = Color3.fromRGB(70, 34, 120),
	})
	planet.Material = Enum.Material.Neon
	neon(decor, {
		Name = "PlanetRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 900, 900),
		CFrame = CFrame.new(planetPos) * CFrame.Angles(math.rad(14), 0, math.rad(90 + 18)),
		Color = Color3.fromRGB(200, 110, 255),
		Transparency = 0.78,
	})
	local moon = neon(decor, {
		Name = "Moon",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(120, 120, 120),
		CFrame = CFrame.new(-700, 320, 900),
		Color = Color3.fromRGB(40, 120, 170),
	})
	local _ = moon
	-- Leuchtender Abgrund unter allem
	neon(decor, {
		Name = "Abyss",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 2000, 2000),
		CFrame = CFrame.new(0, -90, 300) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(70, 20, 140),
		Transparency = 0.7,
	})
end

function WorldBuilder.Build(): WorldInfo
	setupLighting()
	local existing = workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end
	local map = Make("Folder", { Name = "Map" })
	local lobbySpawn, dummySpots = buildLobby(map)
	local arenaSpawns = buildArena(map)
	buildSkyDecor(map)
	map.Parent = workspace

	return {
		LobbySpawn = lobbySpawn,
		ArenaSpawns = arenaSpawns,
		DummySpots = dummySpots,
		LobbyCenter = Config.World.LobbyCenter,
		ArenaCenter = Config.World.ArenaCenter,
		ArenaRadius = Config.World.ArenaRadius,
	}
end

return WorldBuilder
