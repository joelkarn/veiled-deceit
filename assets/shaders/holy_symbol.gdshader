shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_always, depth_prepass_alpha;

uniform sampler2D symbol_texture : source_color;
uniform vec3 glow_color : source_color = vec3(1.0, 0.95, 0.7);
uniform float emission_strength : hint_range(0.0, 10.0) = 0.0;

void fragment() {
	// Get texture size to preserve aspect ratio
	vec2 tex_size = vec2(textureSize(symbol_texture, 0));
	float aspect_ratio = tex_size.x / tex_size.y;
	
	// Adjust UV to maintain aspect ratio (center and scale)
	vec2 adjusted_uv = UV;
	if (aspect_ratio > 1.0) {
		// Wider than tall
		adjusted_uv.y = (UV.y - 0.5) * aspect_ratio + 0.5;
	} else if (aspect_ratio < 1.0) {
		// Taller than wide
		adjusted_uv.x = (UV.x - 0.5) / aspect_ratio + 0.5;
	}
	
	// Sample the texture with adjusted UVs, discard if outside 0-1 range
	if (adjusted_uv.x < 0.0 || adjusted_uv.x > 1.0 || adjusted_uv.y < 0.0 || adjusted_uv.y > 1.0) {
		discard;
	}
	
	vec4 tex = texture(symbol_texture, adjusted_uv);
	
	// Invert the RGB channels (black becomes white)
	vec3 inverted = vec3(1.0) - tex.rgb;
	
	// Use the original alpha
	float alpha = tex.a;
	
	// Make the inverted color glow with the glow_color
	vec3 final_color = inverted * glow_color;
	
	// Set albedo and emission
	ALBEDO = final_color;
	EMISSION = final_color * emission_strength;
	ALPHA = alpha * clamp(emission_strength * 0.3, 0.0, 1.0);
}
