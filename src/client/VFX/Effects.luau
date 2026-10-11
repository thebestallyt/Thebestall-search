-- VFX-Grundbausteine fuer NOVA CLASH. Alles wird NUR lokal auf dem Client erstellt.
--
-- Stil-Regeln (bitte einhalten, damit alles "handgemacht" und geerdet wirkt):
-- * Schichten statt Neon-Flaechen: heller Kern -> farbige Mitte -> dunkler Rauch/Staub
-- * Neon nur fuer kleine, heisse Kerne (Blitz-Kern, Funken, Glut), nie fuer grosse Kugeln
-- * Staub, Steine und Brandflecken nehmen die Farbe des Bodens an (Terrain-Wiese / Steinboden)
-- * Schnitte sind Trails (weiche Sicheln), harte Treffer bekommen Impact-Frame + kurzen Hit-Stop
-- * Glaubwuerdige Element-Farben aus Effects.Palettes statt Regenbogen/Cyan/Magenta

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Make = require(Shared:WaitForChild("Make"))
local Sounds = require(Shared:WaitForChild("Sounds"))

local VFX = script.Parent :: Instance
local CameraShake = require(VFX:WaitForChild("CameraShake"))

local Effects = {}

Effects.Textures = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Sparks = "rbxasset://textures/particles/fire_sparks_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Glow = "rbxasset://textures/particles/forcefield_glow_main.dds",
	Vortex = "rbxasset://textures/particles/forcefield_vortex_main.dds",
	Shockwave = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
	Implosion = "rbxasset://textures/particles/explosion01_implosion_main.dds",
	Core = "rbxasset://textures/particles/explosion01_core_main.dds",
	ExplosionSmoke = "rbxasset://textures/particles/explosion01_smoke_main.dds",
}
local TEX = Effects.Textures

local C = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local TAU = math.pi * 2
local SMALL = Vector3.new(0.2, 0.2, 0.2)

-- Farbpaletten: glaubwuerdige Element-Farben (heller Kern -> Mitte -> Tiefe)
Effects.Palettes = {
	Fire = { Core = C(255, 248, 220), Hot = C(255, 206, 92), Mid = C(255, 124, 32), Deep = C(196, 44, 16), Smoke = C(48, 42, 40) },
	Ice = { Core = C(255, 255, 255), Light = C(218, 242, 255), Mid = C(152, 208, 240), Deep = C(78, 146, 204) },
	Lightning = { Core = C(255, 255, 255), Glow = C(136, 170, 255), Outer = C(146, 112, 255) },
	Water = { Foam = C(240, 250, 255), Light = C(132, 206, 240), Mid = C(46, 140, 214), Deep = C(20, 80, 158) },
	Shadow = { Ink = C(10, 8, 14), Dark = C(32, 20, 46), Accent = C(126, 70, 208) },
	Wind = { White = C(244, 248, 250), Pale = C(210, 228, 232) },
	Earth = { Dirt = C(116, 90, 64), Rock = C(124, 118, 110), Dust = C(184, 166, 134) },
	Holy = { Core = C(255, 252, 232), Gold = C(255, 212, 110) },
}
local PAL = Effects.Palettes

-- Feuer ueber die Lebenszeit: weiss-gelber Kern -> orange -> tiefrot -> dunkel
Effects.FireColors = ColorSequence.new({
	ColorSequenceKeypoint.new(0, PAL.Fire.Core),
	ColorSequenceKeypoint.new(0.16, PAL.Fire.Hot),
	ColorSequenceKeypoint.new(0.42, PAL.Fire.Mid),
	ColorSequenceKeypoint.new(0.75, PAL.Fire.Deep),
	ColorSequenceKeypoint.new(1, C(70, 34, 26)),
})

local folder = workspace:FindFirstChild("ClientVFX") or Make("Folder", { Name = "ClientVFX", Parent = workspace })
Effects.Folder = folder

local soundFolder = SoundService:FindFirstChild("NovaSounds") or Make("Folder", { Name = "NovaSounds", Parent = SoundService })

-- Qualitaet (kann im Spiel reduziert werden)
Effects.Quality = 1

local rng = Random.new()
Effects.Random = rng

-- Kurzformen -------------------------------------------------------------------

function Effects.Tween(inst: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?, delay: number?): Tween
	local tween = TweenService:Create(
		inst,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out, 0, false, delay or 0),
		props
	)
	tween:Play()
	return tween
end

function Effects.Clean(inst: Instance, time: number)
	Debris:AddItem(inst, time)
end

function Effects.Seq(...: any): ColorSequence
	local colors = { ... }
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local kps = {}
	for i, c in colors do
		table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
	end
	return ColorSequence.new(kps)
end

function Effects.NSeq(...: number): NumberSequence
	local values = { ... }
	if #values == 1 then
		return NumberSequence.new(values[1])
	end
	local kps = {}
	for i, v in values do
		table.insert(kps, NumberSequenceKeypoint.new((i - 1) / (#values - 1), v))
	end
	return NumberSequence.new(kps)
end
local Seq, NSeq = Effects.Seq, Effects.NSeq

-- Fuehrt fn(alpha, dt) jeden Frame aus, bis "duration" vorbei ist
function Effects.Animate(duration: number, fn: (number, number) -> (), onDone: (() -> ())?): RBXScriptConnection
	local start = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt)
		local a = math.clamp((os.clock() - start) / math.max(duration, 1e-3), 0, 1)
		local ok, err = pcall(fn, a, dt)
		if not ok then
			warn("[VFX] " .. tostring(err))
			conn:Disconnect()
			if onDone then
				pcall(onDone)
			end
			return
		end
		if a >= 1 then
			conn:Disconnect()
			if onDone then
				local ok2, err2 = pcall(onDone)
				if not ok2 then
					warn("[VFX] " .. tostring(err2))
				end
			end
		end
	end)
	return conn
end

function Effects.Ease(a: number, style: string?): number
	if style == "In" then
		return a * a
	elseif style == "InCubic" then
		return a * a * a
	elseif style == "OutCubic" then
		return 1 - (1 - a) ^ 3
	elseif style == "OutQuint" then
		return 1 - (1 - a) ^ 5
	elseif style == "Linear" then
		return a
	elseif style == "InOut" then
		return if a < 0.5 then 2 * a * a else 1 - ((-2 * a + 2) ^ 2) / 2
	elseif style == "OutBack" then
		local c1, c3 = 1.70158, 2.70158
		return 1 + c3 * (a - 1) ^ 3 + c1 * (a - 1) ^ 2
	end
	return 1 - (1 - a) * (1 - a) -- Out
end

-- Farbe leicht variieren (heller/dunkler), damit Steine/Staub nicht wie Klone aussehen
local function vary(c: Color3, amount: number): Color3
	local v = rng:NextNumber(-amount, amount)
	return if v >= 0 then c:Lerp(WHITE, v) else c:Lerp(BLACK, -v)
end
Effects.Vary = vary

-- Teile -------------------------------------------------------------------------

function Effects.Part(props: { [string]: any }?): Part
	local p = Make("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.Neon,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		Size = Vector3.new(1, 1, 1),
	})
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(p :: any)[k] = v
			end
		end
	end
	p.Parent = if props and props.Parent then props.Parent else folder
	return p
end

-- Keil (fuer spitze Felsen, Eiskristalle, Splitter)
function Effects.Wedge(props: { [string]: any }?): WedgePart
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.CanCollide = false
	w.CanQuery = false
	w.CanTouch = false
	w.CastShadow = false
	w.Material = Enum.Material.Slate
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(w :: any)[k] = v
			end
		end
	end
	w.Parent = if props and props.Parent then props.Parent else folder
	return w
end

function Effects.Ball(cf: CFrame, size: number, color: Color3, props: { [string]: any }?): Part
	local p = Effects.Part(props)
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(size, size, size)
	p.CFrame = cf
	p.Color = color
	return p
end

-- Unsichtbarer Anker mit Attachment (fuer Partikel, Licht, Sound)
function Effects.Anchor(position: Vector3, life: number?): (Part, Attachment)
	local p = Effects.Part({ Transparency = 1, Size = SMALL, CFrame = CFrame.new(position) })
	local att = Make("Attachment", { Parent = p })
	if life then
		Debris:AddItem(p, life)
	end
	return p, att
end

-- Partikel -------------------------------------------------------------------------

local EMITTER_DEFAULTS = {
	Texture = TEX.Sparkle,
	Rate = 0,
	LightEmission = 1,
	LightInfluence = 0,
	Lifetime = NumberRange.new(0.4, 0.8),
	Speed = NumberRange.new(10, 20),
	SpreadAngle = Vector2.new(180, 180),
	Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
	Rotation = NumberRange.new(0, 360),
	RotSpeed = NumberRange.new(-90, 90),
}

function Effects.Emitter(parent: Instance, props: { [string]: any }?): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for k, v in EMITTER_DEFAULTS do
		(e :: any)[k] = v
	end
	if props then
		for k, v in props do
			(e :: any)[k] = v
		end
	end
	e.Parent = parent
	return e
end

local function emitCount(count: number): number
	return math.clamp(math.floor(count * Effects.Quality), 1, 160)
end

-- Einmaliger Partikel-Ausstoss an einer Position
function Effects.Burst(position: Vector3, count: number, props: { [string]: any }?): ParticleEmitter
	local anchor, att = Effects.Anchor(position)
	local e = Effects.Emitter(att, props)
	e:Emit(emitCount(count))
	local maxLife = e.Lifetime.Max
	Debris:AddItem(anchor, maxLife + 0.5)
	return e
end

-- Gerichteter Ausstoss (Partikel fliegen in "direction")
function Effects.BurstDir(position: Vector3, direction: Vector3, count: number, props: { [string]: any }?): ParticleEmitter
	local anchor, att = Effects.Anchor(position)
	if direction.Magnitude > 0.001 then
		anchor.CFrame = CFrame.lookAt(position, position + direction)
	end
	local e = Effects.Emitter(att, props)
	if not (props and props.EmissionDirection) then
		e.EmissionDirection = Enum.NormalId.Front
	end
	e:Emit(emitCount(count))
	Debris:AddItem(anchor, e.Lifetime.Max + 0.5)
	return e
end

-- Boden ------------------------------------------------------------------------------
-- Zaehlt nur die Welt: Terrain (Wiese, Berge) und workspace.Map (Arena, Ruinen ...)

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.IgnoreWater = false

local function worldFilter(): { Instance }
	local list: { Instance } = { workspace.Terrain }
	local map = workspace:FindFirstChild("Map")
	if map then
		table.insert(list, map)
	end
	return list
end

local function castGround(position: Vector3): RaycastResult?
	groundParams.FilterDescendantsInstances = worldFilter()
	return workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -60, 0), groundParams)
end

function Effects.Ground(position: Vector3, fallbackDrop: number?): Vector3
	local res = castGround(position)
	if res then
		return res.Position
	end
	return position - Vector3.new(0, fallbackDrop or 3, 0)
end

function Effects.RaycastMap(origin: Vector3, direction: Vector3): RaycastResult?
	groundParams.FilterDescendantsInstances = worldFilter()
	return workspace:Raycast(origin, direction, groundParams)
end

-- Material-Typ (Alias, damit der Typpruefer ihn ueberall versteht)
type Mat = typeof(Enum.Material.Grass)

local DEFAULT_GROUND = C(150, 144, 132)
local SOFT_GROUND: { [Mat]: boolean } = {
	[Enum.Material.Grass] = true,
	[Enum.Material.LeafyGrass] = true,
	[Enum.Material.Ground] = true,
	[Enum.Material.Mud] = true,
}

-- Bodenpunkt, Bodenfarbe und Material unter einer Position
function Effects.GroundInfo(position: Vector3): (Vector3, Color3, Mat)
	local res = castGround(position)
	if not res then
		return position - Vector3.new(0, 3, 0), DEFAULT_GROUND, Enum.Material.Slate
	end
	local terrain = workspace.Terrain
	local mat = res.Material
	if res.Instance == terrain then
		if mat == Enum.Material.Water then
			return res.Position, PAL.Water.Light, mat
		end
		local ok, col = pcall(function()
			return terrain:GetMaterialColor(mat)
		end)
		return res.Position, if ok and typeof(col) == "Color3" then col else DEFAULT_GROUND, mat
	end
	return res.Position, (res.Instance :: BasePart).Color, mat
end

-- Nur die Farbe des Bodens (Terrain-Materialfarbe bzw. Farbe des Steinbodens)
function Effects.GroundColor(position: Vector3): Color3
	local _, col = Effects.GroundInfo(position)
	return col
end

local function dustFrom(col: Color3, mat: Mat): Color3
	if SOFT_GROUND[mat] then
		return PAL.Earth.Dust:Lerp(col, 0.18) -- Erdstaub (leicht gruenlich auf der Wiese)
	elseif mat == Enum.Material.Snow or mat == Enum.Material.Glacier then
		return C(240, 244, 250)
	elseif mat == Enum.Material.Sand or mat == Enum.Material.Sandstone then
		return col:Lerp(WHITE, 0.15)
	elseif mat == Enum.Material.Water then
		return PAL.Water.Foam
	end
	return col:Lerp(C(212, 204, 190), 0.45) -- Steinstaub
end

-- Staubfarbe passend zum Boden unter der Position
function Effects.DustColor(position: Vector3): Color3
	local _, col, mat = Effects.GroundInfo(position)
	return dustFrom(col, mat)
end

local function debrisFrom(col: Color3, mat: Mat): (Color3, Mat)
	if SOFT_GROUND[mat] then
		return PAL.Earth.Dirt, Enum.Material.Ground
	elseif mat == Enum.Material.Snow or mat == Enum.Material.Glacier then
		return C(226, 232, 242), Enum.Material.Snow
	elseif mat == Enum.Material.Sand then
		return col, Enum.Material.Sandstone
	elseif mat == Enum.Material.Water then
		return PAL.Earth.Rock, Enum.Material.Rock
	end
	return col:Lerp(BLACK, 0.08), mat
end

-- Farbe + Material fuer Truemmer (Erdbrocken auf der Wiese, Steinplatten in der Arena)
function Effects.DebrisLook(position: Vector3): (Color3, Mat)
	local _, col, mat = Effects.GroundInfo(position)
	return debrisFrom(col, mat)
end

-- Farbe + Material fuer Felsen, die aus dem Boden brechen
local function rockFrom(col: Color3, mat: Mat): (Color3, Mat)
	if SOFT_GROUND[mat] or mat == Enum.Material.Water then
		return C(126, 116, 102), Enum.Material.Rock
	elseif mat == Enum.Material.Snow or mat == Enum.Material.Glacier then
		return C(196, 204, 216), Enum.Material.Rock
	end
	return col:Lerp(BLACK, 0.12), mat
end

-- Alle Kaempfer-Modelle (Spieler + NPCs)
function Effects.Characters(): { Model }
	local list = {}
	for _, plr in Players:GetPlayers() do
		if plr.Character then
			table.insert(list, plr.Character)
		end
	end
	local npcs = workspace:FindFirstChild("NPCs")
	if npcs then
		for _, m in npcs:GetChildren() do
			if m:IsA("Model") then
				table.insert(list, m :: Model)
			end
		end
	end
	return list
end

-- Partikel-Ausstoss an einem Attachment/Teil (z.B. Hand)
function Effects.BurstOn(parent: Instance, count: number, props: { [string]: any }?)
	local e = Effects.Emitter(parent, props)
	e:Emit(emitCount(count))
	Debris:AddItem(e, e.Lifetime.Max + 0.3)
	return e
end

-- Laufender Emitter fuer "duration" Sekunden
function Effects.Stream(parent: Instance, duration: number, props: { [string]: any }?): ParticleEmitter
	local e = Effects.Emitter(parent, props)
	if e.Rate == 0 then
		e.Rate = 40
	end
	e.Rate *= Effects.Quality
	task.delay(duration, function()
		e.Enabled = false
		Debris:AddItem(e, e.Lifetime.Max + 0.2)
	end)
	return e
end

-- Licht ---------------------------------------------------------------------------

function Effects.Light(at: Vector3 | Instance, color: Color3, range: number, brightness: number, duration: number, fadeIn: number?): PointLight
	local parent: Instance
	if typeof(at) == "Vector3" then
		local anchor = Effects.Anchor(at :: Vector3, duration + (fadeIn or 0) + 0.2)
		parent = anchor
	else
		parent = at :: Instance
	end
	local light = Make("PointLight", {
		Color = color,
		Range = math.min(range, 60),
		Brightness = if fadeIn then 0 else brightness,
		Shadows = false,
		Parent = parent,
	})
	if fadeIn then
		Effects.Tween(light, fadeIn, { Brightness = brightness })
		Effects.Tween(light, duration, { Brightness = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, fadeIn)
	else
		Effects.Tween(light, duration, { Brightness = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	Debris:AddItem(light, duration + (fadeIn or 0) + 0.1)
	return light
end

-- Weicher Leucht-Sprite (statt einer harten Neon-Kugel)
function Effects.Glow(position: Vector3, color: Color3, size: number, duration: number): ParticleEmitter
	local s = math.min(size, 80)
	return Effects.Burst(position, 1, {
		Texture = TEX.Glow,
		Color = ColorSequence.new(color),
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(duration),
		Size = NSeq(s * 0.35, s),
		Transparency = NSeq(0.2, 1),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(0),
		LightEmission = 1,
		ZOffset = 1,
	})
end

-- Kurzer Aufblitz: kleiner heisser Kern + weicher Glow + Licht (keine grosse Neon-Kugel mehr)
function Effects.Flash(position: Vector3, color: Color3, size: number, duration: number, startSize: number?): Part
	local s0 = math.min(startSize or size * 0.12, size * 0.25)
	local core = Effects.Ball(CFrame.new(position), math.max(0.2, s0), WHITE:Lerp(color, 0.2), { Transparency = 0.05 })
	Effects.Tween(core, duration * 0.4, { Size = Vector3.one * math.max(0.3, size * 0.26), Transparency = 1 }, Enum.EasingStyle.Quart)
	Debris:AddItem(core, duration * 0.4 + 0.05)
	Effects.Burst(position, 1, {
		Texture = TEX.Core,
		Color = Seq(WHITE, color),
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(duration * 0.5),
		Size = NSeq(math.min(size * 0.3, 40), math.min(size * 0.8, 70)),
		Transparency = NSeq(0, 1),
		RotSpeed = NumberRange.new(0),
		LightEmission = 1,
		ZOffset = 1.5,
	})
	Effects.Glow(position, color, size, duration)
	Effects.Light(position, color, math.min(size * 3, 60), 4, duration * 1.5)
	return core
end

-- Ringe & Schockwellen ------------------------------------------------------------

-- Ring (CylinderHandleAdornment mit Innenradius). cf: Achse des Rings = Z-Achse von cf.
-- Bewusst dezent (halbtransparent, wird duenner), damit er nicht wie ein Neon-Reifen wirkt.
function Effects.Ring(
	cf: CFrame,
	radius0: number,
	radius1: number,
	color: Color3,
	duration: number,
	thickness: number?,
	opts: { [string]: any }?
): CylinderHandleAdornment
	local o = opts or {}
	local anchor = Effects.Part({ Transparency = 1, Size = SMALL, CFrame = CFrame.new(cf.Position) })
	local width = thickness or 1
	local t0 = o.Transparency or 0.25
	local ring = Make("CylinderHandleAdornment", {
		Adornee = anchor,
		CFrame = cf.Rotation,
		Color3 = color,
		Radius = radius0,
		InnerRadius = math.max(0, radius0 - width),
		Height = o.Height or 0.2,
		Transparency = t0,
		AlwaysOnTop = false,
		ZIndex = 1,
		Parent = anchor,
	})
	local style = o.Ease or "OutCubic"
	Effects.Animate(duration, function(a)
		local e = Effects.Ease(a, style)
		local r = radius0 + (radius1 - radius0) * e
		local w = width * (1 - a * (if o.Thin then 0.85 else 0.55))
		ring.Radius = r
		ring.InnerRadius = math.max(0, r - w)
		ring.Transparency = t0 + (1 - t0) * (a ^ (o.FadePower or 1.2))
	end, function()
		anchor:Destroy()
	end)
	Debris:AddItem(anchor, duration + 1)
	return ring
end

-- Bodenwelle: Staubring in Bodenfarbe + ein dezenter, schnell verblassender Ring.
-- Schrumpfende Ringe (radius1 < radius0) bleiben reine Warnkreise ohne Staub.
function Effects.GroundRing(position: Vector3, radius0: number, radius1: number, color: Color3, duration: number, thickness: number?, opts: { [string]: any }?)
	local o = opts or {}
	local expanding = radius1 > radius0
	if expanding and not o.NoDust and radius1 >= 4 then
		Effects.DustRing(position, radius1 * 0.8, nil, { Life = math.clamp(duration * 1.8, 0.6, 2.2) })
	end
	local ringOpts = table.clone(o)
	if ringOpts.Transparency == nil then
		ringOpts.Transparency = if expanding then 0.55 else 0.3
	end
	return Effects.Ring(CFrame.new(position) * CFrame.Angles(math.rad(90), 0, 0), radius0, radius1, color, duration, thickness, ringOpts)
end

-- Flache Partikel-Schockwelle (Textur-Ring, halbtransparent)
function Effects.Shockwave(position: Vector3, size: number, color: Color3, duration: number, up: Vector3?)
	local anchor, att = Effects.Anchor(position)
	local dir = up or Vector3.yAxis
	if dir.Magnitude < 1e-3 then
		dir = Vector3.yAxis
	end
	anchor.CFrame = CFrame.lookAt(position, position + dir) * CFrame.Angles(math.rad(-90), 0, 0)
	local e = Effects.Emitter(att, {
		Texture = TEX.Shockwave,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		Speed = NumberRange.new(0.01),
		SpreadAngle = Vector2.new(0, 0),
		EmissionDirection = Enum.NormalId.Top,
		Lifetime = NumberRange.new(duration),
		Size = NSeq(size * 0.1, size),
		Transparency = NSeq(0.35, 1),
		Color = ColorSequence.new(color),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(0, 0),
		LightEmission = 0.7,
		ZOffset = 0.5,
	})
	e:Emit(1)
	Debris:AddItem(anchor, duration + 0.3)
end

-- Geschichtete Effekt-Bausteine ----------------------------------------------------

-- Funken als Streifen (fliegen in Bewegungsrichtung gestreckt)
-- opts: Dir (Vector3), Spread (Vector2), MinLife, MaxLife, Size, Gravity, Drag, Colors (ColorSequence)
function Effects.Sparks(position: Vector3, count: number, color: Color3, speed: number, opts: { [string]: any }?): ParticleEmitter
	local o = opts or {}
	local props = {
		Texture = TEX.Sparks,
		Color = o.Colors or Seq(WHITE, color),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = NSeq(o.Squash or 1.4, 0.4),
		Speed = NumberRange.new(speed * 0.45, speed),
		Lifetime = NumberRange.new(o.MinLife or 0.15, o.MaxLife or 0.4),
		Size = NSeq(o.Size or 0.35, 0),
		Drag = o.Drag or 3,
		Acceleration = Vector3.new(0, -(o.Gravity or 30), 0),
		SpreadAngle = o.Spread or Vector2.new(180, 180),
		LightEmission = 1,
		Brightness = o.Brightness or 2,
		RotSpeed = NumberRange.new(0),
		Rotation = NumberRange.new(0),
	}
	local dir: Vector3? = o.Dir
	if dir and dir.Magnitude > 0.001 then
		return Effects.BurstDir(position, dir, count, props)
	end
	return Effects.Burst(position, count, props)
end

-- Rauchwolke (dunkel oder hell). opts: Dir, Rise, Life
function Effects.SmokePuff(position: Vector3, count: number, color: Color3, scale: number?, opts: { [string]: any }?): ParticleEmitter
	local o = opts or {}
	local s = scale or 1
	local life = o.Life or 1.2
	local props = {
		Texture = TEX.Smoke,
		Color = ColorSequence.new(color),
		LightEmission = 0,
		LightInfluence = 0.8,
		Speed = NumberRange.new(2 * s, 6 * s),
		Lifetime = NumberRange.new(life * 0.65, life),
		Size = NSeq(1.4 * s, 3.8 * s),
		Transparency = NSeq(0.3, 0.6, 1),
		Drag = 2.5,
		RotSpeed = NumberRange.new(-35, 35),
		Acceleration = Vector3.new(0, o.Rise or 2, 0),
	}
	local dir: Vector3? = o.Dir
	if dir and dir.Magnitude > 0.001 then
		props.SpreadAngle = Vector2.new(45, 45)
		return Effects.BurstDir(position, dir, count, props)
	end
	return Effects.Burst(position, count, props)
end

-- Aufsteigende Staubwolke vom Boden (Farbe = Bodenfarbe, wenn nicht angegeben)
function Effects.Dust(position: Vector3, count: number, scale: number?, color: Color3?): ParticleEmitter
	local s = scale or 1
	local col = color or Effects.DustColor(position)
	return Effects.Burst(position + Vector3.new(0, 0.4 * s, 0), count, {
		Texture = TEX.Smoke,
		Color = ColorSequence.new(col),
		LightEmission = 0,
		LightInfluence = 0.85,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(75, 75),
		Speed = NumberRange.new(3 * s, 9 * s),
		Lifetime = NumberRange.new(0.6, 1.2),
		Size = NSeq(1.4 * s, 3.8 * s),
		Transparency = NSeq(0.35, 0.65, 1),
		Drag = 3,
		Acceleration = Vector3.new(0, 1, 0),
		RotSpeed = NumberRange.new(-40, 40),
	})
end

-- Staubring, der sich flach am Boden ausbreitet (Druckwelle in Bodenfarbe)
-- opts: Count, Size, Life
function Effects.DustRing(position: Vector3, radius: number, color: Color3?, opts: { [string]: any }?)
	local o = opts or {}
	local col = color or Effects.DustColor(position)
	local n = math.max(4, math.floor(math.clamp(o.Count or (8 + radius * 0.6), 6, 24) * math.max(Effects.Quality, 0.4)))
	local puff = math.clamp(radius * 0.3, 1.2, 12) * (o.Size or 1)
	local life = o.Life or math.clamp(0.7 + radius * 0.04, 0.7, 2.2)
	local drag = 3.2
	-- Drag halbiert die Geschwindigkeit exponentiell -> Strecke ~ v0 / (drag * ln2)
	local v = radius * drag * 0.69
	local anchor = Effects.Part({ Transparency = 1, Size = SMALL, CFrame = CFrame.new(position + Vector3.new(0, 0.25 + puff * 0.2, 0)) })
	local start = math.min(radius * 0.15, 2)
	for i = 1, n do
		local a = (i / n) * TAU + rng:NextNumber(-0.15, 0.15)
		local dir = Vector3.new(math.cos(a), 0.06, math.sin(a))
		local att = Make("Attachment", { CFrame = CFrame.lookAt(dir * start, dir * (start + 1)), Parent = anchor })
		local e = Effects.Emitter(att, {
			Texture = TEX.Smoke,
			Color = ColorSequence.new(col),
			LightEmission = 0,
			LightInfluence = 0.85,
			EmissionDirection = Enum.NormalId.Front,
			SpreadAngle = Vector2.new(10, 4),
			Speed = NumberRange.new(v * 0.8, v * 1.1),
			Drag = drag,
			Lifetime = NumberRange.new(life * 0.7, life),
			Size = NSeq(puff * 0.6, puff * 1.5),
			Transparency = NSeq(0.3, 0.6, 1),
			Acceleration = Vector3.new(0, 1.2, 0),
			RotSpeed = NumberRange.new(-50, 50),
		})
		e:Emit(2)
	end
	Debris:AddItem(anchor, life + 0.3)
end

-- Mehrschichtiges Feuer: heller Kern -> Flammen -> dunkler Rauch -> Glut
-- direction = nil -> in alle Richtungen. opts: Spread (Vector2), Speed
function Effects.FireBurst(position: Vector3, direction: Vector3?, scale: number, opts: { [string]: any }?)
	local o = opts or {}
	local s = scale
	local dir: Vector3? = if direction and direction.Magnitude > 0.001 then direction else nil
	local spread: Vector2 = o.Spread or (if dir then Vector2.new(30, 30) else Vector2.new(180, 180))
	local speed = o.Speed or 18
	local function emit(count: number, props: { [string]: any })
		props.SpreadAngle = props.SpreadAngle or spread
		if dir then
			Effects.BurstDir(position, dir, count, props)
		else
			Effects.Burst(position, count, props)
		end
	end
	-- 1) weiss-gelber Kern
	emit(7 * s, {
		Texture = TEX.Fire,
		Color = Seq(PAL.Fire.Core, PAL.Fire.Hot),
		Speed = NumberRange.new(speed * 0.5 * s, speed * 0.9 * s),
		Lifetime = NumberRange.new(0.12, 0.24),
		Size = NSeq(1.4 * s, 2.6 * s, 0),
		SpreadAngle = spread * 0.6,
		Drag = 4,
		LightEmission = 1,
		Brightness = 2,
	})
	-- 2) Flammenzungen
	emit(15 * s, {
		Texture = TEX.Fire,
		Color = Effects.FireColors,
		Speed = NumberRange.new(speed * 0.7 * s, speed * 1.3 * s),
		Lifetime = NumberRange.new(0.3, 0.6),
		Size = NSeq(2 * s, 3.8 * s, 0.6 * s),
		Transparency = NSeq(0.05, 0.25, 1),
		Drag = 4,
		Acceleration = Vector3.new(0, 10, 0),
		LightEmission = 0.85,
		RotSpeed = NumberRange.new(-120, 120),
	})
	-- 3) dunkler Rauch
	emit(6 * s, {
		Texture = TEX.Smoke,
		Color = Seq(C(84, 66, 56), PAL.Fire.Smoke),
		LightEmission = 0,
		LightInfluence = 0.7,
		Speed = NumberRange.new(speed * 0.25 * s, speed * 0.55 * s),
		Lifetime = NumberRange.new(0.8, 1.4),
		Size = NSeq(2.4 * s, 6 * s),
		Transparency = NSeq(0.35, 0.6, 1),
		Drag = 2.5,
		Acceleration = Vector3.new(0, 6, 0),
		RotSpeed = NumberRange.new(-40, 40),
	})
	-- 4) Glut
	emit(9 * s, {
		Texture = TEX.Sparks,
		Color = Seq(PAL.Fire.Hot, PAL.Fire.Mid),
		Speed = NumberRange.new(speed * 0.8 * s, speed * 1.7 * s),
		Lifetime = NumberRange.new(0.4, 0.9),
		Size = NSeq(0.3, 0),
		SpreadAngle = spread * 1.2,
		Drag = 2,
		Acceleration = Vector3.new(0, 8, 0),
		LightEmission = 1,
	})
end

-- Komplette Explosion: kurzer Kern, Feuerball, Flammen, Rauch, Funken, Staub & Brandfleck am Boden.
-- opts: Secondary (Kernfarbe), SmokeColor, Shake, NoScorch, GroundOffset (alt, ignoriert)
function Effects.Explosion(position: Vector3, color: Color3, scale: number, opts: { [string]: any }?)
	local o = opts or {}
	local s = math.max(scale, 0.2)
	local secondary: Color3 = o.Secondary or PAL.Fire.Core
	local smoke: Color3 = o.SmokeColor or C(60, 54, 52)
	local deep = color:Lerp(BLACK, 0.45)
	Effects.Flash(position, secondary, 7 * s, 0.22)
	-- Feuerball
	Effects.Burst(position, 5 * s, {
		Texture = TEX.Core,
		Color = Seq(secondary, color, deep),
		Speed = NumberRange.new(3 * s, 9 * s),
		Lifetime = NumberRange.new(0.25, 0.45),
		Size = NSeq(math.min(3 * s, 30), math.min(7 * s, 60)),
		Transparency = NSeq(0, 0.3, 1),
		Drag = 6,
		RotSpeed = NumberRange.new(-60, 60),
		LightEmission = 1,
	})
	-- Flammenzungen
	Effects.Burst(position, 14 * s, {
		Texture = TEX.Fire,
		Color = Seq(secondary, color, deep),
		Speed = NumberRange.new(14 * s, 30 * s),
		Lifetime = NumberRange.new(0.25, 0.55),
		Size = NSeq(2.2 * s, 4 * s, 0.5 * s),
		Drag = 5,
		LightEmission = 0.9,
	})
	-- dunkler Rauch
	Effects.Burst(position, 8 * s, {
		Texture = TEX.ExplosionSmoke,
		Color = ColorSequence.new(smoke),
		LightEmission = 0,
		LightInfluence = 0.8,
		Speed = NumberRange.new(5 * s, 12 * s),
		Lifetime = NumberRange.new(1, 1.8),
		Size = NSeq(math.min(4 * s, 40), math.min(9 * s, 70)),
		Transparency = NSeq(0.25, 0.6, 1),
		Drag = 2.5,
		Acceleration = Vector3.new(0, 5, 0),
		RotSpeed = NumberRange.new(-25, 25),
	})
	-- Funken
	Effects.Sparks(position, 14 * s, secondary:Lerp(color, 0.5), 40 * s, { Gravity = 45, MaxLife = 0.7 })
	-- Boden: Staubring + Brandfleck, wenn der Boden nah ist
	local res = castGround(position)
	if res and position.Y - res.Position.Y < 8 * s then
		Effects.DustRing(res.Position, 7 * s)
		if not o.NoScorch then
			Effects.Scorch(res.Position, 2.6 * s, 2.5)
		end
	end
	Effects.Shockwave(position, 16 * s, secondary:Lerp(color, 0.5), 0.4)
	CameraShake.ShakeAt(position, o.Shake or 1.5 * s, 60 * s, 0.45)
end

-- Schnitte (Trails) ------------------------------------------------------------------

-- Weiche Anime-Sichel: ein Attachment-Paar wird auf einem Kreisbogen bewegt, der Trail
-- dazwischen bildet die Sichel. Der Bogen liegt in der Ebene von cf.LookVector/cf.RightVector
-- (senkrecht zu cf.UpVector) und laeuft von rechts (-arc/2) ueber vorne nach links (+arc/2).
-- Negativer Bogen = andersherum. opts: Sweep, Life, LightEmission, CoreColor, NoCore,
-- Transparency, Ease, ColorSeq, FaceCamera (true = Band dreht sich zur Kamera, gut fuer kleine Schlaege)
function Effects.TrailSlash(cf: CFrame, radius: number, arcDegrees: number, color: Color3, duration: number, width: number?, opts: { [string]: any }?): Part
	local o = opts or {}
	local w = width or 0.8
	local arc = math.rad(arcDegrees)
	local sweepTime = o.Sweep or math.clamp(duration * 0.35, 0.05, 0.22)
	local life = math.max(0.06, o.Life or (duration - sweepTime * 0.5))
	local t0 = o.Transparency or 0.1
	local function at(a: number): CFrame
		return cf * CFrame.Angles(0, -arc / 2 + arc * a, 0) * CFrame.new(0, 0, -radius)
	end
	local anchor = Effects.Part({ Transparency = 1, Size = SMALL, CFrame = at(0) })
	-- -Z zeigt nach aussen: a1 = Aussenkante, a0 = Innenkante
	local a0 = Make("Attachment", { Position = Vector3.new(0, 0, w * 0.5), Parent = anchor })
	local a1 = Make("Attachment", { Position = Vector3.new(0, 0, -w * 0.5), Parent = anchor })
	Make("Trail", {
		Attachment0 = a0,
		Attachment1 = a1,
		Color = o.ColorSeq or ColorSequence.new(color),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, t0),
			NumberSequenceKeypoint.new(0.35, t0 + (1 - t0) * 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
		WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(0.3, 1),
			NumberSequenceKeypoint.new(1, 0.1),
		}),
		Lifetime = life,
		LightEmission = o.LightEmission or 0.6,
		LightInfluence = 0,
		FaceCamera = o.FaceCamera == true,
		MinLength = 0.02,
		Parent = anchor,
	})
	if not o.NoCore then
		-- heller Kern an der Schneide (Aussenkante)
		local c0 = Make("Attachment", { Position = Vector3.new(0, 0, -w * 0.08), Parent = anchor })
		local c1 = Make("Attachment", { Position = Vector3.new(0, 0, -w * 0.42), Parent = anchor })
		Make("Trail", {
			Attachment0 = c0,
			Attachment1 = c1,
			Color = ColorSequence.new(o.CoreColor or WHITE),
			Transparency = NSeq(0, 0.55, 1),
			WidthScale = NSeq(0.6, 1, 0),
			Lifetime = life * 0.7,
			LightEmission = 1,
			LightInfluence = 0,
			FaceCamera = o.FaceCamera == true,
			MinLength = 0.02,
			Parent = anchor,
		})
	end
	local ease = o.Ease or "Out"
	Effects.Animate(sweepTime, function(a)
		anchor.CFrame = at(Effects.Ease(a, ease))
	end)
	Debris:AddItem(anchor, sweepTime + life + 0.2)
	return anchor
end

-- Gerader, scharfer Schnitt als Trail (z.B. X-Schnitte). Dunkle/farbige Kante + heller Kern.
-- opts: Sweep, LightEmission, CoreColor, NoCore, Transparency
function Effects.TrailLine(from: Vector3, to: Vector3, color: Color3, duration: number, width: number?, opts: { [string]: any }?): Part?
	local o = opts or {}
	local dir = to - from
	if dir.Magnitude < 0.05 then
		return nil
	end
	local w = width or 0.8
	local sweepTime = o.Sweep or math.clamp(duration * 0.3, 0.04, 0.15)
	local life = math.max(0.06, duration - sweepTime)
	local t0 = o.Transparency or 0.05
	local start = CFrame.lookAt(from, to)
	local anchor = Effects.Part({ Transparency = 1, Size = SMALL, CFrame = start })
	-- Attachments quer zur Bewegung; FaceCamera dreht das Band zur Kamera
	local a0 = Make("Attachment", { Position = Vector3.new(-w * 0.5, 0, 0), Parent = anchor })
	local a1 = Make("Attachment", { Position = Vector3.new(w * 0.5, 0, 0), Parent = anchor })
	Make("Trail", {
		Attachment0 = a0,
		Attachment1 = a1,
		Color = ColorSequence.new(color),
		Transparency = NSeq(t0, 0.3 + t0 * 0.5, 1),
		WidthScale = NSeq(1, 0.75, 0.15),
		Lifetime = life,
		LightEmission = o.LightEmission or 0.5,
		LightInfluence = 0,
		FaceCamera = true,
		MinLength = 0.02,
		Parent = anchor,
	})
	if not o.NoCore then
		local c0 = Make("Attachment", { Position = Vector3.new(-w * 0.16, 0, 0), Parent = anchor })
		local c1 = Make("Attachment", { Position = Vector3.new(w * 0.16, 0, 0), Parent = anchor })
		Make("Trail", {
			Attachment0 = c0,
			Attachment1 = c1,
			Color = ColorSequence.new(o.CoreColor or WHITE),
			Transparency = NSeq(0, 0.35, 1),
			WidthScale = NSeq(1, 0.6, 0),
			Lifetime = life * 0.85,
			LightEmission = 1,
			LightInfluence = 0,
			FaceCamera = true,
			MinLength = 0.02,
			Parent = anchor,
		})
	end
	Effects.Animate(sweepTime, function(a)
		anchor.CFrame = start + dir * Effects.Ease(a, "OutCubic")
	end)
	Debris:AddItem(anchor, sweepTime + life + 0.2)
	return anchor
end

-- Bogen-Schnitt (alte API): Bogen liegt senkrecht zur Z-Achse von cf. Intern jetzt ein Trail.
function Effects.Slash(cf: CFrame, radius: number, color: Color3, duration: number, angle: number?, width: number?)
	Effects.TrailSlash(cf * CFrame.Angles(math.rad(90), 0, 0), radius, angle or 200, color, duration, (width or 0.6) * 1.5)
end

-- Gerader Schnitt (alte API): Linie entlang cf.LookVector, Mitte = cf.Position. Intern ein Trail.
function Effects.Line(center: CFrame, length: number, color: Color3, duration: number, width: number?)
	local half = center.LookVector * (length / 2)
	Effects.TrailLine(center.Position - half, center.Position + half, color, duration, (width or 0.25) * 3)
end

-- Blitze ----------------------------------------------------------------------------

local function boltPoints(from: Vector3, to: Vector3, segments: number, jitter: number): { Vector3 }
	local points = { from }
	local dir = to - from
	local len = dir.Magnitude
	if len < 0.01 then
		return { from, to }
	end
	local cf = CFrame.lookAt(from, to)
	for i = 1, segments - 1 do
		local a = i / segments
		local j = jitter * math.sin(a * math.pi)
		local offset = cf.RightVector * rng:NextNumber(-j, j) + cf.UpVector * rng:NextNumber(-j, j)
		table.insert(points, from + dir * a + offset)
	end
	table.insert(points, to)
	return points
end

-- Blitz aus Neon-Segmenten: weisser Kern, farbiger Schein, optional violetter Dunst.
-- opts: Color, CoreColor, Outer (Dunstfarbe), Width, Duration, Segments, Jitter, Branches, Flicker
function Effects.Bolt(from: Vector3, to: Vector3, opts: { [string]: any }?)
	local o = opts or {}
	local color: Color3 = o.Color or PAL.Lightning.Glow
	local width: number = o.Width or 0.35
	local duration: number = o.Duration or 0.3
	local len = (to - from).Magnitude
	if len < 0.05 then
		return
	end
	local segments: number = o.Segments or math.clamp(math.floor(len / 2.5), 4, 18)
	local jitter: number = o.Jitter or len * 0.12
	local points = boltPoints(from, to, segments, jitter)
	local core: Color3 = o.CoreColor or WHITE
	local outer: Color3? = o.Outer or (if width >= 0.5 then color else nil)
	local parts: { BasePart } = {}
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local segLen = (b - a).Magnitude
		if segLen > 0.01 then
			local cf = CFrame.lookAt((a + b) / 2, b)
			table.insert(parts, Effects.Part({ Size = Vector3.new(width, width, segLen + width * 0.6), CFrame = cf, Color = core }))
			table.insert(parts, Effects.Part({ Size = Vector3.new(width * 2.6, width * 2.6, segLen + width * 1.4), CFrame = cf, Color = color, Transparency = 0.62 }))
			if outer then
				table.insert(parts, Effects.Part({ Size = Vector3.new(width * 5, width * 5, segLen + width * 3), CFrame = cf, Color = outer, Transparency = 0.86 }))
			end
		end
	end
	-- Verzweigungen
	local branches: number = o.Branches or 0
	if branches > 0 and #points > 2 then
		local main = (to - from).Unit
		for _ = 1, branches do
			local start = points[rng:NextInteger(2, #points - 1)]
			local rand = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
			local side = rand - main * rand:Dot(main)
			if side.Magnitude < 0.05 then
				side = main:Cross(Vector3.yAxis)
			end
			if side.Magnitude < 0.05 then
				side = Vector3.xAxis
			end
			local blen = len * rng:NextNumber(0.12, 0.3)
			local branchEnd = start + (main * 0.6 + side.Unit * 0.8).Unit * blen
			Effects.Bolt(start, branchEnd, {
				Color = color,
				CoreColor = core,
				Width = width * 0.45,
				Duration = duration * 0.8,
				Segments = math.max(3, math.floor(segments * 0.4)),
				Jitter = jitter * 0.4,
			})
		end
	end
	-- Nachzucken: neue Blitze auf derselben Strecke
	local flicker: number = o.Flicker or 0
	for k = 1, flicker do
		task.delay(k * duration * 0.22, function()
			Effects.Bolt(from, to, {
				Color = color,
				CoreColor = core,
				Outer = o.Outer,
				Width = width * 0.8,
				Duration = duration * 0.55,
				Segments = segments,
				Jitter = jitter,
				Branches = math.max(0, branches - 2),
			})
		end)
	end
	local base: { number } = {}
	for i, p in parts do
		base[i] = p.Transparency
		Debris:AddItem(p, duration + 0.4)
	end
	Effects.Animate(duration, function(a)
		local flick = if a < 0.45 and rng:NextNumber() < 0.25 then 0.6 else 0
		for i, p in parts do
			p.Transparency = math.min(1, base[i] + (1 - base[i]) * (a ^ 1.3) + flick)
		end
	end, function()
		for _, p in parts do
			p:Destroy()
		end
	end)
end

-- Boden-Abdruecke ---------------------------------------------------------------------

-- Weicher Abdruck auf dem Boden (Decal auf unsichtbarer Platte): Brandfleck, Frost, Warnkreis ...
-- opts: Texture, Transparency, FadeIn, FadeOut, Grow, Lift
function Effects.GroundMark(position: Vector3, radius: number, color: Color3, duration: number, opts: { [string]: any }?): Part
	local o = opts or {}
	local size = math.max(0.2, radius * 2)
	local part = Effects.Part({
		Name = "GroundMark",
		Transparency = 1,
		Size = Vector3.new(size, 0.05, size),
		CFrame = CFrame.new(position + Vector3.new(0, o.Lift or 0.08, 0)) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0),
	})
	local t0 = o.Transparency or 0.2
	local decal = Make("Decal", {
		Texture = o.Texture or TEX.Smoke,
		Face = Enum.NormalId.Top,
		Color3 = color,
		Transparency = if o.FadeIn then 1 else t0,
		ZIndex = 1,
		Parent = part,
	})
	if o.FadeIn then
		Effects.Tween(decal, o.FadeIn, { Transparency = t0 })
	end
	if o.Grow then
		part.Size = Vector3.new(size * 0.3, 0.05, size * 0.3)
		Effects.Tween(part, o.Grow, { Size = Vector3.new(size, 0.05, size) }, Enum.EasingStyle.Quart)
	end
	local fade = math.min(duration * 0.5, o.FadeOut or 1)
	Effects.Tween(decal, fade, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, math.max(0, duration - fade))
	Debris:AddItem(part, duration + 0.1)
	return part
end

-- Dunkle Brandspur am Boden (weicher Fleck statt harter Scheibe)
function Effects.Scorch(position: Vector3, radius: number, duration: number, color: Color3?): Part
	local col = color or C(24, 18, 16)
	local main = Effects.GroundMark(position, radius, col, duration, { Transparency = 0.15, Grow = 0.12 })
	Effects.GroundMark(position, radius * 0.55, col:Lerp(BLACK, 0.5), duration * 0.85, {
		Texture = TEX.ExplosionSmoke,
		Transparency = 0.1,
		Lift = 0.1,
	})
	return main
end

-- Felsen ------------------------------------------------------------------------------

-- Fliegende Brocken mit Physik. Ohne opts.Color passen Farbe/Material zum Boden
-- (Erdklumpen + Steine auf der Wiese, Platten-Splitter in der Arena).
function Effects.Rocks(position: Vector3, count: number, opts: { [string]: any }?)
	local o = opts or {}
	local n = math.min(40, math.floor(count * Effects.Quality))
	if n <= 0 then
		return
	end
	local baseColor: Color3
	local baseMat: Mat
	local soft = false
	local dust: Color3
	if o.Color then
		baseColor, baseMat = o.Color, o.Material or Enum.Material.Slate
		dust = (o.Color :: Color3):Lerp(WHITE, 0.4)
	else
		local _, gcol, gmat = Effects.GroundInfo(position)
		soft = SOFT_GROUND[gmat] == true
		baseColor, baseMat = debrisFrom(gcol, gmat)
		if o.Material then
			baseMat = o.Material
		end
		dust = dustFrom(gcol, gmat)
	end
	for i = 1, n do
		local col, mat = baseColor, baseMat
		if soft and rng:NextNumber() < 0.35 then
			col, mat = PAL.Earth.Rock, Enum.Material.Rock
		end
		local s = rng:NextNumber(o.MinSize or 0.6, o.MaxSize or 1.6)
		local rock = Effects.Part({
			Size = Vector3.new(s, s * rng:NextNumber(0.6, 1.1), s * rng:NextNumber(0.7, 1.3)),
			CFrame = CFrame.new(position + Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.5, 1.5), rng:NextNumber(-1, 1)))
				* CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)),
			Material = mat,
			Color = vary(col, 0.1),
			Anchored = false,
			CanCollide = true,
			CollisionGroup = "VFX",
			Massless = true,
			CastShadow = s > 1.1,
		})
		local spread = o.Spread or 30
		local flatDir = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
		if flatDir.Magnitude < 0.05 then
			flatDir = Vector3.xAxis
		end
		local v = flatDir.Unit * rng:NextNumber(spread * 0.4, spread)
		rock.AssemblyLinearVelocity = v + Vector3.new(0, rng:NextNumber(o.MinUp or 25, o.MaxUp or 50), 0)
		rock.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-10, 10), rng:NextNumber(-10, 10), rng:NextNumber(-10, 10))
		-- Staubfahne hinter groesseren Brocken
		if s > 1.1 and i % 2 == 0 then
			local t0 = Make("Attachment", { Position = Vector3.new(0, s * 0.3, 0), Parent = rock })
			local t1 = Make("Attachment", { Position = Vector3.new(0, -s * 0.3, 0), Parent = rock })
			Make("Trail", {
				Attachment0 = t0,
				Attachment1 = t1,
				Color = ColorSequence.new(dust),
				Transparency = NSeq(0.55, 1),
				WidthScale = NSeq(1, 0.3),
				Lifetime = 0.35,
				LightEmission = 0,
				LightInfluence = 1,
				FaceCamera = true,
				Parent = rock,
			})
		end
		local life = o.Life or rng:NextNumber(1.6, 2.6)
		task.delay(life, function()
			if rock.Parent then
				Effects.Tween(rock, 0.5, { Size = Vector3.new(0.05, 0.05, 0.05), Transparency = 1 })
			end
		end)
		Debris:AddItem(rock, life + 0.6)
	end
end

-- Felsspitzen, die im Kreis aus dem Boden brechen und sich nach aussen neigen.
-- opts: Color, Material, MinHeight, MaxHeight, Stay, WidthScale
function Effects.GroundSpikes(center: Vector3, radius: number, count: number, opts: { [string]: any }?)
	local o = opts or {}
	local stay = o.Stay or 1.2
	local col0: Color3
	local mat0: Mat
	if o.Color then
		col0, mat0 = o.Color, o.Material or Enum.Material.Slate
	else
		local _, gcol, gmat = Effects.GroundInfo(center)
		col0, mat0 = rockFrom(gcol, gmat)
		if o.Material then
			mat0 = o.Material
		end
	end
	local n = math.max(3, math.floor(count * math.max(Effects.Quality, 0.5)))
	local ws = o.WidthScale or 1
	for i = 1, n do
		local a = (i / n) * TAU + rng:NextNumber(-0.15, 0.15)
		local r = radius * rng:NextNumber(0.85, 1.15)
		local h = rng:NextNumber(o.MinHeight or 3, o.MaxHeight or 6)
		local w = rng:NextNumber(1.4, 2.6) * ws
		local base = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		-- LookVector zeigt zur Mitte; positive X-Drehung kippt die Spitze nach aussen
		local tilt = CFrame.lookAt(base, Vector3.new(center.X, base.Y, center.Z))
			* CFrame.Angles(math.rad(rng:NextNumber(16, 36)), 0, rng:NextNumber(-0.25, 0.25))
			* CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
		local pointy = i % 3 ~= 0
		local size = if pointy then Vector3.new(w * 0.8, h, w * 1.15) else Vector3.new(w, h * 0.7, w * rng:NextNumber(0.8, 1.2))
		local props = {
			Size = size,
			Material = mat0,
			Color = vary(col0, 0.08),
			CFrame = tilt * CFrame.new(0, -size.Y * 0.6, 0),
			CastShadow = true,
		}
		local rock: BasePart = if pointy then Effects.Wedge(props) else Effects.Part(props)
		local up = tilt * CFrame.new(0, size.Y * 0.2, 0)
		local down = tilt * CFrame.new(0, -size.Y * 0.65, 0)
		local delayT = (o.Stagger or 0) * (i / n)
		Effects.Tween(rock, 0.13, { CFrame = up }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, delayT)
		task.delay(stay + delayT, function()
			if rock.Parent then
				Effects.Tween(rock, 0.5, { CFrame = down }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end)
		Debris:AddItem(rock, stay + delayT + 0.6)
	end
end

-- Risse im Boden: dunkle, gezackte Linien; optional mit duenner Glut in "color", die schnell verblasst.
-- opts: NoGlow, Dark (Farbe der Risse)
function Effects.Cracks(center: Vector3, count: number, length: number, color: Color3, duration: number, opts: { [string]: any }?)
	local o = opts or {}
	local dark: Color3 = o.Dark or Effects.GroundColor(center):Lerp(BLACK, 0.7)
	local glow = not o.NoGlow
	local n = math.max(2, math.floor(count * math.max(Effects.Quality, 0.5)))
	local y = Vector3.new(0, 0.06, 0)
	for i = 1, n do
		local ang = (i / n) * TAU + rng:NextNumber(-0.3, 0.3)
		local total = length * rng:NextNumber(0.6, 1.1)
		local segs = if total > 6 then 3 else 2
		local p = center + Vector3.new(math.cos(ang), 0, math.sin(ang)) * 0.4
		for s = 1, segs do
			local segLen = total / segs
			ang += rng:NextNumber(-0.45, 0.45)
			local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
			local q = p + dir * segLen
			local w = (1 - (s - 1) / segs) * rng:NextNumber(0.3, 0.5)
			local mid = (p + q) / 2 + y
			local cf = CFrame.lookAt(mid, mid + dir)
			local grow = 0.08 + s * 0.04
			local crack = Effects.Part({
				Size = Vector3.new(w, 0.08, 0.1),
				CFrame = cf,
				Color = dark,
				Material = Enum.Material.SmoothPlastic,
				Transparency = 0.1,
			})
			Effects.Tween(crack, grow, { Size = Vector3.new(w, 0.08, segLen + w * 0.5) })
			Effects.Tween(crack, duration * 0.4, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, duration * 0.6)
			Debris:AddItem(crack, duration + 0.1)
			if glow then
				local line = Effects.Part({
					Size = Vector3.new(w * 0.35, 0.1, 0.1),
					CFrame = cf + Vector3.new(0, 0.02, 0),
					Color = color,
					Transparency = 0.1,
				})
				local glowTime = math.min(0.7, duration * 0.5)
				Effects.Tween(line, grow, { Size = Vector3.new(w * 0.35, 0.1, segLen) })
				Effects.Tween(line, glowTime, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, grow)
				Debris:AddItem(line, grow + glowTime + 0.1)
			end
			p = q
		end
	end
end

-- Charaktere ----------------------------------------------------------------------------

function Effects.GetPart(character: Model?, ...: string): BasePart?
	if not character then
		return nil
	end
	for _, name in { ... } do
		local p = character:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			return p :: BasePart
		end
	end
	return nil
end

function Effects.Root(character: Model?): BasePart?
	return Effects.GetPart(character, "HumanoidRootPart", "Torso", "UpperTorso")
end

-- Position der Hand (Unterseite des Arms)
function Effects.HandPosition(character: Model?, side: string?): Vector3?
	local isLeft = side == "Left"
	local hand = Effects.GetPart(character, if isLeft then "LeftHand" else "RightHand")
	if hand then
		return hand.Position
	end
	local arm = Effects.GetPart(character, if isLeft then "Left Arm" else "Right Arm")
	if arm then
		return (arm.CFrame * CFrame.new(0, -arm.Size.Y / 2, 0)).Position
	end
	local root = Effects.Root(character)
	return if root then root.Position else nil
end

function Effects.HandPart(character: Model?, side: string?): BasePart?
	local isLeft = side == "Left"
	return Effects.GetPart(character, if isLeft then "LeftHand" else "RightHand", if isLeft then "Left Arm" else "Right Arm")
end

-- Halbtransparente Kopie des Charakters, die verblasst. Farbige Energie leuchtet (Neon),
-- dunkle Farben (Schatten/Tinte) und fast weisse Farben (Tempo-Geist) bleiben matt.
function Effects.Afterimage(character: Model?, color: Color3, duration: number, startTransparency: number?, offset: CFrame?)
	if not character then
		return
	end
	local lum = color.R * 0.3 + color.G * 0.59 + color.B * 0.11
	local glowing = lum > 0.3 and lum < 0.85
	local model = Make("Model", { Name = "Afterimage", Parent = folder })
	for _, child in character:GetChildren() do
		if child:IsA("BasePart") then
			local part = child :: BasePart
			if part.Name ~= "HumanoidRootPart" and part.Transparency < 1 then
				local ghost: BasePart
				if part:IsA("MeshPart") then
					local ok, clone = pcall(function()
						return part:Clone()
					end)
					if ok and clone then
						for _, c in clone:GetChildren() do
							c:Destroy()
						end
						ghost = clone :: BasePart
					else
						ghost = Effects.Part({ Size = part.Size })
					end
				else
					ghost = Effects.Part({ Size = part.Size })
				end
				ghost.Anchored = true
				ghost.CanCollide = false
				ghost.CanQuery = false
				ghost.CanTouch = false
				ghost.CastShadow = false
				ghost.Material = if glowing then Enum.Material.Neon else Enum.Material.SmoothPlastic
				ghost.Color = color
				ghost.Transparency = startTransparency or 0.35
				ghost.LocalTransparencyModifier = 0
				ghost.CFrame = if offset then offset * part.CFrame else part.CFrame
				ghost.Parent = model
				Effects.Tween(ghost, duration, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end
	end
	Debris:AddItem(model, duration + 0.1)
	return model
end

-- Kurzes Aufleuchten (Treffer-Feedback)
function Effects.HitFlash(character: Model?, color: Color3?, duration: number?)
	if not character then
		return
	end
	local old = character:FindFirstChild("NovaHitFlash")
	if old then
		old:Destroy()
	end
	local h = Make("Highlight", {
		Name = "NovaHitFlash",
		Adornee = character,
		FillColor = color or WHITE,
		FillTransparency = 0.1,
		OutlineColor = color or WHITE,
		OutlineTransparency = 0.3,
		DepthMode = Enum.HighlightDepthMode.Occluded,
		Parent = character,
	})
	local d = duration or 0.14
	Effects.Tween(h, d, { FillTransparency = 1, OutlineTransparency = 1 })
	Debris:AddItem(h, d + 0.05)
end

-- Charakter lokal ein-/ausblenden
function Effects.SetCharacterVisible(character: Model?, visible: boolean)
	if not character then
		return
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			(d :: BasePart).LocalTransparencyModifier = if visible then 0 else 1
		elseif d:IsA("Decal") then
			(d :: Decal).LocalTransparencyModifier = if visible then 0 else 1
		end
	end
end

-- Trail an einem Teil
function Effects.Trail(part: BasePart, color: ColorSequence | Color3, lifetime: number, width: number, duration: number?): Trail
	local a0 = Make("Attachment", { Position = Vector3.new(0, width / 2, 0), Parent = part })
	local a1 = Make("Attachment", { Position = Vector3.new(0, -width / 2, 0), Parent = part })
	local seq = if typeof(color) == "Color3" then ColorSequence.new(color :: Color3) else color :: ColorSequence
	local trail = Make("Trail", {
		Attachment0 = a0,
		Attachment1 = a1,
		Color = seq,
		Lifetime = lifetime,
		LightEmission = 1,
		LightInfluence = 0,
		Transparency = NSeq(0.1, 1),
		WidthScale = NSeq(1, 0),
		FaceCamera = true,
		Parent = part,
	})
	if duration then
		task.delay(duration, function()
			trail.Enabled = false
			Debris:AddItem(trail, lifetime + 0.1)
			Debris:AddItem(a0, lifetime + 0.1)
			Debris:AddItem(a1, lifetime + 0.1)
		end)
	end
	return trail
end

-- Treffer-Gefuehl -----------------------------------------------------------------------

-- Hit-Stop: friert die Animationen der Charaktere kurz ein (lokal) und laesst sie dann weiterlaufen
local frozenTracks: { [AnimationTrack]: number } = setmetatable({}, { __mode = "k" }) :: any

function Effects.HitStop(characters: { Model? }, duration: number)
	local d = math.clamp(duration, 0, 0.3)
	if d <= 0 then
		return
	end
	local paused: { AnimationTrack } = {}
	for _, ch in characters do
		if typeof(ch) == "Instance" and ch.Parent then
			local animator = ch:FindFirstChildWhichIsA("Animator", true)
			if animator then
				local ok, tracks = pcall(function()
					return (animator :: Animator):GetPlayingAnimationTracks()
				end)
				if ok and type(tracks) == "table" then
					for _, track in tracks do
						if frozenTracks[track] == nil then
							frozenTracks[track] = track.Speed
							pcall(function()
								track:AdjustSpeed(0)
							end)
							table.insert(paused, track)
						end
					end
				end
			end
		end
	end
	if #paused == 0 then
		return
	end
	task.delay(d, function()
		for _, track in paused do
			local speed = frozenTracks[track]
			frozenTracks[track] = nil
			if speed then
				pcall(function()
					track:AdjustSpeed(speed)
				end)
			end
		end
	end)
end

-- Impact-Frame: 1-3 Frames hart kontrastiertes Schwarz-Weiss-Bild (nur fuer grosse Treffer)
local lastImpactFrame = 0
function Effects.ImpactFrame(duration: number?, strength: number?)
	local now = os.clock()
	if now - lastImpactFrame < 0.3 then
		return
	end
	lastImpactFrame = now
	local d = math.clamp(duration or 0.05, 0.02, 0.12)
	local s = math.clamp(strength or 1, 0.2, 1.5)
	local cc = Make("ColorCorrectionEffect", {
		Name = "NovaImpactFrame",
		Saturation = -1,
		Contrast = 0.9 * s,
		Brightness = 0.08 * s,
		TintColor = WHITE,
		Parent = Lighting,
	})
	-- zweites Bild: dunkler und leicht warm, wirkt wie ein invertierter Frame
	task.delay(d * 0.5, function()
		if cc.Parent then
			cc.Brightness = -0.14 * s
			cc.TintColor = C(255, 238, 230)
		end
	end)
	Debris:AddItem(cc, d)
end

-- Sound -----------------------------------------------------------------------------------

function Effects.Sound(name: string, at: (Vector3 | Instance)?, opts: { [string]: any }?): Sound?
	local def = Sounds[name]
	if not def then
		return nil
	end
	local o = opts or {}
	local sound = Make("Sound", {
		SoundId = def.Id,
		Volume = def.Volume * (o.Volume or 1),
		PlaybackSpeed = (def.Pitch or 1) * (o.Pitch or 1) * (1 + rng:NextNumber(-1, 1) * (o.Variance or 0.06)),
		RollOffMaxDistance = o.MaxDistance or 260,
		RollOffMinDistance = 12,
		RollOffMode = Enum.RollOffMode.InverseTapered,
	})
	local life = o.Life or 6
	if at == nil then
		sound.Parent = soundFolder
	elseif typeof(at) == "Vector3" then
		local anchor = Effects.Anchor(at :: Vector3, life)
		sound.Parent = anchor
	else
		sound.Parent = at :: Instance
	end
	sound:Play()
	Debris:AddItem(sound, life)
	return sound
end

-- Bildschirm ---------------------------------------------------------------------------

local player = Players.LocalPlayer
local screen = Make("ScreenGui", {
	Name = "NovaVFXScreen",
	DisplayOrder = 50,
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})
Effects.Screen = screen

function Effects.ScreenFlash(color: Color3, duration: number, startTransparency: number?)
	local frame = Make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = startTransparency or 0,
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = screen,
	})
	Effects.Tween(frame, duration, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	Debris:AddItem(frame, duration + 0.05)
end

-- Farbige Raender wenn man getroffen wird
function Effects.Vignette(color: Color3, duration: number, strength: number?)
	local s = strength or 0.35
	local holder = Make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 9, Parent = screen })
	local sides = {
		{ UDim2.fromScale(1, s), UDim2.fromScale(0, 0), 90 },
		{ UDim2.fromScale(1, s), UDim2.fromScale(0, 1 - s), -90 },
		{ UDim2.fromScale(s * 0.6, 1), UDim2.fromScale(0, 0), 0 },
		{ UDim2.fromScale(s * 0.6, 1), UDim2.fromScale(1 - s * 0.6, 0), 180 },
	}
	for _, side in sides do
		local f = Make("Frame", {
			Size = side[1],
			Position = side[2],
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = holder,
		})
		Make("UIGradient", {
			Rotation = side[3],
			Transparency = NSeq(0.15, 1),
			Parent = f,
		})
		Effects.Tween(f, duration, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	Debris:AddItem(holder, duration + 0.05)
end

-- Farbkorrektur fuer dramatische Momente (lokal)
function Effects.ColorGrade(props: { [string]: any }, fadeIn: number, hold: number, fadeOut: number)
	local cc = Make("ColorCorrectionEffect", { Name = "NovaGrade", Parent = Lighting })
	Effects.Tween(cc, fadeIn, props, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	task.delay(fadeIn + hold, function()
		Effects.Tween(cc, fadeOut, {
			Brightness = 0,
			Contrast = 0,
			Saturation = 0,
			TintColor = WHITE,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	end)
	Debris:AddItem(cc, fadeIn + hold + fadeOut + 0.1)
	return cc
end

-- Atmosphaere voruebergehend einfaerben
function Effects.AtmosphereTint(color: Color3, decay: Color3, fadeIn: number, hold: number, fadeOut: number)
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmo then
		return
	end
	local a = atmo :: Atmosphere
	local orig = { Color = a.Color, Decay = a.Decay, Density = a.Density }
	Effects.Tween(a, fadeIn, { Color = color, Decay = decay, Density = math.min(orig.Density + 0.15, 0.6) })
	task.delay(fadeIn + hold, function()
		Effects.Tween(a, fadeOut, orig)
	end)
end

Effects.Shake = CameraShake.Shake
Effects.ShakeAt = CameraShake.ShakeAt

-- Ist die Kamera nah genug, um aufwaendige Effekte zu sehen?
function Effects.Near(position: Vector3, distance: number): boolean
	local cam = workspace.CurrentCamera
	return cam ~= nil and (cam.CFrame.Position - position).Magnitude <= distance
end

return Effects
