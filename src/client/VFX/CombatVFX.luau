-- Effekte fuer Grundkampf: Schlaege, Treffer, Blocken, Guard Break, Dash, Tod, Sieg.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Make = require(Shared:WaitForChild("Make"))

local VFX = script.Parent :: Instance
local Effects = require(VFX:WaitForChild("Effects"))
local Poser = require(VFX:WaitForChild("Poser"))

local CombatVFX = {}

local player = Players.LocalPlayer
local rng = Effects.Random
local TEX = Effects.Textures
local P = Poser.Poses

local EFFECT_COLORS: { [string]: Color3 } = {
	Fire = Color3.fromRGB(255, 120, 30),
	Burn = Color3.fromRGB(255, 90, 20),
	Ice = Color3.fromRGB(140, 220, 255),
	Electric = Color3.fromRGB(120, 220, 255),
	Water = Color3.fromRGB(60, 160, 255),
	Shadow = Color3.fromRGB(150, 50, 255),
	Holy = Color3.fromRGB(255, 225, 120),
	Void = Color3.fromRGB(160, 70, 255),
	Slash = Color3.fromRGB(255, 40, 60),
	Rock = Color3.fromRGB(190, 150, 110),
	Wind = Color3.fromRGB(220, 250, 255),
}

local function isLocal(character: Model?): boolean
	return character ~= nil and character == player.Character
end

-- Schadenszahlen -------------------------------------------------------------------

local function damageNumber(position: Vector3, amount: number, color: Color3, big: boolean, label: string?)
	local anchor = Effects.Anchor(position + Vector3.new(rng:NextNumber(-1.2, 1.2), rng:NextNumber(0.5, 1.5), rng:NextNumber(-1.2, 1.2)), 1.4)
	local gui = Make("BillboardGui", {
		Size = UDim2.fromOffset(160, 70),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 140,
		Parent = anchor,
	})
	local text = Make("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = label or tostring(math.floor(amount * 10 + 0.5) / 10),
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = color,
		Parent = gui,
	})
	Make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2.5, Parent = text })
	local scale = Make("UIScale", { Scale = if big then 1.9 else 1.3, Parent = text })
	Effects.Tween(scale, 0.22, { Scale = if big then 1.1 else 0.8 }, Enum.EasingStyle.Back)
	Effects.Tween(gui, 1.1, { StudsOffset = Vector3.new(0, 3, 0) }, Enum.EasingStyle.Quad)
	Effects.Tween(text, 0.5, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.7)
end

-- Effekt-Overlays auf dem Getroffenen ---------------------------------------------

local function overlay(effect: string, victim: Model, root: BasePart)
	local pos = root.Position
	if effect == "Fire" or effect == "Burn" then
		Effects.BurstOn(root, if effect == "Fire" then 26 else 10, {
			Texture = TEX.Fire,
			Color = Effects.Seq(Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 90, 20), Color3.fromRGB(120, 20, 10)),
			Speed = NumberRange.new(4, 10),
			Lifetime = NumberRange.new(0.4, 0.8),
			Size = Effects.NSeq(1.6, 3, 0),
			Acceleration = Vector3.new(0, 18, 0),
			SpreadAngle = Vector2.new(60, 60),
		})
	elseif effect == "Ice" then
		-- Eiskristalle umschliessen die Beine
		local crystals = {}
		for i = 1, 7 do
			local a = (i / 7) * math.pi * 2
			local c = Effects.Part({
				Size = Vector3.new(0.9, rng:NextNumber(2.5, 4), 0.9),
				CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 1.3, -2.2, math.sin(a) * 1.3))
					* CFrame.Angles(rng:NextNumber(-0.4, 0.4), a, rng:NextNumber(-0.4, 0.4)),
				Material = Enum.Material.Glass,
				Color = Color3.fromRGB(170, 230, 255),
				Transparency = 0.25,
				Reflectance = 0.2,
			})
			table.insert(crystals, c)
		end
		Effects.Burst(pos, 18, {
			Texture = TEX.Sparkle,
			Color = ColorSequence.new(Color3.fromRGB(200, 240, 255)),
			Speed = NumberRange.new(4, 12),
			Size = Effects.NSeq(0.8, 0),
		})
		task.delay(1.6, function()
			for _, c in crystals do
				Effects.Tween(c, 0.25, { Transparency = 1, Size = c.Size * 0.3 })
				Effects.Clean(c, 0.3)
			end
			Effects.Sound("Ice", pos, { Volume = 0.6 })
		end)
	elseif effect == "Electric" then
		for _ = 1, 3 do
			local a = pos + Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(-2, 2), rng:NextNumber(-2, 2))
			local b = pos + Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(-2, 2), rng:NextNumber(-2, 2))
			Effects.Bolt(a, b, { Color = EFFECT_COLORS.Electric, Width = 0.15, Duration = 0.2, Segments = 4 })
		end
		Effects.HitFlash(victim, EFFECT_COLORS.Electric, 0.35)
	elseif effect == "Water" then
		Effects.Burst(pos, 14, {
			Texture = TEX.Sparkle,
			Color = Effects.Seq(Color3.fromRGB(200, 240, 255), Color3.fromRGB(40, 140, 255)),
			Speed = NumberRange.new(8, 16),
			Acceleration = Vector3.new(0, -40, 0),
			Size = Effects.NSeq(0.7, 0.2),
		})
	elseif effect == "Shadow" or effect == "Void" then
		Effects.Burst(pos, 16, {
			Texture = TEX.Smoke,
			Color = ColorSequence.new(if effect == "Void" then Color3.fromRGB(90, 30, 160) else Color3.fromRGB(40, 10, 70)),
			LightEmission = 0.3,
			Speed = NumberRange.new(3, 8),
			Size = Effects.NSeq(1.5, 4),
			Transparency = Effects.NSeq(0.2, 1),
		})
	elseif effect == "Holy" then
		local pillar = Effects.Part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(30, 3, 3),
			CFrame = CFrame.new(pos + Vector3.new(0, 12, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = EFFECT_COLORS.Holy,
			Transparency = 0.3,
		})
		Effects.Tween(pillar, 0.5, { Transparency = 1, Size = Vector3.new(30, 0.2, 0.2) })
		Effects.Clean(pillar, 0.55)
	elseif effect == "Slash" then
		local cf = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6))
		Effects.Line(cf, rng:NextNumber(6, 9), EFFECT_COLORS.Slash, 0.3, 0.18)
	elseif effect == "Rock" then
		Effects.Rocks(pos - Vector3.new(0, 2, 0), 4, { MaxUp = 30, Spread = 14 })
	elseif effect == "Wind" then
		Effects.GroundRing(pos, 1, 5, EFFECT_COLORS.Wind, 0.3, 0.5, { Transparency = 0.4 })
	end
end

-- Oeffentliche Effekte ---------------------------------------------------------------

function CombatVFX.M1(p: { [string]: any })
	local caster = p.Caster :: Model?
	local root = Effects.Root(caster)
	if not caster or not root then
		return
	end
	local combo = p.Combo or 1
	local pose = if combo == 1 then P.PunchRight elseif combo == 2 then P.PunchLeft elseif combo == 3 then P.Uppercut else P.HeavyStrike
	if combo == 4 then
		Poser.Sequence(caster, { { P.HeavyWindup, 0.07 }, { pose, 0.18 } }, 0.2)
	else
		Poser.Sequence(caster, { { pose, 0.16 } }, 0.15)
	end
	Effects.Sound(if combo == 4 then "Whoosh" else "Swing", root.Position, { Volume = 0.8 })
	-- Luftschnitt vor dem Charakter
	local front = root.CFrame * CFrame.new(0, 0.5, -2.2)
	local tilt = if combo == 1 then -25 elseif combo == 2 then 25 elseif combo == 3 then 70 else 0
	local radius = if combo == 4 then 4 else 2.8
	Effects.Slash(
		front * CFrame.Angles(math.rad(90), 0, 0) * CFrame.Angles(0, math.rad(tilt), 0) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-30, 30))),
		radius,
		Color3.fromRGB(255, 255, 255),
		0.22,
		160,
		0.35
	)
	if combo == 4 then
		Effects.Ring(root.CFrame * CFrame.new(0, 0, -3), 0.5, 4, Color3.fromRGB(230, 240, 255), 0.3, 0.6, { Transparency = 0.3 })
	end
end

function CombatVFX.Hit(p: { [string]: any })
	local victim = p.Victim :: Model?
	local root = Effects.Root(victim)
	if not victim or not root then
		return
	end
	local pos = root.Position
	local effect = p.Effect :: string?
	local color = p.Color or (if effect then EFFECT_COLORS[effect] else nil) or Color3.fromRGB(255, 240, 200)
	local blocked = p.Blocked == true
	local heavy = p.Heavy == true

	if blocked then
		Effects.Burst(pos + root.CFrame.LookVector * 1.5, 14, {
			Texture = TEX.Sparks,
			Color = ColorSequence.new(Color3.fromRGB(120, 220, 255)),
			Speed = NumberRange.new(14, 26),
			Size = Effects.NSeq(0.4, 0),
			Drag = 5,
		})
		Effects.Sound("Block", pos, { Volume = 0.7 })
		damageNumber(pos, p.Amount, Color3.fromRGB(120, 210, 255), false, "BLOCK " .. math.floor(p.Amount + 0.5))
		return
	end

	Effects.HitFlash(victim, Color3.new(1, 1, 1), if heavy then 0.25 else 0.15)
	Effects.Burst(pos, if heavy then 22 else 10, {
		Texture = TEX.Sparks,
		Color = Effects.Seq(Color3.new(1, 1, 1), color),
		Speed = NumberRange.new(16, if heavy then 40 else 26),
		Lifetime = NumberRange.new(0.2, 0.45),
		Size = Effects.NSeq(if heavy then 0.8 else 0.5, 0),
		Drag = 6,
	})
	if heavy then
		Effects.Flash(pos, color, 6, 0.2)
		Effects.Ring(CFrame.lookAt(pos, workspace.CurrentCamera.CFrame.Position), 0.5, 5, Color3.new(1, 1, 1), 0.25, 0.5, { Transparency = 0.2 })
	end
	if effect then
		overlay(effect, victim, root)
	end
	Effects.Sound(if heavy then "HeavyPunch" else "Punch", pos)

	local isTint = effect == "Burn" or effect == "Void" or effect == "Water"
	damageNumber(pos, p.Amount, if heavy then Color3.fromRGB(255, 200, 60) elseif isTint then color else Color3.new(1, 1, 1), heavy)

	if isLocal(victim) then
		Effects.Vignette(Color3.fromRGB(255, 30, 40), if heavy then 0.6 else 0.35, if heavy then 0.4 else 0.25)
		Effects.Shake(if heavy then 1.6 else 0.6, 0.25)
	elseif isLocal(p.Attacker) then
		Effects.Shake(if heavy then 0.9 else 0.3, 0.15)
	end
end

local shields: { [Model]: Part } = {}

function CombatVFX.Block(p: { [string]: any })
	local caster = p.Caster :: Model?
	local root = Effects.Root(caster)
	if not caster or not root then
		return
	end
	local existing = shields[caster]
	if existing then
		existing:Destroy()
		shields[caster] = nil
	end
	if p.On then
		Poser.Apply(caster, P.Block, 0.1)
		local shield = Effects.Part({
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1, 1, 1),
			Material = Enum.Material.ForceField,
			Color = Color3.fromRGB(80, 200, 255),
			Transparency = 0,
			Anchored = false,
			Massless = true,
			CFrame = root.CFrame,
			Parent = caster,
		})
		Make("Weld", { Part0 = root, Part1 = shield, C0 = CFrame.new(0, 0.3, -0.6), Parent = shield })
		Effects.Tween(shield, 0.15, { Size = Vector3.new(6.5, 6.5, 6.5) }, Enum.EasingStyle.Back)
		shields[caster] = shield
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
	local shield = shields[victim]
	if shield then
		shield:Destroy()
		shields[victim] = nil
	end
	local pos = root.Position
	for _ = 1, 12 do
		local shard = Effects.Part({
			Size = Vector3.new(rng:NextNumber(0.4, 1), rng:NextNumber(0.4, 1), 0.1),
			CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(-1, 2), rng:NextNumber(-2, 2)))
				* CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)),
			Color = Color3.fromRGB(120, 220, 255),
			Anchored = false,
			CanCollide = true,
			CollisionGroup = "VFX",
		})
		shard.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-25, 25), rng:NextNumber(10, 30), rng:NextNumber(-25, 25))
		Effects.Tween(shard, 0.8, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.3)
		Effects.Clean(shard, 1.2)
	end
	Effects.Flash(pos, Color3.fromRGB(120, 220, 255), 8, 0.3)
	Effects.Sound("GuardBreak", pos)
	damageNumber(pos + Vector3.new(0, 2, 0), 0, Color3.fromRGB(255, 80, 80), true, "GUARD BREAK!")
	if isLocal(victim) then
		Effects.Shake(1.5, 0.35)
	end
end

function CombatVFX.Dash(p: { [string]: any })
	local caster = p.Caster :: Model?
	local root = Effects.Root(caster)
	if not caster or not root then
		return
	end
	local dir: Vector3 = p.Direction or root.CFrame.LookVector
	Effects.Sound("Dash", root.Position)
	Effects.Afterimage(caster, Color3.fromRGB(140, 220, 255), 0.35, 0.45)
	task.delay(0.07, function()
		Effects.Afterimage(caster, Color3.fromRGB(140, 220, 255), 0.3, 0.6)
	end)
	-- Staub am Boden
	Effects.Burst(root.Position - Vector3.new(0, 2.6, 0), 10, {
		Texture = TEX.Smoke,
		Color = ColorSequence.new(Color3.fromRGB(180, 170, 200)),
		LightEmission = 0,
		LightInfluence = 0.8,
		Speed = NumberRange.new(4, 10),
		Size = Effects.NSeq(1, 3),
		Transparency = Effects.NSeq(0.5, 1),
		SpreadAngle = Vector2.new(70, 10),
		Lifetime = NumberRange.new(0.4, 0.7),
	})
	-- Windlinien
	for _ = 1, 5 do
		local offset = Vector3.new(rng:NextNumber(-1.5, 1.5), rng:NextNumber(-2, 2), rng:NextNumber(-1.5, 1.5))
		local start = root.Position + offset
		local line = Effects.Part({
			Size = Vector3.new(0.08, 0.08, 4),
			CFrame = CFrame.lookAt(start, start + dir),
			Color = Color3.new(1, 1, 1),
			Transparency = 0.3,
		})
		Effects.Tween(line, 0.25, { CFrame = line.CFrame + dir * 10, Transparency = 1 })
		Effects.Clean(line, 0.3)
	end
	Effects.Trail(root, Color3.fromRGB(160, 230, 255), 0.18, 2.5, 0.25)
end

function CombatVFX.Death(p: { [string]: any })
	local character = p.Character :: Model?
	local root = Effects.Root(character)
	if not character or not root then
		return
	end
	local pos = root.Position
	local color = Color3.fromRGB(180, 120, 255)
	-- Charakter zerfaellt in Neon-Teile
	for _, part in character:GetChildren() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local ghost = Effects.Part({ Size = part.Size, CFrame = part.CFrame, Color = color, Transparency = 0.2 })
			Effects.Tween(ghost, 0.9, {
				Size = Vector3.new(0.05, 0.05, 0.05),
				Transparency = 1,
				CFrame = part.CFrame * CFrame.new(rng:NextNumber(-2, 2), rng:NextNumber(2, 5), rng:NextNumber(-2, 2))
					* CFrame.Angles(rng:NextNumber(-2, 2), rng:NextNumber(-2, 2), rng:NextNumber(-2, 2)),
			}, Enum.EasingStyle.Quad)
			Effects.Clean(ghost, 1)
		end
	end
	Effects.SetCharacterVisible(character, false)
	Effects.Burst(pos, 40, {
		Texture = TEX.Sparkle,
		Color = Effects.Seq(Color3.new(1, 1, 1), color),
		Speed = NumberRange.new(6, 16),
		Acceleration = Vector3.new(0, 12, 0),
		Lifetime = NumberRange.new(0.8, 1.5),
		Size = Effects.NSeq(0.8, 0),
	})
	local pillar = Effects.Part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(60, 4, 4),
		CFrame = CFrame.new(pos + Vector3.new(0, 28, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Transparency = 0.25,
	})
	Effects.Tween(pillar, 0.9, { Size = Vector3.new(60, 0.1, 0.1), Transparency = 1 })
	Effects.Clean(pillar, 1)
	Effects.Light(pos, color, 30, 4, 0.8)
	Effects.Sound("Void", pos, { Volume = 0.6, Pitch = 1.6 })
end

function CombatVFX.Victory(p: { [string]: any })
	local character = p.Character :: Model?
	local root = Effects.Root(character)
	if not character or not root then
		return
	end
	local pos = root.Position
	local gold = Color3.fromRGB(255, 210, 80)
	Poser.Sequence(character, { { P.Victory, 3 } }, 0.4)
	local beam = Effects.Part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(200, 0.5, 0.5),
		CFrame = CFrame.new(pos + Vector3.new(0, 100, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = gold,
		Transparency = 0.2,
	})
	Effects.Tween(beam, 0.4, { Size = Vector3.new(200, 7, 7) }, Enum.EasingStyle.Back)
	Effects.Tween(beam, 2.5, { Transparency = 1, Size = Vector3.new(200, 1, 1) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 1.2)
	Effects.Clean(beam, 4)
	for i = 0, 2 do
		task.delay(i * 0.25, function()
			Effects.GroundRing(pos - Vector3.new(0, 2.8, 0), 1, 14, gold, 0.8, 1.2)
		end)
	end
	-- Konfetti / Feuerwerk
	for i = 1, 6 do
		task.delay(0.2 + i * 0.3, function()
			local at = pos + Vector3.new(rng:NextNumber(-14, 14), rng:NextNumber(10, 20), rng:NextNumber(-14, 14))
			local c = Color3.fromHSV(rng:NextNumber(), 0.8, 1)
			Effects.Burst(at, 40, {
				Texture = TEX.Sparkle,
				Color = Effects.Seq(Color3.new(1, 1, 1), c),
				Speed = NumberRange.new(12, 24),
				Lifetime = NumberRange.new(0.8, 1.4),
				Acceleration = Vector3.new(0, -14, 0),
				Drag = 1.5,
				Size = Effects.NSeq(1, 0),
			})
			Effects.Light(at, c, 40, 3, 0.6)
			Effects.Sound("Explosion", at, { Volume = 0.4, Pitch = 1.8 })
		end)
	end
	Effects.Light(root, gold, 30, 5, 3)
end

function CombatVFX.Unlock(p: { [string]: any })
	local character = p.Character :: Model?
	local root = Effects.Root(character)
	if not character or not root then
		return
	end
	local pos = root.Position
	local purple = Color3.fromRGB(160, 70, 255)
	local orb = Effects.Ball(CFrame.new(pos + Vector3.new(0, 6, 0)), 0.5, Color3.new(0, 0, 0), { Material = Enum.Material.SmoothPlastic })
	Effects.Tween(orb, 0.6, { Size = Vector3.new(4, 4, 4) }, Enum.EasingStyle.Back)
	Effects.Tween(orb, 0.25, { Size = Vector3.new(0.1, 0.1, 0.1) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 1.2)
	Effects.Clean(orb, 1.5)
	task.delay(1.45, function()
		Effects.Explosion(pos + Vector3.new(0, 6, 0), purple, 1.6, { Secondary = Color3.fromRGB(255, 160, 60) })
		Effects.Sound("Void", pos)
	end)
end

return CombatVFX
