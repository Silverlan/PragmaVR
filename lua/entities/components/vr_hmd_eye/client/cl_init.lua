--[[
    Copyright (C) 2021 Silverlan

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]

util.register_class("ents.VRHMDEye", BaseEntityComponent)

function ents.VRHMDEye:__init()
	BaseEntityComponent.__init(self)
end

function ents.VRHMDEye:Initialize()
	self:AddEntityComponent(ents.COMPONENT_CAMERA)
	self:SetRenderEnabled(true)
end
function ents.VRHMDEye:OnRemove()
	if util.is_valid(self.m_scene) then
		self.m_scene:GetEntity():Remove()
	end
	if util.is_valid(self.m_renderer) then
		self.m_renderer:GetEntity():Remove()
	end
end
function ents.VRHMDEye:SetEyeIndex(eyeIdx)
	self.m_eyeIdx = eyeIdx
end
function ents.VRHMDEye:GetEyeIndex()
	return self.m_eyeIdx
end
function ents.VRHMDEye:GetRenderer()
	return self.m_renderer
end
function ents.VRHMDEye:GetResolution()
	local renderer = self:GetRenderer()
	return (renderer ~= nil) and Vector2i(renderer:GetWidth(), renderer:GetHeight()) or Vector2i(0, 0)
end
function ents.VRHMDEye:GetScene()
	return self.m_scene
end
function ents.VRHMDEye:SetClearColor(clearColor)
	self.m_clearColor = clearColor
end
function ents.VRHMDEye:InitializeCamera(aspectRatio)
	local gameCam = game.get_primary_camera()
	if self.m_eyeIdx == nil or gameCam == nil then
		return
	end
	local camC = self:GetEntity():GetComponent(ents.COMPONENT_CAMERA)
	if camC == nil then
		return
	end
	camC:SetAspectRatio(aspectRatio)
	camC:SetFOV(gameCam:GetFOV())
	camC:SetNearZ(gameCam:GetNearZ())
	camC:SetFarZ(gameCam:GetFarZ())

	local fUpdateProjectionMatrix = function()
		self:UpdateProjectionMatrix()
	end
	camC:GetAspectRatioProperty():AddCallback(fUpdateProjectionMatrix)
	camC:GetFOVProperty():AddCallback(fUpdateProjectionMatrix)
	camC:GetNearZProperty():AddCallback(fUpdateProjectionMatrix)
	camC:GetFarZProperty():AddCallback(fUpdateProjectionMatrix)
	self:UpdateProjectionMatrix()
end
function ents.VRHMDEye:GetCamera()
	return self:GetEntity():GetComponent(ents.COMPONENT_CAMERA)
end
function ents.VRHMDEye:UpdateProjectionMatrix()
	local camC = self:GetEntity():GetComponent(ents.COMPONENT_CAMERA)
	if camC == nil then
		return
	end
	if openvr.is_instance_valid() == false then
		camC:UpdateProjectionMatrix()
		return
	end
	local matProj = openvr.get_projection_matrix(self.m_eyeIdx, camC:GetNearZ(), camC:GetFarZ())
	camC:SetProjectionMatrix(matProj)
end
function ents.VRHMDEye:InitializeRenderer(scene)
	local entRenderer = self:GetEntity():CreateChild("rasterization_renderer")
	local renderer = entRenderer:GetComponent(ents.COMPONENT_RENDERER)
	local rasterizer = entRenderer:GetComponent(ents.COMPONENT_RASTERIZATION_RENDERER)
	local width, height = openvr.get_recommended_render_target_size()
	local vrResolutionOverride = console.get_convar_string("vr_resolution_override")
	if #vrResolutionOverride > 0 then
		local res = string.split(vrResolutionOverride, "x")
		if #res == 2 then
			width = tonumber(res[1])
			height = tonumber(res[2])
		end
	end
	print("VR render target size: ", width, height)

	-- rasterizer:SetSSAOEnabled(true)
	renderer:InitializeRenderTarget(scene, width, height)
	self.m_renderer = renderer
	return renderer
end
function ents.VRHMDEye:OnEntitySpawn()
	local sceneCreateInfo = ents.SceneComponent.CreateInfo()
	sceneCreateInfo.sampleCount = prosper.SAMPLE_COUNT_1_BIT
	local gameScene = game.get_scene()
	local scene = ents.create_scene(sceneCreateInfo, gameScene)
	scene:Link(gameScene, false)
	scene:GetEntity():SetName("vr_eye_" .. ((self:GetEyeIndex() == openvr.EYE_LEFT) and "left" or "right"))
	self.m_scene = scene

	local renderer = self:InitializeRenderer(scene)
	if renderer == nil then
		return
	end

	local img = renderer:GetPresentationTexture():GetImage()
	openvr.set_eye_image(self:GetEyeIndex(), img)

	self.m_renderer = renderer
	self:InitializeCamera(renderer:GetWidth() / renderer:GetHeight())
	local cam = self:GetEntity():GetComponent(ents.COMPONENT_CAMERA)
	scene:SetActiveCamera(cam)

	local gameCam = game.get_primary_camera()
	self:GetEntity():SetPose(gameCam:GetEntity():GetPose())
	self:GetEntity():SetParent(gameCam:GetEntity())

	local drawSceneInfo = game.DrawSceneInfo()
	drawSceneInfo.scene = scene
	-- Image has to be flipped vertically for OpenGL, reason unclear
	if prosper.get_api_abbreviation() == "GL" then
		drawSceneInfo.flags = bit.bor(drawSceneInfo.flags, game.DrawSceneInfo.FLAG_FLIP_VERTICALLY_BIT)
	end
	self.m_drawSceneInfo = drawSceneInfo

	scene:SetRenderer(self.m_renderer)
end
function ents.VRHMDEye:Setup(hmdC, eyeIdx)
	self.m_hmdC = hmdC
	self:SetEyeIndex(eyeIdx)
end
function ents.VRHMDEye:GetHMD()
	return self.m_hmdC
end
function ents.VRHMDEye:SubmitScene()
	local res = openvr.submit_eye(self:GetEyeIndex())
	if res ~= openvr.COMPOSITOR_ERROR_NONE then
		print(openvr.compositor_error_to_string(res))
	end
end
function ents.VRHMDEye:SetRenderEnabled(enabled)
	self.m_renderEnabled = enabled
end
function ents.VRHMDEye:IsRenderEnabled()
	return self.m_renderEnabled
end
local cvRenderBothEyesIfHmdInactive = console.get_convar("vr_render_both_eyes_if_hmd_inactive")
local cvMirrorEyeView = console.get_convar("vr_mirror_eye_view")
function ents.VRHMDEye:DrawScene(mainDrawSceneInfo)
	local camC = self:GetEntity():GetComponent(ents.COMPONENT_CAMERA)
	local hmdC = self:GetHMD()
	local trC = util.is_valid(hmdC) and hmdC:GetEntity():GetComponent(ents.COMPONENT_VR_TRACKED_DEVICE) or nil
	if self.m_renderer == nil or camC == nil or trC == nil or self:IsRenderEnabled() == false then
		return
	end
	if
		not trC:IsUserInteractionActive()
		and self:GetEyeIndex() == openvr.EYE_RIGHT
		and not cvRenderBothEyesIfHmdInactive:GetBool()
	then
		return
	end -- If HMD is not put on, we only render the left eye to save resources
	if self:GetEyeIndex() == cvMirrorEyeView:GetInt() then
		self.m_drawSceneInfo.outputImage = mainDrawSceneInfo.outputImage
	else
		self.m_drawSceneInfo.outputImage = nil
	end

	camC:UpdateViewMatrix()
	self:UpdateProjectionMatrix()
	if util.is_valid(self.m_renderer) then
		game.queue_scene_for_rendering(self.m_drawSceneInfo)
	end
end
ents.COMPONENT_VR_HMD_EYE = ents.register_component("vr_hmd_eye", ents.VRHMDEye)
