// Copyright © 2021 Audulus LLC. All rights reserved.

#ifndef sdf_h
#define sdf_h

// From https://www.iquilezles.org/www/articles/distfunctions2d/distfunctions2d.htm

float sdCircle( float2 p, float r )
{
    return length(p) - r;
}

float sdBox( float2 p, float2 b, float r )
{
    float2 d = abs(p)-b+r;
    return length(max(d,float2(0.0))) + min(max(d.x,d.y),0.0)-r;
}

float sdSegment(float2 p, float2 a, float2 b )
{
    float2 pa = p-a, ba = b-a;
    float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
    return length( pa - ba*h );
}

float sdArc(float2 p, float2 sca, float2 scb, float ra, float rb )
{
    p *= float2x2{float2{sca.x,sca.y},float2{-sca.y,sca.x}};
    p.x = abs(p.x);
    float k = (scb.y*p.x>scb.x*p.y) ? dot(p,scb) : length(p);
    return sqrt( dot(p,p) + ra*ra - 2.0*ra*k ) - rb;
}

float dot2(float2 v) {
    return dot(v,v);
}

float sdBezier(float2 pos, float2 A, float2 B, float2 C )
{
    float2 a = B - A;
    float2 b = A - 2.0*B + C;
    float2 c = a * 2.0;
    float2 d = A - pos;
    float kk = 1.0/dot(b,b);
    float kx = kk * dot(a,b);
    float ky = kk * (2.0*dot(a,a)+dot(d,b)) / 3.0;
    float kz = kk * dot(d,a);
    float res = 0.0;
    float p = ky - kx*kx;
    float p3 = p*p*p;
    float q = kx*(2.0*kx*kx-3.0*ky) + kz;
    float h = q*q + 4.0*p3;
    if( h >= 0.0)
    {
        h = sqrt(h);
        float2 x = (float2{h,-h}-q)/2.0;
        float2 uv = sign(x)*pow(abs(x), float2(1.0/3.0));
        float t = clamp( uv.x+uv.y-kx, 0.0, 1.0 );
        res = dot2(d + (c + b*t)*t);
    }
    else
    {
        float z = sqrt(-p);
        float v = acos( q/(p*z*2.0) ) / 3.0;
        float m = cos(v);
        float n = sin(v)*1.732050808;
        float3  t = clamp(float3{m+m,-n-m,n-m}*z-kx,0.0,1.0);
        res = min( dot2(d+(c+b*t.x)*t.x),
                   dot2(d+(c+b*t.y)*t.y) );
        // the third root cannot be the closest
        // res = min(res,dot2(d+(c+b*t.z)*t.z));
    }
    return sqrt( res );
}

float det(float2 a, float2 b) { return a.x*b.y-b.x*a.y; }

float2 closestPointInSegment( float2 a, float2 b )
{
    float2 ba = b - a;
    return a + ba*clamp( -dot(a,ba)/dot(ba,ba), 0.0, 1.0 );
}

// From: http://research.microsoft.com/en-us/um/people/hoppe/ravg.pdf
float2 get_distance_vector(float2 b0, float2 b1, float2 b2) {
    
    float a=det(b0,b2), b=2.0*det(b1,b0), d=2.0*det(b2,b1);
    
    if( abs(2.0*a+b+d) < 0.001 ) return closestPointInSegment(b0,b2);
    
    float f=b*d-a*a; // ð‘“(ð‘)
    float2 d21=b2-b1, d10=b1-b0, d20=b2-b0;
    float2 gf=2.0*(b*d21+d*d10+a*d20);
    gf=float2{gf.y,-gf.x};
    float2 pp=-f*gf/dot(gf,gf);
    float2 d0p=b0-pp;
    float ap=det(d0p,d20), bp=2.0*det(d10,d0p);
    // (note that 2*ap+bp+dp=2*a+b+d=4*area(b0,b1,b2))
    float t=clamp((ap+bp)/(2.0*a+b+d), 0.0 ,1.0);
    return mix(mix(b0,b1,t),mix(b1,b2,t),t);
    
}

float sdBezierApprox(float2 p, float2 b0, float2 b1, float2 b2) {
    return length(get_distance_vector(b0-p, b1-p, b2-p));
}

#if 0
template<class T>
float sdPolygon(float2 p, T v, int num)
{
    float d = dot(p-v[0],p-v[0]);
    float s = 1.0;
    for( int i=0, j=num-1; i<num; j=i, i++ )
    {
        // distance
        float2 e = v[j] - v[i];
        float2 w =    p - v[i];
        float2 b = w - e*clamp( dot(w,e)/dot(e,e), 0.0, 1.0 );
        d = min( d, dot(b,b) );

        // winding number from http://geomalgorithms.com/a03-_inclusion.html
        bool3 cond = bool3( p.y>=v[i].y,
                            p.y <v[j].y,
                            e.x*w.y>e.y*w.x );
        if( all(cond) || all(not(cond)) ) s=-s;
    }

    return s*sqrt(d);
}
#endif

#if __METAL_VERSION__
float sdPrim(const device vgerPrim& prim, float2 p) {
#else
float sdPrim(const vgerPrim& prim, float2 p) {
#endif
    float d = FLT_MAX;
    switch(prim.type) {
        case vgerBezier:
            // d = sdBezier(p, prim.cvs[0], prim.cvs[1], prim.cvs[2]);
            d = sdBezierApprox(p, prim.cvs[0], prim.cvs[1], prim.cvs[2]);
            break;
        case vgerCircle:
            d = sdCircle(p - prim.cvs[0], prim.radius);
            break;
        case vgerArc:
            d = sdArc(p - prim.cvs[0], prim.cvs[1], prim.cvs[2], prim.radius, 0.002);
            break;
        case vgerRect: {
            auto center = .5*(prim.cvs[1] + prim.cvs[0]);
            auto size = prim.cvs[1] - prim.cvs[0];
            d = sdBox(p - center, .5*size, prim.radius);
        }
            break;
        case vgerSegment:
            d = sdSegment(p, prim.cvs[0], prim.cvs[1]);
            break;
        case vgerCurve:
            for(int i=0;i<prim.count-2;i+=2) {
                d = min(d, sdBezierApprox(p,
                                          prim.cvs[i],
                                          prim.cvs[i+1],
                                          prim.cvs[i+2]));
            }
            break;
    }
    return d;
}

#endif /* sdf_h */
