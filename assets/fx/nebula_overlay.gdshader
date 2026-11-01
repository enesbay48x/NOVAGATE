shader_type canvas_item;

uniform vec4 nebula_color_a : source_color = vec4(0.32, 0.20, 0.48, 1.0);
uniform vec4 nebula_color_b : source_color = vec4(0.12, 0.10, 0.30, 1.0);
uniform float nebula_strength = 0.16;

float hash_value(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise_value(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash_value(i);
	float b = hash_value(i + vec2(1.0, 0.0));
	float c = hash_value(i + vec2(0.0, 1.0));
	float d = hash_value(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += noise_value(p) * amplitude;
		p = p * 2.03 + vec2(7.1, 3.7);
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	vec2 p = UV * vec2(3.2, 2.2) + vec2(TIME * 0.008, -TIME * 0.006);
	float cloud_noise = fbm(p);
	float detail = fbm(p * 1.7 + vec2(4.2, 8.1));
	float cloud = smoothstep(0.39, 0.69, cloud_noise * 0.72 + detail * 0.28);
	float edge_fade = smoothstep(0.0, 0.16, UV.y) * smoothstep(0.0, 0.16, 1.0 - UV.y);
	vec3 nebula_color = mix(nebula_color_a.rgb, nebula_color_b.rgb, smoothstep(0.28, 0.78, cloud_noise));
	COLOR = vec4(nebula_color, cloud * nebula_strength * edge_fade);
}
