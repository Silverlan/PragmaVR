/*
    Copyright (C) 2019  Silverlan

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
*/

#version 440

#extension GL_ARB_separate_shader_objects : enable
#extension GL_ARB_shading_language_420pack : enable

#include "/math/equirectangular.glsl"
#include "equirectangular.glsl"

layout(LAYOUT_ID(TEXTURE,TEXTURE)) uniform sampler2D u_texture;

layout(location = 0) in vec2 vs_vert_uv;
layout(location = 1) in vec3 vs_vert_world_dir;

layout(location = 0) out vec4 fs_color;

void main()
{
	vec2 uv = vs_vert_uv;
	vec4 colorMod = vec4(1,1,1,1);
	if((u_pushConstants.shaderFlags &SHADER_FLAG_2D_BIT) == 0)
	{
		vec3 dir = normalize(vs_vert_world_dir);
		uv = direction_to_equirectangular_uv_coordinates(dir,u_pushConstants.horizontalFactor);

		float d = dot(dir,vec3(1,0,0));
		float margin = 0.1;
		if(d < margin && (u_pushConstants.shaderFlags &SHADER_FLAG_ENABLE_MARGIN) != 0)
		{
			float f = max(d,0.0) /margin;
			colorMod.rgb = vec3(f,f,f);
		}

		uv -= 0.5;
		uv *= u_pushConstants.zoom;
		uv += 0.5;

		uv = (uv *u_pushConstants.uvFactor) +u_pushConstants.uvOffset;
	}

	vec4 col = texture(u_texture,uv);
	fs_color.rgb = col.rgb;
	fs_color *= colorMod;
	fs_color.a = 1;
}
