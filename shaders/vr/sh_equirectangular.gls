/*
    Copyright (C) 2019  Silverlan

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at http://mozilla.org/MPL/2.0/.
*/

#ifndef F_SH_EQUIRECTANGULAR_GLS
#define F_SH_EQUIRECTANGULAR_GLS

#define SHADER_FLAG_NONE 0
#define SHADER_FLAG_2D_BIT 1
#define SHADER_FLAG_ENABLE_MARGIN 2

layout(LAYOUT_PUSH_CONSTANTS()) uniform PushConstants {
	mat4 invViewProjection; // view-projection matrix without translation
	vec2 uvFactor;
	vec2 uvOffset;
	float horizontalFactor;
	float zoom;
	uint shaderFlags;
} u_pushConstants;

#endif
