-- Empfaengt Effekt-Befehle vom Server und spielt sie lokal ab.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Sounds = require(Shared:WaitForChild("Sounds"))

local Client = (script.Parent :: Instance).Parent :: Instance
local VFX = Client:WaitForChild("VFX")
local Effects = require(VFX:WaitForChild("Effects"))
local CombatVFX = require(VFX:WaitForChild("CombatVFX"))
local AbilityVFX = require(VFX:WaitForChild("AbilityVFX"))

local VFXController = {}

local player = Players.LocalPlayer

local function onPlayVFX(name: string, payload: any)
	if type(payload) ~= "table" then
		return
	end
	local myChar = player.Character
	if name == "Ability" then
		local isCaster = payload.Caster ~= nil and payload.Caster == myChar
		local involved = isCaster or (myChar ~= nil and table.find(payload.Targets or {}, myChar) ~= nil)
		AbilityVFX.Play(payload, { IsCaster = isCaster, Involved = involved, Preview = false })
		return
	end
	-- Eigene Schlaege und Dashes werden schon lokal (ohne Verzoegerung) abgespielt
	if (name == "M1" or name == "Dash") and payload.Caster == myChar and myChar ~= nil then
		return
	end
	local fn = (CombatVFX :: any)[name]
	if fn then
		task.spawn(function()
			local ok, err = pcall(fn, payload)
			if not ok then
				warn("[VFX] " .. name .. ": " .. tostring(err))
			end
		end)
	end
end

-- Spielt eine Faehigkeit nur lokal als Vorschau ab
function VFXController.Preview(abilityId: string)
	local char = player.Character
	if not char then
		return
	end
	local payload = AbilityVFX.PreviewPayload(abilityId, char)
	if payload then
		AbilityVFX.Play(payload, { IsCaster = true, Involved = true, Preview = true })
	end
end

function VFXController.Init()
	Net.Event("PlayVFX").OnClientEvent:Connect(onPlayVFX)
end

function VFXController.Start()
	-- Sounds und Texturen vorladen, damit der erste Effekt nicht stockt
	task.spawn(function()
		local assets = {}
		for _, def in Sounds do
			local s = Instance.new("Sound")
			s.SoundId = def.Id
			table.insert(assets, s)
		end
		for _, tex in Effects.Textures do
			local d = Instance.new("Decal")
			d.Texture = tex
			table.insert(assets, d)
		end
		pcall(function()
			ContentProvider:PreloadAsync(assets)
		end)
	end)
end

return VFXController
