#version 440

#extension GL_ARB_separate_shader_objects : enable
#extension GL_ARB_shading_language_420pack : enable

#include "equirectangular.glsl"

layout(location = 0) in vec2 in_vert_pos;
layout(location = 1) in vec2 in_vert_uv;

layout(location = 0) out vec2 vs_vert_uv;
layout(location = 1) out vec3 vs_vert_world_dir;

void main()
{
	gl_Position = vec4(in_vert_pos,0.0,1.0);
	vs_vert_uv = in_vert_uv;
	vs_vert_world_dir = (u_pushConstants.invViewProjection *vec4(in_vert_uv.x *2.0 -1.0,in_vert_uv.y *2.0 -1.0,0,1)).xyz;
}
