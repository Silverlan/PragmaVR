--[[
    Copyright (C) 2020 Silverlan

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]

include("/vr/vr_recording.lua")

util = util or {}
util.impl = util.impl or {}
util.initialize_vr = function()
	if util.impl.vr_module_result == false then
		return false, util.impl.vr_module_result
	else
		local result = engine.load_library("openvr/pr_openvr")
		util.impl.vr_module_result = result
		if result ~= true then
			return false, result
		end
	end

	if util.impl.vr_initialized == false then
		return false, util.impl.vr_initialized_message
	else
		local result = openvr.initialize()
		util.impl.vr_initialized = result
		if result ~= openvr.INIT_ERROR_NONE then
			util.impl.vr_initialized_message = openvr.init_error_to_string(result)
			return false, openvr.init_error_to_string(result)
		end
	end
	return true
end

console.register_variable(
	"vr_debug_show_controller_location_pointers",
	udm.TYPE_BOOLEAN,
	false,
	0,
	"If enabled, a line will be drawn in front of the camera pointing to the vr controller(s)."
)

console.register_variable(
	"vr_hide_primary_game_scene",
	udm.TYPE_BOOLEAN,
	true,
	0,
	"If enabled, the default game render will be disabled to save rendering resources."
)

console.register_variable(
	"vr_apply_hmd_pose_to_camera",
	udm.TYPE_BOOLEAN,
	true,
	0,
	"If enabled, the HMD pose will be applied to the game camera."
)

console.register_variable(
	"vr_freeze_tracked_device_poses",
	udm.TYPE_BOOLEAN,
	false,
	0,
	"If enabled, all tracked vr devices will freeze in their current places."
)

console.register_variable(
	"vr_update_tracked_device_poses",
	udm.TYPE_BOOLEAN,
	true,
	0,
	"If disabled, tracked device poses will not be updated."
)

locale.load("vr_components.txt")

local g_debug_hmd
console.register_command("vr_debug_launch", function()
	if util.is_valid(g_debug_hmd) then
		util.remove(g_debug_hmd)
		return
	end
	local pl = ents.get_local_player()
	if pl == nil then
		return
	end
	local vrHmd = ents.create("vr_hmd")
	vrHmd:Spawn()

	local hmdC = vrHmd:GetComponent(ents.COMPONENT_VR_HMD)
	if hmdC ~= nil then
		hmdC:SetOwner(pl:GetEntity())
	end
	g_debug_hmd = vrHmd

	console.run("vr_hide_primary_game_scene", "0")
	-- console.run("vr_lock_hmd_pos_to_camera","1")
	-- console.run("vr_lock_hmd_ang_to_camera","1")
end)

console.register_command("vr_tracked_devices", function()
	for ent in ents.iterator({ ents.IteratorFilterComponent(ents.COMPONENT_VR_TRACKED_DEVICE) }) do
		local trC = ent:GetComponent(ents.COMPONENT_VR_TRACKED_DEVICE)
		local type = trC:GetType()
		local strType = ""
		if type == openvr.TRACKED_DEVICE_CLASS_HMD then
			strType = "HMD"
		elseif type == openvr.TRACKED_DEVICE_CLASS_CONTROLLER then
			strType = "Controller"
		elseif type == openvr.TRACKED_DEVICE_CLASS_GENERIC_TRACKER then
			strType = "Generic Tracker"
		elseif type == openvr.TRACKED_DEVICE_CLASS_TRACKING_REFERENCE then
			strType = "Tracking Reference"
		else
			strType = "Unknown"
		end
		print("Found tracked device: " .. tostring(ent) .. " of type " .. strType)
		local pose, vel = openvr.get_pose(trC:GetTrackedDeviceIndex())
		if pose ~= nil then
			print("\tPos: ", pose:GetOrigin())
			print("\tAng: ", pose:GetRotation():ToEulerAngles())
			print("\tVel: ", vel)
		end
	end
end)

console.register_command("vr_hmd_pose", function()
	local ent = ents.iterator({ ents.IteratorFilterComponent(ents.COMPONENT_VR_HMD) })()
	if ent == nil then
		console.print_warning("No HMD found!")
		return
	end
	local pose = ent:GetPose()
	print("World Space: ", pose)

	local trC = ent:GetComponent(ents.COMPONENT_VR_TRACKED_DEVICE)
	if trC == nil then
		return
	end
	local pose, vel = trC:GetDevicePose()
	print("Head Space: ", pose)
	print("Velocity: ", vel)
end)

console.register_command("vr_pose_wait_time", function()
	if openvr == nil then
		console.print_warning("OpenVR module has not been loaded!")
		return
	end
	print("Last pose wait time: " .. openvr.get_pose_wait_time() .. "ms")
end)

console.register_variable(
	"vr_lock_hmd_pos_to_camera",
	udm.TYPE_BOOLEAN,
	false,
	0,
	"If enabled, relative HMD motion will be ignored."
)

console.register_variable(
	"vr_lock_hmd_ang_to_camera",
	udm.TYPE_BOOLEAN,
	false,
	0,
	"If enabled, relative HMD rotation will be ignored."
)

console.register_variable(
	"vr_render_both_eyes_if_hmd_inactive",
	udm.TYPE_BOOLEAN,
	false,
	0,
	"If enabled, both eyes will be rendered even if the HMD is not put on."
)

console.register_variable(
	"vr_force_always_active",
	udm.TYPE_BOOLEAN,
	false,
	0,
	"If enabled, HMD will never be put into inactive state."
)

console.register_variable(
	"vr_show_rendermodels",
	udm.TYPE_BOOLEAN,
	false,
	0,
	"If enabled, tracked devices will be rendered as models."
)

console.register_variable("vr_debug_mode", udm.TYPE_BOOLEAN, false, 0, "Enables the vr developer debug mode.")

console.register_variable(
	"vr_resolution_override",
	udm.TYPE_STRING,
	"",
	0,
	"Forces VR to run with this resolution instead of the one recommended by the API."
)

console.register_variable(
	"vr_mirror_eye_view",
	udm.TYPE_INT8,
	-1,
	0,
	"Mirrors the image of the specified eye onto the game viewport (-1 = disabled, 0 = left eye, 1 = right eye)"
)

console.add_change_callback("vr_force_always_active", function(old, new)
	for ent in ents.iterator({ ents.IteratorFilterComponent(ents.COMPONENT_VR_TRACKED_DEVICE) }) do
		ent:GetComponent(ents.COMPONENT_VR_TRACKED_DEVICE):SetForceActive(toboolean(new))
	end
end)

console.add_change_callback("vr_show_rendermodels", function(old, new)
	for ent in ents.iterator({ ents.IteratorFilterComponent(ents.COMPONENT_VR_TRACKED_DEVICE) }) do
		ent:GetComponent(ents.COMPONENT_VR_TRACKED_DEVICE):UpdateRenderModel()
	end
end)

console.register_command("vr_reset_body", function()
	local ent = ents.iterator({ ents.IteratorFilterComponent(ents.COMPONENT_VR_POV_CONTROLLER) })()
	if ent == nil then
		console.print_warning("No VR body found!")
		return
	end
	local vrBodyC = ent:GetComponent(ents.COMPONENT_VR_POV_CONTROLLER)
	vrBodyC:ResetIk()
end)

console.register_command("vr_recording_mode", function()
	console.run("vr_render_both_eyes_if_hmd_inactive", "0")
	console.run("vr_debug_mode", "0")
	--console.run("vr_mirror_eye_view","0")
	console.run("vr_hide_primary_game_scene", "1")
	console.run("cl_render_frustum_culling_enabled", "0")

	local entHmd = ents.iterator({ ents.IteratorFilterComponent(ents.COMPONENT_VR_HMD) })()
	if entHmd ~= nil then
		local hmdC = entHmd:GetComponent(ents.COMPONENT_VR_HMD)
		local eyeC = hmdC:GetEye(openvr.EYE_RIGHT)
		if util.is_valid(eyeC) then
			eyeC:SetRenderEnabled(false)
		end
	end
end)
