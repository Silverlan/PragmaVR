--[[
    Copyright (C) 2021 Silverlan

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]

include("/gui/renderimage.lua")

util.register_class("ents.VRVideo", BaseEntityComponent)

function ents.VRVideo:__init()
	BaseEntityComponent.__init(self)
end

function ents.VRVideo:Initialize()
	self.m_eyeGUIElements = {}
	self.m_hmdEyeRenderCallbacks = {}
	self.m_eyeScenes = {}
	self:AddEntityComponent("vr_hmd")
	self:BindEvent(ents.VRHMD.EVENT_ON_HMD_INITIALIZED, "OnHMDInitialized")

	self:InitializeEye(openvr.EYE_LEFT)
	self:InitializeEye(openvr.EYE_RIGHT)
end

function ents.VRVideo:OnEntitySpawn()
	local hmdC = self:GetEntity():GetComponent(ents.COMPONENT_VR_HMD)
	if hmdC == nil or hmdC:IsHMDValid() == false then
		return
	end
	self:OnHMDInitialized(hmdC)
end

function ents.VRVideo:OnHMDInitialized(hmd)
	for _, eyeId in ipairs({ openvr.EYE_LEFT, openvr.EYE_RIGHT }) do
		local eyeC = hmd:GetEye(eyeId)
		if eyeC ~= nil then
			self.m_hmdEyeRenderCallbacks[eyeId] = eyeC:AddEventCallback(
				ents.VRHMDEye.EVENT_ON_RENDER_EYE,
				function(scene, drawSceneInfo)
					self:OnRenderEye(eyeC, scene, drawSceneInfo)
				end
			)

			local scene = self.m_eyeScenes[eyeId]
			if scene ~= nil then
				scene:SetRenderer(eyeC:GetRenderer())
				scene:SetActiveCamera(eyeC:GetCamera())
			end
		end
	end
end

function ents.VRVideo:GetScene(eyeIdx)
	return self.m_eyeScenes[eyeIdx]
end

function ents.VRVideo:OnRenderEye(eyeC, scene, drawSceneInfo)
	local idx = eyeC:GetEyeIndex()
	local el = self.m_eyeGUIElements[idx]
	if util.is_valid(el) == false then
		return
	end
	scene = self.m_eyeScenes[idx]
	drawSceneInfo.scene = scene
	local renderer = scene:GetRenderer()

	local drawInfo = gui.Base.DrawInfo()
	drawInfo.offset = math.Vector2i(0, 0)
	drawInfo.size = math.Vector2i(el:GetWidth(), el:GetHeight())
	drawInfo.transform = Mat4(1.0)
	local rpInfo = prosper.RenderPassInfo(renderer:GetRenderTarget())
	rpInfo:SetClearValues({
		prosper.ClearValue(),
		prosper.ClearValue(),
		prosper.ClearValue(),
	})
	-- We'll render the frames as the background of our scene
	-- TODO: Image barriers
	el:ApplyImageProcessing(drawSceneInfo) -- Update the image with our current HMD head transform
	if drawSceneInfo.commandBuffer:RecordBeginRenderPass(rpInfo) then
		-- drawSceneInfo.commandBuffer:RecordClearAttachment(renderer:GetRenderTarget():GetTexture():GetImage(),Color.Lime,0)
		el:Draw(drawInfo)
		drawSceneInfo.commandBuffer:RecordEndRenderPass()
	end
end

function ents.VRVideo:OnRemove()
	for eyeIdx, el in pairs(self.m_eyeGUIElements) do
		util.remove(el)
	end
	for eyeId, cb in pairs(self.m_hmdEyeRenderCallbacks) do
		util.remove(cb)
	end
	for eyeId, scene in pairs(self.m_eyeScenes) do
		util.remove(scene)
	end
end

function ents.VRVideo:InitializeEye(eyeIdx)
	-- We don't want to render the world, skybox, etc. during video plaback,
	-- so we'll set up a custom scene. This way we can also still render
	-- certain objects (e.g. 3D VR interfaces) more easily.
	local gameScene = game.get_scene()
	local scene = ents.create_scene(prosper.SAMPLE_COUNT_1_BIT)
	scene:SetWorldEnvironment(gameScene:GetWorldEnvironment())
	self.m_eyeScenes[eyeIdx] = scene

	local elTex = gui.create("WIRenderImage")
	elTex:SetVisible(false)
	elTex:SetVRView(true)
	elTex:SetAutoUpdate(false)
	self.m_eyeGUIElements[eyeIdx] = elTex

	local hmdC = self:GetEntity():GetComponent(ents.COMPONENT_VR_HMD)
	local eyeC = (hmdC ~= nil) and hmdC:GetEye(eyeIdx) or nil
	local camC = (eyeC ~= nil) and eyeC:GetEntity():GetComponent(ents.COMPONENT_CAMERA) or nil
	if camC == nil then
		return
	end
	elTex:SetVRCamera(camC)
	local res = eyeC:GetResolution()
	elTex:SetWidth(res.x)
	elTex:SetHeight(res.y)
end

function ents.VRVideo:SetEyeTexture(eye, vrView)
	local el = self.m_eyeGUIElements[eye]
	if util.is_valid(el) == false then
		return
	end
	el:SetTexture(vrView:GetTexture())

	el:GetZoomLevelProperty():Unlink()
	el:GetRenderFlagsProperty():Unlink()
	el:GetHorizontalRangeProperty():Unlink()
	if vrView ~= nil then
		el:GetZoomLevelProperty():Link(vrView:GetZoomLevelProperty())
		el:GetRenderFlagsProperty():Link(vrView:GetRenderFlagsProperty())
		el:GetHorizontalRangeProperty():Link(vrView:GetHorizontalRangeProperty())
	end
end
ents.register_component("vr_video", ents.VRVideo, "vr")
