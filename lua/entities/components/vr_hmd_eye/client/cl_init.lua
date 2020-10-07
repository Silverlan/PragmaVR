--[[
    Copyright (C) 2019  Florian Weischer

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]

util.register_class("ents.VRHMDEye",BaseEntityComponent)

function ents.VRHMDEye:__init()
	BaseEntityComponent.__init(self)
end

function ents.VRHMDEye:Initialize()
	self:AddEntityComponent(ents.COMPONENT_CAMERA)
end
function ents.VRHMDEye:SetEyeIndex(eyeIdx) self.m_eyeIdx = eyeIdx end
function ents.VRHMDEye:GetEyeIndex() return self.m_eyeIdx end
function ents.VRHMDEye:GetRenderer() return self.m_renderer end
function ents.VRHMDEye:GetResolution()
	local renderer = self:GetRenderer()
	return (renderer ~= nil) and Vector2i(renderer:GetWidth(),renderer:GetHeight()) or Vector2i(0,0)
end
function ents.VRHMDEye:GetScene() return self.m_scene end
function ents.VRHMDEye:InitializeCamera(aspectRatio)
	local gameCam = game.get_primary_camera()
	if(self.m_eyeIdx == nil or gameCam == nil) then return end
	local camC = self:GetEntity():GetComponent(ents.COMPONENT_CAMERA)
	if(camC == nil) then return end
	camC:SetAspectRatio(aspectRatio)
	camC:SetFOV(gameCam:GetFOV())
	camC:SetNearZ(gameCam:GetNearZ())
	camC:SetFarZ(gameCam:GetFarZ())

	local fUpdateProjectionMatrix = function() self:UpdateProjectionMatrix() end
	camC:GetAspectRatioProperty():AddCallback(fUpdateProjectionMatrix)
	camC:GetFOVProperty():AddCallback(fUpdateProjectionMatrix)
	camC:GetNearZProperty():AddCallback(fUpdateProjectionMatrix)
	camC:GetFarZProperty():AddCallback(fUpdateProjectionMatrix)
	self:UpdateProjectionMatrix()
end
function ents.VRHMDEye:GetCamera() return self:GetEntity():GetComponent(ents.COMPONENT_CAMERA) end
function ents.VRHMDEye:UpdateProjectionMatrix()
	local camC = self:GetEntity():GetComponent(ents.COMPONENT_CAMERA)
	if(camC == nil) then return end
	local matProj = openvr.get_projection_matrix(self.m_eyeIdx,camC:GetNearZ(),camC:GetFarZ())
	camC:SetProjectionMatrix(matProj)
end
function ents.VRHMDEye:OnEntitySpawn()
	local scene = game.get_scene()
	local renderer = scene:CreateRenderer(game.Scene.RENDERER_TYPE_RASTERIZATION)
	if(renderer == nil) then return end
	local width,height = openvr.get_recommended_render_target_size()

	-- TODO: For some reason the images will not get updated properly on the HMD (Vive)
	-- if the height is larger than the width. I have no idea why that is the case, for now we'll
	-- just increase the width in those cases
	if(height > width) then width = height end

	renderer:SetSSAOEnabled(scene,true)
	renderer:InitializeRenderTarget(scene,width,height)

	local img = renderer:GetPresentationTexture():GetImage()
	openvr.set_eye_image(self:GetEyeIndex(),img)

	self.m_scene = scene
	self.m_renderer = renderer
	self:InitializeCamera(width /height)

	local drawSceneInfo = game.DrawSceneInfo()
	drawSceneInfo.scene = scene
	drawSceneInfo.flipVertically = true
	self.m_drawSceneInfo = drawSceneInfo
end
function ents.VRHMDEye:DrawScene(mainDrawSceneInfo)
	--[[if(self:GetEyeIndex() ~= 0) then
		local res = openvr.submit_eye(self:GetEyeIndex())
		return
	end]]
	local camC = self:GetEntity():GetComponent(ents.COMPONENT_CAMERA)
	if(self.m_renderer == nil or camC == nil) then return end
	local scene = game.get_scene()
	local gameCam = scene:GetActiveCamera()
	if(gameCam == nil) then return end

	local gameRenderer = scene:GetRenderer()
	local entGameCam = gameCam:GetEntity()
	local rot = entGameCam:GetRotation()
	local rotTmp = rot *EulerAngles(0,180,0):ToQuaternion()
	local test = false
	if(test == false) then
		--entGameCam:SetRotation(rotTmp)
	end
	gameCam:UpdateViewMatrix()
	local vm = gameCam:GetViewMatrix()
	entGameCam:SetRotation(rot)

	camC:SetViewMatrix(vm)
	--local hmdPoseMatrix = openvr.get_pose_matrix()
	local eyeToHeadTransform = openvr.get_eye_to_head_transform(self.m_eyeIdx,camC)
	--local mView = hmdPoseMatrix *eyeToHeadTransform
	if(test == false) then
		--camC:SetViewMatrix(mView)
	end
	local mProj = openvr.get_projection_matrix(self.m_eyeIdx,camC:GetNearZ(),camC:GetFarZ())
	-- mProj:Scale(Vector(1,-1,1))
	camC:SetProjectionMatrix(mProj)

	self.m_drawSceneInfo.commandBuffer = mainDrawSceneInfo.commandBuffer
	self.m_drawSceneInfo.scene = nil
	if(self:InvokeEventCallbacks(ents.VRHMDEye.EVENT_ON_RENDER_EYE,{scene,self.m_drawSceneInfo}) ~= util.EVENT_REPLY_HANDLED) then
		local useGameScene = (self.m_drawSceneInfo.scene == nil)
		if(useGameScene) then
			scene = game.get_scene()
			self.m_drawSceneInfo.scene = scene
			scene:SetActiveCamera(camC)
			scene:SetRenderer(self.m_renderer)
		else scene = self.m_drawSceneInfo.scene end

		self.m_drawSceneInfo.outputImage = self.m_renderer:GetPresentationTexture():GetImage()
		game.draw_scene(self.m_drawSceneInfo)
		-- self.m_drawSceneInfo.commandBuffer:RecordClearImage(self.m_drawSceneInfo.outputImage,Color.Red)

		-- Restore original camera and renderer
		if(useGameScene) then
			scene:SetActiveCamera(gameCam)
			scene:SetRenderer(gameRenderer)
		end
	end
	
	local res = openvr.submit_eye(self:GetEyeIndex())
	if(res ~= openvr.COMPOSITOR_ERROR_NONE) then
		print(openvr.compositor_error_to_string(res))
	end


	--[[gameCam:UpdateViewMatrix()
	camC:SetViewMatrix(gameCam:GetViewMatrix())
	local hmdPoseMatrix = openvr.get_pose_matrix()
	local eyeToHeadTransform = openvr.get_eye_to_head_transform(self.m_eyeIdx,camC)
	local mView = hmdPoseMatrix *eyeToHeadTransform
	camC:SetViewMatrix(mView)
	local mProj = openvr.get_projection_matrix(self.m_eyeIdx,camC:GetNearZ(),camC:GetFarZ())
	-- mProj:Scale(Vector(1,-1,1))
	camC:SetProjectionMatrix(mProj)

	--scene:SetActiveCamera(camC)
	scene:SetRenderer(self.m_renderer)
self.m_drawSceneInfo.outputImage = self.m_renderer:GetPresentationTexture():GetImage()

	self.m_drawSceneInfo.commandBuffer = mainDrawSceneInfo.commandBuffer
self.m_drawSceneInfo.clearColor = Color.Lime
	game.draw_scene(self.m_drawSceneInfo)

	-- Restore original camera and renderer
	scene:SetRenderer(gameRenderer)
	if(gameCam ~= nil) then scene:SetActiveCamera(gameCam) end

	local res = openvr.submit_eye(self:GetEyeIndex())
	if(res ~= openvr.COMPOSITOR_ERROR_NONE) then
		print(openvr.compositor_error_to_string(res))
	end]]
end
ents.COMPONENT_VR_HMD_EYE = ents.register_component("vr_hmd_eye",ents.VRHMDEye)
ents.VRHMDEye.EVENT_ON_RENDER_EYE = ents.register_component_event(ents.COMPONENT_VR_HMD_EYE,"render_eye")
