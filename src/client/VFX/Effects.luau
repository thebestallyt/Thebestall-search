-- VFX-Grundbausteine: Neon-Teile, Partikel, Schockwellen, Ringe, Blitze, Nachbilder,
-- Licht, Sound, Bildschirm-Blitze und Farbkorrektur. Alles wird NUR lokal erstellt.

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

-- Fuehrt fn(alpha, dt) jeden Frame aus, bis "duration" vorbei ist
function Effects.Animate(duration: number, fn: (number, number) -> (), onDone: (() -> ())?): RBXScriptConnection
	local start = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt)
		local a = math.clamp((os.clock() - start) / duration, 0, 1)
		local ok, err = pcall(fn, a, dt)
		if not ok then
			warn("[VFX] " .. tostring(err))
			conn:Disconnect()
			return
		end
		if a >= 1 then
			conn:Disconnect()
			if onDone then
				onDone()
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
	elseif style == "InOut" then
		return if a < 0.5 then 2 * a * a else 1 - ((-2 * a + 2) ^ 2) / 2
	elseif style == "OutBack" then
		local c1, c3 = 1.70158, 2.70158
		return 1 + c3 * (a - 1) ^ 3 + c1 * (a - 1) ^ 2
	end
	return 1 - (1 - a) * (1 - a) -- Out
end

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
	local p = Effects.Part({ Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(position) })
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

-- Einmaliger Partikel-Ausstoss an einer Position
function Effects.Burst(position: Vector3, count: number, props: { [string]: any }?): ParticleEmitter
	local anchor, att = Effects.Anchor(position)
	local e = Effects.Emitter(att, props)
	e:Emit(math.max(1, math.floor(count * Effects.Quality)))
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
	e:Emit(math.max(1, math.floor(count * Effects.Quality)))
	Debris:AddItem(anchor, e.Lifetime.Max + 0.5)
	return e
end

-- Bodenpunkt unter einer Position (nur die Map zaehlt)
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
function Effects.Ground(position: Vector3, fallbackDrop: number?): Vector3
	local map = workspace:FindFirstChild("Map")
	if map then
		groundParams.FilterDescendantsInstances = { map }
		local res = workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -60, 0), groundParams)
		if res then
			return res.Position
		end
	end
	return position - Vector3.new(0, fallbackDrop or 3, 0)
end

function Effects.RaycastMap(origin: Vector3, direction: Vector3): RaycastResult?
	local map = workspace:FindFirstChild("Map")
	if not map then
		return nil
	end
	groundParams.FilterDescendantsInstances = { map }
	return workspace:Raycast(origin, direction, groundParams)
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
				table.insert(list, m)
			end
		end
	end
	return list
end

-- Partikel-Ausstoss an einem Attachment/Teil (z.B. Hand)
function Effects.BurstOn(parent: Instance, count: number, props: { [string]: any }?)
	local e = Effects.Emitter(parent, props)
	e:Emit(math.max(1, math.floor(count * Effects.Quality)))
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
		Range = range,
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

-- Neon-Kugel, die aufblitzt und verblasst
function Effects.Flash(position: Vector3, color: Color3, size: number, duration: number, startSize: number?)
	local ball = Effects.Ball(CFrame.new(position), startSize or size * 0.3, color, { Transparency = 0.05 })
	Effects.Tween(ball, duration, { Size = Vector3.new(size, size, size), Transparency = 1 }, Enum.EasingStyle.Quart)
	Debris:AddItem(ball, duration + 0.05)
	Effects.Light(position, color, math.min(size * 3, 60), 4, duration * 1.5)
	return ball
end

-- Ringe & Schockwellen ------------------------------------------------------------

-- Ring (CylinderHandleAdornment mit Innenradius). cf: Achse des Rings = Z-Achse von cf.
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
	local anchor = Effects.Part({ Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(cf.Position) })
	local width = thickness or 1
	local ring = Make("CylinderHandleAdornment", {
		Adornee = anchor,
		CFrame = cf.Rotation,
		Color3 = color,
		Radius = radius0,
		InnerRadius = math.max(0, radius0 - width),
		Height = o.Height or 0.25,
		Transparency = o.Transparency or 0.05,
		AlwaysOnTop = false,
		ZIndex = 1,
		Parent = anchor,
	})
	local t0 = o.Transparency or 0.05
	local style = o.Ease or "OutCubic"
	Effects.Animate(duration, function(a)
		local e = Effects.Ease(a, style)
		local r = radius0 + (radius1 - radius0) * e
		local w = width * (1 - a * (o.Thin and 0.8 or 0.4))
		ring.Radius = r
		ring.InnerRadius = math.max(0, r - w)
		ring.Transparency = t0 + (1 - t0) * (a ^ (o.FadePower or 1.4))
	end, function()
		anchor:Destroy()
	end)
	return ring
end

-- Liegender Ring am Boden
function Effects.GroundRing(position: Vector3, radius0: number, radius1: number, color: Color3, duration: number, thickness: number?, opts: { [string]: any }?)
	return Effects.Ring(CFrame.new(position) * CFrame.Angles(math.rad(90), 0, 0), radius0, radius1, color, duration, thickness, opts)
end

-- Flache Partikel-Schockwelle (Textur-Ring)
function Effects.Shockwave(position: Vector3, size: number, color: Color3, duration: number, up: Vector3?)
	local anchor, att = Effects.Anchor(position)
	local dir = up or Vector3.yAxis
	anchor.CFrame = CFrame.lookAt(position, position + dir) * CFrame.Angles(math.rad(-90), 0, 0)
	local e = Effects.Emitter(att, {
		Texture = TEX.Shockwave,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		Speed = NumberRange.new(0.01),
		SpreadAngle = Vector2.new(0, 0),
		EmissionDirection = Enum.NormalId.Top,
		Lifetime = NumberRange.new(duration),
		Size = Effects.NSeq(size * 0.1, size),
		Transparency = Effects.NSeq(0, 1),
		Color = ColorSequence.new(color),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(0, 0),
		LightEmission = 1,
		ZOffset = 0.5,
	})
	e:Emit(1)
	Debris:AddItem(anchor, duration + 0.3)
end

-- Komplette Explosion: Blitz + Ringe + Partikel + Licht + Wackeln
function Effects.Explosion(position: Vector3, color: Color3, scale: number, opts: { [string]: any }?)
	local o = opts or {}
	local secondary = o.Secondary or Color3.new(1, 1, 1)
	Effects.Flash(position, secondary, 6 * scale, 0.25)
	Effects.Flash(position, color, 10 * scale, 0.5, 2 * scale)
	Effects.GroundRing(position - Vector3.new(0, o.GroundOffset or 0, 0), scale, 9 * scale, color, 0.55, 1.6 * scale)
	Effects.Shockwave(position, 22 * scale, color, 0.5)
	Effects.Burst(position, 30 * scale, {
		Texture = TEX.Sparks,
		Color = Effects.Seq(secondary, color),
		Speed = NumberRange.new(25 * scale, 50 * scale),
		Lifetime = NumberRange.new(0.3, 0.7),
		Size = Effects.NSeq(0.6 * scale, 0),
		Drag = 4,
		Acceleration = Vector3.new(0, -30, 0),
	})
	Effects.Burst(position, 14 * scale, {
		Texture = TEX.Smoke,
		Color = ColorSequence.new(o.SmokeColor or Color3.fromRGB(60, 50, 70)),
		LightEmission = 0,
		LightInfluence = 0.6,
		Speed = NumberRange.new(6 * scale, 14 * scale),
		Lifetime = NumberRange.new(0.8, 1.6),
		Size = Effects.NSeq(3 * scale, 7 * scale),
		Transparency = Effects.NSeq(0.3, 1),
		Drag = 3,
	})
	CameraShake.ShakeAt(position, o.Shake or 1.5 * scale, 60 * scale, 0.45)
end

-- Bogen-Schnitt (Slash) ------------------------------------------------------------

function Effects.Slash(cf: CFrame, radius: number, color: Color3, duration: number, angle: number?, width: number?)
	local anchor = Effects.Part({ Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(cf.Position) })
	local w = width or 0.6
	local arc = Make("CylinderHandleAdornment", {
		Adornee = anchor,
		CFrame = cf.Rotation,
		Color3 = color,
		Radius = radius,
		InnerRadius = radius - w,
		Height = 0.1,
		Angle = 10,
		Transparency = 0,
		Parent = anchor,
	})
	local core = Make("CylinderHandleAdornment", {
		Adornee = anchor,
		CFrame = cf.Rotation,
		Color3 = Color3.new(1, 1, 1),
		Radius = radius - w * 0.35,
		InnerRadius = radius - w * 0.65,
		Height = 0.12,
		Angle = 10,
		Transparency = 0,
		Parent = anchor,
	})
	local target = angle or 200
	Effects.Animate(duration, function(a)
		local grow = math.clamp(a / 0.35, 0, 1)
		local fade = math.clamp((a - 0.35) / 0.65, 0, 1)
		local ang = 10 + (target - 10) * Effects.Ease(grow, "OutCubic")
		arc.Angle = ang
		core.Angle = ang
		arc.Transparency = fade
		core.Transparency = fade
		arc.Radius = radius + fade * radius * 0.15
		arc.InnerRadius = arc.Radius - w * (1 - fade * 0.8)
	end, function()
		anchor:Destroy()
	end)
end

-- Gerader Neon-Schnitt (Linie), z.B. fuer X-Schnitte
function Effects.Line(center: CFrame, length: number, color: Color3, duration: number, width: number?)
	local w = width or 0.25
	local glow = Effects.Part({ Size = Vector3.new(w * 3, w * 3, 0.1), CFrame = center, Color = color, Transparency = 0.5 })
	local core = Effects.Part({ Size = Vector3.new(w, w, 0.1), CFrame = center, Color = Color3.new(1, 1, 1) })
	Effects.Tween(glow, duration * 0.25, { Size = Vector3.new(w * 3, w * 3, length) }, Enum.EasingStyle.Quart)
	Effects.Tween(core, duration * 0.25, { Size = Vector3.new(w, w, length * 0.95) }, Enum.EasingStyle.Quart)
	Effects.Tween(glow, duration * 0.75, { Transparency = 1, Size = Vector3.new(0.05, 0.05, length * 1.1) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, duration * 0.25)
	Effects.Tween(core, duration * 0.75, { Transparency = 1, Size = Vector3.new(0.02, 0.02, length * 1.05) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, duration * 0.25)
	Debris:AddItem(glow, duration + 0.1)
	Debris:AddItem(core, duration + 0.1)
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

function Effects.Bolt(from: Vector3, to: Vector3, opts: { [string]: any }?)
	local o = opts or {}
	local color = o.Color or Color3.fromRGB(150, 220, 255)
	local width = o.Width or 0.35
	local duration = o.Duration or 0.3
	local segments = o.Segments or math.clamp(math.floor((to - from).Magnitude / 3), 4, 16)
	local points = boltPoints(from, to, segments, o.Jitter or (to - from).Magnitude * 0.12)
	local parts = {}
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local len = (b - a).Magnitude
		local mid = (a + b) / 2
		local core = Effects.Part({
			Size = Vector3.new(width, width, len + width),
			CFrame = CFrame.lookAt(mid, b),
			Color = o.CoreColor or Color3.new(1, 1, 1),
		})
		local glow = Effects.Part({
			Size = Vector3.new(width * 3, width * 3, len + width),
			CFrame = CFrame.lookAt(mid, b),
			Color = color,
			Transparency = 0.55,
		})
		table.insert(parts, core)
		table.insert(parts, glow)
	end
	-- Verzweigungen
	if (o.Branches or 0) > 0 then
		for _ = 1, o.Branches do
			local idx = rng:NextInteger(2, math.max(2, #points - 1))
			local start = points[idx]
			local dir = (to - from).Unit
			local branchEnd = start
				+ dir * rng:NextNumber(3, 8)
				+ Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * rng:NextNumber(3, 8)
			Effects.Bolt(start, branchEnd, { Color = color, Width = width * 0.5, Duration = duration * 0.8, Segments = 4 })
		end
	end
	for _, p in parts do
		Effects.Tween(p, duration, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(p, duration + 0.05)
	end
end

-- Felsen ------------------------------------------------------------------------------

-- Fliegende Felsbrocken mit Physik
function Effects.Rocks(position: Vector3, count: number, opts: { [string]: any }?)
	local o = opts or {}
	local n = math.floor(count * Effects.Quality)
	for _ = 1, n do
		local s = rng:NextNumber(o.MinSize or 0.6, o.MaxSize or 1.6)
		local rock = Effects.Part({
			Size = Vector3.new(s, s * rng:NextNumber(0.7, 1.2), s * rng:NextNumber(0.7, 1.3)),
			CFrame = CFrame.new(position + Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.5, 1.5), rng:NextNumber(-1, 1)))
				* CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)),
			Material = o.Material or Enum.Material.Slate,
			Color = o.Color or Color3.fromRGB(70, 62, 80),
			Anchored = false,
			CanCollide = true,
			CollisionGroup = "VFX",
			Massless = true,
		})
		local spread = o.Spread or 30
		local v = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit * rng:NextNumber(spread * 0.4, spread)
		rock.AssemblyLinearVelocity = v + Vector3.new(0, rng:NextNumber(o.MinUp or 25, o.MaxUp or 50), 0)
		rock.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-10, 10), rng:NextNumber(-10, 10), rng:NextNumber(-10, 10))
		local life = o.Life or rng:NextNumber(1.6, 2.6)
		task.delay(life, function()
			if rock.Parent then
				Effects.Tween(rock, 0.5, { Size = Vector3.new(0.05, 0.05, 0.05), Transparency = 1 })
			end
		end)
		Debris:AddItem(rock, life + 0.6)
	end
end

-- Felsspitzen, die im Kreis aus dem Boden brechen
function Effects.GroundSpikes(center: Vector3, radius: number, count: number, opts: { [string]: any }?)
	local o = opts or {}
	local stay = o.Stay or 1.2
	for i = 1, count do
		local a = (i / count) * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local r = radius * rng:NextNumber(0.85, 1.15)
		local h = rng:NextNumber(o.MinHeight or 3, o.MaxHeight or 6)
		local w = rng:NextNumber(1.6, 2.8)
		local base = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local tilt = CFrame.lookAt(base, center) * CFrame.Angles(math.rad(-rng:NextNumber(15, 35)), 0, rng:NextNumber(-0.3, 0.3))
		local rock = Effects.Part({
			Size = Vector3.new(w, h, w * rng:NextNumber(0.8, 1.2)),
			Material = o.Material or Enum.Material.Slate,
			Color = o.Color or Color3.fromRGB(58, 50, 70),
			CFrame = tilt * CFrame.new(0, -h, 0),
			CastShadow = true,
		})
		local up = tilt * CFrame.new(0, h * 0.25, 0)
		Effects.Tween(rock, 0.12, { CFrame = up }, Enum.EasingStyle.Back)
		task.delay(stay, function()
			Effects.Tween(rock, 0.5, { CFrame = tilt * CFrame.new(0, -h, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end)
		Debris:AddItem(rock, stay + 0.6)
	end
end

-- Leuchtende Risse im Boden
function Effects.Cracks(center: Vector3, count: number, length: number, color: Color3, duration: number)
	for i = 1, count do
		local a = (i / count) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local len = length * rng:NextNumber(0.6, 1.1)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local mid = center + dir * (len / 2) + Vector3.new(0, 0.05, 0)
		local crack = Effects.Part({
			Size = Vector3.new(0.35, 0.1, 0.1),
			CFrame = CFrame.lookAt(mid, mid + dir),
			Color = color,
		})
		Effects.Tween(crack, 0.15, { Size = Vector3.new(rng:NextNumber(0.25, 0.5), 0.1, len) })
		Effects.Tween(crack, duration, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.4)
		Debris:AddItem(crack, duration + 0.5)
	end
end

-- Dunkle Brandspur am Boden
function Effects.Scorch(position: Vector3, radius: number, duration: number, color: Color3?)
	local disc = Effects.Part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.05, radius * 2, radius * 2),
		CFrame = CFrame.new(position + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.SmoothPlastic,
		Color = color or Color3.fromRGB(15, 10, 12),
		Transparency = 0.25,
	})
	Effects.Tween(disc, duration, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	Debris:AddItem(disc, duration + 0.1)
	return disc
end

-- Charaktere ----------------------------------------------------------------------------

function Effects.GetPart(character: Model?, ...: string): BasePart?
	if not character then
		return nil
	end
	for _, name in { ... } do
		local p = character:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			return p
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

-- Halbtransparente Neon-Kopie des Charakters, die verblasst
function Effects.Afterimage(character: Model?, color: Color3, duration: number, startTransparency: number?, offset: CFrame?)
	if not character then
		return
	end
	local model = Make("Model", { Name = "Afterimage", Parent = folder })
	for _, part in character:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Transparency < 1 then
			local ghost: BasePart
			if part:IsA("MeshPart") then
				local ok, clone = pcall(function()
					return part:Clone()
				end)
				if ok and clone then
					for _, c in clone:GetChildren() do
						c:Destroy()
					end
					ghost = clone
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
			ghost.Material = Enum.Material.Neon
			ghost.Color = color
			ghost.Transparency = startTransparency or 0.35
			ghost.CFrame = if offset then offset * part.CFrame else part.CFrame
			ghost.Parent = model
			Effects.Tween(ghost, duration, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
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
		FillColor = color or Color3.new(1, 1, 1),
		FillTransparency = 0.05,
		OutlineColor = color or Color3.new(1, 1, 1),
		OutlineTransparency = 0.2,
		DepthMode = Enum.HighlightDepthMode.Occluded,
		Parent = character,
	})
	local d = duration or 0.18
	Effects.Tween(h, d, { FillTransparency = 1, OutlineTransparency = 1 })
	Debris:AddItem(h, d + 0.05)
end

-- Charakter lokal ein-/ausblenden
function Effects.SetCharacterVisible(character: Model?, visible: boolean)
	if not character then
		return
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = if visible then 0 else 1
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
		Transparency = Effects.NSeq(0.1, 1),
		WidthScale = Effects.NSeq(1, 0),
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

-- Rote Raender wenn man getroffen wird
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
			Transparency = Effects.NSeq(0.15, 1),
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
			TintColor = Color3.new(1, 1, 1),
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
