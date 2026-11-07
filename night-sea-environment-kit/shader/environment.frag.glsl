// Night Sea environment: one full-screen fragment shader (WebGL 1 / GLSL ES 1.0).
// Draws, per pixel: sky gradient + Milky Way texture + the 2D star layer (tStar) + three rings of island silhouettes,
// and below the horizon a procedural sea that mirrors all of that with small moving waves and a moon glitter road.
//
// Coordinates: every direction is a unit vector [east, north, up] in the observer's horizon frame (z = up, z = 0 is the horizon).
// Camera: uF = forward, uR = right, uU = up (all unit, same frame); uFoc = focal length in CSS px; (uCx, uCy) = optical centre in CSS px.
// uRes = drawing-buffer size in device px, uDpr = device pixel ratio.
// tStar: the 2D canvas with stars/planets/Moon, uploaded every frame (premultiplied alpha, flipped Y).
// tMW: equirectangular Milky Way map in RA/Dec (u = RA/360, v = (90 - Dec)/180). uE0..uE2 = horizon vectors of the equatorial X, Y, Z axes.
// uSun / uMoon: Sun and Moon directions. In this build the Sun is pinned below the horizon ([0,0,-1]) so it is always night.
// Sky palette: uZen (zenith), uMid, uHor (horizon), all linear-ish RGB 0..1. uWave = wave strength (0.06 calm .. 0.3 choppy). uT = time in s.
// uIsl = 1 islands on / 0 off. uMW = Milky Way strength. uMoonUp, uIllum, uMoonI = Moon above horizon, phase, glitter strength.
// Unused at night (kept so a dusk/day mode can be added): uGlow, uTw, uBelt, uLP, uDay, uSunI, uSunCol, uLow.

precision highp float;
uniform vec2 uRes;uniform float uDpr,uFoc,uCx,uCy;uniform vec3 uF,uR,uU;
uniform sampler2D tStar;
uniform vec3 uZen,uMid,uHor,uSun,uMoon,uGlow,uSunCol;
uniform sampler2D tMW;uniform vec3 uE0,uE1,uE2;uniform float uMW;
uniform float uIllum,uMoonUp,uTw,uBelt,uLP,uNight,uDay,uT,uWave,uSunI,uMoonI,uIsl,uLow;
const float PI=3.14159265;
vec3 mwCol(vec3 d){vec3 e=vec3(dot(uE0,d),dot(uE1,d),dot(uE2,d));float ra=atan(e.y,e.x);
  vec3 m=texture2D(tMW,vec2(fract(ra/(2.*PI)+1.),acos(clamp(e.z,-1.,1.))/PI)).rgb;return m*m*1.15;}   // texture is gamma-encoded
vec3 skyCol(vec3 d){float h=max(d.z,0.);
  vec3 c=mix(uZen,uMid,smoothstep(0.,.9,pow(1.-h,2.6)));c=mix(c,uHor,pow(1.-h,8.));
  vec2 hs=normalize(uSun.xy+1e-5),hd=normalize(d.xy+1e-5);float ca=dot(hs,hd);
  // low sun: tint the sky toward the sun with a warm gradient (gold at the horizon, salmon above) instead of adding light, so the disc stays readable
  vec3 warm=mix(vec3(1.,.64,.28),vec3(.92,.42,.34),smoothstep(0.,.12,h));
  c=mix(c,warm,uLow*pow(ca*.5+.5,3.)*exp(-h*7.)*.88);
  c+=uGlow*uTw*pow(ca*.5+.5,4.)*exp(-h*5.)*.9*(1.-.8*uLow);
  c+=vec3(.42,.24,.36)*uBelt*pow(max(-ca,0.),1.5)*smoothstep(.015,.09,h)*exp(-h*6.);
  float cs=dot(d,uSun),su=step(-.02,uSun.z);
  vec3 e1=normalize(vec3(uSun.y,-uSun.x,0.)+1e-5),e2=cross(e1,uSun);float sr=length(vec2(dot(d,e1),dot(d,e2)*mix(1.,1.25,uLow)))*step(0.,cs);
  c+=uSunCol*(pow(max(cs,0.),20.)*.25*uDay+exp(-sr*sr/.0011)*mix(.75,.5,uLow)+exp(-sr*sr/.00025)*.6*uLow+exp(-sr/.1)*.18*uLow)*su;
  c+=mix(vec3(1.,.98,.92),vec3(1.,.8,.5),uLow)*smoothstep(.0165,.0125,sr)*su*2.;
  float cm=dot(d,uMoon);c+=vec3(.7,.76,.95)*uIllum*uMoonUp*(pow(max(cm,0.),140.)*.25+pow(max(cm,0.),10.)*.05)*(1.-uDay*.85);
  c+=vec3(.5,.33,.2)*uLP*uNight*exp(-h*5.)*.5;
  c+=mwCol(d)*uMW*(.25+.75*smoothstep(0.,.35,h));
  c+=uHor*.16*exp(-h*70.);
  c=mix(c,vec3(.17,.10,.36),smoothstep(.3,.85,h)*.42);                       // violet toward the zenith
  c+=vec3(.025,.085,.055)*exp(-pow((h-.17)/.075,2.));                          // airglow: the real faint green band ~10 deg up
  float wv=pow(max(dot(normalize(d.xy+1e-5),vec2(-1.,0.)),0.),2.);             // west: last light of dusk
  c=mix(c,vec3(.86,.52,.42),exp(-h*45.)*(.22+.42*wv));
  c=mix(c,vec3(.95,.70,.52),exp(-h*140.)*(.15+.35*wv));
  c+=vec3(.10,.06,.18)*exp(-h*10.)*(1.-wv)*.5;                                // cool violet glow on the other side
  return c;}
float hsh(float n){return fract(sin(n*127.1+.73)*43758.5453);}
// one ring of islands around the horizon: n cells, each may hold one island (degrees)
float isl(float az,float n,float hm,float sd){float x=(az/(2.*PI)+.5)*n,c=floor(x),best=0.;
  for(int k=-1;k<=1;k++){float ci=c+float(k),cc=mod(ci,n),q=cc*3.17+sd;if(hsh(q)<.5)continue;
    float w=mix(.28,.9,hsh(q+3.1)),ctr=ci+.5+(hsh(q+5.7)-.5)*.5,hh=hm*mix(.3,1.,hsh(q+9.3)),sk=(hsh(q+11.)-.5)*.9;
    float u=(x-ctr)/w;if(abs(u)>=1.)continue;u=u+sk*(1.-u*u)*.5;
    float sh=pow(max(1.-u*u,0.),.85)*(1.+.07*sin(x*37.+cc*5.)+.04*sin(x*97.+cc)+.025*sin(x*211.));
    best=max(best,hh*sh);}
  return best;}
float islandH(float az){return max(max(isl(az,6.,8.5,19.),isl(az,11.,4.2,7.)),isl(az,19.,1.9,1.))*PI/180.;}
vec4 lay(float az,float alt,float pa,float n,float hm,float sd,vec3 base,float haze){
  float h=isl(az,n,hm,sd)*PI/180.;float cov=clamp((h-alt)/(pa*.9),0.,1.);if(cov<=0.)return vec4(0.);
  float e=.03,sl=(isl(az+e,n,hm,sd)-isl(az-e,n,hm,sd))*PI/180./(2.*e);
  float t=clamp(alt/max(h,1e-5),0.,1.),side=clamp(.5+sl*5.,0.,1.);
  vec3 c=base*mix(.6,1.5,side);
  c+=uHor*.07*t*(1.-haze);
  float rim=smoothstep(2.2*pa,0.,h-alt)*(.25+.5*side);c=mix(c,uHor*.6+base,rim*(1.-haze));
  c=mix(c,uHor*.85,haze*(1.-.35*t));
  return vec4(c,cov);}
vec4 island(vec3 d){if(uIsl<.5)return vec4(0.);
  float az=atan(d.x,d.y),alt=asin(clamp(d.z,-1.,1.)),pa=1./uFoc;if(alt<-.003||alt>.16)return vec4(0.);
  vec3 col=vec3(0.);float a=0.;vec4 L;
  L=lay(az,alt,pa,6.,8.5,19.,vec3(.022,.03,.06),.05);col+=L.rgb*L.a*(1.-a);a+=L.a*(1.-a);
  if(a<.999){L=lay(az,alt,pa,11.,4.2,7.,vec3(.05,.07,.13),.32);col+=L.rgb*L.a*(1.-a);a+=L.a*(1.-a);}
  if(a<.999){L=lay(az,alt,pa,19.,1.9,1.,vec3(.10,.14,.24),.62);col+=L.rgb*L.a*(1.-a);a+=L.a*(1.-a);}
  return vec4(col/max(a,1e-4),a);}
float h2(vec2 p){vec3 q=fract(vec3(p.xyx)*.1031);q+=dot(q,q.yzx+33.33);return fract((q.x+q.y)*q.z);}
float road(vec3 d,vec3 S,float sig){vec3 Hh=normalize(S-d);float c=max(Hh.z,.08),t2=(1.-c*c)/(c*c);return exp(-t2/(sig*sig))*step(-.02,S.z);}
float sparkle(vec3 d,float p){float e=-d.z,sz=(1.6+70.*e)/uFoc;vec2 q=vec2(atan(d.x,d.y)/sz,e/sz),ce=floor(q);
  float hc=h2(ce),tt=floor(uT*4.+hc*9.);float hv=h2(ce+tt*vec2(17.31,9.73));if(hv>=clamp(p*.9,0.,.85))return 0.;
  vec2 o=vec2(h2(ce+3.1),h2(ce+7.7))*.6+.2;float rp=length((fract(q)-o)*sz*uFoc);return smoothstep(1.7,.2,rp)*(.6+.4*h2(ce+tt));}
vec2 toScreen(vec3 d){float z=dot(d,uF);if(z<.05)return vec2(-1.);vec2 q=vec2(uCx+dot(d,uR)/z*uFoc,uCy-dot(d,uU)/z*uFoc);return vec2(q.x*uDpr/uRes.x,1.-q.y*uDpr/uRes.y);}
void main(){
  vec2 fc=gl_FragCoord.xy;vec2 px=vec2(fc.x,uRes.y-fc.y)/uDpr;
  vec3 d=normalize(uF+((px.x-uCx)/uFoc)*uR+((uCy-px.y)/uFoc)*uU);
  vec4 st=texture2D(tStar,fc/uRes);
  vec3 col;
  if(d.z>=0.){col=skyCol(d)*(1.-st.a)+st.rgb;vec4 il=island(d);col=mix(col,il.rgb,il.a);}
  else{
    float eh=1.5,dist=min(eh/-d.z,4000.);vec2 P=d.xy*dist;vec3 off=vec3(0.);vec2 gr=vec2(0.);
    vec4 ang=vec4(.3,-.8,1.9,2.7),L=vec4(9.,5.5,3.1,1.7),A=vec4(.22,.12,.07,.04);
    for(int i=0;i<4;i++){vec2 dir=vec2(cos(ang[i]),sin(ang[i]));float k=2.*PI/L[i],w=sqrt(9.81*k),ph=k*dot(dir,P)-w*uT;
      float f=1.-smoothstep(L[i]*6.,L[i]*45.,dist);off+=A[i]*f*vec3(dir*sin(ph),cos(ph));gr-=A[i]*f*k*sin(ph)*dir;}

    float pl=.5;vec3 sea=mix(vec3(.01,.018,.045),vec3(.035,.06,.12),smoothstep(-.5,-.01,d.z));
    vec2 gc=gr*uWave;vec3 N=normalize(vec3(-gc,1.));vec3 R=reflect(d,N);R.z=max(R.z,.003);R=normalize(R);
    float fr=.02+.98*pow(1.-max(-dot(d,N),0.),5.);
    vec3 refl=skyCol(R);vec3 R0=reflect(d,normalize(vec3(-gc*.3,1.)));R0.z=max(R0.z,.0005);vec4 il=island(normalize(R0));
    if(il.a<.5){vec2 uv=toScreen(R);if(uv.x>0.&&uv.x<1.&&uv.y>0.&&uv.y<1.){vec4 s=vec4(0.);float stp=2.*uDpr/uRes.y;
        for(int j=-2;j<=2;j++)s+=texture2D(tStar,uv+vec2(0.,float(j)*stp*.5))*.2;
        float fd=mix(.3,1.,smoothstep(-.55,-.02,d.z));refl=refl*(1.-s.a*.55*fd)+s.rgb*.55*fd;}}
    refl=mix(refl,il.rgb*.85,il.a*.85);
    float k=clamp(mix(.3,.8,uNight)+fr*.45,0.,1.);
    col=mix(sea,refl*vec3(.62,.70,.88),k*.85);
    float far=smoothstep(3.,500.,dist),sg=mix(.006,.075,far)*(.35+.65*max(uWave,.15));
    float sig=.06+.33*uWave,pS=road(d,uSun,sig),pM=road(d,uMoon,sig*.9),hz=mix(.1,.75,far);
    col+=uSunCol*uSunI*(pS*hz+sparkle(d,pS*.85)*1.7)+vec3(.85,.88,.95)*uMoonI*(pM*hz*.3+sparkle(d+.001,pM*.7)*.6);
    col=mix(col,skyCol(normalize(vec3(d.xy,.002))),smoothstep(250.,4000.,dist)*.6);
    {vec3 u=normalize(vec3(d.xy,.0015));vec4 iu=island(u);vec3 ab=mix(skyCol(u),iu.rgb,iu.a)*.82;col=mix(col,ab,smoothstep(-.012,-.0005,d.z)*.9);}
  }
  gl_FragColor=vec4(clamp(col,0.,1.),1.);}