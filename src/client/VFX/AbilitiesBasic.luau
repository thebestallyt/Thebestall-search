-- VFX der Faehigkeiten ohne Cutscene (Gewoehnlich bis Legendaer).
-- Jede Funktion bekommt das Payload vom Server (p) und einen Kontext (ctx).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
local rng = Effects.Random
local NSeq, Seq = Effects.NSeq, Effects.Seq
local player = Players.LocalPlayer

local FIRE = Seq(Color3.fromRGB(255, 245, 170), Color3.fromRGB(255, 150, 40), Color3.fromRGB(220, 50, 20), Color3.fromRGB(60, 20, 20))

local function def(id: string): any
	return Abilities.Get(id)
end

local function look(p: any, root: BasePart): Vector3
	local d: Vector3 = (p.Extra and p.Extra.Dir) or root.CFrame.LookVector
	return Vector3.new(d.X, 0, d.Z).Unit
end

local function isLocalChar(m: Model?): boolean
	return m ~= nil and m == player.Character
end

-- GEWOEHNLICH ------------------------------------------------------------------

function V.EmberPunch(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local d = def("EmberPunch")
	local dir = look(p, root)
	Poser.Sequence(caster, { { P.HeavyWindup, 0.06 }, { P.PunchRight, 0.34 } }, 0.2)
	Effects.Sound("Fire", root.Position)
	local hand = Effects.HandPart(caster, "Right")
	if hand then
		local att = Make("Attachment", { Parent = hand })
		Effects.Stream(att, 0.45, {
			Texture = TEX.Fire,
			Rate = 140,
			Color = FIRE,
			Speed = NumberRange.new(1, 4),
			Lifetime = NumberRange.new(0.2, 0.4),
			Size = NSeq(1.6, 0.2),
			SpreadAngle = Vector2.new(40, 40),
			Acceleration = Vector3.new(0, 8, 0),
		})
		Effects.Clean(att, 1.2)
		Effects.Light(hand, Color3.fromRGB(255, 140, 40), 16, 3, 0.6)
	end
	Effects.Trail(root, Seq(Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 90, 20)), 0.25, 3, d.Timing.Lunge + 0.12)
	task.delay(d.Timing.Lunge * 0.85, function()
		local pos = root.Position + dir * 3.5
		Effects.Explosion(pos, Color3.fromRGB(255, 120, 30), 1.1, { Secondary = Color3.fromRGB(255, 230, 140), Shake = 1.2 })
		Effects.BurstDir(pos, dir, 40, {
			Texture = TEX.Fire,
			Color = FIRE,
			Speed = NumberRange.new(25, 45),
			SpreadAngle = Vector2.new(30, 30),
			Lifetime = NumberRange.new(0.3, 0.55),
			Size = NSeq(2, 4, 0),
			Drag = 4,
		})
		Effects.Ring(CFrame.lookAt(pos, pos + dir), 1, 7, Color3.fromRGB(255, 220, 120), 0.35, 0.8)
		Effects.Ring(CFrame.lookAt(pos + dir * 2, pos + dir * 3), 0.5, 4.5, Color3.fromRGB(255, 120, 30), 0.3, 0.6)
		Effects.Sound("Explosion", pos, { Pitch = 1.3, Volume = 0.6 })
	end)
end

function V.StoneSmash(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local d = def("StoneSmash")
	Poser.Sequence(caster, { { P.ArmsUp, d.Timing.Impact - 0.05 }, { P.Slam, 0.35 } }, 0.25)
	Effects.Sound("Whoosh", root.Position, { Pitch = 0.8 })
	Effects.Burst(root.Position - Vector3.new(0, 2.5, 0), 10, {
		Texture = TEX.Smoke,
		Color = ColorSequence.new(Color3.fromRGB(150, 130, 110)),
		LightEmission = 0,
		LightInfluence = 0.8,
		Speed = NumberRange.new(4, 8),
		Size = NSeq(1.5, 3),
		Transparency = NSeq(0.5, 1),
	})
	task.delay(d.Timing.Impact, function()
		local center = Effects.Ground(root.Position)
		local rock = Color3.fromRGB(80, 66, 58)
		Effects.GroundSpikes(center, 6.5, 10, { Color = rock, MinHeight = 3.5, MaxHeight = 6.5 })
		task.delay(0.08, function()
			Effects.GroundSpikes(center, 11, 15, { Color = rock, MinHeight = 2, MaxHeight = 4.5, Stay = 1 })
		end)
		Effects.Cracks(center, 8, 13, Color3.fromRGB(255, 140, 40), 1.6)
		Effects.Rocks(center, 16, { Spread = 32, MaxUp = 55, Color = rock })
		Effects.GroundRing(center + Vector3.new(0, 0.3, 0), 2, 17, Color3.fromRGB(210, 180, 140), 0.6, 2.5, { Transparency = 0.25 })
		Effects.Burst(center + Vector3.new(0, 1, 0), 26, {
			Texture = TEX.Smoke,
			Color = ColorSequence.new(Color3.fromRGB(160, 140, 120)),
			LightEmission = 0,
			LightInfluence = 0.8,
			Speed = NumberRange.new(12, 22),
			SpreadAngle = Vector2.new(90, 90),
			Lifetime = NumberRange.new(0.6, 1.2),
			Size = NSeq(2.5, 6),
			Transparency = NSeq(0.35, 1),
			Drag = 4,
		})
		Effects.Flash(center + Vector3.new(0, 1, 0), Color3.fromRGB(255, 200, 140), 10, 0.3)
		Effects.Sound("Impact", center)
		Effects.Sound("Rumble", center, { Volume = 0.5, Pitch = 0.8 })
		Effects.ShakeAt(center, 2.2, 70, 0.45)
	end)
end

function V.GaleBurst(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local d = def("GaleBurst")
	local dir = look(p, root)
	Poser.Sequence(caster, { { P.PushBoth, 0.4 } }, 0.2)
	Effects.Sound("Wind", root.Position)
	task.delay(d.Timing.Release, function()
		local origin = root.Position + Vector3.new(0, 0.5, 0)
		local white = Color3.fromRGB(230, 250, 255)
		for i = 0, 3 do
			task.delay(i * 0.05, function()
				local start = origin + dir * (2 + i * 1.5)
				local ring = Effects.Ring(CFrame.lookAt(start, start + dir), 1.5, 6 + i * 1.6, if i % 2 == 0 then white else Color3.fromRGB(150, 225, 255), 0.45, 0.7, { Transparency = 0.25 })
				local anchor = ring.Adornee :: BasePart
				Effects.Tween(anchor, 0.45, { CFrame = anchor.CFrame + dir * 14 })
			end)
		end
		for _ = 1, 16 do
			local right = dir:Cross(Vector3.yAxis)
			local start = origin + right * rng:NextNumber(-3, 3) + Vector3.new(0, rng:NextNumber(-2, 2.5), 0)
			local line = Effects.Part({
				Size = Vector3.new(0.1, 0.1, rng:NextNumber(3, 6)),
				CFrame = CFrame.lookAt(start, start + dir),
				Color = white,
				Transparency = 0.2,
			})
			Effects.Tween(line, rng:NextNumber(0.25, 0.4), { CFrame = line.CFrame + dir * rng:NextNumber(14, 20), Transparency = 1 })
			Effects.Clean(line, 0.45)
		end
		Effects.BurstDir(origin + dir * 2, dir, 30, {
			Texture = TEX.Smoke,
			Color = ColorSequence.new(white),
			LightEmission = 0.4,
			Speed = NumberRange.new(40, 60),
			SpreadAngle = Vector2.new(25, 25),
			Lifetime = NumberRange.new(0.3, 0.5),
			Size = NSeq(1, 4),
			Transparency = NSeq(0.5, 1),
			Drag = 3,
		})
		Effects.BurstDir(origin + dir * 2, dir, 24, {
			Texture = TEX.Sparkle,
			Color = ColorSequence.new(Color3.fromRGB(180, 240, 255)),
			Speed = NumberRange.new(30, 50),
			SpreadAngle = Vector2.new(30, 30),
			Size = NSeq(0.6, 0),
			Drag = 2,
		})
	end)
end

-- UNGEWOEHNLICH ------------------------------------------------------------------

local function shatter(pos: Vector3)
	Effects.Burst(pos, 18, {
		Texture = TEX.Sparkle,
		Color = Seq(Color3.new(1, 1, 1), Color3.fromRGB(130, 210, 255)),
		Speed = NumberRange.new(8, 18),
		Size = NSeq(0.7, 0),
	})
	for _ = 1, 6 do
		local shard = Effects.Part({
			Size = Vector3.new(0.3, 0.3, rng:NextNumber(0.6, 1.2)),
			CFrame = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0),
			Material = Enum.Material.Glass,
			Color = Color3.fromRGB(180, 235, 255),
			Transparency = 0.2,
			Anchored = false,
			CanCollide = true,
			CollisionGroup = "VFX",
		})
		shard.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-14, 14), rng:NextNumber(5, 18), rng:NextNumber(-14, 14))
		Effects.Tween(shard, 0.5, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.4)
		Effects.Clean(shard, 1)
	end
	Effects.Ring(CFrame.new(pos), 0.3, 3, Color3.fromRGB(180, 235, 255), 0.25, 0.4)
	Effects.Sound("Ice", pos, { Volume = 0.5 })
end

function V.FrostShard(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local d = def("FrostShard")
	Poser.Sequence(caster, { { P.CastForward, 0.4 } }, 0.2)
	local handPos = Effects.HandPosition(caster, "Right") or root.Position
	Effects.Burst(handPos, 14, {
		Texture = TEX.Sparkle,
		Color = ColorSequence.new(Color3.fromRGB(170, 230, 255)),
		Speed = NumberRange.new(3, 8),
		Size = NSeq(0.8, 0),
	})
	Effects.Sound("Ice", root.Position, { Pitch = 1.3, Volume = 0.5 })
	task.delay(d.Timing.Release, function()
		local origin: Vector3 = p.Extra.Origin or (root.Position + Vector3.new(0, 1, 0))
		local dirs: { Vector3 } = p.Extra.Dirs or { root.CFrame.LookVector }
		local speed = d.Timing.Speed
		local shards = {}
		for _, dir in dirs do
			local cf = CFrame.lookAt(origin, origin + dir)
			local body = Effects.Part({
				Size = Vector3.new(0.7, 0.7, 3.4),
				CFrame = cf,
				Material = Enum.Material.Glass,
				Color = Color3.fromRGB(170, 230, 255),
				Transparency = 0.1,
				Reflectance = 0.3,
			})
			local core = Effects.Part({ Size = Vector3.new(0.3, 0.3, 2.8), CFrame = cf, Color = Color3.fromRGB(120, 210, 255) })
			Effects.Trail(core, Seq(Color3.new(1, 1, 1), Color3.fromRGB(110, 200, 255)), 0.2, 0.7)
			local att = Make("Attachment", { Parent = core })
			Effects.Emitter(att, {
				Texture = TEX.Sparkle,
				Rate = 50,
				Color = ColorSequence.new(Color3.fromRGB(210, 245, 255)),
				Speed = NumberRange.new(0.5, 2),
				Lifetime = NumberRange.new(0.3, 0.6),
				Size = NSeq(0.4, 0),
			})
			table.insert(shards, { body = body, core = core, pos = origin, dir = dir, traveled = 0, alive = true })
		end
		local characters = Effects.Characters()
		Effects.Animate(d.Range / speed + 0.1, function(_, dt)
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
				if stop or s.traveled >= d.Range then
					s.alive = false
					shatter(s.pos)
					s.body:Destroy()
					s.core:Destroy()
				else
					local cf = CFrame.lookAt(s.pos, s.pos + s.dir) * CFrame.Angles(0, 0, s.traveled * 0.3)
					s.body.CFrame = cf
					s.core.CFrame = cf
				end
			end
		end, function()
			for _, s in shards do
				if s.alive then
					s.body:Destroy()
					s.core:Destroy()
				end
			end
		end)
	end)
end

function V.VoltDash(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local d = def("VoltDash")
	local cyan = Color3.fromRGB(90, 220, 255)
	local yellow = Color3.fromRGB(255, 250, 140)
	local from: Vector3 = p.Extra.From or root.Position
	local to: Vector3 = p.Extra.To or (root.Position + root.CFrame.LookVector * 22)
	Effects.Afterimage(caster, cyan, 0.45, 0.25)
	Effects.Sound("Electric", from)
	Effects.Burst(from, 22, {
		Texture = TEX.Sparks,
		Color = Seq(Color3.new(1, 1, 1), cyan),
		Speed = NumberRange.new(15, 30),
		Size = NSeq(0.5, 0),
		Drag = 4,
	})
	Effects.Light(from, cyan, 25, 6, 0.4)
	if not ctx.Preview then
		Effects.SetCharacterVisible(caster, false)
	end
	local ball = Effects.Ball(CFrame.new(from), 2.2, Color3.new(1, 1, 1))
	local glow = Effects.Ball(CFrame.new(from), 4.5, cyan, { Transparency = 0.5 })
	Effects.Tween(ball, d.Timing.Teleport, { CFrame = CFrame.new(to) }, Enum.EasingStyle.Linear)
	Effects.Tween(glow, d.Timing.Teleport, { CFrame = CFrame.new(to) }, Enum.EasingStyle.Linear)
	task.delay(d.Timing.Teleport, function()
		ball:Destroy()
		glow:Destroy()
		if not ctx.Preview then
			Effects.SetCharacterVisible(caster, true)
		end
		for i = 1, 3 do
			local up = Vector3.new(0, rng:NextNumber(-1, 1.5), 0)
			Effects.Bolt(from + up, to + up, {
				Color = if i == 2 then yellow else cyan,
				Width = 0.3,
				Duration = 0.45,
				Branches = 2,
				Jitter = 2,
			})
		end
		Effects.Burst(to, 26, {
			Texture = TEX.Sparks,
			Color = Seq(Color3.new(1, 1, 1), cyan),
			Speed = NumberRange.new(15, 32),
			Size = NSeq(0.5, 0),
			Drag = 4,
		})
		Effects.Light(to, cyan, 25, 6, 0.45)
		Effects.GroundRing(Effects.Ground(to) + Vector3.new(0, 0.2, 0), 1, 7, cyan, 0.35, 0.7)
		Effects.Sound("Electric", to, { Pitch = 1.4 })
		local g0, g1 = Effects.Ground(from), Effects.Ground(to)
		local len = (g1 - g0).Magnitude
		if len > 1 then
			local mid = (g0 + g1) / 2 + Vector3.new(0, 0.07, 0)
			local scorch = Effects.Part({
				Size = Vector3.new(1.4, 0.05, len),
				CFrame = CFrame.lookAt(mid, g1 + Vector3.new(0, 0.07, 0)),
				Material = Enum.Material.SmoothPlastic,
				Color = Color3.fromRGB(20, 20, 30),
				Transparency = 0.3,
			})
			Effects.Tween(scorch, 1.5, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			Effects.Clean(scorch, 1.6)
		end
		if isLocalChar(caster) then
			Effects.Shake(0.8, 0.2)
		end
	end)
end

-- SELTEN ------------------------------------------------------------------------------

function V.InfernoRing(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local d = def("InfernoRing")
	local orange = Color3.fromRGB(255, 110, 25)
	local yellow = Color3.fromRGB(255, 220, 90)
	Poser.Sequence(caster, { { P.ArmsOut, d.Timing.Charge }, { P.ArmsUp, 0.45 } }, 0.3)
	Effects.Sound("Charge", root.Position, { Pitch = 1.4 })
	-- Feuer wird eingesaugt
	local sphere = Effects.Ball(root.CFrame, 16, orange, { Transparency = 1 })
	Effects.Stream(sphere, d.Timing.Charge, {
		Texture = TEX.Fire,
		Rate = 180,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Speed = NumberRange.new(14, 20),
		Lifetime = NumberRange.new(0.35, 0.5),
		Color = FIRE,
		Size = NSeq(0.6, 1.6, 0.4),
		SpreadAngle = Vector2.new(0, 0),
	})
	Effects.Clean(sphere, d.Timing.Charge + 0.7)
	local groundPos = Effects.Ground(root.Position)
	local glowDisc = Effects.Part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 2, 2),
		CFrame = CFrame.new(groundPos + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = orange,
		Transparency = 0.4,
	})
	Effects.Tween(glowDisc, d.Timing.Charge, { Size = Vector3.new(0.1, 12, 12) })
	Effects.Clean(glowDisc, d.Timing.Charge)
	Effects.Light(root, orange, 22, 5, d.Timing.Charge + 0.2, d.Timing.Charge)

	task.delay(d.Timing.Charge, function()
		local center = root.Position
		local g = Effects.Ground(center)
		Effects.Flash(center, yellow, 16, 0.4, 3)
		Effects.Sound("Fire", center)
		Effects.Sound("Explosion", center, { Volume = 0.7 })
		local count = math.floor(26 * Effects.Quality)
		local anchors = {}
		for _ = 1, count do
			local anchor, att = Effects.Anchor(g)
			Effects.Stream(att, d.Timing.Expand + 0.12, {
				Texture = TEX.Fire,
				Rate = 55,
				Color = FIRE,
				EmissionDirection = Enum.NormalId.Top,
				Speed = NumberRange.new(5, 12),
				SpreadAngle = Vector2.new(18, 18),
				Lifetime = NumberRange.new(0.35, 0.65),
				Size = NSeq(3, 5.5, 0),
				Acceleration = Vector3.new(0, 10, 0),
			})
			Effects.Clean(anchor, d.Timing.Expand + 1)
			table.insert(anchors, anchor)
		end
		Effects.Animate(d.Timing.Expand + 0.12, function(a)
			local r = 1.5 + (d.Range - 1.5) * Effects.Ease(a, "OutCubic")
			for i, anchor in anchors do
				local ang = (i / #anchors) * math.pi * 2
				anchor.CFrame = CFrame.new(g + Vector3.new(math.cos(ang) * r, 0.6, math.sin(ang) * r))
			end
		end)
		Effects.GroundRing(g + Vector3.new(0, 0.25, 0), 1, d.Range + 1, orange, d.Timing.Expand + 0.2, 2.2)
		task.delay(0.06, function()
			Effects.GroundRing(g + Vector3.new(0, 0.3, 0), 1, d.Range - 2, yellow, d.Timing.Expand + 0.2, 1)
		end)
		Effects.Shockwave(g + Vector3.new(0, 0.6, 0), d.Range * 2.4, orange, 0.55)
		Effects.Burst(center, 50, {
			Texture = TEX.Sparks,
			Color = Seq(yellow, orange),
			Speed = NumberRange.new(14, 34),
			Acceleration = Vector3.new(0, 14, 0),
			Lifetime = NumberRange.new(0.6, 1.2),
			Size = NSeq(0.5, 0),
			Drag = 2,
		})
		Effects.Scorch(g, d.Range * 0.8, 2.6)
		Effects.Light(center, orange, 40, 6, 0.8)
		Effects.ShakeAt(center, 2, 80, 0.4)
	end)
end

function V.TidalVortex(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local d = def("TidalVortex")
	local deep = Color3.fromRGB(30, 110, 255)
	local light = Color3.fromRGB(170, 240, 255)
	local center: Vector3 = p.Extra.Center or Effects.Ground(p.Aim)
	Poser.Sequence(caster, { { P.RightUp, 0.25 }, { P.CastForward, 0.45 } }, 0.3)
	Effects.Sound("Water", root.Position)
	task.delay(d.Timing.Spawn, function()
		local function splash(scale: number)
			Effects.Burst(center + Vector3.new(0, 0.5, 0), 40 * scale, {
				Texture = TEX.Sparkle,
				Color = Seq(Color3.new(1, 1, 1), light, deep),
				EmissionDirection = Enum.NormalId.Top,
				SpreadAngle = Vector2.new(50, 50),
				Speed = NumberRange.new(18 * scale, 34 * scale),
				Acceleration = Vector3.new(0, -50, 0),
				Lifetime = NumberRange.new(0.6, 1.1),
				Size = NSeq(0.9, 0.3),
			})
			Effects.GroundRing(center + Vector3.new(0, 0.2, 0), 1, 13 * scale, light, 0.5, 1.5, { Transparency = 0.2 })
			Effects.Sound("Water", center, { Volume = scale })
		end
		splash(1)

		local strands, perStrand = 3, math.floor(20 * math.max(Effects.Quality, 0.5))
		local parts = {}
		for s = 1, strands do
			for i = 1, perStrand do
				local t = i / perStrand
				local part = Effects.Part({
					Size = Vector3.new(0.6, 0.6, 2.6),
					Color = deep:Lerp(light, t),
					Transparency = 0.15 + t * 0.35,
					Material = if i % 3 == 0 then Enum.Material.Glass else Enum.Material.Neon,
				})
				table.insert(parts, { part = part, s = s, i = i })
			end
		end
		local core = Effects.Part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, 3.5, 3.5),
			Material = Enum.Material.Glass,
			Color = deep,
			Transparency = 0.55,
		})
		local mistAnchor, mistAtt = Effects.Anchor(center)
		Effects.Stream(mistAtt, d.Timing.Duration, {
			Texture = TEX.Smoke,
			Rate = 40,
			Color = ColorSequence.new(light),
			LightEmission = 0.3,
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(25, 25),
			Speed = NumberRange.new(10, 18),
			Lifetime = NumberRange.new(0.8, 1.3),
			Size = NSeq(2, 6),
			Transparency = NSeq(0.4, 1),
			RotSpeed = NumberRange.new(-200, 200),
		})
		Effects.Stream(mistAtt, d.Timing.Duration, {
			Texture = TEX.Sparkle,
			Rate = 60,
			Color = ColorSequence.new(Color3.new(1, 1, 1)),
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(40, 40),
			Speed = NumberRange.new(14, 24),
			Lifetime = NumberRange.new(0.5, 1),
			Size = NSeq(0.5, 0),
		})
		Effects.Clean(mistAnchor, d.Timing.Duration + 1.5)
		Effects.Light(mistAnchor, light, 28, 3, d.Timing.Duration, 0.3)
		local foam = Make("CylinderHandleAdornment", {
			Adornee = mistAnchor,
			CFrame = CFrame.Angles(math.rad(90), 0, 0),
			Color3 = Color3.new(1, 1, 1),
			Radius = 10,
			InnerRadius = 9.2,
			Height = 0.15,
			Transparency = 0.4,
			Parent = mistAnchor,
		})
		local duration = d.Timing.Duration
		Effects.Animate(duration, function(a)
			local t = a * duration
			local scale = math.min(math.clamp(t / 0.35, 0, 1), math.clamp((duration - t) / 0.3, 0, 1))
			for _, entry in parts do
				local frac = entry.i / perStrand
				local h = frac * 17 * scale
				local r = (1.6 + h * 0.55) * math.max(scale, 0.05)
				local ang = t * 8 + entry.i * 0.42 + entry.s * (math.pi * 2 / strands)
				local pos = center + Vector3.new(math.cos(ang) * r, h + 0.3, math.sin(ang) * r)
				local tangent = Vector3.new(-math.sin(ang), 0.3, math.cos(ang))
				entry.part.CFrame = CFrame.lookAt(pos, pos + tangent)
			end
			core.Size = Vector3.new(math.max(0.1, 17 * scale), 3.5, 3.5)
			core.CFrame = CFrame.new(center + Vector3.new(0, 8.5 * scale, 0)) * CFrame.Angles(0, t * 4, math.rad(90))
			foam.Radius = 9.5 + math.sin(t * 10) * 0.6
			foam.InnerRadius = foam.Radius - 0.7
		end, function()
			for _, entry in parts do
				entry.part:Destroy()
			end
			core:Destroy()
			splash(1.3)
		end)
	end)
end

-- EPISCH --------------------------------------------------------------------------------

function V.Thunderclap(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local d = def("Thunderclap")
	local purple = Color3.fromRGB(150, 120, 255)
	local ice = Color3.fromRGB(200, 240, 255)
	Poser.Sequence(caster, { { P.RightUp, d.Timing.Strike1 } }, 0.3)
	local hand = Effects.HandPart(caster, "Right")
	if hand then
		local att = Make("Attachment", { Parent = hand })
		Effects.Stream(att, d.Timing.Strike1, {
			Texture = TEX.Sparks,
			Rate = 60,
			Color = Seq(Color3.new(1, 1, 1), purple),
			Speed = NumberRange.new(3, 9),
			Size = NSeq(0.4, 0),
		})
		Effects.Clean(att, d.Timing.Strike1 + 1)
	end
	local strikes: { Vector3 } = p.Extra.Strikes or { Effects.Ground(p.Aim) }
	local center = strikes[1]
	local cloudPos = center + Vector3.new(0, 38, 0)
	local cloud = Effects.Part({ Size = Vector3.new(28, 3, 28), CFrame = CFrame.new(cloudPos), Transparency = 1 })
	Effects.Stream(cloud, 1.7, {
		Texture = TEX.Smoke,
		Rate = 90,
		Shape = Enum.ParticleEmitterShape.Box,
		Color = Seq(Color3.fromRGB(70, 60, 100), Color3.fromRGB(30, 26, 50)),
		LightEmission = 0,
		LightInfluence = 0.2,
		Speed = NumberRange.new(0, 1.5),
		Lifetime = NumberRange.new(1.2, 2),
		Size = NSeq(8, 14),
		Transparency = NSeq(0.3, 0.1, 1),
		RotSpeed = NumberRange.new(-30, 30),
	})
	Effects.Clean(cloud, 4)
	local flicker = Make("PointLight", { Color = purple, Range = 50, Brightness = 0, Parent = cloud })
	task.spawn(function()
		for _ = 1, 18 do
			flicker.Brightness = if rng:NextNumber() > 0.6 then rng:NextNumber(2, 6) else 0
			task.wait(0.08)
		end
		flicker.Brightness = 0
	end)
	Effects.Sound("Rumble", center, { Volume = 0.6, Pitch = 0.7 })
	if Effects.Near(center, 90) then
		Effects.ColorGrade({ Brightness = -0.08, Contrast = 0.15, TintColor = Color3.fromRGB(205, 200, 255) }, 0.3, 1.2, 0.6)
	end
	-- Warnkreise
	for i, pos in strikes do
		local t = d.Timing["Strike" .. i] or 0.6
		Effects.GroundRing(pos + Vector3.new(0, 0.2, 0), 7.5, 1, purple, t, 0.4, { Transparency = 0.3, Ease = "In" })
	end
	for i, pos in strikes do
		task.delay(d.Timing["Strike" .. i] or 0.6, function()
			local top = cloudPos + Vector3.new(rng:NextNumber(-5, 5), 0, rng:NextNumber(-5, 5))
			Effects.Bolt(top, pos, { Color = purple, Width = 0.9, Duration = 0.4, Branches = 4, Jitter = 4 })
			Effects.Bolt(top, pos, { Color = ice, Width = 0.4, Duration = 0.3, Jitter = 3 })
			Effects.Explosion(pos + Vector3.new(0, 0.5, 0), Color3.fromRGB(140, 200, 255), 1.15, { Secondary = Color3.new(1, 1, 1), Shake = 1.8 })
			Effects.Cracks(pos, 6, 7, ice, 0.9)
			Effects.Scorch(pos, 4, 2)
			Effects.Light(pos, Color3.new(1, 1, 1), 60, 10, 0.35)
			if Effects.Near(pos, 70) then
				Effects.ScreenFlash(Color3.new(1, 1, 1), 0.18, 0.6)
			end
			Effects.Sound("Thunder", pos)
		end)
	end
end

function V.ShadowStep(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local d = def("ShadowStep")
	local purple = Color3.fromRGB(150, 50, 255)
	local dark = Color3.fromRGB(25, 5, 45)
	local origin = root.Position
	local dest: CFrame = p.Extra.Dest or (root.CFrame * CFrame.new(0, 0, -15))
	local function smoke(pos: Vector3)
		Effects.Burst(pos, 30, {
			Texture = TEX.Smoke,
			Color = Seq(Color3.fromRGB(80, 20, 140), dark),
			LightEmission = 0.2,
			Speed = NumberRange.new(4, 12),
			Lifetime = NumberRange.new(0.5, 1),
			Size = NSeq(2, 5),
			Transparency = NSeq(0.1, 1),
			Drag = 3,
		})
		Effects.Burst(pos, 16, {
			Texture = TEX.Sparkle,
			Color = ColorSequence.new(purple),
			Speed = NumberRange.new(6, 14),
			Size = NSeq(0.6, 0),
		})
	end
	Effects.Afterimage(caster, Color3.fromRGB(60, 10, 100), 0.6, 0.15)
	smoke(origin)
	Effects.Ring(CFrame.new(origin) * CFrame.Angles(math.rad(90), 0, 0), 6, 0.3, purple, 0.22, 0.6, { Ease = "In" })
	Effects.Sound("Shadow", origin)
	if not ctx.Preview then
		Effects.SetCharacterVisible(caster, false)
	end
	task.delay(d.Timing.Teleport, function()
		if not ctx.Preview then
			Effects.SetCharacterVisible(caster, true)
		end
		smoke(dest.Position)
		Effects.Ring(CFrame.new(dest.Position) * CFrame.Angles(math.rad(90), 0, 0), 0.5, 6, purple, 0.3, 0.6)
		Effects.Light(dest.Position, purple, 22, 4, 0.5)
		Poser.Sequence(caster, { { P.Slash, 0.35 } }, 0.25)
	end)
	task.delay(d.Timing.Slash, function()
		local hitPos = dest.Position + dest.LookVector * 2.5 + Vector3.new(0, 0.5, 0)
		local right, up = dest.RightVector, dest.UpVector
		Effects.Line(CFrame.lookAt(hitPos, hitPos + right + up), 11, purple, 0.5, 0.3)
		task.delay(0.07, function()
			Effects.Line(CFrame.lookAt(hitPos, hitPos + right - up), 11, purple, 0.5, 0.3)
			Effects.Sound("Slash", hitPos, { Pitch = 1.1 })
		end)
		Effects.Slash(CFrame.lookAt(hitPos, hitPos + dest.LookVector) * CFrame.Angles(0, 0, math.rad(45)), 4, purple, 0.35, 160, 0.5)
		Effects.Flash(hitPos, purple, 7, 0.25)
		Effects.Burst(hitPos, 24, {
			Texture = TEX.Sparks,
			Color = Seq(Color3.new(1, 1, 1), purple),
			Speed = NumberRange.new(14, 30),
			Size = NSeq(0.5, 0),
			Drag = 4,
		})
		Effects.Sound("Slash", hitPos)
		local target = p.Extra.Target
		if isLocalChar(target) then
			Effects.Vignette(Color3.fromRGB(70, 0, 120), 0.6, 0.45)
			Effects.Shake(1.4, 0.3)
		end
	end)
end

-- LEGENDAER -----------------------------------------------------------------------------

function V.MeteorStrike(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local d = def("MeteorStrike")
	local orange = Color3.fromRGB(255, 110, 30)
	local red = Color3.fromRGB(255, 40, 10)
	local center: Vector3 = p.Extra.Center or Effects.Ground(p.Aim)
	local start: Vector3 = p.Extra.Start or (center + Vector3.new(-40, 130, -40))
	local radius = d.Timing.Radius
	local fall = d.Timing.Fall
	Poser.Sequence(caster, { { P.RightUp, 0.7 } }, 0.3)
	Effects.Sound("Rumble", center, { Volume = 0.8 })

	-- Warnzone
	local zone = Effects.Part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, radius * 2, radius * 2),
		CFrame = CFrame.new(center + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = red,
		Transparency = 0.85,
	})
	local zoneAnchor = Effects.Anchor(center + Vector3.new(0, 0.15, 0), fall + 0.2)
	local outline = Make("CylinderHandleAdornment", {
		Adornee = zoneAnchor,
		CFrame = CFrame.Angles(math.rad(90), 0, 0),
		Color3 = red,
		Radius = radius,
		InnerRadius = radius - 0.5,
		Height = 0.12,
		Transparency = 0.1,
		Parent = zoneAnchor,
	})
	local inner = Make("CylinderHandleAdornment", {
		Adornee = zoneAnchor,
		CFrame = CFrame.Angles(math.rad(90), 0, 0),
		Color3 = orange,
		Radius = 0.5,
		InnerRadius = 0,
		Height = 0.12,
		Transparency = 0.5,
		Parent = zoneAnchor,
	})
	local _ = outline

	-- Meteor
	local rock = Effects.Ball(CFrame.new(start), 9, Color3.fromRGB(255, 90, 30), { Material = Enum.Material.CrackedLava })
	local aura = Effects.Ball(CFrame.new(start), 13, orange, { Transparency = 0.55 })
	local att = Make("Attachment", { Parent = rock })
	Effects.Emitter(att, {
		Texture = TEX.Fire,
		Rate = 220 * Effects.Quality,
		Color = FIRE,
		Speed = NumberRange.new(2, 6),
		Lifetime = NumberRange.new(0.4, 0.7),
		Size = NSeq(5, 9, 2),
	})
	Effects.Emitter(att, {
		Texture = TEX.Smoke,
		Rate = 60 * Effects.Quality,
		Color = Seq(Color3.fromRGB(90, 60, 50), Color3.fromRGB(30, 26, 30)),
		LightEmission = 0,
		LightInfluence = 0.4,
		Speed = NumberRange.new(1, 3),
		Lifetime = NumberRange.new(1.5, 2.5),
		Size = NSeq(6, 12),
		Transparency = NSeq(0.2, 1),
	})
	Effects.Emitter(att, {
		Texture = TEX.Sparks,
		Rate = 60,
		Color = Seq(Color3.fromRGB(255, 230, 150), orange),
		Speed = NumberRange.new(6, 14),
		Size = NSeq(0.6, 0),
	})
	Effects.Trail(rock, Seq(Color3.fromRGB(255, 220, 120), orange, red), 0.5, 9)
	Make("PointLight", { Color = orange, Range = 55, Brightness = 4, Parent = rock })

	Effects.Animate(fall, function(a)
		local e = a ^ 1.7
		local pos = start:Lerp(center, e)
		rock.CFrame = CFrame.new(pos) * CFrame.Angles(a * 8, a * 5, 0)
		aura.CFrame = rock.CFrame
		zone.Transparency = 0.85 - 0.25 * math.abs(math.sin(a * 22))
		inner.Radius = math.max(0.5, radius * a)
	end, function()
		rock:Destroy()
		aura:Destroy()
		zone:Destroy()
		-- EINSCHLAG
		Effects.Flash(center + Vector3.new(0, 2, 0), Color3.fromRGB(255, 245, 210), 36, 0.45, 6)
		local fireball = Effects.Ball(CFrame.new(center + Vector3.new(0, 2, 0)), 8, orange, {
			Material = Enum.Material.CrackedLava,
			Transparency = 0.05,
		})
		Effects.Tween(fireball, 0.65, { Size = Vector3.new(28, 28, 28), Transparency = 1 }, Enum.EasingStyle.Quart)
		Effects.Clean(fireball, 0.7)
		Effects.GroundRing(center + Vector3.new(0, 0.3, 0), 2, radius * 2, orange, 0.65, 3)
		task.delay(0.05, function()
			Effects.GroundRing(center + Vector3.new(0, 0.4, 0), 2, radius * 1.3, Color3.new(1, 1, 1), 0.4, 1.2)
		end)
		Effects.Ring(CFrame.new(center + Vector3.new(0, 4, 0)), 2, radius * 1.2, orange, 0.5, 1.5, { Transparency = 0.3 })
		Effects.Shockwave(center + Vector3.new(0, 1, 0), radius * 4, orange, 0.6)
		Effects.Burst(center + Vector3.new(0, 1, 0), 80, {
			Texture = TEX.Fire,
			Color = FIRE,
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(70, 70),
			Speed = NumberRange.new(30, 60),
			Lifetime = NumberRange.new(0.5, 0.9),
			Size = NSeq(4, 8, 1),
			Drag = 3,
		})
		Effects.Burst(center + Vector3.new(0, 2, 0), 30, {
			Texture = TEX.Smoke,
			Color = Seq(Color3.fromRGB(90, 70, 60), Color3.fromRGB(30, 26, 30)),
			LightEmission = 0,
			LightInfluence = 0.5,
			Speed = NumberRange.new(10, 22),
			Lifetime = NumberRange.new(1.8, 3),
			Size = NSeq(8, 18),
			Transparency = NSeq(0.2, 1),
			Drag = 2.5,
			Acceleration = Vector3.new(0, 4, 0),
		})
		Effects.Burst(center + Vector3.new(0, 1, 0), 60, {
			Texture = TEX.Sparks,
			Color = Seq(Color3.fromRGB(255, 240, 180), orange),
			Speed = NumberRange.new(40, 80),
			Lifetime = NumberRange.new(0.6, 1.2),
			Acceleration = Vector3.new(0, -40, 0),
			Size = NSeq(0.8, 0),
			Drag = 1.5,
		})
		Effects.Rocks(center, 22, { Material = Enum.Material.Basalt, Color = Color3.fromRGB(45, 35, 35), Spread = 45, MaxUp = 70, MaxSize = 2.2 })
		Effects.GroundSpikes(center, radius * 0.6, 14, { Color = Color3.fromRGB(45, 35, 35), Material = Enum.Material.Basalt, Stay = 2.5, MinHeight = 3, MaxHeight = 7 })
		local lava = Effects.Part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.12, 14, 14),
			CFrame = CFrame.new(center + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(255, 100, 20),
			Transparency = 0.1,
		})
		Effects.Tween(lava, 3.5, { Transparency = 1, Size = Vector3.new(0.12, 9, 9) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Effects.Clean(lava, 3.6)
		Effects.Cracks(center, 10, radius, orange, 3)
		Effects.Scorch(center, radius * 0.9, 4.5)
		Effects.Light(center + Vector3.new(0, 4, 0), orange, 60, 8, 1.4)
		Effects.ShakeAt(center, 3.5, 150, 0.8)
		if Effects.Near(center, 80) then
			Effects.ScreenFlash(Color3.fromRGB(255, 200, 140), 0.35, 0.45)
		end
		Effects.Sound("BigExplosion", center)
		Effects.Sound("Explosion", center, { Volume = 0.8 })
	end)
end

function V.DragonBreath(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local d = def("DragonBreath")
	local windup, channel = d.Timing.Windup, d.Timing.Channel
	local orange = Color3.fromRGB(255, 130, 30)
	local total = windup + channel
	Poser.Sequence(caster, { { P.PushBoth, total } }, 0.3)

	-- Geisterdrache aus Neon-Teilen (relativ zum Wurzelteil)
	local spec = {
		{ name = "Skull", size = Vector3.new(2.8, 2.1, 3.4), off = CFrame.new(0, 2, -4.3) },
		{ name = "Upper", size = Vector3.new(2.2, 0.8, 3.2), off = CFrame.new(0, 2.25, -6.6) },
		{ name = "Jaw", size = Vector3.new(2, 0.55, 3), off = CFrame.new(0, 1.35, -6.3) },
		{ name = "HornL", size = Vector3.new(0.4, 0.4, 3), off = CFrame.new(-1, 3.3, -3.2) * CFrame.Angles(math.rad(35), math.rad(-15), 0) },
		{ name = "HornR", size = Vector3.new(0.4, 0.4, 3), off = CFrame.new(1, 3.3, -3.2) * CFrame.Angles(math.rad(35), math.rad(15), 0) },
		{ name = "Fin", size = Vector3.new(0.25, 1.4, 2.4), off = CFrame.new(0, 3.3, -4) * CFrame.Angles(math.rad(-20), 0, 0) },
		{ name = "Neck", size = Vector3.new(2, 1.8, 2.6), off = CFrame.new(0, 1.8, -2.2) * CFrame.Angles(math.rad(-10), 0, 0) },
	}
	local parts = {}
	for _, s in spec do
		local part = Effects.Part({ Size = s.size, Color = orange, Transparency = 1 })
		Effects.Tween(part, windup, { Transparency = 0.35 })
		table.insert(parts, { part = part, off = s.off, name = s.name })
	end
	for _, side in { -1, 1 } do
		local eye = Effects.Part({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.55, 0.55, 0.55), Color = Color3.fromRGB(255, 250, 160), Transparency = 1 })
		Effects.Tween(eye, windup, { Transparency = 0 })
		table.insert(parts, { part = eye, off = CFrame.new(side * 0.8, 2.5, -5.4), name = "Eye" })
	end
	local mouth, mouthAtt = Effects.Anchor(root.Position)
	local mouthOff = CFrame.new(0, 1.7, -7.6)
	Make("PointLight", { Color = orange, Range = 34, Brightness = 4, Parent = mouth })
	Effects.Sound("Charge", root.Position, { Pitch = 0.9 })

	local flames = {
		Effects.Emitter(mouthAtt, {
			Texture = TEX.Fire,
			Color = FIRE,
			EmissionDirection = Enum.NormalId.Front,
			Speed = NumberRange.new(50, 70),
			SpreadAngle = Vector2.new(12, 12),
			Lifetime = NumberRange.new(0.35, 0.5),
			Size = NSeq(1.5, 5, 8),
			Transparency = NSeq(0, 0.15, 1),
			Drag = 1.5,
		}),
		Effects.Emitter(mouthAtt, {
			Texture = TEX.Fire,
			Color = Seq(Color3.fromRGB(255, 170, 60), Color3.fromRGB(220, 40, 20)),
			EmissionDirection = Enum.NormalId.Front,
			Speed = NumberRange.new(35, 50),
			SpreadAngle = Vector2.new(22, 22),
			Lifetime = NumberRange.new(0.45, 0.65),
			Size = NSeq(3, 9),
			Transparency = NSeq(0.2, 1),
			Drag = 1.2,
		}),
		Effects.Emitter(mouthAtt, {
			Texture = TEX.Smoke,
			Color = Seq(Color3.fromRGB(80, 50, 40), Color3.fromRGB(30, 25, 25)),
			LightEmission = 0,
			LightInfluence = 0.5,
			EmissionDirection = Enum.NormalId.Front,
			Speed = NumberRange.new(25, 35),
			SpreadAngle = Vector2.new(25, 25),
			Lifetime = NumberRange.new(0.8, 1.2),
			Size = NSeq(4, 10),
			Transparency = NSeq(0.4, 1),
		}),
		Effects.Emitter(mouthAtt, {
			Texture = TEX.Sparks,
			Color = Seq(Color3.fromRGB(255, 240, 170), orange),
			EmissionDirection = Enum.NormalId.Front,
			Speed = NumberRange.new(60, 80),
			SpreadAngle = Vector2.new(18, 18),
			Size = NSeq(0.5, 0),
		}),
	}
	local rates = { 300, 120, 40, 60 }

	local start = os.clock()
	local lastSound = 0
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if not root.Parent or t > total + 0.5 then
			conn:Disconnect()
			for _, entry in parts do
				entry.part:Destroy()
			end
			mouth:Destroy()
			return
		end
		local base = root.CFrame
		local open = math.clamp(t / windup, 0, 1) * 30
		for _, entry in parts do
			local off = entry.off
			if entry.name == "Jaw" then
				off = CFrame.new(0, 1.6, -4.9) * CFrame.Angles(math.rad(open), 0, 0) * CFrame.new(0, -0.25, -1.4)
			end
			entry.part.CFrame = base * off
		end
		mouth.CFrame = base * mouthOff
		local firing = t >= windup and t < total
		for i, e in flames do
			e.Rate = if firing then rates[i] * Effects.Quality else 0
		end
		if firing and t - lastSound > 0.35 then
			lastSound = t
			Effects.Sound("Fire", mouth.Position, { Volume = 0.7 })
		end
	end)

	task.delay(total, function()
		for _, entry in parts do
			Effects.Tween(entry.part, 0.4, { Transparency = 1, Size = entry.part.Size * 1.4 })
		end
		Effects.Burst(mouth.Position, 20, {
			Texture = TEX.Smoke,
			Color = ColorSequence.new(Color3.fromRGB(70, 50, 50)),
			LightEmission = 0,
			Speed = NumberRange.new(4, 10),
			Size = NSeq(3, 7),
			Transparency = NSeq(0.3, 1),
		})
	end)
	if isLocalChar(caster) then
		task.delay(windup, function()
			Effects.Shake(0.5, channel)
		end)
	end
end

return V
