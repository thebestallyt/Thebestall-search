-- VFX der Faehigkeiten ohne Cutscene (Gewoehnlich bis Legendaer).
-- Jede Funktion bekommt das Payload vom Server (p) und einen Kontext (ctx = {IsCaster, Involved, Preview}).
-- Stil: geschichtete Element-Effekte (heller Kern -> Farbe -> Rauch), Staub/Truemmer in Bodenfarbe,
-- Neon nur fuer kleine heisse Kerne. Zeiten kommen aus Shared/Abilities (Timing).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Make = require(Shared:WaitForChild("Make"))
local Abilities = require(Shared:WaitForChild("Abilities"))

local VFX = script.Parent :: Instance
local Effects = require(VFX:WaitForChild("Effects"))
local Poser = require(VFX:WaitForChild("Poser"))

local V = {}

local TEX = Effects.Textures
local P = Poser.Poses
local PAL = Effects.Palettes
local FIRE = Effects.FireColors
local rng = Effects.Random
local NSeq, Seq = Effects.NSeq, Effects.Seq
local player = Players.LocalPlayer

local C = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local TAU = math.pi * 2
local SMALL = Vector3.new(0.2, 0.2, 0.2)

local function def(id: string): any
	return Abilities.Get(id)
end

local function flat(v: Vector3, fallback: Vector3?): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-3 then
		return fallback or Vector3.new(0, 0, -1)
	end
	return f.Unit
end

local function look(p: any, root: BasePart): Vector3
	local d: Vector3 = (p.Extra and p.Extra.Dir) or root.CFrame.LookVector
	return flat(d, flat(root.CFrame.LookVector))
end

local function isLocalChar(m: Model?): boolean
	return m ~= nil and m == player.Character
end

local function randomRot(): CFrame
	return CFrame.Angles(rng:NextNumber(0, TAU), rng:NextNumber(0, TAU), rng:NextNumber(0, TAU))
end

-- Unsichtbarer Traeger mit Trail (fuer Wind-/Wasserspuren)
local function trailCarrier(at: Vector3, width: number, color: ColorSequence, lifetime: number, props: { [string]: any }?): Part
	local part = Effects.Part({ Transparency = 1, Size = SMALL, CFrame = CFrame.new(at) })
	local a0 = Make("Attachment", { Position = Vector3.new(0, width / 2, 0), Parent = part })
	local a1 = Make("Attachment", { Position = Vector3.new(0, -width / 2, 0), Parent = part })
	local trail = Make("Trail", {
		Attachment0 = a0,
		Attachment1 = a1,
		Color = color,
		Transparency = NSeq(0.2, 1),
		WidthScale = NSeq(1, 0.2),
		Lifetime = lifetime,
		LightEmission = 0.4,
		LightInfluence = 0.4,
		FaceCamera = true,
		MinLength = 0.05,
		Parent = part,
	})
	if props then
		for k, v in props do
			(trail :: any)[k] = v
		end
	end
	return part
end

-- GEWOEHNLICH ------------------------------------------------------------------

-- Ansturm mit brennender Faust, am Ende ein Flammenkegel mit Glut und Brandfleck
function V.EmberPunch(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local d = def("EmberPunch")
	local lunge: number = d.Timing.Lunge
	local dir = look(p, root)
	local F = PAL.Fire
	Poser.Sequence(caster, { { P.HeavyWindup, 0.06 }, { P.LungePunch, 0.34 } }, 0.22)
	Effects.Sound("Fire", root.Position, { Volume = 0.8 })
	Effects.Sound("Whoosh", root.Position, { Pitch = 0.9 })

	-- Absprung: Staub fliegt nach hinten
	local g0 = Effects.Ground(root.Position)
	if root.Position.Y - g0.Y < 5 then
		Effects.BurstDir(g0 + Vector3.new(0, 0.4, 0), -dir + Vector3.new(0, 0.3, 0), 8, {
			Texture = TEX.Smoke,
			Color = ColorSequence.new(Effects.DustColor(g0)),
			LightEmission = 0,
			LightInfluence = 0.85,
			Speed = NumberRange.new(8, 16),
			SpreadAngle = Vector2.new(40, 15),
			Lifetime = NumberRange.new(0.5, 0.9),
			Size = NSeq(1.4, 3.6),
			Transparency = NSeq(0.35, 0.7, 1),
			Drag = 4,
		})
	end

	-- Brennende Faust: Kern + Flammen + Rauchfaeden + Feuerspur
	local hand = Effects.HandPart(caster, "Right")
	if hand then
		local att = Make("Attachment", { Parent = hand })
		local burn = lunge + 0.25
		Effects.Stream(att, burn, {
			Texture = TEX.Fire,
			Rate = 60,
			Color = Seq(F.Core, F.Hot),
			Speed = NumberRange.new(0.5, 2),
			Lifetime = NumberRange.new(0.1, 0.2),
			Size = NSeq(1.1, 0.4),
			LightEmission = 1,
			Brightness = 1.6,
			LockedToPart = true,
		})
		Effects.Stream(att, burn, {
			Texture = TEX.Fire,
			Rate = 55,
			Color = FIRE,
			Speed = NumberRange.new(1, 3),
			Lifetime = NumberRange.new(0.25, 0.45),
			Size = NSeq(1.4, 2, 0),
			SpreadAngle = Vector2.new(40, 40),
			Acceleration = Vector3.new(0, 9, 0),
			LightEmission = 0.8,
		})
		Effects.Stream(att, burn, {
			Texture = TEX.Smoke,
			Rate = 16,
			Color = Seq(C(90, 70, 60), F.Smoke),
			LightEmission = 0,
			LightInfluence = 0.7,
			Speed = NumberRange.new(1, 3),
			Lifetime = NumberRange.new(0.5, 0.9),
			Size = NSeq(0.8, 2.4),
			Transparency = NSeq(0.4, 0.7, 1),
			Acceleration = Vector3.new(0, 6, 0),
		})
		Effects.Clean(att, burn + 1.2)
		Effects.Trail(hand, Seq(F.Hot, F.Mid, F.Deep), 0.2, 1.2, lunge + 0.1)
		Effects.Light(hand, F.Mid, 14, 2.5, lunge + 0.4)
	end
	-- Flammen bleiben entlang der Strecke in der Luft zurueck
	local rootAtt = Make("Attachment", { Parent = root })
	Effects.Stream(rootAtt, lunge, {
		Texture = TEX.Fire,
		Rate = 45,
		Color = FIRE,
		Speed = NumberRange.new(0.5, 1.5),
		Lifetime = NumberRange.new(0.2, 0.4),
		Size = NSeq(2.2, 0),
		Acceleration = Vector3.new(0, 6, 0),
		LightEmission = 0.7,
	})
	Effects.Clean(rootAtt, lunge + 0.8)

	task.delay(lunge * 0.85, function()
		if not root.Parent then
			return
		end
		local pos = root.Position + dir * 3 + Vector3.new(0, 0.3, 0)
		Effects.Flash(pos, F.Hot, 6, 0.18)
		-- Flammenkegel nach vorne
		Effects.FireBurst(pos, dir, 1.3, { Spread = Vector2.new(24, 24), Speed = 34 })
		Effects.Shockwave(pos, 9, F.Hot, 0.28, dir)
		Effects.Sparks(pos, 14, F.Mid, 46, {
			Dir = dir,
			Spread = Vector2.new(35, 35),
			Gravity = 25,
			MaxLife = 0.6,
			Colors = Seq(F.Hot, F.Mid),
		})
		-- Brandfleck + Staub vor dem Spieler
		local gp = Effects.Ground(pos + dir * 3)
		if pos.Y - gp.Y < 7 then
			Effects.Scorch(gp, 3.2, 2.2)
			Effects.Dust(gp, 5, 1.1)
		end
		Effects.Light(pos, F.Mid, 26, 5, 0.45)
		Effects.Sound("Explosion", pos, { Pitch = 1.3, Volume = 0.6 })
		Effects.ShakeAt(pos, 1.2, 50, 0.3)
	end)
end

-- Sprung + Aufprall: Felsspitzen in Bodenfarbe brechen im Ring heraus, Staubwelle, Brocken
function V.StoneSmash(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local d = def("StoneSmash")
	local impact: number = d.Timing.Impact
	Poser.Sequence(caster, { { P.Crouch, 0.08 }, { P.ArmsUp, math.max(0.05, impact - 0.1) }, { P.Slam, 0.35 } }, 0.25)
	Effects.Sound("Whoosh", root.Position, { Pitch = 0.8 })
	local startGround: Vector3 = p.Extra.Ground or Effects.Ground(root.Position)

	-- Absprung: Staubring + Steinchen, die mit hochschweben
	Effects.DustRing(startGround, 4, nil, { Count = 8, Life = 0.8 })
	local pebbleColor, pebbleMat = Effects.DebrisLook(startGround)
	local pebbles: { BasePart } = {}
	for _ = 1, math.floor(6 * Effects.Quality) do
		local s = rng:NextNumber(0.3, 0.7)
		local a = rng:NextNumber(0, TAU)
		local r = rng:NextNumber(1.5, 4)
		local pos = startGround + Vector3.new(math.cos(a) * r, s * 0.5, math.sin(a) * r)
		local peb = Effects.Part({
			Size = Vector3.new(s, s * 0.8, s),
			CFrame = CFrame.new(pos) * randomRot(),
			Material = pebbleMat,
			Color = Effects.Vary(pebbleColor, 0.1),
		})
		Effects.Tween(peb, impact, { CFrame = CFrame.new(pos + Vector3.new(0, rng:NextNumber(1.5, 3.5), 0)) * randomRot() }, Enum.EasingStyle.Quad)
		table.insert(pebbles, peb)
		Effects.Clean(peb, impact + 2)
	end

	task.delay(impact, function()
		-- Steinchen werden weggeschleudert
		for _, peb in pebbles do
			if peb.Parent then
				peb.Anchored = false
				peb.CanCollide = true
				peb.CollisionGroup = "VFX"
				peb.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-20, 20), rng:NextNumber(18, 32), rng:NextNumber(-20, 20))
				Effects.Tween(peb, 0.4, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 1)
			end
		end
		local center = if root.Parent then Effects.Ground(root.Position) else startGround
		local _, groundColor = Effects.GroundInfo(center)
		local dust = Effects.DustColor(center)
		-- Innen spitze Felsen, aussen flachere Platten
		Effects.GroundSpikes(center, 5.5, 9, { MinHeight = 4, MaxHeight = 7, Stagger = 0.05 })
		task.delay(0.07, function()
			Effects.GroundSpikes(center, 10, 14, { MinHeight = 2, MaxHeight = 4.5, Stay = 1, WidthScale = 1.2, Stagger = 0.06 })
		end)
		Effects.Cracks(center, 8, 12, PAL.Fire.Mid, 1.6, { NoGlow = true })
		Effects.Rocks(center, 14, { Spread = 30, MaxUp = 55, MaxSize = 1.8 })
		Effects.DustRing(center, 14, dust)
		Effects.Dust(center, 10, 2, dust)
		Effects.GroundMark(center, 6.5, groundColor:Lerp(BLACK, 0.55), 2.6, { Transparency = 0.2, Grow = 0.1 })
		Effects.Shockwave(center + Vector3.new(0, 0.5, 0), 26, dust, 0.4)
		Effects.Sound("Impact", center)
		Effects.Sound("Rumble", center, { Volume = 0.5, Pitch = 0.8 })
		Effects.ShakeAt(center, 2.4, 70, 0.45)
	end)
end

-- Kleine Blaetter, die vom Wind mitgerissen werden
local LEAF_COLORS = { C(96, 150, 60), C(126, 172, 70), C(170, 168, 72), C(110, 140, 52) }

local function leaves(origin: Vector3, dir: Vector3, count: number)
	local right = dir:Cross(Vector3.yAxis)
	for i = 1, math.floor(count * Effects.Quality) do
		local start = origin + right * rng:NextNumber(-2.5, 2.5) + Vector3.new(0, rng:NextNumber(0.3, 1.5), 0)
		local leaf = Effects.Part({
			Size = Vector3.new(0.35, 0.04, 0.55),
			CFrame = CFrame.new(start) * randomRot(),
			Material = Enum.Material.SmoothPlastic,
			Color = LEAF_COLORS[(i % #LEAF_COLORS) + 1],
		})
		local travel = rng:NextNumber(0.7, 1.1)
		local goal = start + dir * rng:NextNumber(14, 22) + right * rng:NextNumber(-4, 4) + Vector3.new(0, rng:NextNumber(1, 5), 0)
		Effects.Tween(leaf, travel, { CFrame = CFrame.new(goal) * randomRot() }, Enum.EasingStyle.Quad)
		Effects.Tween(leaf, 0.3, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, travel - 0.2)
		Effects.Clean(leaf, travel + 0.2)
	end
end

-- Kegelfoermiger Windstoss: Wind-Spiralen (Trails), Druckluft-Schwaden, Staubwelle, Blaetter
function V.GaleBurst(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local d = def("GaleBurst")
	local dir = look(p, root)
	local W = PAL.Wind
	Poser.Sequence(caster, { { P.ChargeLow, d.Timing.Release }, { P.PushBoth, 0.35 } }, 0.2)
	Effects.Sound("Wind", root.Position)
	-- Luft sammelt sich an den Haenden
	local handPos = Effects.HandPosition(caster, "Right") or root.Position
	Effects.Burst(handPos, 5, {
		Texture = TEX.Smoke,
		Color = ColorSequence.new(W.White),
		LightEmission = 0.15,
		LightInfluence = 0.7,
		Speed = NumberRange.new(1, 3),
		Lifetime = NumberRange.new(0.2, 0.3),
		Size = NSeq(0.8, 2),
		Transparency = NSeq(0.6, 1),
	})

	task.delay(d.Timing.Release, function()
		if not root.Parent then
			return
		end
		local origin = root.Position + Vector3.new(0, 0.4, 0) + dir * 1.5
		local right = dir:Cross(Vector3.yAxis)
		local range: number = d.Range
		-- 1) Wind-Spiralen: Trails schrauben sich nach vorne und weiten sich zum Kegel
		local carriers = {}
		for i = 1, 6 do
			local part = trailCarrier(origin, 0.32, ColorSequence.new(W.White), 0.24, { LightEmission = 0.35, Transparency = NSeq(0.2, 1) })
			table.insert(carriers, {
				part = part,
				phase = (i / 6) * TAU,
				radius = rng:NextNumber(0.6, 1.4),
				speed = rng:NextNumber(0.9, 1.15),
				spin = if i % 2 == 0 then 7 else -7,
			})
		end
		Effects.Animate(0.4, function(a)
			for _, c in carriers do
				local t = math.min(1, a * c.speed)
				local e = Effects.Ease(t, "Out")
				local dist = e * range
				local spread = c.radius + dist * 0.4
				local ang = c.phase + e * c.spin
				c.part.CFrame = CFrame.new(origin + dir * dist + right * math.cos(ang) * spread + Vector3.new(0, math.sin(ang) * spread * 0.55, 0))
			end
		end, function()
			for _, c in carriers do
				Effects.Clean(c.part, 0.3)
			end
		end)
		for _, c in carriers do
			Effects.Clean(c.part, 1)
		end
		-- 2) Druckluft: helle Schwaden, die schnell nach vorne schiessen
		Effects.BurstDir(origin, dir, 14, {
			Texture = TEX.Smoke,
			Color = ColorSequence.new(W.White),
			LightEmission = 0.15,
			LightInfluence = 0.7,
			Speed = NumberRange.new(40, 60),
			SpreadAngle = Vector2.new(32, 18),
			Lifetime = NumberRange.new(0.3, 0.5),
			Size = NSeq(1.5, 5),
			Transparency = NSeq(0.55, 0.8, 1),
			Drag = 4,
			RotSpeed = NumberRange.new(-200, 200),
		})
		Effects.Shockwave(origin + dir * 2, 10, W.White, 0.3, dir)
		-- 3) Boden: Staubwelle in Windrichtung + Blaetter
		local g = Effects.Ground(origin + dir * 4)
		if origin.Y - g.Y < 7 then
			Effects.BurstDir(g + Vector3.new(0, 0.6, 0), dir + Vector3.new(0, 0.15, 0), 12, {
				Texture = TEX.Smoke,
				Color = ColorSequence.new(Effects.DustColor(g)),
				LightEmission = 0,
				LightInfluence = 0.85,
				Speed = NumberRange.new(30, 50),
				SpreadAngle = Vector2.new(40, 8),
				Lifetime = NumberRange.new(0.5, 0.9),
				Size = NSeq(1.5, 4.5),
				Transparency = NSeq(0.4, 0.7, 1),
				Drag = 3.5,
			})
			leaves(g, dir, 8)
		end
		Effects.Sound("Whoosh", origin, { Pitch = 0.7 })
		if isLocalChar(caster) then
			Effects.Shake(0.4, 0.18)
		end
	end)
end

-- UNGEWOEHNLICH ------------------------------------------------------------------

local ICE = PAL.Ice

-- Kristall-Cluster (Glas-Keile), der aus dem Boden waechst und wieder schmilzt
local function iceCluster(pos: Vector3, size: number, stay: number)
	for _ = 1, 3 do
		local h = size * rng:NextNumber(0.7, 1.3)
		local w = size * rng:NextNumber(0.25, 0.4)
		local tilt = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, TAU), rng:NextNumber(-0.5, 0.5))
		local wedge = Effects.Wedge({
			Size = Vector3.new(w, 0.1, w * 1.4),
			CFrame = tilt,
			Material = Enum.Material.Glass,
			Color = ICE.Light:Lerp(ICE.Mid, rng:NextNumber()),
			Transparency = 0.25,
			Reflectance = 0.15,
		})
		Effects.Tween(wedge, 0.12, { Size = Vector3.new(w, h, w * 1.4), CFrame = tilt * CFrame.new(0, h / 2, 0) }, Enum.EasingStyle.Back)
		task.delay(stay, function()
			if wedge.Parent then
				Effects.Tween(wedge, 0.3, { Size = Vector3.new(w * 0.3, 0.1, w * 0.4), Transparency = 1 })
			end
		end)
		Effects.Clean(wedge, stay + 0.35)
	end
end

-- Eis-Splitter beim Aufprall: Glas-Splitter, Frostnebel, Glitzer, Kristalle + Frost am Boden
local function frostBurst(pos: Vector3, dir: Vector3)
	for _ = 1, math.floor(7 * Effects.Quality) do
		local s = rng:NextNumber(0.25, 0.6)
		local shard = Effects.Wedge({
			Size = Vector3.new(s * 0.5, s * 1.6, s),
			CFrame = CFrame.new(pos) * randomRot(),
			Material = Enum.Material.Glass,
			Color = ICE.Light,
			Transparency = 0.2,
			Reflectance = 0.2,
			Anchored = false,
			CanCollide = true,
			CollisionGroup = "VFX",
		})
		shard.AssemblyLinearVelocity = -dir * rng:NextNumber(4, 10)
			+ Vector3.new(rng:NextNumber(-14, 14), rng:NextNumber(6, 18), rng:NextNumber(-14, 14))
		shard.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-15, 15), rng:NextNumber(-15, 15), rng:NextNumber(-15, 15))
		Effects.Tween(shard, 0.4, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.5)
		Effects.Clean(shard, 1)
	end
	Effects.SmokePuff(pos, 6, ICE.Light, 1, { Life = 0.9, Rise = 0.5 })
	Effects.Burst(pos, 10, {
		Texture = TEX.Sparkle,
		Color = Seq(WHITE, ICE.Light),
		Speed = NumberRange.new(6, 14),
		Lifetime = NumberRange.new(0.3, 0.6),
		Size = NSeq(0.5, 0),
		Drag = 3,
	})
	Effects.Flash(pos, ICE.Light, 3, 0.15)
	local res = Effects.RaycastMap(pos + Vector3.new(0, 1, 0), Vector3.new(0, -7, 0))
	if res then
		iceCluster(res.Position, 1.6, 1)
		Effects.GroundMark(res.Position, 2.2, ICE.Light, 1.6, { Transparency = 0.35 })
	end
	Effects.Sound("Ice", pos, { Volume = 0.5 })
end

-- Ein Eis-Geschoss: Kristall aus mehreren Glas-Teilen, kleiner heller Kern, Frost-Trail
local SHARD_LAYOUT = {
	{ size = Vector3.new(0.55, 0.55, 3), off = CFrame.Angles(0, 0, math.rad(45)), color = ICE.Light, glass = true },
	{ size = Vector3.new(0.35, 0.35, 1.8), off = CFrame.new(0.32, 0.16, 0.5) * CFrame.Angles(0.18, 0.22, math.rad(45)), color = ICE.Mid, glass = true },
	{ size = Vector3.new(0.3, 0.3, 1.5), off = CFrame.new(-0.3, -0.12, 0.7) * CFrame.Angles(-0.16, -0.24, math.rad(45)), color = ICE.Mid, glass = true },
	{ size = Vector3.new(0.16, 0.16, 2.2), off = CFrame.new(), color = WHITE, glass = false },
}

local function makeShard(cf: CFrame): { { part: BasePart, off: CFrame } }
	local pieces = {}
	for _, l in SHARD_LAYOUT do
		local part = Effects.Part({
			Size = l.size,
			CFrame = cf * l.off,
			Material = if l.glass then Enum.Material.Glass else Enum.Material.Neon,
			Color = l.color,
			Transparency = if l.glass then 0.15 else 0,
			Reflectance = if l.glass then 0.25 else 0,
		})
		table.insert(pieces, { part = part, off = l.off })
	end
	local core = pieces[#pieces].part
	local a0 = Make("Attachment", { Position = Vector3.new(0, 0.3, 0.6), Parent = core })
	local a1 = Make("Attachment", { Position = Vector3.new(0, -0.3, 0.6), Parent = core })
	Make("Trail", {
		Attachment0 = a0,
		Attachment1 = a1,
		Color = Seq(WHITE, ICE.Light, ICE.Mid),
		Transparency = NSeq(0.25, 1),
		WidthScale = NSeq(1, 0.1),
		Lifetime = 0.25,
		LightEmission = 0.6,
		LightInfluence = 0,
		FaceCamera = true,
		Parent = core,
	})
	local att = Make("Attachment", { Parent = core })
	Effects.Emitter(att, {
		Texture = TEX.Sparkle,
		Rate = 30 * Effects.Quality,
		Color = Seq(WHITE, ICE.Light),
		Speed = NumberRange.new(0.5, 2),
		Lifetime = NumberRange.new(0.3, 0.6),
		Size = NSeq(0.35, 0),
	})
	Effects.Emitter(att, {
		Texture = TEX.Smoke,
		Rate = 18 * Effects.Quality,
		Color = ColorSequence.new(ICE.Light),
		LightEmission = 0.2,
		LightInfluence = 0.6,
		Speed = NumberRange.new(0.2, 1),
		Lifetime = NumberRange.new(0.35, 0.6),
		Size = NSeq(0.6, 1.8),
		Transparency = NSeq(0.55, 0.8, 1),
	})
	return pieces
end

-- Drei Eis-Geschosse im Faecher
function V.FrostShard(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local d = def("FrostShard")
	Poser.Sequence(caster, { { P.CastForward, 0.4 } }, 0.2)
	local handPos = Effects.HandPosition(caster, "Right") or root.Position
	-- Kaelte sammelt sich an der Hand
	Effects.Burst(handPos, 10, {
		Texture = TEX.Sparkle,
		Color = Seq(WHITE, ICE.Light),
		Speed = NumberRange.new(2, 6),
		Lifetime = NumberRange.new(0.2, 0.4),
		Size = NSeq(0.6, 0),
	})
	Effects.SmokePuff(handPos, 3, ICE.Light, 0.5, { Life = 0.5, Rise = 0.3 })
	Effects.Sound("Ice", root.Position, { Pitch = 1.3, Volume = 0.5 })

	task.delay(d.Timing.Release, function()
		local origin: Vector3 = p.Extra.Origin or (root.Position + Vector3.new(0, 1, 0))
		local dirs: { Vector3 } = p.Extra.Dirs or { root.CFrame.LookVector }
		local speed: number = d.Timing.Speed
		local range: number = d.Range
		Effects.Flash(origin, ICE.Light, 3.5, 0.15)
		Effects.SmokePuff(origin, 4, ICE.Light, 0.7, { Life = 0.6 })
		local shards = {}
		for _, dir in dirs do
			local cf = CFrame.lookAt(origin, origin + dir)
			table.insert(shards, { pieces = makeShard(cf), pos = origin, dir = dir, traveled = 0, alive = true })
		end
		local function destroyShard(s: any)
			for _, piece in s.pieces do
				piece.part:Destroy()
			end
		end
		local characters = Effects.Characters()
		Effects.Animate(range / speed + 0.15, function(_, dt)
			for _, s in shards do
				if not s.alive then
					continue
				end
				local step = speed * dt
				local nextPos = s.pos + s.dir * step
				local stop = false
				for _, ch in characters do
					if ch ~= caster then
						local r = Effects.Root(ch)
						if r and (r.Position - nextPos).Magnitude < 3.4 then
							stop = true
							break
						end
					end
				end
				if not stop and Effects.RaycastMap(s.pos, s.dir * step) then
					stop = true
				end
				s.pos = nextPos
				s.traveled += step
				if stop or s.traveled >= range then
					s.alive = false
					frostBurst(s.pos, s.dir)
					destroyShard(s)
				else
					local cf = CFrame.lookAt(s.pos, s.pos + s.dir) * CFrame.Angles(0, 0, s.traveled * 0.25)
					for _, piece in s.pieces do
						piece.part.CFrame = cf * piece.off
					end
				end
			end
		end, function()
			for _, s in shards do
				if s.alive then
					s.alive = false
					destroyShard(s)
				end
			end
		end)
	end)
end

-- Der Zaubernde wird zum Blitz: zuckende Blitze mit Verzweigungen, Nachbilder, Funken, Brandspur
function V.VoltDash(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local d = def("VoltDash")
	local L = PAL.Lightning
	local tp: number = d.Timing.Teleport
	local from: Vector3 = p.Extra.From or root.Position
	local to: Vector3 = p.Extra.To or (root.Position + root.CFrame.LookVector * 22)
	local path = to - from
	-- Nachbilder entlang der Strecke (vor dem Unsichtbar-Werden aufgenommen)
	Effects.Afterimage(caster, L.Glow, 0.35, 0.5)
	if path.Magnitude > 3 then
		for i = 1, 3 do
			Effects.Afterimage(caster, L.Glow:Lerp(WHITE, 0.3), 0.22 + i * 0.05, 0.62 + i * 0.08, CFrame.new(path * (i / 4)))
		end
	end
	Effects.Sound("Electric", from)
	Effects.Sparks(from, 14, L.Glow, 30, { Gravity = 10, Colors = Seq(WHITE, L.Glow) })
	Effects.Flash(from, L.Glow, 5, 0.2)
	local g0 = Effects.Ground(from)
	if from.Y - g0.Y < 6 then
		Effects.Dust(g0, 5, 0.9)
	end
	if not ctx.Preview then
		Effects.SetCharacterVisible(caster, false)
	end
	-- Kleiner heller Kern, der die Strecke entlang zuckt
	local orb = Effects.Ball(CFrame.new(from), 1, WHITE)
	local orbAtt = Make("Attachment", { Parent = orb })
	Effects.Emitter(orbAtt, {
		Texture = TEX.Sparks,
		Rate = 100 * Effects.Quality,
		Color = Seq(WHITE, L.Glow),
		Speed = NumberRange.new(4, 10),
		Lifetime = NumberRange.new(0.1, 0.25),
		Size = NSeq(0.35, 0),
	})
	Effects.Trail(orb, Seq(WHITE, L.Glow, L.Outer), 0.16, 1.2)
	Make("PointLight", { Color = L.Glow, Range = 20, Brightness = 5, Parent = orb })
	Effects.Clean(orb, tp + 0.5)
	Effects.Animate(tp, function(a)
		local jitter = Vector3.new(rng:NextNumber(-0.4, 0.4), rng:NextNumber(-0.4, 0.4), rng:NextNumber(-0.4, 0.4))
		orb.CFrame = CFrame.new(from:Lerp(to, a) + jitter)
	end, function()
		orb.Transparency = 1
		orbAtt:Destroy()
	end)
	-- Hauptblitz (flackert nach) + zweiter, violetter Blitz
	local up = Vector3.new(0, 0.6, 0)
	local segs = math.clamp(math.floor(path.Magnitude / 1.8), 5, 16)
	Effects.Bolt(from + up, to + up, { Color = L.Glow, Width = 0.3, Duration = 0.35, Branches = 3, Jitter = 1.8, Segments = segs, Flicker = 2 })
	task.delay(0.04, function()
		Effects.Bolt(from, to + up * 0.5, { Color = L.Outer, Width = 0.16, Duration = 0.3, Branches = 2, Jitter = 2.4, Segments = segs })
	end)

	task.delay(tp, function()
		if not ctx.Preview then
			Effects.SetCharacterVisible(caster, true)
		end
		Effects.Flash(to, L.Glow, 6, 0.2)
		Effects.Sparks(to, 20, L.Glow, 34, { Gravity = 15, Colors = Seq(WHITE, L.Glow) })
		local g1 = Effects.Ground(to)
		if to.Y - g1.Y < 6 then
			Effects.DustRing(g1, 5, nil, { Count = 8, Life = 0.8 })
		end
		Effects.Light(to, L.Glow, 24, 5, 0.4)
		Effects.Sound("Electric", to, { Pitch = 1.4 })
		-- Russige Spur auf dem Boden + duenne Glimmlinie
		local len = (g1 - g0).Magnitude
		if len > 2 then
			local mid = (g0 + g1) / 2 + Vector3.new(0, 0.07, 0)
			local streakCF = CFrame.lookAt(mid, g1 + Vector3.new(0, 0.07, 0))
			local streak = Effects.Part({ Transparency = 1, Size = Vector3.new(1.6, 0.05, len), CFrame = streakCF })
			local decal = Make("Decal", { Texture = TEX.Smoke, Face = Enum.NormalId.Top, Color3 = C(26, 24, 32), Transparency = 0.25, Parent = streak })
			Effects.Tween(decal, 1.2, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.5)
			Effects.Clean(streak, 1.8)
			local glowLine = Effects.Part({ Size = Vector3.new(0.12, 0.06, len), CFrame = streakCF + Vector3.new(0, 0.02, 0), Color = L.Glow, Transparency = 0.3 })
			Effects.Tween(glowLine, 0.35, { Transparency = 1 })
			Effects.Clean(glowLine, 0.4)
		end
		-- kleine Nachentladungen am Ziel
		for i = 1, 3 do
			task.delay(0.05 + i * 0.07, function()
				local q = to + Vector3.new(rng:NextNumber(-2.5, 2.5), rng:NextNumber(-2, 1), rng:NextNumber(-2.5, 2.5))
				Effects.Bolt(to + up, q, { Color = L.Glow, Width = 0.1, Duration = 0.12, Segments = 4, Jitter = 0.6 })
			end)
		end
		if isLocalChar(caster) then
			Effects.Shake(0.7, 0.2)
		end
	end)
end

-- SELTEN ------------------------------------------------------------------------------

-- Hitze sammeln, dann eine wandernde Feuerwand im Ring, Rauch, Glut und verbrannter Boden
function V.InfernoRing(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local d = def("InfernoRing")
	local F = PAL.Fire
	local charge: number = d.Timing.Charge
	local expand: number = d.Timing.Expand
	local range: number = d.Range
	Poser.Sequence(caster, { { P.ChargeLow, charge }, { P.ArmsOut, 0.45 } }, 0.3)
	Effects.Sound("Charge", root.Position, { Pitch = 1.4 })
	local g0 = Effects.Ground(root.Position)
	-- Flammen werden eingesaugt
	local sphere = Effects.Ball(root.CFrame, 14, F.Mid, { Transparency = 1 })
	Effects.Stream(sphere, charge, {
		Texture = TEX.Fire,
		Rate = 110,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Speed = NumberRange.new(14, 18),
		Lifetime = NumberRange.new(0.35, 0.45),
		Color = FIRE,
		Size = NSeq(0.6, 1.4, 0.3),
		SpreadAngle = Vector2.new(0, 0),
		LightEmission = 0.9,
	})
	Effects.Clean(sphere, charge + 0.6)
	-- Boden glueht auf, Glut steigt auf
	local glow = Effects.GroundMark(g0, 1, F.Mid, charge + 0.25, { Texture = TEX.Glow, Transparency = 0.35, Lift = 0.1 })
	Effects.Tween(glow, charge, { Size = Vector3.new(14, 0.05, 14) })
	local _, emberAtt = Effects.Anchor(g0 + Vector3.new(0, 0.3, 0), charge + 1.5)
	Effects.Stream(emberAtt, charge, {
		Texture = TEX.Sparks,
		Rate = 40,
		Color = Seq(F.Hot, F.Mid),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(60, 60),
		Speed = NumberRange.new(3, 8),
		Lifetime = NumberRange.new(0.5, 1),
		Size = NSeq(0.25, 0),
		Acceleration = Vector3.new(0, 6, 0),
	})
	Effects.Light(root, F.Mid, 22, 4, charge + 0.2, charge)

	task.delay(charge, function()
		if not root.Parent then
			return
		end
		local center = root.Position
		local g = Effects.Ground(center)
		Effects.Flash(center, F.Hot, 8, 0.25)
		Effects.Sound("Fire", center)
		Effects.Sound("Explosion", center, { Volume = 0.7 })
		-- Feuerwand: Anker wandern nach aussen, Flammen bleiben zurueck
		local count = math.floor(20 * math.max(Effects.Quality, 0.5))
		local anchors: { Part } = {}
		for _ = 1, count do
			local anchor, att = Effects.Anchor(g)
			Effects.Stream(att, expand + 0.15, {
				Texture = TEX.Fire,
				Rate = 30,
				Color = FIRE,
				EmissionDirection = Enum.NormalId.Top,
				Speed = NumberRange.new(6, 12),
				SpreadAngle = Vector2.new(14, 14),
				Lifetime = NumberRange.new(0.35, 0.6),
				Size = NSeq(2.6, 4.2, 0.4),
				Acceleration = Vector3.new(0, 12, 0),
				LightEmission = 0.85,
				RotSpeed = NumberRange.new(-90, 90),
			})
			Effects.Stream(att, expand + 0.25, {
				Texture = TEX.Smoke,
				Rate = 7,
				Color = Seq(C(96, 72, 60), F.Smoke),
				LightEmission = 0,
				LightInfluence = 0.7,
				EmissionDirection = Enum.NormalId.Top,
				Speed = NumberRange.new(8, 12),
				SpreadAngle = Vector2.new(20, 20),
				Lifetime = NumberRange.new(0.8, 1.3),
				Size = NSeq(3, 7),
				Transparency = NSeq(0.45, 0.7, 1),
				Acceleration = Vector3.new(0, 5, 0),
			})
			Effects.Clean(anchor, expand + 1.8)
			table.insert(anchors, anchor)
		end
		Effects.Animate(expand + 0.15, function(a)
			local r = 1.5 + (range - 1.5) * Effects.Ease(a, "OutCubic")
			for i, anchor in anchors do
				local ang = (i / #anchors) * TAU
				anchor.CFrame = CFrame.new(g + Vector3.new(math.cos(ang) * r, 0.8, math.sin(ang) * r))
			end
		end)
		-- Restfeuer: einzelne Flammen brennen am Rand weiter
		for i = 1, math.floor(6 * Effects.Quality) do
			local ang = (i / 6) * TAU + rng:NextNumber(-0.3, 0.3)
			local r = range * rng:NextNumber(0.55, 0.9)
			local _, att = Effects.Anchor(g + Vector3.new(math.cos(ang) * r, 0.3, math.sin(ang) * r), 2.4)
			task.delay(expand * (r / range), function()
				Effects.Stream(att, 1.2, {
					Texture = TEX.Fire,
					Rate = 14,
					Color = FIRE,
					EmissionDirection = Enum.NormalId.Top,
					Speed = NumberRange.new(2, 5),
					SpreadAngle = Vector2.new(15, 15),
					Lifetime = NumberRange.new(0.3, 0.5),
					Size = NSeq(1.4, 2, 0),
					Acceleration = Vector3.new(0, 8, 0),
					LightEmission = 0.85,
				})
			end)
		end
		Effects.DustRing(g, range * 0.9, Effects.DustColor(g):Lerp(C(80, 62, 52), 0.4))
		Effects.Sparks(center, 26, F.Mid, 36, { Gravity = -6, MaxLife = 1, Colors = Seq(F.Hot, F.Mid) })
		Effects.Scorch(g, range * 0.75, 2.8)
		Effects.Shockwave(g + Vector3.new(0, 0.6, 0), range * 2.2, F.Hot, 0.45)
		Effects.Light(center, F.Mid, 40, 6, 0.8)
		Effects.ShakeAt(center, 2, 80, 0.4)
	end)
end

-- Wasser-Wirbel: Wasserbecken, Spiral-Stroeme aus Trails, Gischt, Tropfen und Spritzer
function V.TidalVortex(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local d = def("TidalVortex")
	local W = PAL.Water
	local spawn: number = d.Timing.Spawn
	local duration: number = d.Timing.Duration
	local center: Vector3 = p.Extra.Center or Effects.Ground(p.Aim)
	Poser.Sequence(caster, { { P.RightUp, 0.25 }, { P.CastForward, 0.45 } }, 0.3)
	Effects.Sound("Water", root.Position)
	-- Vorzeichen: der Boden wird nass, erste Tropfen
	Effects.GroundMark(center, 6, W.Deep, spawn + 0.4, { Transparency = 0.45, FadeIn = 0.15 })
	Effects.Sparks(center + Vector3.new(0, 0.3, 0), 8, W.Light, 16, {
		Colors = Seq(W.Foam, W.Light),
		Spread = Vector2.new(30, 30),
		Gravity = 40,
		MaxLife = 0.5,
		Brightness = 1,
	})

	task.delay(spawn, function()
		local function splash(scale: number)
			Effects.Burst(center + Vector3.new(0, 0.5, 0), 30 * scale, {
				Texture = TEX.Sparks,
				Color = Seq(W.Foam, W.Light),
				Orientation = Enum.ParticleOrientation.VelocityParallel,
				Squash = NSeq(1.2, 0.3),
				EmissionDirection = Enum.NormalId.Top,
				SpreadAngle = Vector2.new(50, 50),
				Speed = NumberRange.new(18 * scale, 32 * scale),
				Acceleration = Vector3.new(0, -60, 0),
				Lifetime = NumberRange.new(0.6, 1),
				Size = NSeq(0.5, 0.25),
				LightEmission = 0.3,
				LightInfluence = 0.5,
				Drag = 0.5,
			})
			Effects.Burst(center + Vector3.new(0, 0.8, 0), 10 * scale, {
				Texture = TEX.Smoke,
				Color = ColorSequence.new(W.Foam),
				LightEmission = 0.15,
				LightInfluence = 0.75,
				EmissionDirection = Enum.NormalId.Top,
				SpreadAngle = Vector2.new(70, 70),
				Speed = NumberRange.new(6 * scale, 14 * scale),
				Lifetime = NumberRange.new(0.6, 1.1),
				Size = NSeq(2 * scale, 5 * scale),
				Transparency = NSeq(0.3, 0.6, 1),
				Drag = 3,
			})
			Effects.DustRing(center, 9 * scale, W.Foam, { Count = 12 })
			Effects.Sound("Water", center, { Volume = scale })
		end
		splash(1)

		-- Wasserbecken am Boden
		local pool = Effects.Part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 2, 2),
			CFrame = CFrame.new(center + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Glass,
			Color = W.Mid,
			Transparency = 0.4,
			Reflectance = 0.15,
		})
		Effects.Tween(pool, 0.35, { Size = Vector3.new(0.3, 22, 22) }, Enum.EasingStyle.Back)
		Effects.Clean(pool, duration + 1)

		-- Schaum am Beckenrand + Tropfen, die aus dem Wirbel geschleudert werden
		local holder = Effects.Part({ Transparency = 1, Size = SMALL, CFrame = CFrame.new(center + Vector3.new(0, 0.4, 0)) })
		Effects.Clean(holder, duration + 2)
		for i = 1, 8 do
			local a = (i / 8) * TAU
			local att = Make("Attachment", { Position = Vector3.new(math.cos(a) * 10, 0, math.sin(a) * 10), Parent = holder })
			Effects.Stream(att, duration, {
				Texture = TEX.Smoke,
				Rate = 5,
				Color = ColorSequence.new(W.Foam),
				LightEmission = 0.15,
				LightInfluence = 0.75,
				EmissionDirection = Enum.NormalId.Top,
				SpreadAngle = Vector2.new(50, 50),
				Speed = NumberRange.new(1, 3),
				Lifetime = NumberRange.new(0.6, 1),
				Size = NSeq(1.2, 2.8),
				Transparency = NSeq(0.4, 0.7, 1),
			})
		end
		local coreAtt = Make("Attachment", { Position = Vector3.new(0, 1, 0), Parent = holder })
		Effects.Stream(coreAtt, duration, {
			Texture = TEX.Sparks,
			Rate = 40,
			Color = Seq(W.Foam, W.Light),
			Orientation = Enum.ParticleOrientation.VelocityParallel,
			Squash = NSeq(1, 0.3),
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(70, 70),
			Speed = NumberRange.new(14, 22),
			Acceleration = Vector3.new(0, -40, 0),
			Lifetime = NumberRange.new(0.6, 1),
			Size = NSeq(0.4, 0.2),
			LightEmission = 0.3,
			LightInfluence = 0.5,
		})
		Effects.Stream(coreAtt, duration, {
			Texture = TEX.Smoke,
			Rate = 26,
			Color = Seq(W.Foam, W.Light),
			LightEmission = 0.2,
			LightInfluence = 0.7,
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(15, 15),
			Speed = NumberRange.new(10, 16),
			Lifetime = NumberRange.new(0.8, 1.2),
			Size = NSeq(2, 5),
			Transparency = NSeq(0.45, 0.75, 1),
			RotSpeed = NumberRange.new(-200, 200),
		})
		Effects.Light(holder, W.Light, 24, 2, duration, 0.3)

		-- Wassersaeule in der Mitte (Glas, dreht sich)
		local column = Effects.Part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, 3, 3),
			Material = Enum.Material.Glass,
			Color = W.Mid,
			Transparency = 0.55,
			Reflectance = 0.1,
			CFrame = CFrame.new(center),
		})
		Effects.Clean(column, duration + 0.5)

		-- Spiral-Stroeme: Traeger mit Trails schrauben sich nach oben (werden laufend nachgeschoben)
		local H = 17
		local live = {}
		local nextSpawn = 0
		local waterSeq = Seq(W.Foam, W.Light, W.Mid)
		Effects.Animate(duration, function(a)
			local t = a * duration
			local scale = math.min(math.clamp(t / 0.35, 0, 1), math.clamp((duration - t) / 0.35, 0, 1))
			if t >= nextSpawn and t < duration - 0.45 then
				nextSpawn = t + 0.09 / math.max(Effects.Quality, 0.5)
				local phase = rng:NextNumber(0, TAU)
				local rMul = rng:NextNumber(0.85, 1.15)
				local r0 = 1.4 * rMul * math.max(scale, 0.3)
				local startPos = center + Vector3.new(math.cos(phase + t * 2) * r0, 0.3, math.sin(phase + t * 2) * r0)
				local part = trailCarrier(startPos, rng:NextNumber(1.6, 2.6), waterSeq, 0.45, {
					LightEmission = 0.25,
					LightInfluence = 0.6,
					Transparency = NSeq(0.15, 0.45, 1),
					WidthScale = NSeq(0.6, 1, 0.3),
				})
				table.insert(live, { part = part, born = t, phase = phase, life = rng:NextNumber(0.6, 0.8), rMul = rMul })
			end
			for i = #live, 1, -1 do
				local c = live[i]
				local u = (t - c.born) / c.life
				if u >= 1 then
					Effects.Clean(c.part, 0.5)
					table.remove(live, i)
				else
					local h = u * H * math.max(scale, 0.2)
					local r = (1.4 + h * 0.5) * c.rMul * math.max(scale, 0.3)
					local ang = c.phase + u * 9 + t * 2
					c.part.CFrame = CFrame.new(center + Vector3.new(math.cos(ang) * r, h + 0.3, math.sin(ang) * r))
				end
			end
			local colH = math.max(0.1, H * 0.9 * scale)
			column.Size = Vector3.new(colH, 3 + scale * 0.6, 3 + scale * 0.6)
			column.CFrame = CFrame.new(center + Vector3.new(0, colH / 2, 0)) * CFrame.Angles(0, t * 5, math.rad(90))
		end, function()
			for _, c in live do
				Effects.Clean(c.part, 0.5)
			end
			table.clear(live)
			column:Destroy()
			if pool.Parent then
				Effects.Tween(pool, 0.4, { Size = Vector3.new(0.3, 26, 26), Transparency = 1 })
			end
			Effects.GroundMark(center, 9, W.Deep, 2.5, { Transparency = 0.55 })
			splash(1.3)
		end)
	end)
end

-- EPISCH --------------------------------------------------------------------------------

-- Gewitterwolke mit Regen, dann drei Blitzeinschlaege mit Verzweigungen, Staub und Brandflecken
function V.Thunderclap(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local d = def("Thunderclap")
	local L = PAL.Lightning
	local strikes: { Vector3 } = p.Extra.Strikes or { Effects.Ground(p.Aim) }
	local lastT: number = d.Timing["Strike" .. #strikes] or d.Timing.Strike3 or 1.25
	Poser.Sequence(caster, { { P.RightUp, lastT } }, 0.3)
	-- Die Hand knistert
	local hand = Effects.HandPart(caster, "Right")
	if hand then
		local att = Make("Attachment", { Parent = hand })
		Effects.Stream(att, lastT, {
			Texture = TEX.Sparks,
			Rate = 40,
			Color = Seq(WHITE, L.Glow),
			Speed = NumberRange.new(3, 8),
			Lifetime = NumberRange.new(0.1, 0.25),
			Size = NSeq(0.35, 0),
		})
		Effects.Clean(att, lastT + 1)
		for i = 1, 3 do
			task.delay(i * 0.18, function()
				if hand.Parent then
					local h = hand.Position
					Effects.Bolt(h, h + Vector3.new(rng:NextNumber(-1.5, 1.5), rng:NextNumber(0.5, 2), rng:NextNumber(-1.5, 1.5)), {
						Color = L.Glow,
						Width = 0.08,
						Duration = 0.1,
						Segments = 3,
						Jitter = 0.4,
					})
				end
			end)
		end
	end

	local center = strikes[1]
	local cloudPos = center + Vector3.new(0, 34, 0)
	local total = lastT + 0.7
	-- Gewitterwolke: dunkle Schicht + hellere Unterseite
	local cloud = Effects.Part({ Size = Vector3.new(30, 4, 30), CFrame = CFrame.new(cloudPos), Transparency = 1 })
	Effects.Stream(cloud, total, {
		Texture = TEX.ExplosionSmoke,
		Rate = 45,
		Shape = Enum.ParticleEmitterShape.Box,
		Color = Seq(C(78, 80, 96), C(42, 44, 56)),
		LightEmission = 0,
		LightInfluence = 0.35,
		Speed = NumberRange.new(0, 1.5),
		Lifetime = NumberRange.new(1.4, 2.2),
		Size = NSeq(9, 15),
		Transparency = NSeq(1, 0.15, 0.2, 1),
		RotSpeed = NumberRange.new(-20, 20),
	})
	local under = Effects.Part({ Size = Vector3.new(26, 1, 26), CFrame = CFrame.new(cloudPos - Vector3.new(0, 2.5, 0)), Transparency = 1 })
	Effects.Stream(under, total, {
		Texture = TEX.Smoke,
		Rate = 18,
		Shape = Enum.ParticleEmitterShape.Box,
		Color = ColorSequence.new(C(116, 120, 138)),
		LightEmission = 0,
		LightInfluence = 0.5,
		Speed = NumberRange.new(0, 1),
		Lifetime = NumberRange.new(1.2, 1.8),
		Size = NSeq(7, 11),
		Transparency = NSeq(1, 0.35, 1),
		RotSpeed = NumberRange.new(-15, 15),
	})
	-- Regen unter der Wolke
	Effects.Stream(under, total - 0.2, {
		Texture = TEX.Sparks,
		Rate = 70,
		Shape = Enum.ParticleEmitterShape.Box,
		Color = ColorSequence.new(C(196, 206, 226)),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = NSeq(2.5),
		EmissionDirection = Enum.NormalId.Bottom,
		SpreadAngle = Vector2.new(4, 4),
		Speed = NumberRange.new(60, 70),
		Lifetime = NumberRange.new(0.45, 0.5),
		Size = NSeq(0.2),
		Transparency = NSeq(0.4, 0.6),
		LightEmission = 0.1,
		LightInfluence = 0.6,
		RotSpeed = NumberRange.new(0),
		Rotation = NumberRange.new(0),
	})
	Effects.Clean(cloud, total + 2.5)
	Effects.Clean(under, total + 2.5)
	-- Wetterleuchten in der Wolke
	local flicker = Make("PointLight", { Color = L.Glow, Range = 60, Brightness = 0, Parent = cloud })
	task.spawn(function()
		for _ = 1, math.floor(total / 0.08) do
			if not flicker.Parent then
				return
			end
			flicker.Brightness = if rng:NextNumber() > 0.65 then rng:NextNumber(2, 6) else 0
			task.wait(0.08)
		end
		if flicker.Parent then
			flicker.Brightness = 0
		end
	end)
	Effects.Sound("Rumble", center, { Volume = 0.6, Pitch = 0.7 })
	if Effects.Near(center, 90) then
		Effects.ColorGrade({ Brightness = -0.06, Contrast = 0.12, Saturation = -0.2, TintColor = C(215, 220, 240) }, 0.3, lastT, 0.6)
	end

	for i, pos in strikes do
		local t: number = d.Timing["Strike" .. i] or 0.6
		local heavy = i == #strikes
		-- Dezente Warnung am Boden + Knistern kurz vor dem Einschlag
		Effects.GroundMark(pos, 7.5, L.Glow, t + 0.05, { Texture = TEX.Shockwave, Transparency = 0.6, FadeIn = 0.25, FadeOut = 0.1 })
		task.delay(math.max(0, t - 0.15), function()
			Effects.Sparks(pos + Vector3.new(0, 0.3, 0), 6, L.Glow, 10, { Gravity = 0, MaxLife = 0.2 })
		end)
		task.delay(t, function()
			local top = cloudPos + Vector3.new(rng:NextNumber(-5, 5), 0, rng:NextNumber(-5, 5))
			Effects.Bolt(top, pos, {
				Color = L.Glow,
				Outer = L.Outer,
				Width = if heavy then 0.85 else 0.65,
				Duration = 0.35,
				Branches = 4,
				Jitter = 3.5,
				Segments = 14,
				Flicker = 2,
			})
			Effects.Flash(pos + Vector3.new(0, 1, 0), WHITE, if heavy then 11 else 8, 0.2)
			Effects.Glow(pos + Vector3.new(0, 1, 0), L.Glow, if heavy then 20 else 14, 0.35)
			Effects.Sparks(pos + Vector3.new(0, 0.5, 0), 20, L.Glow, 40, { Gravity = 35, Colors = Seq(WHITE, L.Glow) })
			Effects.DustRing(pos, if heavy then 9 else 7)
			Effects.Dust(pos, 6, 1.4)
			Effects.Rocks(pos, if heavy then 7 else 4, { MaxUp = 35, Spread = 16, MaxSize = 1 })
			Effects.Scorch(pos, 3.5, 2.4)
			Effects.Cracks(pos, 5, 6, L.Glow, 1.2)
			Effects.Shockwave(pos + Vector3.new(0, 0.4, 0), 14, L.Glow, 0.35)
			Effects.Light(pos, L.Glow, 60, 9, 0.35)
			-- Restspannung am Boden
			for k = 1, 2 do
				task.delay(0.08 * k, function()
					local q = pos + Vector3.new(rng:NextNumber(-3, 3), 0.2, rng:NextNumber(-3, 3))
					Effects.Bolt(pos + Vector3.new(0, 0.3, 0), q, { Color = L.Glow, Width = 0.1, Duration = 0.12, Segments = 4, Jitter = 0.7 })
				end)
			end
			if Effects.Near(pos, 70) then
				Effects.ScreenFlash(WHITE, 0.12, 0.75)
			end
			if heavy and ctx.Involved and Effects.Near(pos, 60) then
				Effects.ImpactFrame(0.05, 0.8)
			end
			Effects.ShakeAt(pos, if heavy then 2.2 else 1.6, 70, 0.35)
			Effects.Sound("Thunder", pos)
		end)
	end
end

-- In Schatten aufloesen (Tinte), hinter dem Gegner auftauchen und einen scharfen X-Schnitt ziehen
function V.ShadowStep(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local d = def("ShadowStep")
	local S = PAL.Shadow
	local tp: number = d.Timing.Teleport
	local slashT: number = d.Timing.Slash
	local origin = root.Position
	local dest: CFrame = p.Extra.Dest or (root.CFrame * CFrame.new(0, 0, -15))

	local function inkBurst(pos: Vector3, scale: number)
		Effects.Burst(pos, 16 * scale, {
			Texture = TEX.Smoke,
			Color = Seq(S.Dark, S.Ink),
			LightEmission = 0,
			LightInfluence = 0.25,
			Speed = NumberRange.new(5 * scale, 12 * scale),
			Lifetime = NumberRange.new(0.45, 0.9),
			Size = NSeq(2 * scale, 4.5 * scale, 3 * scale),
			Transparency = NSeq(0.05, 0.4, 1),
			Drag = 4,
			RotSpeed = NumberRange.new(-120, 120),
			Acceleration = Vector3.new(0, 3, 0),
		})
		Effects.Sparks(pos, 7 * scale, S.Accent, 14, { Gravity = -3, MaxLife = 0.6, Colors = Seq(C(200, 170, 255), S.Accent) })
	end

	-- Aufloesen: mattes dunkles Nachbild + Tinten-Rauch aus den Koerperteilen
	Effects.Afterimage(caster, S.Dark, 0.45, 0.1)
	local count = 0
	for _, child in caster:GetChildren() do
		if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" and count < 8 then
			count += 1
			Effects.Burst((child :: BasePart).Position, 2, {
				Texture = TEX.Smoke,
				Color = Seq(S.Dark, S.Ink),
				LightEmission = 0,
				LightInfluence = 0.25,
				Speed = NumberRange.new(1, 3),
				Lifetime = NumberRange.new(0.5, 0.8),
				Size = NSeq(1.2, 2.6),
				Transparency = NSeq(0.1, 0.5, 1),
				Acceleration = Vector3.new(0, 4, 0),
			})
		end
	end
	inkBurst(origin, 1)
	local gOrigin = Effects.Ground(origin)
	Effects.GroundMark(gOrigin, 3, S.Ink, 1.2, { Transparency = 0.25, Grow = 0.1 })
	Effects.Sound("Shadow", origin)
	if not ctx.Preview then
		Effects.SetCharacterVisible(caster, false)
	end
	-- Schattenfaden vom Start zum Ziel
	Effects.TrailLine(origin, dest.Position, S.Ink, tp + 0.25, 1.3, { CoreColor = S.Accent, LightEmission = 0, Sweep = tp })

	task.delay(tp, function()
		if not ctx.Preview then
			Effects.SetCharacterVisible(caster, true)
		end
		-- Wiederauftauchen: Rauch zieht sich zusammen
		local sph = Effects.Ball(CFrame.new(dest.Position), 7, S.Ink, { Transparency = 1 })
		Effects.BurstOn(sph, 14, {
			Texture = TEX.Smoke,
			Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
			Speed = NumberRange.new(10, 14),
			Lifetime = NumberRange.new(0.2, 0.3),
			Color = Seq(S.Dark, S.Ink),
			Size = NSeq(2.5, 1),
			Transparency = NSeq(0.2, 1),
			LightEmission = 0,
			LightInfluence = 0.25,
			SpreadAngle = Vector2.new(0, 0),
		})
		Effects.Clean(sph, 0.6)
		Effects.GroundMark(Effects.Ground(dest.Position), 3, S.Ink, 1, { Transparency = 0.3, Grow = 0.1 })
		Effects.Light(dest.Position, S.Accent, 14, 2, 0.4)
		Poser.Sequence(caster, { { P.XSlash1, math.max(0.05, slashT - tp) }, { P.XSlash2, 0.3 } }, 0.25)
	end)

	task.delay(slashT, function()
		local hitPos = dest.Position + dest.LookVector * 2.6 + Vector3.new(0, 0.4, 0)
		local right, up = dest.RightVector, dest.UpVector
		local reach = 5.5
		local d1 = (right + up).Unit * reach
		local d2 = (-right + up).Unit * reach
		-- Erster Schnitt: oben rechts -> unten links (dunkle Kante, heller Kern)
		Effects.TrailLine(hitPos + d1, hitPos - d1, S.Ink, 0.42, 1.1, { CoreColor = WHITE, LightEmission = 0, Sweep = 0.06 })
		Effects.Sound("Slash", hitPos, { Pitch = 1.1 })
		task.delay(0.08, function()
			-- Zweiter Schnitt: oben links -> unten rechts
			Effects.TrailLine(hitPos + d2, hitPos - d2, S.Ink, 0.42, 1.1, { CoreColor = WHITE, LightEmission = 0, Sweep = 0.06 })
			Effects.Sound("Slash", hitPos)
			Effects.Burst(hitPos, 1, {
				Texture = TEX.Core,
				Color = Seq(WHITE, C(220, 200, 255)),
				Speed = NumberRange.new(0),
				Lifetime = NumberRange.new(0.1),
				Size = NSeq(2, 6),
				Transparency = NSeq(0, 1),
				RotSpeed = NumberRange.new(0),
				ZOffset = 2,
			})
			Effects.Sparks(hitPos, 16, C(220, 200, 255), 32, { Gravity = 10, Dir = dest.LookVector, Spread = Vector2.new(60, 60) })
			inkBurst(hitPos, 0.7)
			Effects.Shockwave(hitPos, 9, S.Accent, 0.25, dest.LookVector)
			local target = p.Extra.Target
			if isLocalChar(target) or (ctx.IsCaster and target ~= nil) then
				Effects.ImpactFrame(0.06, 1)
			end
			if isLocalChar(target) then
				Effects.Vignette(C(30, 10, 50), 0.6, 0.45)
				Effects.Shake(1.4, 0.3)
			end
		end)
	end)
end

-- LEGENDAER -----------------------------------------------------------------------------

-- Brennender Meteor (Fels + Feuer + Rauchspur) mit dezentem Warnkreis, gewaltiger Einschlag mit Krater
function V.MeteorStrike(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local d = def("MeteorStrike")
	local F = PAL.Fire
	local center: Vector3 = p.Extra.Center or Effects.Ground(p.Aim)
	local start: Vector3 = p.Extra.Start or (center + Vector3.new(-40, 130, -40))
	local radius: number = d.Timing.Radius
	local fall: number = d.Timing.Fall
	Poser.Sequence(caster, { { P.RightUp, 0.7 } }, 0.3)
	Effects.Sound("Rumble", center, { Volume = 0.8 })

	-- Warnkreis: dezenter Ring + Fuellung, die mit dem Fall waechst
	Effects.GroundMark(center, radius, F.Deep, fall + 0.1, { Texture = TEX.Shockwave, Transparency = 0.5, FadeIn = 0.25, FadeOut = 0.1 })
	local fill = Effects.GroundMark(center, radius * 0.25, F.Mid, fall + 0.1, { Texture = TEX.Glow, Transparency = 0.72, Lift = 0.1, FadeOut = 0.1 })
	Effects.Tween(fill, fall, { Size = Vector3.new(radius * 2, 0.05, radius * 2) }, Enum.EasingStyle.Linear)

	-- Meteor: gluehender Kern aus Lava, umhuellt von dunklen Basaltbrocken
	local pieces: { { part: BasePart, off: CFrame } } = {}
	local core = Effects.Ball(CFrame.new(start), 6.2, C(255, 104, 34), { Material = Enum.Material.CrackedLava })
	table.insert(pieces, { part = core, off = CFrame.new() })
	for _ = 1, 6 do
		local s = rng:NextNumber(2.4, 3.6)
		local dirV = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
		if dirV.Magnitude < 0.1 then
			dirV = Vector3.yAxis
		end
		local off = CFrame.new(dirV.Unit * 2.4) * randomRot()
		local chunk = Effects.Part({
			Size = Vector3.new(s, s * rng:NextNumber(0.7, 1), s * rng:NextNumber(0.8, 1.2)),
			Material = Enum.Material.Basalt,
			Color = Effects.Vary(C(54, 46, 44), 0.1),
			CFrame = CFrame.new(start) * off,
		})
		table.insert(pieces, { part = chunk, off = off })
	end
	local att = Make("Attachment", { Parent = core })
	Effects.Emitter(att, {
		Texture = TEX.Fire,
		Rate = 90 * Effects.Quality,
		Color = FIRE,
		Speed = NumberRange.new(1, 4),
		Lifetime = NumberRange.new(0.3, 0.5),
		Size = NSeq(6, 8, 2),
		LightEmission = 0.9,
		RotSpeed = NumberRange.new(-60, 60),
	})
	Effects.Emitter(att, {
		Texture = TEX.ExplosionSmoke,
		Rate = 36 * Effects.Quality,
		Color = Seq(C(96, 74, 62), C(40, 36, 36)),
		LightEmission = 0,
		LightInfluence = 0.6,
		Speed = NumberRange.new(1, 3),
		Lifetime = NumberRange.new(1.6, 2.6),
		Size = NSeq(5, 12),
		Transparency = NSeq(0.3, 0.6, 1),
		RotSpeed = NumberRange.new(-20, 20),
	})
	Effects.Emitter(att, {
		Texture = TEX.Sparks,
		Rate = 50 * Effects.Quality,
		Color = Seq(F.Hot, F.Mid),
		Speed = NumberRange.new(6, 14),
		Lifetime = NumberRange.new(0.4, 0.8),
		Size = NSeq(0.5, 0),
	})
	Effects.Trail(core, Seq(F.Hot, F.Mid, F.Deep), 0.35, 7)
	Make("PointLight", { Color = F.Mid, Range = 50, Brightness = 4, Parent = core })
	for _, piece in pieces do
		Effects.Clean(piece.part, fall + 1)
	end

	local pressureDust = false
	Effects.Animate(fall, function(a)
		local e = a ^ 1.6
		local pos = start:Lerp(center + Vector3.new(0, 3, 0), e)
		local cf = CFrame.new(pos) * CFrame.Angles(a * 8, a * 5, 0)
		for _, piece in pieces do
			piece.part.CFrame = cf * piece.off
		end
		-- Luftdruck: kurz vor dem Einschlag wird Staub aufgewirbelt
		if a > 0.72 and not pressureDust then
			pressureDust = true
			Effects.DustRing(center, radius * 0.6, nil, { Count = 10, Life = 0.8 })
		end
	end, function()
		for _, piece in pieces do
			piece.part:Destroy()
		end
		-- EINSCHLAG ---------------------------------------------------------
		local dust = Effects.DustColor(center)
		Effects.Flash(center + Vector3.new(0, 2, 0), F.Core, 14, 0.25)
		Effects.FireBurst(center + Vector3.new(0, 2, 0), nil, 2.6, { Speed = 30 })
		Effects.Burst(center + Vector3.new(0, 3, 0), 8, {
			Texture = TEX.Core,
			Color = Seq(F.Core, F.Hot, F.Mid, F.Deep),
			Speed = NumberRange.new(4, 10),
			Lifetime = NumberRange.new(0.35, 0.6),
			Size = NSeq(10, 22),
			Transparency = NSeq(0, 0.35, 1),
			Drag = 5,
			RotSpeed = NumberRange.new(-40, 40),
			LightEmission = 1,
		})
		-- Staubkuppel in Bodenfarbe + dunkle Rauchsaeule
		Effects.Burst(center + Vector3.new(0, 2, 0), 20, {
			Texture = TEX.ExplosionSmoke,
			Color = Seq(dust, dust:Lerp(C(60, 52, 48), 0.5)),
			LightEmission = 0,
			LightInfluence = 0.85,
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(80, 80),
			Speed = NumberRange.new(18, 34),
			Lifetime = NumberRange.new(1.4, 2.4),
			Size = NSeq(8, 16),
			Transparency = NSeq(0.2, 0.55, 1),
			Drag = 2.2,
			RotSpeed = NumberRange.new(-20, 20),
		})
		Effects.Burst(center + Vector3.new(0, 4, 0), 10, {
			Texture = TEX.ExplosionSmoke,
			Color = Seq(C(80, 64, 56), C(36, 32, 32)),
			LightEmission = 0,
			LightInfluence = 0.6,
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(18, 18),
			Speed = NumberRange.new(16, 26),
			Lifetime = NumberRange.new(2, 3),
			Size = NSeq(7, 15),
			Transparency = NSeq(0.25, 0.6, 1),
			Drag = 1.2,
			Acceleration = Vector3.new(0, 3, 0),
		})
		Effects.DustRing(center, radius * 1.1, dust, { Count = 20 })
		Effects.Sparks(center + Vector3.new(0, 1, 0), 40, F.Mid, 70, { Gravity = 45, MaxLife = 1.1, Colors = Seq(F.Core, F.Hot, F.Mid) })
		-- Krater: Felsplatten am Rand, Truemmer, gluehende Brocken, Brandfleck, Glut in der Mitte, Risse
		Effects.GroundSpikes(center, radius * 0.5, 12, { MinHeight = 3, MaxHeight = 6, Stay = 2.6, WidthScale = 1.3 })
		Effects.Rocks(center, 18, { Spread = 45, MaxUp = 70, MaxSize = 2.2 })
		Effects.Rocks(center, 6, { Material = Enum.Material.CrackedLava, Color = C(110, 56, 36), Spread = 35, MaxUp = 60, MaxSize = 1.4 })
		Effects.Scorch(center, radius * 0.8, 5)
		Effects.GroundMark(center, 6, F.Mid, 3.5, { Texture = TEX.Glow, Transparency = 0.15, Lift = 0.12 })
		Effects.Cracks(center, 10, radius * 0.9, F.Mid, 3)
		Effects.Shockwave(center + Vector3.new(0, 1, 0), radius * 3, F.Hot, 0.5)
		Effects.Light(center + Vector3.new(0, 4, 0), F.Mid, 60, 8, 1.4)
		-- Restfeuer im Krater
		for _ = 1, math.floor(5 * Effects.Quality) do
			local a = rng:NextNumber(0, TAU)
			local r = rng:NextNumber(1, radius * 0.4)
			local _, fireAtt = Effects.Anchor(center + Vector3.new(math.cos(a) * r, 0.3, math.sin(a) * r), 3.4)
			Effects.Stream(fireAtt, 2.2, {
				Texture = TEX.Fire,
				Rate = 16,
				Color = FIRE,
				EmissionDirection = Enum.NormalId.Top,
				Speed = NumberRange.new(2, 5),
				SpreadAngle = Vector2.new(15, 15),
				Lifetime = NumberRange.new(0.3, 0.6),
				Size = NSeq(1.6, 2.4, 0),
				Acceleration = Vector3.new(0, 8, 0),
				LightEmission = 0.85,
			})
			Effects.Stream(fireAtt, 2.4, {
				Texture = TEX.Smoke,
				Rate = 4,
				Color = ColorSequence.new(F.Smoke),
				LightEmission = 0,
				LightInfluence = 0.7,
				EmissionDirection = Enum.NormalId.Top,
				Speed = NumberRange.new(3, 6),
				SpreadAngle = Vector2.new(15, 15),
				Lifetime = NumberRange.new(0.8, 1.2),
				Size = NSeq(1.6, 4),
				Transparency = NSeq(0.5, 0.75, 1),
			})
		end
		Effects.ShakeAt(center, 3.5, 150, 0.8)
		if Effects.Near(center, 80) then
			Effects.ScreenFlash(F.Hot, 0.2, 0.7)
		end
		if (ctx.Involved or ctx.IsCaster) and Effects.Near(center, 70) then
			Effects.ImpactFrame(0.06, 1)
		end
		Effects.Sound("BigExplosion", center)
		Effects.Sound("Explosion", center, { Volume = 0.8 })
	end)
end

-- Catmull-Rom-Spline durch Punkte (u = 0..1)
local function catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3)
end

local function pathAt(points: { Vector3 }, u: number): Vector3
	local n = #points
	local f = math.clamp(u, 0, 1) * (n - 1)
	local i = math.min(math.floor(f) + 1, n - 1)
	local t = f - (i - 1)
	return catmull(points[math.max(i - 1, 1)], points[i], points[i + 1], points[math.min(i + 2, n)], t)
end

-- Weg des Drachenkopfs beim Herauswinden (lokal: X rechts, Y oben, -Z vorne)
local DRAGON_COIL = {
	Vector3.new(0.6, 1, -1.4), -- aus den Haenden
	Vector3.new(3.2, 2.2, -0.4),
	Vector3.new(2.4, 3.8, 2.6),
	Vector3.new(-2.4, 3.6, 2.2),
	Vector3.new(-2.8, 2.6, -1.8),
	Vector3.new(0, 2.2, -4.2), -- Endposition vor dem Spieler
}
-- Koerperform waehrend des Feuerstosses (vom Kopf ueber die Schulter nach hinten)
local DRAGON_BODY = {
	Vector3.new(0, 2.2, -4.2),
	Vector3.new(0.5, 3.4, -2.2),
	Vector3.new(1.7, 4.6, 0.2),
	Vector3.new(0.8, 4.1, 2.4),
	Vector3.new(-1, 3, 3.6),
	Vector3.new(-1.7, 1.8, 5.2),
}

-- Ein schlangenfoermiger Feuerdrache windet sich aus den Haenden um den Spieler und speit einen Flammenstrom
function V.DragonBreath(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local d = def("DragonBreath")
	local F = PAL.Fire
	local windup: number = d.Timing.Windup
	local channel: number = d.Timing.Channel
	local total = windup + channel
	Poser.Sequence(caster, { { P.Breath, total } }, 0.3)
	Effects.Sound("Charge", root.Position, { Pitch = 0.9 })
	Effects.Sound("Fire", root.Position, { Pitch = 0.7, Volume = 0.6 })

	local N = 12
	local LAG = 0.075
	local holder = Effects.Part({ Name = "FireDragon", Transparency = 1, Size = SMALL, CFrame = root.CFrame })
	Effects.Clean(holder, total + 2)
	local atts: { Attachment } = {}
	for i = 1, N do
		atts[i] = Make("Attachment", { Parent = holder })
	end
	-- Koerper: Beams mit Feuer-Textur zwischen den Gliedern, zum Schwanz hin duenner
	local beams: { Beam } = {}
	for i = 1, N - 1 do
		local t0, t1 = (i - 1) / (N - 1), i / (N - 1)
		local beam = Make("Beam", {
			Attachment0 = atts[i],
			Attachment1 = atts[i + 1],
			Texture = TEX.Fire,
			TextureMode = Enum.TextureMode.Stretch,
			TextureLength = 1,
			TextureSpeed = 1.6,
			Color = Seq(F.Hot:Lerp(F.Mid, t0), F.Mid:Lerp(F.Deep, t1 * 0.8)),
			Width0 = 2.6 * (1 - t0 * 0.85),
			Width1 = 2.6 * (1 - t1 * 0.85),
			LightEmission = 0.9,
			LightInfluence = 0,
			Transparency = NumberSequence.new(1),
			FaceCamera = true,
			Segments = 4,
			Parent = holder,
		})
		table.insert(beams, beam)
	end
	-- Hoerner (kurze Flammen-Beams nach hinten oben)
	local hornTips: { Attachment } = {}
	for _ = 1, 2 do
		local tip = Make("Attachment", { Parent = holder })
		table.insert(hornTips, tip)
		local beam = Make("Beam", {
			Attachment0 = atts[1],
			Attachment1 = tip,
			Texture = TEX.Fire,
			TextureMode = Enum.TextureMode.Stretch,
			TextureSpeed = 1,
			Color = Seq(F.Hot, F.Deep),
			Width0 = 0.7,
			Width1 = 0.05,
			LightEmission = 0.9,
			LightInfluence = 0,
			Transparency = NumberSequence.new(1),
			FaceCamera = true,
			Parent = holder,
		})
		table.insert(beams, beam)
	end
	-- Flammen entlang des Koerpers
	local bodyEmitters: { ParticleEmitter } = {}
	for i = 1, N, 2 do
		local t = (i - 1) / (N - 1)
		table.insert(bodyEmitters, Effects.Emitter(atts[i], {
			Texture = TEX.Fire,
			Rate = 0,
			Color = FIRE,
			Speed = NumberRange.new(1, 3),
			Lifetime = NumberRange.new(0.25, 0.45),
			Size = NSeq(2 * (1 - t * 0.6), 0),
			Acceleration = Vector3.new(0, 6, 0),
			LightEmission = 0.85,
		}))
	end
	-- Augen (kleine heisse Kerne) + Licht
	local eyes: { Part } = {}
	for _ = 1, 2 do
		table.insert(eyes, Effects.Ball(root.CFrame, 0.32, F.Core, { Transparency = 1 }))
	end
	for _, eye in eyes do
		Effects.Clean(eye, total + 2)
	end
	local light = Make("PointLight", { Color = F.Mid, Range = 30, Brightness = 0, Parent = eyes[1] })

	-- Maul: geschichteter Flammenstrom nach vorne
	local mouth = Make("Attachment", { Parent = holder })
	local flames = {
		Effects.Emitter(mouth, {
			Texture = TEX.Fire,
			Color = Seq(F.Core, F.Hot, F.Mid),
			EmissionDirection = Enum.NormalId.Front,
			Speed = NumberRange.new(48, 62),
			SpreadAngle = Vector2.new(8, 8),
			Lifetime = NumberRange.new(0.18, 0.28),
			Size = NSeq(0.8, 2.5, 3),
			Transparency = NSeq(0, 0.2, 1),
			LightEmission = 1,
			Brightness = 1.6,
		}),
		Effects.Emitter(mouth, {
			Texture = TEX.Fire,
			Color = FIRE,
			EmissionDirection = Enum.NormalId.Front,
			Speed = NumberRange.new(36, 50),
			SpreadAngle = Vector2.new(14, 14),
			Lifetime = NumberRange.new(0.35, 0.55),
			Size = NSeq(1.5, 5.5, 8),
			Transparency = NSeq(0.05, 0.2, 1),
			Drag = 1.2,
			RotSpeed = NumberRange.new(-150, 150),
			LightEmission = 0.85,
		}),
		Effects.Emitter(mouth, {
			Texture = TEX.Smoke,
			Color = Seq(C(90, 66, 54), F.Smoke),
			LightEmission = 0,
			LightInfluence = 0.6,
			EmissionDirection = Enum.NormalId.Front,
			Speed = NumberRange.new(20, 30),
			SpreadAngle = Vector2.new(20, 20),
			Lifetime = NumberRange.new(0.9, 1.4),
			Size = NSeq(3, 10),
			Transparency = NSeq(0.5, 0.7, 1),
			Acceleration = Vector3.new(0, 6, 0),
		}),
		Effects.Emitter(mouth, {
			Texture = TEX.Sparks,
			Color = Seq(F.Hot, F.Mid),
			EmissionDirection = Enum.NormalId.Front,
			Orientation = Enum.ParticleOrientation.VelocityParallel,
			Squash = NSeq(1.5, 0.5),
			Speed = NumberRange.new(50, 75),
			SpreadAngle = Vector2.new(18, 18),
			Lifetime = NumberRange.new(0.3, 0.6),
			Size = NSeq(0.35, 0),
			LightEmission = 1,
		}),
	}
	local rates = { 150, 110, 28, 45 }

	-- Boden: Brandspuren im Feuerkegel (entlang der Startrichtung)
	task.delay(windup, function()
		if not root.Parent then
			return
		end
		local fwd = flat(root.CFrame.LookVector)
		for k = 1, 3 do
			local gp = Effects.Ground(root.Position + fwd * (5 + k * 5.5))
			if root.Position.Y - gp.Y < 8 then
				Effects.GroundMark(gp, 2.5 + k * 0.8, C(26, 18, 14), channel + 1.4, { Transparency = 0.3, FadeIn = 0.25 + k * 0.1 })
			end
		end
	end)

	local lastSound = 0
	local dissolving = false
	local gone = false
	local beamAlpha = 0
	local function setBeamAlpha(alpha: number)
		if math.abs(alpha - beamAlpha) < 0.01 then
			return
		end
		beamAlpha = alpha
		local tr = NumberSequence.new(1 - alpha * 0.85)
		for _, b in beams do
			b.Transparency = tr
		end
	end
	-- Am Ende: alles abschalten; der Halter verschwindet spaeter (Rauch darf ausklingen)
	local function cleanup()
		for _, e in flames do
			e.Enabled = false
		end
		for _, e in bodyEmitters do
			e.Enabled = false
		end
		beamAlpha = 1
		setBeamAlpha(0)
		light.Brightness = 0
		for _, eye in eyes do
			eye:Destroy()
		end
	end
	Effects.Animate(total + 0.5, function(a)
		if not root.Parent then
			-- Zaubernder ist weg (gestorben/verlassen): sofort abschalten
			if not gone then
				gone = true
				cleanup()
			end
			return
		end
		if gone then
			return
		end
		local t = a * (total + 0.5)
		local rootCF = root.CFrame
		local fwd = flat(rootCF.LookVector)
		local base = CFrame.lookAt(rootCF.Position, rootCF.Position + fwd)
		local w = math.clamp(t / windup, 0, 1)
		local blend = Effects.Ease(math.clamp((t - windup) / 0.25, 0, 1), "InOut")
		-- Glieder positionieren
		local positions: { Vector3 } = {}
		for i = 1, N do
			local s = (i - 1) / (N - 1)
			local coil = pathAt(DRAGON_COIL, Effects.Ease(w, "Out") - (i - 1) * LAG)
			local wave = Vector3.new(math.sin(t * 7 - s * 9) * 0.6, math.cos(t * 6 - s * 8) * 0.4, 0) * math.sqrt(s)
			local body = pathAt(DRAGON_BODY, s) + wave
			local localPos = coil:Lerp(body, blend)
			if dissolving then
				localPos += Vector3.new(0, (t - total) * 6 * (0.5 + s), 0)
			end
			positions[i] = base:PointToWorldSpace(localPos)
		end
		for i = 1, N do
			atts[i].WorldPosition = positions[i]
		end
		-- Kopf ausrichten: beim Winden in Bewegungsrichtung, beim Speien nach vorne
		local headPos = positions[1]
		local neckDir = headPos - positions[2]
		local headDir = if neckDir.Magnitude > 0.05 then neckDir.Unit else fwd
		headDir = headDir:Lerp(fwd, blend)
		if headDir.Magnitude < 0.05 then
			headDir = fwd
		end
		local headCF = CFrame.lookAt(headPos, headPos + headDir)
		for k, tip in hornTips do
			tip.WorldPosition = (headCF * CFrame.new(if k == 1 then -0.6 else 0.6, 1, 1.4)).Position
		end
		eyes[1].CFrame = headCF * CFrame.new(-0.45, 0.35, -0.3)
		eyes[2].CFrame = headCF * CFrame.new(0.45, 0.35, -0.3)
		-- Maul leicht nach unten geneigt, damit der Strom Gegner auf Bodenhoehe trifft
		mouth.WorldCFrame = headCF * CFrame.new(0, -0.2, -1) * CFrame.Angles(-0.1 + math.sin(t * 9) * 0.03, 0, 0)
		-- Sichtbarkeit / Raten
		local firing = t >= windup and t < total
		if t >= total and not dissolving then
			dissolving = true
			for _, e in bodyEmitters do
				e.Rate = 0
			end
			for _, idx in { 1, 5, 9 } do
				Effects.FireBurst(positions[idx], nil, 0.5, { Speed = 8 })
			end
			Effects.Sound("Fire", headPos, { Volume = 0.5, Pitch = 0.8 })
		end
		if dissolving then
			setBeamAlpha(math.clamp(1 - (t - total) / 0.45, 0, 1))
		else
			setBeamAlpha(math.clamp(t / 0.15, 0, 1))
		end
		local eyeAlpha = if dissolving then 1 else math.clamp(1 - t / 0.2, 0, 1)
		for _, eye in eyes do
			eye.Transparency = eyeAlpha
		end
		light.Brightness = if dissolving then 0 elseif firing then 5 else 2 * w
		if not dissolving then
			for _, e in bodyEmitters do
				e.Rate = 22 * Effects.Quality
			end
		end
		for i, e in flames do
			e.Rate = if firing then rates[i] * Effects.Quality else 0
		end
		if firing and t - lastSound > 0.35 then
			lastSound = t
			Effects.Sound("Fire", headPos, { Volume = 0.7 })
		end
	end, function()
		if not gone then
			gone = true
			cleanup()
		end
	end)
	if isLocalChar(caster) then
		task.delay(windup, function()
			Effects.Shake(0.45, channel)
		end)
	end
end

return V
