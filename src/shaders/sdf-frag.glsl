#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

//Constants:
#define EPSILON 1e-2
#define MAX_RAY_STEPS 128
#define MAX_DISTANCE 50.0

//Toolbox functions:

float easeInOutCubic(float x) {
    if (x < 0.5) {
        return 4.0 * x * x * x;
    } else {
        1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0;
    }
}

float bias(float t, float b) {
    return (t / ((((1.0/b) - 2.0)*(1.0 - t))+1.0));
}

float easeInQuad(float x) {
    return x * x;
}
//Structs:

struct Intersection 
{
    vec3 position;
    float t;
    int material_id;
};

struct Geom
{
    float distance;
    int material_id;
};

//Material List:

//0: 
//1: 
//...

////IQ Voronoise from ShaderToy:

vec3 hash3( vec2 p )
{
    vec3 q = vec3( dot(p,vec2(127.1,311.7)), 
				   dot(p,vec2(269.5,183.3)), 
				   dot(p,vec2(419.2,371.9)) );
	return fract(sin(q)*43758.5453);
}

float voronoise( in vec2 p, float u, float v )
{
	float k = 1.0+63.0*pow(1.0-v,6.0);

    vec2 i = floor(p);
    vec2 f = fract(p);
    
	vec2 a = vec2(0.0,0.0);
    for( int y=-2; y<=2; y++ )
    for( int x=-2; x<=2; x++ )
    {
        vec2  g = vec2( x, y );
		vec3  o = hash3( i + g )*vec3(u,u,1.0);
		vec2  d = g - f + o.xy;
		float w = pow( 1.0-smoothstep(0.0,1.414,length(d)), k );
		a += vec2(o.z*w,w);
    }
    return a.x/a.y;
}

float voroFBM(vec2 p, vec2 time, int N_OCTAVES) {

    float total = 0.f;
    float frequency = 1.f;
    float amplitude = 1.f;
    float persistence = 0.5f;
    float maxValue = 0.f;  // Used for normalizing result to 0.0 - 1.0

    for(int i = 0; i < N_OCTAVES; i++) {
        total += voronoise(frequency * (p+time), 1.0, 1.0) * amplitude;
        maxValue += amplitude;
        amplitude *= persistence;
        frequency *= 2.f;
    }
    return total/maxValue;
}
////

//SDF Functions:

Geom union_Geom(Geom g1, Geom g2) {
    Geom g;
    if (g1.distance < g2.distance) {
        return g1;
    } else {
        return g2;
    }
}

Geom subtract_Geom(Geom g1, Geom g2) {
    Geom g;
    if (-g1.distance > g2.distance) {
        return g1;
    } else {
        return g2;
    }
}

float smoothUnion( float d1, float d2, float k ) {
    float h = clamp( 0.5 + 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) - k*h*(1.0-h); 
}

Geom sdBox_Geom( vec3 p, vec3 b, vec3 pos, int id)
{
    Geom g;
    p -= pos;
    vec3 q = abs(p) - b;
    g.distance = length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
    g.material_id = id;
    return g;
}

Geom sdRoundBox_Geom( vec3 p, vec3 b, vec3 pos, float r, int id)
{
    Geom g;
    p -= pos;
    vec3 q = abs(p) - b;
    g.distance = length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - r;
    g.material_id = id;
    return g;
}

Geom sphereSDF_Geom(vec3 query_position, vec3 position, float radius, int id)
{
    Geom g;
    g.distance = length(query_position - position) - radius;
    g.material_id = id;
    return g;
}

Geom planeSDF_Geom(vec3 queryPos, float height, int id)
{
    Geom g;
    g.distance = queryPos.y - height;
    g.material_id = id;
    return g;
}

Geom xz_planeSDF_Geom(vec3 queryPos, float pos, int id)
{
    Geom g;
    g.distance = queryPos.z - pos;
    g.material_id = id;
    return g;
}

Geom pole_Geom( vec3 p, vec3 b, vec3 pos, float h, int id)
{
    vec3 poleScale = b * vec3(0.08, 1.0, 0.08);
    p.y -= h;
    Geom g = sdBox_Geom(p, poleScale, pos, id);
    return g;
}

float midMountainNoise(vec3 queryPos) {
    // float n = 7.f * voronoise(0.25 * queryPos.xz + vec2(0.02 * u_Time), 1.0, 1.0);
    float n = 9.f * voroFBM(0.2 * queryPos.xz, vec2(0.12 * u_Time, 0.0), 5);
    float w1 = bias(1.f - smoothstep(0.0, 1.0, 13.f * (abs((queryPos.z - 100.f)) / 100.f)), 0.7f);


    return w1 * n;
}

float bigMountainNoise(vec3 queryPos) {

    float n = 50.f * voroFBM(0.03 * queryPos.xz + vec2(-1000.0), vec2(0.004 * u_Time, 0.0) , 7);

    float w1 = 1.f - smoothstep(0.0, 1.0, (abs((queryPos.z - 40.f)) / 40.f));
    w1 = easeInQuad(w1);

    return w1 * n;
}

vec3 opRep( vec3 p, vec3 c ) {
    vec3 q = mod(p+0.5*c,c)-0.5*c;
    return q;
}

Geom sceneSDF_Geom(vec3 queryPos) {

    Geom plane = planeSDF_Geom(queryPos, midMountainNoise(queryPos) + bigMountainNoise(queryPos), 0);
    Geom train = sdBox_Geom(queryPos, vec3(10.0f, 0.5f, 0.5f), vec3(u_Ref.x, u_Ref.y - 0.75f, u_Ref.z + 110.f), 1);
    Geom tracks = sdBox_Geom(queryPos, vec3(50.0f, 0.1f, 0.5f), vec3(u_Ref.x, u_Ref.y - 0.95f, u_Ref.z + 110.f), 2);
    
    Geom pole = pole_Geom(opRep(queryPos, vec3(15.f, 0.f, 0.f)), vec3(0.4f, 0.6f, 0.4f), opRep(-vec3(12.f * u_Time, 0, 0) + vec3(u_Ref.x + 15.f, u_Ref.y - 1.0f, u_Ref.z + 110.25f), vec3(15., 0., 0.)), 1.f, 10);

    return union_Geom(pole, union_Geom(union_Geom(plane, train), tracks));
}

float sceneSDF(vec3 queryPos) {
    return sceneSDF_Geom(queryPos).distance;
}

//Helper Functions:
vec3 getRay(vec2 uv) {
    float len = tan(3.14159 * 0.125) * distance(u_Eye, u_Ref);
    vec3 H = normalize(cross(vec3(0.0, 1.0, 0.0), u_Ref - u_Eye));
    vec3 V = normalize(cross(H, u_Eye - u_Ref));
    V *= len;
    H *= len * u_Dimensions.x / u_Dimensions.y;
    vec3 p = u_Ref + uv.x * H + uv.y * V;
    vec3 dir = normalize(p - u_Eye);
    return dir;
}

vec3 estimateNormal(vec3 p) {
  return normalize(vec3(
    sceneSDF(vec3(p.x + EPSILON, p.y, p.z)) - sceneSDF(vec3(p.x - EPSILON, p.y, p.z)),
    sceneSDF(vec3(p.x, p.y + EPSILON, p.z)) - sceneSDF(vec3(p.x, p.y - EPSILON, p.z)),
    sceneSDF(vec3(p.x, p.y, p.z + EPSILON)) - sceneSDF(vec3(p.x, p.y, p.z - EPSILON))
  ));
}

//Ray Marching
Intersection rayMarch(vec2 uv)
{
    Intersection intersection;
    intersection.t = 0.001;

    vec3 dir = getRay(uv);
    vec3 queryPos = u_Eye;

    for (int i=0; i < MAX_RAY_STEPS && intersection.t < MAX_DISTANCE; ++i)
    {
        Geom g = sceneSDF_Geom(queryPos);
        float dist = g.distance;
        
        if (dist < EPSILON)
        {
            intersection.position = queryPos;
            intersection.t = length(queryPos - u_Eye);
            intersection.material_id = g.material_id;
            return intersection;
        }
        queryPos += dir * dist;
    }
    
    intersection.t = -1.0;
    return intersection;
}

//Coloring:
vec3 getSceneColor(vec2 uv) {
    //1. Ray March to get scene intersection / or lack there of
    Intersection isect = rayMarch(uv);
    //2. Choose color based on distance value (but also, in future, we can categorize by material too...)
    vec3 color;
    if (isect.t > 0.0) {
        // if (isect.material_id == 0) {
        //     color = vec3(1.);
        // } else if (isect.material_id == 1) {
        //     color = vec3(0.2);
        // } else if (isect.material_id == 2) {
        //     color = vec3(0.4);
        // } else if (isect.material_id == 3) {
        //     color = vec3(0.5);
        // } else if (isect.material_id == 4) {
            // color = vec3(0.1);
        // }else {
            if (isect.material_id == 10) {
                color = vec3(0.);
            } else {
                vec3 N = estimateNormal(isect.position);
                color = N;
            }
            
        // }
    } else {
        color = vec3(0.67, 0.81, 0.88);
    }

    vec3 backgroundColor = vec3(0.67, 0.81, 0.88) * 1.f;
    float fogT = smoothstep(10.0, 220.0, distance(isect.position, u_Eye));
    color = mix(color.rgb, backgroundColor, fogT);
    color = pow(color.rgb, vec3(1.0, 1.2, 1.5));
    return color;
}

void main() {
    vec2 uv = fs_Pos;
    //uv is in NDC space!

    vec3 color = getSceneColor(uv);
    out_Col = vec4(color, 1.f);
}
