--[[
    Copyright (C) 2020  Florian Weischer

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]

console.register_variable("vr_debug_show_controller_location_pointers","0",0,"If enabled, a line will be drawn in front of the camera pointing to the vr controller(s).")
console.register_variable("vr_hide_primary_game_scene","1",0,"If enabled, the default game render will be disabled to save rendering resources.")
console.register_variable("vr_apply_hmd_pose_to_camera","1",0,"If enabled, the HMD pose will be applied to the game camera.")
