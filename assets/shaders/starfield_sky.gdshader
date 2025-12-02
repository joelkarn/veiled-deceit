shader_type sky;

// Constellation highlight parameters (updated from script)
uniform int num_constellations = 0;
uniform vec3 constellation_centers[10]; // Max 10 constellations
uniform float constellation_radii[10];
uniform float constellation_glow[10]; // 0.0 = off, 1.0 = full glow

// Star generation parameters
uniform float star_density = 100.0; // Number of stars (reduced from 500 for performance)
uniform float star_size = 0.005; // Size of stars (slightly larger to compensate)
uniform float star_brightness = 1.2; // Brighter to compensate for fewer stars
uniform float twinkle_speed = 0.5;

// Background gradient
uniform vec3 sky_color_top = vec3(0.02, 0.02, 0.08);
uniform vec3 sky_color_horizon = vec3(0.1, 0.05, 0.15);

// Random function
float hash(vec3 p) {
    p = fract(p * vec3(443.897, 441.423, 437.195));
    p += dot(p, p.yzx + 19.19);
    return fract((p.x + p.y) * p.z);
}

// Star field generation
float stars(vec3 dir, float seed) {
    vec3 p = dir * 100.0;
    float star_field = 0.0;
    
    // Generate multiple layers of stars
    for (float i = 0.0; i < star_density; i += 1.0) {
        vec3 star_pos = vec3(
            hash(vec3(i * 12.34, seed, i * 56.78)),
            hash(vec3(i * 78.90, seed, i * 23.45)),
            hash(vec3(i * 34.56, seed, i * 89.01))
        ) * 2.0 - 1.0;
        
        star_pos = normalize(star_pos);
        float dist = distance(dir, star_pos);
        
        // Twinkle effect
        float twinkle = sin(TIME * twinkle_speed + i) * 0.5 + 0.5;
        float brightness = hash(vec3(i * 23.45, seed, i * 67.89)) * star_brightness;
        
        if (dist < star_size) {
            star_field += (1.0 - dist / star_size) * brightness * (0.5 + twinkle * 0.5);
        }
    }
    
    return clamp(star_field, 0.0, 1.0);
}

// Check if direction is near any constellation
vec3 get_constellation_glow(vec3 dir) {
    vec3 glow = vec3(0.0);
    
    for (int i = 0; i < num_constellations; i++) {
        vec3 center = normalize(constellation_centers[i]);
        float dist = distance(dir, center);
        float radius = constellation_radii[i];
        
        if (dist < radius * 2.0 && constellation_glow[i] > 0.0) {  // Expand glow area 2x
            // Create a smooth glow falloff with gentle curve for wide spread
            float falloff = 1.0 - (dist / (radius * 2.0));
            falloff = pow(falloff, 0.8);  // Very gentle falloff for wider glow
            
            // Intense golden glow color for highlighted constellations
            vec3 glow_color = vec3(5.0, 4.0, 2.0);  // Very bright golden color
            float glow_intensity = constellation_glow[i] * 10.0;  // 10x stronger base glow
            
            // Add extra glow for center area
            if (dist < radius) {
                glow_intensity *= 2.0;  // Double intensity in core area
            }
            
            glow += glow_color * falloff * glow_intensity;
        }
    }
    
    return glow;
}

void sky() {
    vec3 dir = EYEDIR;
    
    // Background gradient based on vertical angle
    float horizon_blend = smoothstep(-0.2, 0.3, dir.y);
    vec3 bg_color = mix(sky_color_horizon, sky_color_top, horizon_blend);
    
    // Generate stars
    float star_field = stars(dir, 123.456);
    vec3 star_color = vec3(star_field);
    
    // Combine background and stars
    COLOR = bg_color + star_color;
}
