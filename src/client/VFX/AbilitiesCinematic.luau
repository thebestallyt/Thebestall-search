-- VFX + Kino-Cutscenes der Mythischen, Goettlichen und Exklusiven Faehigkeiten.
-- Alle Spieler sehen die Welt-Effekte. Beteiligte (Zaubernder + Ziele) bekommen zusaetzlich die Kinokamera.
--
-- Stil-Regeln (neue Art Direction):
-- * geerdet und filmisch: Staub und Brocken in der Farbe des Bodens, echtes Licht (Spot/Point), Schatten
-- * Partikel in Schichten: heller Kern -> farbige Mitte -> dunkler Rauch
-- * Schnitte als Trails, kurze Blitze, Impact-Frames + Hit-Stop + Kamerawackeln am Hoehepunkt
-- * Neon nur fuer kleine, heisse Kerne (Hohlkehle, Edelsteine, Sternkern) - nie fuer grosse flache Formen
-- * die sonnige Welt wird waehrend der Cutscene dramatisch gegradet und danach sauber wiederhergestellt

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Make = require(Shared:WaitForChild("Make"))
local Abilities = require(Shared:WaitForChild("Abilities"))
local Rarities = require(Shared:WaitForChild("Rarities"))

local VFX = script.Parent :: Instance
local Effects = require(VFX:WaitForChild("Effects"))
local Poser = require(VFX:WaitForChild("Poser"))
local Cutscene = require(VFX:WaitForChild("Cutscene"))

local C = {}

local TEX = Effects.Textures
local P = Poser.Poses
local rng = Effects.Random
local NSeq, Seq = Effects.NSeq, Effects.Seq
local RGB = Color3.fromRGB
local TAU = math.pi * 2
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local UP = Vector3.yAxis

type Mat = typeof(Enum.Material.Grass)

-- =============================================================================
-- Allgemeine Hilfsfunktionen
-- =============================================================================

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude < 1e-3 then Vector3.new(0, 0, -1) else f.Unit
end

local function rotateY(v: Vector3, angle: number): Vector3
	return CFrame.Angles(0, angle, 0):VectorToWorldSpace(v)
end

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Fortschritt (0..1) von t im Zeitfenster [t0, t1]
local function window(t: number, t0: number, t1: number): number
	return clamp01((t - t0) / math.max(t1 - t0, 1e-3))
end

local function randomUnit(): Vector3
	local v = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
	return if v.Magnitude < 1e-3 then UP else v.Unit
end

local function q(n: number): number
	return math.max(1, math.floor(n * math.max(Effects.Quality, 0.35)))
end

-- Fuehrt fn nur aus, wenn die Cutscene noch laeuft
local function at(token: number?, t: number, fn: () -> ())
	task.delay(t, function()
		if token and Cutscene.IsCurrent(token) then
			fn()
		end
	end)
end

local function beginCutscene(ctx: any, def: any, extra: { [string]: any }?): number?
	if not ctx.Involved then
		return nil
	end
	local rarity = Rarities.Get(def.Rarity)
	local opts: { [string]: any } = {
		Title = string.upper(def.Name),
		Subtitle = rarity.Name .. " ABILITY",
		Color = rarity.Color,
		Hold = 1.9,
		MaxDuration = def.CutsceneDuration + 3,
	}
	if extra then
		for k, v in extra do
			opts[k] = v
		end
	end
	local token = Cutscene.Begin(opts)
	task.delay(def.CutsceneDuration, function()
		Cutscene.End(token)
	end)
	return token
end

-- Ordner fuer alle langlebigen Teile einer Faehigkeit (wird spaetestens nach "life" geloescht)
local function newScene(name: string, life: number): Folder
	local folder = Make("Folder", { Name = "Cinematic_" .. name, Parent = Effects.Folder })
	Effects.Clean(folder, life)
	return folder
end

local function targetRoots(p: any): { BasePart }
	local list = {}
	for _, ch in p.Targets or {} do
		local r = Effects.Root(ch)
		if r then
			table.insert(list, r)
		end
	end
	return list
end

local function involvedChars(p: any): { Model }
	local list = {}
	if p.Caster then
		table.insert(list, p.Caster)
	end
	for _, ch in p.Targets or {} do
		table.insert(list, ch)
	end
	return list
end

-- Kamerafahrt im Kreis als Funktion (fuer Whip / Shot)
local function orbitFn(
	center: () -> Vector3,
	r0: number,
	r1: number,
	h0: number,
	h1: number,
	a0: number,
	a1: number,
	duration: number,
	lookOffset: Vector3?
): (number) -> CFrame
	local d = math.max(duration, 0.01)
	return function(t: number): CFrame
		local a = Effects.Ease(clamp01(t / d), "InOut")
		local c = center()
		local pos = c + Vector3.new(math.cos(lerp(a0, a1, a)) * lerp(r0, r1, a), lerp(h0, h1, a), math.sin(lerp(a0, a1, a)) * lerp(r0, r1, a))
		return CFrame.lookAt(pos, c + (lookOffset or Vector3.zero))
	end
end

-- =============================================================================
-- Teile & Modelle
-- =============================================================================

-- Solides, nicht kollidierendes Bauteil (Part, WedgePart ...)
local function solid(className: string, props: { [string]: any }): BasePart
	local part = Instance.new(className) :: BasePart
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		if k ~= "Parent" then
			(part :: any)[k] = v
		end
	end
	part.Parent = props.Parent
	return part
end

-- Ellipsoid (Kugel-Mesh, frei skalierbar)
local function ellipsoid(parent: Instance, size: Vector3, color: Color3, material: Mat, transparency: number): Part
	local p = Effects.Part({ Size = size, Color = color, Material = material, Transparency = transparency, Parent = parent })
	Make("SpecialMesh", { MeshType = Enum.MeshType.Sphere, Parent = p })
	return p
end

-- Mehrteiliges Modell, das als Ganzes bewegt wird (BulkMoveTo)
type Rig = { Parts: { BasePart }, Offsets: { CFrame }, Buffer: { CFrame } }

local function newRig(): Rig
	return { Parts = {}, Offsets = {}, Buffer = {} }
end

local function rigAdd(rig: Rig, part: BasePart, offset: CFrame)
	table.insert(rig.Parts, part)
	table.insert(rig.Offsets, offset)
	table.insert(rig.Buffer, offset)
end

local function rigMove(rig: Rig, cf: CFrame)
	for i, off in rig.Offsets do
		rig.Buffer[i] = cf * off
	end
	workspace:BulkMoveTo(rig.Parts, rig.Buffer, Enum.BulkMoveMode.FireCFrameChanged)
end

-- =============================================================================
-- Boden: Terrain + Map (Farbe/Material fuer Staub und Brocken)
-- =============================================================================

type GroundInfo = {
	Position: Vector3,
	Normal: Vector3,
	Color: Color3,
	Material: Mat,
	Water: boolean,
	Terrain: boolean,
}

local DIRT = RGB(118, 92, 66)
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.IgnoreWater = false

local function probe(pos: Vector3, up: number?, down: number?): GroundInfo
	local list: { Instance } = { workspace.Terrain }
	local map = workspace:FindFirstChild("Map")
	if map then
		table.insert(list, map)
	end
	groundParams.FilterDescendantsInstances = list
	local u = up or 6
	local res = workspace:Raycast(pos + Vector3.new(0, u, 0), Vector3.new(0, -(u + (down or 60)), 0), groundParams)
	if not res then
		return {
			Position = pos - Vector3.new(0, 3, 0),
			Normal = UP,
			Color = DIRT,
			Material = Enum.Material.Ground,
			Water = false,
			Terrain = true,
		}
	end
	local hit = res.Instance
	local isTerrain = hit == workspace.Terrain
	local color = DIRT
	if isTerrain then
		local ok, c = pcall(function()
			return workspace.Terrain:GetMaterialColor(res.Material)
		end)
		if ok and typeof(c) == "Color3" then
			color = c
		end
	elseif hit:IsA("BasePart") then
		color = (hit :: BasePart).Color
	end
	return {
		Position = res.Position,
		Normal = res.Normal,
		Color = color,
		Material = res.Material,
		Water = res.Material == Enum.Material.Water,
		Terrain = isTerrain,
	}
end

-- Kameraposition absichern: nicht hinter Waenden/Bergen (Strahl vom Motiv aus) und nicht im Boden
local camParams = RaycastParams.new()
camParams.FilterType = Enum.RaycastFilterType.Include
camParams.IgnoreWater = true

local function clearCam(target: Vector3, desired: Vector3, minAbove: number?): Vector3
	local list: { Instance } = { workspace.Terrain }
	local map = workspace:FindFirstChild("Map")
	if map then
		table.insert(list, map)
	end
	camParams.FilterDescendantsInstances = list
	local pos = desired
	local dir = desired - target
	if dir.Magnitude > 0.5 then
		local hit = workspace:Raycast(target, dir, camParams)
		if hit then
			pos = hit.Position - dir.Unit * 2
		end
	end
	local g = probe(pos, 6, 40)
	local minY = g.Position.Y + (minAbove or 1.2)
	if pos.Y < minY then
		pos = Vector3.new(pos.X, minY, pos.Z)
	end
	return pos
end

local function isGrass(m: Mat): boolean
	return m == Enum.Material.Grass or m == Enum.Material.LeafyGrass
end

-- Staubfarbe passend zum Boden (Wiese -> erdiger Staub, Schnee -> weiss, Wasser -> Gischt)
local function dustTone(info: GroundInfo): Color3
	if info.Water then
		return RGB(226, 238, 242)
	end
	local m = info.Material
	if m == Enum.Material.Snow then
		return RGB(240, 244, 250)
	end
	if isGrass(m) or m == Enum.Material.Mud or m == Enum.Material.Ground then
		return info.Color:Lerp(RGB(168, 146, 114), 0.7)
	end
	return info.Color:Lerp(RGB(178, 166, 148), 0.45)
end

-- Brocken-Aussehen: Oberseite (Farbe, Material) und Erdreich darunter (Farbe, Material)
local function chunkLook(info: GroundInfo): (Color3, Mat, Color3, Mat)
	local m = info.Material
	if isGrass(m) then
		return info.Color, Enum.Material.Grass, DIRT, Enum.Material.Ground
	elseif m == Enum.Material.Snow then
		return RGB(240, 244, 250), Enum.Material.Snow, RGB(128, 126, 124), Enum.Material.Slate
	elseif m == Enum.Material.Sand then
		return info.Color, Enum.Material.Sand, info.Color:Lerp(DIRT, 0.4), Enum.Material.Sand
	elseif info.Terrain then
		return info.Color, Enum.Material.Slate, info.Color:Lerp(BLACK, 0.25), Enum.Material.Slate
	end
	local mat = if m == Enum.Material.Neon or m == Enum.Material.Air or m == Enum.Material.Water or m == Enum.Material.ForceField
		then Enum.Material.Slate
		else m
	return info.Color, mat, info.Color:Lerp(BLACK, 0.2), mat
end

-- =============================================================================
-- Partikel- und Boden-Effekte
-- =============================================================================

-- Rauch weich einblenden, langsam ausblenden
local SMOKE_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.1, 0.32),
	NumberSequenceKeypoint.new(0.6, 0.62),
	NumberSequenceKeypoint.new(1, 1),
})

-- Eigenschaften fuer beleuchteten Rauch/Staub (leuchtet NICHT selbst)
local function smoke(color: Color3, props: { [string]: any }): { [string]: any }
	local out: { [string]: any } = {
		Texture = TEX.Smoke,
		Color = ColorSequence.new(color),
		LightEmission = 0,
		LightInfluence = 1,
		Transparency = SMOKE_FADE,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-25, 25),
	}
	for k, v in props do
		out[k] = v
	end
	return out
end

local function sparks(pos: Vector3, count: number, core: Color3, mid: Color3, speedMin: number, speedMax: number, gravity: number?)
	Effects.Burst(pos, count, {
		Texture = TEX.Sparks,
		Color = Seq(core, mid),
		LightEmission = 1,
		LightInfluence = 0,
		Speed = NumberRange.new(speedMin, speedMax),
		Lifetime = NumberRange.new(0.25, 0.65),
		Size = NSeq(0.45, 0),
		Drag = 3,
		Acceleration = Vector3.new(0, -(gravity or 30), 0),
		SpreadAngle = Vector2.new(180, 180),
	})
end

-- Staubwolken entlang eines Kreises; jede Wolke folgt dem Boden und fliegt nach aussen (oder innen)
local function dustRing(center: Vector3, radius: number, count: number, opts: { [string]: any }?)
	local o = opts or {}
	local n = math.max(3, q(count))
	local speed: number = o.Speed or 22
	local life: number = o.Life or 1.6
	for i = 1, n do
		local ang = (i / n) * TAU + rng:NextNumber(-0.25, 0.25)
		local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
		local info = probe(center + dir * radius, 6, 40)
		local col: Color3 = o.Color or dustTone(info)
		local move = if o.Inward then -dir else dir
		Effects.BurstDir(
			info.Position + Vector3.new(0, o.Lift or 0.8, 0),
			move + Vector3.new(0, o.Rise or 0.2, 0),
			o.Per or 3,
			smoke(col, {
				Size = NSeq(o.Size0 or 4, o.Size1 or 10),
				Speed = NumberRange.new(speed * 0.55, speed),
				Drag = o.Drag or 2.6,
				Lifetime = NumberRange.new(life * 0.65, life),
				SpreadAngle = Vector2.new(18, 18),
				Acceleration = Vector3.new(0, o.Buoyancy or 1.5, 0),
			})
		)
	end
end

-- Staubwelle, die sich ueber den Boden ausbreitet (mehrere Ringe nacheinander)
local function dustWave(center: Vector3, maxRadius: number, duration: number, opts: { [string]: any }?)
	local o = opts or {}
	local rings = 4
	for i = 1, rings do
		local k = i / rings
		task.delay(duration * (k - 1 / rings), function()
			dustRing(center, maxRadius * (0.18 + 0.82 * k), math.floor(8 + 10 * k), {
				Speed = (o.Speed or 26) * (0.7 + 0.3 * k),
				Size0 = (o.Size0 or 4) * (0.8 + 0.4 * k),
				Size1 = (o.Size1 or 11) * (0.8 + 0.4 * k),
				Life = o.Life or 1.8,
				Color = o.Color,
				Per = 2,
			})
		end)
	end
end

local function smokeColumn(pos: Vector3, color: Color3, count: number, height: number)
	Effects.Burst(
		pos + Vector3.new(0, 1, 0),
		count,
		smoke(color, {
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(35, 35),
			Speed = NumberRange.new(height * 0.4, height),
			Drag = 1.8,
			Lifetime = NumberRange.new(1.6, 2.8),
			Size = NSeq(6, 16),
			Acceleration = Vector3.new(0, 2, 0),
		})
	)
end

-- Erd-/Grasbrocken in Bodenfarbe (auf Wasser: Gischt)
local function groundChunks(center: Vector3, count: number, info: GroundInfo, opts: { [string]: any }?)
	local o = opts or {}
	if info.Water then
		Effects.Burst(center + Vector3.new(0, 1, 0), count * 2, {
			Texture = TEX.Smoke,
			Color = ColorSequence.new(RGB(232, 244, 248)),
			LightEmission = 0.1,
			LightInfluence = 1,
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(40, 40),
			Speed = NumberRange.new(20, 45),
			Lifetime = NumberRange.new(0.6, 1.2),
			Size = NSeq(1.5, 4),
			Transparency = NSeq(0.2, 1),
			Acceleration = Vector3.new(0, -50, 0),
			Drag = 1,
		})
		return
	end
	local topC, topM, botC, botM = chunkLook(info)
	local half = math.ceil(count * 0.55)
	local spread: number = o.Spread or 40
	local maxUp: number = o.MaxUp or 55
	local minUp: number = o.MinUp or 25
	local maxSize: number = o.MaxSize or 1.8
	Effects.Rocks(center, half, { Color = topC, Material = topM, Spread = spread, MinUp = minUp, MaxUp = maxUp, MinSize = 0.6, MaxSize = maxSize })
	Effects.Rocks(center, count - half, {
		Color = botC,
		Material = botM,
		Spread = spread * 0.8,
		MinUp = minUp,
		MaxUp = maxUp * 0.85,
		MinSize = 0.6,
		MaxSize = maxSize * 1.2,
	})
end

-- Kraterrand: Erdplatten brechen hoch und kippen nach aussen
local function craterRim(parent: Instance, center: Vector3, radius: number, count: number, info: GroundInfo, stay: number)
	if info.Water then
		return
	end
	local topC, topM, botC, botM = chunkLook(info)
	local grassy = isGrass(info.Material)
	for i = 1, count do
		local a = (i / count) * TAU + rng:NextNumber(-0.2, 0.2)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local base = probe(center + dir * radius * rng:NextNumber(0.85, 1.15), 6, 30).Position
		local w, h, d = rng:NextNumber(2.4, 4.4), rng:NextNumber(2.2, 4.2), rng:NextNumber(1, 1.8)
		local tilt = CFrame.lookAt(base, base + dir) * CFrame.Angles(math.rad(-rng:NextNumber(28, 55)), 0, rng:NextNumber(-0.25, 0.25))
		local down = tilt * CFrame.new(0, -h / 2 - 0.3, 0)
		local upCF = tilt * CFrame.new(0, h / 2 - 0.5, 0)
		local slab = Effects.Part({
			Size = Vector3.new(w, h, d),
			Color = if grassy then botC else topC,
			Material = if grassy then botM else topM,
			CastShadow = true,
			CFrame = down,
			Parent = parent,
		})
		local cap: Part? = nil
		if grassy then
			cap = Effects.Part({
				Size = Vector3.new(w + 0.1, 0.35, d + 0.1),
				Color = topC,
				Material = topM,
				CastShadow = true,
				CFrame = down * CFrame.new(0, h / 2, 0),
				Parent = parent,
			})
		end
		local riseT = rng:NextNumber(0.08, 0.14)
		Effects.Tween(slab, riseT, { CFrame = upCF }, Enum.EasingStyle.Back)
		if cap then
			Effects.Tween(cap, riseT, { CFrame = upCF * CFrame.new(0, h / 2, 0) }, Enum.EasingStyle.Back)
		end
		task.delay(stay, function()
			Effects.Tween(slab, 0.6, { CFrame = down }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			if cap then
				Effects.Tween(cap, 0.6, { CFrame = down * CFrame.new(0, h / 2, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end)
		Effects.Clean(slab, stay + 0.7)
		if cap then
			Effects.Clean(cap, stay + 0.7)
		end
	end
end

-- Dunkler Fleck auf dem Boden, der langsam waechst (Decal auf unsichtbarer Platte)
local function growMark(parent: Instance, position: Vector3, r0: number, r1: number, color: Color3, growTime: number, life: number)
	local mark = Effects.Part({
		Transparency = 1,
		Size = Vector3.new(r0 * 2, 0.05, r0 * 2),
		CFrame = CFrame.new(position + Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0),
		Parent = parent,
	})
	local decal = Make("Decal", {
		Texture = TEX.Smoke,
		Face = Enum.NormalId.Top,
		Color3 = color,
		Transparency = 0.15,
		Parent = mark,
	})
	Effects.Tween(mark, growTime, { Size = Vector3.new(r1 * 2, 0.05, r1 * 2) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	Effects.Tween(decal, 1.2, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, math.max(0, life - 1.2))
	Effects.Clean(mark, life + 0.1)
end

-- Kleiner, sehr heller Kern, der kurz aufblitzt (KEINE grosse Neon-Kugel)
local function hotCore(pos: Vector3, size: number, color: Color3, duration: number)
	local ball = Effects.Ball(CFrame.new(pos), size * 0.35, WHITE, { Material = Enum.Material.Neon, Transparency = 0 })
	Effects.Tween(ball, duration * 0.35, { Size = Vector3.one * size }, Enum.EasingStyle.Quart)
	Effects.Tween(
		ball,
		duration * 0.65,
		{ Transparency = 1, Size = Vector3.one * size * 1.15, Color = color },
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In,
		duration * 0.35
	)
	Effects.Clean(ball, duration + 0.05)
end

-- Druckwelle in der Luft: flimmernde ForceField-Huelle (wirkt wie Verzerrung)
local function airDistortion(pos: Vector3, size0: number, size1: number, duration: number, color: Color3?)
	local ball = Effects.Ball(CFrame.new(pos), size0, color or WHITE, { Material = Enum.Material.ForceField, Transparency = 0.1 })
	Effects.Tween(ball, duration, { Size = Vector3.one * size1, Transparency = 1 }, Enum.EasingStyle.Quart)
	Effects.Clean(ball, duration + 0.05)
end

-- Flache Bodenwelle (Textur), beleuchtet statt leuchtend wenn emission = 0
local function groundShock(pos: Vector3, size: number, color: Color3, duration: number, emission: number)
	local anchor, att = Effects.Anchor(pos)
	anchor.CFrame = CFrame.new(pos)
	local e = Effects.Emitter(att, {
		Texture = TEX.Shockwave,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		Speed = NumberRange.new(0.01),
		SpreadAngle = Vector2.new(0, 0),
		EmissionDirection = Enum.NormalId.Top,
		Lifetime = NumberRange.new(duration),
		Size = NSeq(size * 0.1, math.min(size, 100)),
		Transparency = NSeq(0.15, 1),
		Color = ColorSequence.new(color),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(0, 0),
		LightEmission = emission,
		LightInfluence = 1 - emission,
		ZOffset = 0.5,
	})
	e:Emit(1)
	Effects.Clean(anchor, duration + 0.3)
end

-- Kurze Ueberbelichtung (geblendet) - klingt schnell ab
local function exposurePop(brightness: number, time: number, tint: Color3?)
	local cc = Make("ColorCorrectionEffect", {
		Name = "NovaExposurePop",
		Brightness = brightness,
		Contrast = -0.1,
		Saturation = -0.25,
		TintColor = tint or WHITE,
		Parent = Lighting,
	})
	Effects.Tween(cc, time, { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = WHITE }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	Effects.Clean(cc, time + 0.05)
end

-- Ring aus Lichtern, der ueber den Boden nach aussen laeuft (Lichtwelle)
local function lightWave(center: Vector3, radius: number, duration: number, color: Color3, count: number)
	local lights = {}
	for i = 1, count do
		local anchor = Effects.Anchor(center)
		local light = Make("PointLight", { Color = color, Range = 22, Brightness = 5, Shadows = false, Parent = anchor })
		local ang = (i / count) * TAU
		table.insert(lights, { Anchor = anchor, Light = light, Dir = Vector3.new(math.cos(ang), 0, math.sin(ang)) })
		Effects.Clean(anchor, duration + 1)
	end
	Effects.Animate(duration, function(a)
		local r = radius * Effects.Ease(a, "OutCubic")
		for _, e in lights do
			e.Anchor.CFrame = CFrame.new(center + e.Dir * r + Vector3.new(0, 3, 0))
			e.Light.Brightness = 5 * (1 - a) ^ 1.5
		end
	end, function()
		for _, e in lights do
			e.Anchor:Destroy()
		end
	end)
end

-- =============================================================================
-- Trails: Schnitte und Streifen
-- =============================================================================

type SlashStyle = { Core: Color3, Mid: ColorSequence, Dark: Color3?, Width: number, Life: number, Emission: number? }

local function trailBand(arm: BasePart, r0: number, r1: number, color: ColorSequence, emission: number, transparency: NumberSequence, life: number)
	local a0 = Make("Attachment", { Position = Vector3.new(r0, 0, 0), Parent = arm })
	local a1 = Make("Attachment", { Position = Vector3.new(r1, 0, 0), Parent = arm })
	Make("Trail", {
		Attachment0 = a0,
		Attachment1 = a1,
		Color = color,
		Transparency = transparency,
		Lifetime = life,
		LightEmission = emission,
		LightInfluence = 0,
		FaceCamera = false,
		MinLength = 0,
		WidthScale = NSeq(1, 0.3),
		Parent = arm,
	})
end

-- Bogen-Schnitt aus Trails: ein unsichtbarer Arm dreht sich in der XY-Ebene von cf.
-- Schichten: dunkler Rand (innen) -> farbige Mitte -> weisser Kern an der Schneide.
local function trailSlash(cf: CFrame, radius: number, sweepDeg: number, duration: number, style: SlashStyle)
	local w = style.Width
	local arm = Effects.Part({ Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = cf })
	if style.Dark then
		trailBand(arm, radius - w, radius - w * 0.35, ColorSequence.new(style.Dark :: Color3), 0, NSeq(0.3, 1), style.Life * 1.15)
	end
	trailBand(arm, radius - w * 0.62, radius, style.Mid, style.Emission or 0.8, NSeq(0.05, 1), style.Life)
	trailBand(
		arm,
		radius - w * 0.16,
		radius + w * 0.04,
		ColorSequence.new(style.Core),
		1,
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		style.Life * 0.75
	)
	local sweep = math.rad(sweepDeg)
	Effects.Animate(duration, function(a)
		arm.CFrame = cf * CFrame.Angles(0, 0, sweep * Effects.Ease(a, "OutCubic"))
	end)
	Effects.Clean(arm, duration + style.Life * 1.2 + 0.15)
end

-- Schnitt quer durch einen Punkt: Bogenmitte liegt auf "pos", Ebene steht senkrecht zu "facing"
local function slashAcross(pos: Vector3, facing: Vector3, roll: number, radius: number, sweepDeg: number, duration: number, style: SlashStyle)
	local base = CFrame.lookAt(pos, pos + facing) * CFrame.Angles(0, 0, roll)
	local mid = (base * CFrame.Angles(0, 0, math.rad(sweepDeg) / 2)).RightVector
	trailSlash(base + (-mid * radius * 0.82), radius, sweepDeg, duration, style)
end

-- Schneller Streifen von A nach B (Dash)
local function streak(from: Vector3, to: Vector3, duration: number, color: ColorSequence, width: number, life: number)
	local mover = Effects.Part({ Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(from) })
	local a0 = Make("Attachment", { Position = Vector3.new(0, width / 2, 0), Parent = mover })
	local a1 = Make("Attachment", { Position = Vector3.new(0, -width / 2, 0), Parent = mover })
	Make("Trail", {
		Attachment0 = a0,
		Attachment1 = a1,
		Color = color,
		Transparency = NSeq(0, 1),
		Lifetime = life,
		LightEmission = 1,
		LightInfluence = 0,
		FaceCamera = true,
		MinLength = 0,
		WidthScale = NSeq(1, 0.15),
		Parent = mover,
	})
	Effects.Tween(mover, duration, { CFrame = CFrame.new(to) }, Enum.EasingStyle.Quart)
	Effects.Clean(mover, duration + life + 0.2)
end

-- Trail an einem Teil mit waagerechter Breite (fuer senkrecht bewegte Teile)
local function sideTrail(part: BasePart, color: ColorSequence, life: number, width: number): Trail
	local a0 = Make("Attachment", { Position = Vector3.new(-width / 2, 0, 0), Parent = part })
	local a1 = Make("Attachment", { Position = Vector3.new(width / 2, 0, 0), Parent = part })
	return Make("Trail", {
		Attachment0 = a0,
		Attachment1 = a1,
		Color = color,
		Transparency = NSeq(0.15, 1),
		Lifetime = life,
		LightEmission = 1,
		LightInfluence = 0,
		FaceCamera = true,
		MinLength = 0,
		WidthScale = NSeq(1, 0.2),
		Parent = part,
	})
end

-- =============================================================================
-- Welt-Grading: Licht, Atmosphaere, Wolken (Referenzzaehler -> sichere Wiederherstellung)
-- =============================================================================

local GRADE_PROPS: { [string]: { string } } = {
	Lighting = { "Ambient", "OutdoorAmbient", "Brightness", "ExposureCompensation" },
	Atmosphere = { "Color", "Decay", "Density", "Haze", "Glare" },
	SunRays = { "Intensity" },
	Bloom = { "Intensity" },
	Clouds = { "Color", "Cover", "Density" },
}

local gradeSaved: { [Instance]: { [string]: any } }? = nil
local gradeUsers = 0
local gradeSerial = 0

local function gradeTargets(): { [string]: Instance }
	local out: { [string]: Instance } = { Lighting = Lighting }
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo then
		out.Atmosphere = atmo
	end
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if rays then
		out.SunRays = rays
	end
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom then
		out.Bloom = bloom
	end
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		out.Clouds = clouds
	end
	return out
end

local function gradeSnapshot(): { [Instance]: { [string]: any } }
	local snap: { [Instance]: { [string]: any } } = {}
	for key, inst in gradeTargets() do
		local vals: { [string]: any } = {}
		local props = GRADE_PROPS[key]
		if props then
			for _, prop in props do
				local ok, v = pcall(function()
					return (inst :: any)[prop]
				end)
				if ok then
					vals[prop] = v
				end
			end
		end
		snap[inst] = vals
	end
	return snap
end

-- spec = { CC = {...}, Lighting = {...}, Atmosphere = {...}, SunRays = {...}, Bloom = {...}, Clouds = {...} }
local function worldGrade(spec: { [string]: any }, fadeIn: number, hold: number, fadeOut: number)
	if spec.CC then
		Effects.ColorGrade(spec.CC, fadeIn, hold, fadeOut)
	end
	if not gradeSaved then
		gradeSaved = gradeSnapshot()
	end
	gradeUsers += 1
	gradeSerial += 1
	local targets = gradeTargets()
	for key, props in spec do
		local inst = targets[key]
		if key ~= "CC" and inst then
			pcall(function()
				Effects.Tween(inst, fadeIn, props, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			end)
		end
	end
	task.delay(fadeIn + hold, function()
		gradeUsers = math.max(0, gradeUsers - 1)
		local saved = gradeSaved
		if gradeUsers == 0 and saved then
			for inst, vals in saved do
				if inst.Parent then
					pcall(function()
						Effects.Tween(inst, fadeOut, vals, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
					end)
				end
			end
			gradeSerial += 1
			local mine = gradeSerial
			task.delay(fadeOut + 0.1, function()
				if gradeSerial == mine and gradeUsers == 0 then
					gradeSaved = nil
				end
			end)
		end
	end)
end

-- =============================================================================
-- CELESTIAL JUDGMENT (Mythisch): Die Wolken reissen auf, ein gigantisches heiliges Schwert faellt
-- =============================================================================

-- Gottesstrahl (Beam ohne Textur, additiv) - Profil: oben weich, unten auslaufend
local function rayProfile(alpha: number): NumberSequence
	local core = 1 - 0.34 * alpha
	local low = 1 - 0.2 * alpha
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.1, core),
		NumberSequenceKeypoint.new(0.65, low),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local function godRay(parent: Instance, top: Vector3, bottom: Vector3, w0: number, w1: number, color: Color3): Beam
	local pa, aa = Effects.Anchor(top)
	local pb, ab = Effects.Anchor(bottom)
	pa.Parent = parent
	pb.Parent = parent
	return Make("Beam", {
		Attachment0 = aa,
		Attachment1 = ab,
		Color = ColorSequence.new(color),
		LightEmission = 1,
		LightInfluence = 0,
		Width0 = w0,
		Width1 = w1,
		FaceCamera = true,
		Segments = 12,
		Transparency = rayProfile(0),
		Parent = pa,
	})
end

local function fadeRays(rays: { Beam }, from: number, to: number, time: number)
	Effects.Animate(time, function(a)
		local profile = rayProfile(lerp(from, to, Effects.Ease(a, "InOut")))
		for _, beam in rays do
			beam.Transparency = profile
		end
	end)
end

-- Das heilige Schwert: Spitze aus Keilen, Hohlkehle, verzierte Parierstange, Griff, Knauf mit Edelstein.
-- Lokaler Raum: Y = Klingenachse (Spitze bei -Y), X = Klingenbreite, Z = Dicke. Ursprung = Klingenansatz.
local SWORD_BLADE = 46

local function buildHolySword(parent: Instance): { [string]: any }
	local model = Make("Model", { Name = "HolySword", Parent = parent })
	local rig = newRig()
	local targets: { number } = {}
	local L, TIP, W, TH = SWORD_BLADE, 8.5, 6.4, 1.3
	local body = L - TIP
	local steel = RGB(226, 226, 220)
	local edgeColor = RGB(250, 250, 247)
	local gold = RGB(236, 184, 74)
	local goldDark = RGB(178, 122, 40)
	local leather = RGB(84, 52, 36)
	local sapphire = RGB(64, 128, 255)
	local FOIL = Enum.Material.Foil

	local function add(className: string, props: { [string]: any }, offset: CFrame): BasePart
		table.insert(targets, props.Transparency or 0)
		props.Transparency = 1
		props.Parent = model
		local part = solid(className, props)
		rigAdd(rig, part, offset)
		return part
	end

	-- Klinge mit helleren, duenneren Schneiden (wirkt wie ein Schliff)
	local blade = add("Part", { Size = Vector3.new(W - 1.2, body, TH), Color = steel, Reflectance = 0.12, CastShadow = true }, CFrame.new(0, -body / 2, 0))
	for _, s in { -1, 1 } do
		add(
			"Part",
			{ Size = Vector3.new(0.62, body, TH * 0.5), Color = edgeColor, Reflectance = 0.3, CastShadow = true },
			CFrame.new(s * (W / 2 - 0.31), -body / 2, 0)
		)
	end
	-- Spitze aus zwei Keilen (rechte/linke Haelfte, Spitze auf der Mittellinie)
	local tipY = -(body + TIP / 2)
	add(
		"WedgePart",
		{ Size = Vector3.new(TH, TIP, W / 2), Color = steel, Reflectance = 0.12, CastShadow = true },
		CFrame.fromMatrix(Vector3.new(W / 4, tipY, 0), Vector3.new(0, 0, -1), Vector3.new(0, -1, 0), Vector3.new(-1, 0, 0))
	)
	add(
		"WedgePart",
		{ Size = Vector3.new(TH, TIP, W / 2), Color = steel, Reflectance = 0.12, CastShadow = true },
		CFrame.fromMatrix(Vector3.new(-W / 4, tipY, 0), Vector3.new(0, 0, 1), Vector3.new(0, -1, 0), Vector3.new(1, 0, 0))
	)
	-- Hohlkehle: schmaler heisser Lichtkern auf beiden Seiten
	add("Part", { Size = Vector3.new(W * 0.16, body * 0.8, TH + 0.14), Color = RGB(255, 224, 150), Material = Enum.Material.Neon }, CFrame.new(0, -body * 0.47, 0))
	-- Zierplatte am Klingenansatz
	add("Part", { Size = Vector3.new(W * 0.9, 2.4, TH + 0.5), Color = gold, Material = FOIL, CastShadow = true }, CFrame.new(0, -1.4, 0))
	-- Parierstange mit nach oben geschwungenen Enden
	add("Part", { Size = Vector3.new(5.4, 2.8, TH + 2), Color = gold, Material = FOIL, CastShadow = true }, CFrame.new(0, 1.3, 0))
	local finials: { BasePart } = {}
	for _, s in { -1, 1 } do
		add("Part", { Size = Vector3.new(7.6, 1.7, 1.9), Color = gold, Material = FOIL, CastShadow = true }, CFrame.new(s * 6.3, 1.6, 0) * CFrame.Angles(0, 0, s * math.rad(7)))
		add("Part", { Size = Vector3.new(3.6, 1.4, 1.7), Color = gold, Material = FOIL, CastShadow = true }, CFrame.new(s * 10.5, 2.8, 0) * CFrame.Angles(0, 0, s * math.rad(38)))
		table.insert(
			finials,
			add("Part", { Shape = Enum.PartType.Ball, Size = Vector3.new(1.8, 1.8, 1.8), Color = goldDark, Material = FOIL }, CFrame.new(s * 11.8, 4.1, 0))
		)
		-- Edelstein vorne/hinten in der Parierstange
		add("Part", { Shape = Enum.PartType.Ball, Size = Vector3.new(1.7, 1.7, 1.7), Color = sapphire, Material = Enum.Material.Neon }, CFrame.new(0, 1.3, s * (TH / 2 + 1)))
	end
	-- Griff mit Goldringen
	local upright = CFrame.Angles(0, 0, math.rad(90))
	add("Part", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(8.4, 1.7, 1.7), Color = leather, Material = Enum.Material.Fabric, CastShadow = true }, CFrame.new(0, 7, 0) * upright)
	for _, y in { 3.3, 7, 10.7 } do
		add("Part", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.45, 2.05, 2.05), Color = gold, Material = FOIL }, CFrame.new(0, y, 0) * upright)
	end
	-- Knauf + Edelstein (Raute)
	local pommel = add("Part", { Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3), Color = gold, Material = FOIL, CastShadow = true }, CFrame.new(0, 12.5, 0))
	add(
		"Part",
		{ Size = Vector3.new(1.5, 1.5, 1.5), Color = sapphire, Material = Enum.Material.Neon },
		CFrame.new(0, 14.3, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45))
	)

	local highlight = Make("Highlight", {
		Adornee = model,
		FillColor = WHITE,
		FillTransparency = 1,
		OutlineColor = RGB(255, 236, 190),
		OutlineTransparency = 1,
		DepthMode = Enum.HighlightDepthMode.Occluded,
		Parent = model,
	})
	local light = Make("PointLight", { Color = RGB(255, 228, 170), Range = 26, Brightness = 0, Shadows = false, Parent = blade })
	return {
		Model = model,
		Rig = rig,
		Targets = targets,
		Blade = blade,
		Highlight = highlight,
		Light = light,
		Streakers = { finials[1], finials[2], pommel },
	}
end

function C.CelestialJudgment(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local def = Abilities.Get("CelestialJudgment") :: any
	local T = def.Timing
	local R: number = T.Radius
	local D: number = def.CutsceneDuration
	local scene = newScene("CelestialJudgment", D + 7)

	local center: Vector3 = p.Extra.Center or Effects.Ground(p.Aim)
	local gInfo = probe(center, 6, 30)
	local base = gInfo.Position
	local dust = dustTone(gInfo)
	local rootCF = root.CFrame
	local toCaster = flat(rootCF.Position - base)
	local yaw = math.atan2(-toCaster.X, -toCaster.Z) -- Breitseite der Klinge zeigt zum Zaubernden
	local holy = RGB(255, 245, 222)
	local gold = RGB(255, 206, 104)
	local warm = RGB(255, 228, 176)
	local CLOUD_H = 100
	local HILT_TOP = 92
	local HILT_END = SWORD_BLADE - 8 -- Spitze steckt 8 Studs im Boden
	local swordY = HILT_TOP

	local function swordCF(y: number, extra: CFrame?): CFrame
		return CFrame.new(base + Vector3.new(0, y, 0)) * CFrame.Angles(0, yaw, 0) * (extra or CFrame.identity)
	end
	local function tipPos(): Vector3
		return base + Vector3.new(0, swordY - SWORD_BLADE, 0)
	end

	-- Kamera --------------------------------------------------------------
	local token = beginCutscene(ctx, def)
	if token then
		local front = flat(rootCF.LookVector)
		local right = front:Cross(UP)
		-- A) Ueber-die-Schulter-Untersicht: der Blick kippt vom Zaubernden hinauf in die Wolken
		Cutscene.Shot(function(t)
			local k = Effects.Ease(clamp01(t / T.Form), "InOut")
			local c = root.Position
			local pos = c - front * lerp(6.5, 4.6, k) + right * 2.6 + Vector3.new(0, lerp(-1.4, -0.9, k), 0)
			local look = (c + Vector3.new(0, 2.5, 0) + front * 6):Lerp(base + Vector3.new(0, 70, 0), k)
			return CFrame.lookAt(pos, look)
		end, 58, 0.01)
		-- B) Reissschwenk: Untersicht aus dem Gras auf das Schwert in der Wolkenluecke
		at(token, T.Form - 0.05, function()
			local offset = clearCam(base + Vector3.new(0, 30, 0), base + rotateY(toCaster, math.rad(38)) * 34 + Vector3.new(0, 2.4, 0), 1.6) - base
			local dur = T.Descend - T.Form + 0.05
			Cutscene.Whip(function(t)
				local pos = base + rotateY(offset, 0.12 * clamp01(t / dur))
				return CFrame.lookAt(pos, base + Vector3.new(0, swordY - 20, 0))
			end, 0.24, 52, 0.24)
		end)
		at(token, T.Form + 0.22, function()
			Cutscene.FOV(45, T.Descend - T.Form - 0.22)
		end)
		-- C) Der Sturz: Kamera im Gras, Blick steil nach oben auf die Spitze
		at(token, T.Descend, function()
			local camC = clearCam(base + Vector3.new(0, 20, 0), base + rotateY(toCaster, math.rad(-55)) * 14 + Vector3.new(0, 1.6, 0), 1.4)
			Cutscene.Shot(function()
				return CFrame.lookAt(camC, tipPos())
			end, 70, 0.15)
			Effects.Shake(0.6, 0.5)
		end)
		-- D) Totale von der Seite: das Schwert schlaegt ein
		local wideLook = base + Vector3.new(0, 16, 0)
		local wideCF = CFrame.lookAt(clearCam(wideLook, base + rotateY(toCaster, math.rad(96)) * 50 + Vector3.new(0, 12, 0), 3), wideLook)
		at(token, T.Impact - 0.3, function()
			Cutscene.Whip(function()
				return wideCF
			end, 0.12, 72, 0.12)
		end)
		-- E) Einschlag: Impact-Frame + Hit-Stop, dann langsames Zurueckziehen
		at(token, T.Impact, function()
			local look2 = base + Vector3.new(0, 12, 0)
			local cam2 = clearCam(look2, base + rotateY(toCaster, math.rad(104)) * 60 + Vector3.new(0, 19, 0), 3)
			Cutscene.Move(wideCF, CFrame.lookAt(cam2, look2), D - T.Impact + 0.3, "Out")
			Cutscene.FOV(76, D - T.Impact)
			Cutscene.ImpactFrame({ Characters = involvedChars(p), Tint = RGB(255, 210, 140) })
			Cutscene.HitStop(0.07)
		end)
	end

	-- Welt: Grading, Pose, Ruf in den Himmel ----------------------------------
	Poser.Sequence(caster, { { P.RightUp, T.Impact } }, 0.4)
	Effects.Sound("Holy", root.Position, { Pitch = 0.6, MaxDistance = 400 })
	if ctx.Involved or Effects.Near(base, 240) then
		worldGrade({
			CC = { Brightness = -0.02, Contrast = 0.2, Saturation = -0.12, TintColor = RGB(255, 240, 216) },
			Lighting = { Brightness = 1.7, ExposureCompensation = -0.2 },
			Atmosphere = { Haze = 2.4, Color = RGB(226, 212, 192), Decay = RGB(140, 132, 146) },
			SunRays = { Intensity = 0.2 },
			Bloom = { Intensity = 0.7 },
			Clouds = { Cover = 0.78, Color = RGB(210, 210, 220) },
		}, 0.7, T.Impact + 0.4, 1.4)
	end

	-- Licht in der erhobenen Hand + duenner Strahl, der in die Wolken schiesst
	local handGlow = Effects.Ball(CFrame.new(root.Position), 0.6, holy, { Material = Enum.Material.Neon, Parent = scene })
	Make("PointLight", { Color = warm, Range = 12, Brightness = 2, Parent = handGlow })
	local handAtt = Make("Attachment", { Parent = handGlow })
	local skyAnchor, skyAtt = Effects.Anchor(root.Position)
	skyAnchor.Parent = scene
	local skyBeam = Make("Beam", {
		Attachment0 = handAtt,
		Attachment1 = skyAtt,
		Color = Seq(holy, warm),
		LightEmission = 1,
		LightInfluence = 0,
		Width0 = 0.3,
		Width1 = 1.4,
		FaceCamera = true,
		Segments = 10,
		Transparency = NSeq(1),
		Parent = handGlow,
	})
	local skyTarget = base + Vector3.new(0, CLOUD_H - 6, 0)
	local handLife = T.Form + 0.5
	Effects.Animate(handLife, function(a)
		local t = a * handLife
		local hand = Effects.HandPosition(caster, "Right") or root.Position
		handGlow.CFrame = CFrame.new(hand + Vector3.new(0, 0.3, 0))
		local shoot = Effects.Ease(window(t, 0.3, 0.5), "OutCubic")
		skyAnchor.CFrame = CFrame.new(hand:Lerp(skyTarget, shoot))
		local vis = window(t, 0.3, 0.4) * (1 - window(t, T.Form, handLife))
		skyBeam.Transparency = NumberSequence.new(1 - 0.75 * vis, 1 - 0.35 * vis)
	end, function()
		handGlow:Destroy()
		skyAnchor:Destroy()
	end)

	-- Wolkendecke: zieht sich ueber dem Ziel zusammen und reisst beim Formen auf ----
	local cloudData = {}
	local cloudParts: { BasePart } = {}
	local cloudOwner: { number } = {}
	local cloudOffset: { CFrame } = {}
	local cloudBuffer: { CFrame } = {}
	local cloudIsBottom: { boolean } = {}
	local CLOUD_N = 12
	local pieces = {
		{ Size = Vector3.new(24, 8, 17), Pos = Vector3.new(0, 0, 0), Bottom = false },
		{ Size = Vector3.new(14, 9, 12), Pos = Vector3.new(-4, 3.6, 1.5), Bottom = false },
		{ Size = Vector3.new(12, 7, 10), Pos = Vector3.new(5.5, 2.8, -2), Bottom = false },
		{ Size = Vector3.new(22, 4, 15), Pos = Vector3.new(0.5, -2.8, 0), Bottom = true },
	}
	for i = 1, CLOUD_N do
		local s = rng:NextNumber(0.9, 1.5)
		table.insert(cloudData, {
			Angle = (i / CLOUD_N) * TAU + rng:NextNumber(-0.2, 0.2),
			Far = rng:NextNumber(85, 120),
			Closed = rng:NextNumber(11, 30),
			Open = rng:NextNumber(48, 74),
			Height = CLOUD_H + rng:NextNumber(-5, 7),
			Spin = rng:NextNumber(0, TAU),
		})
		for _, pc in pieces do
			local part = ellipsoid(scene, pc.Size * s, if pc.Bottom then RGB(186, 192, 206) else RGB(238, 240, 246), Enum.Material.SmoothPlastic, 1)
			table.insert(cloudParts, part)
			table.insert(cloudOwner, i)
			table.insert(cloudOffset, CFrame.new(pc.Pos * s))
			table.insert(cloudBuffer, CFrame.identity)
			table.insert(cloudIsBottom, pc.Bottom)
			Effects.Tween(part, 0.7, { Transparency = 0.04 })
		end
	end
	local clusterCF: { CFrame } = {}
	local cloudLife = T.Impact + 3.4
	Effects.Animate(cloudLife, function(a)
		local t = a * cloudLife
		for i, cd in cloudData do
			local r
			if t < T.Form then
				r = lerp(cd.Far, cd.Closed, Effects.Ease(t / T.Form, "InOut"))
			else
				r = lerp(cd.Closed, cd.Open, Effects.Ease(window(t, T.Form, T.Form + 1.3), "OutCubic")) + math.max(0, t - T.Form - 1.3) * 4
			end
			local ang = cd.Angle + t * 0.035
			local y = cd.Height + math.sin(t * 0.7 + i) * 0.6
			clusterCF[i] = CFrame.new(base + Vector3.new(math.cos(ang) * r, y, math.sin(ang) * r)) * CFrame.Angles(0, cd.Spin - ang, 0)
		end
		for j in cloudParts do
			cloudBuffer[j] = clusterCF[cloudOwner[j]] * cloudOffset[j]
		end
		workspace:BulkMoveTo(cloudParts, cloudBuffer, Enum.BulkMoveMode.FireCFrameChanged)
	end, function()
		for _, part in cloudParts do
			part:Destroy()
		end
	end)
	task.delay(T.Impact + 1.4, function()
		for _, part in cloudParts do
			Effects.Tween(part, 1.8, { Transparency = 1 })
		end
	end)

	-- FORMEN: Wolken werden von innen warm angestrahlt, Gottesstrahlen, Lichtkegel, Schwert
	task.delay(T.Form, function()
		for j, part in cloudParts do
			Effects.Tween(part, 0.9, { Color = if cloudIsBottom[j] then RGB(228, 204, 176) else RGB(255, 240, 214) })
		end
		-- Lichtkegel von oben (echtes Licht auf dem Gras)
		local spotAnchor = Effects.Anchor(base + Vector3.new(0, 50, 0))
		spotAnchor.Parent = scene
		local spot = Make("SpotLight", {
			Face = Enum.NormalId.Bottom,
			Angle = 56,
			Range = 60,
			Brightness = 0,
			Color = warm,
			Shadows = true,
			Parent = spotAnchor,
		})
		Effects.Tween(spot, 0.7, { Brightness = 4 })
		task.delay(T.Impact - T.Form + 1.6, function()
			Effects.Tween(spot, 1.4, { Brightness = 0 })
		end)
		-- Gottesstrahlen durch die Wolkenluecke
		local rays: { Beam } = {}
		for _ = 1, 6 do
			local a1 = rng:NextNumber(0, TAU)
			local a2 = rng:NextNumber(0, TAU)
			local r1 = rng:NextNumber(0, 8)
			local r2 = rng:NextNumber(2, R * 0.85)
			local top = base + Vector3.new(math.cos(a1) * r1, CLOUD_H - 3, math.sin(a1) * r1)
			local bottom = base + Vector3.new(math.cos(a2) * r2, 0, math.sin(a2) * r2)
			table.insert(rays, godRay(scene, top, bottom, rng:NextNumber(3, 6), rng:NextNumber(8, 15), warm))
		end
		fadeRays(rays, 0, 1, 0.6)
		task.delay(T.Impact - T.Form + 1.2, function()
			fadeRays(rays, 1, 0, 1.3)
		end)
		-- Lichtstaub, der langsam im Lichtkegel herabsinkt
		local motes = Effects.Part({ Transparency = 1, Size = Vector3.new(R * 1.4, 1, R * 1.4), CFrame = CFrame.new(base + Vector3.new(0, 24, 0)), Parent = scene })
		Effects.Stream(motes, T.Impact - T.Form + 1.4, {
			Texture = TEX.Sparkle,
			Rate = 28,
			Shape = Enum.ParticleEmitterShape.Box,
			EmissionDirection = Enum.NormalId.Bottom,
			Speed = NumberRange.new(1.5, 4),
			SpreadAngle = Vector2.new(20, 20),
			Lifetime = NumberRange.new(3, 5),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.32), NumberSequenceKeypoint.new(1, 0) }),
			Color = Seq(holy, gold),
			LightEmission = 1,
			Transparency = NSeq(0.2, 0.6),
		})
		Effects.Sound("Holy", base + Vector3.new(0, 30, 0), { Pitch = 0.5, MaxDistance = 600 })

		-- Das Schwert materialisiert: von oben nach unten, erst als weisse Silhouette
		local sword = buildHolySword(scene)
		local rig: Rig = sword.Rig
		rigMove(rig, swordCF(HILT_TOP))
		for i, part in rig.Parts do
			local y = rig.Offsets[i].Position.Y
			Effects.Tween(part, 0.3, { Transparency = sword.Targets[i] }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, (15 - y) / 62 * 0.45)
		end
		local hl: Highlight = sword.Highlight
		hl.FillTransparency = 0.05
		hl.OutlineTransparency = 0
		Effects.Tween(hl, 1, { FillTransparency = 1, OutlineTransparency = 0.45 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0.35)
		Effects.Tween(sword.Light, 0.8, { Brightness = 1.6 })

		-- Schweben, kurz ausholen, dann der Sturz (beschleunigt)
		local life = T.Impact - T.Form
		local lift = 0.18
		local plungeStart = T.Descend - T.Form + lift
		local trailsOn = false
		Effects.Animate(life, function(a)
			local t = a * life
			local extra = CFrame.identity
			if t < T.Descend - T.Form then
				swordY = HILT_TOP + math.sin(t * 2.2) * 0.8
				extra = CFrame.Angles(0, math.sin(t * 0.7) * 0.05, math.sin(t * 1.1) * 0.02)
			elseif t < plungeStart then
				swordY = HILT_TOP + 3.5 * Effects.Ease(window(t, T.Descend - T.Form, plungeStart), "Out")
			else
				local k = window(t, plungeStart, life)
				swordY = HILT_TOP + 3.5 + (HILT_END - HILT_TOP - 3.5) * k ^ 3
				if not trailsOn then
					trailsOn = true
					for _, sp in sword.Streakers do
						sideTrail(sp, Seq(holy, gold), 0.28, 1.1)
					end
					Effects.Sound("Whoosh", base + Vector3.new(0, 40, 0), { Pitch = 0.45, Volume = 1.2, MaxDistance = 600 })
				end
			end
			rigMove(rig, swordCF(swordY, extra))
		end)

		-- Luftdruck kurz vor dem Einschlag: Gras/Staub weht weg
		task.delay(T.Impact - T.Form - 0.22, function()
			dustRing(base, 5, 10, { Speed = 30, Size0 = 3, Size1 = 8, Life = 1, Per = 2 })
		end)

		-- EINSCHLAG ------------------------------------------------------------
		task.delay(T.Impact - T.Form, function()
			swordY = HILT_END
			rigMove(rig, swordCF(HILT_END))
			local contact = base + Vector3.new(0, 0.6, 0)
			local near = ctx.Involved or Effects.Near(base, 200)
			if near then
				exposurePop(0.28, 0.4, RGB(255, 240, 210))
			end
			if not ctx.Involved and Effects.Near(base, 160) then
				Effects.ScreenFlash(RGB(255, 246, 225), 0.2, 0.55)
			end
			hotCore(contact, 9, gold, 0.22)
			Effects.Light(contact + Vector3.new(0, 4, 0), warm, 60, 12, 1.1)
			Effects.Tween(sword.Light, 0.1, { Brightness = 6, Range = 40 })
			Effects.Tween(sword.Light, 1.2, { Brightness = 1.5, Range = 26 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0.1)
			hl.FillTransparency = 0.2
			Effects.Tween(hl, 0.35, { FillTransparency = 1 })
			sparks(contact + Vector3.new(0, 1, 0), 70, holy, gold, 40, 85, 60)
			groundShock(base + Vector3.new(0, 0.3, 0), R * 3.4, dust, 0.8, 0)
			Effects.Shockwave(base + Vector3.new(0, 0.5, 0), R * 2.4, holy, 0.3)
			airDistortion(contact + Vector3.new(0, 3, 0), 6, R * 2.2, 0.4)
			dustWave(base, R * 2.1, 0.45, { Speed = 28, Life = 2 })
			smokeColumn(base, dust, q(16), 22)
			groundChunks(base, 26, gInfo, { Spread = 46, MaxUp = 62 })
			craterRim(scene, base, 6.5, 11, gInfo, 2.6)
			Effects.Cracks(base, 9, R * 0.75, RGB(255, 204, 120), 2.2)
			Effects.Scorch(base, 9, 5, RGB(58, 46, 36))
			Effects.ShakeAt(base, 4.5, 220, 0.9)
			Effects.Sound("BigExplosion", base, { MaxDistance = 600 })
			Effects.Sound("Impact", base, { Pitch = 0.5, Volume = 1.2, MaxDistance = 600 })
			Effects.Sound("Holy", base, { Pitch = 0.4, MaxDistance = 600 })
			-- Nachzittern der Klinge
			Effects.Animate(0.45, function(a)
				rigMove(rig, swordCF(HILT_END, CFrame.Angles(0, 0, math.sin(a * 60) * 0.012 * (1 - a))))
			end)

			-- Nachspiel: Klinge loest sich von der Spitze aufwaerts in Licht auf
			task.delay(1.5, function()
				hl.FillTransparency = 0.45
				Effects.Tween(hl, 0.9, { FillTransparency = 1, OutlineTransparency = 1 })
				for i, part in rig.Parts do
					local y = rig.Offsets[i].Position.Y
					Effects.Tween(part, 0.35, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, (y + SWORD_BLADE) / 62 * 0.7)
				end
				Effects.Tween(sword.Light, 1, { Brightness = 0 })
				for k = 0, 3 do
					task.delay(k * 0.16, function()
						Effects.Burst(base + Vector3.new(0, 2 + k * 11, 0), 18, {
							Texture = TEX.Sparkle,
							Color = Seq(holy, gold),
							EmissionDirection = Enum.NormalId.Top,
							SpreadAngle = Vector2.new(60, 60),
							Speed = NumberRange.new(4, 12),
							Lifetime = NumberRange.new(1, 1.8),
							Size = NSeq(0.6, 0),
							Acceleration = Vector3.new(0, 6, 0),
							Drag = 1,
						})
					end)
				end
				Effects.Clean(sword.Model, 1.3)
			end)
		end)
	end)
end

-- =============================================================================
-- BLOOD MOON (Mythisch): Roter Himmel, ein Blutmond steigt auf, Schnitte im Bruchteil einer Sekunde
-- =============================================================================

function C.BloodMoon(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local def = Abilities.Get("BloodMoon") :: any
	local T = def.Timing
	local D: number = def.CutsceneDuration
	local scene = newScene("BloodMoon", D + 5)
	local crimson = RGB(206, 22, 44)
	local blood = RGB(124, 8, 22)
	local inkRed = RGB(34, 2, 8)
	local pale = RGB(255, 218, 218)
	local rootCF = root.CFrame
	local casterPos = rootCF.Position
	local lookDir = flat(rootCF.LookVector)
	local right = lookDir:Cross(UP)
	local roots = targetRoots(p)
	local casterGround = probe(casterPos, 2, 12)
	local function targetCenter(): Vector3
		local sum, n = Vector3.zero, 0
		for _, r in roots do
			if r.Parent then
				sum += r.Position
				n += 1
			end
		end
		return if n > 0 then sum / n else casterPos + lookDir * 7
	end
	local tc0 = targetCenter()
	local toTargets = flat(tc0 - casterPos)
	local style: SlashStyle = {
		Core = pale,
		Mid = Seq(RGB(255, 84, 90), crimson, blood),
		Dark = inkRed,
		Width = 1.3,
		Life = 0.24,
		Emission = 0.85,
	}

	-- Kamera ----------------------------------------------------------------
	local token = beginCutscene(ctx, def)
	if token then
		-- A) Untersicht von vorn: Silhouette vor dem aufsteigenden Mond
		local headish = casterPos + Vector3.new(0, 3, 0)
		local camA0 = clearCam(headish, casterPos + lookDir * 13 + right * 2.4 + Vector3.new(0, -1.6, 0), 1.1)
		local camA1 = clearCam(headish, casterPos + lookDir * 10 + right * 2.4 + Vector3.new(0, -1.6, 0), 1.1)
		Cutscene.Shot(function(t)
			local k = Effects.Ease(clamp01(t / 0.95), "InOut")
			return CFrame.lookAt(camA0:Lerp(camA1, k), casterPos + Vector3.new(0, 3.4 + k * 0.8, 0))
		end, 58, 0.01)
		-- B) Nahaufnahme der Augen
		at(token, 0.95, function()
			local head = Effects.GetPart(caster, "Head")
			if head then
				local hcf = head.CFrame
				Cutscene.Move(
					CFrame.lookAt((hcf * CFrame.new(0.4, 0.1, -3.8)).Position, hcf.Position),
					CFrame.lookAt((hcf * CFrame.new(0.25, 0.1, -2.5)).Position, hcf.Position),
					T.Vanish - 0.95,
					"Out",
					44
				)
				Cutscene.Focus(function()
					return head.Position
				end, 0.55, 2)
			end
		end)
		-- C) Reissschwenk zu den Zielen, schnelles Umkreisen waehrend der Schnitte
		at(token, T.Vanish - 0.02, function()
			Cutscene.Focus(nil)
			local a0 = math.atan2(-toTargets.Z, -toTargets.X) + 0.9
			Cutscene.Whip(orbitFn(targetCenter, 15, 11, 5, 2.6, a0, a0 + 1.5, T.FinalSlash - T.Vanish), 0.18, 70, 0.18)
		end)
		-- D) Ueber die Schulter: der Zaubernde steckt das Schwert weg, dahinter die Ziele
		at(token, T.FinalSlash - 0.22, function()
			local side = toTargets:Cross(UP)
			local shoulder = casterPos + Vector3.new(0, 1.5, 0)
			local camD0 = clearCam(shoulder, casterPos - toTargets * 6.5 + side * 2.4 + Vector3.new(0, 0.6, 0), 1.2)
			local camD1 = clearCam(shoulder, casterPos - toTargets * 5.6 + side * 2.4 + Vector3.new(0, 0.6, 0), 1.2)
			Cutscene.Shot(function(t)
				return CFrame.lookAt(camD0:Lerp(camD1, clamp01(t / 0.22)), targetCenter() + Vector3.new(0, 1, 0))
			end, 56, 0.01)
		end)
		-- E) Finaler Schnitt: Impact-Frame, dann Kran nach oben
		at(token, T.FinalSlash, function()
			Cutscene.Move(
				CFrame.lookAt(clearCam(tc0, casterPos - toTargets * 14 + Vector3.new(0, 16, 0), 3), tc0),
				CFrame.lookAt(clearCam(tc0, casterPos - toTargets * 18 + Vector3.new(0, 24, 0), 3), tc0),
				D - T.FinalSlash + 0.3,
				"Out",
				78
			)
			Cutscene.ImpactFrame({ Characters = involvedChars(p), Tint = RGB(255, 120, 120) })
			Cutscene.HitStop(0.08)
		end)
	end

	-- Welt: blutroter Himmel ----------------------------------------------------
	if ctx.Involved or Effects.Near(casterPos, 220) then
		worldGrade({
			CC = { Brightness = -0.04, Contrast = 0.28, Saturation = -0.12, TintColor = RGB(255, 170, 165) },
			Lighting = { Ambient = RGB(70, 22, 26), OutdoorAmbient = RGB(120, 40, 46), Brightness = 1.2, ExposureCompensation = -0.25 },
			Atmosphere = { Color = RGB(160, 34, 42), Decay = RGB(70, 8, 18), Haze = 2.6, Glare = 0.3 },
			SunRays = { Intensity = 0 },
			Clouds = { Color = RGB(96, 30, 36), Cover = 0.7 },
		}, 0.6, D - 0.4, 1.1)
	end
	Effects.Sound("Void", casterPos, { Pitch = 0.7, MaxDistance = 500 })
	-- Apply statt Sequence: kein automatischer Reset, die Nachbilder brauchen die Schlag-Posen
	Poser.Apply(caster, P.Sheath, 0.3)

	-- Der Blutmond: rot gluehender Koerper, dunkle Maria/Krater, weicher Halo
	local moonSize = 92
	local moonBase = casterPos - lookDir * 175
	local moonFrom = moonBase + Vector3.new(0, 4, 0)
	local moonTo = moonBase + Vector3.new(0, 72, 0)
	local moonRig = newRig()
	local moonParts: { BasePart } = {}
	local body = Effects.Ball(CFrame.new(moonFrom), moonSize, RGB(194, 44, 38), { Material = Enum.Material.Neon, Transparency = 1, Parent = scene })
	rigAdd(moonRig, body, CFrame.identity)
	table.insert(moonParts, body)
	local facing = (casterPos + Vector3.new(0, 30, 0) - moonTo).Unit
	local craterColors = { RGB(150, 28, 28), RGB(128, 20, 24), RGB(168, 36, 32), RGB(110, 16, 20) }
	for i = 1, 10 do
		local dir = (facing + randomUnit() * 0.8).Unit
		if dir:Dot(facing) < 0.25 then
			dir = (dir + facing).Unit
		end
		local d = rng:NextNumber(7, 22)
		local crater = ellipsoid(scene, Vector3.new(d, d * rng:NextNumber(0.7, 1), d * 0.3), craterColors[(i % #craterColors) + 1], Enum.Material.Neon, 1)
		rigAdd(moonRig, crater, CFrame.lookAt(dir * (moonSize / 2 - d * 0.08), Vector3.zero))
		table.insert(moonParts, crater)
	end
	rigMove(moonRig, CFrame.new(moonFrom))
	local haloAtt = Make("Attachment", { Parent = body })
	local halo = Effects.Emitter(haloAtt, {
		Texture = TEX.Glow,
		Rate = 0,
		LockedToPart = true,
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(D - T.MoonRise + 0.6),
		Size = NSeq(100),
		Color = ColorSequence.new(RGB(255, 64, 54)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.15, 0.6),
			NumberSequenceKeypoint.new(0.85, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = NumberRange.new(0),
		RotSpeed = NumberRange.new(0),
		LightEmission = 1,
		ZOffset = -4,
	})
	task.delay(T.MoonRise, function()
		for _, part in moonParts do
			Effects.Tween(part, 0.6, { Transparency = 0 })
		end
		halo:Emit(1)
		Effects.Animate(1.5, function(a)
			rigMove(moonRig, CFrame.new(moonFrom:Lerp(moonTo, Effects.Ease(a, "OutCubic"))))
		end)
	end)
	task.delay(D + 0.2, function()
		for _, part in moonParts do
			Effects.Tween(part, 1, { Transparency = 1 })
		end
	end)

	-- Dunkle Wolkenbaender ziehen vor dem Mond vorbei
	local cloudBand: { { Part: BasePart, Start: Vector3, Speed: number } } = {}
	for i = 1, 6 do
		local lateral = rng:NextNumber(-95, 95)
		local start = casterPos - lookDir * 140 + right * lateral + Vector3.new(0, rng:NextNumber(28, 96), 0)
		local part = ellipsoid(
			scene,
			Vector3.new(rng:NextNumber(55, 95), rng:NextNumber(7, 12), rng:NextNumber(16, 26)),
			if i % 2 == 0 then RGB(46, 14, 20) else RGB(30, 8, 14),
			Enum.Material.SmoothPlastic,
			1
		)
		part.CFrame = CFrame.lookAt(start, start + right)
		Effects.Tween(part, 0.8, { Transparency = 0.06 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0.3)
		table.insert(cloudBand, { Part = part, Start = start, Speed = rng:NextNumber(5, 9) * (if lateral > 0 then -1 else 1) })
	end
	Effects.Animate(D + 1.4, function(a)
		local t = a * (D + 1.4)
		for _, cb in cloudBand do
			local pos = cb.Start + right * (cb.Speed * t)
			cb.Part.CFrame = CFrame.lookAt(pos, pos + right)
		end
	end)
	task.delay(D + 0.2, function()
		for _, cb in cloudBand do
			Effects.Tween(cb.Part, 1.1, { Transparency = 1 })
		end
	end)

	-- Aura: dunkelroter Rauch steigt auf, einzelne Glutfunken
	Effects.Stream(
		root,
		T.Vanish,
		smoke(RGB(80, 10, 18), {
			Rate = 26,
			LightInfluence = 0.5,
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(30, 30),
			Speed = NumberRange.new(1, 3.5),
			Lifetime = NumberRange.new(0.8, 1.4),
			Size = NSeq(1.4, 3.6),
		})
	)
	Effects.Stream(root, T.Vanish, {
		Texture = TEX.Sparks,
		Rate = 14,
		Color = Seq(RGB(255, 120, 100), crimson),
		LightEmission = 1,
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(40, 40),
		Speed = NumberRange.new(2, 5),
		Lifetime = NumberRange.new(0.6, 1.1),
		Size = NSeq(0.22, 0),
		Acceleration = Vector3.new(0, 2, 0),
	})

	-- Gluehende Augen + Aufblitzen ("Shing")
	local head = Effects.GetPart(caster, "Head")
	if head then
		local eyes = {}
		for _, x in { -0.22, 0.22 } do
			local eye = Effects.Part({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.22, 0.22, 0.22), Color = RGB(255, 50, 60), Material = Enum.Material.Neon, Parent = scene })
			sideTrail(eye, ColorSequence.new(crimson), 0.2, 0.12)
			table.insert(eyes, { Part = eye, Offset = CFrame.new(x, 0.15, -0.58) })
		end
		local light = Make("PointLight", { Color = crimson, Range = 8, Brightness = 3, Parent = head })
		Effects.Animate(T.Vanish, function()
			for _, e in eyes do
				e.Part.CFrame = head.CFrame * e.Offset
			end
		end, function()
			for _, e in eyes do
				e.Part:Destroy()
			end
			light:Destroy()
		end)
		task.delay(T.Vanish - 0.32, function()
			for _, e in eyes do
				Effects.Burst(e.Part.Position, 1, {
					Texture = TEX.Sparkle,
					Color = Seq(pale, crimson),
					LightEmission = 1,
					Speed = NumberRange.new(0),
					Lifetime = NumberRange.new(0.28),
					Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 2.2), NumberSequenceKeypoint.new(1, 0) }),
					Transparency = NSeq(0),
					Rotation = NumberRange.new(45),
					RotSpeed = NumberRange.new(180),
				})
			end
			Effects.Sound("Block", head.Position, { Pitch = 1.3, Volume = 0.8 })
		end)
	end

	-- Verschwinden
	task.delay(T.Vanish, function()
		local pos = root.Position
		Effects.Afterimage(caster, blood, 0.5, 0.15)
		Effects.Burst(
			pos,
			18,
			smoke(RGB(60, 6, 14), {
				LightInfluence = 0.4,
				Speed = NumberRange.new(4, 12),
				Drag = 3,
				Lifetime = NumberRange.new(0.6, 1.1),
				Size = NSeq(2, 5),
			})
		)
		sparks(pos, 30, RGB(255, 140, 130), crimson, 10, 26, 10)
		dustRing(casterGround.Position, 1.5, 8, { Speed = 18, Size0 = 2, Size1 = 5, Life = 0.9, Per = 2 })
		Effects.Sound("Shadow", pos, { Pitch = 0.9 })
		if not ctx.Preview then
			Effects.SetCharacterVisible(caster, false)
		end
		Poser.Apply(caster, P.Slash, 0.04)
	end)

	-- Blitzschnelle Schnitte: Nachbilder rund um jedes Ziel, Trail-Schnitte, Funken
	local prevPos = casterPos
	local baseAng = rng:NextNumber(0, TAU)
	for i = 0, 4 do
		task.delay(T.SlashStart + i * 0.18, function()
			local points = {}
			for _, r in roots do
				if r.Parent then
					table.insert(points, r.Position)
				end
			end
			if #points == 0 then
				points = { casterPos + lookDir * 7 + right * (if i % 2 == 0 then 2 else -2) }
			end
			for j, pos in points do
				local ang = baseAng + i * 2.39 + j * 1.3
				local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
				local ghostPos = pos + dir * 4.2
				if j <= 3 then
					local ghostCF = CFrame.lookAt(ghostPos, Vector3.new(pos.X, ghostPos.Y, pos.Z))
					Effects.Afterimage(caster, crimson, 0.34, 0.35, ghostCF * root.CFrame:Inverse())
					streak(prevPos, ghostPos, 0.05, Seq(pale, crimson), 0.5, 0.16)
					prevPos = ghostPos
				end
				local roll = rng:NextNumber(-1.2, 1.2) + (if i % 2 == 0 then 0.6 else -0.6)
				slashAcross(pos + Vector3.new(0, 0.5, 0), -dir, roll, 5.2, 165, 0.09, style)
				sparks(pos + Vector3.new(0, 0.6, 0), 14, pale, crimson, 18, 34, 20)
				-- dunkelrote Tropfen fallen
				Effects.Burst(pos + Vector3.new(0, 0.6, 0), 8, {
					Texture = TEX.Sparks,
					Color = ColorSequence.new(blood),
					LightEmission = 0.2,
					LightInfluence = 0.4,
					Speed = NumberRange.new(8, 16),
					Lifetime = NumberRange.new(0.4, 0.7),
					Size = NSeq(0.3, 0.1),
					Acceleration = Vector3.new(0, -60, 0),
					Drag = 1,
				})
				Effects.Sound("Slash", pos, { Pitch = rng:NextNumber(0.95, 1.4), Volume = 0.8 })
			end
			Effects.ShakeAt(points[1], 1.3, 70, 0.18)
			Poser.Apply(caster, if i % 2 == 0 then P.HeavyStrike else P.Slash, 0.04)
		end)
	end

	-- Wiederauftauchen: der Zaubernde steckt das Schwert weg ...
	task.delay(T.FinalSlash - 0.22, function()
		if not ctx.Preview then
			Effects.SetCharacterVisible(caster, true)
		end
		Poser.Sequence(caster, { { P.Sheath, 0.9 } }, 0.3)
		Effects.Afterimage(caster, blood, 0.25, 0.4)
		Effects.Sound("Block", root.Position, { Pitch = 0.8, Volume = 0.9 })
	end)

	-- ... und alle Schnitte brechen gleichzeitig auf
	task.delay(T.FinalSlash, function()
		local pos = root.Position + Vector3.new(0, 0.8, 0)
		local reach = 8
		for _, r in roots do
			if r.Parent then
				local off = r.Position - casterPos
				reach = math.max(reach, Vector3.new(off.X, 0, off.Z).Magnitude + 1.2)
			end
		end
		reach = math.min(reach, 28)
		-- grosser Halbmond-Schnitt um den Zaubernden
		local bigStyle: SlashStyle = { Core = pale, Mid = Seq(RGB(255, 96, 100), crimson, blood), Dark = inkRed, Width = 3.4, Life = 0.5, Emission = 0.9 }
		trailSlash(CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0) * CFrame.Angles(math.rad(90 + 7), 0, 0), reach, 320, 0.15, bigStyle)
		-- X-Schnitt auf jedem Ziel
		for _, r in roots do
			if r.Parent then
				local face = flat(r.Position - casterPos)
				slashAcross(r.Position + Vector3.new(0, 0.6, 0), -face, 0.75, 6.5, 170, 0.08, style)
				slashAcross(r.Position + Vector3.new(0, 0.6, 0), -face, -0.75 + math.pi, 6.5, 170, 0.08, style)
				sparks(r.Position, 30, pale, crimson, 24, 48, 30)
				Effects.Burst(r.Position + Vector3.new(0, 0.6, 0), 14, {
					Texture = TEX.Sparks,
					Color = ColorSequence.new(blood),
					LightEmission = 0.2,
					LightInfluence = 0.4,
					Speed = NumberRange.new(12, 24),
					Lifetime = NumberRange.new(0.5, 0.8),
					Size = NSeq(0.35, 0.1),
					Acceleration = Vector3.new(0, -60, 0),
				})
			end
		end
		if not ctx.Involved and Effects.Near(pos, 120) then
			Effects.ScreenFlash(RGB(255, 210, 210), 0.18, 0.6)
		end
		Effects.Light(pos, crimson, 40, 6, 0.6)
		dustWave(casterGround.Position, reach + 6, 0.35, { Speed = 30, Size0 = 3, Size1 = 9, Life = 1.6 })
		groundShock(casterGround.Position + Vector3.new(0, 0.3, 0), (reach + 6) * 2, dustTone(casterGround), 0.6, 0)
		Effects.ShakeAt(pos, 3.2, 140, 0.6)
		Effects.Sound("Slash", pos, { Pitch = 0.6, Volume = 1.2 })
		Effects.Sound("Explosion", pos, { Pitch = 0.8 })
	end)
end

-- =============================================================================
-- SUPERNOVA (Goettlich): Ein Stern entsteht zwischen den Haenden, kollabiert und explodiert
-- =============================================================================

function C.Supernova(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local def = Abilities.Get("Supernova") :: any
	local T = def.Timing
	local D: number = def.CutsceneDuration
	local scene = newScene("Supernova", D + 7)
	local startPos = root.Position
	local gInfo = probe(startPos, 2, 16)
	local ground = gInfo.Position
	local dust = dustTone(gInfo)
	local lookDir = flat(root.CFrame.LookVector)
	local right = lookDir:Cross(UP)
	local a0 = math.atan2(lookDir.Z, lookDir.X)
	local hot = RGB(255, 251, 238)
	local yellow = RGB(255, 222, 122)
	local orange = RGB(255, 146, 48)
	local deep = RGB(186, 52, 22)
	local blueWhite = RGB(212, 230, 255)
	local FORM = 0.45
	local size = 0.3
	local function sizeAt(t: number): number
		if t < T.Grow then
			return lerp(0.3, 7.4, Effects.Ease(window(t, FORM, T.Grow), "InOut"))
		elseif t < T.Collapse then
			local k = window(t, T.Grow, T.Collapse)
			return 7.4 + k * 0.9 + math.sin(t * 26) * (0.15 + 0.35 * k)
		end
		return lerp(8.3, 0.7, Effects.Ease(window(t, T.Collapse, T.Explode), "InCubic"))
	end
	local function starPos(): Vector3
		return root.Position + Vector3.new(0, 4.2 + size * 0.5, 0)
	end

	-- Kamera ----------------------------------------------------------------
	local token = beginCutscene(ctx, def, { Hold = 2.2 })
	if token then
		-- A) Totale aus dem Gras: der Zaubernde steigt auf
		local riseLook = startPos + Vector3.new(0, 3, 0)
		local camA0 = clearCam(riseLook, ground + lookDir * 15 + right * 5 + Vector3.new(0, 1.3, 0), 1.2)
		local camA1 = clearCam(riseLook, ground + lookDir * 13 + right * 4.2 + Vector3.new(0, 1.3, 0), 1.2)
		Cutscene.Shot(function(t)
			local k = Effects.Ease(clamp01(t / 0.9), "InOut")
			return CFrame.lookAt(camA0:Lerp(camA1, k), root.Position + Vector3.new(0, 2 + k * 2, 0))
		end, 60, 0.01)
		-- B) Nah: der Stern entsteht zwischen den Haenden
		at(token, 0.9, function()
			Cutscene.Whip(orbitFn(starPos, 7.5, 9, -1.6, -0.6, a0 + 0.8, a0 + 1.5, 1), 0.2, 54, 0.2)
			Cutscene.Focus(starPos, 0.45, 4)
		end)
		-- C) Gegenlicht: tiefe Kamera, Silhouette vor dem Stern, langsam zurueck
		at(token, 1.9, function()
			Cutscene.Focus(nil)
			Cutscene.Shot(
				orbitFn(function()
					return root.Position + Vector3.new(0, 3, 0)
				end, 12, 19, -4.2, -2.6, a0 + 1.5 + math.pi, a0 + 1.9 + math.pi, 0.85, Vector3.new(0, 2.5, 0)),
				58,
				0.01
			)
			Cutscene.FOV(52, 0.85)
		end)
		-- D) Instabil: Kamera rueckt nah an die brodelnde Oberflaeche
		at(token, 2.75, function()
			Cutscene.Shot(orbitFn(starPos, 9, 6.5, -0.8, -0.4, a0 + 2.3, a0 + 2.55, T.Collapse - 2.75), 46, 0.3)
			Effects.Shake(0.5, T.Explode - 2.75, 26)
		end)
		-- E) Kollaps: Zoom hinein
		at(token, T.Collapse, function()
			Cutscene.FOV(32, T.Explode - T.Collapse)
		end)
		-- F) Explosion: Impact-Frame auf der Nahaufnahme, dann Totale ueber dem Tal
		at(token, T.Explode, function()
			local dir = Vector3.new(math.cos(a0 + 2.55), 0, math.sin(a0 + 2.55))
			local c = ground + Vector3.new(0, 8, 0)
			Cutscene.Move(
				CFrame.lookAt(clearCam(c, ground + dir * 64 + Vector3.new(0, 24, 0), 3), c),
				CFrame.lookAt(clearCam(c, ground + dir * 76 + Vector3.new(0, 30, 0), 3), c),
				D - T.Explode + 0.3,
				"Out",
				78
			)
			Cutscene.ImpactFrame({ Characters = involvedChars(p), Tint = RGB(255, 200, 140) })
			Cutscene.HitStop(0.06)
		end)
	end

	-- Welt: Eklipse - die Welt wird dunkel, der Stern ist die einzige Lichtquelle -----
	Poser.Sequence(caster, { { P.ArmsUp, T.Explode + 0.25 } }, 0.4)
	Effects.Sound("Charge", root.Position, { Pitch = 0.55, MaxDistance = 500 })
	if ctx.Involved or Effects.Near(startPos, 240) then
		worldGrade({
			CC = { Brightness = -0.06, Contrast = 0.24, Saturation = -0.35, TintColor = RGB(214, 222, 255) },
			Lighting = { Brightness = 0.9, ExposureCompensation = -0.55, OutdoorAmbient = RGB(96, 100, 122), Ambient = RGB(60, 62, 80) },
			Atmosphere = { Haze = 2.2, Color = RGB(150, 160, 190), Decay = RGB(70, 74, 104), Glare = 0 },
			SunRays = { Intensity = 0 },
			Bloom = { Intensity = 0.8 },
		}, 0.8, T.Explode - 0.8, 1.6)
	end
	-- Staub vom Abheben
	task.delay(0.05, function()
		dustRing(ground, 2.5, 12, { Speed = 16, Size0 = 2.5, Size1 = 7, Life = 1.4, Per = 2 })
	end)
	-- leiser Staubwirbel am Boden, solange der Stern waechst
	task.spawn(function()
		local t0 = os.clock()
		task.wait(0.6)
		while os.clock() - t0 < T.Collapse - 0.2 do
			dustRing(ground, rng:NextNumber(5, 9), 6, { Speed = 6, Size0 = 3, Size1 = 7, Life = 1.6, Per = 1, Rise = 0.5 })
			task.wait(0.4)
		end
	end)

	-- Der Stern ----------------------------------------------------------------
	task.delay(FORM, function()
		local c0 = starPos()
		local core = Effects.Ball(CFrame.new(c0), size, hot, { Material = Enum.Material.Neon, Parent = scene })
		local surface = Effects.Ball(CFrame.new(c0), size * 1.14, orange, { Material = Enum.Material.ForceField, Transparency = 0, Parent = scene })
		local coreAtt = Make("Attachment", { Parent = core })
		-- weicher Halo (Textur) statt grosser Neonkugel
		local glow = Effects.Emitter(coreAtt, {
			Texture = TEX.Glow,
			Rate = 6,
			LockedToPart = true,
			Speed = NumberRange.new(0),
			Lifetime = NumberRange.new(0.5),
			Size = NSeq(2),
			Color = Seq(yellow, orange),
			Transparency = NSeq(0.78, 1),
			RotSpeed = NumberRange.new(0),
			LightEmission = 1,
			ZOffset = -1,
		})
		-- Korona: Flammen-Partikel von der Oberflaeche (weiss -> gelb -> orange -> tiefrot)
		local corona = Effects.Emitter(surface, {
			Texture = TEX.Fire,
			Rate = 70 * Effects.Quality,
			Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
			ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
			Speed = NumberRange.new(0.5, 2.5),
			Lifetime = NumberRange.new(0.3, 0.55),
			Color = Seq(hot, yellow, orange, deep),
			Transparency = NSeq(0.2, 1),
			Size = NSeq(0.5, 0.9),
			LightEmission = 1,
			RotSpeed = NumberRange.new(-120, 120),
		})
		local light = Make("PointLight", { Color = yellow, Range = 14, Brightness = 1.5, Shadows = true, Parent = core })
		-- Protuberanzen: Feuerboegen, die die Oberflaeche umlaufen
		local proms = {}
		for i = 1, 3 do
			local part = Effects.Part({ Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(c0), Parent = scene })
			Effects.Trail(part, Seq(yellow, orange, deep), 0.22, 0.6)
			table.insert(proms, {
				Part = part,
				Axis = randomUnit(),
				Speed = rng:NextNumber(5, 8) * (if i % 2 == 0 then -1 else 1),
				Phase = rng:NextNumber(0, TAU),
			})
		end
		-- Partikelringe auf geneigten Bahnen
		local ringDefs = {
			{ Mult = 1.45, Extra = 0.8, Speed = 7.5, Tilt = CFrame.Angles(math.rad(70), 0, math.rad(12)) },
			{ Mult = 1.9, Extra = 1.4, Speed = -5.2, Tilt = CFrame.Angles(math.rad(-58), math.rad(40), 0) },
		}
		local rings = {}
		for i, rd in ringDefs do
			local part = Effects.Part({ Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(c0), Parent = scene })
			Effects.Trail(part, Seq(hot, yellow), 0.4, 0.3)
			Effects.Emitter(part, {
				Texture = TEX.Sparkle,
				Rate = 70 * Effects.Quality,
				Speed = NumberRange.new(0),
				SpreadAngle = Vector2.new(0, 0),
				Lifetime = NumberRange.new(0.5, 0.7),
				Size = NSeq(0.35, 0),
				Color = Seq(hot, yellow),
				LightEmission = 1,
			})
			table.insert(rings, { Part = part, Def = rd, Angle = i * 2.1 })
		end
		-- Licht stroemt von allen Seiten ein
		local gather = Effects.Ball(CFrame.new(c0), 34, yellow, { Transparency = 1, Parent = scene })
		local infall = Effects.Emitter(gather, {
			Texture = TEX.Sparkle,
			Rate = 110 * Effects.Quality,
			Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
			Speed = NumberRange.new(24, 30),
			Lifetime = NumberRange.new(0.6, 0.7),
			Color = Seq(hot, yellow),
			Size = NSeq(0.25, 0.7, 0.1),
			SpreadAngle = Vector2.new(0, 0),
		})
		-- Steine und Grasbrocken schweben vom Boden hoch
		local pebbles = {}
		for _ = 1, q(12) do
			local ang = rng:NextNumber(0, TAU)
			local dist = rng:NextNumber(3.5, 13)
			local info = probe(startPos + Vector3.new(math.cos(ang) * dist, 0, math.sin(ang) * dist), 4, 20)
			if not info.Water then
				local topC, topM = chunkLook(info)
				local s = rng:NextNumber(0.45, 1.3)
				local part = Effects.Part({
					Size = Vector3.new(s, s * 0.7, s * 0.9),
					Color = topC,
					Material = topM,
					CastShadow = true,
					CFrame = CFrame.new(info.Position),
					Parent = scene,
				})
				table.insert(pebbles, {
					Part = part,
					Base = info.Position + Vector3.new(0, s * 0.3, 0),
					Rise = rng:NextNumber(2.5, 7),
					Delay = rng:NextNumber(0, 0.6),
					Spin = randomUnit() * rng:NextNumber(0.6, 2),
				})
			end
		end
		Effects.Sound("Holy", root.Position, { Pitch = 0.7, MaxDistance = 500 })

		local life = T.Explode - FORM
		local collapsed = false
		Effects.Animate(life, function(a, dt)
			local t = FORM + a * life
			size = sizeAt(t)
			local c = starPos()
			local heat = window(t, T.Collapse, T.Explode)
			core.Size = Vector3.one * size
			core.CFrame = CFrame.new(c)
			core.Color = hot:Lerp(blueWhite, heat)
			surface.Size = Vector3.one * size * (1.14 + math.sin(t * 13) * 0.02)
			surface.CFrame = CFrame.new(c) * CFrame.Angles(0, t * 0.8, 0)
			surface.Color = orange:Lerp(RGB(140, 180, 255), heat)
			corona.Size = NSeq(size * 0.3, size * 0.55)
			glow.Size = NSeq(size * 2.6)
			glow.Color = Seq(yellow:Lerp(blueWhite, heat), orange:Lerp(RGB(120, 160, 255), heat))
			gather.CFrame = CFrame.new(c)
			light.Range = math.min(60, 12 + size * 6)
			light.Brightness = 1.5 + size * 0.5 + heat * 6
			light.Color = yellow:Lerp(blueWhite, heat)
			for _, pr in proms do
				pr.Part.CFrame = CFrame.new(c) * CFrame.fromAxisAngle(pr.Axis, pr.Phase + t * pr.Speed) * CFrame.new(size * 0.62, 0, 0)
			end
			for _, rg in rings do
				rg.Angle += dt * rg.Def.Speed * (1 + heat * 2)
				local rad = (size * rg.Def.Mult + rg.Def.Extra) * (1 - heat * 0.7)
				rg.Part.CFrame = CFrame.new(c) * rg.Def.Tilt * CFrame.Angles(0, rg.Angle, 0) * CFrame.new(rad, 0, 0)
			end
			for i, pb in pebbles do
				local k = Effects.Ease(window(t, 0.6 + pb.Delay, T.Collapse), "Out")
				local pull = (c - pb.Base) * (0.12 * heat)
				local pos = pb.Base + Vector3.new(0, pb.Rise * k + math.sin(t * 2 + i) * 0.15 * k, 0) + pull
				pb.Part.CFrame = CFrame.new(pos) * CFrame.Angles(pb.Spin.X * t, pb.Spin.Y * t, pb.Spin.Z * t)
			end
			if heat > 0 and not collapsed then
				collapsed = true
				infall.Speed = NumberRange.new(40, 50)
				infall.Lifetime = NumberRange.new(0.38, 0.42)
				infall.Color = Seq(WHITE, blueWhite)
				corona.Rate = 0
			end
		end, function()
			core:Destroy()
			surface:Destroy()
			gather:Destroy()
			for _, pr in proms do
				pr.Part:Destroy()
			end
			for _, rg in rings do
				rg.Part:Destroy()
			end
			-- Brocken werden weggeschleudert
			for _, pb in pebbles do
				local part = pb.Part
				if part.Parent then
					local out = flat(part.Position - startPos)
					pcall(function()
						part.Anchored = false
						part.CollisionGroup = "VFX"
						part.AssemblyLinearVelocity = out * rng:NextNumber(50, 80) + Vector3.new(0, rng:NextNumber(20, 40), 0)
						part.AssemblyAngularVelocity = randomUnit() * 12
					end)
					Effects.Clean(part, 2.2)
				end
			end
		end)
	end)

	-- Kollaps
	task.delay(T.Collapse, function()
		Effects.Sound("Charge", root.Position, { Pitch = 1.6, Volume = 0.9, MaxDistance = 500 })
		dustRing(ground, 18, 14, { Inward = true, Speed = 26, Size0 = 3, Size1 = 7, Life = 0.9, Per = 2 })
	end)

	-- EXPLOSION ----------------------------------------------------------------
	task.delay(T.Explode, function()
		local c = root.Position + Vector3.new(0, 4.6, 0)
		if ctx.Involved or Effects.Near(c, 240) then
			exposurePop(0.7, 0.45, RGB(255, 246, 228))
		end
		if not ctx.Involved and Effects.Near(c, 200) then
			Effects.ScreenFlash(WHITE, 0.25, 0.3)
		end
		hotCore(c, 24, yellow, 0.3)
		-- Schicht 1: weissgelber Kern (Textur)
		Effects.Burst(c, 6, {
			Texture = TEX.Core,
			Color = Seq(hot, yellow, orange),
			LightEmission = 1,
			Speed = NumberRange.new(0.1),
			Lifetime = NumberRange.new(0.35, 0.45),
			Size = NSeq(14, 46),
			Transparency = NSeq(0, 1),
			RotSpeed = NumberRange.new(-60, 60),
		})
		-- Schicht 2: Feuer nach aussen (orange -> tiefrot)
		Effects.Burst(c, 70, {
			Texture = TEX.Fire,
			Color = Seq(hot, yellow, orange, deep),
			LightEmission = 1,
			Speed = NumberRange.new(55, 110),
			Drag = 4,
			Lifetime = NumberRange.new(0.45, 0.9),
			Size = NSeq(5, 13),
			Transparency = NSeq(0, 0.25, 1),
			RotSpeed = NumberRange.new(-90, 90),
		})
		-- Schicht 3: dunkler Rauch
		Effects.Burst(
			c,
			26,
			smoke(RGB(92, 82, 74), {
				Speed = NumberRange.new(18, 48),
				Drag = 2.2,
				Lifetime = NumberRange.new(2, 3.4),
				Size = NSeq(8, 24),
				Acceleration = Vector3.new(0, 5, 0),
			})
		)
		sparks(c, 120, hot, orange, 60, 140, 35)
		-- Licht- und Staubwelle ueber das Gelaende
		lightWave(ground, 80, 0.75, RGB(255, 214, 150), 8)
		Effects.Light(c, RGB(255, 226, 170), 60, 14, 1.3)
		groundShock(ground + Vector3.new(0, 0.4, 0), 100, dust, 0.9, 0)
		Effects.Shockwave(ground + Vector3.new(0, 0.6, 0), 90, RGB(255, 222, 170), 0.45)
		airDistortion(c, 6, 80, 0.5)
		dustWave(ground, 70, 0.6, { Speed = 34, Size0 = 5, Size1 = 13, Life = 2.2 })
		groundChunks(ground, 30, gInfo, { Spread = 70, MaxUp = 60 })
		Effects.Scorch(ground, 13, 6, RGB(48, 40, 34))
		Effects.ShakeAt(c, 5.5, 260, 1.1)
		Effects.Sound("BigExplosion", c, { MaxDistance = 700 })
		Effects.Sound("Explosion", c, { Pitch = 0.6, MaxDistance = 700 })
		Effects.Sound("Holy", c, { Pitch = 0.4, MaxDistance = 700 })
		-- Sternenstaub rieselt langsam nach
		local dustBox = Effects.Part({ Transparency = 1, Size = Vector3.new(60, 1, 60), CFrame = CFrame.new(c + Vector3.new(0, 16, 0)), Parent = scene })
		Effects.Stream(dustBox, 2.2, {
			Texture = TEX.Sparkle,
			Rate = 60,
			Shape = Enum.ParticleEmitterShape.Box,
			EmissionDirection = Enum.NormalId.Bottom,
			Speed = NumberRange.new(2, 5),
			SpreadAngle = Vector2.new(15, 15),
			Lifetime = NumberRange.new(2, 3),
			Size = NSeq(0.4, 0),
			Color = Seq(hot, RGB(255, 196, 120)),
			LightEmission = 1,
		})
	end)
end

-- =============================================================================
-- BLACK HOLE (Exklusiv): Singularitaet mit Lichtring, Akkretionsscheibe, Kollaps und Implosion
-- =============================================================================

function C.BlackHole(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local def = Abilities.Get("BlackHole") :: any
	local T = def.Timing
	local D: number = def.CutsceneDuration
	local scene = newScene("BlackHole", D + 6)
	local violet = RGB(112, 52, 196)
	local darkViolet = RGB(38, 14, 66)
	local hotWhite = RGB(255, 246, 228)
	local hotOrange = RGB(255, 168, 80)
	local rootCF = root.CFrame
	local center: Vector3 = p.Extra.Center or (rootCF.Position + flat(rootCF.LookVector) * 16 + Vector3.new(0, 6, 0))
	local gInfo = probe(center, 2, 30)
	local groundPos = gInfo.Position
	local dust = dustTone(gInfo)
	local toCenter = flat(center - rootCF.Position)
	local a0 = math.atan2(-toCenter.Z, -toCenter.X) + 0.5
	local HOLE_R = 4.2

	-- Kamera ----------------------------------------------------------------
	local token = beginCutscene(ctx, def, { Glitch = true, GlitchColor = hotOrange, Hold = 2.4 })
	if token then
		-- A) Nah an der Hand: die Dunkelheit sammelt sich
		Cutscene.Shot(function()
			local hand = Effects.HandPosition(caster, "Right") or root.Position
			local cam = (root.CFrame * CFrame.new(3.4, 2.4, -5.6)).Position
			return CFrame.lookAt(cam, hand:Lerp(root.Position + Vector3.new(0, 1.5, 0), 0.35))
		end, 55, 0.2)
		Cutscene.Focus(function()
			return Effects.HandPosition(caster, "Right") or root.Position
		end, 0.5, 3)
		-- B) Ueber die Schulter: der Wurf
		at(token, T.Throw, function()
			Cutscene.Focus(nil)
			Cutscene.Move(
				CFrame.lookAt((root.CFrame * CFrame.new(2.6, 2.8, 5.5)).Position, center),
				CFrame.lookAt((root.CFrame * CFrame.new(2.2, 3.2, 3.5)).Position, center),
				T.Form - T.Throw,
				"Out",
				66
			)
		end)
		-- C) Das Loch oeffnet sich: FOV-Stoss, weite Umkreisung
		at(token, T.Form, function()
			Cutscene.Orbit(function()
				return center
			end, 36, 28, 11, 6, a0, a0 + 1.6, 2.4 - T.Form)
			Cutscene.FOV(80, 0.01)
			Cutscene.FOV(68, 0.5)
		end)
		-- D) Tief und nah: die Scheibe fast von der Kante, die Ziele werden eingesaugt
		at(token, 2.4, function()
			Cutscene.Orbit(function()
				return center
			end, 19, 13, 2, 0.6, a0 + 1.6, a0 + 2.3, T.Collapse - 2.4)
			Cutscene.FOV(60, 0.4)
		end)
		-- E) Kollaps: Zoom in die Singularitaet
		at(token, T.Collapse, function()
			Cutscene.FOV(28, T.Explode - T.Collapse)
		end)
		-- F) Implosion: Impact-Frame, dann Totale
		at(token, T.Explode, function()
			local want = center + Vector3.new(math.cos(a0 + 2.3) * 58, 28, math.sin(a0 + 2.3) * 58)
			local pos = clearCam(center, want, 3)
			local pos2 = clearCam(center, want + (want - center).Unit * 10, 3)
			Cutscene.Move(CFrame.lookAt(pos, center), CFrame.lookAt(pos2, center), D - T.Explode + 0.3, "Out", 82)
			Cutscene.ImpactFrame({ Characters = involvedChars(p), Tint = RGB(190, 150, 255) })
			Cutscene.HitStop(0.08)
		end)
	end

	-- Welt: das Licht wird verschluckt ------------------------------------------
	if ctx.Involved or Effects.Near(center, 240) then
		worldGrade({
			CC = { Brightness = -0.12, Contrast = 0.32, Saturation = -0.55, TintColor = RGB(212, 200, 255) },
			Lighting = { Brightness = 1, ExposureCompensation = -0.55, OutdoorAmbient = RGB(84, 76, 108), Ambient = RGB(50, 44, 70) },
			Atmosphere = { Color = RGB(96, 80, 130), Decay = RGB(34, 22, 56), Haze = 2.2, Glare = 0 },
			SunRays = { Intensity = 0 },
			Clouds = { Color = RGB(110, 100, 130) },
		}, 0.8, T.Explode - 0.8, 1.4)
	end
	Poser.Sequence(caster, { { P.RightUp, T.Throw }, { P.CastForward, D - T.Throw } }, 0.4)
	Effects.Sound("Void", root.Position, { Pitch = 0.5, MaxDistance = 600 })

	-- Kamerazugewandter Lichtring (Gravitationslinse)
	local function facingRing(adornee: BasePart, color: Color3, transparency: number): CylinderHandleAdornment
		return Make("CylinderHandleAdornment", {
			Adornee = adornee,
			Color3 = color,
			Radius = 0.2,
			InnerRadius = 0,
			Height = 0.05,
			Transparency = transparency,
			AlwaysOnTop = false,
			Parent = adornee,
		})
	end
	local function faceCamera(from: Vector3): CFrame
		local cam = workspace.CurrentCamera
		local toCam = if cam then cam.CFrame.Position - from else Vector3.zAxis
		return CFrame.lookAt(Vector3.zero, if toCam.Magnitude > 0.01 then toCam.Unit else Vector3.zAxis)
	end

	-- 1) Dunkelheit sammelt sich in der Hand
	local orb = Effects.Ball(CFrame.new(root.Position), 0.2, BLACK, { Material = Enum.Material.Neon, Parent = scene })
	local orbRing = facingRing(orb, hotWhite, 0)
	local gather = Effects.Ball(CFrame.new(root.Position), 12, violet, { Transparency = 1, Parent = scene })
	Effects.Stream(gather, T.Throw, {
		Texture = TEX.Sparkle,
		Rate = 90,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Speed = NumberRange.new(14, 18),
		Lifetime = NumberRange.new(0.34, 0.4),
		Color = Seq(hotWhite, RGB(200, 170, 255)),
		Size = NSeq(0.4, 0.1),
		SpreadAngle = Vector2.new(0, 0),
	})
	Effects.Stream(
		gather,
		T.Throw,
		smoke(darkViolet, {
			Rate = 30,
			LightInfluence = 0.3,
			Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
			Speed = NumberRange.new(12, 16),
			Lifetime = NumberRange.new(0.4, 0.45),
			Size = NSeq(2.5, 0.8),
			SpreadAngle = Vector2.new(0, 0),
		})
	)
	Effects.Animate(T.Throw, function(a)
		local hand = Effects.HandPosition(caster, "Right") or root.Position
		local s = 0.2 + 1.2 * a
		orb.Size = Vector3.one * s
		orb.CFrame = CFrame.new(hand + Vector3.new(0, 0.7, 0))
		gather.CFrame = orb.CFrame
		orbRing.CFrame = faceCamera(orb.Position)
		orbRing.Radius = s * 0.66
		orbRing.InnerRadius = math.max(0, s * 0.66 - 0.08)
	end, function()
		gather:Destroy()
		-- 2) Wurf ins Zentrum
		Effects.Trail(orb, Seq(hotWhite, violet), 0.25, 0.9)
		Effects.Sound("Whoosh", orb.Position, { Pitch = 0.6 })
		local from = orb.Position
		local flight = T.Form - T.Throw
		Effects.Animate(flight, function(a)
			orb.CFrame = CFrame.new(from:Lerp(center, a * a))
			orbRing.CFrame = faceCamera(orb.Position)
		end, function()
			orb:Destroy()
		end)
	end)

	-- 3) Die Singularitaet
	task.delay(T.Form, function()
		-- Raum faltet sich nach innen (umgekehrte Druckwelle)
		local fold = Effects.Ball(CFrame.new(center), 26, RGB(200, 180, 255), { Material = Enum.Material.ForceField, Transparency = 0.3 })
		Effects.Tween(fold, 0.24, { Size = Vector3.one, Transparency = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Effects.Clean(fold, 0.26)
		Effects.Sound("Void", center, { Pitch = 0.35, Volume = 1.2, MaxDistance = 700 })
		Effects.Sound("Rumble", center, { Pitch = 0.4, MaxDistance = 700 })
		Effects.ShakeAt(center, 1.6, 160, 0.4)

		local anchor = Effects.Anchor(center)
		anchor.Parent = scene
		local core = Effects.Ball(CFrame.new(center), 0.2, BLACK, { Material = Enum.Material.Neon, Parent = scene })
		local photon = facingRing(anchor, hotWhite, 0)
		local einstein = facingRing(anchor, hotOrange, 0.55)
		local outerGlow = facingRing(anchor, RGB(170, 90, 255), 0.82)
		local shellA = Effects.Ball(CFrame.new(center), 1, RGB(190, 160, 255), { Material = Enum.Material.ForceField, Transparency = 0.25, Parent = scene })
		local shellB = Effects.Ball(CFrame.new(center), 1, RGB(255, 200, 150), { Material = Enum.Material.ForceField, Transparency = 0.75, Parent = scene })
		local light = Make("PointLight", { Color = RGB(255, 150, 80), Range = 20, Brightness = 3, Shadows = false, Parent = anchor })

		-- Akkretionsscheibe: Trail-Streifen auf Kreisbahnen, innen heiss und schnell, aussen rot/violett und langsam
		local tilt = CFrame.Angles(math.rad(16), 0, math.rad(9))
		local bands = {
			{ R0 = 1.25, R1 = 1.75, Speed = 5.6, Life = 0.32, N = 6, Color = Seq(RGB(255, 252, 240), RGB(255, 214, 140), RGB(255, 150, 60)), Emission = 1, Tr = 0 },
			{ R0 = 1.7, R1 = 2.6, Speed = 3.4, Life = 0.46, N = 6, Color = Seq(RGB(255, 186, 96), RGB(240, 96, 40), RGB(170, 40, 30)), Emission = 0.9, Tr = 0.12 },
			{ R0 = 2.5, R1 = 3.9, Speed = 1.9, Life = 0.72, N = 6, Color = Seq(RGB(200, 60, 40), RGB(130, 40, 110), RGB(70, 30, 120)), Emission = 0.6, Tr = 0.3 },
		}
		local bandAngle = { 0, 0, 0 }
		local orbiters = {}
		for bi, band in bands do
			for i = 1, band.N do
				local part = Effects.Part({ Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(center) * tilt, Parent = scene })
				local att0 = Make("Attachment", { Position = Vector3.new(band.R0 * 0.05, 0, 0), Parent = part })
				local att1 = Make("Attachment", { Position = Vector3.new(band.R1 * 0.05, 0, 0), Parent = part })
				Make("Trail", {
					Attachment0 = att0,
					Attachment1 = att1,
					Color = band.Color,
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, band.Tr),
						NumberSequenceKeypoint.new(0.7, band.Tr + (1 - band.Tr) * 0.5),
						NumberSequenceKeypoint.new(1, 1),
					}),
					Lifetime = band.Life,
					LightEmission = band.Emission,
					LightInfluence = 0,
					FaceCamera = false,
					MinLength = 0,
					WidthScale = NSeq(1, 0.6),
					Parent = part,
				})
				table.insert(orbiters, { Part = part, A0 = att0, A1 = att1, Band = bi, Phase = (i / band.N) * TAU + rng:NextNumber(-0.2, 0.2) })
			end
		end

		-- Licht und Staub werden eingesaugt
		local suck = Effects.Ball(CFrame.new(center), 60, violet, { Transparency = 1, Parent = scene })
		local suckLight = Effects.Emitter(suck, {
			Texture = TEX.Sparkle,
			Rate = 120 * Effects.Quality,
			Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
			Speed = NumberRange.new(30, 34),
			Lifetime = NumberRange.new(0.88, 0.95),
			Color = Seq(hotWhite, RGB(255, 200, 140)),
			Size = NSeq(0.2, 0.7, 0),
			SpreadAngle = Vector2.new(0, 0),
		})
		local suckDust = Effects.Emitter(
			suck,
			smoke(dust:Lerp(darkViolet, 0.45), {
				Rate = 30 * Effects.Quality,
				LightInfluence = 0.6,
				Shape = Enum.ParticleEmitterShape.Sphere,
				ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
				ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
				Speed = NumberRange.new(26, 30),
				Lifetime = NumberRange.new(0.95, 1.05),
				Size = NSeq(7, 2),
				SpreadAngle = Vector2.new(0, 0),
			})
		)
		-- Boden darunter: dunkler Fleck waechst, Staub stroemt nach innen
		growMark(scene, groundPos, 2, 12, RGB(34, 24, 38), T.Explode - T.Form, T.Explode - T.Form + 4)
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < T.Collapse - T.Form - 0.2 do
				dustRing(groundPos, rng:NextNumber(13, 17), 8, { Inward = true, Speed = 14, Size0 = 3, Size1 = 6, Life = 1, Rise = 0.5, Per = 1 })
				task.wait(0.35)
			end
		end)

		-- Erdbrocken werden losgerissen und spiralfoermig hineingezogen (und gedehnt)
		for i = 1, q(30) do
			task.delay(0.1 + i * 0.07, function()
				local ang = rng:NextNumber(0, TAU)
				local dist = rng:NextNumber(10, 30)
				local info = probe(center + Vector3.new(math.cos(ang) * dist, 0, math.sin(ang) * dist), 8, 40)
				if info.Water then
					return
				end
				local topC, topM, botC, botM = chunkLook(info)
				local grassTop = rng:NextNumber() > 0.4
				local s = rng:NextNumber(0.7, 2.1)
				local startPos = info.Position + Vector3.new(0, s * 0.3, 0)
				local rock = Effects.Part({
					Size = Vector3.new(s, s * 0.8, s),
					Material = if grassTop then topM else botM,
					Color = if grassTop then topC else botC,
					CastShadow = true,
					CFrame = CFrame.new(startPos),
					Parent = scene,
				})
				Effects.Burst(startPos, 2, smoke(dustTone(info), { Speed = NumberRange.new(2, 5), Lifetime = NumberRange.new(0.8, 1.2), Size = NSeq(2, 4) }))
				local rel = startPos - center
				local startAng = math.atan2(rel.Z, rel.X)
				local life = rng:NextNumber(1.2, 1.8)
				local spin = randomUnit() * rng:NextNumber(4, 8)
				Effects.Animate(life, function(a)
					local e = a * a
					local r = dist * (1 - e)
					local th = startAng + e * TAU * 1.5
					local h = startPos.Y + (center.Y - startPos.Y) * Effects.Ease(a, "OutCubic")
					local pos = Vector3.new(center.X + math.cos(th) * r, h, center.Z + math.sin(th) * r)
					local tangent = Vector3.new(-math.sin(th), 0, math.cos(th))
					local k = math.max(0.06, 1 - e * 0.85)
					rock.Size = Vector3.new(s * k, s * 0.8 * k, s * (1 + e * 2.6))
					rock.CFrame = CFrame.lookAt(pos, pos + tangent) * CFrame.Angles(0, 0, spin.Z * a)
				end, function()
					rock:Destroy()
				end)
			end)
		end

		-- Pulsierender Klang
		task.spawn(function()
			for _ = 1, 2 do
				task.wait(0.9)
				Effects.Sound("Void", center, { Pitch = 0.3, Volume = 0.8, MaxDistance = 600 })
			end
		end)

		local life = T.Explode - T.Form
		local collapseAt = T.Collapse - T.Form
		Effects.Animate(life, function(a, dt)
			local t = a * life
			local grow = Effects.Ease(clamp01(t / 0.5), "OutBack")
			local col = window(t, collapseAt, life)
			local shrink = 1 - Effects.Ease(col, "InCubic")
			local k = math.max(0, grow * shrink)
			local r = math.max(0.05, HOLE_R * k * (1 + math.sin(t * 7) * 0.03))
			core.Size = Vector3.one * r * 2
			core.CFrame = CFrame.new(center)
			shellA.Size = Vector3.one * math.max(0.2, r * 4.8)
			shellA.CFrame = CFrame.new(center) * CFrame.Angles(0, t * 0.9, 0)
			shellB.Size = Vector3.one * math.max(0.2, r * 7.2)
			shellB.CFrame = CFrame.new(center) * CFrame.Angles(0, -t * 0.5, 0)
			-- Lichtringe immer zur Kamera
			local face = faceCamera(center)
			local flare = col * 0.25
			photon.CFrame = face
			photon.Radius = math.max(0.1, r * 1.1)
			photon.InnerRadius = math.max(0, photon.Radius - 0.22 - flare)
			einstein.CFrame = face
			einstein.Radius = math.max(0.1, r * 1.5)
			einstein.InnerRadius = math.max(0, r * 1.14)
			einstein.Transparency = 0.55 - col * 0.35
			outerGlow.CFrame = face
			outerGlow.Radius = math.max(0.1, r * 2)
			outerGlow.InnerRadius = math.max(0, r * 1.45)
			light.Range = 10 + 30 * k
			light.Brightness = 3 + col * 10
			-- Scheibe: unterschiedlich schnell, beim Kollaps immer schneller
			local boost = 1 + col * 2.5
			for bi, band in bands do
				bandAngle[bi] += dt * band.Speed * boost
			end
			local diskCF = CFrame.new(center) * tilt
			for _, ob in orbiters do
				local band = bands[ob.Band]
				ob.Part.CFrame = diskCF * CFrame.Angles(0, ob.Phase + bandAngle[ob.Band], 0)
				ob.A0.Position = Vector3.new(band.R0 * r, 0, 0)
				ob.A1.Position = Vector3.new(band.R1 * r, 0, 0)
			end
			if t > collapseAt then
				suckLight.Rate = 0
				suckDust.Rate = 0
			end
		end, function()
			core:Destroy()
			anchor:Destroy()
			shellA:Destroy()
			shellB:Destroy()
			suck:Destroy()
			for _, ob in orbiters do
				ob.Part:Destroy()
			end
		end)
	end)

	-- 4) Kollaps: hohes Sirren, alles stuerzt hinein
	task.delay(T.Collapse, function()
		Effects.Sound("Holy", center, { Pitch = 2, Volume = 0.8, MaxDistance = 600 })
		dustRing(groundPos, 22, 14, { Inward = true, Speed = 40, Size0 = 4, Size1 = 8, Life = 0.6, Per = 2 })
	end)

	-- 5) IMPLOSION / EXPLOSION
	task.delay(T.Explode, function()
		if ctx.Involved or Effects.Near(center, 240) then
			exposurePop(0.5, 0.4, RGB(235, 225, 255))
		end
		if not ctx.Involved and Effects.Near(center, 200) then
			Effects.ScreenFlash(WHITE, 0.22, 0.35)
		end
		hotCore(center, 16, hotOrange, 0.25)
		-- heisse Scheibenreste fliegen davon
		Effects.Burst(center, 90, {
			Texture = TEX.Sparks,
			Color = Seq(hotWhite, hotOrange, RGB(200, 60, 40)),
			LightEmission = 1,
			Speed = NumberRange.new(60, 130),
			Drag = 2,
			Lifetime = NumberRange.new(0.5, 1),
			Size = NSeq(0.6, 0),
			Acceleration = Vector3.new(0, -20, 0),
		})
		Effects.Burst(center, 40, {
			Texture = TEX.Fire,
			Color = Seq(hotWhite, hotOrange, RGB(160, 50, 120)),
			LightEmission = 1,
			Speed = NumberRange.new(40, 80),
			Drag = 4,
			Lifetime = NumberRange.new(0.4, 0.8),
			Size = NSeq(4, 10),
			Transparency = NSeq(0, 0.3, 1),
			RotSpeed = NumberRange.new(-90, 90),
		})
		-- dunkler, violetter Rauch
		Effects.Burst(
			center,
			30,
			smoke(RGB(46, 24, 70), {
				LightInfluence = 0.5,
				Speed = NumberRange.new(20, 45),
				Drag = 2.2,
				Lifetime = NumberRange.new(1.8, 3),
				Size = NSeq(8, 22),
				Acceleration = Vector3.new(0, 3, 0),
			})
		)
		airDistortion(center, 4, 90, 0.55, RGB(220, 200, 255))
		groundShock(groundPos + Vector3.new(0, 0.4, 0), 100, dust, 1, 0)
		dustWave(groundPos, 80, 0.6, { Speed = 36, Size0 = 5, Size1 = 13, Life = 2.2 })
		groundChunks(groundPos, 30, gInfo, { Spread = 70, MaxUp = 70, MaxSize = 2.2 })
		Effects.Scorch(groundPos, 16, 6, RGB(30, 20, 36))
		Effects.Light(center, RGB(230, 210, 255), 60, 12, 1.4)
		Effects.ShakeAt(center, 6, 260, 1.3)
		Effects.Sound("BigExplosion", center, { Pitch = 0.8, MaxDistance = 800 })
		Effects.Sound("Void", center, { Pitch = 0.6, MaxDistance = 800 })
		Effects.Sound("Explosion", center, { Pitch = 0.5, MaxDistance = 800 })
	end)
end

return C
