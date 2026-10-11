-- Effekte fuer den Grundkampf: Schlaege (M1), Treffer, Blocken, Guard Break, Dash, Tod, Sieg, Freischaltung.
-- Stil: knackige Trail-Sicheln, kleine Funken + Staub in Bodenfarbe, beim Finisher Hit-Stop,
-- Impact-Frame und kraeftiges Wackeln. Schadenszahlen im Chunky-UI-Stil (FredokaOne + dunkle Kontur).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Make = require(Shared:WaitForChild("Make"))

local VFX = script.Parent :: Instance
local Effects = require(VFX:WaitForChild("Effects"))
local Poser = require(VFX:WaitForChild("Poser"))
local UIFolder = (VFX.Parent :: Instance):WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))

local CombatVFX = {}

local player = Players.LocalPlayer
local rng = Effects.Random
local TEX = Effects.Textures
local P = Poser.Poses
local PAL = Effects.Palettes
local Seq, NSeq = Effects.Seq, Effects.NSeq

local C = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local TAU = math.pi * 2
local INK = Theme.Colors.Ink

local EFFECT_COLORS: { [string]: Color3 } = {
	Fire = PAL.Fire.Mid,
	Burn = C(255, 150, 60),
	Ice = PAL.Ice.Mid,
	Electric = PAL.Lightning.Glow,
	Water = C(110, 190, 245),
	Shadow = C(170, 120, 240),
	Holy = PAL.Holy.Gold,
	Void = C(170, 110, 240),
	Slash = C(230, 60, 70),
	Rock = C(190, 160, 120),
	Wind = PAL.Wind.Pale,
}

local function isLocal(character: Model?): boolean
	return character ~= nil and character == player.Character
end

local function flat(v: Vector3, fallback: Vector3?): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-3 then
		return fallback or Vector3.new(0, 0, -1)
	end
	return f.Unit
end

-- Schadenszahlen -------------------------------------------------------------------

local function formatAmount(amount: number): string
	local n = math.floor(amount * 10 + 0.5) / 10
	if n >= 10 or n == math.floor(n) then
		return tostring(math.floor(n + 0.5))
	end
	return string.format("%.1f", n)
end

local function damageNumber(position: Vector3, amount: number, color: Color3, big: boolean, label: string?)
	local jitter = Vector3.new(rng:NextNumber(-1.3, 1.3), rng:NextNumber(0.9, 1.8), rng:NextNumber(-1.3, 1.3))
	local anchor = Effects.Anchor(position + jitter, 1.5)
	local text = label or formatAmount(amount)
	local h = if big then 64 else 46
	local w = math.max(if big then 150 else 110, 28 + #text * (if big then 30 else 22))
	local gui = Make("BillboardGui", {
		Size = UDim2.fromOffset(w, h),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 150,
		Parent = anchor,
	})
	local labelObj = Make("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Text = text,
		Font = Theme.Fonts.Heading,
		TextScaled = true,
		TextColor3 = color,
		Rotation = if big then rng:NextNumber(-7, 7) else 0,
		Parent = gui,
	})
	local stroke = Make("UIStroke", {
		Color = INK,
		Thickness = if big then 4 else 3,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = labelObj,
	})
	-- Pop: gross rein, mit Rueckfederung auf normale Groesse
	local scale = Make("UIScale", { Scale = if big then 1.9 else 1.5, Parent = labelObj })
	Effects.Tween(scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	-- Schweben + Ausblenden
	Effects.Tween(gui, 1.05, { StudsOffset = Vector3.new(rng:NextNumber(-0.5, 0.5), 3, 0) }, Enum.EasingStyle.Quad)
	Effects.Tween(labelObj, 0.3, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.78)
	Effects.Tween(stroke, 0.3, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.78)
	Effects.Tween(scale, 0.3, { Scale = 0.7 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.78)
end

-- Kleine Bausteine ------------------------------------------------------------------

-- Heller Treffer-Kern (ein Sprite, sehr kurz)
local function hitCore(position: Vector3, size: number, color: Color3)
	Effects.Burst(position, 1, {
		Texture = TEX.Core,
		Color = Seq(WHITE, color),
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.08, 0.11),
		Size = NSeq(size * 0.4, size),
		Transparency = NSeq(0, 1),
		RotSpeed = NumberRange.new(0),
		LightEmission = 1,
		ZOffset = 2,
	})
end

-- Anime-"Treffer-Stern": kurze, duenne Striche, die von der Trefferstelle wegspritzen (zur Kamera ausgerichtet)
local function impactStar(point: Vector3, size: number, color: Color3)
	local cam = workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else point + Vector3.new(0, 0, 10)
	if (camPos - point).Magnitude < 0.1 then
		return
	end
	local facing = CFrame.lookAt(point, camPos)
	for i = 1, 6 do
		local a = (i / 6) * TAU + rng:NextNumber(-0.35, 0.35)
		local len = size * rng:NextNumber(0.55, 1)
		local dir = facing.RightVector * math.cos(a) + facing.UpVector * math.sin(a)
		local startPos = point + dir * 0.7
		local spike = Effects.Part({
			Size = Vector3.new(0.12, 0.12, len * 0.3),
			CFrame = CFrame.lookAt(startPos + dir * len * 0.15, startPos + dir * (len * 0.15 + 1)),
			Color = color,
		})
		local endPos = startPos + dir * len * 0.9
		Effects.Tween(spike, 0.05, { Size = Vector3.new(0.14, 0.14, len) })
		Effects.Tween(spike, 0.12, {
			Size = Vector3.new(0.02, 0.02, len * 0.6),
			Transparency = 1,
			CFrame = CFrame.lookAt(endPos, endPos + dir),
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.05)
		Effects.Clean(spike, 0.2)
	end
end

-- Partikel an mehreren Emittern derselben Stelle ausstossen (spart Anker-Teile)
local function emitAt(position: Vector3, life: number, list: { { any } })
	local anchor, att = Effects.Anchor(position, life)
	for _, entry in list do
		local e = Effects.Emitter(att, entry[2])
		e:Emit(math.max(1, math.floor(entry[1] * Effects.Quality)))
	end
	return anchor
end

-- Effekt-Overlays auf dem Getroffenen ---------------------------------------------

local function overlay(effect: string, victim: Model, root: BasePart, point: Vector3, dir: Vector3)
	local pos = root.Position
	if effect == "Fire" then
		Effects.FireBurst(point, dir, 0.7, { Speed = 14, Spread = Vector2.new(50, 50) })
		Effects.Light(pos, PAL.Fire.Mid, 16, 3, 0.35)
	elseif effect == "Burn" then
		emitAt(pos + Vector3.new(rng:NextNumber(-0.6, 0.6), rng:NextNumber(-1, 1), rng:NextNumber(-0.6, 0.6)), 1.2, {
			{ 6, {
				Texture = TEX.Fire,
				Color = Effects.FireColors,
				EmissionDirection = Enum.NormalId.Top,
				SpreadAngle = Vector2.new(25, 25),
				Speed = NumberRange.new(2, 5),
				Lifetime = NumberRange.new(0.3, 0.55),
				Size = NSeq(1.2, 1.8, 0),
				Acceleration = Vector3.new(0, 8, 0),
				LightEmission = 0.85,
			} },
			{ 3, {
				Texture = TEX.Smoke,
				Color = ColorSequence.new(PAL.Fire.Smoke),
				LightEmission = 0,
				LightInfluence = 0.7,
				EmissionDirection = Enum.NormalId.Top,
				SpreadAngle = Vector2.new(20, 20),
				Speed = NumberRange.new(2, 4),
				Lifetime = NumberRange.new(0.7, 1),
				Size = NSeq(1, 2.6),
				Transparency = NSeq(0.4, 0.7, 1),
			} },
		})
	elseif effect == "Ice" then
		-- Eiskristalle wachsen um die Beine
		local g = Effects.Ground(pos)
		local crystals = {}
		for i = 1, 6 do
			local a = (i / 6) * TAU + rng:NextNumber(-0.2, 0.2)
			local h = rng:NextNumber(2.2, 3.6)
			local w = rng:NextNumber(0.7, 1.1)
			local base = g + Vector3.new(math.cos(a) * 1.3, 0, math.sin(a) * 1.3)
			local tilt = CFrame.lookAt(base, Vector3.new(pos.X, base.Y, pos.Z)) * CFrame.Angles(math.rad(-rng:NextNumber(8, 22)), 0, 0)
				* CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
			local crystal = Effects.Wedge({
				Size = Vector3.new(w, 0.2, w * 1.3),
				CFrame = tilt,
				Material = Enum.Material.Glass,
				Color = PAL.Ice.Light:Lerp(PAL.Ice.Mid, rng:NextNumber()),
				Transparency = 0.3,
				Reflectance = 0.15,
			})
			Effects.Tween(crystal, 0.14, { Size = Vector3.new(w, h, w * 1.3), CFrame = tilt * CFrame.new(0, h / 2, 0) }, Enum.EasingStyle.Back)
			table.insert(crystals, crystal)
		end
		Effects.GroundMark(g, 2.6, PAL.Ice.Light, 2, { Transparency = 0.35 })
		Effects.SmokePuff(pos - Vector3.new(0, 1.5, 0), 5, PAL.Ice.Light, 0.8, { Rise = 0.5 })
		Effects.Burst(pos, 10, {
			Texture = TEX.Sparkle,
			Color = Seq(WHITE, PAL.Ice.Light),
			Speed = NumberRange.new(3, 9),
			Lifetime = NumberRange.new(0.4, 0.8),
			Size = NSeq(0.5, 0),
			Drag = 2,
		})
		task.delay(1.6, function()
			for _, c in crystals do
				if c.Parent then
					Effects.Tween(c, 0.25, { Transparency = 1, Size = c.Size * 0.3 })
					Effects.Clean(c, 0.3)
				end
			end
			Effects.Sound("Ice", pos, { Volume = 0.5 })
		end)
		for _, c in crystals do
			Effects.Clean(c, 2.2)
		end
	elseif effect == "Electric" then
		for _ = 1, 3 do
			local a = pos + Vector3.new(rng:NextNumber(-1.8, 1.8), rng:NextNumber(-2, 2), rng:NextNumber(-1.8, 1.8))
			local b = pos + Vector3.new(rng:NextNumber(-1.8, 1.8), rng:NextNumber(-2, 2), rng:NextNumber(-1.8, 1.8))
			Effects.Bolt(a, b, { Color = PAL.Lightning.Glow, Width = 0.1, Duration = 0.18, Segments = 4, Jitter = 0.6 })
		end
		Effects.Sparks(point, 10, PAL.Lightning.Glow, 24, { Gravity = 10 })
		Effects.HitFlash(victim, C(200, 214, 255), 0.3)
	elseif effect == "Water" then
		Effects.Sparks(point, 12, PAL.Water.Light, 22, {
			Colors = Seq(PAL.Water.Foam, PAL.Water.Light),
			Gravity = 50,
			MaxLife = 0.6,
			Size = 0.4,
			Brightness = 1,
		})
		Effects.SmokePuff(point, 3, PAL.Water.Foam, 0.7, { Life = 0.7 })
	elseif effect == "Shadow" or effect == "Void" then
		Effects.Burst(pos, 12, {
			Texture = TEX.Smoke,
			Color = Seq(PAL.Shadow.Dark, PAL.Shadow.Ink),
			LightEmission = 0,
			LightInfluence = 0.3,
			Speed = NumberRange.new(3, 9),
			Lifetime = NumberRange.new(0.5, 0.9),
			Size = NSeq(1.6, 3.8),
			Transparency = NSeq(0.1, 0.5, 1),
			Drag = 3,
		})
		Effects.Sparks(point, 6, PAL.Shadow.Accent, 18, { Gravity = -4, MaxLife = 0.5 })
	elseif effect == "Holy" then
		Effects.Burst(pos, 14, {
			Texture = TEX.Sparkle,
			Color = Seq(WHITE, PAL.Holy.Gold),
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(60, 60),
			Speed = NumberRange.new(4, 10),
			Lifetime = NumberRange.new(0.6, 1.1),
			Size = NSeq(0.6, 0),
			Acceleration = Vector3.new(0, 6, 0),
			Drag = 2,
		})
		Effects.Glow(pos, PAL.Holy.Gold, 7, 0.35)
	elseif effect == "Slash" then
		local cf = CFrame.new(point) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6))
		local half = cf.LookVector * rng:NextNumber(3, 4.5)
		Effects.TrailLine(point - half, point + half, EFFECT_COLORS.Slash, 0.3, 0.7, { LightEmission = 0.3 })
	elseif effect == "Rock" then
		Effects.Rocks(pos - Vector3.new(0, 2, 0), 4, { MaxUp = 30, Spread = 14, MaxSize = 1.1 })
		Effects.Dust(Effects.Ground(pos), 4, 0.9)
	elseif effect == "Wind" then
		Effects.Burst(pos, 8, {
			Texture = TEX.Smoke,
			Color = ColorSequence.new(PAL.Wind.White),
			LightEmission = 0.15,
			LightInfluence = 0.7,
			Speed = NumberRange.new(8, 14),
			Lifetime = NumberRange.new(0.3, 0.5),
			Size = NSeq(1, 3),
			Transparency = NSeq(0.5, 0.75, 1),
			Drag = 4,
			RotSpeed = NumberRange.new(-200, 200),
		})
		Effects.Dust(Effects.Ground(pos), 4, 0.9)
	end
end

-- Oeffentliche Effekte ---------------------------------------------------------------

local SWIPE = C(236, 240, 246)

function CombatVFX.M1(p: { [string]: any })
	local caster = p.Caster :: Model?
	local root = Effects.Root(caster)
	if not caster or not root then
		return
	end
	local combo = p.Combo or 1
	if combo == 4 then
		Poser.Sequence(caster, { { P.HeavyWindup, 0.07 }, { P.HeavyStrike, 0.18 } }, 0.2)
	else
		local pose = if combo == 1 then P.PunchRight elseif combo == 2 then P.HookLeft else P.Uppercut
		Poser.Sequence(caster, { { pose, 0.16 } }, 0.15)
	end
	Effects.Sound(if combo == 4 then "Whoosh" else "Swing", root.Position, { Volume = 0.8 })

	-- Brusthoehe, leicht vor dem Koerper
	local base = root.CFrame * CFrame.new(0, 0.5, -0.6)
	-- Die Sicheln sind schraeg gestellt und drehen sich zur Kamera, damit sie aus der
	-- Schulterperspektive gut lesbar bleiben
	local swipe = { Sweep = 0.08, LightEmission = 0.45, Transparency = 0.2, FaceCamera = true }
	if combo == 1 then
		-- rechter Haken: schraeger Bogen von rechts oben nach links
		Effects.TrailSlash(base * CFrame.Angles(0, 0, math.rad(-30 + rng:NextNumber(-6, 6))), 3, 140, SWIPE, 0.22, 0.9, swipe)
	elseif combo == 2 then
		-- linker Haken: gespiegelt
		Effects.TrailSlash(base * CFrame.Angles(0, 0, math.rad(30 + rng:NextNumber(-6, 6))), 3, -140, SWIPE, 0.22, 0.9, swipe)
	elseif combo == 3 then
		-- Aufwaertshaken: von rechts unten nach links oben
		Effects.TrailSlash(base * CFrame.Angles(0, 0, math.rad(-60)), 2.8, 150, SWIPE, 0.24, 0.9, swipe)
	else
		-- Finisher: breite Doppel-Sichel, Luftstoss nach vorne, Staub am Boden
		local slashCF = base * CFrame.Angles(0, 0, math.rad(-18))
		Effects.TrailSlash(slashCF, 4.2, 200, SWIPE, 0.32, 1.5, { Sweep = 0.1, LightEmission = 0.55, Transparency = 0.1, FaceCamera = true })
		task.delay(0.03, function()
			Effects.TrailSlash(slashCF * CFrame.Angles(0, 0, math.rad(12)), 3.2, 170, C(255, 226, 170), 0.26, 0.7, {
				Sweep = 0.1,
				LightEmission = 0.8,
				Transparency = 0.25,
				NoCore = true,
				FaceCamera = true,
			})
		end)
		task.delay(0.1, function()
			if not root.Parent then
				return
			end
			local look = flat(root.CFrame.LookVector)
			local front = root.Position + look * 3.2
			Effects.Shockwave(front, 7, WHITE, 0.25, look)
			Effects.Burst(front, 6, {
				Texture = TEX.Smoke,
				Color = ColorSequence.new(PAL.Wind.White),
				LightEmission = 0.1,
				LightInfluence = 0.8,
				Speed = NumberRange.new(10, 18),
				SpreadAngle = Vector2.new(30, 30),
				Lifetime = NumberRange.new(0.25, 0.4),
				Size = NSeq(1, 2.6),
				Transparency = NSeq(0.55, 0.8, 1),
				Drag = 5,
			})
			local g = Effects.Ground(root.Position)
			Effects.BurstDir(g + Vector3.new(0, 0.4, 0), -look + Vector3.new(0, 0.3, 0), 6, {
				Texture = TEX.Smoke,
				Color = ColorSequence.new(Effects.DustColor(g)),
				LightEmission = 0,
				LightInfluence = 0.85,
				Speed = NumberRange.new(6, 12),
				SpreadAngle = Vector2.new(45, 12),
				Lifetime = NumberRange.new(0.5, 0.8),
				Size = NSeq(1.2, 3),
				Transparency = NSeq(0.4, 0.7, 1),
				Drag = 4,
			})
		end)
	end
end

function CombatVFX.Hit(p: { [string]: any })
	local victim = p.Victim :: Model?
	local root = Effects.Root(victim)
	if not victim or not root then
		return
	end
	local attacker = p.Attacker :: Model?
	local attackerRoot = Effects.Root(attacker)
	local effect = p.Effect :: string?
	local color: Color3 = p.Color or (if effect then EFFECT_COLORS[effect] else nil) or C(255, 226, 170)
	local blocked = p.Blocked == true
	local heavy = p.Heavy == true
	local amount = tonumber(p.Amount) or 0

	-- Trefferpunkt: Vorderseite des Opfers (Richtung Angreifer), Schlagrichtung = vom Angreifer weg
	local pos = root.Position + Vector3.new(0, 0.4, 0)
	local dir = if attackerRoot then flat(pos - attackerRoot.Position, -root.CFrame.LookVector) else flat(-root.CFrame.LookVector)
	local point = pos - dir * 0.9

	if blocked then
		-- Funken an der Deckung, metallischer Glanz
		hitCore(point, 3, C(255, 236, 190))
		Effects.Sparks(point, 10, C(255, 214, 140), 26, { Dir = -dir, Spread = Vector2.new(70, 70), Gravity = 40, MaxLife = 0.35 })
		Effects.Burst(point, 1, {
			Texture = TEX.Sparkle,
			Color = ColorSequence.new(WHITE),
			Speed = NumberRange.new(0),
			Lifetime = NumberRange.new(0.16),
			Size = NSeq(3.2, 0),
			Rotation = NumberRange.new(0, 45),
			RotSpeed = NumberRange.new(90),
			ZOffset = 2,
		})
		Effects.SmokePuff(point, 2, C(220, 220, 214), 0.5, { Life = 0.5 })
		Effects.Sound("Block", pos, { Volume = 0.7 })
		damageNumber(pos, amount, C(170, 200, 230), false, "BLOCK " .. formatAmount(amount))
		if isLocal(victim) then
			Effects.Shake(0.35, 0.12)
		end
		return
	end

	Effects.HitFlash(victim, WHITE, if heavy then 0.2 else 0.12)
	hitCore(point, if heavy then 6 else 3.6, C(255, 232, 190))
	Effects.Sparks(point, if heavy then 14 else 7, C(255, 220, 150), if heavy then 42 else 28, {
		Dir = dir,
		Spread = Vector2.new(55, 55),
		Gravity = 25,
		MaxLife = if heavy then 0.4 else 0.25,
	})
	Effects.SmokePuff(point, if heavy then 4 else 2, C(232, 230, 224), if heavy then 0.9 else 0.55, { Dir = dir, Life = 0.6 })

	if heavy then
		impactStar(point, 3.4, C(255, 246, 225))
		local cam = workspace.CurrentCamera
		local toCam = if cam then cam.CFrame.Position - point else Vector3.yAxis
		Effects.Shockwave(point, 9, C(255, 246, 230), 0.22, toCam)
		-- Staub unter den Fuessen des Getroffenen
		local g = Effects.Ground(root.Position)
		if root.Position.Y - g.Y < 6 then
			Effects.DustRing(g, 4.5, nil, { Count = 8, Life = 0.7 })
		end
		Effects.HitStop({ victim, attacker }, 0.06)
	end
	if effect then
		overlay(effect, victim, root, point, dir)
	end
	Effects.Sound(if heavy then "HeavyPunch" else "Punch", pos)

	local numberColor = if heavy then C(255, 196, 64) elseif effect == "Burn" or effect == "Water" or effect == "Void" then color else WHITE
	damageNumber(pos, amount, numberColor, heavy)

	local involved = isLocal(victim) or isLocal(attacker)
	if heavy and involved and effect == nil then
		-- M1-Finisher: kurzer Impact-Frame fuer die Beteiligten
		Effects.ImpactFrame(0.05, 0.9)
	end
	if isLocal(victim) then
		Effects.Vignette(C(200, 30, 36), if heavy then 0.55 else 0.3, if heavy then 0.38 else 0.22)
		Effects.Shake(if heavy then 1.8 else 0.6, if heavy then 0.3 else 0.2)
	elseif isLocal(attacker) then
		Effects.Shake(if heavy then 1.1 else 0.3, if heavy then 0.22 else 0.12)
	end
end

-- schwache Schluessel: zerstoerte Charaktere werden nicht festgehalten
local shields: { [Model]: BasePart } = setmetatable({}, { __mode = "k" }) :: any

local function removeShield(caster: Model, fade: boolean)
	local existing = shields[caster]
	shields[caster] = nil
	if not existing then
		return
	end
	if fade and existing.Parent then
		Effects.Tween(existing, 0.12, { Size = existing.Size * 0.6, Transparency = 1 })
		Effects.Clean(existing, 0.14)
	else
		existing:Destroy()
	end
end

function CombatVFX.Block(p: { [string]: any })
	local caster = p.Caster :: Model?
	local root = Effects.Root(caster)
	if not caster or not root then
		return
	end
	removeShield(caster, not p.On)
	if p.On then
		Poser.Apply(caster, P.Block, 0.1)
		-- Dezente, gewoelbte Schutzlinse vor den Armen (ForceField-Material), keine riesige Blase
		local shield = Effects.Part({
			Size = Vector3.new(1, 1, 0.4),
			Material = Enum.Material.ForceField,
			Color = C(180, 214, 255),
			Transparency = 0,
			Anchored = false,
			Massless = true,
			CFrame = root.CFrame * CFrame.new(0, 0.4, -1.5),
			Parent = caster,
		})
		Make("SpecialMesh", { MeshType = Enum.MeshType.Sphere, Parent = shield })
		Make("Weld", { Part0 = root, Part1 = shield, C0 = CFrame.new(0, 0.4, -1.5), Parent = shield })
		Effects.Tween(shield, 0.14, { Size = Vector3.new(4.6, 5, 1.1) }, Enum.EasingStyle.Back)
		shields[caster] = shield
		-- Glanz an beiden Haenden
		for _, side in { "Right", "Left" } do
			local handPos = Effects.HandPosition(caster, side)
			if handPos then
				Effects.Burst(handPos, 1, {
					Texture = TEX.Sparkle,
					Color = ColorSequence.new(WHITE),
					Speed = NumberRange.new(0),
					Lifetime = NumberRange.new(0.18),
					Size = NSeq(2.2, 0),
					Rotation = NumberRange.new(0, 45),
					RotSpeed = NumberRange.new(120),
					ZOffset = 1,
				})
			end
		end
		-- Abstuetzen: etwas Staub an den Fuessen
		local g = Effects.Ground(root.Position)
		if root.Position.Y - g.Y < 5 then
			Effects.Dust(g, 3, 0.6)
		end
		Effects.Sound("Block", root.Position, { Volume = 0.4, Pitch = 1.3 })
	else
		Poser.Reset(caster, 0.15)
	end
end

function CombatVFX.GuardBreak(p: { [string]: any })
	local victim = p.Victim :: Model?
	local root = Effects.Root(victim)
	if not victim or not root then
		return
	end
	removeShield(victim, false)
	local pos = root.Position + Vector3.new(0, 0.4, 0)
	local front = pos + root.CFrame.LookVector * 1.4
	-- Die Deckung zerspringt in Glas-Splitter
	for _ = 1, 10 do
		local s = rng:NextNumber(0.35, 0.8)
		local shard = Effects.Wedge({
			Size = Vector3.new(0.08, s * 1.4, s),
			CFrame = CFrame.new(front + Vector3.new(rng:NextNumber(-1.6, 1.6), rng:NextNumber(-1.4, 1.6), rng:NextNumber(-0.4, 0.4)))
				* CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)),
			Material = Enum.Material.Glass,
			Color = C(196, 224, 255),
			Transparency = 0.25,
			Reflectance = 0.25,
			Anchored = false,
			CanCollide = true,
			CollisionGroup = "VFX",
		})
		local out = root.CFrame.LookVector * rng:NextNumber(8, 18)
		shard.AssemblyLinearVelocity = out + Vector3.new(rng:NextNumber(-16, 16), rng:NextNumber(8, 22), rng:NextNumber(-16, 16))
		shard.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12))
		Effects.Tween(shard, 0.6, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.4)
		Effects.Clean(shard, 1.1)
	end
	hitCore(front, 7, C(220, 236, 255))
	Effects.Burst(front, 12, {
		Texture = TEX.Sparkle,
		Color = Seq(WHITE, C(196, 224, 255)),
		Speed = NumberRange.new(8, 18),
		Lifetime = NumberRange.new(0.3, 0.6),
		Size = NSeq(0.6, 0),
		Drag = 3,
	})
	Effects.Shockwave(front, 10, C(220, 236, 255), 0.3, root.CFrame.LookVector)
	impactStar(front, 4, WHITE)
	Poser.Sequence(victim, { { P.Stagger, 0.5 } }, 0.3)
	local g = Effects.Ground(root.Position)
	Effects.DustRing(g, 4, nil, { Count = 8, Life = 0.7 })
	Effects.Sound("GuardBreak", pos)
	damageNumber(pos + Vector3.new(0, 2, 0), 0, C(255, 120, 64), true, "GUARD BREAK!")
	if isLocal(victim) then
		Effects.Shake(1.6, 0.35)
		Effects.ImpactFrame(0.05, 0.8)
		Effects.Vignette(C(200, 30, 36), 0.5, 0.35)
	end
end

function CombatVFX.Dash(p: { [string]: any })
	local caster = p.Caster :: Model?
	local root = Effects.Root(caster)
	if not caster or not root then
		return
	end
	local dir: Vector3 = flat(p.Direction or root.CFrame.LookVector, flat(root.CFrame.LookVector))
	Effects.Sound("Dash", root.Position)
	-- Ein dezentes, helles Nachbild (keine Neon-Kopie)
	Effects.Afterimage(caster, C(226, 232, 240), 0.28, 0.62)
	task.delay(0.07, function()
		Effects.Afterimage(caster, C(226, 232, 240), 0.24, 0.75)
	end)
	-- Staub beim Abstossen (fliegt nach hinten weg)
	local g = Effects.Ground(root.Position)
	local onGround = root.Position.Y - g.Y < 5
	local dust = Effects.DustColor(g)
	if onGround then
		Effects.BurstDir(g + Vector3.new(0, 0.4, 0), -dir + Vector3.new(0, 0.35, 0), 8, {
			Texture = TEX.Smoke,
			Color = ColorSequence.new(dust),
			LightEmission = 0,
			LightInfluence = 0.85,
			Speed = NumberRange.new(8, 16),
			SpreadAngle = Vector2.new(35, 15),
			Lifetime = NumberRange.new(0.45, 0.8),
			Size = NSeq(1.2, 3.4),
			Transparency = NSeq(0.35, 0.7, 1),
			Drag = 4,
			RotSpeed = NumberRange.new(-60, 60),
		})
	end
	-- Windstreifen am Koerper (drei duenne Trails)
	local offsets = { Vector3.new(1.1, 0.9, 0.3), Vector3.new(-1.1, 0.4, 0.3), Vector3.new(0.2, 1.8, 0.4) }
	for _, off in offsets do
		local a0 = Make("Attachment", { Position = off + Vector3.new(0, 0.07, 0), Parent = root })
		local a1 = Make("Attachment", { Position = off - Vector3.new(0, 0.07, 0), Parent = root })
		local trail = Make("Trail", {
			Attachment0 = a0,
			Attachment1 = a1,
			Color = ColorSequence.new(WHITE),
			Transparency = NSeq(0.35, 1),
			WidthScale = NSeq(1, 0.2),
			Lifetime = 0.2,
			LightEmission = 0.3,
			LightInfluence = 0.4,
			FaceCamera = true,
			Parent = root,
		})
		task.delay(0.25, function()
			trail.Enabled = false
		end)
		Effects.Clean(trail, 0.5)
		Effects.Clean(a0, 0.5)
		Effects.Clean(a1, 0.5)
	end
	-- Rutsch-Staub am Boden waehrend des Dashs
	if onGround then
		local skidAtt = Make("Attachment", { Position = Vector3.new(0, -2.6, 0), Parent = root })
		Effects.Stream(skidAtt, 0.22, {
			Texture = TEX.Smoke,
			Rate = 28,
			Color = ColorSequence.new(dust),
			LightEmission = 0,
			LightInfluence = 0.85,
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(60, 60),
			Speed = NumberRange.new(1, 3),
			Lifetime = NumberRange.new(0.4, 0.7),
			Size = NSeq(0.8, 2.2),
			Transparency = NSeq(0.45, 0.75, 1),
		})
		Effects.Clean(skidAtt, 1.2)
	end
end

function CombatVFX.Death(p: { [string]: any })
	local character = p.Character :: Model?
	local root = Effects.Root(character)
	if not character or not root then
		return
	end
	local pos = root.Position
	local parts: { BasePart } = {}
	local decals: { Decal } = {}
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			local bp = d :: BasePart
			if bp.Transparency < 1 then
				table.insert(parts, bp)
			end
		elseif d:IsA("Decal") then
			table.insert(decals, d :: Decal)
		end
	end
	-- Der Koerper zerfaellt zu Asche: Staub + Glut aus jedem Teil (begrenzt)
	for i, part in parts do
		if i > 14 then
			break
		end
		emitAt(part.Position, 2, {
			{ 3, {
				Texture = TEX.Smoke,
				Color = Seq(C(206, 202, 196), C(96, 92, 90)),
				LightEmission = 0,
				LightInfluence = 0.8,
				Speed = NumberRange.new(1, 4),
				Lifetime = NumberRange.new(0.8, 1.4),
				Size = NSeq(1, 2.6),
				Transparency = NSeq(0.3, 0.6, 1),
				Acceleration = Vector3.new(0, 4, 0),
				Drag = 2,
			} },
			{ 3, {
				Texture = TEX.Sparks,
				Color = Seq(WHITE, C(255, 220, 170)),
				Speed = NumberRange.new(1, 3),
				Lifetime = NumberRange.new(0.8, 1.4),
				Size = NSeq(0.18, 0),
				Acceleration = Vector3.new(0, 7, 0),
				Drag = 1,
			} },
		})
	end
	-- Langsam ausblenden, dann ganz verstecken
	Effects.Animate(0.45, function(a)
		for _, part in parts do
			if part.Parent then
				part.LocalTransparencyModifier = a
			end
		end
		for _, decal in decals do
			if decal.Parent then
				decal.LocalTransparencyModifier = a
			end
		end
	end, function()
		Effects.SetCharacterVisible(character, false)
	end)
	-- Ein heller Funke steigt auf (Seele), Staubring am Boden
	Effects.Burst(pos, 10, {
		Texture = TEX.Sparkle,
		Color = Seq(WHITE, C(255, 236, 200)),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(25, 25),
		Speed = NumberRange.new(4, 10),
		Acceleration = Vector3.new(0, 6, 0),
		Lifetime = NumberRange.new(0.8, 1.4),
		Size = NSeq(0.6, 0),
		Drag = 1,
	})
	Effects.Glow(pos, C(255, 240, 214), 6, 0.6)
	local g = Effects.Ground(pos)
	if pos.Y - g.Y < 8 then
		Effects.DustRing(g, 4.5, nil, { Count = 8 })
	end
	Effects.Light(pos, C(255, 236, 200), 18, 2, 0.8)
	Effects.Sound("Void", pos, { Volume = 0.5, Pitch = 1.6 })
end

-- Feuerwerks-Rakete mit Leuchtspur, die oben zerplatzt (feste, klassische Farben)
local FIREWORK_COLORS = { C(255, 206, 84), C(255, 255, 255), C(255, 110, 90), C(120, 190, 255) }

local function firework(from: Vector3, to: Vector3, color: Color3)
	local rocket = Effects.Ball(CFrame.new(from), 0.4, C(255, 236, 190))
	Effects.Trail(rocket, Seq(C(255, 236, 190), C(255, 170, 80)), 0.35, 0.35)
	local flight = 0.7
	Effects.Tween(rocket, flight, { CFrame = CFrame.new(to) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	Effects.Clean(rocket, flight + 0.4)
	task.delay(flight, function()
		rocket.Transparency = 1
		Effects.Burst(to, 34, {
			Texture = TEX.Sparks,
			Color = Seq(WHITE, color),
			Speed = NumberRange.new(14, 22),
			Lifetime = NumberRange.new(0.9, 1.4),
			Acceleration = Vector3.new(0, -12, 0),
			Drag = 1.6,
			Size = NSeq(0.55, 0.3, 0),
			Brightness = 2,
		})
		Effects.Burst(to, 10, {
			Texture = TEX.Sparkle,
			Color = Seq(WHITE, color),
			Speed = NumberRange.new(6, 12),
			Lifetime = NumberRange.new(0.6, 1),
			Size = NSeq(1, 0),
			Drag = 2,
		})
		Effects.Light(to, color, 40, 3, 0.6)
		Effects.Sound("Explosion", to, { Volume = 0.35, Pitch = 1.8 })
	end)
end

function CombatVFX.Victory(p: { [string]: any })
	local character = p.Character :: Model?
	local root = Effects.Root(character)
	if not character or not root then
		return
	end
	local pos = root.Position
	local gold = PAL.Holy.Gold
	Poser.Sequence(character, { { P.Victory, 3 } }, 0.4)
	local g = Effects.Ground(pos)
	-- Weicher Lichtstrahl von oben (Beam mit Glow-Textur statt Neon-Zylinder)
	local beamHolder = Effects.Part({ Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(g) })
	local bottom = Make("Attachment", { Position = Vector3.new(0, 0.2, 0), Parent = beamHolder })
	local top = Make("Attachment", { Position = Vector3.new(0, 70, 0), Parent = beamHolder })
	local beam = Make("Beam", {
		Attachment0 = bottom,
		Attachment1 = top,
		Texture = TEX.Glow,
		TextureMode = Enum.TextureMode.Stretch,
		Color = ColorSequence.new(C(255, 236, 180)),
		Width0 = 7,
		Width1 = 12,
		LightEmission = 1,
		LightInfluence = 0,
		FaceCamera = true,
		Transparency = NSeq(0.55, 0.75, 1),
		Parent = beamHolder,
	})
	Effects.Animate(3.2, function(a)
		local fadeIn = math.clamp(a / 0.1, 0, 1)
		local fadeOut = math.clamp((1 - a) / 0.5, 0, 1)
		local k = 1 - fadeIn * fadeOut
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55 + 0.45 * k),
			NumberSequenceKeypoint.new(0.5, 0.75 + 0.25 * k),
			NumberSequenceKeypoint.new(1, 1),
		})
	end, function()
		beamHolder:Destroy()
	end)
	Effects.Clean(beamHolder, 4)
	-- Staubring + goldener Glitzer, der aufsteigt
	Effects.DustRing(g, 9, nil, { Count = 14 })
	local sparkArea = Effects.Part({ Transparency = 1, Size = Vector3.new(6, 0.2, 6), CFrame = CFrame.new(g + Vector3.new(0, 0.5, 0)) })
	Effects.Clean(sparkArea, 4.5)
	Effects.Stream(sparkArea, 2.4, {
		Texture = TEX.Sparkle,
		Rate = 18,
		Color = Seq(WHITE, gold),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(10, 10),
		Speed = NumberRange.new(3, 7),
		Lifetime = NumberRange.new(1, 1.6),
		Size = NSeq(0.5, 0),
		Shape = Enum.ParticleEmitterShape.Box,
	})
	-- Konfetti (kleine Papierstreifen mit Physik)
	local confettiColors = { gold, WHITE, C(255, 110, 90), C(120, 190, 255), C(130, 210, 110) }
	for i = 1, math.floor(30 * Effects.Quality) do
		local c = confettiColors[(i % #confettiColors) + 1]
		local piece = Effects.Part({
			Size = Vector3.new(0.3, 0.04, 0.55),
			CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-1, 1), 3, rng:NextNumber(-1, 1)))
				* CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)),
			Material = Enum.Material.SmoothPlastic,
			Color = c,
			Anchored = false,
			CanCollide = true,
			CollisionGroup = "VFX",
		})
		piece.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-16, 16), rng:NextNumber(24, 40), rng:NextNumber(-16, 16))
		piece.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-14, 14), rng:NextNumber(-14, 14), rng:NextNumber(-14, 14))
		Effects.Tween(piece, 0.5, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 2.6)
		Effects.Clean(piece, 3.2)
	end
	-- Feuerwerk
	for i = 1, 4 do
		task.delay(0.25 + i * 0.35, function()
			local a = rng:NextNumber(0, TAU)
			local from = g + Vector3.new(math.cos(a) * 8, 0.5, math.sin(a) * 8)
			local to = pos + Vector3.new(math.cos(a) * 12, rng:NextNumber(16, 24), math.sin(a) * 12)
			firework(from, to, FIREWORK_COLORS[(i - 1) % #FIREWORK_COLORS + 1])
		end)
	end
	Effects.Light(root, gold, 24, 3, 3)
end

function CombatVFX.Unlock(p: { [string]: any })
	local character = p.Character :: Model?
	local root = Effects.Root(character)
	if not character or not root then
		return
	end
	local pos = root.Position
	local center = pos + Vector3.new(0, 6, 0)
	local purple = C(130, 70, 220)
	local orange = C(255, 150, 60)
	-- Dunkler Kern mit Akkretions-Wirbel, der Partikel einsaugt
	local orb = Effects.Ball(CFrame.new(center), 0.5, Color3.new(0, 0, 0), { Material = Enum.Material.SmoothPlastic })
	Effects.Tween(orb, 0.8, { Size = Vector3.new(3.6, 3.6, 3.6) }, Enum.EasingStyle.Back)
	Effects.Tween(orb, 0.22, { Size = Vector3.new(0.1, 0.1, 0.1) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 1.25)
	Effects.Clean(orb, 1.6)
	local sphere = Effects.Ball(CFrame.new(center), 12, purple, { Transparency = 1 })
	Effects.Stream(sphere, 1.2, {
		Texture = TEX.Sparks,
		Rate = 60,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Speed = NumberRange.new(10, 14),
		Lifetime = NumberRange.new(0.4, 0.5),
		Color = Seq(orange, purple),
		Size = NSeq(0.25, 0.5),
		SpreadAngle = Vector2.new(0, 0),
	})
	Effects.Clean(sphere, 2)
	local _, swirlAtt = Effects.Anchor(center, 2)
	Effects.Stream(swirlAtt, 1.2, {
		Texture = TEX.Vortex,
		Rate = 6,
		Color = Seq(orange, purple),
		Speed = NumberRange.new(0),
		Lifetime = NumberRange.new(0.6, 0.8),
		Size = NSeq(3, 6),
		Transparency = NSeq(1, 0.4, 1),
		RotSpeed = NumberRange.new(200, 300),
		LightEmission = 0.8,
		ZOffset = -1,
	})
	Effects.Sound("Charge", center, { Pitch = 0.7 })
	task.delay(1.45, function()
		Effects.Flash(center, C(230, 210, 255), 9, 0.25)
		Effects.Sparks(center, 34, orange, 44, { Gravity = 20, MaxLife = 0.8, Colors = Seq(WHITE, orange, purple) })
		Effects.SmokePuff(center, 10, C(46, 30, 70), 2, { Life = 1.4 })
		Effects.Shockwave(center, 22, purple, 0.45)
		Effects.Light(center, purple, 40, 5, 0.6)
		Effects.DustRing(Effects.Ground(pos), 10)
		Effects.Sound("Void", pos)
		if isLocal(character) then
			Effects.Shake(1.2, 0.35)
		end
	end)
end

return CombatVFX
