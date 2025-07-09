-- SPDX-FileCopyrightText: (c) 2023 Silverlan <opensource@pragma-engine.com>
-- SPDX-License-Identifier: MIT

util.register_class("ents.VrControllerLaser", BaseEntityComponent)

local Component = ents.VrControllerLaser
Component.impl = Component.impl or {}
function Component:Initialize()
	BaseEntityComponent.Initialize(self)

	self:AddEntityComponent(ents.COMPONENT_TRANSFORM)
	self:AddEntityComponent(ents.COMPONENT_MODEL)
	self:AddEntityComponent(ents.COMPONENT_RENDER)
end

function Component:GetModel()
	if Component.impl.model ~= nil then
		return Component.impl.model
	end
	local mdl = game.create_model()
	local meshGroup = mdl:GetMeshGroup(0)

	local mesh = game.Model.Mesh.Create()
	local meshBase = game.Model.Mesh.Sub.create_cylinder(game.Model.CylinderCreateInfo(0.2, 1.0))
	meshBase:SetSkinTextureIndex(0)
	mesh:AddSubMesh(meshBase)

	meshGroup:AddMesh(mesh)

	mdl:Update(game.Model.FUPDATE_ALL)
	mdl:AddMaterial(0, "pfm/gizmo")

	meshBase:SetCenter(Vector())

	return mdl
end

function Component:OnEntitySpawn()
	local mdl = self:GetModel()
	self:GetEntity():SetModel(mdl)
end
ents.register_component("vr_controller_laser", Component, "vr", ents.EntityComponent.FREGISTER_BIT_HIDE_IN_EDITOR)
