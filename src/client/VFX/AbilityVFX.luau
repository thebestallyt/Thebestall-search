-- Verteilt Faehigkeits-Effekte an die richtigen Module und baut Vorschau-Daten.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Abilities = require(Shared:WaitForChild("Abilities"))

local VFX = script.Parent :: Instance
local Effects = require(VFX:WaitForChild("Effects"))
local Cutscene = require(VFX:WaitForChild("Cutscene"))
local Basic = require(VFX:WaitForChild("AbilitiesBasic"))
local Cinematic = require(VFX:WaitForChild("AbilitiesCinematic"))

local AbilityVFX = {}

export type Context = { IsCaster: boolean, Involved: boolean, Preview: boolean }

function AbilityVFX.Play(p: any, ctx: Context)
	local fn = (Basic :: any)[p.Id] or (Cinematic :: any)[p.Id]
	if not fn then
		warn("[AbilityVFX] Keine Effekte fuer " .. tostring(p.Id))
		return
	end
	p.Extra = p.Extra or {}
	p.Targets = p.Targets or {}
	task.spawn(function()
		local ok, err = pcall(fn, p, ctx)
		if not ok then
			warn("[AbilityVFX] Fehler in " .. tostring(p.Id) .. ": " .. tostring(err))
			if ctx.Involved and Cutscene.IsActive() then
				Cutscene.End()
			end
			Effects.SetCharacterVisible(p.Caster, true)
		end
	end)
end

local function flatLook(cf: CFrame): Vector3
	local l = cf.LookVector
	local f = Vector3.new(l.X, 0, l.Z)
	return if f.Magnitude < 1e-3 then Vector3.new(0, 0, -1) else f.Unit
end

-- Erstellt Daten fuer eine lokale Vorschau (nur Effekte, kein Schaden)
function AbilityVFX.PreviewPayload(id: string, character: Model): any?
	local root = Effects.Root(character)
	if not root or not Abilities.Get(id) then
		return nil
	end
	local cf = root.CFrame
	local pos = cf.Position
	local look = flatLook(cf)
	local aim = Effects.Ground(pos + look * 20)
	local extra: { [string]: any } = {}
	if id == "EmberPunch" or id == "GaleBurst" then
		extra.Dir = look
	elseif id == "StoneSmash" then
		extra.Ground = Effects.Ground(pos)
	elseif id == "FrostShard" then
		local origin = pos + Vector3.new(0, 1, 0) + look * 2
		extra.Origin = origin
		extra.Dirs = {}
		for _, a in { -11, 0, 11 } do
			table.insert(extra.Dirs, CFrame.Angles(0, math.rad(a), 0):VectorToWorldSpace(look))
		end
	elseif id == "VoltDash" then
		extra.From = pos
		extra.To = pos + look * 22
		extra.Dir = look
	elseif id == "TidalVortex" or id == "MeteorStrike" then
		extra.Center = aim
		extra.Start = aim - look * 55 + Vector3.new(0, 140, 0)
	elseif id == "Thunderclap" then
		extra.Strikes = {
			aim,
			Effects.Ground(aim + Vector3.new(5, 0, 2)),
			Effects.Ground(aim + Vector3.new(-3, 0, -5)),
		}
	elseif id == "ShadowStep" then
		local dest = pos + look * 14
		extra.Dest = CFrame.lookAt(dest, dest + look)
	elseif id == "CelestialJudgment" then
		extra.Center = Effects.Ground(pos + look * 22)
	elseif id == "Supernova" then
		extra.Center = pos
	elseif id == "BlackHole" then
		extra.Center = Effects.Ground(pos + look * 18) + Vector3.new(0, 7, 0)
	end
	return {
		Id = id,
		Caster = character,
		Origin = cf,
		Aim = aim,
		Targets = {},
		Extra = extra,
		Seed = 1,
	}
end

return AbilityVFX
