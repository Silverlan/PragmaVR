-- SPDX-FileCopyrightText: (c) 2022 Silverlan <opensource@pragma-engine.com>
-- SPDX-License-Identifier: MIT

include("/util/image_recorder.lua")

util.register_class("pfm.VrRecorder", util.ImageRecorder)
function pfm.VrRecorder:__init()
	local entHmd = ents.iterator({ ents.IteratorFilterComponent(ents.COMPONENT_VR_HMD) })()
	local hmdC = entHmd:GetComponent(ents.COMPONENT_VR_HMD)
	-- TODO: It would be better in the future to place the camera in the center instead of using
	-- either the left or right eye
	local eye = hmdC:GetEye(openvr.EYE_LEFT)
	local renderer = eye:GetRenderer()

	local tex = renderer:GetPresentationTexture()
	local img = tex:GetImage()

	util.ImageRecorder.__init(self, img)

	local entPlayer = ents.iterator({ ents.IteratorFilterComponent("game_animation_player") })()
	if entPlayer ~= nil then
		local playerC = entPlayer:GetComponent("game_animation_player")
		playerC:SetPlaybackRate(0.0)
		self.m_player = playerC
	end
end
function pfm.VrRecorder:GoToTimeOffset(frameIndex, t)
	local f = self.m_player:GetCurrentTimeFraction()
	if f >= 1.0 then
		return false
	end
	self.m_player:SetCurrentTime(t)
	return true
end
function pfm.VrRecorder:Log(msg, isWarning)
	pfm.log(msg, pfm.LOG_CATEGORY_PFM, isWarning and pfm.LOG_SEVERITY_WARNING or nil)
end
