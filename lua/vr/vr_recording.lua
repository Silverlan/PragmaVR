-- SPDX-FileCopyrightText: (c) 2022 Silverlan <opensource@pragma-engine.com>
-- SPDX-License-Identifier: MIT

local vr_start_recording
local vr_end_recording
local vr_play_recording

local recorder
local recordingName

local function setup_uuids()
	local entHmd = ents.iterator({ ents.IteratorFilterComponent(ents.COMPONENT_VR_HMD) })()
	if entHmd == nil then
		return
	end
	local hmdC = entHmd:GetComponent(ents.COMPONENT_VR_HMD)
	hmdC:GetEntity():SetUuid(util.generate_uuid_v4("vr_hmd"))

	local primaryController = hmdC:GetPrimaryController()
	if primaryController ~= nil then
		primaryController:GetEntity():SetUuid(util.generate_uuid_v4("vr_primary_controller"))
	end

	local secondaryController = hmdC:GetSecondaryController()
	if secondaryController ~= nil then
		secondaryController:GetEntity():SetUuid(util.generate_uuid_v4("vr_secondary_controller"))
	end

	hmdC:GetEye(openvr.EYE_LEFT):GetEntity():SetUuid(util.generate_uuid_v4("vr_hmd_eye_left"))
	hmdC:GetEye(openvr.EYE_RIGHT):GetEntity():SetUuid(util.generate_uuid_v4("vr_hmd_eye_right"))

	local cam = hmdC:GetCamera()
	if cam ~= nil then
		hmdC:GetEntity():SetUuid(util.generate_uuid_v4("vr_camera"))
	end
end

vr_start_recording = function(pl, name)
	vr_end_recording(true)
	local entHmd = ents.iterator({ ents.IteratorFilterComponent(ents.COMPONENT_VR_HMD) })()
	if entHmd == nil then
		console.print_warning("Unable to start VR recording: HMD not found!")
		return
	end
	setup_uuids()

	recorder = ents.create("game_animation_recorder")
	recorder:Spawn()

	local recorderC = recorder:GetComponent("game_animation_recorder")
	recorderC:AddEntity(entHmd)

	local hmdC = entHmd:GetComponent(ents.COMPONENT_VR_HMD)

	local primaryController = hmdC:GetPrimaryController()
	if primaryController ~= nil then
		recorderC:AddEntity(primaryController:GetEntity())
	end

	local secondaryController = hmdC:GetSecondaryController()
	if secondaryController ~= nil then
		recorderC:AddEntity(secondaryController:GetEntity())
	end

	local cam = hmdC:GetCamera()
	if cam ~= nil then
		recorderC:AddEntity(cam:GetEntity())
	end

	recorderC:AddEntity(hmdC:GetEye(openvr.EYE_LEFT):GetEntity())
	recorderC:AddEntity(hmdC:GetEye(openvr.EYE_RIGHT):GetEntity())

	local entProject = ents.iterator({ ents.IteratorFilterComponent("pfm_project") })()
	if entProject ~= nil then
		recorderC:AddEntity(entProject, { ["pfm_project"] = { "playbackOffset" } })
	end

	recordingName = name or "demo"
	print("Starting recording '" .. recordingName .. "'...")
	recorderC:StartRecording()
end

vr_end_recording = function(cancel)
	if util.is_valid(recorder) == false then
		console.print_warning("Unable to end VR recording: Recorder not found!")
		return
	end
	if cancel ~= true then
		local recorderC = recorder:GetComponent("game_animation_recorder")
		recorderC:EndRecording()

		file.create_directory("recordings")
		local path = "recordings/" .. recordingName
		local res = recorderC:Save(path)
		if res == false then
			console.print_warning("Unable to save recording as '" .. path .. "'")
		else
			print("Recording successfully saved as '" .. path .. "'!")
		end
	end

	util.remove(recorder)
end

local player
local renderRecorder
vr_render_recording = function(pl, recordingName)
	setup_uuids()
	recordingName = recordingName or "demo"
	util.remove(player)
	player = ents.create("game_animation_player")
	player:Spawn()

	console.run("vr_update_tracked_device_poses", "0")

	local entHmd = ents.iterator({ ents.IteratorFilterComponent(ents.COMPONENT_VR_HMD) })()
	if entHmd ~= nil then
		local hmdC = entHmd:GetComponent(ents.COMPONENT_VR_HMD)
		hmdC:GetEye(openvr.EYE_LEFT):GetEntity():ClearParent()
		hmdC:GetEye(openvr.EYE_RIGHT):GetEntity():ClearParent()
	end

	-- Initialize renderer
	include("/vr/vr_sequence_recorder.lua")

	local playerC = player:GetComponent("game_animation_player")
	local path = "recordings/" .. recordingName
	if playerC:Load(path) == true then
		playerC:PlayAnimation()

		renderRecorder = pfm.VrRecorder(tool.get_vr_player())
		renderRecorder:StartRecording("render/recording/recording")
	else
		console.print_warning("Failed to load recording '" .. path .. "'...")
	end
end

console.register_command("vr_start_recording", vr_start_recording)
console.register_command("vr_end_recording", vr_end_recording)
console.register_command("vr_render_recording", vr_render_recording)

--[[function vr_stop_play_recording()
	util.remove(player)
	console.run("vr_update_tracked_device_poses","1")
end]]

-- Freeze controller poses?

-- vr_debug_launch

-- vr_lock_hmd_pos_to_camera 0; vr_lock_hmd_ang_to_camera 0

-- vr_start_recording

-- vr_end_recording

-- vr_play_recording

-- lua_exec_cl vr_recording.lua

-- lc vr_start_recording('test')

-- lc vr_end_recording()

-- lc vr_play_recording('test')

-- lc vr_stop_play_recording('test')

-- udm_convert recordings/test.pgma_b

-- lc
