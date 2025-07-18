-- SPDX-FileCopyrightText: (c) 2020 Silverlan <opensource@pragma-engine.com>
-- SPDX-License-Identifier: MIT

include("/shaders/vr/vr_equirectangular.lua")

util.register_class("gui.VRView")
gui.VRView.STEREO_IMAGE_LEFT = 0
gui.VRView.STEREO_IMAGE_RIGHT = 1
function gui.VRView:__init()
	self.m_zoomLevel = util.FloatProperty()
	self.m_horizontalRange = util.FloatProperty()
	self.m_renderFlags = util.IntProperty()

	self:SetHorizontalRange(360.0)
	self:SetCameraRotation(Quaternion())
	self:SetRotationOffset(Quaternion())
	self:SetReferenceCameraRotation(Quaternion())
	self:SetZoomLevel(1.0)
	self:SetRenderFlags(
		bit.bor(
			shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_BIT,
			shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_STEREO_VERTICAL_BIT
		)
	)
	self.m_shaderVr = shader.get("vr_equirectangular")
end
function gui.VRView:GetVRShader()
	return self.m_shaderVr
end
function gui.VRView:SetVRCamera(cam)
	self.m_cam = cam
end
function gui.VRView:SetCameraRotation(rot)
	self.m_viewMatrix = rot:ToMatrix()
end
function gui.VRView:SetZoomLevel(zoom)
	self.m_zoomLevel:Set(zoom)
end
function gui.VRView:GetZoomLevel()
	return self.m_zoomLevel:Get()
end
function gui.VRView:GetZoomLevelProperty()
	return self.m_zoomLevel
end
function gui.VRView:GetRenderFlags()
	return self.m_renderFlags:Get()
end
function gui.VRView:GetRenderFlagsProperty()
	return self.m_renderFlags
end
function gui.VRView:SetRenderFlags(flags)
	self.m_renderFlags:Set(flags)
end
function gui.VRView:SetRenderFlag(flag, enabled)
	self.m_renderFlags:Set(math.set_flag(self:GetRenderFlags(), flag, enabled))
end
function gui.VRView:SetStereo(stereo)
	self.m_renderFlags:Set(
		math.set_flag(
			self.m_renderFlags:Get(),
			shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_STEREO_VERTICAL_BIT,
			stereo
		)
	)
end
function gui.VRView:SetHorizontalRange(range)
	self.m_horizontalRange:Set(range)
end
function gui.VRView:GetHorizontalRange()
	return self.m_horizontalRange:Get()
end
function gui.VRView:GetHorizontalRangeProperty()
	return self.m_horizontalRange
end
function gui.VRView:SetStereoImage(eye)
	self.m_renderFlags:Set(
		math.set_flag(
			self.m_renderFlags:Get(),
			shader.VREquirectangular.RENDER_FLAG_EQUIRECTANGULAR_STEREO_RIGHT_EYE_BIT,
			eye == gui.VRView.STEREO_IMAGE_RIGHT
		)
	)
end
function gui.VRView:SetRotationOffset(rot)
	self.m_rotationOffset = rot:ToMatrix()
end
function gui.VRView:SetReferenceCameraRotation(rot)
	self.m_refCamRot = rot
end
function gui.VRView:DrawVR(drawCmd, dsTex)
	local cam
	local v
	if util.is_valid(self.m_cam) then
		v = self.m_cam:GetViewMatrix()
		cam = self.m_cam
	else
		v = self.m_viewMatrix
		cam = game.get_scene():GetActiveCamera()
	end
	if util.is_valid(cam) == false then
		return
	end
	-- Not sure why this yaw offset is required
	local yawOffset = -(1.0 - self.m_horizontalRange:Get() / 360.0) * 180
	v = v * self.m_refCamRot:ToMatrix() * EulerAngles(0, yawOffset, 0):ToQuaternion():ToMatrix() * self.m_rotationOffset

	-- Strip translation
	v:Set(3, 0, 0)
	v:Set(3, 1, 0)
	v:Set(3, 2, 0)
	local vp = cam:GetProjectionMatrix() * v
	vp:Inverse()

	local renderFlags = self.m_renderFlags:Get()
	if self:GetHorizontalRange() <= 180.0 then
		renderFlags = bit.bor(renderFlags, shader.VREquirectangular.RENDER_FLAG_ENABLE_MARGIN_BIT)
	end
	local r = self:GetVRShader()
		:GetWrapper()
		:Draw(drawCmd, dsTex, vp, self.m_horizontalRange:Get(), self.m_zoomLevel:Get(), renderFlags)
end
function gui.VRView:SetCursorInputMovementEnabled(enabled, elFocus)
	if enabled == false then
		util.remove(self.m_cbCursorInputMovement)
		return
	end
	if util.is_valid(self.m_cbCursorInputMovement) then
		return
	end
	self.m_cbCursorInputMovement = self:AddCallback("OnMouseEvent", function(el, mouseButton, state, mods)
		if
			elFocus:IsValid() == false
			or (mouseButton ~= input.MOUSE_BUTTON_LEFT and mouseButton ~= input.MOUSE_BUTTON_RIGHT)
		then
			return util.EVENT_REPLY_UNHANDLED
		end
		if state ~= input.STATE_PRESS and state ~= input.STATE_RELEASE then
			return util.EVENT_REPLY_UNHANDLED
		end

		if
			self.m_inCameraControlMode
			and mouseButton == input.MOUSE_BUTTON_LEFT
			and state == input.STATE_RELEASE
			and self:HasFocus() == false
		then
			elFocus:TrapFocus(true)
			elFocus:RequestFocus()
			input.set_cursor_pos(self.m_oldCursorPos)
			self.m_inCameraControlMode = false
			return util.EVENT_REPLY_HANDLED
		end

		--local el = gui.get_element_under_cursor()
		--if util.is_valid(el) and (el == self or el:IsDescendantOf(self)) then
		if mouseButton == input.MOUSE_BUTTON_LEFT and state == input.STATE_PRESS then
			self.m_oldCursorPos = input.get_cursor_pos()
			input.center_cursor()
			elFocus:TrapFocus(false)
			elFocus:KillFocus()
			self.m_inCameraControlMode = true
		end
		return util.EVENT_REPLY_HANDLED
		--end
		--return util.EVENT_REPLY_UNHANDLED
	end)
end
