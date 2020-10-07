--[[
    Copyright (C) 2019  Florian Weischer

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]

include_component("vr_tracked_device")

util.register_class("ents.VRHMD",BaseEntityComponent)

function ents.VRHMD:__init()
	BaseEntityComponent.__init(self)
end

function ents.VRHMD:Initialize()
	local toggleC = self:AddEntityComponent(ents.COMPONENT_TOGGLE)
	self:AddEntityComponent(ents.COMPONENT_OWNABLE)
	self:AddEntityComponent(ents.COMPONENT_LOGIC)
	self:AddEntityComponent(ents.COMPONENT_VR_TRACKED_DEVICE)
	self:BindEvent(ents.ToggleComponent.EVENT_ON_TURN_ON,"OnTurnedOn")
	self:BindEvent(ents.ToggleComponent.EVENT_ON_TURN_OFF,"OnTurnedOff")
	self:BindEvent(ents.LogicComponent.EVENT_ON_TICK,"OnTick")
	self.m_eyes = {}
	self.m_trackedDevices = {}
	self.m_deviceClassToDevice = {}
	self.m_trackedDeviceIndexToTypeIndex = {}
	self.m_refPose = phys.Transform()
	self:SetDefaultGameRenderEnabled(not console.get_convar_bool("vr_hide_primary_game_scene"))
	toggleC:TurnOn()
end
function ents.VRHMD:InitializeEye(eyeIdx)
	local ent = ents.create("vr_hmd_eye")
	local eyeC = ent:GetComponent(ents.COMPONENT_VR_HMD_EYE)
	if(eyeC ~= nil) then eyeC:SetEyeIndex(eyeIdx) end
	ent:Spawn()

	self.m_eyes[eyeIdx] = eyeC
end
function ents.VRHMD:OnTick()
	local events = openvr.poll_events()
	for _,ev in ipairs(events) do
		-- print("Event: ",openvr.event_type_to_string(ev.type))
		if(ev.type == openvr.EVENT_BUTTON_PRESS or ev.type == openvr.EVENT_BUTTON_UNPRESS) then
			-- print("Button press: ",openvr.button_id_to_string(ev.data.button))
			local deviceIndex = ev.trackedDeviceIndex
			local dev = self:GetTrackedDevice(deviceIndex)
			if(dev ~= nil and dev:IsController()) then
				local vrC = dev:GetEntity():GetComponent(ents.COMPONENT_VR_CONTROLLER)
				if(vrC ~= nil) then vrC:InjectButtonInput(ev.data.button,(ev.type == openvr.EVENT_BUTTON_PRESS) and input.STATE_PRESS or input.STATE_RELEASE) end
			end
		elseif(ev.type == openvr.EVENT_BUTTON_TOUCH) then

		elseif(ev.type == openvr.EVENT_BUTTON_UNTOUCH) then

		elseif(ev.type == openvr.EVENT_TRACKED_DEVICE_ACTIVATED or ev.type == openvr.EVENT_TRACKED_DEVICE_DEACTIVATED) then
			local deviceId = ev.trackedDeviceIndex
			local type = openvr.get_tracked_device_class(deviceId)
			if(type ~= openvr.TRACKED_DEVICE_CLASS_INVALID) then
				self:ActivateTrackedDevice(deviceId,type)
			end
		elseif(ev.type == openvr.EVENT_TRACKED_DEVICE_DEACTIVATED) then
			self:DeactivateTrackedDevice(ev.trackedDeviceIndex)
		elseif(ev.type == openvr.EVENT_TRACKED_DEVICE_USER_INTERACTION_STARTED) then
			local tdC = self:GetTrackedDevice(ev.trackedDeviceIndex)
			if(util.is_valid(tdC)) then tdC:SetUserInteractionState(ents.VRTrackedDevice.USER_INTERACTION_ACTIVE) end
		elseif(ev.type == openvr.EVENT_TRACKED_DEVICE_USER_INTERACTION_ENDED) then
			local tdC = self:GetTrackedDevice(ev.trackedDeviceIndex)
			if(util.is_valid(tdC)) then tdC:SetUserInteractionState(ents.VRTrackedDevice.USER_INTERACTION_INACTIVE) end
		end
	end
end
function ents.VRHMD:ActivateTrackedDevice(deviceId,type)
	if(type == openvr.TRACKED_DEVICE_CLASS_CONTROLLER) then self:AddController(deviceId)
	elseif(type == openvr.TRACKED_DEVICE_CLASS_HMD) then self:AddTrackedDevice(self:GetEntity(),deviceId,type) end
	local tdC = self:GetTrackedDevice(deviceId)
	if(util.is_valid(tdC) == false) then return end
	tdC:GetEntity():TurnOn()
	local ent = tdC:GetEntity()
	local renderC = ent:GetComponent(ents.COMPONENT_RENDER)
	if(renderC ~= nil) then renderC:SetRenderMode(ents.RenderComponent.RENDERMODE_WORLD) end
	local physC = ent:GetComponent(ents.COMPONENT_PHYSICS)
	if(physC ~= nil) then
		if(self.m_deviceCollisionGroup ~= nil and self.m_deviceCollisionGroup[deviceId] ~= nil) then
			physC:SetCollisionFilterGroup(self.m_deviceCollisionGroup[deviceId])
			self.m_deviceCollisionGroup[deviceId] = nil
		end
	end
	self:BroadcastEvent(ents.VRHMD.EVENT_ON_TRACKED_DEVICE_ACTIVATED,{tdC})
end
function ents.VRHMD:DeactivateTrackedDevice(deviceId)
	local tdC = self:GetTrackedDevice(deviceId)
	if(util.is_valid(tdC) == false) then return end
	tdC:GetEntity():TurnOff()
	local ent = tdC:GetEntity()
	local renderC = ent:GetComponent(ents.COMPONENT_RENDER)
	if(renderC ~= nil) then renderC:SetRenderMode(ents.RenderComponent.RENDERMODE_NONE) end
	local physC = ent:GetComponent(ents.COMPONENT_PHYSICS)
	if(physC ~= nil) then
		self.m_deviceCollisionGroup = self.m_deviceCollisionGroup or {}
		self.m_deviceCollisionGroup[deviceId] = self.m_deviceCollisionGroup[deviceId] or physC:GetCollisionFilterGroup()
		physC:SetCollisionFilterGroup(phys.COLLISIONMASK_NO_COLLISION)
	end
	self:BroadcastEvent(ents.VRHMD.EVENT_ON_TRACKED_DEVICE_DEACTIVATED,{tdC})
end
function ents.VRHMD:GetEye(eyeIdx) return self.m_eyes[eyeIdx] end
function ents.VRHMD:IsHMDValid() return self.m_valid or false end
function ents.VRHMD:GetErrorMessage() return self.m_errMsg end
function ents.VRHMD:SetDefaultGameRenderEnabled(enabled)
	self.m_defaultGameRenderEnabled = enabled
	if(enabled) then util.remove(self.m_cbDrawMainScene)
	else self:InitializeRenderCallbacks() end
end
function ents.VRHMD:Setup()
	if(self.m_setup or self:GetEntity():IsSpawned() == false) then return end
	local toggleC = self:GetEntity():GetComponent(ents.COMPONENT_TOGGLE)
	if(toggleC ~= nil and toggleC:IsTurnedOff()) then return end
	self.m_setup = true
	local r = engine.load_library("openvr/pr_openvr")
	if(r ~= true) then
		self.m_errMsg = r
		console.print_warning("Unable to load openvr module: " .. r)
		self:GetEntity():RemoveSafely()
		return
	end

	local result = openvr.initialize()
	if(result ~= openvr.INIT_ERROR_NONE) then
		self.m_errMsg = openvr.init_error_to_string(result)
		console.print_warning("Unable to initialize openvr library: " .. openvr.init_error_to_string(result))
		self:GetEntity():RemoveSafely()
		return
	end

	self:InitializeEye(openvr.EYE_LEFT)
	self:InitializeEye(openvr.EYE_RIGHT)
	self.m_valid = true

	-- Initialize devices
	for i=0,openvr.MAX_TRACKED_DEVICE_COUNT -1 do
		local type = openvr.get_tracked_device_class(i)
		if(type ~= openvr.TRACKED_DEVICE_CLASS_INVALID) then
			self:ActivateTrackedDevice(i,type)
		end
	end

	self:InitializeRenderCallbacks()

	self:BroadcastEvent(ents.VRHMD.EVENT_ON_HMD_INITIALIZED)
end
function ents.VRHMD:InitializeRenderCallbacks()
	if(self.m_valid ~= true) then return end
	local toggleC = self:GetEntity():GetComponent(ents.COMPONENT_TOGGLE)
	if(toggleC ~= nil and toggleC:IsTurnedOff()) then return end
	if(util.is_valid(self.m_cbDrawMainScene) == false and self.m_defaultGameRenderEnabled ~= true) then
		self.m_cbDrawMainScene = game.add_callback("DrawScene",function(drawSceneInfo)
			return true -- Disable default rendering of the scene
		end)
	end
	if(util.is_valid(self.m_cbDrawScenes) == false) then
		self.m_cbDrawScenes = game.add_callback("RenderScenes",function(drawSceneInfo)
			self:UpdateHMDPose()
			self:RenderEyes(drawSceneInfo)
		end)
	end
end
function ents.VRHMD:GetCamera()
	return game.get_scene():GetActiveCamera()
end
function ents.VRHMD:GetReferencePose() return self.m_refPose end
local cvApplyHMDPose = console.get_convar("vr_apply_hmd_pose_to_camera")
function ents.VRHMD:UpdateHMDPose()
	local tdC = self:GetEntity():GetComponent(ents.COMPONENT_VR_TRACKED_DEVICE)
	local gameCam = self:GetCamera()
	if(gameCam == nil or tdC == nil) then return end
	local entCam = gameCam:GetEntity()
	self.m_refPose = entCam:GetPose()
	local pose = self.m_refPose
	if(cvApplyHMDPose:GetBool()) then
		local hmdPose = tdC:GetDevicePose()
		if(hmdPose == nil) then return end
		pose = pose *hmdPose
	end

	local pos = pose:GetOrigin()
	local rot = pose:GetRotation()
	--rot = rot:GetInverse()
	
	local ent = self:GetEntity()
	ent:SetPos(pos)
	ent:SetRotation(rot)

	entCam:SetPos(pos)
	entCam:SetRotation(rot)

	self:InvokeEventCallbacks(ents.VRHMD.EVENT_ON_HMD_POSE_UPDATED,{pose})
end
function ents.VRHMD:RenderEyes(drawSceneInfo)
	for eyeIdx,eye in pairs(self.m_eyes) do
		if(eye:IsValid()) then
			eye:DrawScene(drawSceneInfo)
		end
	end
	prosper.flush()
	openvr.update_poses()
end
function ents.VRHMD:SetOwner(owner)
	local ownableC = self:GetEntity():GetComponent(ents.COMPONENT_OWNABLE)
	if(ownableC == nil) then return end
	ownableC:SetOwner(owner)
end
function ents.VRHMD:GetOwner()
	local ownableComponent = self:GetEntity():GetComponent(ents.COMPONENT_OWNABLE)
	return (ownableComponent ~= nil) and ownableComponent:GetOwner() or nil
end
function ents.VRHMD:OnTurnedOn()
	self:Setup()
	self:InitializeRenderCallbacks()
	if(openvr == nil) then return end
	openvr.set_hmd_view_enabled(true)
end
function ents.VRHMD:OnTurnedOff()
	util.remove(self.m_cbDrawMainScene)
	util.remove(self.m_cbDrawScenes)
	if(openvr == nil) then return end
	openvr.set_hmd_view_enabled(false)
end
function ents.VRHMD:OnEntitySpawn()
	self:Setup()
end
function ents.VRHMD:GetControllers() return self.m_trackedDevices[openvr.TRACKED_DEVICE_CLASS_CONTROLLER] or {} end
function ents.VRHMD:GetController(controllerIdx)
	if(self.m_deviceClassToDevice[openvr.TRACKED_DEVICE_CLASS_CONTROLLER] == nil) then return end
	local tdC = self.m_deviceClassToDevice[openvr.TRACKED_DEVICE_CLASS_CONTROLLER][controllerIdx +1]
	if(util.is_valid(tdC) == false) then return end
	return tdC:GetEntity():GetComponent(ents.COMPONENT_VR_CONTROLLER)
end
function ents.VRHMD:GetPrimaryController() return self:GetController(0) end
function ents.VRHMD:GetSecondaryController() return self:GetController(1) end
function ents.VRHMD:GetTrackedDevice(trackedDeviceIndex) return self.m_trackedDevices[trackedDeviceIndex] end
function ents.VRHMD:GetTrackedDevices() return self.m_trackedDevices end
function ents.VRHMD:AddTrackedDevice(ent,trackedDeviceIndex,type)
	self.m_deviceClassToDevice[type] = self.m_deviceClassToDevice[type] or {}

	local tdC = ent:AddComponent(ents.COMPONENT_VR_TRACKED_DEVICE)
	local typeIndex = self.m_trackedDeviceIndexToTypeIndex[trackedDeviceIndex]
	if(typeIndex == nil) then
		table.insert(self.m_deviceClassToDevice[type],tdC)
		typeIndex = #self.m_deviceClassToDevice[type]
		self.m_trackedDeviceIndexToTypeIndex[trackedDeviceIndex] = typeIndex
	else self.m_deviceClassToDevice[type][typeIndex] = tdC end

	self.m_trackedDevices[trackedDeviceIndex] = tdC

	if(tdC ~= nil) then
		tdC:Setup(trackedDeviceIndex,type,typeIndex)
	end
	if(ent ~= self:GetEntity()) then ent:SetOwner(self:GetEntity()) end

	self:BroadcastEvent(ents.VRHMD.EVENT_ON_TRACKED_DEVICE_ADDED,{tdC})
	return tdC
end
function ents.VRHMD:AddController(trackedDeviceIndex)
	local tdC = self:GetTrackedDevice(trackedDeviceIndex)
	if(util.is_valid(tdC)) then
		if(tdC:IsController() == false) then return end -- Tracked device exists, but isn't a controller?
		return tdC:GetEntity():GetComponent(ents.COMPONENT_VR_CONTROLLER)
	end

	local ent = ents.create("vr_controller")
	if(ent == nil) then return end
	local vrC = ent:GetComponent(ents.COMPONENT_VR_CONTROLLER)
	if(vrC == nil) then
		ent:Remove()
		return
	end
	tdC = self:AddTrackedDevice(ent,trackedDeviceIndex,openvr.TRACKED_DEVICE_CLASS_CONTROLLER)
	ent:Spawn()
	return tdC
end
function ents.VRHMD:OnRemove()
	for eyeIdx,c in pairs(self.m_eyes) do
		if(c:IsValid()) then c:GetEntity():Remove() end
	end
	for deviceId,tdC in pairs(self.m_trackedDevices) do
		if(tdC:IsValid()) then tdC:GetEntity():Remove() end
	end
	util.remove(self.m_cbDrawMainScene)
	util.remove(self.m_cbDrawScenes)
end
ents.COMPONENT_VR_HMD = ents.register_component("vr_hmd",ents.VRHMD)
ents.VRHMD.EVENT_ON_TRACKED_DEVICE_ADDED = ents.register_component_event(ents.COMPONENT_VR_HMD,"controller_added")
ents.VRHMD.EVENT_ON_TRACKED_DEVICE_ACTIVATED = ents.register_component_event(ents.COMPONENT_VR_HMD,"tracked_device_activated")
ents.VRHMD.EVENT_ON_TRACKED_DEVICE_DEACTIVATED = ents.register_component_event(ents.COMPONENT_VR_HMD,"tracked_device_deactivated")
ents.VRHMD.EVENT_ON_HMD_INITIALIZED = ents.register_component_event(ents.COMPONENT_VR_HMD,"hmd_initialized")
ents.VRHMD.EVENT_ON_HMD_POSE_UPDATED = ents.register_component_event(ents.COMPONENT_VR_HMD,"hmd_pose_updated")
