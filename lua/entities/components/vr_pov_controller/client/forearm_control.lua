-- SPDX-FileCopyrightText: (c) 2024 Silverlan <opensource@pragma-engine.com>
-- SPDX-License-Identifier: MIT

local Component = ents.VrPovController

function Component:UpdateForearmControls()
	local entRef = self:GetTargetActor()
	local ikC = util.is_valid(entRef) and entRef:GetComponent(ents.COMPONENT_IK_SOLVER) or nil
	--print(self.m_rightHandIkControlIdx)
	if
		ikC == nil
		or self.m_spineMetaBoneId == nil
		or self.m_leftForearmIkControlIdx == nil
		or self.m_rightForearmIkControlIdx == nil
	then
		return
	end
	local mdl = entRef:GetModel()
	local metaRig = mdl:GetMetaRig()
	local animC = entRef:GetComponent(ents.COMPONENT_ANIMATED)
	local spinePose = animC:GetMetaBonePose(self.m_spineMetaBoneId, math.COORDINATE_SPACE_OBJECT)

	--mdl:GetReferenceMetaPose(self.m_spineMetaBoneId)
	local pos = spinePose:GetOrigin()
	local rot = spinePose:GetRotation()
	local forward = rot:GetForward()
	local right = rot:GetRight()
	local up = rot:GetUp()
	local charScale = metaRig:GetReferenceScale()
	-- TODO: Use character scale
	local forwardOffset = -10.0
	local sideOffset = 5.0
	local upOffset = -20.0

	local leftLowerArmPose = mdl:GetMetaRigReferencePose(Model.MetaRig.BONE_TYPE_LEFT_LOWER_ARM)
	local rightLowerArmPose = mdl:GetMetaRigReferencePose(Model.MetaRig.BONE_TYPE_RIGHT_LOWER_ARM)
	local leftRelOffset = spinePose:GetInverse() * leftLowerArmPose:GetOrigin()
	local rightRelOffset = spinePose:GetInverse() * rightLowerArmPose:GetOrigin()

	local leftForearmPos = spinePose * leftRelOffset
		+ forward * forwardOffset * charScale
		- right * sideOffset * charScale
		+ up * upOffset * charScale
	local rightForearmPos = spinePose * rightRelOffset
		+ forward * forwardOffset * charScale
		+ right * sideOffset * charScale
		+ up * upOffset * charScale

	--leftForearmPos = leftLowerArmPose:GetOrigin()
	--rightForearmPos = rightLowerArmPose:GetOrigin()

	ikC:SetTransformMemberPos(self.m_leftForearmIkControlIdx, math.COORDINATE_SPACE_OBJECT, leftForearmPos)
	ikC:SetTransformMemberPos(self.m_rightForearmIkControlIdx, math.COORDINATE_SPACE_OBJECT, rightForearmPos)

	local drawInfo = debug.DrawInfo()
	drawInfo:SetDuration(0.1)
	drawInfo:SetColor(Color.Red)
	debug.draw_line(leftForearmPos, leftForearmPos + Vector(0, 15, 0), drawInfo)
	drawInfo:SetColor(Color.Lime)
	debug.draw_line(rightForearmPos, rightForearmPos + Vector(0, 15, 0), drawInfo)
end
