--[[
    Copyright (C) 2021 Silverlan

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]

include_component("vr_tracked_device")

util.register_class("ents.VRHMD", BaseEntityComponent)

function ents.VRHMD:Initialize()
	local toggleC = self:AddEntityComponent(ents.COMPONENT_TOGGLE)
	self:AddEntityComponent(ents.COMPONENT_OWNABLE)
	local tdC = self:AddEntityComponent(ents.COMPONENT_VR_TRACKED_DEVICE)
	self:BindEvent(ents.ToggleComponent.EVENT_ON_TURN_ON, "OnTurnedOn")
	self:BindEvent(ents.ToggleComponent.EVENT_ON_TURN_OFF, "OnTurnedOff")
	self.m_eyes = {}
	self.m_trackedDevices = {}
	self.m_deviceClassToDevice = {}
	self.m_trackedDeviceIndexToTypeIndex = {}
	self.m_roleToController = {}
	self.m_refPose = math.Transform()
	toggleC:TurnOn()

	self:SetTickPolicy(ents.TICK_POLICY_ALWAYS)
end
function ents.VRHMD:InitializeEye(eyeIdx)
	local ent = self:GetEntity():CreateChild("vr_hmd_eye")
	local eyeC = ent:GetComponent(ents.COMPONENT_VR_HMD_EYE)
	if eyeC ~= nil then
		eyeC:Setup(self, eyeIdx)
	end
	ent:Spawn()

	self.m_eyes[eyeIdx] = eyeC
end
function ents.VRHMD:OnTick()
	local events = openvr.poll_events()
	for _, ev in ipairs(events) do
		-- print("Event: ",openvr.event_type_to_string(ev.type))
		if ev.type == openvr.EVENT_BUTTON_PRESS or ev.type == openvr.EVENT_BUTTON_UNPRESS then
			-- print("Button press: ",openvr.button_id_to_string(ev.data.button))
			local deviceIndex = ev.trackedDeviceIndex
			local dev = self:GetTrackedDevice(deviceIndex)
			if dev ~= nil and dev:IsController() then
				local vrC = dev:GetEntity():GetComponent(ents.COMPONENT_VR_CONTROLLER)
				if vrC ~= nil then
					vrC:InjectButtonInput(
						ev.data.button,
						(ev.type == openvr.EVENT_BUTTON_PRESS) and input.STATE_PRESS or input.STATE_RELEASE
					)
				end
			end
		elseif ev.type == openvr.EVENT_BUTTON_TOUCH then
		elseif ev.type == openvr.EVENT_BUTTON_UNTOUCH then
		elseif
			ev.type == openvr.EVENT_TRACKED_DEVICE_ACTIVATED or ev.type == openvr.EVENT_TRACKED_DEVICE_DEACTIVATED
		then
			local deviceId = ev.trackedDeviceIndex
			local type = openvr.get_tracked_device_class(deviceId)
			if type ~= openvr.TRACKED_DEVICE_CLASS_INVALID then
				self:ActivateTrackedDevice(deviceId, type)
			end
		elseif ev.type == openvr.EVENT_TRACKED_DEVICE_DEACTIVATED then
			self:DeactivateTrackedDevice(ev.trackedDeviceIndex)
		elseif ev.type == openvr.EVENT_TRACKED_DEVICE_USER_INTERACTION_STARTED then
			local tdC = self:GetTrackedDevice(ev.trackedDeviceIndex)
			if util.is_valid(tdC) then
				tdC:SetUserInteractionState(ents.VRTrackedDevice.USER_INTERACTION_ACTIVE)
			end
		elseif ev.type == openvr.EVENT_TRACKED_DEVICE_USER_INTERACTION_ENDED then
			local tdC = self:GetTrackedDevice(ev.trackedDeviceIndex)
			if util.is_valid(tdC) then
				tdC:SetUserInteractionState(ents.VRTrackedDevice.USER_INTERACTION_INACTIVE)
			end
		elseif ev.type == openvr.EVENT_TRACKED_DEVICE_ROLE_CHANGED then
			-- Doesn't seem to get called?
		end
	end

	self:InvokeEventCallbacks(ents.VRHMD.EVENT_ON_EVENTS_UPDATED)
end
function ents.VRHMD:ActivateTrackedDevice(deviceId, type)
	if type == openvr.TRACKED_DEVICE_CLASS_CONTROLLER then
		self:AddController(deviceId)
	elseif type == openvr.TRACKED_DEVICE_CLASS_HMD then
		self:AddTrackedDevice(self:GetEntity(), deviceId, type)
	end
	local tdC = self:GetTrackedDevice(deviceId)
	if util.is_valid(tdC) == false then
		return
	end
	tdC:GetEntity():TurnOn()
	local ent = tdC:GetEntity()
	local renderC = ent:GetComponent(ents.COMPONENT_RENDER)
	if renderC ~= nil then
		renderC:SetSceneRenderPass(game.SCENE_RENDER_PASS_WORLD)
	end
	local physC = ent:GetComponent(ents.COMPONENT_PHYSICS)
	if physC ~= nil then
		if self.m_deviceCollisionGroup ~= nil and self.m_deviceCollisionGroup[deviceId] ~= nil then
			physC:SetCollisionFilterGroup(self.m_deviceCollisionGroup[deviceId])
			self.m_deviceCollisionGroup[deviceId] = nil
		end
	end
	self:BroadcastEvent(ents.VRHMD.EVENT_ON_TRACKED_DEVICE_ACTIVATED, { tdC })
	self:BroadcastEvent(ents.VRHMD.EVENT_ON_TRACKED_DEVICE_ACTIVATION_CHANGED, { tdC, true })
end
function ents.VRHMD:DeactivateTrackedDevice(deviceId)
	local tdC = self:GetTrackedDevice(deviceId)
	if util.is_valid(tdC) == false then
		return
	end
	tdC:GetEntity():TurnOff()
	local ent = tdC:GetEntity()
	local renderC = ent:GetComponent(ents.COMPONENT_RENDER)
	if renderC ~= nil then
		renderC:SetSceneRenderPass(game.SCENE_RENDER_PASS_NONE)
	end
	local physC = ent:GetComponent(ents.COMPONENT_PHYSICS)
	if physC ~= nil then
		self.m_deviceCollisionGroup = self.m_deviceCollisionGroup or {}
		self.m_deviceCollisionGroup[deviceId] = self.m_deviceCollisionGroup[deviceId] or physC:GetCollisionFilterGroup()
		physC:SetCollisionFilterGroup(phys.COLLISIONMASK_NO_COLLISION)
	end
	self:BroadcastEvent(ents.VRHMD.EVENT_ON_TRACKED_DEVICE_DEACTIVATED, { tdC })
	self:BroadcastEvent(ents.VRHMD.EVENT_ON_TRACKED_DEVICE_ACTIVATION_CHANGED, { tdC, false })
end
function ents.VRHMD:GetEye(eyeIdx)
	return self.m_eyes[eyeIdx]
end
function ents.VRHMD:GetEyes()
	return self.m_eyes
end
function ents.VRHMD:IsHMDValid()
	return self.m_valid or false
end
function ents.VRHMD:GetErrorMessage()
	return self.m_errMsg
end
function ents.VRHMD:SetDefaultGameRenderEnabled(enabled)
	self.m_defaultGameRenderEnabled = enabled
	if enabled then
		util.remove(self.m_cbDrawMainScene)
	else
		self:InitializeRenderCallbacks()
	end
end
function ents.VRHMD:InitializeDebugMirrorUi()
	if util.is_valid(self.m_debugMirrorUi) then
		self.m_debugMirrorUi:Remove()
	end
	local el = gui.get_base_element()
	self.m_debugMirrorUi = gui.create("WIBase", el, 0, 0, el:GetWidth(), el:GetHeight(), 0, 0, 1, 1)
	local elTexLeft = gui.create(
		"WITexturedRect",
		self.m_debugMirrorUi,
		0,
		0,
		self.m_debugMirrorUi:GetWidth() / 2,
		self.m_debugMirrorUi:GetHeight(),
		0,
		0,
		1,
		1
	)
	local elTexRight = gui.create(
		"WITexturedRect",
		self.m_debugMirrorUi,
		elTexLeft:GetRight(),
		0,
		self.m_debugMirrorUi:GetWidth() / 2,
		self.m_debugMirrorUi:GetHeight(),
		0,
		0,
		1,
		1
	)

	local textures = { elTexLeft, elTexRight }
	for i, eyeIdx in ipairs({ openvr.EYE_LEFT, openvr.EYE_RIGHT }) do
		local eye = self.m_eyes[eyeIdx]
		local elTex = textures[i]
		if eye:IsValid() then
			local renderer = eye:GetRenderer()
			if renderer ~= nil then
				elTex:SetTexture(renderer:GetPresentationTexture())
			end
		end
	end
end
function ents.VRHMD:Setup()
	if self.m_setup or self:GetEntity():IsSpawned() == false then
		return
	end
	local toggleC = self:GetEntity():GetComponent(ents.COMPONENT_TOGGLE)
	if toggleC ~= nil and toggleC:IsTurnedOff() then
		return
	end
	self.m_setup = true

	local result, msg = util.initialize_vr()
	if result == false then
		self:LogErr("Failed to initialize vr: {}", msg)
		self:GetEntity():RemoveSafely()
		return
	end

	self:InitializeEye(openvr.EYE_LEFT)
	self:InitializeEye(openvr.EYE_RIGHT)
	self.m_valid = true

	-- Initialize devices
	for i = 0, openvr.MAX_TRACKED_DEVICE_COUNT - 1 do
		local type = openvr.get_tracked_device_class(i)
		if type ~= openvr.TRACKED_DEVICE_CLASS_INVALID then
			self:ActivateTrackedDevice(i, type)
		end
	end

	openvr.set_tracking_space(openvr.TRACKING_UNIVERSE_ORIGIN_SEATED)

	self:InitializeRenderCallbacks()

	self:BroadcastEvent(ents.VRHMD.EVENT_ON_HMD_INITIALIZED)
	if console.get_convar_bool("vr_debug_mode") then
		self:InitializeDebugMirrorUi()
	end
end
function ents.VRHMD:InitializeRenderCallbacks()
	if self.m_valid ~= true then
		return
	end
	local toggleC = self:GetEntity():GetComponent(ents.COMPONENT_TOGGLE)
	if toggleC ~= nil and toggleC:IsTurnedOff() then
		return
	end
	if util.is_valid(self.m_cbDrawScenes) == false then
		self.m_cbDrawScenes = game.add_callback("RenderScenes", function(drawSceneInfo)
			self:RenderEyes(drawSceneInfo)
		end)
	end
	if util.is_valid(self.m_cbSubmitScenes) == false then
		self.m_cbSubmitScenes = game.add_callback("PostRenderScenes", function()
			self:SubmitEyes()
		end)
	end
end
function ents.VRHMD:GetReferenceEntity()
	local cam = game.get_scene():GetActiveCamera()
	if cam ~= nil then
		return cam:GetEntity()
	end
end
function ents.VRHMD:SetHMDPoseOffset(offsetPose)
	self.m_offsetPose = offsetPose
end
function ents.VRHMD:GetHMDPoseOffset()
	return self.m_offsetPose or math.Transform()
end
function ents.VRHMD:GetReferencePose()
	return self.m_refPose
end
local cvApplyHMDPose = console.get_convar("vr_apply_hmd_pose_to_camera")
local cvUpdateTrackedDevicePoses = console.get_convar("vr_update_tracked_device_poses")
function ents.VRHMD:UpdateHMDPose()
	if cvUpdateTrackedDevicePoses:GetBool() == false then
		return
	end

	local ent = self:GetEntity()
	local hmdPoseData = {}
	if self:InvokeEventCallbacks(ents.VRHMD.EVENT_UPDATE_HMD_POSE, { hmdPoseData }) == util.EVENT_REPLY_UNHANDLED then
		-- Default behavior: Put the HMD relative to the currently active camera
		local tdC = ent:GetComponent(ents.COMPONENT_VR_TRACKED_DEVICE)
		local entRef = self:GetReferenceEntity()
		if tdC ~= nil and entRef ~= nil then
			local pose = entRef:GetPose()
			if cvApplyHMDPose:GetBool() then
				local hmdPose = tdC:GetDevicePose()
				if hmdPose ~= nil then
					pose = pose * hmdPose
				end
			end
			ent:SetPose(pose)
		end
	end

	local pose = hmdPoseData.cameraPose
	if pose ~= nil then
		-- If a custom camera pose was supplied, add the HMD offset pose
		local tdC = ent:GetComponent(ents.COMPONENT_VR_TRACKED_DEVICE)
		local hmdPose = (tdC ~= nil) and tdC:GetDevicePose() or nil
		if hmdPose ~= nil then
			pose = pose * hmdPose
		end
	end
	-- If no custom pose was supplied, use the HMD pose as the VR camera pose
	pose = pose or ent:GetPose()
	for eyeIdx, eye in pairs(self.m_eyes) do
		if eye:IsValid() then
			eye:GetEntity():SetPose(pose)
		end
	end

	self:UpdateTrackedDevicePoses(ent:GetPose())
	-- TODO: Tracked device poses should be clamped by IK

	self:InvokeEventCallbacks(ents.VRHMD.EVENT_ON_HMD_POSE_UPDATED, { pose })
end
function ents.VRHMD:UpdateTrackedDevicePoses(basePose)
	for _, tdC in ipairs(self:GetTrackedDevices()) do
		if tdC:IsValid() and tdC:IsHMD() == false then
			tdC:UpdatePose(basePose)
			if tdC:IsController() then
				local controllerC = tdC:GetEntity():GetComponent(ents.COMPONENT_VR_CONTROLLER)
				if controllerC ~= nil then
					controllerC:UpdateTriggerState()
				end
			end
		end
	end
end
local cvHideGameScene = console.get_convar("vr_hide_primary_game_scene")
function ents.VRHMD:RenderEyes(drawSceneInfo)
	game.set_default_game_render_enabled(not cvHideGameScene:GetBool())
	openvr.update_poses()
	self:UpdateHMDPose()
	for eyeIdx, eye in pairs(self.m_eyes) do
		if eye:IsValid() then
			eye:DrawScene(drawSceneInfo)
		end
	end
end
function ents.VRHMD:SubmitEyes()
	for eyeIdx, eye in pairs(self.m_eyes) do
		if eye:IsValid() then
			eye:SubmitScene()
		end
	end
	prosper.flush()
end
function ents.VRHMD:SetOwner(owner)
	local ownableC = self:GetEntity():GetComponent(ents.COMPONENT_OWNABLE)
	if ownableC == nil then
		return
	end
	ownableC:SetOwner(owner)
end
function ents.VRHMD:GetOwner()
	local ownableComponent = self:GetEntity():GetComponent(ents.COMPONENT_OWNABLE)
	return (ownableComponent ~= nil) and ownableComponent:GetOwner() or nil
end
function ents.VRHMD:OnTurnedOn()
	self:Setup()
	self:InitializeRenderCallbacks()
	if openvr == nil or openvr.is_instance_valid() == false then
		return
	end
	openvr.set_hmd_view_enabled(true)
end
function ents.VRHMD:OnTurnedOff()
	util.remove(self.m_cbDrawScenes)
	util.remove(self.m_cbSubmitScenes)
	game.set_default_game_render_enabled(true)
	if openvr == nil or openvr.is_instance_valid() == false then
		return
	end
	openvr.set_hmd_view_enabled(false)
end
function ents.VRHMD:OnEntitySpawn()
	self:Setup()
end
function ents.VRHMD:GetControllers()
	return self.m_trackedDevices[openvr.TRACKED_DEVICE_CLASS_CONTROLLER] or {}
end
function ents.VRHMD:GetController(controllerIdx)
	if self.m_deviceClassToDevice[openvr.TRACKED_DEVICE_CLASS_CONTROLLER] == nil then
		return
	end
	local tdC = self.m_deviceClassToDevice[openvr.TRACKED_DEVICE_CLASS_CONTROLLER][controllerIdx + 1]
	if util.is_valid(tdC) == false then
		return
	end
	return tdC:GetEntity():GetComponent(ents.COMPONENT_VR_CONTROLLER)
end
function ents.VRHMD:GetPrimaryController()
	return self:GetController(0)
end
function ents.VRHMD:GetSecondaryController()
	return self:GetController(1)
end
function ents.VRHMD:GetTrackedDevice(trackedDeviceIndex)
	return self.m_trackedDevices[trackedDeviceIndex]
end
function ents.VRHMD:GetTrackedDevices()
	return self.m_trackedDevices
end
function ents.VRHMD:GetControllersByRole(role)
	return self.m_roleToController[role] or {}
end
function ents.VRHMD:AddTrackedDevice(ent, trackedDeviceIndex, type)
	self.m_deviceClassToDevice[type] = self.m_deviceClassToDevice[type] or {}

	local function find_free_type_index()
		local typeIndex = 1
		for i, _ in pairs(self.m_deviceClassToDevice[type]) do
			typeIndex = math.max(typeIndex, i + 1)
		end
		return typeIndex
	end

	local tdC = ent:AddComponent(ents.COMPONENT_VR_TRACKED_DEVICE)
	local typeIndex = self.m_trackedDeviceIndexToTypeIndex[trackedDeviceIndex]
	if typeIndex == nil then
		local role = openvr.get_controller_role(trackedDeviceIndex)
		self.m_roleToController[role] = self.m_roleToController[role] or {}
		table.insert(self.m_roleToController[role], tdC)

		local typeIndex
		if role == openvr.TRACKED_CONTROLLER_ROLE_RIGHT_HAND then
			typeIndex = 1
			if self.m_deviceClassToDevice[type][typeIndex] ~= nil then
				self.m_deviceClassToDevice[type][find_free_type_index()] = self.m_deviceClassToDevice[type][typeIndex]
			end
		elseif role == openvr.TRACKED_CONTROLLER_ROLE_LEFT_HAND then
			typeIndex = 2
			if self.m_deviceClassToDevice[type][typeIndex] ~= nil then
				self.m_deviceClassToDevice[type][find_free_type_index()] = self.m_deviceClassToDevice[type][typeIndex]
			end
		else
			typeIndex = find_free_type_index()
		end
		self.m_deviceClassToDevice[type][typeIndex] = tdC
		typeIndex = #self.m_deviceClassToDevice[type]
		self.m_trackedDeviceIndexToTypeIndex[trackedDeviceIndex] = typeIndex
	else
		self.m_deviceClassToDevice[type][typeIndex] = tdC
	end

	self.m_trackedDevices[trackedDeviceIndex] = tdC

	if tdC ~= nil then
		tdC:Setup(self, trackedDeviceIndex, type, typeIndex)
	end
	if ent ~= self:GetEntity() then
		ent:SetOwner(self:GetEntity())
	end

	self:BroadcastEvent(ents.VRHMD.EVENT_ON_TRACKED_DEVICE_ADDED, { tdC })
	return tdC
end
function ents.VRHMD:AddController(trackedDeviceIndex)
	local tdC = self:GetTrackedDevice(trackedDeviceIndex)
	if util.is_valid(tdC) then
		if tdC:IsController() == false then
			return
		end -- Tracked device exists, but isn't a controller?
		return tdC:GetEntity():GetComponent(ents.COMPONENT_VR_CONTROLLER)
	end

	local ent = self:GetEntity():CreateChild("vr_controller")
	if ent == nil then
		return
	end
	local vrC = ent:GetComponent(ents.COMPONENT_VR_CONTROLLER)
	if vrC == nil then
		ent:Remove()
		return
	end
	tdC = self:AddTrackedDevice(ent, trackedDeviceIndex, openvr.TRACKED_DEVICE_CLASS_CONTROLLER)
	ent:Spawn()
	return tdC
end
function ents.VRHMD:OnRemove()
	for eyeIdx, c in pairs(self.m_eyes) do
		if c:IsValid() then
			c:GetEntity():Remove()
		end
	end
	for deviceId, tdC in pairs(self.m_trackedDevices) do
		if tdC:IsValid() then
			tdC:GetEntity():Remove()
		end
	end
	util.remove(self.m_cbDrawScenes)
	util.remove(self.m_cbSubmitScenes)
	util.remove(self.m_debugMirrorUi)
end
ents.register_component("vr_hmd", ents.VRHMD, "vr")
ents.VRHMD.EVENT_ON_TRACKED_DEVICE_ADDED = ents.register_component_event(ents.COMPONENT_VR_HMD, "controller_added")
ents.VRHMD.EVENT_ON_TRACKED_DEVICE_ACTIVATED =
	ents.register_component_event(ents.COMPONENT_VR_HMD, "tracked_device_activated")
ents.VRHMD.EVENT_ON_TRACKED_DEVICE_DEACTIVATED =
	ents.register_component_event(ents.COMPONENT_VR_HMD, "tracked_device_deactivated")
ents.VRHMD.EVENT_ON_TRACKED_DEVICE_ACTIVATION_CHANGED =
	ents.register_component_event(ents.COMPONENT_VR_HMD, "tracked_device_activation_changed")
ents.VRHMD.EVENT_ON_HMD_INITIALIZED = ents.register_component_event(ents.COMPONENT_VR_HMD, "hmd_initialized")
ents.VRHMD.EVENT_ON_HMD_POSE_UPDATED = ents.register_component_event(ents.COMPONENT_VR_HMD, "hmd_pose_updated")
ents.VRHMD.EVENT_ON_EVENTS_UPDATED = ents.register_component_event(ents.COMPONENT_VR_HMD, "on_events_updated")
ents.VRHMD.EVENT_UPDATE_HMD_POSE = ents.register_component_event(ents.COMPONENT_VR_HMD, "update_hmd_pose")
