--!strict
-- Entry point shared by Roblox (Realizer) and the offline preview (Lune):
--   Scene.build(styleId) -> scene description (plain data)
--   Scene.evaluate(scene, t) -> camera, bone transforms, channels, overlay
local Builder = require(script.Parent.Builder)
local Styles = require(script.Parent.Styles)
local Shots = require(script.Parent.Shots)
local WideSet = require(script.Parent.Art.Sets.WideSet)
local CloseupSet = require(script.Parent.Art.Sets.CloseupSet)

local Scene = {}

Scene.DURATION = Shots.DURATION

function Scene.build(styleId: string): Builder.Scene
	local scene = Builder.new(Styles.get(styleId))
	WideSet.build(scene)
	CloseupSet.build(scene)
	return scene
end

function Scene.evaluate(scene: Builder.Scene, t: number): Shots.FrameState
	return Shots.evaluate(scene, t)
end

-- World CFrame of a part for a frame
function Scene.partCFrame(part: Builder.PartSpec, frame: Shots.FrameState): CFrame
	if part.rig and part.bone then
		local bones = frame.rigs[part.rig]
		if bones then
			local b = bones[part.bone]
			if b then
				return b * part.cf
			end
		end
	elseif part.channel then
		local ch = frame.channels[part.channel]
		if ch then
			return ch * part.cf
		end
	end
	return part.cf
end

return Scene
