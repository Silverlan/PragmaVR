--[[
    Copyright (C) 2021 Silverlan

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]

util.register_class("ents.VrIk", BaseEntityComponent)

local Component = ents.VrIk
function Component:__init()
	BaseEntityComponent.__init(self)
end

function Component:Initialize()
	BaseEntityComponent.Initialize(self)

	self:AddEntityComponent(ents.COMPONENT_ANIMATED)
	-- self:AddEntityComponent(ents.COMPONENT_IK)
	-- self:BindEvent(ents.AnimatedComponent.EVENT_UPDATE_BONE_POSES,"UpdateIkTrees")

	self.m_ikControllers = {}
	self.m_ikControllerNames = {}
	self.m_ikControllerPriorityDirty = false

	self:SetEnabled(true)
end

function Component:CreateEffector(ikControllerIdx, effectorIdx)
	local entEffector = ents.create("entity")
	--local ikC = entEffector:AddComponent("pfm_ik_effector_target")
	--if(ikC ~= nil) then ikC:SetTargetActor(self:GetEntity(),ikControllerIdx,effectorIdx) end -- TODO
	if self:GetEntity():IsSpawned() then
		entEffector:Spawn()
	end
	return entEffector
end

--[[function Component:AddIkController(name,trackedDevice,ikControllerIdx,effectorIdx)
	if(self.m_ikControllers[name] ~= nil) then return end
	self.m_ikControllers[name] = {
		trackedDevice = trackedDevice,
		effector = self:CreateEffector(ikControllerIdx,effectorIdx)
	}
	self:InitializeIkTree(name)
end]]

function Component:LinkIkControllerToTrackedDevice(name, trackedDevice)
	if self.m_ikControllers[name] == nil then
		return
	end
	self.m_ikControllers[name].trackedDevice = trackedDevice
end

function Component:GetTrackedDevice(name)
	if self.m_ikControllers[name] == nil then
		return
	end
	return self.m_ikControllers[name].trackedDevice
end

function Component:SortIkControllers()
	if self.m_ikControllerPriorityDirty == false then
		return
	end
	table.sort(self.m_ikControllerNames, function(a, b)
		return self:GetIkControllerPriority(a) < self:GetIkControllerPriority(b)
	end)
	self.m_ikControllerPriorityDirty = false
end

function Component:GetIkControllerPriority(name)
	return (self.m_ikControllers[name] ~= nil) and self.m_ikControllers[name].priority or -1
end
function Component:SetIkControllerPriority(name, priority)
	if self.m_ikControllers[name] == nil then
		return
	end
	self.m_ikControllers[name].priority = priority
end

function Component:GetIkControllerBoneChain(name)
	return (self.m_ikControllers[name] ~= nil) and self.m_ikControllers[name].ikChain or nil
end
function Component:GetIkSolver(name)
	return (self.m_ikControllers[name] ~= nil) and self.m_ikControllers[name].ikSolver or nil
end

function Component:AddIkController(name, ikChain, effectorOffsetPose)
	if self.m_ikControllers[name] ~= nil then
		return
	end

	self.m_ikControllers[name] = {
		trackedDevice = trackedDevice,
		effector = self:CreateEffector(ikControllerIdx, effectorIdx),
		effectorOffsetPose = effectorOffsetPose or math.Transform(),
	}
	table.insert(self.m_ikControllerNames, name)
	self.m_ikControllerPriorityDirty = true
	self:InitializeIkTree(name, ikChain)
end

function Component:SetDebugDrawIkTree(draw)
	draw = draw or false
	if draw == util.is_valid(self.m_cbDebugDraw) then
		return
	end
	if draw == false then
		util.remove(self.m_cbDebugDraw)
		return
	end
	self.m_cbDebugDraw = game.add_callback("Think", function()
		self:DebugDraw()
	end)
end

function Component:DebugDraw(name)
	if name == nil then
		for name, _ in pairs(self.m_ikControllers) do
			self:DebugDraw(name)
		end
		return
	end

	local ikData = self.m_ikControllers[name]
	local effectorPos = self:GetEffectorPos(name)
	local animC = self:GetEntity():GetComponent(ents.COMPONENT_ANIMATED)
	if ikData.ikSolver == nil or animC == nil then
		return
	end

	local solver = ikData.ikSolver
	local originPose = animC:GetGlobalBonePose(ikData.ikChain[1])
	local parentPose = originPose
	originPose = originPose * solver:GetGlobalTransform(0):GetInverse()
	for i = 2, solver:Size() do
		local pose = originPose * solver:GetGlobalTransform(i - 1)
		debug.draw_line(parentPose:GetOrigin(), pose:GetOrigin(), Color.Red, 0.0001)
		debug.draw_line(pose:GetOrigin(), pose:GetOrigin() + pose:GetRotation():GetUp() * 1, Color.Yellow, 0.0001)
		parentPose = pose
	end
	debug.draw_line(effectorPos, effectorPos + Vector(0, 10, 0), Color.Lime, 0.0001)
end

function Component:OnRemove()
	self:SetDebugDrawIkTree(false)
	for name, data in pairs(self.m_ikControllers) do
		util.remove(data.effector)
	end
end

function Component:SetIkControllerEnabled(name, enabled)
	if self.m_ikControllers[name] == nil then
		return
	end
	self.m_ikControllers[name].enabled = enabled
end

function Component:SetEffectorPos(name, pos)
	if self.m_ikControllers[name] == nil or util.is_valid(self.m_ikControllers[name].effector) == false then
		return
	end
	self.m_ikControllers[name].effector:SetPos(pos)
end
function Component:SetEffectorPose(name, pose)
	if self.m_ikControllers[name] == nil or util.is_valid(self.m_ikControllers[name].effector) == false then
		return
	end
	self.m_ikControllers[name].effector:SetPose(pose)
end

function Component:GetEffectorPos(name)
	return (self.m_ikControllers[name] ~= nil and util.is_valid(self.m_ikControllers[name].effector))
			and self.m_ikControllers[name].effector:GetPos()
		or nil
end
function Component:GetEffectorPose(name)
	return (self.m_ikControllers[name] ~= nil and util.is_valid(self.m_ikControllers[name].effector))
			and self.m_ikControllers[name].effector:GetPose()
		or nil
end
function Component:GetEffectorTarget(name)
	return self.m_ikControllers[name] and self.m_ikControllers[name].effector or nil
end

function Component:OnEntitySpawn()
	for name, data in pairs(self.m_ikControllers) do
		if util.is_valid(data.effector) and data.effector:IsSpawned() == false then
			data.effector:Spawn()
		end
	end
end

function Component:SetEnabled(enabled)
	if enabled == self.m_enabled then
		return
	end
	self.m_enabled = enabled
end

function Component:IsEnabled()
	return self.m_enabled
end

function Component:UpdateIkTrees()
	--if(true) then return end
	if self:IsEnabled() == false then
		return
	end
	local animC = self:GetEntity():GetComponent(ents.COMPONENT_ANIMATED)
	if animC == nil then
		return
	end
	if self.m_ikControllerPriorityDirty then
		self:SortIkControllers()
	end
	for name, data in pairs(self.m_ikControllers) do
		self:ResetIkTree(name) -- TODO: This is very expensive, how can we optimize it?
		if util.is_valid(data.trackedDevice) then
			local pose = data.trackedDevice:GetEntity():GetPose()
			self:SetEffectorPose(name, pose)
		end
	end

	self:InvokeEventCallbacks(ents.VrIk.EVENT_PRE_IK_TREES_UPDATED)
	for _, name in ipairs(self.m_ikControllerNames) do
		local ikData = self.m_ikControllers[name]
		if ikData.ikSolver ~= nil and ikData.enabled == true then
			local effectorPose = self:GetEffectorPose(name)
			local targetPose = effectorPose

			local mdl = self:GetEntity():GetModel()
			local bone = mdl:GetSkeleton():GetBone(ikData.ikChain[1])
			local parent = bone:GetParent()
			local rootAnimPose = (parent ~= nil) and animC:GetGlobalBonePose(parent:GetID())
				or self:GetEntity():GetPose()
			local test = animC:GetBonePose(ikData.ikChain[1])
			rootAnimPose:TranslateLocal(-test:GetOrigin())

			targetPose = rootAnimPose:GetInverse() * targetPose
			--test = test or ikData.ikSolver:GetGlobalTransform(1)
			--targetPose:SetOrigin(test:GetOrigin())
			ikData.ikSolver:Solve(targetPose)

			local rootIkPose = ikData.ikSolver:GetGlobalTransform(0)
			local rootPose = rootAnimPose * rootIkPose --math.ScaledTransform(rootAnimPose:GetOrigin(),rootIkPose:GetRotation(),rootAnimPose:GetScale())
			animC:SetGlobalBonePose(ikData.ikChain[1], rootPose)

			local parentPose = rootPose
			for i = 2, #ikData.ikChain do
				local boneId = ikData.ikChain[i]
				local ikPose = ikData.ikSolver:GetGlobalTransform(i - 2):GetInverse()
					* ikData.ikSolver:GetGlobalTransform(i - 1)
				local relPose = parentPose:GetInverse() * ikPose
				animC:SetBonePose(boneId, ikPose)
				parentPose = ikPose

				if i == #ikData.ikChain then
					local pose = animC:GetGlobalBonePose(boneId)
					--pose:SetRotation(effectorPose:GetRotation() *EulerAngles(90,-90,0):ToQuaternion())--effectorPose:GetRotation() *ikPose:GetRotation())
					--pose:SetRotation(effectorPose:GetRotation() *EulerAngles(-90,90,0):ToQuaternion())--effectorPose:GetRotation() *ikPose:GetRotation())
					pose:SetRotation(effectorPose:GetRotation() * ikData.effectorOffsetPose:GetRotation())
					animC:SetGlobalBonePose(boneId, pose)
					--print(ikPose:GetRotation() *effectorPose:GetRotation():GetInverse())
				end

				-- Fix lengths
				local parentId = mdl:GetSkeleton():GetBone(boneId):GetParent():GetID()
				local refLen = mdl:GetReferencePose()
					:GetBonePose(parentId)
					:GetOrigin()
					:Distance(mdl:GetReferencePose():GetBonePose(boneId):GetOrigin())
				local localParentPose = animC:GetBonePose(parentId)
				local localPose = animC:GetBonePose(boneId)
				localPose:SetOrigin(
					localParentPose:GetOrigin()
						+ (localPose:GetOrigin() - localParentPose:GetOrigin()):GetNormal() * refLen
				)
				animC:SetBonePose(boneId, localPose)
				--print(refLen)

				-- Angular constraints
				--parentPose = ikPose
			end
			--[[for i=1,#ikData.ikChain -1 do
				local parentPose = ikData.ikSolver:GetGlobalTransform(i -1)
				local pose = ikData.ikSolver:GetGlobalTransform(i)
				local offset = Vector(0,70,0)
				debug.draw_line(parentPose:GetOrigin() +offset,pose:GetOrigin() +offset,Color.Magenta,0.1)
				if(i == #ikData.ikChain -1) then
					debug.draw_line(pose:GetOrigin() +offset,targetPose:GetOrigin() +offset,Color.Aqua,0.1)
				end
			end

			local parentPose = math.ScaledTransform()
			for i,boneId in ipairs(ikData.ikChain) do
				local ikPose = ikData.ikSolver:GetGlobalTransform(i -1)
				local relPose = parentPose:GetInverse() *ikPose
				animC:SetBonePose(boneId,relPose)
				parentPose = ikPose
			end]]
		end
	end
	self:InvokeEventCallbacks(ents.VrIk.EVENT_ON_IK_TREES_UPDATED)
end

function Component:ResetIkTree(name)
	if self.m_ikControllers[name] == nil then
		return
	end
	local ikData = self.m_ikControllers[name]
	local mdl = self:GetEntity():GetModel()
	if mdl == nil then
		return
	end
	local animC = self:GetEntity():GetComponent(ents.COMPONENT_ANIMATED)
	local ref = mdl:GetReferencePose()
	local skeleton = mdl:GetSkeleton()
	-- The ik tree is defined relative to the root bone it's assigned to.
	-- Since ik has an effect on the rotation only of the root bone (and not the translation),
	-- we use the inverse of the root bone rotation as base and ignore the position.
	local boneIds = ikData.ikChain
	local solver = ikData.ikSolver
	local bone = skeleton:GetBone(boneIds[1])
	local parent = bone:GetParent()
	local rootPose = (parent ~= nil) and animC:GetGlobalBonePose(parent:GetID()) or self:GetEntity():GetPose()
	local test = animC:GetGlobalBonePose(boneIds[1])
	test = rootPose:GetInverse() * test
	rootPose:TranslateLocal(-test:GetOrigin())

	local parentPose = rootPose
	for i = 1, #boneIds do
		local boneId = boneIds[i]
		local bone = skeleton:GetBone(boneId)
		local pose = animC:GetGlobalBonePose(boneId)
		local relPose = parentPose:GetInverse() * pose
		parentPose = pose
		solver:SetLocalTransform(i - 1, relPose)
	end
end

function Component:InitializeIkTree(name, ikChain)
	if #ikChain == 0 then
		return
	end
	local ikData = self.m_ikControllers[name]
	local solver = ik.FABRIkSolver() -- CCDIkSolver()

	local mdl = self:GetEntity():GetModel()
	if mdl == nil then
		return
	end

	solver:Resize(#ikChain)

	local boneIds = {}
	for i = 1, #ikChain do
		local boneId = (type(ikChain[i]) == "string") and mdl:LookupBone(ikChain[i]) or ikChain[i]
		if boneId == -1 then
			console.print_warning("Unknown bone '" .. ikChain[i] .. "' for ik tree '" .. name .. "'!")
			self.m_ikControllers[name] = nil
			for i, nameOther in pairs(self.m_ikControllerNames) do
				if nameOther == name then
					self.m_ikControllerNames[i] = nil
					break
				end
			end
			return
		end
		table.insert(boneIds, boneId)
	end

	ikData.ikSolver = solver
	ikData.ikChain = boneIds
	ikData.enabled = true
	self:ResetIkTree(name)
end
ents.COMPONENT_VR_IK = ents.register_component("vr_ik", Component)
Component.EVENT_ON_IK_TREES_UPDATED = ents.register_component_event(ents.COMPONENT_VR_IK, "on_ik_trees_updated")
Component.EVENT_PRE_IK_TREES_UPDATED = ents.register_component_event(ents.COMPONENT_VR_IK, "pre_ik_trees_updated")
