shader_type spatial;

//#define SHOW_ITERATIONS

uniform mat4 inverse_model_matrix;
//uniform mat4 model_matrix;

const int max_raymarching_iterations = 200;
const float max_raymarching_distance = 10.0;
const float raymarching_surface_treshold = 0.00001;
const float raymarching_normal_epsilon = 0.00001;

const int max_intersector_iterations = 10; // delete if intersector get's scrapped
const float intersector_derivative_epsilon = 0.000001;

const vec3 arbitrary_vector_for_tangents = vec3(0.0, 1.0, 0.0); // delete if tangents unnecessary

varying vec3 fragment_position_world; //For the light shader

//function that blends two objects together by only using the sdfs
float smoothBlend(float d1, float d2, float k) {
    float h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    return mix(d2, d1, h) - k * h * (1.0 - h);
}

float hash(vec3 p) {
    return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453123);
}

float gradientNoise(vec3 p, float scale) {
    vec3 i = floor(p * scale);
    vec3 f = fract(p * scale);

    float a = hash(i);
    float b = hash(i + vec3(1.0, 0.0, 0.0));
    float c = hash(i + vec3(0.0, 1.0, 0.0));
    float d = hash(i + vec3(1.0, 1.0, 0.0));

    vec2 u = f.xy * f.xy * (3.0 - 2.0 * f.xy); // Smooth interpolation

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

//uses a clever trick from the internet where we change our base to elliptic space
//so that ellipsoid is a sphere we calculate the distance and convert it back to our space
vec2 sdEllipsoid(vec3 p, vec3 dimensions, vec3 center, float objID) {
    vec3 q = p - center;
    float k0 = length(q / dimensions);
    float k1 = length(q / (dimensions * dimensions));
    return vec2 ( k0 * (k0 - 1.0) / k1, objID);
}

//bascially playing around with multiple ellipsoid to create a mushroom cap
vec2 sdCap(vec3 p, vec3 center, vec3 dimensions, float thickness, float cutHeight, float hatID, float fluffID) {
    // Translate point to ellipsoid center
    vec3 q = p - center;
    // Transform to ellipsoid space
    q /= dimensions;
    // Outer ellipsoid
    float outer = length(q) - 1.0;
    // Inner ellipsoid (smaller version)
	float inner = length(q) - (1.0 - 0.1 * thickness);
	float inner2 = length(q) - (1.0 - thickness);
    // Hollow shape
    float hollow = max(outer, -inner);
    // Plane cut (cutting off the bottom at height `cutHeight`)
    float plane = q.y - cutHeight ;
	//object recognition
	float objID = 0.0;
	if(hollow < max(inner2, -plane - thickness - 1.0 )){
		objID = hatID;
	} else objID = fluffID;

    //two version of following code 1st one no noise second one with noise
    //v1
	//float d1 = max(hollow + thickness, -plane) * min(min(dimensions.x, dimensions.y) , dimensions.z );
	//float d2 = max(inner2, -plane + 1.7 * thickness) * min(min(dimensions.x, dimensions.y), dimensions.z );
	//v2
	float d1 = max(hollow + thickness * gradientNoise(p, 470) * 0.1, -plane) * min(min(dimensions.x, dimensions.y) , dimensions.z );
	float d2 = max(inner2, -plane + 1.7 * thickness + thickness * gradientNoise(p, 100.0) * 0.5 ) * min(min(dimensions.x, dimensions.y), dimensions.z );
	float d = smoothBlend(d1, d2, 0.04);
	return vec2(d, objID);
}

//another base object sdf based on other persons code to create a rounded cylinder like object between two points
float sdCapsule( vec3 p, vec3 a, vec3 b, float r )
{
  vec3 pa = p - a, ba = b - a;
  float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
  return length( pa - ba*h ) - r;
}

vec2 sdStem(vec3 p, vec3 a, vec3 b, vec3 c,vec3 dim, float r1, float r2, float b1, float b2, float objId){
	float d1 = sdCapsule(p, a, b, r1);
	float d2 = sdEllipsoid(p, dim, a, objId).x;
	float d = smoothBlend(d1, d2, b1);
	d1 = sdCapsule(p,b,c,r2);
	d = smoothBlend(d,d1, b2);
	//two version noiseless and with noise
	//return vec2(d, objId);
	return vec2(gradientNoise(p , 40.0) * 0.005 + d, objId);
}

//arguments: x_ratios is x_height to w1,w2, cap_properties is (thickness, cutHeight), IDs is (leg,cap top, cap fluff)
//cut height might not seem intuitive the closer to -1 the rounder the closer to 1 the flatter, not necessarily sane close to -1 / 1
vec2 sdGzib(vec3 p, vec3 cap_pos ,float cap_height, vec2 cap_ratios, vec2 cap_properties,vec3 leg_pos, vec3 leg_mid, vec3 leg_elip, vec4 r_leg,  vec3 leg_cap_offset, vec3 IDs) {
//shroom parameters
vec3 cap_dimensions = vec3(cap_height * cap_ratios.x, cap_height, cap_height * cap_ratios.y);
cap_pos.y -= cap_properties.y * cap_height;

vec2 d1 = sdStem(p, leg_pos, leg_mid, cap_pos + leg_cap_offset, leg_elip,r_leg.x, r_leg.y, r_leg.z, r_leg.w, IDs.x);
vec2 d2 = sdCap(p, cap_pos, cap_dimensions, cap_properties.x, cap_properties.y, IDs.y, IDs.z);
float d = smoothBlend(d1.x,d2.x,0.03);
if(d1.x + 0.01 < d2.x) return vec2(d, d1.y);
else return vec2(d, d2.y);
}




vec2 sdf(vec3 input_point){
	//Transfer to solid coordinates
	//input_point = (inverse_model_matrix * vec4(input_point, 1.0)).xyz;

	return sdGzib(input_point, vec3(0.19,0.4,0), 0.2, vec2(1.77,1.63), vec2(0.02,-0.3),vec3(0.11,0,0), vec3(0.24,0.22,0.0) ,vec3(0.16,0.09,0.14),vec4(0.1, 0.1, 0.1, 0.1), vec3(0.05,0,0),vec3(1.0, 2.0, 3.0));

}


vec3 normal_to_sdf(vec3 input_point) {
	float sdf_at_input = sdf(input_point).x;
	return normalize(vec3(
		sdf(input_point + vec3(raymarching_normal_epsilon, 0.0, 0.0)).x - sdf_at_input,
		sdf(input_point + vec3(0.0, raymarching_normal_epsilon, 0.0)).x - sdf_at_input,
		sdf(input_point + vec3(0.0, 0.0, raymarching_normal_epsilon)).x - sdf_at_input
	) / raymarching_normal_epsilon);
}

vec2 ray_marching(vec3 source, vec3 direction) {
	vec3 analyzed_point = source;
	direction = normalize(direction);

	int iteration = 0;
	vec2 sdf_res = sdf(analyzed_point);
	float free_radius = sdf_res.x;
	float objID = sdf_res.y;
	while (
	iteration < max_raymarching_iterations &&
	free_radius > raymarching_surface_treshold &&
	distance(analyzed_point, source) < max_raymarching_distance) {
		analyzed_point += direction * (free_radius + raymarching_surface_treshold);
		iteration++;

		sdf_res = sdf(analyzed_point);
		free_radius = sdf_res.x;
		objID = sdf_res.y;
	}

	#ifndef SHOW_ITERATIONS
		return vec2(abs(distance(analyzed_point, source)), objID);
	#else
		return float(iteration) / float(max_raymarching_iterations);
	#endif
}

// simplified ray marching that only checks if a ray intersects the sdf or not
// using something akin to the Newton's method
bool ray_intersects_sdf(vec3 source, vec3 direction) {
	if (dot(normal_to_sdf(source), direction) < 0.0)
		return false;
}

void fragment() {
	// We do not have access to the direction from the camera to the drawn fragment in so
	// we calculate it using the fragment's position in the view space
	vec3 cast_direction = normalize((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD);
	vec2 a = ray_marching(CAMERA_POSITION_WORLD, cast_direction);
	float distance = a.x;
	float objectID = a.y ;

	#ifndef SHOW_ITERATIONS
		if (distance > max_raymarching_distance)
			discard;

		fragment_position_world = CAMERA_POSITION_WORLD + distance * cast_direction;

		LIGHT_VERTEX = (VIEW_MATRIX * vec4(fragment_position_world, 1.0)).xyz;
		NORMAL = (VIEW_MATRIX * vec4(normal_to_sdf(fragment_position_world), 0.0)).xyz;
		//EMISSION = vec3(0.1);
		//very wonky color but trying to use a switch here was problematic
		ALBEDO = vec3(0, 0, 0);
		if(objectID == 1.0) ALBEDO = vec3(0.25, 0.22, 0.2);
		if(objectID == 2.0) ALBEDO = vec3(0.7, 0.3, 0.55);
		if(objectID == 3.0) ALBEDO = vec3(0.31, 0.4, 0.25);

		vec3 fr = mod(fragment_position_world - vec3(1.0), 2.0) + vec3(1.0);
		//following line does rainbow
		//ALBEDO = vec3(0.3, 0.3, 0.3) + cross(vec3(0.7, 0.3, 0.6), sin(10.0 * fr + fr + 10.0 * sin(TIME)));
		//following lien color represents space
		//ALBEDO = mod(fragment_position_world, 0.3);
	#else
		ALBEDO = vec3(1.0, 0.0, 0.0) * distance + vec3(0.0, 0.0, 1.0) * (1.0 - distance);
	#endif
}

void light() {
	// Called for every pixel for every light affecting the material.
	//DIFFUSE_LIGHT = (INV_PROJECTION_MATRIX * FRAGCOORD).xyz;
	//DIFFUSE_LIGHT = (INV_VIEW_MATRIX * (vec4(LIGHT, 0.0))).xyz;
	vec3 light_direction = (INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz;
	vec2 a = ray_marching(fragment_position_world + light_direction * 0.1, light_direction);
	float distance = a.x;
	if (distance < 0.0 || distance > max_raymarching_distance)
    	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI;

}