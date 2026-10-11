-- Kamera-Wackeln mit weichem Rauschen. Mehrere Shakes addieren sich.

local RunService = game:GetService("RunService")

local CameraShake = {}

type Shake = { Intensity: number, Duration: number, Start: number, Frequency: number, Seed: number }

local shakes: { Shake } = {}
local bound = false
CameraShake.Enabled = true

local function update()
	if #shakes == 0 then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local t = os.clock()
	local px, py, rx, ry, rz = 0, 0, 0, 0, 0
	for i = #shakes, 1, -1 do
		local s = shakes[i]
		local elapsed = t - s.Start
		if elapsed >= s.Duration then
			table.remove(shakes, i)
			continue
		end
		local fade = 1 - (elapsed / s.Duration)
		fade = fade * fade
		local amp = s.Intensity * fade
		local n = elapsed * s.Frequency
		px += math.noise(n, s.Seed, 0) * amp * 0.35
		py += math.noise(s.Seed, n, 0) * amp * 0.35
		rx += math.noise(n, 0, s.Seed) * amp * 0.012
		ry += math.noise(0, n, s.Seed) * amp * 0.012
		rz += math.noise(s.Seed, 0, n) * amp * 0.018
	end
	if CameraShake.Enabled then
		camera.CFrame = camera.CFrame * CFrame.new(px, py, 0) * CFrame.Angles(rx, ry, rz)
	end
end

function CameraShake.Shake(intensity: number, duration: number, frequency: number?)
	if intensity <= 0.01 then
		return
	end
	if not bound then
		bound = true
		RunService:BindToRenderStep("NovaCameraShake", Enum.RenderPriority.Camera.Value + 2, update)
	end
	table.insert(shakes, {
		Intensity = math.min(intensity, 6),
		Duration = duration,
		Start = os.clock(),
		Frequency = frequency or 18,
		Seed = math.random() * 100,
	})
end

-- Wackeln abhaengig von der Entfernung zur Kamera
function CameraShake.ShakeAt(position: Vector3, intensity: number, radius: number, duration: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local dist = (camera.CFrame.Position - position).Magnitude
	local falloff = 1 - math.clamp(dist / radius, 0, 1)
	if falloff > 0 then
		CameraShake.Shake(intensity * falloff, duration)
	end
end

return CameraShake
