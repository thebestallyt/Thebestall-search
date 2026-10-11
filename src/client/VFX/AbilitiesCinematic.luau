-- VFX + Kino-Cutscenes der Mythischen, Goettlichen und Exklusiven Faehigkeiten.
-- Alle Spieler sehen die Welt-Effekte. Beteiligte (Zaubernder + Ziele) bekommen zusaetzlich die Kinokamera.

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

local WHITE = Color3.new(1, 1, 1)

-- Hilfsfunktionen -----------------------------------------------------------------

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude < 1e-3 then Vector3.new(0, 0, -1) else f.Unit
end

local function rotateY(v: Vector3, angle: number): Vector3
	return CFrame.Angles(0, angle, 0):VectorToWorldSpace(v)
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
	local opts = {
		Title = string.upper(def.Name),
		Subtitle = "✦ " .. rarity.Name .. " ABILITY ✦",
		Color = rarity.Color,
		Gradient = rarity.Gradient,
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

local function headPart(character: Model?): BasePart?
	return Effects.GetPart(character, "Head")
end

-- Lichtstrahlen, die aus einem Punkt schiessen
local function lightRays(origin: Vector3, count: number, length: number, duration: number, colorFn: (number) -> Color3)
	for i = 1, count do
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 1), rng:NextNumber(-1, 1)).Unit
		local ray = Effects.Part({
			Size = Vector3.new(rng:NextNumber(0.3, 0.8), rng:NextNumber(0.3, 0.8), 0.1),
			CFrame = CFrame.lookAt(origin, origin + dir),
			Color = colorFn(i),
			Transparency = 0.1,
		})
		local len = length * rng:NextNumber(0.6, 1.1)
		Effects.Animate(duration, function(a)
			local e = Effects.Ease(a, "OutCubic")
			ray.Size = Vector3.new(ray.Size.X, ray.Size.Y, math.max(0.1, len * e))
			ray.CFrame = CFrame.lookAt(origin, origin + dir) * CFrame.new(0, 0, -len * e / 2)
			ray.Transparency = 0.1 + 0.9 * a ^ 1.5
		end, function()
			ray:Destroy()
		end)
	end
end

-- Gefuellte, leuchtende Scheibe auf dem Boden
local function glowDisc(position: Vector3, radius: number, color: Color3, transparency: number): Part
	return Effects.Part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, radius * 2, radius * 2),
		CFrame = CFrame.new(position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Transparency = transparency,
	})
end

local function staticRing(adornee: BasePart, rot: CFrame, radius: number, width: number, color: Color3, transparency: number): CylinderHandleAdornment
	return Make("CylinderHandleAdornment", {
		Adornee = adornee,
		CFrame = rot,
		Color3 = color,
		Radius = radius,
		InnerRadius = math.max(0, radius - width),
		Height = 0.15,
		Transparency = transparency,
		Parent = adornee,
	})
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

-- =============================================================================
-- CELESTIAL JUDGMENT (Mythisch): Ein gigantisches Lichtschwert faellt vom Himmel
-- =============================================================================

function C.CelestialJudgment(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local def = Abilities.Get("CelestialJudgment") :: any
	local T = def.Timing
	local R = T.Radius
	local gold = Color3.fromRGB(255, 205, 90)
	local paleGold = Color3.fromRGB(255, 245, 210)
	local center: Vector3 = p.Extra.Center or Effects.Ground(p.Aim)
	local rootCF = root.CFrame
	local toCaster = flat(rootCF.Position - center)
	local side = rotateY(toCaster, math.rad(40))
	local bladeLen = 44
	local swordTop = center + Vector3.new(0, 78, 0)
	local swordEnd = center + Vector3.new(0, bladeLen - 9, 0)
	local swordPos = swordTop

	-- Kamera --------------------------------------------------------------
	local token = beginCutscene(ctx, def)
	if token then
		local headY = Vector3.new(0, 1.5, 0)
		Cutscene.Move(
			CFrame.lookAt((rootCF * CFrame.new(3.5, 0.2, -8.5)).Position, rootCF.Position + headY),
			CFrame.lookAt((rootCF * CFrame.new(2.4, 1, -6)).Position, rootCF.Position + headY + Vector3.new(0, 1, 0)),
			T.Form,
			"InOut",
			60
		)
		at(token, T.Form, function()
			Cutscene.Shot(function(t)
				local ang = t * 0.18
				local pos = center + rotateY(side, ang) * 24 + Vector3.new(0, 2.5, 0)
				return CFrame.lookAt(pos, swordPos - Vector3.new(0, 18, 0))
			end, 62, 0.3)
		end)
		at(token, T.Descend, function()
			local side2 = rotateY(side, math.rad(-70))
			Cutscene.Shot(function()
				local pos = center + side2 * 40 + Vector3.new(0, 12, 0)
				return CFrame.lookAt(pos, swordPos - Vector3.new(0, bladeLen * 0.8, 0))
			end)
			Cutscene.FOV(52, T.Impact - T.Descend)
		end)
		at(token, T.Impact, function()
			Cutscene.Move(
				CFrame.lookAt(center + side * 46 + Vector3.new(0, 20, 0), center),
				CFrame.lookAt(center + side * 56 + Vector3.new(0, 26, 0), center),
				def.CutsceneDuration - T.Impact,
				"Out",
				78
			)
		end)
	end

	-- Welt-Effekte -----------------------------------------------------------
	Poser.Sequence(caster, { { P.RightUp, T.Impact } }, 0.4)
	Effects.Sound("Holy", root.Position)
	if Effects.Near(center, 160) then
		Effects.ColorGrade({ Brightness = 0.04, Contrast = 0.18, Saturation = 0.1, TintColor = Color3.fromRGB(255, 240, 205) }, 0.4, T.Impact - 0.2, 0.8)
	end
	-- Lichtsaeule um den Zaubernden
	local pillar = Effects.Part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(60, 5, 5),
		CFrame = CFrame.new(rootCF.Position + Vector3.new(0, 26, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = gold,
		Transparency = 1,
	})
	Effects.Tween(pillar, 0.3, { Transparency = 0.55 })
	Effects.Tween(pillar, 0.6, { Transparency = 1, Size = Vector3.new(60, 0.5, 0.5) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, T.Form)
	Effects.Clean(pillar, T.Form + 0.7)
	Effects.Stream(root, T.Form, {
		Texture = TEX.Sparkle,
		Rate = 60,
		Color = Seq(WHITE, gold),
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(4, 10),
		Lifetime = NumberRange.new(0.8, 1.4),
		Size = NSeq(0.7, 0),
		SpreadAngle = Vector2.new(60, 60),
	})

	-- Runenkreis am Zielort
	local runeAnchor = Effects.Anchor(center + Vector3.new(0, 0.15, 0))
	local flatRot = CFrame.Angles(math.rad(90), 0, 0)
	local rings = {
		staticRing(runeAnchor, flatRot, 0.1, 0.5, gold, 0.1),
		staticRing(runeAnchor, flatRot, 0.1, 0.35, paleGold, 0.2),
		staticRing(runeAnchor, flatRot, 0.1, 0.7, gold, 0.05),
	}
	local ringTargets = { R * 0.35, R * 0.7, R }
	local disc = glowDisc(center, R * 0.35, gold, 1)
	Effects.Tween(disc, 0.5, { Transparency = 0.7 })
	local bars = {}
	for i = 1, 12 do
		local bar = Effects.Part({ Size = Vector3.new(0.3, 0.12, R * 0.3), Color = gold, Transparency = 0.2 })
		table.insert(bars, { part = bar, i = i })
	end
	local runeLife = T.Impact + 0.4
	Effects.Animate(runeLife, function(a)
		local t = a * runeLife
		for i, ring in rings do
			local grow = math.clamp((t - 0.15 - i * 0.18) / 0.45, 0, 1)
			local r = math.max(0.1, ringTargets[i] * Effects.Ease(grow, "OutBack"))
			ring.Radius = r
			ring.InnerRadius = math.max(0, r - (if i == 3 then 0.7 else 0.4))
		end
		local barGrow = math.clamp((t - 0.6) / 0.4, 0, 1)
		for _, entry in bars do
			local ang = entry.i / 12 * math.pi * 2 + t * 0.6
			local mid = center + Vector3.new(math.cos(ang) * R * 0.53, 0.16, math.sin(ang) * R * 0.53)
			entry.part.Size = Vector3.new(0.3, 0.12, math.max(0.1, R * 0.3 * barGrow))
			entry.part.CFrame = CFrame.lookAt(mid, Vector3.new(center.X, mid.Y, center.Z))
		end
	end, function()
		runeAnchor:Destroy()
		for _, entry in bars do
			entry.part:Destroy()
		end
		Effects.Tween(disc, 0.5, { Transparency = 1 })
		Effects.Clean(disc, 0.6)
	end)

	-- Lichtschaechte vom Himmel
	for i = 1, 6 do
		task.delay(0.3 + i * 0.08, function()
			local ang = rng:NextNumber(0, math.pi * 2)
			local pos = center + Vector3.new(math.cos(ang), 0, math.sin(ang)) * rng:NextNumber(R * 0.4, R * 1.1)
			local shaft = Effects.Part({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(140, rng:NextNumber(1.5, 3.5), rng:NextNumber(1.5, 3.5)),
				CFrame = CFrame.new(pos + Vector3.new(0, 70, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Color = paleGold,
				Transparency = 1,
			})
			Effects.Tween(shaft, 0.5, { Transparency = 0.78 })
			Effects.Tween(shaft, 0.5, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, T.Impact - 0.3 - i * 0.08)
			Effects.Clean(shaft, T.Impact + 0.6)
		end)
	end

	-- Das Schwert -------------------------------------------------------------
	task.delay(T.Form, function()
		local spec = {
			{ size = Vector3.new(1.2, bladeLen, 6), off = CFrame.new(0, -bladeLen / 2, 0), color = Color3.fromRGB(255, 252, 235), tr = 0 },
			{ size = Vector3.new(1.8, bladeLen + 2, 7.6), off = CFrame.new(0, -bladeLen / 2 - 1, 0), color = gold, tr = 0.6 },
			{ size = Vector3.new(1.25, 4.24, 4.24), off = CFrame.new(0, -bladeLen, 0) * CFrame.Angles(math.rad(45), 0, 0), color = Color3.fromRGB(255, 252, 235), tr = 0 },
			{ size = Vector3.new(1.3, bladeLen * 0.8, 0.8), off = CFrame.new(0, -bladeLen * 0.42, 0), color = Color3.fromRGB(255, 190, 70), tr = 0 },
			{ size = Vector3.new(2.4, 2.4, 19), off = CFrame.new(0, 0, 0), color = gold, tr = 0 },
			{ size = Vector3.new(1.7, 9, 1.7), off = CFrame.new(0, 5.6, 0), color = Color3.fromRGB(140, 90, 30), tr = 0, mat = Enum.Material.Metal },
			{ size = Vector3.new(3, 3, 3), off = CFrame.new(0, 11, 0), color = gold, tr = 0, ball = true },
			{ size = Vector3.new(3.2, 3.2, 3.2), off = CFrame.new(0, 0, 9.6), color = gold, tr = 0, ball = true },
			{ size = Vector3.new(3.2, 3.2, 3.2), off = CFrame.new(0, 0, -9.6), color = gold, tr = 0, ball = true },
		}
		local sword = {}
		local swordCF = function(): CFrame
			return CFrame.new(swordPos) * CFrame.Angles(0, math.atan2(-toCaster.X, -toCaster.Z), 0)
		end
		for _, s in spec do
			local part = Effects.Part({
				Size = s.size,
				Color = s.color,
				Transparency = 1,
				Material = s.mat or Enum.Material.Neon,
				CastShadow = true,
			})
			if s.ball then
				part.Shape = Enum.PartType.Ball
				part.Size = s.size
			end
			part.CFrame = swordCF() * s.off
			Effects.Tween(part, 0.7, { Transparency = s.tr }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, rng:NextNumber(0, 0.25))
			table.insert(sword, { part = part, off = s.off, tr = s.tr })
		end
		local blade = sword[1].part
		local haloAnchor = Effects.Anchor(swordPos)
		local halo = staticRing(haloAnchor, CFrame.new(), 13, 0.8, gold, 1)
		Effects.Tween(halo, 0.6, { Transparency = 0.3 })
		local glowLight = Make("PointLight", { Color = gold, Range = 60, Brightness = 0, Parent = blade })
		Effects.Tween(glowLight, 0.7, { Brightness = 6 })
		-- Lichtpartikel sammeln sich
		local gather = Effects.Ball(CFrame.new(swordPos - Vector3.new(0, bladeLen / 2, 0)), 46, gold, { Transparency = 1 })
		Effects.Stream(gather, 0.9, {
			Texture = TEX.Sparkle,
			Rate = 160,
			Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
			Speed = NumberRange.new(30, 40),
			Lifetime = NumberRange.new(0.5, 0.7),
			Color = Seq(WHITE, gold),
			Size = NSeq(1.2, 0.2),
			SpreadAngle = Vector2.new(0, 0),
		})
		Effects.Clean(gather, 1.8)
		Effects.Sound("Holy", swordPos, { Pitch = 0.5, MaxDistance = 600 })

		local descendStart = T.Descend - T.Form
		local impactAt = T.Impact - T.Form
		local trailOn = false
		Effects.Animate(impactAt, function(a, _)
			local t = a * impactAt
			if t < descendStart then
				swordPos = swordTop + Vector3.new(0, math.sin(t * 3) * 0.8, 0)
			else
				local k = math.clamp((t - descendStart) / (impactAt - descendStart), 0, 1)
				swordPos = swordTop:Lerp(swordEnd, k ^ 2.4)
				if not trailOn then
					trailOn = true
					Effects.Trail(blade, Seq(WHITE, gold), 0.35, 6)
					Effects.Sound("Whoosh", center, { Pitch = 0.45, Volume = 1, MaxDistance = 600 })
				end
			end
			local cf = swordCF()
			for _, entry in sword do
				entry.part.CFrame = cf * entry.off
			end
			haloAnchor.CFrame = CFrame.lookAt(swordPos, swordPos + toCaster)
		end, function()
			swordPos = swordEnd
			local cf = swordCF()
			for _, entry in sword do
				entry.part.CFrame = cf * entry.off
			end
			haloAnchor:Destroy()
			-- EINSCHLAG
			if Effects.Near(center, 160) then
				Effects.ScreenFlash(WHITE, 0.6, 0)
			end
			Effects.Flash(center + Vector3.new(0, 3, 0), WHITE, 60, 0.6, 8)
			Effects.Flash(center + Vector3.new(0, 3, 0), gold, 44, 0.9, 6)
			Effects.GroundRing(center + Vector3.new(0, 0.3, 0), 2, R * 2.3, gold, 0.85, 4)
			task.delay(0.06, function()
				Effects.GroundRing(center + Vector3.new(0, 0.4, 0), 2, R * 1.6, WHITE, 0.55, 2)
			end)
			task.delay(0.12, function()
				Effects.Ring(CFrame.new(center + Vector3.new(0, 6, 0)) * CFrame.Angles(math.rad(90), 0, 0), 2, R * 1.4, paleGold, 0.6, 1.2, { Transparency = 0.3 })
			end)
			Effects.Shockwave(center + Vector3.new(0, 1, 0), R * 5, gold, 0.8)
			lightRays(center + Vector3.new(0, 2, 0), 14, 55, 0.7, function()
				return if rng:NextNumber() > 0.5 then gold else WHITE
			end)
			for _ = 1, 10 do
				local ang = rng:NextNumber(0, math.pi * 2)
				local pos = center + Vector3.new(math.cos(ang), 0, math.sin(ang)) * rng:NextNumber(3, R)
				local col = Effects.Part({
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(0.1, 2.2, 2.2),
					CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)),
					Color = paleGold,
				})
				local h = rng:NextNumber(30, 60)
				Effects.Tween(col, 0.2, { Size = Vector3.new(h, 2.2, 2.2), CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)) }, Enum.EasingStyle.Quart)
				Effects.Tween(col, 0.6, { Transparency = 1, Size = Vector3.new(h, 0.2, 0.2) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.2)
				Effects.Clean(col, 0.9)
			end
			Effects.Burst(center + Vector3.new(0, 2, 0), 150, {
				Texture = TEX.Sparkle,
				Color = Seq(WHITE, gold),
				Speed = NumberRange.new(30, 70),
				Lifetime = NumberRange.new(0.8, 1.6),
				Size = NSeq(1.4, 0),
				Drag = 2,
			})
			Effects.Rocks(center, 26, { Spread = 50, MaxUp = 70, Color = Color3.fromRGB(60, 52, 70) })
			Effects.Cracks(center, 12, R, gold, 2.5)
			local glow = glowDisc(center, R * 0.6, gold, 0.35)
			Effects.Tween(glow, 2.5, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			Effects.Clean(glow, 2.6)
			Effects.Light(center + Vector3.new(0, 5, 0), gold, 60, 10, 1.4)
			Effects.ShakeAt(center, 4.5, 200, 0.9)
			Effects.Sound("BigExplosion", center, { MaxDistance = 600 })
			Effects.Sound("Holy", center, { Pitch = 0.4, MaxDistance = 600 })

			-- Schwert bleibt stecken und zerfaellt dann in Licht
			task.delay(1.4, function()
				for _, entry in sword do
					Effects.Tween(entry.part, 0.8, { Transparency = 1 })
					Effects.Clean(entry.part, 0.9)
				end
				Effects.Burst(center + Vector3.new(0, bladeLen / 2, 0), 70, {
					Texture = TEX.Sparkle,
					Color = Seq(WHITE, gold),
					EmissionDirection = Enum.NormalId.Top,
					Speed = NumberRange.new(6, 16),
					Lifetime = NumberRange.new(1, 1.8),
					Size = NSeq(1, 0),
					Acceleration = Vector3.new(0, 8, 0),
				})
			end)
		end)
	end)
end

-- =============================================================================
-- BLOOD MOON (Mythisch): Roter Himmel, Mond, blitzschnelle Schnitte
-- =============================================================================

function C.BloodMoon(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local def = Abilities.Get("BloodMoon") :: any
	local T = def.Timing
	local red = Color3.fromRGB(255, 30, 50)
	local crimson = Color3.fromRGB(150, 0, 25)
	local rootCF = root.CFrame
	local casterPos = rootCF.Position
	local lookDir = flat(rootCF.LookVector)
	local roots = targetRoots(p)
	local function targetCenter(): Vector3
		if #roots == 0 then
			return casterPos + lookDir * 6
		end
		local sum = Vector3.zero
		for _, r in roots do
			sum += r.Position
		end
		return sum / #roots
	end

	-- Kamera ----------------------------------------------------------------
	local token = beginCutscene(ctx, def)
	if token then
		local right = lookDir:Cross(Vector3.yAxis)
		Cutscene.Move(
			CFrame.lookAt(casterPos + lookDir * 12 + right * 2 + Vector3.new(0, -1.2, 0), casterPos + Vector3.new(0, 6, 0)),
			CFrame.lookAt(casterPos + lookDir * 8.5 + right * 1.5 + Vector3.new(0, -1, 0), casterPos + Vector3.new(0, 7, 0)),
			T.Vanish,
			"InOut",
			64
		)
		at(token, T.Vanish - 0.25, function()
			local head = headPart(caster)
			if head then
				local hcf = head.CFrame
				Cutscene.Move(
					CFrame.lookAt((hcf * CFrame.new(0, 0.15, -4.5)).Position, hcf.Position),
					CFrame.lookAt((hcf * CFrame.new(0, 0.15, -2.6)).Position, hcf.Position),
					0.4,
					"Out",
					48
				)
			end
		end)
		at(token, T.SlashStart, function()
			local a0 = math.atan2(lookDir.Z, lookDir.X) + math.pi * 0.6
			Cutscene.Orbit(targetCenter, 21, 16, 7, 4.5, a0, a0 + 1.3, T.FinalSlash - T.SlashStart, Vector3.new(0, 1, 0))
			Cutscene.FOV(72, 0.2)
		end)
		at(token, T.FinalSlash, function()
			Cutscene.Move(
				CFrame.lookAt(casterPos - lookDir * 14 + Vector3.new(0, 18, 0), casterPos),
				CFrame.lookAt(casterPos - lookDir * 18 + Vector3.new(0, 24, 0), casterPos),
				def.CutsceneDuration - T.FinalSlash,
				"Out",
				80
			)
		end)
	end

	-- Welt-Effekte ------------------------------------------------------------
	local near = Effects.Near(casterPos, 170)
	if near then
		Effects.ColorGrade({ Brightness = -0.06, Contrast = 0.3, Saturation = -0.1, TintColor = Color3.fromRGB(255, 120, 120) }, 0.5, def.CutsceneDuration - 0.3, 0.9)
		Effects.AtmosphereTint(Color3.fromRGB(200, 40, 50), Color3.fromRGB(90, 0, 12), 0.5, def.CutsceneDuration - 0.3, 0.9)
	end
	Effects.Sound("Void", casterPos, { Pitch = 0.7, MaxDistance = 500 })
	Poser.Sequence(caster, { { P.Sheath, T.Vanish } }, 0.3)

	-- Der Blutmond
	local moonStart = casterPos - lookDir * 150 + Vector3.new(0, 15, 0)
	local moonEnd = casterPos - lookDir * 150 + Vector3.new(0, 78, 0)
	local moon = Effects.Ball(CFrame.new(moonStart), 84, Color3.fromRGB(255, 45, 55), { Transparency = 1 })
	local halo = Effects.Ball(CFrame.new(moonStart), 108, Color3.fromRGB(255, 80, 80), { Transparency = 1 })
	Effects.Tween(moon, 0.8, { Transparency = 0.02 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, T.MoonRise)
	Effects.Tween(halo, 0.8, { Transparency = 0.82 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, T.MoonRise)
	Effects.Tween(moon, 1.4, { CFrame = CFrame.new(moonEnd) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, T.MoonRise)
	Effects.Tween(halo, 1.4, { CFrame = CFrame.new(moonEnd) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, T.MoonRise)
	task.delay(def.CutsceneDuration, function()
		Effects.Tween(moon, 0.9, { Transparency = 1 })
		Effects.Tween(halo, 0.9, { Transparency = 1 })
		Effects.Clean(moon, 1)
		Effects.Clean(halo, 1)
	end)

	-- Rote Aura + gluehende Augen
	Effects.Stream(root, T.Vanish, {
		Texture = TEX.Smoke,
		Rate = 40,
		Color = Seq(red, Color3.fromRGB(30, 0, 5)),
		LightEmission = 0.4,
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(2, 6),
		Lifetime = NumberRange.new(0.6, 1.1),
		Size = NSeq(2, 4),
		Transparency = NSeq(0.3, 1),
		SpreadAngle = Vector2.new(50, 50),
	})
	local head = headPart(caster)
	if head then
		local eyes = {}
		for _, x in { -0.22, 0.22 } do
			local eye = Effects.Part({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.28, 0.28, 0.28), Color = red })
			Effects.Trail(eye, ColorSequence.new(red), 0.25, 0.2)
			table.insert(eyes, { part = eye, off = CFrame.new(x, 0.15, -0.58) })
		end
		local light = Make("PointLight", { Color = red, Range = 10, Brightness = 4, Parent = head })
		Effects.Animate(T.Vanish, function()
			for _, e in eyes do
				e.part.CFrame = head.CFrame * e.off
			end
		end, function()
			for _, e in eyes do
				e.part:Destroy()
			end
			light:Destroy()
		end)
	end

	-- Verschwinden
	task.delay(T.Vanish, function()
		local pos = root.Position
		Effects.Afterimage(caster, red, 0.5, 0.2)
		Effects.Burst(pos, 60, {
			Texture = TEX.Sparkle,
			Color = Seq(Color3.fromRGB(255, 120, 120), red, crimson),
			Speed = NumberRange.new(8, 22),
			Lifetime = NumberRange.new(0.8, 1.4),
			Size = NSeq(1, 0.3),
			Drag = 2,
			Acceleration = Vector3.new(0, -6, 0),
		})
		Effects.Flash(pos, red, 9, 0.3)
		Effects.Sound("Shadow", pos, { Pitch = 0.9 })
		if not ctx.Preview then
			Effects.SetCharacterVisible(caster, false)
		end
	end)

	-- Blitzschnelle Schnitte
	for i = 0, 4 do
		task.delay(T.SlashStart + i * 0.18, function()
			local points = {}
			if #roots > 0 then
				for _, r in roots do
					table.insert(points, r.Position)
				end
			else
				for _ = 1, 2 do
					table.insert(points, casterPos + lookDir * 7 + Vector3.new(rng:NextNumber(-5, 5), 0, rng:NextNumber(-5, 5)))
				end
			end
			for _, pos in points do
				local cf = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28))
				Effects.Slash(cf, rng:NextNumber(3.5, 5.5), red, 0.32, 230, 0.6)
				Effects.Line(cf * CFrame.Angles(math.rad(90), 0, 0), rng:NextNumber(10, 14), red, 0.3, 0.2)
				Effects.Burst(pos, 14, {
					Texture = TEX.Sparks,
					Color = Seq(Color3.fromRGB(255, 200, 200), red),
					Speed = NumberRange.new(14, 30),
					Size = NSeq(0.5, 0),
					Drag = 4,
				})
				local offset = Vector3.new(rng:NextNumber(-6, 6), 0, rng:NextNumber(-6, 6))
				Effects.Afterimage(caster, red, 0.25, 0.35, CFrame.new(pos + offset - root.Position))
				Effects.Sound("Slash", pos, { Pitch = rng:NextNumber(0.9, 1.4), Volume = 0.8 })
			end
		end)
	end

	-- Finaler Halbmond-Schnitt
	task.delay(T.FinalSlash, function()
		if not ctx.Preview then
			Effects.SetCharacterVisible(caster, true)
		end
		Poser.Sequence(caster, { { P.Sheath, 0.6 } }, 0.3)
		local pos = root.Position + Vector3.new(0, 1, 0)
		local flatCF = CFrame.new(pos) * CFrame.Angles(math.rad(90), 0, 0) * CFrame.Angles(0, 0, rng:NextNumber(0, 6.28))
		Effects.Slash(flatCF, 20, red, 0.7, 320, 2.4)
		Effects.Slash(flatCF * CFrame.Angles(0, 0, 0.4), 16, WHITE, 0.5, 260, 0.8)
		Effects.GroundRing(Effects.Ground(pos) + Vector3.new(0, 0.3, 0), 2, 32, red, 0.7, 3)
		Effects.Shockwave(pos, 70, red, 0.6)
		Effects.Burst(pos, 90, {
			Texture = TEX.Sparkle,
			Color = Seq(Color3.fromRGB(255, 150, 150), red, crimson),
			Speed = NumberRange.new(20, 50),
			Lifetime = NumberRange.new(0.8, 1.4),
			Size = NSeq(1.2, 0),
			Drag = 2,
		})
		if Effects.Near(pos, 120) then
			Effects.ScreenFlash(red, 0.45, 0.45)
		end
		Effects.ShakeAt(pos, 3, 120, 0.6)
		Effects.Sound("Slash", pos, { Pitch = 0.6, Volume = 1.2 })
		Effects.Sound("Explosion", pos, { Pitch = 0.8 })
	end)
end

-- =============================================================================
-- SUPERNOVA (Goettlich): Ein Stern entsteht und explodiert
-- =============================================================================

function C.Supernova(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local def = Abilities.Get("Supernova") :: any
	local T = def.Timing
	local divine = Rarities.Get("Divine")
	local warm = Color3.fromRGB(255, 225, 140)
	local blue = Color3.fromRGB(150, 220, 255)
	local function starPos(): Vector3
		return root.Position + Vector3.new(0, 6.5, 0)
	end
	local ground = Effects.Ground(root.Position)
	local lookDir = flat(root.CFrame.LookVector)
	local a0 = math.atan2(lookDir.Z, lookDir.X)

	-- Kamera ----------------------------------------------------------------
	local token = beginCutscene(ctx, def, { Hold = 2.2 })
	if token then
		Cutscene.Orbit(function()
			return root.Position + Vector3.new(0, 2, 0)
		end, 13, 12, -1, 2, a0, a0 + 1.2, 1.0, Vector3.new(0, 1, 0))
		Cutscene.FOV(62, 0.3)
		at(token, 1.0, function()
			Cutscene.Orbit(starPos, 10, 8, -2.5, -1.2, a0 + 1.2, a0 + 2.0, T.Grow - 1.0)
		end)
		at(token, T.Grow, function()
			Cutscene.Orbit(starPos, 10, 50, 0, 20, a0 + 2.0, a0 + 2.6, T.Explode - T.Grow)
			Cutscene.FOV(76, T.Explode - T.Grow)
		end)
		at(token, T.Explode, function()
			local c = starPos()
			local pos = c + Vector3.new(math.cos(a0 + 2.6) * 56, 24, math.sin(a0 + 2.6) * 56)
			Cutscene.Move(CFrame.lookAt(pos, c), CFrame.lookAt(pos + (pos - c).Unit * 8, c), def.CutsceneDuration - T.Explode, "Out", 80)
		end)
	end

	-- Welt-Effekte ------------------------------------------------------------
	Poser.Sequence(caster, { { P.ArmsUp, T.Explode + 0.2 } }, 0.4)
	local near = Effects.Near(root.Position, 220)
	if near then
		Effects.ColorGrade({ Brightness = -0.22, Saturation = -0.5, Contrast = 0.2, TintColor = Color3.fromRGB(220, 225, 255) }, 0.6, T.Collapse - 0.6, 0.3)
	end
	Effects.Sound("Charge", root.Position, { Pitch = 0.6, MaxDistance = 500 })

	local core = Effects.Ball(CFrame.new(starPos()), 0.5, WHITE)
	local corona = Effects.Ball(CFrame.new(starPos()), 0.8, warm, { Transparency = 0.55 })
	local light = Make("PointLight", { Color = warm, Range = 20, Brightness = 2, Shadows = true, Parent = core })
	local gather = Effects.Ball(CFrame.new(starPos()), 38, warm, { Transparency = 1 })
	Effects.Stream(gather, T.Collapse, {
		Texture = TEX.Sparkle,
		Rate = 140,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Speed = NumberRange.new(22, 30),
		Lifetime = NumberRange.new(0.6, 0.8),
		Color = divine.Gradient,
		Size = NSeq(1, 0.2),
		SpreadAngle = Vector2.new(0, 0),
	})
	local ringAnchor = Effects.Anchor(starPos())
	local ringDefs = {
		{ axis = Vector3.new(1, 0.2, 0).Unit, speed = 2.2, color = Color3.fromRGB(120, 230, 255), extra = 1.2 },
		{ axis = Vector3.new(0.2, 1, 0.3).Unit, speed = -1.6, color = Color3.fromRGB(255, 210, 90), extra = 2.4 },
		{ axis = Vector3.new(0.4, 0.3, 1).Unit, speed = 2.8, color = WHITE, extra = 3.6 },
	}
	local rings = {}
	for _, rd in ringDefs do
		local ring = staticRing(ringAnchor, CFrame.new(), 1, 0.25, rd.color, 0.15)
		local moonlet = Effects.Ball(CFrame.new(starPos()), 0.7, rd.color)
		table.insert(rings, { ring = ring, def = rd, moonlet = moonlet })
	end
	Effects.Sound("Holy", root.Position, { Pitch = 0.7, MaxDistance = 500 })

	local total = T.Explode
	Effects.Animate(total, function(a)
		local t = a * total
		local c = starPos()
		local size: number
		if t < T.Grow then
			size = 0.5 + 6.5 * Effects.Ease(math.clamp(t / T.Grow, 0, 1), "InOut")
		elseif t < T.Collapse then
			size = 7 + math.sin(t * 22) * 0.6
		else
			local k = math.clamp((t - T.Collapse) / (T.Explode - T.Collapse), 0, 1)
			size = 7 * (1 - k) ^ 2 + 0.3
		end
		local blueShift = math.clamp((t - T.Grow) / 0.5, 0, 1)
		core.Size = Vector3.new(size, size, size)
		core.CFrame = CFrame.new(c)
		core.Color = WHITE:Lerp(Color3.fromRGB(220, 245, 255), blueShift)
		corona.Size = core.Size * (1.7 + math.sin(t * 9) * 0.1)
		corona.CFrame = core.CFrame
		corona.Color = warm:Lerp(blue, blueShift)
		gather.CFrame = core.CFrame
		light.Range = math.min(60, 20 + size * 6)
		light.Brightness = 2 + size
		light.Color = warm:Lerp(blue, blueShift)
		ringAnchor.CFrame = CFrame.new(c)
		for i, entry in rings do
			local rd = entry.def
			local spin = t * rd.speed * (1 + blueShift)
			local r = math.max(0.1, size * 0.6 + rd.extra)
			if t > T.Collapse then
				r = math.max(0.05, r * (1 - math.clamp((t - T.Collapse) / (T.Explode - T.Collapse), 0, 1)))
			end
			local rot = CFrame.fromAxisAngle(rd.axis, spin) * CFrame.Angles(math.rad(70 + i * 25), 0, 0)
			entry.ring.CFrame = rot
			entry.ring.Radius = r
			entry.ring.InnerRadius = math.max(0, r - 0.25)
			entry.moonlet.CFrame = CFrame.new(c) * rot * CFrame.Angles(0, 0, spin * 2) * CFrame.new(r, 0, 0)
		end
	end, function()
		core:Destroy()
		corona:Destroy()
		gather:Destroy()
		ringAnchor:Destroy()
		for _, entry in rings do
			entry.moonlet:Destroy()
		end
	end)

	-- EXPLOSION
	task.delay(T.Explode, function()
		local c = starPos()
		if Effects.Near(c, 220) then
			Effects.ScreenFlash(WHITE, 0.8, 0)
		end
		local big = Effects.Ball(CFrame.new(c), 2, WHITE, { Transparency = 0 })
		Effects.Tween(big, 0.9, { Size = Vector3.new(78, 78, 78), Transparency = 1 }, Enum.EasingStyle.Quart)
		Effects.Clean(big, 0.95)
		local cyan = Effects.Ball(CFrame.new(c), 2, blue, { Transparency = 0.1 })
		Effects.Tween(cyan, 0.7, { Size = Vector3.new(56, 56, 56), Transparency = 1 }, Enum.EasingStyle.Quart)
		Effects.Clean(cyan, 0.75)
		Effects.GroundRing(ground + Vector3.new(0, 0.3, 0), 2, 72, WHITE, 0.9, 5)
		task.delay(0.05, function()
			Effects.GroundRing(ground + Vector3.new(0, 0.4, 0), 2, 52, blue, 0.7, 3)
		end)
		Effects.Ring(CFrame.new(c) * CFrame.Angles(math.rad(90), 0, 0), 2, 64, Color3.fromRGB(255, 210, 90), 0.8, 3, { Transparency = 0.1 })
		Effects.Ring(CFrame.new(c) * CFrame.Angles(math.rad(60), math.rad(30), 0), 2, 55, Color3.fromRGB(255, 130, 200), 0.75, 2.5, { Transparency = 0.2 })
		Effects.Ring(CFrame.new(c) * CFrame.Angles(math.rad(120), math.rad(-30), 0), 2, 55, Color3.fromRGB(130, 255, 170), 0.75, 2.5, { Transparency = 0.2 })
		Effects.Shockwave(c, 160, WHITE, 0.9)
		lightRays(c, 20, 75, 0.9, function(i)
			return Color3.fromHSV((i / 20 + rng:NextNumber(0, 0.1)) % 1, 0.55, 1)
		end)
		Effects.Burst(c, 220, {
			Texture = TEX.Sparkle,
			Color = divine.Gradient,
			Speed = NumberRange.new(40, 95),
			Lifetime = NumberRange.new(1, 1.8),
			Size = NSeq(1.8, 0),
			Drag = 1.5,
		})
		Effects.Rocks(ground, 28, { Spread = 60, MaxUp = 80, Color = Color3.fromRGB(60, 52, 70) })
		Effects.Cracks(ground, 14, 30, blue, 3)
		Effects.Light(c, WHITE, 60, 14, 1.6)
		Effects.ShakeAt(c, 5.5, 240, 1.1)
		Effects.Sound("BigExplosion", c, { MaxDistance = 700 })
		Effects.Sound("Holy", c, { Pitch = 0.4, MaxDistance = 700 })
		-- Sternenstaub rieselt
		local dust = Effects.Part({ Size = Vector3.new(70, 1, 70), CFrame = CFrame.new(c + Vector3.new(0, 18, 0)), Transparency = 1 })
		Effects.Stream(dust, 2.2, {
			Texture = TEX.Sparkle,
			Rate = 120,
			Shape = Enum.ParticleEmitterShape.Box,
			Color = divine.Gradient,
			EmissionDirection = Enum.NormalId.Bottom,
			Speed = NumberRange.new(3, 7),
			Lifetime = NumberRange.new(2, 3),
			Size = NSeq(0.6, 0),
			SpreadAngle = Vector2.new(10, 10),
		})
		Effects.Clean(dust, 6)
	end)
end

-- =============================================================================
-- BLACK HOLE (Exklusiv / Robux): Singularitaet, Akkretionsscheibe, Implosion
-- =============================================================================

function C.BlackHole(p: any, ctx: any)
	local caster = p.Caster
	local root = Effects.Root(caster)
	if not root then
		return
	end
	local def = Abilities.Get("BlackHole") :: any
	local T = def.Timing
	local purple = Color3.fromRGB(150, 60, 255)
	local orange = Color3.fromRGB(255, 140, 40)
	local hot = Color3.fromRGB(255, 220, 160)
	local rootCF = root.CFrame
	local center: Vector3 = p.Extra.Center or (rootCF.Position + flat(rootCF.LookVector) * 16 + Vector3.new(0, 6, 0))
	local toCenter = flat(center - rootCF.Position)
	local a0 = math.atan2(-toCenter.Z, -toCenter.X) + 0.5

	-- Kamera ----------------------------------------------------------------
	local token = beginCutscene(ctx, def, { Glitch = true, Subtitle = "✦ SINGULARITY • EXCLUSIVE ✦", Hold = 2.4 })
	if token then
		Cutscene.Shot(function()
			local hand = Effects.HandPosition(caster, "Right") or root.Position
			local cam = (root.CFrame * CFrame.new(3.4, 2.4, -5.6)).Position
			return CFrame.lookAt(cam, hand:Lerp(root.Position + Vector3.new(0, 1.5, 0), 0.35))
		end, 55, 0.2)
		at(token, T.Throw, function()
			Cutscene.Move(
				CFrame.lookAt((root.CFrame * CFrame.new(2.6, 2.8, 5.5)).Position, center),
				CFrame.lookAt((root.CFrame * CFrame.new(2.2, 3.2, 3.5)).Position, center),
				T.Form - T.Throw,
				"Out",
				66
			)
		end)
		at(token, T.Form, function()
			Cutscene.Orbit(function()
				return center
			end, 36, 28, 11, 6, a0, a0 + 1.6, 2.4 - T.Form)
			Cutscene.FOV(70, 0.3)
		end)
		at(token, 2.4, function()
			Cutscene.Orbit(function()
				return center
			end, 19, 14, 3, 1.5, a0 + 1.6, a0 + 2.3, T.Collapse - 2.4)
			Cutscene.FOV(62, 0.4)
		end)
		at(token, T.Collapse, function()
			Cutscene.FOV(26, T.Explode - T.Collapse)
		end)
		at(token, T.Explode, function()
			local pos = center + Vector3.new(math.cos(a0 + 2.3) * 58, 28, math.sin(a0 + 2.3) * 58)
			Cutscene.Move(CFrame.lookAt(pos, center), CFrame.lookAt(pos + (pos - center).Unit * 10, center), def.CutsceneDuration - T.Explode, "Out", 82)
		end)
	end

	-- Welt-Effekte ------------------------------------------------------------
	if Effects.Near(center, 230) then
		Effects.ColorGrade({ Brightness = -0.18, Contrast = 0.35, Saturation = -0.6, TintColor = Color3.fromRGB(205, 180, 255) }, 0.5, T.Explode - 0.5, 0.5)
		Effects.AtmosphereTint(Color3.fromRGB(60, 20, 120), Color3.fromRGB(10, 0, 30), 0.5, T.Explode - 0.5, 0.8)
	end
	Poser.Sequence(caster, { { P.RightUp, T.Throw }, { P.CastForward, def.CutsceneDuration - T.Throw } }, 0.4)
	Effects.Sound("Void", root.Position, { Pitch = 0.5, MaxDistance = 600 })

	-- 1) Energie sammelt sich in der Hand
	local orb = Effects.Ball(CFrame.new(root.Position), 0.2, Color3.new(0, 0, 0), { Material = Enum.Material.SmoothPlastic })
	local orbGlow = Effects.Ball(CFrame.new(root.Position), 0.4, purple, { Transparency = 0.4 })
	local gather = Effects.Ball(CFrame.new(root.Position), 14, purple, { Transparency = 1 })
	Effects.Stream(gather, T.Throw, {
		Texture = TEX.Sparkle,
		Rate = 120,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Speed = NumberRange.new(12, 18),
		Lifetime = NumberRange.new(0.35, 0.45),
		Color = Seq(WHITE, purple),
		Size = NSeq(0.7, 0.1),
		SpreadAngle = Vector2.new(0, 0),
	})
	Make("PointLight", { Color = purple, Range = 16, Brightness = 5, Parent = orbGlow })
	Effects.Animate(T.Throw, function(a)
		local hand = Effects.HandPosition(caster, "Right") or root.Position
		local s = 0.2 + 1.5 * a
		orb.Size = Vector3.new(s, s, s)
		orb.CFrame = CFrame.new(hand + Vector3.new(0, 0.8, 0))
		orbGlow.Size = orb.Size * 1.6
		orbGlow.CFrame = orb.CFrame
		gather.CFrame = orb.CFrame
	end, function()
		gather:Destroy()
		-- 2) Wurf zum Zentrum
		Effects.Trail(orbGlow, Seq(WHITE, purple), 0.3, 1.5)
		Effects.Sound("Whoosh", orb.Position, { Pitch = 0.6 })
		Effects.Tween(orb, T.Form - T.Throw, { CFrame = CFrame.new(center) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Effects.Tween(orbGlow, T.Form - T.Throw, { CFrame = CFrame.new(center) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Effects.Clean(orb, T.Form - T.Throw + 0.05)
		Effects.Clean(orbGlow, T.Form - T.Throw + 0.05)
	end)

	-- 3) Die Singularitaet
	task.delay(T.Form, function()
		Effects.Flash(center, purple, 14, 0.35)
		Effects.Sound("Void", center, { Pitch = 0.35, Volume = 1.2, MaxDistance = 700 })
		Effects.Sound("Rumble", center, { Pitch = 0.4, MaxDistance = 700 })

		local core = Effects.Ball(CFrame.new(center), 0.5, Color3.new(0, 0, 0), { Material = Enum.Material.SmoothPlastic })
		local horizon = Effects.Ball(CFrame.new(center), 0.7, purple, { Transparency = 0.5 })
		local outer = Effects.Ball(CFrame.new(center), 1, Color3.fromRGB(90, 30, 200), { Transparency = 0.85 })
		local field = Effects.Ball(CFrame.new(center), 2, purple, { Material = Enum.Material.ForceField, Transparency = 0 })
		local lightPart = Effects.Anchor(center)
		local light = Make("PointLight", { Color = purple, Range = 50, Brightness = 6, Parent = lightPart })
		local photon = staticRing(lightPart, CFrame.new(), 1, 0.35, hot, 0.05)

		-- Akkretionsscheibe aus rotierenden Neon-Segmenten
		local tilt = CFrame.Angles(math.rad(14), 0, math.rad(8))
		local diskDefs = {
			{ r = 8, n = 18, color = hot, speed = 4.2, tr = 0.05, w = 1.4 },
			{ r = 11.5, n = 26, color = orange, speed = 2.8, tr = 0.2, w = 1.8 },
			{ r = 15.5, n = 34, color = purple, speed = 1.7, tr = 0.35, w = 2.2 },
		}
		local segments = {}
		for di, dd in diskDefs do
			local n = math.max(10, math.floor(dd.n * math.max(Effects.Quality, 0.6)))
			for i = 1, n do
				local seg = Effects.Part({
					Size = Vector3.new(dd.w, 0.25, (2 * math.pi * dd.r / n) * 1.1),
					Color = dd.color,
					Transparency = dd.tr,
				})
				if di == 3 and i % 6 == 0 then
					local att = Make("Attachment", { Parent = seg })
					Effects.Emitter(att, {
						Texture = TEX.Sparkle,
						Rate = 18,
						Color = Seq(hot, purple),
						Speed = NumberRange.new(0.5, 1.5),
						Lifetime = NumberRange.new(0.4, 0.8),
						Size = NSeq(0.8, 0),
					})
				end
				table.insert(segments, { part = seg, def = dd, phase = (i / n) * math.pi * 2 })
			end
		end

		-- Partikel werden eingesaugt
		local suck = Effects.Ball(CFrame.new(center), 66, purple, { Transparency = 1 })
		local suckSpark = Effects.Emitter(suck, {
			Texture = TEX.Sparkle,
			Rate = 150 * Effects.Quality,
			Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
			Speed = NumberRange.new(28, 34),
			Lifetime = NumberRange.new(0.95, 1.05),
			Color = Seq(WHITE, purple),
			Size = NSeq(0.4, 1.2, 0),
			SpreadAngle = Vector2.new(0, 0),
		})
		local suckDust = Effects.Emitter(suck, {
			Texture = TEX.Smoke,
			Rate = 35 * Effects.Quality,
			Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
			Speed = NumberRange.new(26, 32),
			Lifetime = NumberRange.new(1, 1.1),
			Color = ColorSequence.new(Color3.fromRGB(70, 30, 120)),
			LightEmission = 0.3,
			Size = NSeq(6, 2),
			Transparency = NSeq(0.6, 0.2),
			SpreadAngle = Vector2.new(0, 0),
		})

		-- Truemmer werden spiralfoermig eingesaugt
		for i = 1, math.floor(26 * Effects.Quality) do
			task.delay(i * 0.05, function()
				local ang = rng:NextNumber(0, math.pi * 2)
				local dist = rng:NextNumber(10, 30)
				local startPos = Effects.Ground(center + Vector3.new(math.cos(ang) * dist, 0, math.sin(ang) * dist), 8)
				local s = rng:NextNumber(0.8, 2.2)
				local rock = Effects.Part({
					Size = Vector3.new(s, s * 0.8, s),
					Material = Enum.Material.Slate,
					Color = Color3.fromRGB(60, 50, 72),
					CFrame = CFrame.new(startPos),
				})
				local life = rng:NextNumber(1.3, 2.0)
				local spin = Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-6, 6), rng:NextNumber(-6, 6))
				Effects.Animate(life, function(a)
					local e = a * a
					local r = dist * (1 - e)
					local th = ang + e * math.pi * 3
					local h = startPos.Y + (center.Y - startPos.Y) * Effects.Ease(a, "OutCubic")
					local pos = Vector3.new(center.X + math.cos(th) * r, h, center.Z + math.sin(th) * r)
					rock.CFrame = CFrame.new(pos) * CFrame.Angles(spin.X * a, spin.Y * a, spin.Z * a)
					local k = math.max(0.05, 1 - e)
					rock.Size = Vector3.new(s, s * 0.8, s) * k
				end, function()
					rock:Destroy()
				end)
			end)
		end

		-- Lila Blitze
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < T.Collapse - T.Form do
				local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.6, 0.6), rng:NextNumber(-1, 1)).Unit
				Effects.Bolt(center + dir * 4, center + dir * rng:NextNumber(11, 19), {
					Color = purple,
					Width = 0.22,
					Duration = 0.2,
					Segments = 6,
				})
				task.wait(0.14)
			end
		end)

		-- Pulsierender Klang
		task.spawn(function()
			for _ = 1, 2 do
				task.wait(1)
				Effects.Sound("Void", center, { Pitch = 0.3, Volume = 0.8, MaxDistance = 600 })
			end
		end)

		local life = T.Explode - T.Form
		local collapseAt = T.Collapse - T.Form
		Effects.Animate(life, function(a)
			local t = a * life
			local grow = Effects.Ease(math.clamp(t / 0.55, 0, 1), "OutBack")
			local shrink = 1 - Effects.Ease(math.clamp((t - collapseAt) / (life - collapseAt), 0, 1), "In")
			local k = grow * shrink
			local pulse = 1 + math.sin(t * 9) * 0.04
			local coreSize = math.max(0.2, 10 * k * pulse)
			core.Size = Vector3.new(coreSize, coreSize, coreSize)
			horizon.Size = core.Size * 1.28
			outer.Size = core.Size * 2.3
			field.Size = Vector3.one * math.max(0.5, 32 * k)
			light.Brightness = 6 + (1 - shrink) * 20
			local cam = workspace.CurrentCamera
			local toCam = if cam then (cam.CFrame.Position - center) else Vector3.zAxis
			photon.CFrame = CFrame.lookAt(Vector3.zero, if toCam.Magnitude > 0.01 then toCam.Unit else Vector3.zAxis)
			photon.Radius = math.max(0.1, coreSize * 0.78)
			photon.InnerRadius = math.max(0, photon.Radius - 0.35)
			for _, seg in segments do
				local dd = seg.def
				local ang = seg.phase + t * dd.speed
				local r = dd.r * k
				seg.part.CFrame = CFrame.new(center) * tilt * CFrame.Angles(0, ang, 0) * CFrame.new(r, 0, 0)
				seg.part.Size = Vector3.new(dd.w * math.max(k, 0.05), 0.25, math.max(0.1, (2 * math.pi * r / 26) * 1.1))
			end
			if t > collapseAt then
				suckSpark.Rate = 0
				suckDust.Rate = 0
			end
		end, function()
			core:Destroy()
			horizon:Destroy()
			outer:Destroy()
			field:Destroy()
			lightPart:Destroy()
			suck:Destroy()
			for _, seg in segments do
				seg.part:Destroy()
			end
		end)
	end)

	-- 4) Kollaps-Ton
	task.delay(T.Collapse, function()
		Effects.Sound("Holy", center, { Pitch = 2, Volume = 0.8, MaxDistance = 600 })
	end)

	-- 5) IMPLOSION / EXPLOSION
	task.delay(T.Explode, function()
		if Effects.Near(center, 230) then
			Effects.ScreenFlash(WHITE, 0.7, 0)
			task.delay(0.15, function()
				Effects.ScreenFlash(purple, 0.5, 0.4)
			end)
		end
		local blast = Effects.Ball(CFrame.new(center), 2, purple, { Transparency = 0 })
		Effects.Tween(blast, 1, { Size = Vector3.new(90, 90, 90), Transparency = 1 }, Enum.EasingStyle.Quart)
		Effects.Clean(blast, 1.05)
		local anti = Effects.Ball(CFrame.new(center), 2, Color3.new(0, 0, 0), { Material = Enum.Material.SmoothPlastic })
		Effects.Tween(anti, 0.35, { Size = Vector3.new(42, 42, 42) }, Enum.EasingStyle.Quart)
		Effects.Tween(anti, 0.25, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.25)
		Effects.Clean(anti, 0.55)
		local g = Effects.Ground(center, 7)
		Effects.GroundRing(g + Vector3.new(0, 0.3, 0), 2, 85, purple, 1, 5.5)
		task.delay(0.05, function()
			Effects.GroundRing(g + Vector3.new(0, 0.4, 0), 2, 60, orange, 0.8, 3)
		end)
		local cam = workspace.CurrentCamera
		local camDir = if cam then (cam.CFrame.Position - center).Unit else Vector3.zAxis
		Effects.Ring(CFrame.lookAt(center, center + camDir), 2, 52, WHITE, 0.6, 2, { Transparency = 0.1 })
		Effects.Ring(CFrame.new(center) * CFrame.Angles(math.rad(76), 0, math.rad(8)), 2, 66, hot, 0.85, 3, { Transparency = 0.15 })
		Effects.Shockwave(center, 180, purple, 1)
		lightRays(center, 22, 80, 1, function(i)
			return if i % 3 == 0 then orange elseif i % 3 == 1 then purple else WHITE
		end)
		Effects.Burst(center, 230, {
			Texture = TEX.Sparkle,
			Color = Seq(WHITE, purple, orange),
			Speed = NumberRange.new(40, 100),
			Lifetime = NumberRange.new(1, 1.8),
			Size = NSeq(1.8, 0),
			Drag = 1.5,
		})
		Effects.Burst(center, 40, {
			Texture = TEX.Smoke,
			Color = Seq(Color3.fromRGB(110, 50, 200), Color3.fromRGB(20, 5, 40)),
			LightEmission = 0.3,
			Speed = NumberRange.new(20, 40),
			Lifetime = NumberRange.new(1.5, 2.5),
			Size = NSeq(8, 18),
			Transparency = NSeq(0.3, 1),
			Drag = 2,
		})
		Effects.Rocks(g, 30, { Spread = 70, MaxUp = 90, Color = Color3.fromRGB(50, 40, 64), MaxSize = 2.4 })
		Effects.Cracks(g, 14, 34, purple, 3.5)
		Effects.Scorch(g, 24, 5, Color3.fromRGB(20, 5, 35))
		Effects.Light(center, purple, 60, 14, 1.6)
		Effects.ShakeAt(center, 6, 260, 1.3)
		Effects.Sound("BigExplosion", center, { Pitch = 0.8, MaxDistance = 800 })
		Effects.Sound("Void", center, { Pitch = 0.6, MaxDistance = 800 })
		Effects.Sound("Explosion", center, { Pitch = 0.5, MaxDistance = 800 })
	end)
end

return C
