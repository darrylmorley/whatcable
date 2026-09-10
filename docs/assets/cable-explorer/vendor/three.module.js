var HH="180",FU={LEFT:0,MIDDLE:1,RIGHT:2,ROTATE:0,DOLLY:1,PAN:2},MU={ROTATE:0,PAN:1,DOLLY_PAN:2,DOLLY_ROTATE:3},YH=0,o$=1,XH=2,kU=3,VU=0,a$=1,UH=2,O8=3,Q6=0,i0=1,R8=2,m8=0,h6=1,r$=2,t$=3,e$=4,GH=5,$6=100,EH=101,NH=102,qH=103,DH=104,OH=200,RH=201,FH=202,MH=203,kH=204,VH=205,LH=206,zH=207,BH=208,IH=209,_H=210,wH=211,CH=212,PH=213,AH=214,JQ=0,QQ=1,$Q=2,x6=3,ZQ=4,WQ=5,KQ=6,HQ=7,TH=0,SH=1,jH=2,T8=0,yH=1,vH=2,fH=3,bH=4,hH=5,xH=6,gH=7,LU="attached",zU="detached",BU=300,Z6=301,D9=302,YQ=303,XQ=304,g6=306,pH=1000,mH=1001,dH=1002,W6=1003,lH=1004,IU=1004,p6=1005,_U=1005,O9=1006,UQ=1007,wU=1007,K6=1008,CU=1008,d8=1009,uH=1010,cH=1011,m6=1012,JZ=1013,H6=1014,l8=1015,d6=1016,QZ=1017,$Z=1018,Y6=1020,nH=35902,sH=35899,iH=1021,oH=1022,F8=1023,GQ=1026,l6=1027,aH=1028,ZZ=1029,rH=1030,WZ=1031,PU=1032,KZ=1033,EQ=33776,NQ=33777,qQ=33778,DQ=33779,HZ=35840,YZ=35841,XZ=35842,UZ=35843,GZ=36196,EZ=37492,NZ=37496,qZ=37808,DZ=37809,OZ=37810,RZ=37811,FZ=37812,MZ=37813,kZ=37814,VZ=37815,LZ=37816,zZ=37817,BZ=37818,IZ=37819,_Z=37820,wZ=37821,CZ=36492,PZ=36494,AZ=36495,TZ=36283,SZ=36284,jZ=36285,yZ=36286,AU=2200,TU=2201,SU=2202,jU=2300,yU=2301,vU=2302,fU=2400,bU=2401,hU=2402,xU=2500,gU=2501,pU=0,mU=1,dU=2,lU=3200,tH=3201,uU=3202,cU=3203,eH=0,JY=1,R9="",QY="srgb",u6="srgb-linear",vZ="linear",G0="srgb",nU=0,sU=7680,iU=7681,oU=7682,aU=7683,rU=34055,tU=34056,eU=5386,JG=512,QG=513,$G=514,ZG=515,WG=516,KG=517,HG=518,YG=519,$Y=512,ZY=513,WY=514,fZ=515,KY=516,HY=517,YY=518,XY=519,XG=35044,UG=35048,GG=35040,EG=35045,NG=35049,qG=35041,DG=35046,OG=35050,RG=35042,FG="100",bZ="300 es",hZ=2000,MG=2001,kG={COMPUTE:"compute",RENDER:"render"},VG={PERSPECTIVE:"perspective",LINEAR:"linear",FLAT:"flat"},LG={NORMAL:"normal",CENTROID:"centroid",SAMPLE:"sample",FIRST:"first",EITHER:"either"};class H8{addEventListener(J,Q){if(this._listeners===void 0)this._listeners={};let $=this._listeners;if($[J]===void 0)$[J]=[];if($[J].indexOf(Q)===-1)$[J].push(Q)}hasEventListener(J,Q){let $=this._listeners;if($===void 0)return!1;return $[J]!==void 0&&$[J].indexOf(Q)!==-1}removeEventListener(J,Q){let $=this._listeners;if($===void 0)return;let Z=$[J];if(Z!==void 0){let W=Z.indexOf(Q);if(W!==-1)Z.splice(W,1)}}dispatchEvent(J){let Q=this._listeners;if(Q===void 0)return;let $=Q[J.type];if($!==void 0){J.target=this;let Z=$.slice(0);for(let W=0,K=Z.length;W<K;W++)Z[W].call(this,J);J.target=null}}}var P0=["00","01","02","03","04","05","06","07","08","09","0a","0b","0c","0d","0e","0f","10","11","12","13","14","15","16","17","18","19","1a","1b","1c","1d","1e","1f","20","21","22","23","24","25","26","27","28","29","2a","2b","2c","2d","2e","2f","30","31","32","33","34","35","36","37","38","39","3a","3b","3c","3d","3e","3f","40","41","42","43","44","45","46","47","48","49","4a","4b","4c","4d","4e","4f","50","51","52","53","54","55","56","57","58","59","5a","5b","5c","5d","5e","5f","60","61","62","63","64","65","66","67","68","69","6a","6b","6c","6d","6e","6f","70","71","72","73","74","75","76","77","78","79","7a","7b","7c","7d","7e","7f","80","81","82","83","84","85","86","87","88","89","8a","8b","8c","8d","8e","8f","90","91","92","93","94","95","96","97","98","99","9a","9b","9c","9d","9e","9f","a0","a1","a2","a3","a4","a5","a6","a7","a8","a9","aa","ab","ac","ad","ae","af","b0","b1","b2","b3","b4","b5","b6","b7","b8","b9","ba","bb","bc","bd","be","bf","c0","c1","c2","c3","c4","c5","c6","c7","c8","c9","ca","cb","cc","cd","ce","cf","d0","d1","d2","d3","d4","d5","d6","d7","d8","d9","da","db","dc","dd","de","df","e0","e1","e2","e3","e4","e5","e6","e7","e8","e9","ea","eb","ec","ed","ee","ef","f0","f1","f2","f3","f4","f5","f6","f7","f8","f9","fa","fb","fc","fd","fe","ff"],eW=1234567,U9=Math.PI/180,G9=180/Math.PI;function n0(){let J=Math.random()*4294967295|0,Q=Math.random()*4294967295|0,$=Math.random()*4294967295|0,Z=Math.random()*4294967295|0;return(P0[J&255]+P0[J>>8&255]+P0[J>>16&255]+P0[J>>24&255]+"-"+P0[Q&255]+P0[Q>>8&255]+"-"+P0[Q>>16&15|64]+P0[Q>>24&255]+"-"+P0[$&63|128]+P0[$>>8&255]+"-"+P0[$>>16&255]+P0[$>>24&255]+P0[Z&255]+P0[Z>>8&255]+P0[Z>>16&255]+P0[Z>>24&255]).toLowerCase()}function bJ(J,Q,$){return Math.max(Q,Math.min($,J))}function xZ(J,Q){return(J%Q+Q)%Q}function zG(J,Q,$,Z,W){return Z+(J-Q)*(W-Z)/($-Q)}function BG(J,Q,$){if(J!==Q)return($-J)/(Q-J);else return 0}function T6(J,Q,$){return(1-$)*J+$*Q}function IG(J,Q,$,Z){return T6(J,Q,1-Math.exp(-$*Z))}function _G(J,Q=1){return Q-Math.abs(xZ(J,Q*2)-Q)}function wG(J,Q,$){if(J<=Q)return 0;if(J>=$)return 1;return J=(J-Q)/($-Q),J*J*(3-2*J)}function CG(J,Q,$){if(J<=Q)return 0;if(J>=$)return 1;return J=(J-Q)/($-Q),J*J*J*(J*(J*6-15)+10)}function PG(J,Q){return J+Math.floor(Math.random()*(Q-J+1))}function AG(J,Q){return J+Math.random()*(Q-J)}function TG(J){return J*(0.5-Math.random())}function SG(J){if(J!==void 0)eW=J;let Q=eW+=1831565813;return Q=Math.imul(Q^Q>>>15,Q|1),Q^=Q+Math.imul(Q^Q>>>7,Q|61),((Q^Q>>>14)>>>0)/4294967296}function jG(J){return J*U9}function yG(J){return J*G9}function vG(J){return(J&J-1)===0&&J!==0}function fG(J){return Math.pow(2,Math.ceil(Math.log(J)/Math.LN2))}function bG(J){return Math.pow(2,Math.floor(Math.log(J)/Math.LN2))}function hG(J,Q,$,Z,W){let{cos:K,sin:H}=Math,Y=K($/2),X=H($/2),U=K((Q+Z)/2),G=H((Q+Z)/2),E=K((Q-Z)/2),N=H((Q-Z)/2),q=K((Z-Q)/2),R=H((Z-Q)/2);switch(W){case"XYX":J.set(Y*G,X*E,X*N,Y*U);break;case"YZY":J.set(X*N,Y*G,X*E,Y*U);break;case"ZXZ":J.set(X*E,X*N,Y*G,Y*U);break;case"XZX":J.set(Y*G,X*R,X*q,Y*U);break;case"YXY":J.set(X*q,Y*G,X*R,Y*U);break;case"ZYZ":J.set(X*R,X*q,Y*G,Y*U);break;default:console.warn("THREE.MathUtils: .setQuaternionFromProperEuler() encountered an unknown order: "+W)}}function f0(J,Q){switch(Q.constructor){case Float32Array:return J;case Uint32Array:return J/4294967295;case Uint16Array:return J/65535;case Uint8Array:return J/255;case Int32Array:return Math.max(J/2147483647,-1);case Int16Array:return Math.max(J/32767,-1);case Int8Array:return Math.max(J/127,-1);default:throw Error("Invalid component type.")}}function cJ(J,Q){switch(Q.constructor){case Float32Array:return J;case Uint32Array:return Math.round(J*4294967295);case Uint16Array:return Math.round(J*65535);case Uint8Array:return Math.round(J*255);case Int32Array:return Math.round(J*2147483647);case Int16Array:return Math.round(J*32767);case Int8Array:return Math.round(J*127);default:throw Error("Invalid component type.")}}var xG={DEG2RAD:U9,RAD2DEG:G9,generateUUID:n0,clamp:bJ,euclideanModulo:xZ,mapLinear:zG,inverseLerp:BG,lerp:T6,damp:IG,pingpong:_G,smoothstep:wG,smootherstep:CG,randInt:PG,randFloat:AG,randFloatSpread:TG,seededRandom:SG,degToRad:jG,radToDeg:yG,isPowerOfTwo:vG,ceilPowerOfTwo:fG,floorPowerOfTwo:bG,setQuaternionFromProperEuler:hG,normalize:cJ,denormalize:f0};class t{constructor(J=0,Q=0){t.prototype.isVector2=!0,this.x=J,this.y=Q}get width(){return this.x}set width(J){this.x=J}get height(){return this.y}set height(J){this.y=J}set(J,Q){return this.x=J,this.y=Q,this}setScalar(J){return this.x=J,this.y=J,this}setX(J){return this.x=J,this}setY(J){return this.y=J,this}setComponent(J,Q){switch(J){case 0:this.x=Q;break;case 1:this.y=Q;break;default:throw Error("index is out of range: "+J)}return this}getComponent(J){switch(J){case 0:return this.x;case 1:return this.y;default:throw Error("index is out of range: "+J)}}clone(){return new this.constructor(this.x,this.y)}copy(J){return this.x=J.x,this.y=J.y,this}add(J){return this.x+=J.x,this.y+=J.y,this}addScalar(J){return this.x+=J,this.y+=J,this}addVectors(J,Q){return this.x=J.x+Q.x,this.y=J.y+Q.y,this}addScaledVector(J,Q){return this.x+=J.x*Q,this.y+=J.y*Q,this}sub(J){return this.x-=J.x,this.y-=J.y,this}subScalar(J){return this.x-=J,this.y-=J,this}subVectors(J,Q){return this.x=J.x-Q.x,this.y=J.y-Q.y,this}multiply(J){return this.x*=J.x,this.y*=J.y,this}multiplyScalar(J){return this.x*=J,this.y*=J,this}divide(J){return this.x/=J.x,this.y/=J.y,this}divideScalar(J){return this.multiplyScalar(1/J)}applyMatrix3(J){let Q=this.x,$=this.y,Z=J.elements;return this.x=Z[0]*Q+Z[3]*$+Z[6],this.y=Z[1]*Q+Z[4]*$+Z[7],this}min(J){return this.x=Math.min(this.x,J.x),this.y=Math.min(this.y,J.y),this}max(J){return this.x=Math.max(this.x,J.x),this.y=Math.max(this.y,J.y),this}clamp(J,Q){return this.x=bJ(this.x,J.x,Q.x),this.y=bJ(this.y,J.y,Q.y),this}clampScalar(J,Q){return this.x=bJ(this.x,J,Q),this.y=bJ(this.y,J,Q),this}clampLength(J,Q){let $=this.length();return this.divideScalar($||1).multiplyScalar(bJ($,J,Q))}floor(){return this.x=Math.floor(this.x),this.y=Math.floor(this.y),this}ceil(){return this.x=Math.ceil(this.x),this.y=Math.ceil(this.y),this}round(){return this.x=Math.round(this.x),this.y=Math.round(this.y),this}roundToZero(){return this.x=Math.trunc(this.x),this.y=Math.trunc(this.y),this}negate(){return this.x=-this.x,this.y=-this.y,this}dot(J){return this.x*J.x+this.y*J.y}cross(J){return this.x*J.y-this.y*J.x}lengthSq(){return this.x*this.x+this.y*this.y}length(){return Math.sqrt(this.x*this.x+this.y*this.y)}manhattanLength(){return Math.abs(this.x)+Math.abs(this.y)}normalize(){return this.divideScalar(this.length()||1)}angle(){return Math.atan2(-this.y,-this.x)+Math.PI}angleTo(J){let Q=Math.sqrt(this.lengthSq()*J.lengthSq());if(Q===0)return Math.PI/2;let $=this.dot(J)/Q;return Math.acos(bJ($,-1,1))}distanceTo(J){return Math.sqrt(this.distanceToSquared(J))}distanceToSquared(J){let Q=this.x-J.x,$=this.y-J.y;return Q*Q+$*$}manhattanDistanceTo(J){return Math.abs(this.x-J.x)+Math.abs(this.y-J.y)}setLength(J){return this.normalize().multiplyScalar(J)}lerp(J,Q){return this.x+=(J.x-this.x)*Q,this.y+=(J.y-this.y)*Q,this}lerpVectors(J,Q,$){return this.x=J.x+(Q.x-J.x)*$,this.y=J.y+(Q.y-J.y)*$,this}equals(J){return J.x===this.x&&J.y===this.y}fromArray(J,Q=0){return this.x=J[Q],this.y=J[Q+1],this}toArray(J=[],Q=0){return J[Q]=this.x,J[Q+1]=this.y,J}fromBufferAttribute(J,Q){return this.x=J.getX(Q),this.y=J.getY(Q),this}rotateAround(J,Q){let $=Math.cos(Q),Z=Math.sin(Q),W=this.x-J.x,K=this.y-J.y;return this.x=W*$-K*Z+J.x,this.y=W*Z+K*$+J.y,this}random(){return this.x=Math.random(),this.y=Math.random(),this}*[Symbol.iterator](){yield this.x,yield this.y}}class b0{constructor(J=0,Q=0,$=0,Z=1){this.isQuaternion=!0,this._x=J,this._y=Q,this._z=$,this._w=Z}static slerpFlat(J,Q,$,Z,W,K,H){let Y=$[Z+0],X=$[Z+1],U=$[Z+2],G=$[Z+3],E=W[K+0],N=W[K+1],q=W[K+2],R=W[K+3];if(H===0){J[Q+0]=Y,J[Q+1]=X,J[Q+2]=U,J[Q+3]=G;return}if(H===1){J[Q+0]=E,J[Q+1]=N,J[Q+2]=q,J[Q+3]=R;return}if(G!==R||Y!==E||X!==N||U!==q){let F=1-H,O=Y*E+X*N+U*q+G*R,D=O>=0?1:-1,k=1-O*O;if(k>Number.EPSILON){let L=Math.sqrt(k),A=Math.atan2(L,O*D);F=Math.sin(F*A)/L,H=Math.sin(H*A)/L}let M=H*D;if(Y=Y*F+E*M,X=X*F+N*M,U=U*F+q*M,G=G*F+R*M,F===1-H){let L=1/Math.sqrt(Y*Y+X*X+U*U+G*G);Y*=L,X*=L,U*=L,G*=L}}J[Q]=Y,J[Q+1]=X,J[Q+2]=U,J[Q+3]=G}static multiplyQuaternionsFlat(J,Q,$,Z,W,K){let H=$[Z],Y=$[Z+1],X=$[Z+2],U=$[Z+3],G=W[K],E=W[K+1],N=W[K+2],q=W[K+3];return J[Q]=H*q+U*G+Y*N-X*E,J[Q+1]=Y*q+U*E+X*G-H*N,J[Q+2]=X*q+U*N+H*E-Y*G,J[Q+3]=U*q-H*G-Y*E-X*N,J}get x(){return this._x}set x(J){this._x=J,this._onChangeCallback()}get y(){return this._y}set y(J){this._y=J,this._onChangeCallback()}get z(){return this._z}set z(J){this._z=J,this._onChangeCallback()}get w(){return this._w}set w(J){this._w=J,this._onChangeCallback()}set(J,Q,$,Z){return this._x=J,this._y=Q,this._z=$,this._w=Z,this._onChangeCallback(),this}clone(){return new this.constructor(this._x,this._y,this._z,this._w)}copy(J){return this._x=J.x,this._y=J.y,this._z=J.z,this._w=J.w,this._onChangeCallback(),this}setFromEuler(J,Q=!0){let{_x:$,_y:Z,_z:W,_order:K}=J,H=Math.cos,Y=Math.sin,X=H($/2),U=H(Z/2),G=H(W/2),E=Y($/2),N=Y(Z/2),q=Y(W/2);switch(K){case"XYZ":this._x=E*U*G+X*N*q,this._y=X*N*G-E*U*q,this._z=X*U*q+E*N*G,this._w=X*U*G-E*N*q;break;case"YXZ":this._x=E*U*G+X*N*q,this._y=X*N*G-E*U*q,this._z=X*U*q-E*N*G,this._w=X*U*G+E*N*q;break;case"ZXY":this._x=E*U*G-X*N*q,this._y=X*N*G+E*U*q,this._z=X*U*q+E*N*G,this._w=X*U*G-E*N*q;break;case"ZYX":this._x=E*U*G-X*N*q,this._y=X*N*G+E*U*q,this._z=X*U*q-E*N*G,this._w=X*U*G+E*N*q;break;case"YZX":this._x=E*U*G+X*N*q,this._y=X*N*G+E*U*q,this._z=X*U*q-E*N*G,this._w=X*U*G-E*N*q;break;case"XZY":this._x=E*U*G-X*N*q,this._y=X*N*G-E*U*q,this._z=X*U*q+E*N*G,this._w=X*U*G+E*N*q;break;default:console.warn("THREE.Quaternion: .setFromEuler() encountered an unknown order: "+K)}if(Q===!0)this._onChangeCallback();return this}setFromAxisAngle(J,Q){let $=Q/2,Z=Math.sin($);return this._x=J.x*Z,this._y=J.y*Z,this._z=J.z*Z,this._w=Math.cos($),this._onChangeCallback(),this}setFromRotationMatrix(J){let Q=J.elements,$=Q[0],Z=Q[4],W=Q[8],K=Q[1],H=Q[5],Y=Q[9],X=Q[2],U=Q[6],G=Q[10],E=$+H+G;if(E>0){let N=0.5/Math.sqrt(E+1);this._w=0.25/N,this._x=(U-Y)*N,this._y=(W-X)*N,this._z=(K-Z)*N}else if($>H&&$>G){let N=2*Math.sqrt(1+$-H-G);this._w=(U-Y)/N,this._x=0.25*N,this._y=(Z+K)/N,this._z=(W+X)/N}else if(H>G){let N=2*Math.sqrt(1+H-$-G);this._w=(W-X)/N,this._x=(Z+K)/N,this._y=0.25*N,this._z=(Y+U)/N}else{let N=2*Math.sqrt(1+G-$-H);this._w=(K-Z)/N,this._x=(W+X)/N,this._y=(Y+U)/N,this._z=0.25*N}return this._onChangeCallback(),this}setFromUnitVectors(J,Q){let $=J.dot(Q)+1;if($<0.00000001)if($=0,Math.abs(J.x)>Math.abs(J.z))this._x=-J.y,this._y=J.x,this._z=0,this._w=$;else this._x=0,this._y=-J.z,this._z=J.y,this._w=$;else this._x=J.y*Q.z-J.z*Q.y,this._y=J.z*Q.x-J.x*Q.z,this._z=J.x*Q.y-J.y*Q.x,this._w=$;return this.normalize()}angleTo(J){return 2*Math.acos(Math.abs(bJ(this.dot(J),-1,1)))}rotateTowards(J,Q){let $=this.angleTo(J);if($===0)return this;let Z=Math.min(1,Q/$);return this.slerp(J,Z),this}identity(){return this.set(0,0,0,1)}invert(){return this.conjugate()}conjugate(){return this._x*=-1,this._y*=-1,this._z*=-1,this._onChangeCallback(),this}dot(J){return this._x*J._x+this._y*J._y+this._z*J._z+this._w*J._w}lengthSq(){return this._x*this._x+this._y*this._y+this._z*this._z+this._w*this._w}length(){return Math.sqrt(this._x*this._x+this._y*this._y+this._z*this._z+this._w*this._w)}normalize(){let J=this.length();if(J===0)this._x=0,this._y=0,this._z=0,this._w=1;else J=1/J,this._x=this._x*J,this._y=this._y*J,this._z=this._z*J,this._w=this._w*J;return this._onChangeCallback(),this}multiply(J){return this.multiplyQuaternions(this,J)}premultiply(J){return this.multiplyQuaternions(J,this)}multiplyQuaternions(J,Q){let{_x:$,_y:Z,_z:W,_w:K}=J,H=Q._x,Y=Q._y,X=Q._z,U=Q._w;return this._x=$*U+K*H+Z*X-W*Y,this._y=Z*U+K*Y+W*H-$*X,this._z=W*U+K*X+$*Y-Z*H,this._w=K*U-$*H-Z*Y-W*X,this._onChangeCallback(),this}slerp(J,Q){if(Q===0)return this;if(Q===1)return this.copy(J);let $=this._x,Z=this._y,W=this._z,K=this._w,H=K*J._w+$*J._x+Z*J._y+W*J._z;if(H<0)this._w=-J._w,this._x=-J._x,this._y=-J._y,this._z=-J._z,H=-H;else this.copy(J);if(H>=1)return this._w=K,this._x=$,this._y=Z,this._z=W,this;let Y=1-H*H;if(Y<=Number.EPSILON){let N=1-Q;return this._w=N*K+Q*this._w,this._x=N*$+Q*this._x,this._y=N*Z+Q*this._y,this._z=N*W+Q*this._z,this.normalize(),this}let X=Math.sqrt(Y),U=Math.atan2(X,H),G=Math.sin((1-Q)*U)/X,E=Math.sin(Q*U)/X;return this._w=K*G+this._w*E,this._x=$*G+this._x*E,this._y=Z*G+this._y*E,this._z=W*G+this._z*E,this._onChangeCallback(),this}slerpQuaternions(J,Q,$){return this.copy(J).slerp(Q,$)}random(){let J=2*Math.PI*Math.random(),Q=2*Math.PI*Math.random(),$=Math.random(),Z=Math.sqrt(1-$),W=Math.sqrt($);return this.set(Z*Math.sin(J),Z*Math.cos(J),W*Math.sin(Q),W*Math.cos(Q))}equals(J){return J._x===this._x&&J._y===this._y&&J._z===this._z&&J._w===this._w}fromArray(J,Q=0){return this._x=J[Q],this._y=J[Q+1],this._z=J[Q+2],this._w=J[Q+3],this._onChangeCallback(),this}toArray(J=[],Q=0){return J[Q]=this._x,J[Q+1]=this._y,J[Q+2]=this._z,J[Q+3]=this._w,J}fromBufferAttribute(J,Q){return this._x=J.getX(Q),this._y=J.getY(Q),this._z=J.getZ(Q),this._w=J.getW(Q),this._onChangeCallback(),this}toJSON(){return this.toArray()}_onChange(J){return this._onChangeCallback=J,this}_onChangeCallback(){}*[Symbol.iterator](){yield this._x,yield this._y,yield this._z,yield this._w}}class w{constructor(J=0,Q=0,$=0){w.prototype.isVector3=!0,this.x=J,this.y=Q,this.z=$}set(J,Q,$){if($===void 0)$=this.z;return this.x=J,this.y=Q,this.z=$,this}setScalar(J){return this.x=J,this.y=J,this.z=J,this}setX(J){return this.x=J,this}setY(J){return this.y=J,this}setZ(J){return this.z=J,this}setComponent(J,Q){switch(J){case 0:this.x=Q;break;case 1:this.y=Q;break;case 2:this.z=Q;break;default:throw Error("index is out of range: "+J)}return this}getComponent(J){switch(J){case 0:return this.x;case 1:return this.y;case 2:return this.z;default:throw Error("index is out of range: "+J)}}clone(){return new this.constructor(this.x,this.y,this.z)}copy(J){return this.x=J.x,this.y=J.y,this.z=J.z,this}add(J){return this.x+=J.x,this.y+=J.y,this.z+=J.z,this}addScalar(J){return this.x+=J,this.y+=J,this.z+=J,this}addVectors(J,Q){return this.x=J.x+Q.x,this.y=J.y+Q.y,this.z=J.z+Q.z,this}addScaledVector(J,Q){return this.x+=J.x*Q,this.y+=J.y*Q,this.z+=J.z*Q,this}sub(J){return this.x-=J.x,this.y-=J.y,this.z-=J.z,this}subScalar(J){return this.x-=J,this.y-=J,this.z-=J,this}subVectors(J,Q){return this.x=J.x-Q.x,this.y=J.y-Q.y,this.z=J.z-Q.z,this}multiply(J){return this.x*=J.x,this.y*=J.y,this.z*=J.z,this}multiplyScalar(J){return this.x*=J,this.y*=J,this.z*=J,this}multiplyVectors(J,Q){return this.x=J.x*Q.x,this.y=J.y*Q.y,this.z=J.z*Q.z,this}applyEuler(J){return this.applyQuaternion(JK.setFromEuler(J))}applyAxisAngle(J,Q){return this.applyQuaternion(JK.setFromAxisAngle(J,Q))}applyMatrix3(J){let Q=this.x,$=this.y,Z=this.z,W=J.elements;return this.x=W[0]*Q+W[3]*$+W[6]*Z,this.y=W[1]*Q+W[4]*$+W[7]*Z,this.z=W[2]*Q+W[5]*$+W[8]*Z,this}applyNormalMatrix(J){return this.applyMatrix3(J).normalize()}applyMatrix4(J){let Q=this.x,$=this.y,Z=this.z,W=J.elements,K=1/(W[3]*Q+W[7]*$+W[11]*Z+W[15]);return this.x=(W[0]*Q+W[4]*$+W[8]*Z+W[12])*K,this.y=(W[1]*Q+W[5]*$+W[9]*Z+W[13])*K,this.z=(W[2]*Q+W[6]*$+W[10]*Z+W[14])*K,this}applyQuaternion(J){let Q=this.x,$=this.y,Z=this.z,W=J.x,K=J.y,H=J.z,Y=J.w,X=2*(K*Z-H*$),U=2*(H*Q-W*Z),G=2*(W*$-K*Q);return this.x=Q+Y*X+K*G-H*U,this.y=$+Y*U+H*X-W*G,this.z=Z+Y*G+W*U-K*X,this}project(J){return this.applyMatrix4(J.matrixWorldInverse).applyMatrix4(J.projectionMatrix)}unproject(J){return this.applyMatrix4(J.projectionMatrixInverse).applyMatrix4(J.matrixWorld)}transformDirection(J){let Q=this.x,$=this.y,Z=this.z,W=J.elements;return this.x=W[0]*Q+W[4]*$+W[8]*Z,this.y=W[1]*Q+W[5]*$+W[9]*Z,this.z=W[2]*Q+W[6]*$+W[10]*Z,this.normalize()}divide(J){return this.x/=J.x,this.y/=J.y,this.z/=J.z,this}divideScalar(J){return this.multiplyScalar(1/J)}min(J){return this.x=Math.min(this.x,J.x),this.y=Math.min(this.y,J.y),this.z=Math.min(this.z,J.z),this}max(J){return this.x=Math.max(this.x,J.x),this.y=Math.max(this.y,J.y),this.z=Math.max(this.z,J.z),this}clamp(J,Q){return this.x=bJ(this.x,J.x,Q.x),this.y=bJ(this.y,J.y,Q.y),this.z=bJ(this.z,J.z,Q.z),this}clampScalar(J,Q){return this.x=bJ(this.x,J,Q),this.y=bJ(this.y,J,Q),this.z=bJ(this.z,J,Q),this}clampLength(J,Q){let $=this.length();return this.divideScalar($||1).multiplyScalar(bJ($,J,Q))}floor(){return this.x=Math.floor(this.x),this.y=Math.floor(this.y),this.z=Math.floor(this.z),this}ceil(){return this.x=Math.ceil(this.x),this.y=Math.ceil(this.y),this.z=Math.ceil(this.z),this}round(){return this.x=Math.round(this.x),this.y=Math.round(this.y),this.z=Math.round(this.z),this}roundToZero(){return this.x=Math.trunc(this.x),this.y=Math.trunc(this.y),this.z=Math.trunc(this.z),this}negate(){return this.x=-this.x,this.y=-this.y,this.z=-this.z,this}dot(J){return this.x*J.x+this.y*J.y+this.z*J.z}lengthSq(){return this.x*this.x+this.y*this.y+this.z*this.z}length(){return Math.sqrt(this.x*this.x+this.y*this.y+this.z*this.z)}manhattanLength(){return Math.abs(this.x)+Math.abs(this.y)+Math.abs(this.z)}normalize(){return this.divideScalar(this.length()||1)}setLength(J){return this.normalize().multiplyScalar(J)}lerp(J,Q){return this.x+=(J.x-this.x)*Q,this.y+=(J.y-this.y)*Q,this.z+=(J.z-this.z)*Q,this}lerpVectors(J,Q,$){return this.x=J.x+(Q.x-J.x)*$,this.y=J.y+(Q.y-J.y)*$,this.z=J.z+(Q.z-J.z)*$,this}cross(J){return this.crossVectors(this,J)}crossVectors(J,Q){let{x:$,y:Z,z:W}=J,K=Q.x,H=Q.y,Y=Q.z;return this.x=Z*Y-W*H,this.y=W*K-$*Y,this.z=$*H-Z*K,this}projectOnVector(J){let Q=J.lengthSq();if(Q===0)return this.set(0,0,0);let $=J.dot(this)/Q;return this.copy(J).multiplyScalar($)}projectOnPlane(J){return H$.copy(this).projectOnVector(J),this.sub(H$)}reflect(J){return this.sub(H$.copy(J).multiplyScalar(2*this.dot(J)))}angleTo(J){let Q=Math.sqrt(this.lengthSq()*J.lengthSq());if(Q===0)return Math.PI/2;let $=this.dot(J)/Q;return Math.acos(bJ($,-1,1))}distanceTo(J){return Math.sqrt(this.distanceToSquared(J))}distanceToSquared(J){let Q=this.x-J.x,$=this.y-J.y,Z=this.z-J.z;return Q*Q+$*$+Z*Z}manhattanDistanceTo(J){return Math.abs(this.x-J.x)+Math.abs(this.y-J.y)+Math.abs(this.z-J.z)}setFromSpherical(J){return this.setFromSphericalCoords(J.radius,J.phi,J.theta)}setFromSphericalCoords(J,Q,$){let Z=Math.sin(Q)*J;return this.x=Z*Math.sin($),this.y=Math.cos(Q)*J,this.z=Z*Math.cos($),this}setFromCylindrical(J){return this.setFromCylindricalCoords(J.radius,J.theta,J.y)}setFromCylindricalCoords(J,Q,$){return this.x=J*Math.sin(Q),this.y=$,this.z=J*Math.cos(Q),this}setFromMatrixPosition(J){let Q=J.elements;return this.x=Q[12],this.y=Q[13],this.z=Q[14],this}setFromMatrixScale(J){let Q=this.setFromMatrixColumn(J,0).length(),$=this.setFromMatrixColumn(J,1).length(),Z=this.setFromMatrixColumn(J,2).length();return this.x=Q,this.y=$,this.z=Z,this}setFromMatrixColumn(J,Q){return this.fromArray(J.elements,Q*4)}setFromMatrix3Column(J,Q){return this.fromArray(J.elements,Q*3)}setFromEuler(J){return this.x=J._x,this.y=J._y,this.z=J._z,this}setFromColor(J){return this.x=J.r,this.y=J.g,this.z=J.b,this}equals(J){return J.x===this.x&&J.y===this.y&&J.z===this.z}fromArray(J,Q=0){return this.x=J[Q],this.y=J[Q+1],this.z=J[Q+2],this}toArray(J=[],Q=0){return J[Q]=this.x,J[Q+1]=this.y,J[Q+2]=this.z,J}fromBufferAttribute(J,Q){return this.x=J.getX(Q),this.y=J.getY(Q),this.z=J.getZ(Q),this}random(){return this.x=Math.random(),this.y=Math.random(),this.z=Math.random(),this}randomDirection(){let J=Math.random()*Math.PI*2,Q=Math.random()*2-1,$=Math.sqrt(1-Q*Q);return this.x=$*Math.cos(J),this.y=Q,this.z=$*Math.sin(J),this}*[Symbol.iterator](){yield this.x,yield this.y,yield this.z}}var H$=new w,JK=new b0;class dJ{constructor(J,Q,$,Z,W,K,H,Y,X){if(dJ.prototype.isMatrix3=!0,this.elements=[1,0,0,0,1,0,0,0,1],J!==void 0)this.set(J,Q,$,Z,W,K,H,Y,X)}set(J,Q,$,Z,W,K,H,Y,X){let U=this.elements;return U[0]=J,U[1]=Z,U[2]=H,U[3]=Q,U[4]=W,U[5]=Y,U[6]=$,U[7]=K,U[8]=X,this}identity(){return this.set(1,0,0,0,1,0,0,0,1),this}copy(J){let Q=this.elements,$=J.elements;return Q[0]=$[0],Q[1]=$[1],Q[2]=$[2],Q[3]=$[3],Q[4]=$[4],Q[5]=$[5],Q[6]=$[6],Q[7]=$[7],Q[8]=$[8],this}extractBasis(J,Q,$){return J.setFromMatrix3Column(this,0),Q.setFromMatrix3Column(this,1),$.setFromMatrix3Column(this,2),this}setFromMatrix4(J){let Q=J.elements;return this.set(Q[0],Q[4],Q[8],Q[1],Q[5],Q[9],Q[2],Q[6],Q[10]),this}multiply(J){return this.multiplyMatrices(this,J)}premultiply(J){return this.multiplyMatrices(J,this)}multiplyMatrices(J,Q){let $=J.elements,Z=Q.elements,W=this.elements,K=$[0],H=$[3],Y=$[6],X=$[1],U=$[4],G=$[7],E=$[2],N=$[5],q=$[8],R=Z[0],F=Z[3],O=Z[6],D=Z[1],k=Z[4],M=Z[7],L=Z[2],A=Z[5],_=Z[8];return W[0]=K*R+H*D+Y*L,W[3]=K*F+H*k+Y*A,W[6]=K*O+H*M+Y*_,W[1]=X*R+U*D+G*L,W[4]=X*F+U*k+G*A,W[7]=X*O+U*M+G*_,W[2]=E*R+N*D+q*L,W[5]=E*F+N*k+q*A,W[8]=E*O+N*M+q*_,this}multiplyScalar(J){let Q=this.elements;return Q[0]*=J,Q[3]*=J,Q[6]*=J,Q[1]*=J,Q[4]*=J,Q[7]*=J,Q[2]*=J,Q[5]*=J,Q[8]*=J,this}determinant(){let J=this.elements,Q=J[0],$=J[1],Z=J[2],W=J[3],K=J[4],H=J[5],Y=J[6],X=J[7],U=J[8];return Q*K*U-Q*H*X-$*W*U+$*H*Y+Z*W*X-Z*K*Y}invert(){let J=this.elements,Q=J[0],$=J[1],Z=J[2],W=J[3],K=J[4],H=J[5],Y=J[6],X=J[7],U=J[8],G=U*K-H*X,E=H*Y-U*W,N=X*W-K*Y,q=Q*G+$*E+Z*N;if(q===0)return this.set(0,0,0,0,0,0,0,0,0);let R=1/q;return J[0]=G*R,J[1]=(Z*X-U*$)*R,J[2]=(H*$-Z*K)*R,J[3]=E*R,J[4]=(U*Q-Z*Y)*R,J[5]=(Z*W-H*Q)*R,J[6]=N*R,J[7]=($*Y-X*Q)*R,J[8]=(K*Q-$*W)*R,this}transpose(){let J,Q=this.elements;return J=Q[1],Q[1]=Q[3],Q[3]=J,J=Q[2],Q[2]=Q[6],Q[6]=J,J=Q[5],Q[5]=Q[7],Q[7]=J,this}getNormalMatrix(J){return this.setFromMatrix4(J).invert().transpose()}transposeIntoArray(J){let Q=this.elements;return J[0]=Q[0],J[1]=Q[3],J[2]=Q[6],J[3]=Q[1],J[4]=Q[4],J[5]=Q[7],J[6]=Q[2],J[7]=Q[5],J[8]=Q[8],this}setUvTransform(J,Q,$,Z,W,K,H){let Y=Math.cos(W),X=Math.sin(W);return this.set($*Y,$*X,-$*(Y*K+X*H)+K+J,-Z*X,Z*Y,-Z*(-X*K+Y*H)+H+Q,0,0,1),this}scale(J,Q){return this.premultiply(Y$.makeScale(J,Q)),this}rotate(J){return this.premultiply(Y$.makeRotation(-J)),this}translate(J,Q){return this.premultiply(Y$.makeTranslation(J,Q)),this}makeTranslation(J,Q){if(J.isVector2)this.set(1,0,J.x,0,1,J.y,0,0,1);else this.set(1,0,J,0,1,Q,0,0,1);return this}makeRotation(J){let Q=Math.cos(J),$=Math.sin(J);return this.set(Q,-$,0,$,Q,0,0,0,1),this}makeScale(J,Q){return this.set(J,0,0,0,Q,0,0,0,1),this}equals(J){let Q=this.elements,$=J.elements;for(let Z=0;Z<9;Z++)if(Q[Z]!==$[Z])return!1;return!0}fromArray(J,Q=0){for(let $=0;$<9;$++)this.elements[$]=J[$+Q];return this}toArray(J=[],Q=0){let $=this.elements;return J[Q]=$[0],J[Q+1]=$[1],J[Q+2]=$[2],J[Q+3]=$[3],J[Q+4]=$[4],J[Q+5]=$[5],J[Q+6]=$[6],J[Q+7]=$[7],J[Q+8]=$[8],J}clone(){return new this.constructor().fromArray(this.elements)}}var Y$=new dJ;function gZ(J){for(let Q=J.length-1;Q>=0;--Q)if(J[Q]>=65535)return!0;return!1}var gG={Int8Array,Uint8Array,Uint8ClampedArray,Int16Array,Uint16Array,Int32Array,Uint32Array,Float32Array,Float64Array};function n9(J,Q){return new gG[J](Q)}function i9(J){return document.createElementNS("http://www.w3.org/1999/xhtml",J)}function UY(){let J=i9("canvas");return J.style.display="block",J}var QK={};function o9(J){if(J in QK)return;QK[J]=!0,console.warn(J)}function GY(J,Q,$){return new Promise(function(Z,W){function K(){switch(J.clientWaitSync(Q,J.SYNC_FLUSH_COMMANDS_BIT,0)){case J.WAIT_FAILED:W();break;case J.TIMEOUT_EXPIRED:setTimeout(K,$);break;default:Z()}}setTimeout(K,$)})}var $K=new dJ().set(0.4123908,0.3575843,0.1804808,0.212639,0.7151687,0.0721923,0.0193308,0.1191948,0.9505322),ZK=new dJ().set(3.2409699,-1.5373832,-0.4986108,-0.9692436,1.8759675,0.0415551,0.0556301,-0.203977,1.0569715);function pG(){let J={enabled:!0,workingColorSpace:"srgb-linear",spaces:{},convert:function(W,K,H){if(this.enabled===!1||K===H||!K||!H)return W;if(this.spaces[K].transfer==="srgb")W.r=P8(W.r),W.g=P8(W.g),W.b=P8(W.b);if(this.spaces[K].primaries!==this.spaces[H].primaries)W.applyMatrix3(this.spaces[K].toXYZ),W.applyMatrix3(this.spaces[H].fromXYZ);if(this.spaces[H].transfer==="srgb")W.r=s9(W.r),W.g=s9(W.g),W.b=s9(W.b);return W},workingToColorSpace:function(W,K){return this.convert(W,this.workingColorSpace,K)},colorSpaceToWorking:function(W,K){return this.convert(W,K,this.workingColorSpace)},getPrimaries:function(W){return this.spaces[W].primaries},getTransfer:function(W){if(W==="")return"linear";return this.spaces[W].transfer},getToneMappingMode:function(W){return this.spaces[W].outputColorSpaceConfig.toneMappingMode||"standard"},getLuminanceCoefficients:function(W,K=this.workingColorSpace){return W.fromArray(this.spaces[K].luminanceCoefficients)},define:function(W){Object.assign(this.spaces,W)},_getMatrix:function(W,K,H){return W.copy(this.spaces[K].toXYZ).multiply(this.spaces[H].fromXYZ)},_getDrawingBufferColorSpace:function(W){return this.spaces[W].outputColorSpaceConfig.drawingBufferColorSpace},_getUnpackColorSpace:function(W=this.workingColorSpace){return this.spaces[W].workingColorSpaceConfig.unpackColorSpace},fromWorkingColorSpace:function(W,K){return o9("THREE.ColorManagement: .fromWorkingColorSpace() has been renamed to .workingToColorSpace()."),J.workingToColorSpace(W,K)},toWorkingColorSpace:function(W,K){return o9("THREE.ColorManagement: .toWorkingColorSpace() has been renamed to .colorSpaceToWorking()."),J.colorSpaceToWorking(W,K)}},Q=[0.64,0.33,0.3,0.6,0.15,0.06],$=[0.2126,0.7152,0.0722],Z=[0.3127,0.329];return J.define({["srgb-linear"]:{primaries:Q,whitePoint:Z,transfer:"linear",toXYZ:$K,fromXYZ:ZK,luminanceCoefficients:$,workingColorSpaceConfig:{unpackColorSpace:"srgb"},outputColorSpaceConfig:{drawingBufferColorSpace:"srgb"}},["srgb"]:{primaries:Q,whitePoint:Z,transfer:"srgb",toXYZ:$K,fromXYZ:ZK,luminanceCoefficients:$,outputColorSpaceConfig:{drawingBufferColorSpace:"srgb"}}}),J}var tJ=pG();function P8(J){return J<0.04045?J*0.0773993808:Math.pow(J*0.9478672986+0.0521327014,2.4)}function s9(J){return J<0.0031308?J*12.92:1.055*Math.pow(J,0.41666)-0.055}var w9;class pZ{static getDataURL(J,Q="image/png"){if(/^data:/i.test(J.src))return J.src;if(typeof HTMLCanvasElement>"u")return J.src;let $;if(J instanceof HTMLCanvasElement)$=J;else{if(w9===void 0)w9=i9("canvas");w9.width=J.width,w9.height=J.height;let Z=w9.getContext("2d");if(J instanceof ImageData)Z.putImageData(J,0,0);else Z.drawImage(J,0,0,J.width,J.height);$=w9}return $.toDataURL(Q)}static sRGBToLinear(J){if(typeof HTMLImageElement<"u"&&J instanceof HTMLImageElement||typeof HTMLCanvasElement<"u"&&J instanceof HTMLCanvasElement||typeof ImageBitmap<"u"&&J instanceof ImageBitmap){let Q=i9("canvas");Q.width=J.width,Q.height=J.height;let $=Q.getContext("2d");$.drawImage(J,0,0,J.width,J.height);let Z=$.getImageData(0,0,J.width,J.height),W=Z.data;for(let K=0;K<W.length;K++)W[K]=P8(W[K]/255)*255;return $.putImageData(Z,0,0),Q}else if(J.data){let Q=J.data.slice(0);for(let $=0;$<Q.length;$++)if(Q instanceof Uint8Array||Q instanceof Uint8ClampedArray)Q[$]=Math.floor(P8(Q[$]/255)*255);else Q[$]=P8(Q[$]);return{data:Q,width:J.width,height:J.height}}else return console.warn("THREE.ImageUtils.sRGBToLinear(): Unsupported image type. No color space conversion applied."),J}}var mG=0;class C8{constructor(J=null){this.isSource=!0,Object.defineProperty(this,"id",{value:mG++}),this.uuid=n0(),this.data=J,this.dataReady=!0,this.version=0}getSize(J){let Q=this.data;if(typeof HTMLVideoElement<"u"&&Q instanceof HTMLVideoElement)J.set(Q.videoWidth,Q.videoHeight,0);else if(Q instanceof VideoFrame)J.set(Q.displayHeight,Q.displayWidth,0);else if(Q!==null)J.set(Q.width,Q.height,Q.depth||0);else J.set(0,0,0);return J}set needsUpdate(J){if(J===!0)this.version++}toJSON(J){let Q=J===void 0||typeof J==="string";if(!Q&&J.images[this.uuid]!==void 0)return J.images[this.uuid];let $={uuid:this.uuid,url:""},Z=this.data;if(Z!==null){let W;if(Array.isArray(Z)){W=[];for(let K=0,H=Z.length;K<H;K++)if(Z[K].isDataTexture)W.push(X$(Z[K].image));else W.push(X$(Z[K]))}else W=X$(Z);$.url=W}if(!Q)J.images[this.uuid]=$;return $}}function X$(J){if(typeof HTMLImageElement<"u"&&J instanceof HTMLImageElement||typeof HTMLCanvasElement<"u"&&J instanceof HTMLCanvasElement||typeof ImageBitmap<"u"&&J instanceof ImageBitmap)return pZ.getDataURL(J);else if(J.data)return{data:Array.from(J.data),width:J.width,height:J.height,type:J.data.constructor.name};else return console.warn("THREE.Texture: Unable to serialize Texture."),{}}var dG=0,U$=new w;class F0 extends H8{constructor(J=F0.DEFAULT_IMAGE,Q=F0.DEFAULT_MAPPING,$=1001,Z=1001,W=1006,K=1008,H=1023,Y=1009,X=F0.DEFAULT_ANISOTROPY,U=""){super();this.isTexture=!0,Object.defineProperty(this,"id",{value:dG++}),this.uuid=n0(),this.name="",this.source=new C8(J),this.mipmaps=[],this.mapping=Q,this.channel=0,this.wrapS=$,this.wrapT=Z,this.magFilter=W,this.minFilter=K,this.anisotropy=X,this.format=H,this.internalFormat=null,this.type=Y,this.offset=new t(0,0),this.repeat=new t(1,1),this.center=new t(0,0),this.rotation=0,this.matrixAutoUpdate=!0,this.matrix=new dJ,this.generateMipmaps=!0,this.premultiplyAlpha=!1,this.flipY=!0,this.unpackAlignment=4,this.colorSpace=U,this.userData={},this.updateRanges=[],this.version=0,this.onUpdate=null,this.renderTarget=null,this.isRenderTargetTexture=!1,this.isArrayTexture=J&&J.depth&&J.depth>1?!0:!1,this.pmremVersion=0}get width(){return this.source.getSize(U$).x}get height(){return this.source.getSize(U$).y}get depth(){return this.source.getSize(U$).z}get image(){return this.source.data}set image(J=null){this.source.data=J}updateMatrix(){this.matrix.setUvTransform(this.offset.x,this.offset.y,this.repeat.x,this.repeat.y,this.rotation,this.center.x,this.center.y)}addUpdateRange(J,Q){this.updateRanges.push({start:J,count:Q})}clearUpdateRanges(){this.updateRanges.length=0}clone(){return new this.constructor().copy(this)}copy(J){return this.name=J.name,this.source=J.source,this.mipmaps=J.mipmaps.slice(0),this.mapping=J.mapping,this.channel=J.channel,this.wrapS=J.wrapS,this.wrapT=J.wrapT,this.magFilter=J.magFilter,this.minFilter=J.minFilter,this.anisotropy=J.anisotropy,this.format=J.format,this.internalFormat=J.internalFormat,this.type=J.type,this.offset.copy(J.offset),this.repeat.copy(J.repeat),this.center.copy(J.center),this.rotation=J.rotation,this.matrixAutoUpdate=J.matrixAutoUpdate,this.matrix.copy(J.matrix),this.generateMipmaps=J.generateMipmaps,this.premultiplyAlpha=J.premultiplyAlpha,this.flipY=J.flipY,this.unpackAlignment=J.unpackAlignment,this.colorSpace=J.colorSpace,this.renderTarget=J.renderTarget,this.isRenderTargetTexture=J.isRenderTargetTexture,this.isArrayTexture=J.isArrayTexture,this.userData=JSON.parse(JSON.stringify(J.userData)),this.needsUpdate=!0,this}setValues(J){for(let Q in J){let $=J[Q];if($===void 0){console.warn(`THREE.Texture.setValues(): parameter '${Q}' has value of undefined.`);continue}let Z=this[Q];if(Z===void 0){console.warn(`THREE.Texture.setValues(): property '${Q}' does not exist.`);continue}if(Z&&$&&(Z.isVector2&&$.isVector2))Z.copy($);else if(Z&&$&&(Z.isVector3&&$.isVector3))Z.copy($);else if(Z&&$&&(Z.isMatrix3&&$.isMatrix3))Z.copy($);else this[Q]=$}}toJSON(J){let Q=J===void 0||typeof J==="string";if(!Q&&J.textures[this.uuid]!==void 0)return J.textures[this.uuid];let $={metadata:{version:4.7,type:"Texture",generator:"Texture.toJSON"},uuid:this.uuid,name:this.name,image:this.source.toJSON(J).uuid,mapping:this.mapping,channel:this.channel,repeat:[this.repeat.x,this.repeat.y],offset:[this.offset.x,this.offset.y],center:[this.center.x,this.center.y],rotation:this.rotation,wrap:[this.wrapS,this.wrapT],format:this.format,internalFormat:this.internalFormat,type:this.type,colorSpace:this.colorSpace,minFilter:this.minFilter,magFilter:this.magFilter,anisotropy:this.anisotropy,flipY:this.flipY,generateMipmaps:this.generateMipmaps,premultiplyAlpha:this.premultiplyAlpha,unpackAlignment:this.unpackAlignment};if(Object.keys(this.userData).length>0)$.userData=this.userData;if(!Q)J.textures[this.uuid]=$;return $}dispose(){this.dispatchEvent({type:"dispose"})}transformUv(J){if(this.mapping!==300)return J;if(J.applyMatrix3(this.matrix),J.x<0||J.x>1)switch(this.wrapS){case 1000:J.x=J.x-Math.floor(J.x);break;case 1001:J.x=J.x<0?0:1;break;case 1002:if(Math.abs(Math.floor(J.x)%2)===1)J.x=Math.ceil(J.x)-J.x;else J.x=J.x-Math.floor(J.x);break}if(J.y<0||J.y>1)switch(this.wrapT){case 1000:J.y=J.y-Math.floor(J.y);break;case 1001:J.y=J.y<0?0:1;break;case 1002:if(Math.abs(Math.floor(J.y)%2)===1)J.y=Math.ceil(J.y)-J.y;else J.y=J.y-Math.floor(J.y);break}if(this.flipY)J.y=1-J.y;return J}set needsUpdate(J){if(J===!0)this.version++,this.source.needsUpdate=!0}set needsPMREMUpdate(J){if(J===!0)this.pmremVersion++}}F0.DEFAULT_IMAGE=null;F0.DEFAULT_MAPPING=300;F0.DEFAULT_ANISOTROPY=1;class J0{constructor(J=0,Q=0,$=0,Z=1){J0.prototype.isVector4=!0,this.x=J,this.y=Q,this.z=$,this.w=Z}get width(){return this.z}set width(J){this.z=J}get height(){return this.w}set height(J){this.w=J}set(J,Q,$,Z){return this.x=J,this.y=Q,this.z=$,this.w=Z,this}setScalar(J){return this.x=J,this.y=J,this.z=J,this.w=J,this}setX(J){return this.x=J,this}setY(J){return this.y=J,this}setZ(J){return this.z=J,this}setW(J){return this.w=J,this}setComponent(J,Q){switch(J){case 0:this.x=Q;break;case 1:this.y=Q;break;case 2:this.z=Q;break;case 3:this.w=Q;break;default:throw Error("index is out of range: "+J)}return this}getComponent(J){switch(J){case 0:return this.x;case 1:return this.y;case 2:return this.z;case 3:return this.w;default:throw Error("index is out of range: "+J)}}clone(){return new this.constructor(this.x,this.y,this.z,this.w)}copy(J){return this.x=J.x,this.y=J.y,this.z=J.z,this.w=J.w!==void 0?J.w:1,this}add(J){return this.x+=J.x,this.y+=J.y,this.z+=J.z,this.w+=J.w,this}addScalar(J){return this.x+=J,this.y+=J,this.z+=J,this.w+=J,this}addVectors(J,Q){return this.x=J.x+Q.x,this.y=J.y+Q.y,this.z=J.z+Q.z,this.w=J.w+Q.w,this}addScaledVector(J,Q){return this.x+=J.x*Q,this.y+=J.y*Q,this.z+=J.z*Q,this.w+=J.w*Q,this}sub(J){return this.x-=J.x,this.y-=J.y,this.z-=J.z,this.w-=J.w,this}subScalar(J){return this.x-=J,this.y-=J,this.z-=J,this.w-=J,this}subVectors(J,Q){return this.x=J.x-Q.x,this.y=J.y-Q.y,this.z=J.z-Q.z,this.w=J.w-Q.w,this}multiply(J){return this.x*=J.x,this.y*=J.y,this.z*=J.z,this.w*=J.w,this}multiplyScalar(J){return this.x*=J,this.y*=J,this.z*=J,this.w*=J,this}applyMatrix4(J){let Q=this.x,$=this.y,Z=this.z,W=this.w,K=J.elements;return this.x=K[0]*Q+K[4]*$+K[8]*Z+K[12]*W,this.y=K[1]*Q+K[5]*$+K[9]*Z+K[13]*W,this.z=K[2]*Q+K[6]*$+K[10]*Z+K[14]*W,this.w=K[3]*Q+K[7]*$+K[11]*Z+K[15]*W,this}divide(J){return this.x/=J.x,this.y/=J.y,this.z/=J.z,this.w/=J.w,this}divideScalar(J){return this.multiplyScalar(1/J)}setAxisAngleFromQuaternion(J){this.w=2*Math.acos(J.w);let Q=Math.sqrt(1-J.w*J.w);if(Q<0.0001)this.x=1,this.y=0,this.z=0;else this.x=J.x/Q,this.y=J.y/Q,this.z=J.z/Q;return this}setAxisAngleFromRotationMatrix(J){let Q,$,Z,W,K=0.01,H=0.1,Y=J.elements,X=Y[0],U=Y[4],G=Y[8],E=Y[1],N=Y[5],q=Y[9],R=Y[2],F=Y[6],O=Y[10];if(Math.abs(U-E)<0.01&&Math.abs(G-R)<0.01&&Math.abs(q-F)<0.01){if(Math.abs(U+E)<0.1&&Math.abs(G+R)<0.1&&Math.abs(q+F)<0.1&&Math.abs(X+N+O-3)<0.1)return this.set(1,0,0,0),this;Q=Math.PI;let k=(X+1)/2,M=(N+1)/2,L=(O+1)/2,A=(U+E)/4,_=(G+R)/4,C=(q+F)/4;if(k>M&&k>L)if(k<0.01)$=0,Z=0.707106781,W=0.707106781;else $=Math.sqrt(k),Z=A/$,W=_/$;else if(M>L)if(M<0.01)$=0.707106781,Z=0,W=0.707106781;else Z=Math.sqrt(M),$=A/Z,W=C/Z;else if(L<0.01)$=0.707106781,Z=0.707106781,W=0;else W=Math.sqrt(L),$=_/W,Z=C/W;return this.set($,Z,W,Q),this}let D=Math.sqrt((F-q)*(F-q)+(G-R)*(G-R)+(E-U)*(E-U));if(Math.abs(D)<0.001)D=1;return this.x=(F-q)/D,this.y=(G-R)/D,this.z=(E-U)/D,this.w=Math.acos((X+N+O-1)/2),this}setFromMatrixPosition(J){let Q=J.elements;return this.x=Q[12],this.y=Q[13],this.z=Q[14],this.w=Q[15],this}min(J){return this.x=Math.min(this.x,J.x),this.y=Math.min(this.y,J.y),this.z=Math.min(this.z,J.z),this.w=Math.min(this.w,J.w),this}max(J){return this.x=Math.max(this.x,J.x),this.y=Math.max(this.y,J.y),this.z=Math.max(this.z,J.z),this.w=Math.max(this.w,J.w),this}clamp(J,Q){return this.x=bJ(this.x,J.x,Q.x),this.y=bJ(this.y,J.y,Q.y),this.z=bJ(this.z,J.z,Q.z),this.w=bJ(this.w,J.w,Q.w),this}clampScalar(J,Q){return this.x=bJ(this.x,J,Q),this.y=bJ(this.y,J,Q),this.z=bJ(this.z,J,Q),this.w=bJ(this.w,J,Q),this}clampLength(J,Q){let $=this.length();return this.divideScalar($||1).multiplyScalar(bJ($,J,Q))}floor(){return this.x=Math.floor(this.x),this.y=Math.floor(this.y),this.z=Math.floor(this.z),this.w=Math.floor(this.w),this}ceil(){return this.x=Math.ceil(this.x),this.y=Math.ceil(this.y),this.z=Math.ceil(this.z),this.w=Math.ceil(this.w),this}round(){return this.x=Math.round(this.x),this.y=Math.round(this.y),this.z=Math.round(this.z),this.w=Math.round(this.w),this}roundToZero(){return this.x=Math.trunc(this.x),this.y=Math.trunc(this.y),this.z=Math.trunc(this.z),this.w=Math.trunc(this.w),this}negate(){return this.x=-this.x,this.y=-this.y,this.z=-this.z,this.w=-this.w,this}dot(J){return this.x*J.x+this.y*J.y+this.z*J.z+this.w*J.w}lengthSq(){return this.x*this.x+this.y*this.y+this.z*this.z+this.w*this.w}length(){return Math.sqrt(this.x*this.x+this.y*this.y+this.z*this.z+this.w*this.w)}manhattanLength(){return Math.abs(this.x)+Math.abs(this.y)+Math.abs(this.z)+Math.abs(this.w)}normalize(){return this.divideScalar(this.length()||1)}setLength(J){return this.normalize().multiplyScalar(J)}lerp(J,Q){return this.x+=(J.x-this.x)*Q,this.y+=(J.y-this.y)*Q,this.z+=(J.z-this.z)*Q,this.w+=(J.w-this.w)*Q,this}lerpVectors(J,Q,$){return this.x=J.x+(Q.x-J.x)*$,this.y=J.y+(Q.y-J.y)*$,this.z=J.z+(Q.z-J.z)*$,this.w=J.w+(Q.w-J.w)*$,this}equals(J){return J.x===this.x&&J.y===this.y&&J.z===this.z&&J.w===this.w}fromArray(J,Q=0){return this.x=J[Q],this.y=J[Q+1],this.z=J[Q+2],this.w=J[Q+3],this}toArray(J=[],Q=0){return J[Q]=this.x,J[Q+1]=this.y,J[Q+2]=this.z,J[Q+3]=this.w,J}fromBufferAttribute(J,Q){return this.x=J.getX(Q),this.y=J.getY(Q),this.z=J.getZ(Q),this.w=J.getW(Q),this}random(){return this.x=Math.random(),this.y=Math.random(),this.z=Math.random(),this.w=Math.random(),this}*[Symbol.iterator](){yield this.x,yield this.y,yield this.z,yield this.w}}class OQ extends H8{constructor(J=1,Q=1,$={}){super();$=Object.assign({generateMipmaps:!1,internalFormat:null,minFilter:1006,depthBuffer:!0,stencilBuffer:!1,resolveDepthBuffer:!0,resolveStencilBuffer:!0,depthTexture:null,samples:0,count:1,depth:1,multiview:!1},$),this.isRenderTarget=!0,this.width=J,this.height=Q,this.depth=$.depth,this.scissor=new J0(0,0,J,Q),this.scissorTest=!1,this.viewport=new J0(0,0,J,Q);let Z={width:J,height:Q,depth:$.depth},W=new F0(Z);this.textures=[];let K=$.count;for(let H=0;H<K;H++)this.textures[H]=W.clone(),this.textures[H].isRenderTargetTexture=!0,this.textures[H].renderTarget=this;this._setTextureOptions($),this.depthBuffer=$.depthBuffer,this.stencilBuffer=$.stencilBuffer,this.resolveDepthBuffer=$.resolveDepthBuffer,this.resolveStencilBuffer=$.resolveStencilBuffer,this._depthTexture=null,this.depthTexture=$.depthTexture,this.samples=$.samples,this.multiview=$.multiview}_setTextureOptions(J={}){let Q={minFilter:1006,generateMipmaps:!1,flipY:!1,internalFormat:null};if(J.mapping!==void 0)Q.mapping=J.mapping;if(J.wrapS!==void 0)Q.wrapS=J.wrapS;if(J.wrapT!==void 0)Q.wrapT=J.wrapT;if(J.wrapR!==void 0)Q.wrapR=J.wrapR;if(J.magFilter!==void 0)Q.magFilter=J.magFilter;if(J.minFilter!==void 0)Q.minFilter=J.minFilter;if(J.format!==void 0)Q.format=J.format;if(J.type!==void 0)Q.type=J.type;if(J.anisotropy!==void 0)Q.anisotropy=J.anisotropy;if(J.colorSpace!==void 0)Q.colorSpace=J.colorSpace;if(J.flipY!==void 0)Q.flipY=J.flipY;if(J.generateMipmaps!==void 0)Q.generateMipmaps=J.generateMipmaps;if(J.internalFormat!==void 0)Q.internalFormat=J.internalFormat;for(let $=0;$<this.textures.length;$++)this.textures[$].setValues(Q)}get texture(){return this.textures[0]}set texture(J){this.textures[0]=J}set depthTexture(J){if(this._depthTexture!==null)this._depthTexture.renderTarget=null;if(J!==null)J.renderTarget=this;this._depthTexture=J}get depthTexture(){return this._depthTexture}setSize(J,Q,$=1){if(this.width!==J||this.height!==Q||this.depth!==$){this.width=J,this.height=Q,this.depth=$;for(let Z=0,W=this.textures.length;Z<W;Z++)this.textures[Z].image.width=J,this.textures[Z].image.height=Q,this.textures[Z].image.depth=$,this.textures[Z].isArrayTexture=this.textures[Z].image.depth>1;this.dispose()}this.viewport.set(0,0,J,Q),this.scissor.set(0,0,J,Q)}clone(){return new this.constructor().copy(this)}copy(J){this.width=J.width,this.height=J.height,this.depth=J.depth,this.scissor.copy(J.scissor),this.scissorTest=J.scissorTest,this.viewport.copy(J.viewport),this.textures.length=0;for(let Q=0,$=J.textures.length;Q<$;Q++){this.textures[Q]=J.textures[Q].clone(),this.textures[Q].isRenderTargetTexture=!0,this.textures[Q].renderTarget=this;let Z=Object.assign({},J.textures[Q].image);this.textures[Q].source=new C8(Z)}if(this.depthBuffer=J.depthBuffer,this.stencilBuffer=J.stencilBuffer,this.resolveDepthBuffer=J.resolveDepthBuffer,this.resolveStencilBuffer=J.resolveStencilBuffer,J.depthTexture!==null)this.depthTexture=J.depthTexture.clone();return this.samples=J.samples,this}dispose(){this.dispatchEvent({type:"dispose"})}}class Y8 extends OQ{constructor(J=1,Q=1,$={}){super(J,Q,$);this.isWebGLRenderTarget=!0}}class c6 extends F0{constructor(J=null,Q=1,$=1,Z=1){super(null);this.isDataArrayTexture=!0,this.image={data:J,width:Q,height:$,depth:Z},this.magFilter=1003,this.minFilter=1003,this.wrapR=1001,this.generateMipmaps=!1,this.flipY=!1,this.unpackAlignment=1,this.layerUpdates=new Set}addLayerUpdate(J){this.layerUpdates.add(J)}clearLayerUpdates(){this.layerUpdates.clear()}}class EY extends Y8{constructor(J=1,Q=1,$=1,Z={}){super(J,Q,Z);this.isWebGLArrayRenderTarget=!0,this.depth=$,this.texture=new c6(null,J,Q,$),this._setTextureOptions(Z),this.texture.isRenderTargetTexture=!0}}class n6 extends F0{constructor(J=null,Q=1,$=1,Z=1){super(null);this.isData3DTexture=!0,this.image={data:J,width:Q,height:$,depth:Z},this.magFilter=1003,this.minFilter=1003,this.wrapR=1001,this.generateMipmaps=!1,this.flipY=!1,this.unpackAlignment=1}}class NY extends Y8{constructor(J=1,Q=1,$=1,Z={}){super(J,Q,Z);this.isWebGL3DRenderTarget=!0,this.depth=$,this.texture=new n6(null,J,Q,$),this._setTextureOptions(Z),this.texture.isRenderTargetTexture=!0}}class w0{constructor(J=new w(1/0,1/0,1/0),Q=new w(-1/0,-1/0,-1/0)){this.isBox3=!0,this.min=J,this.max=Q}set(J,Q){return this.min.copy(J),this.max.copy(Q),this}setFromArray(J){this.makeEmpty();for(let Q=0,$=J.length;Q<$;Q+=3)this.expandByPoint(Q8.fromArray(J,Q));return this}setFromBufferAttribute(J){this.makeEmpty();for(let Q=0,$=J.count;Q<$;Q++)this.expandByPoint(Q8.fromBufferAttribute(J,Q));return this}setFromPoints(J){this.makeEmpty();for(let Q=0,$=J.length;Q<$;Q++)this.expandByPoint(J[Q]);return this}setFromCenterAndSize(J,Q){let $=Q8.copy(Q).multiplyScalar(0.5);return this.min.copy(J).sub($),this.max.copy(J).add($),this}setFromObject(J,Q=!1){return this.makeEmpty(),this.expandByObject(J,Q)}clone(){return new this.constructor().copy(this)}copy(J){return this.min.copy(J.min),this.max.copy(J.max),this}makeEmpty(){return this.min.x=this.min.y=this.min.z=1/0,this.max.x=this.max.y=this.max.z=-1/0,this}isEmpty(){return this.max.x<this.min.x||this.max.y<this.min.y||this.max.z<this.min.z}getCenter(J){return this.isEmpty()?J.set(0,0,0):J.addVectors(this.min,this.max).multiplyScalar(0.5)}getSize(J){return this.isEmpty()?J.set(0,0,0):J.subVectors(this.max,this.min)}expandByPoint(J){return this.min.min(J),this.max.max(J),this}expandByVector(J){return this.min.sub(J),this.max.add(J),this}expandByScalar(J){return this.min.addScalar(-J),this.max.addScalar(J),this}expandByObject(J,Q=!1){J.updateWorldMatrix(!1,!1);let $=J.geometry;if($!==void 0){let W=$.getAttribute("position");if(Q===!0&&W!==void 0&&J.isInstancedMesh!==!0)for(let K=0,H=W.count;K<H;K++){if(J.isMesh===!0)J.getVertexPosition(K,Q8);else Q8.fromBufferAttribute(W,K);Q8.applyMatrix4(J.matrixWorld),this.expandByPoint(Q8)}else{if(J.boundingBox!==void 0){if(J.boundingBox===null)J.computeBoundingBox();X7.copy(J.boundingBox)}else{if($.boundingBox===null)$.computeBoundingBox();X7.copy($.boundingBox)}X7.applyMatrix4(J.matrixWorld),this.union(X7)}}let Z=J.children;for(let W=0,K=Z.length;W<K;W++)this.expandByObject(Z[W],Q);return this}containsPoint(J){return J.x>=this.min.x&&J.x<=this.max.x&&J.y>=this.min.y&&J.y<=this.max.y&&J.z>=this.min.z&&J.z<=this.max.z}containsBox(J){return this.min.x<=J.min.x&&J.max.x<=this.max.x&&this.min.y<=J.min.y&&J.max.y<=this.max.y&&this.min.z<=J.min.z&&J.max.z<=this.max.z}getParameter(J,Q){return Q.set((J.x-this.min.x)/(this.max.x-this.min.x),(J.y-this.min.y)/(this.max.y-this.min.y),(J.z-this.min.z)/(this.max.z-this.min.z))}intersectsBox(J){return J.max.x>=this.min.x&&J.min.x<=this.max.x&&J.max.y>=this.min.y&&J.min.y<=this.max.y&&J.max.z>=this.min.z&&J.min.z<=this.max.z}intersectsSphere(J){return this.clampPoint(J.center,Q8),Q8.distanceToSquared(J.center)<=J.radius*J.radius}intersectsPlane(J){let Q,$;if(J.normal.x>0)Q=J.normal.x*this.min.x,$=J.normal.x*this.max.x;else Q=J.normal.x*this.max.x,$=J.normal.x*this.min.x;if(J.normal.y>0)Q+=J.normal.y*this.min.y,$+=J.normal.y*this.max.y;else Q+=J.normal.y*this.max.y,$+=J.normal.y*this.min.y;if(J.normal.z>0)Q+=J.normal.z*this.min.z,$+=J.normal.z*this.max.z;else Q+=J.normal.z*this.max.z,$+=J.normal.z*this.min.z;return Q<=-J.constant&&$>=-J.constant}intersectsTriangle(J){if(this.isEmpty())return!1;this.getCenter(R6),U7.subVectors(this.max,R6),C9.subVectors(J.a,R6),P9.subVectors(J.b,R6),A9.subVectors(J.c,R6),y8.subVectors(P9,C9),v8.subVectors(A9,P9),o8.subVectors(C9,A9);let Q=[0,-y8.z,y8.y,0,-v8.z,v8.y,0,-o8.z,o8.y,y8.z,0,-y8.x,v8.z,0,-v8.x,o8.z,0,-o8.x,-y8.y,y8.x,0,-v8.y,v8.x,0,-o8.y,o8.x,0];if(!G$(Q,C9,P9,A9,U7))return!1;if(Q=[1,0,0,0,1,0,0,0,1],!G$(Q,C9,P9,A9,U7))return!1;return G7.crossVectors(y8,v8),Q=[G7.x,G7.y,G7.z],G$(Q,C9,P9,A9,U7)}clampPoint(J,Q){return Q.copy(J).clamp(this.min,this.max)}distanceToPoint(J){return this.clampPoint(J,Q8).distanceTo(J)}getBoundingSphere(J){if(this.isEmpty())J.makeEmpty();else this.getCenter(J.center),J.radius=this.getSize(Q8).length()*0.5;return J}intersect(J){if(this.min.max(J.min),this.max.min(J.max),this.isEmpty())this.makeEmpty();return this}union(J){return this.min.min(J.min),this.max.max(J.max),this}applyMatrix4(J){if(this.isEmpty())return this;return k8[0].set(this.min.x,this.min.y,this.min.z).applyMatrix4(J),k8[1].set(this.min.x,this.min.y,this.max.z).applyMatrix4(J),k8[2].set(this.min.x,this.max.y,this.min.z).applyMatrix4(J),k8[3].set(this.min.x,this.max.y,this.max.z).applyMatrix4(J),k8[4].set(this.max.x,this.min.y,this.min.z).applyMatrix4(J),k8[5].set(this.max.x,this.min.y,this.max.z).applyMatrix4(J),k8[6].set(this.max.x,this.max.y,this.min.z).applyMatrix4(J),k8[7].set(this.max.x,this.max.y,this.max.z).applyMatrix4(J),this.setFromPoints(k8),this}translate(J){return this.min.add(J),this.max.add(J),this}equals(J){return J.min.equals(this.min)&&J.max.equals(this.max)}toJSON(){return{min:this.min.toArray(),max:this.max.toArray()}}fromJSON(J){return this.min.fromArray(J.min),this.max.fromArray(J.max),this}}var k8=[new w,new w,new w,new w,new w,new w,new w,new w],Q8=new w,X7=new w0,C9=new w,P9=new w,A9=new w,y8=new w,v8=new w,o8=new w,R6=new w,U7=new w,G7=new w,a8=new w;function G$(J,Q,$,Z,W){for(let K=0,H=J.length-3;K<=H;K+=3){a8.fromArray(J,K);let Y=W.x*Math.abs(a8.x)+W.y*Math.abs(a8.y)+W.z*Math.abs(a8.z),X=Q.dot(a8),U=$.dot(a8),G=Z.dot(a8);if(Math.max(-Math.max(X,U,G),Math.min(X,U,G))>Y)return!1}return!0}var lG=new w0,F6=new w,E$=new w;class _0{constructor(J=new w,Q=-1){this.isSphere=!0,this.center=J,this.radius=Q}set(J,Q){return this.center.copy(J),this.radius=Q,this}setFromPoints(J,Q){let $=this.center;if(Q!==void 0)$.copy(Q);else lG.setFromPoints(J).getCenter($);let Z=0;for(let W=0,K=J.length;W<K;W++)Z=Math.max(Z,$.distanceToSquared(J[W]));return this.radius=Math.sqrt(Z),this}copy(J){return this.center.copy(J.center),this.radius=J.radius,this}isEmpty(){return this.radius<0}makeEmpty(){return this.center.set(0,0,0),this.radius=-1,this}containsPoint(J){return J.distanceToSquared(this.center)<=this.radius*this.radius}distanceToPoint(J){return J.distanceTo(this.center)-this.radius}intersectsSphere(J){let Q=this.radius+J.radius;return J.center.distanceToSquared(this.center)<=Q*Q}intersectsBox(J){return J.intersectsSphere(this)}intersectsPlane(J){return Math.abs(J.distanceToPoint(this.center))<=this.radius}clampPoint(J,Q){let $=this.center.distanceToSquared(J);if(Q.copy(J),$>this.radius*this.radius)Q.sub(this.center).normalize(),Q.multiplyScalar(this.radius).add(this.center);return Q}getBoundingBox(J){if(this.isEmpty())return J.makeEmpty(),J;return J.set(this.center,this.center),J.expandByScalar(this.radius),J}applyMatrix4(J){return this.center.applyMatrix4(J),this.radius=this.radius*J.getMaxScaleOnAxis(),this}translate(J){return this.center.add(J),this}expandByPoint(J){if(this.isEmpty())return this.center.copy(J),this.radius=0,this;F6.subVectors(J,this.center);let Q=F6.lengthSq();if(Q>this.radius*this.radius){let $=Math.sqrt(Q),Z=($-this.radius)*0.5;this.center.addScaledVector(F6,Z/$),this.radius+=Z}return this}union(J){if(J.isEmpty())return this;if(this.isEmpty())return this.copy(J),this;if(this.center.equals(J.center)===!0)this.radius=Math.max(this.radius,J.radius);else E$.subVectors(J.center,this.center).setLength(J.radius),this.expandByPoint(F6.copy(J.center).add(E$)),this.expandByPoint(F6.copy(J.center).sub(E$));return this}equals(J){return J.center.equals(this.center)&&J.radius===this.radius}clone(){return new this.constructor().copy(this)}toJSON(){return{radius:this.radius,center:this.center.toArray()}}fromJSON(J){return this.radius=J.radius,this.center.fromArray(J.center),this}}var V8=new w,N$=new w,E7=new w,f8=new w,q$=new w,N7=new w,D$=new w;class F9{constructor(J=new w,Q=new w(0,0,-1)){this.origin=J,this.direction=Q}set(J,Q){return this.origin.copy(J),this.direction.copy(Q),this}copy(J){return this.origin.copy(J.origin),this.direction.copy(J.direction),this}at(J,Q){return Q.copy(this.origin).addScaledVector(this.direction,J)}lookAt(J){return this.direction.copy(J).sub(this.origin).normalize(),this}recast(J){return this.origin.copy(this.at(J,V8)),this}closestPointToPoint(J,Q){Q.subVectors(J,this.origin);let $=Q.dot(this.direction);if($<0)return Q.copy(this.origin);return Q.copy(this.origin).addScaledVector(this.direction,$)}distanceToPoint(J){return Math.sqrt(this.distanceSqToPoint(J))}distanceSqToPoint(J){let Q=V8.subVectors(J,this.origin).dot(this.direction);if(Q<0)return this.origin.distanceToSquared(J);return V8.copy(this.origin).addScaledVector(this.direction,Q),V8.distanceToSquared(J)}distanceSqToSegment(J,Q,$,Z){N$.copy(J).add(Q).multiplyScalar(0.5),E7.copy(Q).sub(J).normalize(),f8.copy(this.origin).sub(N$);let W=J.distanceTo(Q)*0.5,K=-this.direction.dot(E7),H=f8.dot(this.direction),Y=-f8.dot(E7),X=f8.lengthSq(),U=Math.abs(1-K*K),G,E,N,q;if(U>0)if(G=K*Y-H,E=K*H-Y,q=W*U,G>=0)if(E>=-q)if(E<=q){let R=1/U;G*=R,E*=R,N=G*(G+K*E+2*H)+E*(K*G+E+2*Y)+X}else E=W,G=Math.max(0,-(K*E+H)),N=-G*G+E*(E+2*Y)+X;else E=-W,G=Math.max(0,-(K*E+H)),N=-G*G+E*(E+2*Y)+X;else if(E<=-q)G=Math.max(0,-(-K*W+H)),E=G>0?-W:Math.min(Math.max(-W,-Y),W),N=-G*G+E*(E+2*Y)+X;else if(E<=q)G=0,E=Math.min(Math.max(-W,-Y),W),N=E*(E+2*Y)+X;else G=Math.max(0,-(K*W+H)),E=G>0?W:Math.min(Math.max(-W,-Y),W),N=-G*G+E*(E+2*Y)+X;else E=K>0?-W:W,G=Math.max(0,-(K*E+H)),N=-G*G+E*(E+2*Y)+X;if($)$.copy(this.origin).addScaledVector(this.direction,G);if(Z)Z.copy(N$).addScaledVector(E7,E);return N}intersectSphere(J,Q){V8.subVectors(J.center,this.origin);let $=V8.dot(this.direction),Z=V8.dot(V8)-$*$,W=J.radius*J.radius;if(Z>W)return null;let K=Math.sqrt(W-Z),H=$-K,Y=$+K;if(Y<0)return null;if(H<0)return this.at(Y,Q);return this.at(H,Q)}intersectsSphere(J){if(J.radius<0)return!1;return this.distanceSqToPoint(J.center)<=J.radius*J.radius}distanceToPlane(J){let Q=J.normal.dot(this.direction);if(Q===0){if(J.distanceToPoint(this.origin)===0)return 0;return null}let $=-(this.origin.dot(J.normal)+J.constant)/Q;return $>=0?$:null}intersectPlane(J,Q){let $=this.distanceToPlane(J);if($===null)return null;return this.at($,Q)}intersectsPlane(J){let Q=J.distanceToPoint(this.origin);if(Q===0)return!0;if(J.normal.dot(this.direction)*Q<0)return!0;return!1}intersectBox(J,Q){let $,Z,W,K,H,Y,X=1/this.direction.x,U=1/this.direction.y,G=1/this.direction.z,E=this.origin;if(X>=0)$=(J.min.x-E.x)*X,Z=(J.max.x-E.x)*X;else $=(J.max.x-E.x)*X,Z=(J.min.x-E.x)*X;if(U>=0)W=(J.min.y-E.y)*U,K=(J.max.y-E.y)*U;else W=(J.max.y-E.y)*U,K=(J.min.y-E.y)*U;if($>K||W>Z)return null;if(W>$||isNaN($))$=W;if(K<Z||isNaN(Z))Z=K;if(G>=0)H=(J.min.z-E.z)*G,Y=(J.max.z-E.z)*G;else H=(J.max.z-E.z)*G,Y=(J.min.z-E.z)*G;if($>Y||H>Z)return null;if(H>$||$!==$)$=H;if(Y<Z||Z!==Z)Z=Y;if(Z<0)return null;return this.at($>=0?$:Z,Q)}intersectsBox(J){return this.intersectBox(J,V8)!==null}intersectTriangle(J,Q,$,Z,W){q$.subVectors(Q,J),N7.subVectors($,J),D$.crossVectors(q$,N7);let K=this.direction.dot(D$),H;if(K>0){if(Z)return null;H=1}else if(K<0)H=-1,K=-K;else return null;f8.subVectors(this.origin,J);let Y=H*this.direction.dot(N7.crossVectors(f8,N7));if(Y<0)return null;let X=H*this.direction.dot(q$.cross(f8));if(X<0)return null;if(Y+X>K)return null;let U=-H*f8.dot(D$);if(U<0)return null;return this.at(U/K,W)}applyMatrix4(J){return this.origin.applyMatrix4(J),this.direction.transformDirection(J),this}equals(J){return J.origin.equals(this.origin)&&J.direction.equals(this.direction)}clone(){return new this.constructor().copy(this)}}class hJ{constructor(J,Q,$,Z,W,K,H,Y,X,U,G,E,N,q,R,F){if(hJ.prototype.isMatrix4=!0,this.elements=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],J!==void 0)this.set(J,Q,$,Z,W,K,H,Y,X,U,G,E,N,q,R,F)}set(J,Q,$,Z,W,K,H,Y,X,U,G,E,N,q,R,F){let O=this.elements;return O[0]=J,O[4]=Q,O[8]=$,O[12]=Z,O[1]=W,O[5]=K,O[9]=H,O[13]=Y,O[2]=X,O[6]=U,O[10]=G,O[14]=E,O[3]=N,O[7]=q,O[11]=R,O[15]=F,this}identity(){return this.set(1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1),this}clone(){return new hJ().fromArray(this.elements)}copy(J){let Q=this.elements,$=J.elements;return Q[0]=$[0],Q[1]=$[1],Q[2]=$[2],Q[3]=$[3],Q[4]=$[4],Q[5]=$[5],Q[6]=$[6],Q[7]=$[7],Q[8]=$[8],Q[9]=$[9],Q[10]=$[10],Q[11]=$[11],Q[12]=$[12],Q[13]=$[13],Q[14]=$[14],Q[15]=$[15],this}copyPosition(J){let Q=this.elements,$=J.elements;return Q[12]=$[12],Q[13]=$[13],Q[14]=$[14],this}setFromMatrix3(J){let Q=J.elements;return this.set(Q[0],Q[3],Q[6],0,Q[1],Q[4],Q[7],0,Q[2],Q[5],Q[8],0,0,0,0,1),this}extractBasis(J,Q,$){return J.setFromMatrixColumn(this,0),Q.setFromMatrixColumn(this,1),$.setFromMatrixColumn(this,2),this}makeBasis(J,Q,$){return this.set(J.x,Q.x,$.x,0,J.y,Q.y,$.y,0,J.z,Q.z,$.z,0,0,0,0,1),this}extractRotation(J){let Q=this.elements,$=J.elements,Z=1/T9.setFromMatrixColumn(J,0).length(),W=1/T9.setFromMatrixColumn(J,1).length(),K=1/T9.setFromMatrixColumn(J,2).length();return Q[0]=$[0]*Z,Q[1]=$[1]*Z,Q[2]=$[2]*Z,Q[3]=0,Q[4]=$[4]*W,Q[5]=$[5]*W,Q[6]=$[6]*W,Q[7]=0,Q[8]=$[8]*K,Q[9]=$[9]*K,Q[10]=$[10]*K,Q[11]=0,Q[12]=0,Q[13]=0,Q[14]=0,Q[15]=1,this}makeRotationFromEuler(J){let Q=this.elements,$=J.x,Z=J.y,W=J.z,K=Math.cos($),H=Math.sin($),Y=Math.cos(Z),X=Math.sin(Z),U=Math.cos(W),G=Math.sin(W);if(J.order==="XYZ"){let E=K*U,N=K*G,q=H*U,R=H*G;Q[0]=Y*U,Q[4]=-Y*G,Q[8]=X,Q[1]=N+q*X,Q[5]=E-R*X,Q[9]=-H*Y,Q[2]=R-E*X,Q[6]=q+N*X,Q[10]=K*Y}else if(J.order==="YXZ"){let E=Y*U,N=Y*G,q=X*U,R=X*G;Q[0]=E+R*H,Q[4]=q*H-N,Q[8]=K*X,Q[1]=K*G,Q[5]=K*U,Q[9]=-H,Q[2]=N*H-q,Q[6]=R+E*H,Q[10]=K*Y}else if(J.order==="ZXY"){let E=Y*U,N=Y*G,q=X*U,R=X*G;Q[0]=E-R*H,Q[4]=-K*G,Q[8]=q+N*H,Q[1]=N+q*H,Q[5]=K*U,Q[9]=R-E*H,Q[2]=-K*X,Q[6]=H,Q[10]=K*Y}else if(J.order==="ZYX"){let E=K*U,N=K*G,q=H*U,R=H*G;Q[0]=Y*U,Q[4]=q*X-N,Q[8]=E*X+R,Q[1]=Y*G,Q[5]=R*X+E,Q[9]=N*X-q,Q[2]=-X,Q[6]=H*Y,Q[10]=K*Y}else if(J.order==="YZX"){let E=K*Y,N=K*X,q=H*Y,R=H*X;Q[0]=Y*U,Q[4]=R-E*G,Q[8]=q*G+N,Q[1]=G,Q[5]=K*U,Q[9]=-H*U,Q[2]=-X*U,Q[6]=N*G+q,Q[10]=E-R*G}else if(J.order==="XZY"){let E=K*Y,N=K*X,q=H*Y,R=H*X;Q[0]=Y*U,Q[4]=-G,Q[8]=X*U,Q[1]=E*G+R,Q[5]=K*U,Q[9]=N*G-q,Q[2]=q*G-N,Q[6]=H*U,Q[10]=R*G+E}return Q[3]=0,Q[7]=0,Q[11]=0,Q[12]=0,Q[13]=0,Q[14]=0,Q[15]=1,this}makeRotationFromQuaternion(J){return this.compose(uG,J,cG)}lookAt(J,Q,$){let Z=this.elements;if(u0.subVectors(J,Q),u0.lengthSq()===0)u0.z=1;if(u0.normalize(),b8.crossVectors($,u0),b8.lengthSq()===0){if(Math.abs($.z)===1)u0.x+=0.0001;else u0.z+=0.0001;u0.normalize(),b8.crossVectors($,u0)}return b8.normalize(),q7.crossVectors(u0,b8),Z[0]=b8.x,Z[4]=q7.x,Z[8]=u0.x,Z[1]=b8.y,Z[5]=q7.y,Z[9]=u0.y,Z[2]=b8.z,Z[6]=q7.z,Z[10]=u0.z,this}multiply(J){return this.multiplyMatrices(this,J)}premultiply(J){return this.multiplyMatrices(J,this)}multiplyMatrices(J,Q){let $=J.elements,Z=Q.elements,W=this.elements,K=$[0],H=$[4],Y=$[8],X=$[12],U=$[1],G=$[5],E=$[9],N=$[13],q=$[2],R=$[6],F=$[10],O=$[14],D=$[3],k=$[7],M=$[11],L=$[15],A=Z[0],_=Z[4],C=Z[8],y=Z[12],z=Z[1],I=Z[5],S=Z[9],p=Z[13],d=Z[2],x=Z[6],o=Z[10],l=Z[14],QJ=Z[3],m=Z[7],EJ=Z[11],NJ=Z[15];return W[0]=K*A+H*z+Y*d+X*QJ,W[4]=K*_+H*I+Y*x+X*m,W[8]=K*C+H*S+Y*o+X*EJ,W[12]=K*y+H*p+Y*l+X*NJ,W[1]=U*A+G*z+E*d+N*QJ,W[5]=U*_+G*I+E*x+N*m,W[9]=U*C+G*S+E*o+N*EJ,W[13]=U*y+G*p+E*l+N*NJ,W[2]=q*A+R*z+F*d+O*QJ,W[6]=q*_+R*I+F*x+O*m,W[10]=q*C+R*S+F*o+O*EJ,W[14]=q*y+R*p+F*l+O*NJ,W[3]=D*A+k*z+M*d+L*QJ,W[7]=D*_+k*I+M*x+L*m,W[11]=D*C+k*S+M*o+L*EJ,W[15]=D*y+k*p+M*l+L*NJ,this}multiplyScalar(J){let Q=this.elements;return Q[0]*=J,Q[4]*=J,Q[8]*=J,Q[12]*=J,Q[1]*=J,Q[5]*=J,Q[9]*=J,Q[13]*=J,Q[2]*=J,Q[6]*=J,Q[10]*=J,Q[14]*=J,Q[3]*=J,Q[7]*=J,Q[11]*=J,Q[15]*=J,this}determinant(){let J=this.elements,Q=J[0],$=J[4],Z=J[8],W=J[12],K=J[1],H=J[5],Y=J[9],X=J[13],U=J[2],G=J[6],E=J[10],N=J[14],q=J[3],R=J[7],F=J[11],O=J[15];return q*(+W*Y*G-Z*X*G-W*H*E+$*X*E+Z*H*N-$*Y*N)+R*(+Q*Y*N-Q*X*E+W*K*E-Z*K*N+Z*X*U-W*Y*U)+F*(+Q*X*G-Q*H*N-W*K*G+$*K*N+W*H*U-$*X*U)+O*(-Z*H*U-Q*Y*G+Q*H*E+Z*K*G-$*K*E+$*Y*U)}transpose(){let J=this.elements,Q;return Q=J[1],J[1]=J[4],J[4]=Q,Q=J[2],J[2]=J[8],J[8]=Q,Q=J[6],J[6]=J[9],J[9]=Q,Q=J[3],J[3]=J[12],J[12]=Q,Q=J[7],J[7]=J[13],J[13]=Q,Q=J[11],J[11]=J[14],J[14]=Q,this}setPosition(J,Q,$){let Z=this.elements;if(J.isVector3)Z[12]=J.x,Z[13]=J.y,Z[14]=J.z;else Z[12]=J,Z[13]=Q,Z[14]=$;return this}invert(){let J=this.elements,Q=J[0],$=J[1],Z=J[2],W=J[3],K=J[4],H=J[5],Y=J[6],X=J[7],U=J[8],G=J[9],E=J[10],N=J[11],q=J[12],R=J[13],F=J[14],O=J[15],D=G*F*X-R*E*X+R*Y*N-H*F*N-G*Y*O+H*E*O,k=q*E*X-U*F*X-q*Y*N+K*F*N+U*Y*O-K*E*O,M=U*R*X-q*G*X+q*H*N-K*R*N-U*H*O+K*G*O,L=q*G*Y-U*R*Y-q*H*E+K*R*E+U*H*F-K*G*F,A=Q*D+$*k+Z*M+W*L;if(A===0)return this.set(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);let _=1/A;return J[0]=D*_,J[1]=(R*E*W-G*F*W-R*Z*N+$*F*N+G*Z*O-$*E*O)*_,J[2]=(H*F*W-R*Y*W+R*Z*X-$*F*X-H*Z*O+$*Y*O)*_,J[3]=(G*Y*W-H*E*W-G*Z*X+$*E*X+H*Z*N-$*Y*N)*_,J[4]=k*_,J[5]=(U*F*W-q*E*W+q*Z*N-Q*F*N-U*Z*O+Q*E*O)*_,J[6]=(q*Y*W-K*F*W-q*Z*X+Q*F*X+K*Z*O-Q*Y*O)*_,J[7]=(K*E*W-U*Y*W+U*Z*X-Q*E*X-K*Z*N+Q*Y*N)*_,J[8]=M*_,J[9]=(q*G*W-U*R*W-q*$*N+Q*R*N+U*$*O-Q*G*O)*_,J[10]=(K*R*W-q*H*W+q*$*X-Q*R*X-K*$*O+Q*H*O)*_,J[11]=(U*H*W-K*G*W-U*$*X+Q*G*X+K*$*N-Q*H*N)*_,J[12]=L*_,J[13]=(U*R*Z-q*G*Z+q*$*E-Q*R*E-U*$*F+Q*G*F)*_,J[14]=(q*H*Z-K*R*Z-q*$*Y+Q*R*Y+K*$*F-Q*H*F)*_,J[15]=(K*G*Z-U*H*Z+U*$*Y-Q*G*Y-K*$*E+Q*H*E)*_,this}scale(J){let Q=this.elements,$=J.x,Z=J.y,W=J.z;return Q[0]*=$,Q[4]*=Z,Q[8]*=W,Q[1]*=$,Q[5]*=Z,Q[9]*=W,Q[2]*=$,Q[6]*=Z,Q[10]*=W,Q[3]*=$,Q[7]*=Z,Q[11]*=W,this}getMaxScaleOnAxis(){let J=this.elements,Q=J[0]*J[0]+J[1]*J[1]+J[2]*J[2],$=J[4]*J[4]+J[5]*J[5]+J[6]*J[6],Z=J[8]*J[8]+J[9]*J[9]+J[10]*J[10];return Math.sqrt(Math.max(Q,$,Z))}makeTranslation(J,Q,$){if(J.isVector3)this.set(1,0,0,J.x,0,1,0,J.y,0,0,1,J.z,0,0,0,1);else this.set(1,0,0,J,0,1,0,Q,0,0,1,$,0,0,0,1);return this}makeRotationX(J){let Q=Math.cos(J),$=Math.sin(J);return this.set(1,0,0,0,0,Q,-$,0,0,$,Q,0,0,0,0,1),this}makeRotationY(J){let Q=Math.cos(J),$=Math.sin(J);return this.set(Q,0,$,0,0,1,0,0,-$,0,Q,0,0,0,0,1),this}makeRotationZ(J){let Q=Math.cos(J),$=Math.sin(J);return this.set(Q,-$,0,0,$,Q,0,0,0,0,1,0,0,0,0,1),this}makeRotationAxis(J,Q){let $=Math.cos(Q),Z=Math.sin(Q),W=1-$,K=J.x,H=J.y,Y=J.z,X=W*K,U=W*H;return this.set(X*K+$,X*H-Z*Y,X*Y+Z*H,0,X*H+Z*Y,U*H+$,U*Y-Z*K,0,X*Y-Z*H,U*Y+Z*K,W*Y*Y+$,0,0,0,0,1),this}makeScale(J,Q,$){return this.set(J,0,0,0,0,Q,0,0,0,0,$,0,0,0,0,1),this}makeShear(J,Q,$,Z,W,K){return this.set(1,$,W,0,J,1,K,0,Q,Z,1,0,0,0,0,1),this}compose(J,Q,$){let Z=this.elements,W=Q._x,K=Q._y,H=Q._z,Y=Q._w,X=W+W,U=K+K,G=H+H,E=W*X,N=W*U,q=W*G,R=K*U,F=K*G,O=H*G,D=Y*X,k=Y*U,M=Y*G,L=$.x,A=$.y,_=$.z;return Z[0]=(1-(R+O))*L,Z[1]=(N+M)*L,Z[2]=(q-k)*L,Z[3]=0,Z[4]=(N-M)*A,Z[5]=(1-(E+O))*A,Z[6]=(F+D)*A,Z[7]=0,Z[8]=(q+k)*_,Z[9]=(F-D)*_,Z[10]=(1-(E+R))*_,Z[11]=0,Z[12]=J.x,Z[13]=J.y,Z[14]=J.z,Z[15]=1,this}decompose(J,Q,$){let Z=this.elements,W=T9.set(Z[0],Z[1],Z[2]).length(),K=T9.set(Z[4],Z[5],Z[6]).length(),H=T9.set(Z[8],Z[9],Z[10]).length();if(this.determinant()<0)W=-W;J.x=Z[12],J.y=Z[13],J.z=Z[14],$8.copy(this);let X=1/W,U=1/K,G=1/H;return $8.elements[0]*=X,$8.elements[1]*=X,$8.elements[2]*=X,$8.elements[4]*=U,$8.elements[5]*=U,$8.elements[6]*=U,$8.elements[8]*=G,$8.elements[9]*=G,$8.elements[10]*=G,Q.setFromRotationMatrix($8),$.x=W,$.y=K,$.z=H,this}makePerspective(J,Q,$,Z,W,K,H=2000,Y=!1){let X=this.elements,U=2*W/(Q-J),G=2*W/($-Z),E=(Q+J)/(Q-J),N=($+Z)/($-Z),q,R;if(Y)q=W/(K-W),R=K*W/(K-W);else if(H===2000)q=-(K+W)/(K-W),R=-2*K*W/(K-W);else if(H===2001)q=-K/(K-W),R=-K*W/(K-W);else throw Error("THREE.Matrix4.makePerspective(): Invalid coordinate system: "+H);return X[0]=U,X[4]=0,X[8]=E,X[12]=0,X[1]=0,X[5]=G,X[9]=N,X[13]=0,X[2]=0,X[6]=0,X[10]=q,X[14]=R,X[3]=0,X[7]=0,X[11]=-1,X[15]=0,this}makeOrthographic(J,Q,$,Z,W,K,H=2000,Y=!1){let X=this.elements,U=2/(Q-J),G=2/($-Z),E=-(Q+J)/(Q-J),N=-($+Z)/($-Z),q,R;if(Y)q=1/(K-W),R=K/(K-W);else if(H===2000)q=-2/(K-W),R=-(K+W)/(K-W);else if(H===2001)q=-1/(K-W),R=-W/(K-W);else throw Error("THREE.Matrix4.makeOrthographic(): Invalid coordinate system: "+H);return X[0]=U,X[4]=0,X[8]=0,X[12]=E,X[1]=0,X[5]=G,X[9]=0,X[13]=N,X[2]=0,X[6]=0,X[10]=q,X[14]=R,X[3]=0,X[7]=0,X[11]=0,X[15]=1,this}equals(J){let Q=this.elements,$=J.elements;for(let Z=0;Z<16;Z++)if(Q[Z]!==$[Z])return!1;return!0}fromArray(J,Q=0){for(let $=0;$<16;$++)this.elements[$]=J[$+Q];return this}toArray(J=[],Q=0){let $=this.elements;return J[Q]=$[0],J[Q+1]=$[1],J[Q+2]=$[2],J[Q+3]=$[3],J[Q+4]=$[4],J[Q+5]=$[5],J[Q+6]=$[6],J[Q+7]=$[7],J[Q+8]=$[8],J[Q+9]=$[9],J[Q+10]=$[10],J[Q+11]=$[11],J[Q+12]=$[12],J[Q+13]=$[13],J[Q+14]=$[14],J[Q+15]=$[15],J}}var T9=new w,$8=new hJ,uG=new w(0,0,0),cG=new w(1,1,1),b8=new w,q7=new w,u0=new w,WK=new hJ,KK=new b0;class s0{constructor(J=0,Q=0,$=0,Z=s0.DEFAULT_ORDER){this.isEuler=!0,this._x=J,this._y=Q,this._z=$,this._order=Z}get x(){return this._x}set x(J){this._x=J,this._onChangeCallback()}get y(){return this._y}set y(J){this._y=J,this._onChangeCallback()}get z(){return this._z}set z(J){this._z=J,this._onChangeCallback()}get order(){return this._order}set order(J){this._order=J,this._onChangeCallback()}set(J,Q,$,Z=this._order){return this._x=J,this._y=Q,this._z=$,this._order=Z,this._onChangeCallback(),this}clone(){return new this.constructor(this._x,this._y,this._z,this._order)}copy(J){return this._x=J._x,this._y=J._y,this._z=J._z,this._order=J._order,this._onChangeCallback(),this}setFromRotationMatrix(J,Q=this._order,$=!0){let Z=J.elements,W=Z[0],K=Z[4],H=Z[8],Y=Z[1],X=Z[5],U=Z[9],G=Z[2],E=Z[6],N=Z[10];switch(Q){case"XYZ":if(this._y=Math.asin(bJ(H,-1,1)),Math.abs(H)<0.9999999)this._x=Math.atan2(-U,N),this._z=Math.atan2(-K,W);else this._x=Math.atan2(E,X),this._z=0;break;case"YXZ":if(this._x=Math.asin(-bJ(U,-1,1)),Math.abs(U)<0.9999999)this._y=Math.atan2(H,N),this._z=Math.atan2(Y,X);else this._y=Math.atan2(-G,W),this._z=0;break;case"ZXY":if(this._x=Math.asin(bJ(E,-1,1)),Math.abs(E)<0.9999999)this._y=Math.atan2(-G,N),this._z=Math.atan2(-K,X);else this._y=0,this._z=Math.atan2(Y,W);break;case"ZYX":if(this._y=Math.asin(-bJ(G,-1,1)),Math.abs(G)<0.9999999)this._x=Math.atan2(E,N),this._z=Math.atan2(Y,W);else this._x=0,this._z=Math.atan2(-K,X);break;case"YZX":if(this._z=Math.asin(bJ(Y,-1,1)),Math.abs(Y)<0.9999999)this._x=Math.atan2(-U,X),this._y=Math.atan2(-G,W);else this._x=0,this._y=Math.atan2(H,N);break;case"XZY":if(this._z=Math.asin(-bJ(K,-1,1)),Math.abs(K)<0.9999999)this._x=Math.atan2(E,X),this._y=Math.atan2(H,W);else this._x=Math.atan2(-U,N),this._y=0;break;default:console.warn("THREE.Euler: .setFromRotationMatrix() encountered an unknown order: "+Q)}if(this._order=Q,$===!0)this._onChangeCallback();return this}setFromQuaternion(J,Q,$){return WK.makeRotationFromQuaternion(J),this.setFromRotationMatrix(WK,Q,$)}setFromVector3(J,Q=this._order){return this.set(J.x,J.y,J.z,Q)}reorder(J){return KK.setFromEuler(this),this.setFromQuaternion(KK,J)}equals(J){return J._x===this._x&&J._y===this._y&&J._z===this._z&&J._order===this._order}fromArray(J){if(this._x=J[0],this._y=J[1],this._z=J[2],J[3]!==void 0)this._order=J[3];return this._onChangeCallback(),this}toArray(J=[],Q=0){return J[Q]=this._x,J[Q+1]=this._y,J[Q+2]=this._z,J[Q+3]=this._order,J}_onChange(J){return this._onChangeCallback=J,this}_onChangeCallback(){}*[Symbol.iterator](){yield this._x,yield this._y,yield this._z,yield this._order}}s0.DEFAULT_ORDER="XYZ";class s6{constructor(){this.mask=1}set(J){this.mask=(1<<J|0)>>>0}enable(J){this.mask|=1<<J|0}enableAll(){this.mask=-1}toggle(J){this.mask^=1<<J|0}disable(J){this.mask&=~(1<<J|0)}disableAll(){this.mask=0}test(J){return(this.mask&J.mask)!==0}isEnabled(J){return(this.mask&(1<<J|0))!==0}}var nG=0,HK=new w,S9=new b0,L8=new hJ,D7=new w,M6=new w,sG=new w,iG=new b0,YK=new w(1,0,0),XK=new w(0,1,0),UK=new w(0,0,1),GK={type:"added"},oG={type:"removed"},j9={type:"childadded",child:null},O$={type:"childremoved",child:null};class Q0 extends H8{constructor(){super();this.isObject3D=!0,Object.defineProperty(this,"id",{value:nG++}),this.uuid=n0(),this.name="",this.type="Object3D",this.parent=null,this.children=[],this.up=Q0.DEFAULT_UP.clone();let J=new w,Q=new s0,$=new b0,Z=new w(1,1,1);function W(){$.setFromEuler(Q,!1)}function K(){Q.setFromQuaternion($,void 0,!1)}Q._onChange(W),$._onChange(K),Object.defineProperties(this,{position:{configurable:!0,enumerable:!0,value:J},rotation:{configurable:!0,enumerable:!0,value:Q},quaternion:{configurable:!0,enumerable:!0,value:$},scale:{configurable:!0,enumerable:!0,value:Z},modelViewMatrix:{value:new hJ},normalMatrix:{value:new dJ}}),this.matrix=new hJ,this.matrixWorld=new hJ,this.matrixAutoUpdate=Q0.DEFAULT_MATRIX_AUTO_UPDATE,this.matrixWorldAutoUpdate=Q0.DEFAULT_MATRIX_WORLD_AUTO_UPDATE,this.matrixWorldNeedsUpdate=!1,this.layers=new s6,this.visible=!0,this.castShadow=!1,this.receiveShadow=!1,this.frustumCulled=!0,this.renderOrder=0,this.animations=[],this.customDepthMaterial=void 0,this.customDistanceMaterial=void 0,this.userData={}}onBeforeShadow(){}onAfterShadow(){}onBeforeRender(){}onAfterRender(){}applyMatrix4(J){if(this.matrixAutoUpdate)this.updateMatrix();this.matrix.premultiply(J),this.matrix.decompose(this.position,this.quaternion,this.scale)}applyQuaternion(J){return this.quaternion.premultiply(J),this}setRotationFromAxisAngle(J,Q){this.quaternion.setFromAxisAngle(J,Q)}setRotationFromEuler(J){this.quaternion.setFromEuler(J,!0)}setRotationFromMatrix(J){this.quaternion.setFromRotationMatrix(J)}setRotationFromQuaternion(J){this.quaternion.copy(J)}rotateOnAxis(J,Q){return S9.setFromAxisAngle(J,Q),this.quaternion.multiply(S9),this}rotateOnWorldAxis(J,Q){return S9.setFromAxisAngle(J,Q),this.quaternion.premultiply(S9),this}rotateX(J){return this.rotateOnAxis(YK,J)}rotateY(J){return this.rotateOnAxis(XK,J)}rotateZ(J){return this.rotateOnAxis(UK,J)}translateOnAxis(J,Q){return HK.copy(J).applyQuaternion(this.quaternion),this.position.add(HK.multiplyScalar(Q)),this}translateX(J){return this.translateOnAxis(YK,J)}translateY(J){return this.translateOnAxis(XK,J)}translateZ(J){return this.translateOnAxis(UK,J)}localToWorld(J){return this.updateWorldMatrix(!0,!1),J.applyMatrix4(this.matrixWorld)}worldToLocal(J){return this.updateWorldMatrix(!0,!1),J.applyMatrix4(L8.copy(this.matrixWorld).invert())}lookAt(J,Q,$){if(J.isVector3)D7.copy(J);else D7.set(J,Q,$);let Z=this.parent;if(this.updateWorldMatrix(!0,!1),M6.setFromMatrixPosition(this.matrixWorld),this.isCamera||this.isLight)L8.lookAt(M6,D7,this.up);else L8.lookAt(D7,M6,this.up);if(this.quaternion.setFromRotationMatrix(L8),Z)L8.extractRotation(Z.matrixWorld),S9.setFromRotationMatrix(L8),this.quaternion.premultiply(S9.invert())}add(J){if(arguments.length>1){for(let Q=0;Q<arguments.length;Q++)this.add(arguments[Q]);return this}if(J===this)return console.error("THREE.Object3D.add: object can't be added as a child of itself.",J),this;if(J&&J.isObject3D)J.removeFromParent(),J.parent=this,this.children.push(J),J.dispatchEvent(GK),j9.child=J,this.dispatchEvent(j9),j9.child=null;else console.error("THREE.Object3D.add: object not an instance of THREE.Object3D.",J);return this}remove(J){if(arguments.length>1){for(let $=0;$<arguments.length;$++)this.remove(arguments[$]);return this}let Q=this.children.indexOf(J);if(Q!==-1)J.parent=null,this.children.splice(Q,1),J.dispatchEvent(oG),O$.child=J,this.dispatchEvent(O$),O$.child=null;return this}removeFromParent(){let J=this.parent;if(J!==null)J.remove(this);return this}clear(){return this.remove(...this.children)}attach(J){if(this.updateWorldMatrix(!0,!1),L8.copy(this.matrixWorld).invert(),J.parent!==null)J.parent.updateWorldMatrix(!0,!1),L8.multiply(J.parent.matrixWorld);return J.applyMatrix4(L8),J.removeFromParent(),J.parent=this,this.children.push(J),J.updateWorldMatrix(!1,!0),J.dispatchEvent(GK),j9.child=J,this.dispatchEvent(j9),j9.child=null,this}getObjectById(J){return this.getObjectByProperty("id",J)}getObjectByName(J){return this.getObjectByProperty("name",J)}getObjectByProperty(J,Q){if(this[J]===Q)return this;for(let $=0,Z=this.children.length;$<Z;$++){let K=this.children[$].getObjectByProperty(J,Q);if(K!==void 0)return K}return}getObjectsByProperty(J,Q,$=[]){if(this[J]===Q)$.push(this);let Z=this.children;for(let W=0,K=Z.length;W<K;W++)Z[W].getObjectsByProperty(J,Q,$);return $}getWorldPosition(J){return this.updateWorldMatrix(!0,!1),J.setFromMatrixPosition(this.matrixWorld)}getWorldQuaternion(J){return this.updateWorldMatrix(!0,!1),this.matrixWorld.decompose(M6,J,sG),J}getWorldScale(J){return this.updateWorldMatrix(!0,!1),this.matrixWorld.decompose(M6,iG,J),J}getWorldDirection(J){this.updateWorldMatrix(!0,!1);let Q=this.matrixWorld.elements;return J.set(Q[8],Q[9],Q[10]).normalize()}raycast(){}traverse(J){J(this);let Q=this.children;for(let $=0,Z=Q.length;$<Z;$++)Q[$].traverse(J)}traverseVisible(J){if(this.visible===!1)return;J(this);let Q=this.children;for(let $=0,Z=Q.length;$<Z;$++)Q[$].traverseVisible(J)}traverseAncestors(J){let Q=this.parent;if(Q!==null)J(Q),Q.traverseAncestors(J)}updateMatrix(){this.matrix.compose(this.position,this.quaternion,this.scale),this.matrixWorldNeedsUpdate=!0}updateMatrixWorld(J){if(this.matrixAutoUpdate)this.updateMatrix();if(this.matrixWorldNeedsUpdate||J){if(this.matrixWorldAutoUpdate===!0)if(this.parent===null)this.matrixWorld.copy(this.matrix);else this.matrixWorld.multiplyMatrices(this.parent.matrixWorld,this.matrix);this.matrixWorldNeedsUpdate=!1,J=!0}let Q=this.children;for(let $=0,Z=Q.length;$<Z;$++)Q[$].updateMatrixWorld(J)}updateWorldMatrix(J,Q){let $=this.parent;if(J===!0&&$!==null)$.updateWorldMatrix(!0,!1);if(this.matrixAutoUpdate)this.updateMatrix();if(this.matrixWorldAutoUpdate===!0)if(this.parent===null)this.matrixWorld.copy(this.matrix);else this.matrixWorld.multiplyMatrices(this.parent.matrixWorld,this.matrix);if(Q===!0){let Z=this.children;for(let W=0,K=Z.length;W<K;W++)Z[W].updateWorldMatrix(!1,!0)}}toJSON(J){let Q=J===void 0||typeof J==="string",$={};if(Q)J={geometries:{},materials:{},textures:{},images:{},shapes:{},skeletons:{},animations:{},nodes:{}},$.metadata={version:4.7,type:"Object",generator:"Object3D.toJSON"};let Z={};if(Z.uuid=this.uuid,Z.type=this.type,this.name!=="")Z.name=this.name;if(this.castShadow===!0)Z.castShadow=!0;if(this.receiveShadow===!0)Z.receiveShadow=!0;if(this.visible===!1)Z.visible=!1;if(this.frustumCulled===!1)Z.frustumCulled=!1;if(this.renderOrder!==0)Z.renderOrder=this.renderOrder;if(Object.keys(this.userData).length>0)Z.userData=this.userData;if(Z.layers=this.layers.mask,Z.matrix=this.matrix.toArray(),Z.up=this.up.toArray(),this.matrixAutoUpdate===!1)Z.matrixAutoUpdate=!1;if(this.isInstancedMesh){if(Z.type="InstancedMesh",Z.count=this.count,Z.instanceMatrix=this.instanceMatrix.toJSON(),this.instanceColor!==null)Z.instanceColor=this.instanceColor.toJSON()}if(this.isBatchedMesh){if(Z.type="BatchedMesh",Z.perObjectFrustumCulled=this.perObjectFrustumCulled,Z.sortObjects=this.sortObjects,Z.drawRanges=this._drawRanges,Z.reservedRanges=this._reservedRanges,Z.geometryInfo=this._geometryInfo.map((H)=>({...H,boundingBox:H.boundingBox?H.boundingBox.toJSON():void 0,boundingSphere:H.boundingSphere?H.boundingSphere.toJSON():void 0})),Z.instanceInfo=this._instanceInfo.map((H)=>({...H})),Z.availableInstanceIds=this._availableInstanceIds.slice(),Z.availableGeometryIds=this._availableGeometryIds.slice(),Z.nextIndexStart=this._nextIndexStart,Z.nextVertexStart=this._nextVertexStart,Z.geometryCount=this._geometryCount,Z.maxInstanceCount=this._maxInstanceCount,Z.maxVertexCount=this._maxVertexCount,Z.maxIndexCount=this._maxIndexCount,Z.geometryInitialized=this._geometryInitialized,Z.matricesTexture=this._matricesTexture.toJSON(J),Z.indirectTexture=this._indirectTexture.toJSON(J),this._colorsTexture!==null)Z.colorsTexture=this._colorsTexture.toJSON(J);if(this.boundingSphere!==null)Z.boundingSphere=this.boundingSphere.toJSON();if(this.boundingBox!==null)Z.boundingBox=this.boundingBox.toJSON()}function W(H,Y){if(H[Y.uuid]===void 0)H[Y.uuid]=Y.toJSON(J);return Y.uuid}if(this.isScene){if(this.background){if(this.background.isColor)Z.background=this.background.toJSON();else if(this.background.isTexture)Z.background=this.background.toJSON(J).uuid}if(this.environment&&this.environment.isTexture&&this.environment.isRenderTargetTexture!==!0)Z.environment=this.environment.toJSON(J).uuid}else if(this.isMesh||this.isLine||this.isPoints){Z.geometry=W(J.geometries,this.geometry);let H=this.geometry.parameters;if(H!==void 0&&H.shapes!==void 0){let Y=H.shapes;if(Array.isArray(Y))for(let X=0,U=Y.length;X<U;X++){let G=Y[X];W(J.shapes,G)}else W(J.shapes,Y)}}if(this.isSkinnedMesh){if(Z.bindMode=this.bindMode,Z.bindMatrix=this.bindMatrix.toArray(),this.skeleton!==void 0)W(J.skeletons,this.skeleton),Z.skeleton=this.skeleton.uuid}if(this.material!==void 0)if(Array.isArray(this.material)){let H=[];for(let Y=0,X=this.material.length;Y<X;Y++)H.push(W(J.materials,this.material[Y]));Z.material=H}else Z.material=W(J.materials,this.material);if(this.children.length>0){Z.children=[];for(let H=0;H<this.children.length;H++)Z.children.push(this.children[H].toJSON(J).object)}if(this.animations.length>0){Z.animations=[];for(let H=0;H<this.animations.length;H++){let Y=this.animations[H];Z.animations.push(W(J.animations,Y))}}if(Q){let H=K(J.geometries),Y=K(J.materials),X=K(J.textures),U=K(J.images),G=K(J.shapes),E=K(J.skeletons),N=K(J.animations),q=K(J.nodes);if(H.length>0)$.geometries=H;if(Y.length>0)$.materials=Y;if(X.length>0)$.textures=X;if(U.length>0)$.images=U;if(G.length>0)$.shapes=G;if(E.length>0)$.skeletons=E;if(N.length>0)$.animations=N;if(q.length>0)$.nodes=q}return $.object=Z,$;function K(H){let Y=[];for(let X in H){let U=H[X];delete U.metadata,Y.push(U)}return Y}}clone(J){return new this.constructor().copy(this,J)}copy(J,Q=!0){if(this.name=J.name,this.up.copy(J.up),this.position.copy(J.position),this.rotation.order=J.rotation.order,this.quaternion.copy(J.quaternion),this.scale.copy(J.scale),this.matrix.copy(J.matrix),this.matrixWorld.copy(J.matrixWorld),this.matrixAutoUpdate=J.matrixAutoUpdate,this.matrixWorldAutoUpdate=J.matrixWorldAutoUpdate,this.matrixWorldNeedsUpdate=J.matrixWorldNeedsUpdate,this.layers.mask=J.layers.mask,this.visible=J.visible,this.castShadow=J.castShadow,this.receiveShadow=J.receiveShadow,this.frustumCulled=J.frustumCulled,this.renderOrder=J.renderOrder,this.animations=J.animations.slice(),this.userData=JSON.parse(JSON.stringify(J.userData)),Q===!0)for(let $=0;$<J.children.length;$++){let Z=J.children[$];this.add(Z.clone())}return this}}Q0.DEFAULT_UP=new w(0,1,0);Q0.DEFAULT_MATRIX_AUTO_UPDATE=!0;Q0.DEFAULT_MATRIX_WORLD_AUTO_UPDATE=!0;var Z8=new w,z8=new w,R$=new w,B8=new w,y9=new w,v9=new w,EK=new w,F$=new w,M$=new w,k$=new w,V$=new J0,L$=new J0,z$=new J0;class m0{constructor(J=new w,Q=new w,$=new w){this.a=J,this.b=Q,this.c=$}static getNormal(J,Q,$,Z){Z.subVectors($,Q),Z8.subVectors(J,Q),Z.cross(Z8);let W=Z.lengthSq();if(W>0)return Z.multiplyScalar(1/Math.sqrt(W));return Z.set(0,0,0)}static getBarycoord(J,Q,$,Z,W){Z8.subVectors(Z,Q),z8.subVectors($,Q),R$.subVectors(J,Q);let K=Z8.dot(Z8),H=Z8.dot(z8),Y=Z8.dot(R$),X=z8.dot(z8),U=z8.dot(R$),G=K*X-H*H;if(G===0)return W.set(0,0,0),null;let E=1/G,N=(X*Y-H*U)*E,q=(K*U-H*Y)*E;return W.set(1-N-q,q,N)}static containsPoint(J,Q,$,Z){if(this.getBarycoord(J,Q,$,Z,B8)===null)return!1;return B8.x>=0&&B8.y>=0&&B8.x+B8.y<=1}static getInterpolation(J,Q,$,Z,W,K,H,Y){if(this.getBarycoord(J,Q,$,Z,B8)===null){if(Y.x=0,Y.y=0,"z"in Y)Y.z=0;if("w"in Y)Y.w=0;return null}return Y.setScalar(0),Y.addScaledVector(W,B8.x),Y.addScaledVector(K,B8.y),Y.addScaledVector(H,B8.z),Y}static getInterpolatedAttribute(J,Q,$,Z,W,K){return V$.setScalar(0),L$.setScalar(0),z$.setScalar(0),V$.fromBufferAttribute(J,Q),L$.fromBufferAttribute(J,$),z$.fromBufferAttribute(J,Z),K.setScalar(0),K.addScaledVector(V$,W.x),K.addScaledVector(L$,W.y),K.addScaledVector(z$,W.z),K}static isFrontFacing(J,Q,$,Z){return Z8.subVectors($,Q),z8.subVectors(J,Q),Z8.cross(z8).dot(Z)<0?!0:!1}set(J,Q,$){return this.a.copy(J),this.b.copy(Q),this.c.copy($),this}setFromPointsAndIndices(J,Q,$,Z){return this.a.copy(J[Q]),this.b.copy(J[$]),this.c.copy(J[Z]),this}setFromAttributeAndIndices(J,Q,$,Z){return this.a.fromBufferAttribute(J,Q),this.b.fromBufferAttribute(J,$),this.c.fromBufferAttribute(J,Z),this}clone(){return new this.constructor().copy(this)}copy(J){return this.a.copy(J.a),this.b.copy(J.b),this.c.copy(J.c),this}getArea(){return Z8.subVectors(this.c,this.b),z8.subVectors(this.a,this.b),Z8.cross(z8).length()*0.5}getMidpoint(J){return J.addVectors(this.a,this.b).add(this.c).multiplyScalar(0.3333333333333333)}getNormal(J){return m0.getNormal(this.a,this.b,this.c,J)}getPlane(J){return J.setFromCoplanarPoints(this.a,this.b,this.c)}getBarycoord(J,Q){return m0.getBarycoord(J,this.a,this.b,this.c,Q)}getInterpolation(J,Q,$,Z,W){return m0.getInterpolation(J,this.a,this.b,this.c,Q,$,Z,W)}containsPoint(J){return m0.containsPoint(J,this.a,this.b,this.c)}isFrontFacing(J){return m0.isFrontFacing(this.a,this.b,this.c,J)}intersectsBox(J){return J.intersectsTriangle(this)}closestPointToPoint(J,Q){let $=this.a,Z=this.b,W=this.c,K,H;y9.subVectors(Z,$),v9.subVectors(W,$),F$.subVectors(J,$);let Y=y9.dot(F$),X=v9.dot(F$);if(Y<=0&&X<=0)return Q.copy($);M$.subVectors(J,Z);let U=y9.dot(M$),G=v9.dot(M$);if(U>=0&&G<=U)return Q.copy(Z);let E=Y*G-U*X;if(E<=0&&Y>=0&&U<=0)return K=Y/(Y-U),Q.copy($).addScaledVector(y9,K);k$.subVectors(J,W);let N=y9.dot(k$),q=v9.dot(k$);if(q>=0&&N<=q)return Q.copy(W);let R=N*X-Y*q;if(R<=0&&X>=0&&q<=0)return H=X/(X-q),Q.copy($).addScaledVector(v9,H);let F=U*q-N*G;if(F<=0&&G-U>=0&&N-q>=0)return EK.subVectors(W,Z),H=(G-U)/(G-U+(N-q)),Q.copy(Z).addScaledVector(EK,H);let O=1/(F+R+E);return K=R*O,H=E*O,Q.copy($).addScaledVector(y9,K).addScaledVector(v9,H)}equals(J){return J.a.equals(this.a)&&J.b.equals(this.b)&&J.c.equals(this.c)}}var qY={aliceblue:15792383,antiquewhite:16444375,aqua:65535,aquamarine:8388564,azure:15794175,beige:16119260,bisque:16770244,black:0,blanchedalmond:16772045,blue:255,blueviolet:9055202,brown:10824234,burlywood:14596231,cadetblue:6266528,chartreuse:8388352,chocolate:13789470,coral:16744272,cornflowerblue:6591981,cornsilk:16775388,crimson:14423100,cyan:65535,darkblue:139,darkcyan:35723,darkgoldenrod:12092939,darkgray:11119017,darkgreen:25600,darkgrey:11119017,darkkhaki:12433259,darkmagenta:9109643,darkolivegreen:5597999,darkorange:16747520,darkorchid:10040012,darkred:9109504,darksalmon:15308410,darkseagreen:9419919,darkslateblue:4734347,darkslategray:3100495,darkslategrey:3100495,darkturquoise:52945,darkviolet:9699539,deeppink:16716947,deepskyblue:49151,dimgray:6908265,dimgrey:6908265,dodgerblue:2003199,firebrick:11674146,floralwhite:16775920,forestgreen:2263842,fuchsia:16711935,gainsboro:14474460,ghostwhite:16316671,gold:16766720,goldenrod:14329120,gray:8421504,green:32768,greenyellow:11403055,grey:8421504,honeydew:15794160,hotpink:16738740,indianred:13458524,indigo:4915330,ivory:16777200,khaki:15787660,lavender:15132410,lavenderblush:16773365,lawngreen:8190976,lemonchiffon:16775885,lightblue:11393254,lightcoral:15761536,lightcyan:14745599,lightgoldenrodyellow:16448210,lightgray:13882323,lightgreen:9498256,lightgrey:13882323,lightpink:16758465,lightsalmon:16752762,lightseagreen:2142890,lightskyblue:8900346,lightslategray:7833753,lightslategrey:7833753,lightsteelblue:11584734,lightyellow:16777184,lime:65280,limegreen:3329330,linen:16445670,magenta:16711935,maroon:8388608,mediumaquamarine:6737322,mediumblue:205,mediumorchid:12211667,mediumpurple:9662683,mediumseagreen:3978097,mediumslateblue:8087790,mediumspringgreen:64154,mediumturquoise:4772300,mediumvioletred:13047173,midnightblue:1644912,mintcream:16121850,mistyrose:16770273,moccasin:16770229,navajowhite:16768685,navy:128,oldlace:16643558,olive:8421376,olivedrab:7048739,orange:16753920,orangered:16729344,orchid:14315734,palegoldenrod:15657130,palegreen:10025880,paleturquoise:11529966,palevioletred:14381203,papayawhip:16773077,peachpuff:16767673,peru:13468991,pink:16761035,plum:14524637,powderblue:11591910,purple:8388736,rebeccapurple:6697881,red:16711680,rosybrown:12357519,royalblue:4286945,saddlebrown:9127187,salmon:16416882,sandybrown:16032864,seagreen:3050327,seashell:16774638,sienna:10506797,silver:12632256,skyblue:8900331,slateblue:6970061,slategray:7372944,slategrey:7372944,snow:16775930,springgreen:65407,steelblue:4620980,tan:13808780,teal:32896,thistle:14204888,tomato:16737095,turquoise:4251856,violet:15631086,wheat:16113331,white:16777215,whitesmoke:16119285,yellow:16776960,yellowgreen:10145074},h8={h:0,s:0,l:0},O7={h:0,s:0,l:0};function B$(J,Q,$){if($<0)$+=1;if($>1)$-=1;if($<0.16666666666666666)return J+(Q-J)*6*$;if($<0.5)return Q;if($<0.6666666666666666)return J+(Q-J)*6*(0.6666666666666666-$);return J}class kJ{constructor(J,Q,$){return this.isColor=!0,this.r=1,this.g=1,this.b=1,this.set(J,Q,$)}set(J,Q,$){if(Q===void 0&&$===void 0){let Z=J;if(Z&&Z.isColor)this.copy(Z);else if(typeof Z==="number")this.setHex(Z);else if(typeof Z==="string")this.setStyle(Z)}else this.setRGB(J,Q,$);return this}setScalar(J){return this.r=J,this.g=J,this.b=J,this}setHex(J,Q="srgb"){return J=Math.floor(J),this.r=(J>>16&255)/255,this.g=(J>>8&255)/255,this.b=(J&255)/255,tJ.colorSpaceToWorking(this,Q),this}setRGB(J,Q,$,Z=tJ.workingColorSpace){return this.r=J,this.g=Q,this.b=$,tJ.colorSpaceToWorking(this,Z),this}setHSL(J,Q,$,Z=tJ.workingColorSpace){if(J=xZ(J,1),Q=bJ(Q,0,1),$=bJ($,0,1),Q===0)this.r=this.g=this.b=$;else{let W=$<=0.5?$*(1+Q):$+Q-$*Q,K=2*$-W;this.r=B$(K,W,J+0.3333333333333333),this.g=B$(K,W,J),this.b=B$(K,W,J-0.3333333333333333)}return tJ.colorSpaceToWorking(this,Z),this}setStyle(J,Q="srgb"){function $(W){if(W===void 0)return;if(parseFloat(W)<1)console.warn("THREE.Color: Alpha component of "+J+" will be ignored.")}let Z;if(Z=/^(\w+)\(([^\)]*)\)/.exec(J)){let W,K=Z[1],H=Z[2];switch(K){case"rgb":case"rgba":if(W=/^\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*(\d*\.?\d+)\s*)?$/.exec(H))return $(W[4]),this.setRGB(Math.min(255,parseInt(W[1],10))/255,Math.min(255,parseInt(W[2],10))/255,Math.min(255,parseInt(W[3],10))/255,Q);if(W=/^\s*(\d+)\%\s*,\s*(\d+)\%\s*,\s*(\d+)\%\s*(?:,\s*(\d*\.?\d+)\s*)?$/.exec(H))return $(W[4]),this.setRGB(Math.min(100,parseInt(W[1],10))/100,Math.min(100,parseInt(W[2],10))/100,Math.min(100,parseInt(W[3],10))/100,Q);break;case"hsl":case"hsla":if(W=/^\s*(\d*\.?\d+)\s*,\s*(\d*\.?\d+)\%\s*,\s*(\d*\.?\d+)\%\s*(?:,\s*(\d*\.?\d+)\s*)?$/.exec(H))return $(W[4]),this.setHSL(parseFloat(W[1])/360,parseFloat(W[2])/100,parseFloat(W[3])/100,Q);break;default:console.warn("THREE.Color: Unknown color model "+J)}}else if(Z=/^\#([A-Fa-f\d]+)$/.exec(J)){let W=Z[1],K=W.length;if(K===3)return this.setRGB(parseInt(W.charAt(0),16)/15,parseInt(W.charAt(1),16)/15,parseInt(W.charAt(2),16)/15,Q);else if(K===6)return this.setHex(parseInt(W,16),Q);else console.warn("THREE.Color: Invalid hex color "+J)}else if(J&&J.length>0)return this.setColorName(J,Q);return this}setColorName(J,Q="srgb"){let $=qY[J.toLowerCase()];if($!==void 0)this.setHex($,Q);else console.warn("THREE.Color: Unknown color "+J);return this}clone(){return new this.constructor(this.r,this.g,this.b)}copy(J){return this.r=J.r,this.g=J.g,this.b=J.b,this}copySRGBToLinear(J){return this.r=P8(J.r),this.g=P8(J.g),this.b=P8(J.b),this}copyLinearToSRGB(J){return this.r=s9(J.r),this.g=s9(J.g),this.b=s9(J.b),this}convertSRGBToLinear(){return this.copySRGBToLinear(this),this}convertLinearToSRGB(){return this.copyLinearToSRGB(this),this}getHex(J="srgb"){return tJ.workingToColorSpace(A0.copy(this),J),Math.round(bJ(A0.r*255,0,255))*65536+Math.round(bJ(A0.g*255,0,255))*256+Math.round(bJ(A0.b*255,0,255))}getHexString(J="srgb"){return("000000"+this.getHex(J).toString(16)).slice(-6)}getHSL(J,Q=tJ.workingColorSpace){tJ.workingToColorSpace(A0.copy(this),Q);let{r:$,g:Z,b:W}=A0,K=Math.max($,Z,W),H=Math.min($,Z,W),Y,X,U=(H+K)/2;if(H===K)Y=0,X=0;else{let G=K-H;switch(X=U<=0.5?G/(K+H):G/(2-K-H),K){case $:Y=(Z-W)/G+(Z<W?6:0);break;case Z:Y=(W-$)/G+2;break;case W:Y=($-Z)/G+4;break}Y/=6}return J.h=Y,J.s=X,J.l=U,J}getRGB(J,Q=tJ.workingColorSpace){return tJ.workingToColorSpace(A0.copy(this),Q),J.r=A0.r,J.g=A0.g,J.b=A0.b,J}getStyle(J="srgb"){tJ.workingToColorSpace(A0.copy(this),J);let{r:Q,g:$,b:Z}=A0;if(J!=="srgb")return`color(${J} ${Q.toFixed(3)} ${$.toFixed(3)} ${Z.toFixed(3)})`;return`rgb(${Math.round(Q*255)},${Math.round($*255)},${Math.round(Z*255)})`}offsetHSL(J,Q,$){return this.getHSL(h8),this.setHSL(h8.h+J,h8.s+Q,h8.l+$)}add(J){return this.r+=J.r,this.g+=J.g,this.b+=J.b,this}addColors(J,Q){return this.r=J.r+Q.r,this.g=J.g+Q.g,this.b=J.b+Q.b,this}addScalar(J){return this.r+=J,this.g+=J,this.b+=J,this}sub(J){return this.r=Math.max(0,this.r-J.r),this.g=Math.max(0,this.g-J.g),this.b=Math.max(0,this.b-J.b),this}multiply(J){return this.r*=J.r,this.g*=J.g,this.b*=J.b,this}multiplyScalar(J){return this.r*=J,this.g*=J,this.b*=J,this}lerp(J,Q){return this.r+=(J.r-this.r)*Q,this.g+=(J.g-this.g)*Q,this.b+=(J.b-this.b)*Q,this}lerpColors(J,Q,$){return this.r=J.r+(Q.r-J.r)*$,this.g=J.g+(Q.g-J.g)*$,this.b=J.b+(Q.b-J.b)*$,this}lerpHSL(J,Q){this.getHSL(h8),J.getHSL(O7);let $=T6(h8.h,O7.h,Q),Z=T6(h8.s,O7.s,Q),W=T6(h8.l,O7.l,Q);return this.setHSL($,Z,W),this}setFromVector3(J){return this.r=J.x,this.g=J.y,this.b=J.z,this}applyMatrix3(J){let Q=this.r,$=this.g,Z=this.b,W=J.elements;return this.r=W[0]*Q+W[3]*$+W[6]*Z,this.g=W[1]*Q+W[4]*$+W[7]*Z,this.b=W[2]*Q+W[5]*$+W[8]*Z,this}equals(J){return J.r===this.r&&J.g===this.g&&J.b===this.b}fromArray(J,Q=0){return this.r=J[Q],this.g=J[Q+1],this.b=J[Q+2],this}toArray(J=[],Q=0){return J[Q]=this.r,J[Q+1]=this.g,J[Q+2]=this.b,J}fromBufferAttribute(J,Q){return this.r=J.getX(Q),this.g=J.getY(Q),this.b=J.getZ(Q),this}toJSON(){return this.getHex()}*[Symbol.iterator](){yield this.r,yield this.g,yield this.b}}var A0=new kJ;kJ.NAMES=qY;var aG=0;class C0 extends H8{constructor(){super();this.isMaterial=!0,Object.defineProperty(this,"id",{value:aG++}),this.uuid=n0(),this.name="",this.type="Material",this.blending=1,this.side=0,this.vertexColors=!1,this.opacity=1,this.transparent=!1,this.alphaHash=!1,this.blendSrc=204,this.blendDst=205,this.blendEquation=100,this.blendSrcAlpha=null,this.blendDstAlpha=null,this.blendEquationAlpha=null,this.blendColor=new kJ(0,0,0),this.blendAlpha=0,this.depthFunc=3,this.depthTest=!0,this.depthWrite=!0,this.stencilWriteMask=255,this.stencilFunc=519,this.stencilRef=0,this.stencilFuncMask=255,this.stencilFail=7680,this.stencilZFail=7680,this.stencilZPass=7680,this.stencilWrite=!1,this.clippingPlanes=null,this.clipIntersection=!1,this.clipShadows=!1,this.shadowSide=null,this.colorWrite=!0,this.precision=null,this.polygonOffset=!1,this.polygonOffsetFactor=0,this.polygonOffsetUnits=0,this.dithering=!1,this.alphaToCoverage=!1,this.premultipliedAlpha=!1,this.forceSinglePass=!1,this.allowOverride=!0,this.visible=!0,this.toneMapped=!0,this.userData={},this.version=0,this._alphaTest=0}get alphaTest(){return this._alphaTest}set alphaTest(J){if(this._alphaTest>0!==J>0)this.version++;this._alphaTest=J}onBeforeRender(){}onBeforeCompile(){}customProgramCacheKey(){return this.onBeforeCompile.toString()}setValues(J){if(J===void 0)return;for(let Q in J){let $=J[Q];if($===void 0){console.warn(`THREE.Material: parameter '${Q}' has value of undefined.`);continue}let Z=this[Q];if(Z===void 0){console.warn(`THREE.Material: '${Q}' is not a property of THREE.${this.type}.`);continue}if(Z&&Z.isColor)Z.set($);else if(Z&&Z.isVector3&&($&&$.isVector3))Z.copy($);else this[Q]=$}}toJSON(J){let Q=J===void 0||typeof J==="string";if(Q)J={textures:{},images:{}};let $={metadata:{version:4.7,type:"Material",generator:"Material.toJSON"}};if($.uuid=this.uuid,$.type=this.type,this.name!=="")$.name=this.name;if(this.color&&this.color.isColor)$.color=this.color.getHex();if(this.roughness!==void 0)$.roughness=this.roughness;if(this.metalness!==void 0)$.metalness=this.metalness;if(this.sheen!==void 0)$.sheen=this.sheen;if(this.sheenColor&&this.sheenColor.isColor)$.sheenColor=this.sheenColor.getHex();if(this.sheenRoughness!==void 0)$.sheenRoughness=this.sheenRoughness;if(this.emissive&&this.emissive.isColor)$.emissive=this.emissive.getHex();if(this.emissiveIntensity!==void 0&&this.emissiveIntensity!==1)$.emissiveIntensity=this.emissiveIntensity;if(this.specular&&this.specular.isColor)$.specular=this.specular.getHex();if(this.specularIntensity!==void 0)$.specularIntensity=this.specularIntensity;if(this.specularColor&&this.specularColor.isColor)$.specularColor=this.specularColor.getHex();if(this.shininess!==void 0)$.shininess=this.shininess;if(this.clearcoat!==void 0)$.clearcoat=this.clearcoat;if(this.clearcoatRoughness!==void 0)$.clearcoatRoughness=this.clearcoatRoughness;if(this.clearcoatMap&&this.clearcoatMap.isTexture)$.clearcoatMap=this.clearcoatMap.toJSON(J).uuid;if(this.clearcoatRoughnessMap&&this.clearcoatRoughnessMap.isTexture)$.clearcoatRoughnessMap=this.clearcoatRoughnessMap.toJSON(J).uuid;if(this.clearcoatNormalMap&&this.clearcoatNormalMap.isTexture)$.clearcoatNormalMap=this.clearcoatNormalMap.toJSON(J).uuid,$.clearcoatNormalScale=this.clearcoatNormalScale.toArray();if(this.sheenColorMap&&this.sheenColorMap.isTexture)$.sheenColorMap=this.sheenColorMap.toJSON(J).uuid;if(this.sheenRoughnessMap&&this.sheenRoughnessMap.isTexture)$.sheenRoughnessMap=this.sheenRoughnessMap.toJSON(J).uuid;if(this.dispersion!==void 0)$.dispersion=this.dispersion;if(this.iridescence!==void 0)$.iridescence=this.iridescence;if(this.iridescenceIOR!==void 0)$.iridescenceIOR=this.iridescenceIOR;if(this.iridescenceThicknessRange!==void 0)$.iridescenceThicknessRange=this.iridescenceThicknessRange;if(this.iridescenceMap&&this.iridescenceMap.isTexture)$.iridescenceMap=this.iridescenceMap.toJSON(J).uuid;if(this.iridescenceThicknessMap&&this.iridescenceThicknessMap.isTexture)$.iridescenceThicknessMap=this.iridescenceThicknessMap.toJSON(J).uuid;if(this.anisotropy!==void 0)$.anisotropy=this.anisotropy;if(this.anisotropyRotation!==void 0)$.anisotropyRotation=this.anisotropyRotation;if(this.anisotropyMap&&this.anisotropyMap.isTexture)$.anisotropyMap=this.anisotropyMap.toJSON(J).uuid;if(this.map&&this.map.isTexture)$.map=this.map.toJSON(J).uuid;if(this.matcap&&this.matcap.isTexture)$.matcap=this.matcap.toJSON(J).uuid;if(this.alphaMap&&this.alphaMap.isTexture)$.alphaMap=this.alphaMap.toJSON(J).uuid;if(this.lightMap&&this.lightMap.isTexture)$.lightMap=this.lightMap.toJSON(J).uuid,$.lightMapIntensity=this.lightMapIntensity;if(this.aoMap&&this.aoMap.isTexture)$.aoMap=this.aoMap.toJSON(J).uuid,$.aoMapIntensity=this.aoMapIntensity;if(this.bumpMap&&this.bumpMap.isTexture)$.bumpMap=this.bumpMap.toJSON(J).uuid,$.bumpScale=this.bumpScale;if(this.normalMap&&this.normalMap.isTexture)$.normalMap=this.normalMap.toJSON(J).uuid,$.normalMapType=this.normalMapType,$.normalScale=this.normalScale.toArray();if(this.displacementMap&&this.displacementMap.isTexture)$.displacementMap=this.displacementMap.toJSON(J).uuid,$.displacementScale=this.displacementScale,$.displacementBias=this.displacementBias;if(this.roughnessMap&&this.roughnessMap.isTexture)$.roughnessMap=this.roughnessMap.toJSON(J).uuid;if(this.metalnessMap&&this.metalnessMap.isTexture)$.metalnessMap=this.metalnessMap.toJSON(J).uuid;if(this.emissiveMap&&this.emissiveMap.isTexture)$.emissiveMap=this.emissiveMap.toJSON(J).uuid;if(this.specularMap&&this.specularMap.isTexture)$.specularMap=this.specularMap.toJSON(J).uuid;if(this.specularIntensityMap&&this.specularIntensityMap.isTexture)$.specularIntensityMap=this.specularIntensityMap.toJSON(J).uuid;if(this.specularColorMap&&this.specularColorMap.isTexture)$.specularColorMap=this.specularColorMap.toJSON(J).uuid;if(this.envMap&&this.envMap.isTexture){if($.envMap=this.envMap.toJSON(J).uuid,this.combine!==void 0)$.combine=this.combine}if(this.envMapRotation!==void 0)$.envMapRotation=this.envMapRotation.toArray();if(this.envMapIntensity!==void 0)$.envMapIntensity=this.envMapIntensity;if(this.reflectivity!==void 0)$.reflectivity=this.reflectivity;if(this.refractionRatio!==void 0)$.refractionRatio=this.refractionRatio;if(this.gradientMap&&this.gradientMap.isTexture)$.gradientMap=this.gradientMap.toJSON(J).uuid;if(this.transmission!==void 0)$.transmission=this.transmission;if(this.transmissionMap&&this.transmissionMap.isTexture)$.transmissionMap=this.transmissionMap.toJSON(J).uuid;if(this.thickness!==void 0)$.thickness=this.thickness;if(this.thicknessMap&&this.thicknessMap.isTexture)$.thicknessMap=this.thicknessMap.toJSON(J).uuid;if(this.attenuationDistance!==void 0&&this.attenuationDistance!==1/0)$.attenuationDistance=this.attenuationDistance;if(this.attenuationColor!==void 0)$.attenuationColor=this.attenuationColor.getHex();if(this.size!==void 0)$.size=this.size;if(this.shadowSide!==null)$.shadowSide=this.shadowSide;if(this.sizeAttenuation!==void 0)$.sizeAttenuation=this.sizeAttenuation;if(this.blending!==1)$.blending=this.blending;if(this.side!==0)$.side=this.side;if(this.vertexColors===!0)$.vertexColors=!0;if(this.opacity<1)$.opacity=this.opacity;if(this.transparent===!0)$.transparent=!0;if(this.blendSrc!==204)$.blendSrc=this.blendSrc;if(this.blendDst!==205)$.blendDst=this.blendDst;if(this.blendEquation!==100)$.blendEquation=this.blendEquation;if(this.blendSrcAlpha!==null)$.blendSrcAlpha=this.blendSrcAlpha;if(this.blendDstAlpha!==null)$.blendDstAlpha=this.blendDstAlpha;if(this.blendEquationAlpha!==null)$.blendEquationAlpha=this.blendEquationAlpha;if(this.blendColor&&this.blendColor.isColor)$.blendColor=this.blendColor.getHex();if(this.blendAlpha!==0)$.blendAlpha=this.blendAlpha;if(this.depthFunc!==3)$.depthFunc=this.depthFunc;if(this.depthTest===!1)$.depthTest=this.depthTest;if(this.depthWrite===!1)$.depthWrite=this.depthWrite;if(this.colorWrite===!1)$.colorWrite=this.colorWrite;if(this.stencilWriteMask!==255)$.stencilWriteMask=this.stencilWriteMask;if(this.stencilFunc!==519)$.stencilFunc=this.stencilFunc;if(this.stencilRef!==0)$.stencilRef=this.stencilRef;if(this.stencilFuncMask!==255)$.stencilFuncMask=this.stencilFuncMask;if(this.stencilFail!==7680)$.stencilFail=this.stencilFail;if(this.stencilZFail!==7680)$.stencilZFail=this.stencilZFail;if(this.stencilZPass!==7680)$.stencilZPass=this.stencilZPass;if(this.stencilWrite===!0)$.stencilWrite=this.stencilWrite;if(this.rotation!==void 0&&this.rotation!==0)$.rotation=this.rotation;if(this.polygonOffset===!0)$.polygonOffset=!0;if(this.polygonOffsetFactor!==0)$.polygonOffsetFactor=this.polygonOffsetFactor;if(this.polygonOffsetUnits!==0)$.polygonOffsetUnits=this.polygonOffsetUnits;if(this.linewidth!==void 0&&this.linewidth!==1)$.linewidth=this.linewidth;if(this.dashSize!==void 0)$.dashSize=this.dashSize;if(this.gapSize!==void 0)$.gapSize=this.gapSize;if(this.scale!==void 0)$.scale=this.scale;if(this.dithering===!0)$.dithering=!0;if(this.alphaTest>0)$.alphaTest=this.alphaTest;if(this.alphaHash===!0)$.alphaHash=!0;if(this.alphaToCoverage===!0)$.alphaToCoverage=!0;if(this.premultipliedAlpha===!0)$.premultipliedAlpha=!0;if(this.forceSinglePass===!0)$.forceSinglePass=!0;if(this.wireframe===!0)$.wireframe=!0;if(this.wireframeLinewidth>1)$.wireframeLinewidth=this.wireframeLinewidth;if(this.wireframeLinecap!=="round")$.wireframeLinecap=this.wireframeLinecap;if(this.wireframeLinejoin!=="round")$.wireframeLinejoin=this.wireframeLinejoin;if(this.flatShading===!0)$.flatShading=!0;if(this.visible===!1)$.visible=!1;if(this.toneMapped===!1)$.toneMapped=!1;if(this.fog===!1)$.fog=!1;if(Object.keys(this.userData).length>0)$.userData=this.userData;function Z(W){let K=[];for(let H in W){let Y=W[H];delete Y.metadata,K.push(Y)}return K}if(Q){let W=Z(J.textures),K=Z(J.images);if(W.length>0)$.textures=W;if(K.length>0)$.images=K}return $}clone(){return new this.constructor().copy(this)}copy(J){this.name=J.name,this.blending=J.blending,this.side=J.side,this.vertexColors=J.vertexColors,this.opacity=J.opacity,this.transparent=J.transparent,this.blendSrc=J.blendSrc,this.blendDst=J.blendDst,this.blendEquation=J.blendEquation,this.blendSrcAlpha=J.blendSrcAlpha,this.blendDstAlpha=J.blendDstAlpha,this.blendEquationAlpha=J.blendEquationAlpha,this.blendColor.copy(J.blendColor),this.blendAlpha=J.blendAlpha,this.depthFunc=J.depthFunc,this.depthTest=J.depthTest,this.depthWrite=J.depthWrite,this.stencilWriteMask=J.stencilWriteMask,this.stencilFunc=J.stencilFunc,this.stencilRef=J.stencilRef,this.stencilFuncMask=J.stencilFuncMask,this.stencilFail=J.stencilFail,this.stencilZFail=J.stencilZFail,this.stencilZPass=J.stencilZPass,this.stencilWrite=J.stencilWrite;let Q=J.clippingPlanes,$=null;if(Q!==null){let Z=Q.length;$=Array(Z);for(let W=0;W!==Z;++W)$[W]=Q[W].clone()}return this.clippingPlanes=$,this.clipIntersection=J.clipIntersection,this.clipShadows=J.clipShadows,this.shadowSide=J.shadowSide,this.colorWrite=J.colorWrite,this.precision=J.precision,this.polygonOffset=J.polygonOffset,this.polygonOffsetFactor=J.polygonOffsetFactor,this.polygonOffsetUnits=J.polygonOffsetUnits,this.dithering=J.dithering,this.alphaTest=J.alphaTest,this.alphaHash=J.alphaHash,this.alphaToCoverage=J.alphaToCoverage,this.premultipliedAlpha=J.premultipliedAlpha,this.forceSinglePass=J.forceSinglePass,this.visible=J.visible,this.toneMapped=J.toneMapped,this.userData=JSON.parse(JSON.stringify(J.userData)),this}dispose(){this.dispatchEvent({type:"dispose"})}set needsUpdate(J){if(J===!0)this.version++}}class S8 extends C0{constructor(J){super();this.isMeshBasicMaterial=!0,this.type="MeshBasicMaterial",this.color=new kJ(16777215),this.map=null,this.lightMap=null,this.lightMapIntensity=1,this.aoMap=null,this.aoMapIntensity=1,this.specularMap=null,this.alphaMap=null,this.envMap=null,this.envMapRotation=new s0,this.combine=0,this.reflectivity=1,this.refractionRatio=0.98,this.wireframe=!1,this.wireframeLinewidth=1,this.wireframeLinecap="round",this.wireframeLinejoin="round",this.fog=!0,this.setValues(J)}copy(J){return super.copy(J),this.color.copy(J.color),this.map=J.map,this.lightMap=J.lightMap,this.lightMapIntensity=J.lightMapIntensity,this.aoMap=J.aoMap,this.aoMapIntensity=J.aoMapIntensity,this.specularMap=J.specularMap,this.alphaMap=J.alphaMap,this.envMap=J.envMap,this.envMapRotation.copy(J.envMapRotation),this.combine=J.combine,this.reflectivity=J.reflectivity,this.refractionRatio=J.refractionRatio,this.wireframe=J.wireframe,this.wireframeLinewidth=J.wireframeLinewidth,this.wireframeLinecap=J.wireframeLinecap,this.wireframeLinejoin=J.wireframeLinejoin,this.fog=J.fog,this}}var w8=rG();function rG(){let J=new ArrayBuffer(4),Q=new Float32Array(J),$=new Uint32Array(J),Z=new Uint32Array(512),W=new Uint32Array(512);for(let X=0;X<256;++X){let U=X-127;if(U<-27)Z[X]=0,Z[X|256]=32768,W[X]=24,W[X|256]=24;else if(U<-14)Z[X]=1024>>-U-14,Z[X|256]=1024>>-U-14|32768,W[X]=-U-1,W[X|256]=-U-1;else if(U<=15)Z[X]=U+15<<10,Z[X|256]=U+15<<10|32768,W[X]=13,W[X|256]=13;else if(U<128)Z[X]=31744,Z[X|256]=64512,W[X]=24,W[X|256]=24;else Z[X]=31744,Z[X|256]=64512,W[X]=13,W[X|256]=13}let K=new Uint32Array(2048),H=new Uint32Array(64),Y=new Uint32Array(64);for(let X=1;X<1024;++X){let U=X<<13,G=0;while((U&8388608)===0)U<<=1,G-=8388608;U&=-8388609,G+=947912704,K[X]=U|G}for(let X=1024;X<2048;++X)K[X]=939524096+(X-1024<<13);for(let X=1;X<31;++X)H[X]=X<<23;H[31]=1199570944,H[32]=2147483648;for(let X=33;X<63;++X)H[X]=2147483648+(X-32<<23);H[63]=3347054592;for(let X=1;X<64;++X)if(X!==32)Y[X]=1024;return{floatView:Q,uint32View:$,baseTable:Z,shiftTable:W,mantissaTable:K,exponentTable:H,offsetTable:Y}}function p0(J){if(Math.abs(J)>65504)console.warn("THREE.DataUtils.toHalfFloat(): Value out of range.");J=bJ(J,-65504,65504),w8.floatView[0]=J;let Q=w8.uint32View[0],$=Q>>23&511;return w8.baseTable[$]+((Q&8388607)>>w8.shiftTable[$])}function P6(J){let Q=J>>10;return w8.uint32View[0]=w8.mantissaTable[w8.offsetTable[Q]+(J&1023)]+w8.exponentTable[Q],w8.floatView[0]}class DY{static toHalfFloat(J){return p0(J)}static fromHalfFloat(J){return P6(J)}}var V0=new w,R7=new t,tG=0;class Z0{constructor(J,Q,$=!1){if(Array.isArray(J))throw TypeError("THREE.BufferAttribute: array should be a Typed Array.");this.isBufferAttribute=!0,Object.defineProperty(this,"id",{value:tG++}),this.name="",this.array=J,this.itemSize=Q,this.count=J!==void 0?J.length/Q:0,this.normalized=$,this.usage=35044,this.updateRanges=[],this.gpuType=1015,this.version=0}onUploadCallback(){}set needsUpdate(J){if(J===!0)this.version++}setUsage(J){return this.usage=J,this}addUpdateRange(J,Q){this.updateRanges.push({start:J,count:Q})}clearUpdateRanges(){this.updateRanges.length=0}copy(J){return this.name=J.name,this.array=new J.array.constructor(J.array),this.itemSize=J.itemSize,this.count=J.count,this.normalized=J.normalized,this.usage=J.usage,this.gpuType=J.gpuType,this}copyAt(J,Q,$){J*=this.itemSize,$*=Q.itemSize;for(let Z=0,W=this.itemSize;Z<W;Z++)this.array[J+Z]=Q.array[$+Z];return this}copyArray(J){return this.array.set(J),this}applyMatrix3(J){if(this.itemSize===2)for(let Q=0,$=this.count;Q<$;Q++)R7.fromBufferAttribute(this,Q),R7.applyMatrix3(J),this.setXY(Q,R7.x,R7.y);else if(this.itemSize===3)for(let Q=0,$=this.count;Q<$;Q++)V0.fromBufferAttribute(this,Q),V0.applyMatrix3(J),this.setXYZ(Q,V0.x,V0.y,V0.z);return this}applyMatrix4(J){for(let Q=0,$=this.count;Q<$;Q++)V0.fromBufferAttribute(this,Q),V0.applyMatrix4(J),this.setXYZ(Q,V0.x,V0.y,V0.z);return this}applyNormalMatrix(J){for(let Q=0,$=this.count;Q<$;Q++)V0.fromBufferAttribute(this,Q),V0.applyNormalMatrix(J),this.setXYZ(Q,V0.x,V0.y,V0.z);return this}transformDirection(J){for(let Q=0,$=this.count;Q<$;Q++)V0.fromBufferAttribute(this,Q),V0.transformDirection(J),this.setXYZ(Q,V0.x,V0.y,V0.z);return this}set(J,Q=0){return this.array.set(J,Q),this}getComponent(J,Q){let $=this.array[J*this.itemSize+Q];if(this.normalized)$=f0($,this.array);return $}setComponent(J,Q,$){if(this.normalized)$=cJ($,this.array);return this.array[J*this.itemSize+Q]=$,this}getX(J){let Q=this.array[J*this.itemSize];if(this.normalized)Q=f0(Q,this.array);return Q}setX(J,Q){if(this.normalized)Q=cJ(Q,this.array);return this.array[J*this.itemSize]=Q,this}getY(J){let Q=this.array[J*this.itemSize+1];if(this.normalized)Q=f0(Q,this.array);return Q}setY(J,Q){if(this.normalized)Q=cJ(Q,this.array);return this.array[J*this.itemSize+1]=Q,this}getZ(J){let Q=this.array[J*this.itemSize+2];if(this.normalized)Q=f0(Q,this.array);return Q}setZ(J,Q){if(this.normalized)Q=cJ(Q,this.array);return this.array[J*this.itemSize+2]=Q,this}getW(J){let Q=this.array[J*this.itemSize+3];if(this.normalized)Q=f0(Q,this.array);return Q}setW(J,Q){if(this.normalized)Q=cJ(Q,this.array);return this.array[J*this.itemSize+3]=Q,this}setXY(J,Q,$){if(J*=this.itemSize,this.normalized)Q=cJ(Q,this.array),$=cJ($,this.array);return this.array[J+0]=Q,this.array[J+1]=$,this}setXYZ(J,Q,$,Z){if(J*=this.itemSize,this.normalized)Q=cJ(Q,this.array),$=cJ($,this.array),Z=cJ(Z,this.array);return this.array[J+0]=Q,this.array[J+1]=$,this.array[J+2]=Z,this}setXYZW(J,Q,$,Z,W){if(J*=this.itemSize,this.normalized)Q=cJ(Q,this.array),$=cJ($,this.array),Z=cJ(Z,this.array),W=cJ(W,this.array);return this.array[J+0]=Q,this.array[J+1]=$,this.array[J+2]=Z,this.array[J+3]=W,this}onUpload(J){return this.onUploadCallback=J,this}clone(){return new this.constructor(this.array,this.itemSize).copy(this)}toJSON(){let J={itemSize:this.itemSize,type:this.array.constructor.name,array:Array.from(this.array),normalized:this.normalized};if(this.name!=="")J.name=this.name;if(this.usage!==35044)J.usage=this.usage;return J}}class OY extends Z0{constructor(J,Q,$){super(new Int8Array(J),Q,$)}}class RY extends Z0{constructor(J,Q,$){super(new Uint8Array(J),Q,$)}}class FY extends Z0{constructor(J,Q,$){super(new Uint8ClampedArray(J),Q,$)}}class MY extends Z0{constructor(J,Q,$){super(new Int16Array(J),Q,$)}}class RQ extends Z0{constructor(J,Q,$){super(new Uint16Array(J),Q,$)}}class kY extends Z0{constructor(J,Q,$){super(new Int32Array(J),Q,$)}}class FQ extends Z0{constructor(J,Q,$){super(new Uint32Array(J),Q,$)}}class VY extends Z0{constructor(J,Q,$){super(new Uint16Array(J),Q,$);this.isFloat16BufferAttribute=!0}getX(J){let Q=P6(this.array[J*this.itemSize]);if(this.normalized)Q=f0(Q,this.array);return Q}setX(J,Q){if(this.normalized)Q=cJ(Q,this.array);return this.array[J*this.itemSize]=p0(Q),this}getY(J){let Q=P6(this.array[J*this.itemSize+1]);if(this.normalized)Q=f0(Q,this.array);return Q}setY(J,Q){if(this.normalized)Q=cJ(Q,this.array);return this.array[J*this.itemSize+1]=p0(Q),this}getZ(J){let Q=P6(this.array[J*this.itemSize+2]);if(this.normalized)Q=f0(Q,this.array);return Q}setZ(J,Q){if(this.normalized)Q=cJ(Q,this.array);return this.array[J*this.itemSize+2]=p0(Q),this}getW(J){let Q=P6(this.array[J*this.itemSize+3]);if(this.normalized)Q=f0(Q,this.array);return Q}setW(J,Q){if(this.normalized)Q=cJ(Q,this.array);return this.array[J*this.itemSize+3]=p0(Q),this}setXY(J,Q,$){if(J*=this.itemSize,this.normalized)Q=cJ(Q,this.array),$=cJ($,this.array);return this.array[J+0]=p0(Q),this.array[J+1]=p0($),this}setXYZ(J,Q,$,Z){if(J*=this.itemSize,this.normalized)Q=cJ(Q,this.array),$=cJ($,this.array),Z=cJ(Z,this.array);return this.array[J+0]=p0(Q),this.array[J+1]=p0($),this.array[J+2]=p0(Z),this}setXYZW(J,Q,$,Z,W){if(J*=this.itemSize,this.normalized)Q=cJ(Q,this.array),$=cJ($,this.array),Z=cJ(Z,this.array),W=cJ(W,this.array);return this.array[J+0]=p0(Q),this.array[J+1]=p0($),this.array[J+2]=p0(Z),this.array[J+3]=p0(W),this}}class BJ extends Z0{constructor(J,Q,$){super(new Float32Array(J),Q,$)}}var eG=0,t0=new hJ,I$=new Q0,f9=new w,c0=new w0,k6=new w0,B0=new w;class nJ extends H8{constructor(){super();this.isBufferGeometry=!0,Object.defineProperty(this,"id",{value:eG++}),this.uuid=n0(),this.name="",this.type="BufferGeometry",this.index=null,this.indirect=null,this.attributes={},this.morphAttributes={},this.morphTargetsRelative=!1,this.groups=[],this.boundingBox=null,this.boundingSphere=null,this.drawRange={start:0,count:1/0},this.userData={}}getIndex(){return this.index}setIndex(J){if(Array.isArray(J))this.index=new((gZ(J))?FQ:RQ)(J,1);else this.index=J;return this}setIndirect(J){return this.indirect=J,this}getIndirect(){return this.indirect}getAttribute(J){return this.attributes[J]}setAttribute(J,Q){return this.attributes[J]=Q,this}deleteAttribute(J){return delete this.attributes[J],this}hasAttribute(J){return this.attributes[J]!==void 0}addGroup(J,Q,$=0){this.groups.push({start:J,count:Q,materialIndex:$})}clearGroups(){this.groups=[]}setDrawRange(J,Q){this.drawRange.start=J,this.drawRange.count=Q}applyMatrix4(J){let Q=this.attributes.position;if(Q!==void 0)Q.applyMatrix4(J),Q.needsUpdate=!0;let $=this.attributes.normal;if($!==void 0){let W=new dJ().getNormalMatrix(J);$.applyNormalMatrix(W),$.needsUpdate=!0}let Z=this.attributes.tangent;if(Z!==void 0)Z.transformDirection(J),Z.needsUpdate=!0;if(this.boundingBox!==null)this.computeBoundingBox();if(this.boundingSphere!==null)this.computeBoundingSphere();return this}applyQuaternion(J){return t0.makeRotationFromQuaternion(J),this.applyMatrix4(t0),this}rotateX(J){return t0.makeRotationX(J),this.applyMatrix4(t0),this}rotateY(J){return t0.makeRotationY(J),this.applyMatrix4(t0),this}rotateZ(J){return t0.makeRotationZ(J),this.applyMatrix4(t0),this}translate(J,Q,$){return t0.makeTranslation(J,Q,$),this.applyMatrix4(t0),this}scale(J,Q,$){return t0.makeScale(J,Q,$),this.applyMatrix4(t0),this}lookAt(J){return I$.lookAt(J),I$.updateMatrix(),this.applyMatrix4(I$.matrix),this}center(){return this.computeBoundingBox(),this.boundingBox.getCenter(f9).negate(),this.translate(f9.x,f9.y,f9.z),this}setFromPoints(J){let Q=this.getAttribute("position");if(Q===void 0){let $=[];for(let Z=0,W=J.length;Z<W;Z++){let K=J[Z];$.push(K.x,K.y,K.z||0)}this.setAttribute("position",new BJ($,3))}else{let $=Math.min(J.length,Q.count);for(let Z=0;Z<$;Z++){let W=J[Z];Q.setXYZ(Z,W.x,W.y,W.z||0)}if(J.length>Q.count)console.warn("THREE.BufferGeometry: Buffer size too small for points data. Use .dispose() and create a new geometry.");Q.needsUpdate=!0}return this}computeBoundingBox(){if(this.boundingBox===null)this.boundingBox=new w0;let J=this.attributes.position,Q=this.morphAttributes.position;if(J&&J.isGLBufferAttribute){console.error("THREE.BufferGeometry.computeBoundingBox(): GLBufferAttribute requires a manual bounding box.",this),this.boundingBox.set(new w(-1/0,-1/0,-1/0),new w(1/0,1/0,1/0));return}if(J!==void 0){if(this.boundingBox.setFromBufferAttribute(J),Q)for(let $=0,Z=Q.length;$<Z;$++){let W=Q[$];if(c0.setFromBufferAttribute(W),this.morphTargetsRelative)B0.addVectors(this.boundingBox.min,c0.min),this.boundingBox.expandByPoint(B0),B0.addVectors(this.boundingBox.max,c0.max),this.boundingBox.expandByPoint(B0);else this.boundingBox.expandByPoint(c0.min),this.boundingBox.expandByPoint(c0.max)}}else this.boundingBox.makeEmpty();if(isNaN(this.boundingBox.min.x)||isNaN(this.boundingBox.min.y)||isNaN(this.boundingBox.min.z))console.error('THREE.BufferGeometry.computeBoundingBox(): Computed min/max have NaN values. The "position" attribute is likely to have NaN values.',this)}computeBoundingSphere(){if(this.boundingSphere===null)this.boundingSphere=new _0;let J=this.attributes.position,Q=this.morphAttributes.position;if(J&&J.isGLBufferAttribute){console.error("THREE.BufferGeometry.computeBoundingSphere(): GLBufferAttribute requires a manual bounding sphere.",this),this.boundingSphere.set(new w,1/0);return}if(J){let $=this.boundingSphere.center;if(c0.setFromBufferAttribute(J),Q)for(let W=0,K=Q.length;W<K;W++){let H=Q[W];if(k6.setFromBufferAttribute(H),this.morphTargetsRelative)B0.addVectors(c0.min,k6.min),c0.expandByPoint(B0),B0.addVectors(c0.max,k6.max),c0.expandByPoint(B0);else c0.expandByPoint(k6.min),c0.expandByPoint(k6.max)}c0.getCenter($);let Z=0;for(let W=0,K=J.count;W<K;W++)B0.fromBufferAttribute(J,W),Z=Math.max(Z,$.distanceToSquared(B0));if(Q)for(let W=0,K=Q.length;W<K;W++){let H=Q[W],Y=this.morphTargetsRelative;for(let X=0,U=H.count;X<U;X++){if(B0.fromBufferAttribute(H,X),Y)f9.fromBufferAttribute(J,X),B0.add(f9);Z=Math.max(Z,$.distanceToSquared(B0))}}if(this.boundingSphere.radius=Math.sqrt(Z),isNaN(this.boundingSphere.radius))console.error('THREE.BufferGeometry.computeBoundingSphere(): Computed radius is NaN. The "position" attribute is likely to have NaN values.',this)}}computeTangents(){let J=this.index,Q=this.attributes;if(J===null||Q.position===void 0||Q.normal===void 0||Q.uv===void 0){console.error("THREE.BufferGeometry: .computeTangents() failed. Missing required attributes (index, position, normal or uv)");return}let{position:$,normal:Z,uv:W}=Q;if(this.hasAttribute("tangent")===!1)this.setAttribute("tangent",new Z0(new Float32Array(4*$.count),4));let K=this.getAttribute("tangent"),H=[],Y=[];for(let C=0;C<$.count;C++)H[C]=new w,Y[C]=new w;let X=new w,U=new w,G=new w,E=new t,N=new t,q=new t,R=new w,F=new w;function O(C,y,z){X.fromBufferAttribute($,C),U.fromBufferAttribute($,y),G.fromBufferAttribute($,z),E.fromBufferAttribute(W,C),N.fromBufferAttribute(W,y),q.fromBufferAttribute(W,z),U.sub(X),G.sub(X),N.sub(E),q.sub(E);let I=1/(N.x*q.y-q.x*N.y);if(!isFinite(I))return;R.copy(U).multiplyScalar(q.y).addScaledVector(G,-N.y).multiplyScalar(I),F.copy(G).multiplyScalar(N.x).addScaledVector(U,-q.x).multiplyScalar(I),H[C].add(R),H[y].add(R),H[z].add(R),Y[C].add(F),Y[y].add(F),Y[z].add(F)}let D=this.groups;if(D.length===0)D=[{start:0,count:J.count}];for(let C=0,y=D.length;C<y;++C){let z=D[C],I=z.start,S=z.count;for(let p=I,d=I+S;p<d;p+=3)O(J.getX(p+0),J.getX(p+1),J.getX(p+2))}let k=new w,M=new w,L=new w,A=new w;function _(C){L.fromBufferAttribute(Z,C),A.copy(L);let y=H[C];k.copy(y),k.sub(L.multiplyScalar(L.dot(y))).normalize(),M.crossVectors(A,y);let I=M.dot(Y[C])<0?-1:1;K.setXYZW(C,k.x,k.y,k.z,I)}for(let C=0,y=D.length;C<y;++C){let z=D[C],I=z.start,S=z.count;for(let p=I,d=I+S;p<d;p+=3)_(J.getX(p+0)),_(J.getX(p+1)),_(J.getX(p+2))}}computeVertexNormals(){let J=this.index,Q=this.getAttribute("position");if(Q!==void 0){let $=this.getAttribute("normal");if($===void 0)$=new Z0(new Float32Array(Q.count*3),3),this.setAttribute("normal",$);else for(let E=0,N=$.count;E<N;E++)$.setXYZ(E,0,0,0);let Z=new w,W=new w,K=new w,H=new w,Y=new w,X=new w,U=new w,G=new w;if(J)for(let E=0,N=J.count;E<N;E+=3){let q=J.getX(E+0),R=J.getX(E+1),F=J.getX(E+2);Z.fromBufferAttribute(Q,q),W.fromBufferAttribute(Q,R),K.fromBufferAttribute(Q,F),U.subVectors(K,W),G.subVectors(Z,W),U.cross(G),H.fromBufferAttribute($,q),Y.fromBufferAttribute($,R),X.fromBufferAttribute($,F),H.add(U),Y.add(U),X.add(U),$.setXYZ(q,H.x,H.y,H.z),$.setXYZ(R,Y.x,Y.y,Y.z),$.setXYZ(F,X.x,X.y,X.z)}else for(let E=0,N=Q.count;E<N;E+=3)Z.fromBufferAttribute(Q,E+0),W.fromBufferAttribute(Q,E+1),K.fromBufferAttribute(Q,E+2),U.subVectors(K,W),G.subVectors(Z,W),U.cross(G),$.setXYZ(E+0,U.x,U.y,U.z),$.setXYZ(E+1,U.x,U.y,U.z),$.setXYZ(E+2,U.x,U.y,U.z);this.normalizeNormals(),$.needsUpdate=!0}}normalizeNormals(){let J=this.attributes.normal;for(let Q=0,$=J.count;Q<$;Q++)B0.fromBufferAttribute(J,Q),B0.normalize(),J.setXYZ(Q,B0.x,B0.y,B0.z)}toNonIndexed(){function J(H,Y){let{array:X,itemSize:U,normalized:G}=H,E=new X.constructor(Y.length*U),N=0,q=0;for(let R=0,F=Y.length;R<F;R++){if(H.isInterleavedBufferAttribute)N=Y[R]*H.data.stride+H.offset;else N=Y[R]*U;for(let O=0;O<U;O++)E[q++]=X[N++]}return new Z0(E,U,G)}if(this.index===null)return console.warn("THREE.BufferGeometry.toNonIndexed(): BufferGeometry is already non-indexed."),this;let Q=new nJ,$=this.index.array,Z=this.attributes;for(let H in Z){let Y=Z[H],X=J(Y,$);Q.setAttribute(H,X)}let W=this.morphAttributes;for(let H in W){let Y=[],X=W[H];for(let U=0,G=X.length;U<G;U++){let E=X[U],N=J(E,$);Y.push(N)}Q.morphAttributes[H]=Y}Q.morphTargetsRelative=this.morphTargetsRelative;let K=this.groups;for(let H=0,Y=K.length;H<Y;H++){let X=K[H];Q.addGroup(X.start,X.count,X.materialIndex)}return Q}toJSON(){let J={metadata:{version:4.7,type:"BufferGeometry",generator:"BufferGeometry.toJSON"}};if(J.uuid=this.uuid,J.type=this.type,this.name!=="")J.name=this.name;if(Object.keys(this.userData).length>0)J.userData=this.userData;if(this.parameters!==void 0){let Y=this.parameters;for(let X in Y)if(Y[X]!==void 0)J[X]=Y[X];return J}J.data={attributes:{}};let Q=this.index;if(Q!==null)J.data.index={type:Q.array.constructor.name,array:Array.prototype.slice.call(Q.array)};let $=this.attributes;for(let Y in $){let X=$[Y];J.data.attributes[Y]=X.toJSON(J.data)}let Z={},W=!1;for(let Y in this.morphAttributes){let X=this.morphAttributes[Y],U=[];for(let G=0,E=X.length;G<E;G++){let N=X[G];U.push(N.toJSON(J.data))}if(U.length>0)Z[Y]=U,W=!0}if(W)J.data.morphAttributes=Z,J.data.morphTargetsRelative=this.morphTargetsRelative;let K=this.groups;if(K.length>0)J.data.groups=JSON.parse(JSON.stringify(K));let H=this.boundingSphere;if(H!==null)J.data.boundingSphere=H.toJSON();return J}clone(){return new this.constructor().copy(this)}copy(J){this.index=null,this.attributes={},this.morphAttributes={},this.groups=[],this.boundingBox=null,this.boundingSphere=null;let Q={};this.name=J.name;let $=J.index;if($!==null)this.setIndex($.clone());let Z=J.attributes;for(let X in Z){let U=Z[X];this.setAttribute(X,U.clone(Q))}let W=J.morphAttributes;for(let X in W){let U=[],G=W[X];for(let E=0,N=G.length;E<N;E++)U.push(G[E].clone(Q));this.morphAttributes[X]=U}this.morphTargetsRelative=J.morphTargetsRelative;let K=J.groups;for(let X=0,U=K.length;X<U;X++){let G=K[X];this.addGroup(G.start,G.count,G.materialIndex)}let H=J.boundingBox;if(H!==null)this.boundingBox=H.clone();let Y=J.boundingSphere;if(Y!==null)this.boundingSphere=Y.clone();return this.drawRange.start=J.drawRange.start,this.drawRange.count=J.drawRange.count,this.userData=J.userData,this}dispose(){this.dispatchEvent({type:"dispose"})}}var NK=new hJ,r8=new F9,F7=new _0,qK=new w,M7=new w,k7=new w,V7=new w,_$=new w,L7=new w,DK=new w,z7=new w;class k0 extends Q0{constructor(J=new nJ,Q=new S8){super();this.isMesh=!0,this.type="Mesh",this.geometry=J,this.material=Q,this.morphTargetDictionary=void 0,this.morphTargetInfluences=void 0,this.count=1,this.updateMorphTargets()}copy(J,Q){if(super.copy(J,Q),J.morphTargetInfluences!==void 0)this.morphTargetInfluences=J.morphTargetInfluences.slice();if(J.morphTargetDictionary!==void 0)this.morphTargetDictionary=Object.assign({},J.morphTargetDictionary);return this.material=Array.isArray(J.material)?J.material.slice():J.material,this.geometry=J.geometry,this}updateMorphTargets(){let Q=this.geometry.morphAttributes,$=Object.keys(Q);if($.length>0){let Z=Q[$[0]];if(Z!==void 0){this.morphTargetInfluences=[],this.morphTargetDictionary={};for(let W=0,K=Z.length;W<K;W++){let H=Z[W].name||String(W);this.morphTargetInfluences.push(0),this.morphTargetDictionary[H]=W}}}}getVertexPosition(J,Q){let $=this.geometry,Z=$.attributes.position,W=$.morphAttributes.position,K=$.morphTargetsRelative;Q.fromBufferAttribute(Z,J);let H=this.morphTargetInfluences;if(W&&H){L7.set(0,0,0);for(let Y=0,X=W.length;Y<X;Y++){let U=H[Y],G=W[Y];if(U===0)continue;if(_$.fromBufferAttribute(G,J),K)L7.addScaledVector(_$,U);else L7.addScaledVector(_$.sub(Q),U)}Q.add(L7)}return Q}raycast(J,Q){let $=this.geometry,Z=this.material,W=this.matrixWorld;if(Z===void 0)return;if($.boundingSphere===null)$.computeBoundingSphere();if(F7.copy($.boundingSphere),F7.applyMatrix4(W),r8.copy(J.ray).recast(J.near),F7.containsPoint(r8.origin)===!1){if(r8.intersectSphere(F7,qK)===null)return;if(r8.origin.distanceToSquared(qK)>(J.far-J.near)**2)return}if(NK.copy(W).invert(),r8.copy(J.ray).applyMatrix4(NK),$.boundingBox!==null){if(r8.intersectsBox($.boundingBox)===!1)return}this._computeIntersections(J,Q,r8)}_computeIntersections(J,Q,$){let Z,W=this.geometry,K=this.material,H=W.index,Y=W.attributes.position,X=W.attributes.uv,U=W.attributes.uv1,G=W.attributes.normal,E=W.groups,N=W.drawRange;if(H!==null)if(Array.isArray(K))for(let q=0,R=E.length;q<R;q++){let F=E[q],O=K[F.materialIndex],D=Math.max(F.start,N.start),k=Math.min(H.count,Math.min(F.start+F.count,N.start+N.count));for(let M=D,L=k;M<L;M+=3){let A=H.getX(M),_=H.getX(M+1),C=H.getX(M+2);if(Z=B7(this,O,J,$,X,U,G,A,_,C),Z)Z.faceIndex=Math.floor(M/3),Z.face.materialIndex=F.materialIndex,Q.push(Z)}}else{let q=Math.max(0,N.start),R=Math.min(H.count,N.start+N.count);for(let F=q,O=R;F<O;F+=3){let D=H.getX(F),k=H.getX(F+1),M=H.getX(F+2);if(Z=B7(this,K,J,$,X,U,G,D,k,M),Z)Z.faceIndex=Math.floor(F/3),Q.push(Z)}}else if(Y!==void 0)if(Array.isArray(K))for(let q=0,R=E.length;q<R;q++){let F=E[q],O=K[F.materialIndex],D=Math.max(F.start,N.start),k=Math.min(Y.count,Math.min(F.start+F.count,N.start+N.count));for(let M=D,L=k;M<L;M+=3){let A=M,_=M+1,C=M+2;if(Z=B7(this,O,J,$,X,U,G,A,_,C),Z)Z.faceIndex=Math.floor(M/3),Z.face.materialIndex=F.materialIndex,Q.push(Z)}}else{let q=Math.max(0,N.start),R=Math.min(Y.count,N.start+N.count);for(let F=q,O=R;F<O;F+=3){let D=F,k=F+1,M=F+2;if(Z=B7(this,K,J,$,X,U,G,D,k,M),Z)Z.faceIndex=Math.floor(F/3),Q.push(Z)}}}}function JE(J,Q,$,Z,W,K,H,Y){let X;if(Q.side===1)X=Z.intersectTriangle(H,K,W,!0,Y);else X=Z.intersectTriangle(W,K,H,Q.side===0,Y);if(X===null)return null;z7.copy(Y),z7.applyMatrix4(J.matrixWorld);let U=$.ray.origin.distanceTo(z7);if(U<$.near||U>$.far)return null;return{distance:U,point:z7.clone(),object:J}}function B7(J,Q,$,Z,W,K,H,Y,X,U){J.getVertexPosition(Y,M7),J.getVertexPosition(X,k7),J.getVertexPosition(U,V7);let G=JE(J,Q,$,Z,M7,k7,V7,DK);if(G){let E=new w;if(m0.getBarycoord(DK,M7,k7,V7,E),W)G.uv=m0.getInterpolatedAttribute(W,Y,X,U,E,new t);if(K)G.uv1=m0.getInterpolatedAttribute(K,Y,X,U,E,new t);if(H){if(G.normal=m0.getInterpolatedAttribute(H,Y,X,U,E,new w),G.normal.dot(Z.direction)>0)G.normal.multiplyScalar(-1)}let N={a:Y,b:X,c:U,normal:new w,materialIndex:0};m0.getNormal(M7,k7,V7,N.normal),G.face=N,G.barycoord=E}return G}class M9 extends nJ{constructor(J=1,Q=1,$=1,Z=1,W=1,K=1){super();this.type="BoxGeometry",this.parameters={width:J,height:Q,depth:$,widthSegments:Z,heightSegments:W,depthSegments:K};let H=this;Z=Math.floor(Z),W=Math.floor(W),K=Math.floor(K);let Y=[],X=[],U=[],G=[],E=0,N=0;q("z","y","x",-1,-1,$,Q,J,K,W,0),q("z","y","x",1,-1,$,Q,-J,K,W,1),q("x","z","y",1,1,J,$,Q,Z,K,2),q("x","z","y",1,-1,J,$,-Q,Z,K,3),q("x","y","z",1,-1,J,Q,$,Z,W,4),q("x","y","z",-1,-1,J,Q,-$,Z,W,5),this.setIndex(Y),this.setAttribute("position",new BJ(X,3)),this.setAttribute("normal",new BJ(U,3)),this.setAttribute("uv",new BJ(G,2));function q(R,F,O,D,k,M,L,A,_,C,y){let z=M/_,I=L/C,S=M/2,p=L/2,d=A/2,x=_+1,o=C+1,l=0,QJ=0,m=new w;for(let EJ=0;EJ<o;EJ++){let NJ=EJ*I-p;for(let SJ=0;SJ<x;SJ++){let mJ=SJ*z-S;m[R]=mJ*D,m[F]=NJ*k,m[O]=d,X.push(m.x,m.y,m.z),m[R]=0,m[F]=0,m[O]=A>0?1:-1,U.push(m.x,m.y,m.z),G.push(SJ/_),G.push(1-EJ/C),l+=1}}for(let EJ=0;EJ<C;EJ++)for(let NJ=0;NJ<_;NJ++){let SJ=E+NJ+x*EJ,mJ=E+NJ+x*(EJ+1),U0=E+(NJ+1)+x*(EJ+1),rJ=E+(NJ+1)+x*EJ;Y.push(SJ,mJ,rJ),Y.push(mJ,U0,rJ),QJ+=6}H.addGroup(N,QJ,y),N+=QJ,E+=l}}copy(J){return super.copy(J),this.parameters=Object.assign({},J.parameters),this}static fromJSON(J){return new M9(J.width,J.height,J.depth,J.widthSegments,J.heightSegments,J.depthSegments)}}function k9(J){let Q={};for(let $ in J){Q[$]={};for(let Z in J[$]){let W=J[$][Z];if(W&&(W.isColor||W.isMatrix3||W.isMatrix4||W.isVector2||W.isVector3||W.isVector4||W.isTexture||W.isQuaternion))if(W.isRenderTargetTexture)console.warn("UniformsUtils: Textures of render targets cannot be cloned via cloneUniforms() or mergeUniforms()."),Q[$][Z]=null;else Q[$][Z]=W.clone();else if(Array.isArray(W))Q[$][Z]=W.slice();else Q[$][Z]=W}}return Q}function S0(J){let Q={};for(let $=0;$<J.length;$++){let Z=k9(J[$]);for(let W in Z)Q[W]=Z[W]}return Q}function QE(J){let Q=[];for(let $=0;$<J.length;$++)Q.push(J[$].clone());return Q}function mZ(J){let Q=J.getRenderTarget();if(Q===null)return J.outputColorSpace;if(Q.isXRRenderTarget===!0)return Q.texture.colorSpace;return tJ.workingColorSpace}var LY={clone:k9,merge:S0},$E=`void main() {
	gl_Position = projectionMatrix * modelViewMatrix * vec4( position, 1.0 );
}`,ZE=`void main() {
	gl_FragColor = vec4( 1.0, 0.0, 0.0, 1.0 );
}`;class e0 extends C0{constructor(J){super();if(this.isShaderMaterial=!0,this.type="ShaderMaterial",this.defines={},this.uniforms={},this.uniformsGroups=[],this.vertexShader=$E,this.fragmentShader=ZE,this.linewidth=1,this.wireframe=!1,this.wireframeLinewidth=1,this.fog=!1,this.lights=!1,this.clipping=!1,this.forceSinglePass=!0,this.extensions={clipCullDistance:!1,multiDraw:!1},this.defaultAttributeValues={color:[1,1,1],uv:[0,0],uv1:[0,0]},this.index0AttributeName=void 0,this.uniformsNeedUpdate=!1,this.glslVersion=null,J!==void 0)this.setValues(J)}copy(J){return super.copy(J),this.fragmentShader=J.fragmentShader,this.vertexShader=J.vertexShader,this.uniforms=k9(J.uniforms),this.uniformsGroups=QE(J.uniformsGroups),this.defines=Object.assign({},J.defines),this.wireframe=J.wireframe,this.wireframeLinewidth=J.wireframeLinewidth,this.fog=J.fog,this.lights=J.lights,this.clipping=J.clipping,this.extensions=Object.assign({},J.extensions),this.glslVersion=J.glslVersion,this}toJSON(J){let Q=super.toJSON(J);Q.glslVersion=this.glslVersion,Q.uniforms={};for(let Z in this.uniforms){let K=this.uniforms[Z].value;if(K&&K.isTexture)Q.uniforms[Z]={type:"t",value:K.toJSON(J).uuid};else if(K&&K.isColor)Q.uniforms[Z]={type:"c",value:K.getHex()};else if(K&&K.isVector2)Q.uniforms[Z]={type:"v2",value:K.toArray()};else if(K&&K.isVector3)Q.uniforms[Z]={type:"v3",value:K.toArray()};else if(K&&K.isVector4)Q.uniforms[Z]={type:"v4",value:K.toArray()};else if(K&&K.isMatrix3)Q.uniforms[Z]={type:"m3",value:K.toArray()};else if(K&&K.isMatrix4)Q.uniforms[Z]={type:"m4",value:K.toArray()};else Q.uniforms[Z]={value:K}}if(Object.keys(this.defines).length>0)Q.defines=this.defines;Q.vertexShader=this.vertexShader,Q.fragmentShader=this.fragmentShader,Q.lights=this.lights,Q.clipping=this.clipping;let $={};for(let Z in this.extensions)if(this.extensions[Z]===!0)$[Z]=!0;if(Object.keys($).length>0)Q.extensions=$;return Q}}class i6 extends Q0{constructor(){super();this.isCamera=!0,this.type="Camera",this.matrixWorldInverse=new hJ,this.projectionMatrix=new hJ,this.projectionMatrixInverse=new hJ,this.coordinateSystem=2000,this._reversedDepth=!1}get reversedDepth(){return this._reversedDepth}copy(J,Q){return super.copy(J,Q),this.matrixWorldInverse.copy(J.matrixWorldInverse),this.projectionMatrix.copy(J.projectionMatrix),this.projectionMatrixInverse.copy(J.projectionMatrixInverse),this.coordinateSystem=J.coordinateSystem,this}getWorldDirection(J){return super.getWorldDirection(J).negate()}updateMatrixWorld(J){super.updateMatrixWorld(J),this.matrixWorldInverse.copy(this.matrixWorld).invert()}updateWorldMatrix(J,Q){super.updateWorldMatrix(J,Q),this.matrixWorldInverse.copy(this.matrixWorld).invert()}clone(){return new this.constructor().copy(this)}}var x8=new w,OK=new t,RK=new t;class I0 extends i6{constructor(J=50,Q=1,$=0.1,Z=2000){super();this.isPerspectiveCamera=!0,this.type="PerspectiveCamera",this.fov=J,this.zoom=1,this.near=$,this.far=Z,this.focus=10,this.aspect=Q,this.view=null,this.filmGauge=35,this.filmOffset=0,this.updateProjectionMatrix()}copy(J,Q){return super.copy(J,Q),this.fov=J.fov,this.zoom=J.zoom,this.near=J.near,this.far=J.far,this.focus=J.focus,this.aspect=J.aspect,this.view=J.view===null?null:Object.assign({},J.view),this.filmGauge=J.filmGauge,this.filmOffset=J.filmOffset,this}setFocalLength(J){let Q=0.5*this.getFilmHeight()/J;this.fov=G9*2*Math.atan(Q),this.updateProjectionMatrix()}getFocalLength(){let J=Math.tan(U9*0.5*this.fov);return 0.5*this.getFilmHeight()/J}getEffectiveFOV(){return G9*2*Math.atan(Math.tan(U9*0.5*this.fov)/this.zoom)}getFilmWidth(){return this.filmGauge*Math.min(this.aspect,1)}getFilmHeight(){return this.filmGauge/Math.max(this.aspect,1)}getViewBounds(J,Q,$){x8.set(-1,-1,0.5).applyMatrix4(this.projectionMatrixInverse),Q.set(x8.x,x8.y).multiplyScalar(-J/x8.z),x8.set(1,1,0.5).applyMatrix4(this.projectionMatrixInverse),$.set(x8.x,x8.y).multiplyScalar(-J/x8.z)}getViewSize(J,Q){return this.getViewBounds(J,OK,RK),Q.subVectors(RK,OK)}setViewOffset(J,Q,$,Z,W,K){if(this.aspect=J/Q,this.view===null)this.view={enabled:!0,fullWidth:1,fullHeight:1,offsetX:0,offsetY:0,width:1,height:1};this.view.enabled=!0,this.view.fullWidth=J,this.view.fullHeight=Q,this.view.offsetX=$,this.view.offsetY=Z,this.view.width=W,this.view.height=K,this.updateProjectionMatrix()}clearViewOffset(){if(this.view!==null)this.view.enabled=!1;this.updateProjectionMatrix()}updateProjectionMatrix(){let J=this.near,Q=J*Math.tan(U9*0.5*this.fov)/this.zoom,$=2*Q,Z=this.aspect*$,W=-0.5*Z,K=this.view;if(this.view!==null&&this.view.enabled){let{fullWidth:Y,fullHeight:X}=K;W+=K.offsetX*Z/Y,Q-=K.offsetY*$/X,Z*=K.width/Y,$*=K.height/X}let H=this.filmOffset;if(H!==0)W+=J*H/this.getFilmWidth();this.projectionMatrix.makePerspective(W,W+Z,Q,Q-$,J,this.far,this.coordinateSystem,this.reversedDepth),this.projectionMatrixInverse.copy(this.projectionMatrix).invert()}toJSON(J){let Q=super.toJSON(J);if(Q.object.fov=this.fov,Q.object.zoom=this.zoom,Q.object.near=this.near,Q.object.far=this.far,Q.object.focus=this.focus,Q.object.aspect=this.aspect,this.view!==null)Q.object.view=Object.assign({},this.view);return Q.object.filmGauge=this.filmGauge,Q.object.filmOffset=this.filmOffset,Q}}var b9=-90,h9=1;class dZ extends Q0{constructor(J,Q,$){super();this.type="CubeCamera",this.renderTarget=$,this.coordinateSystem=null,this.activeMipmapLevel=0;let Z=new I0(b9,h9,J,Q);Z.layers=this.layers,this.add(Z);let W=new I0(b9,h9,J,Q);W.layers=this.layers,this.add(W);let K=new I0(b9,h9,J,Q);K.layers=this.layers,this.add(K);let H=new I0(b9,h9,J,Q);H.layers=this.layers,this.add(H);let Y=new I0(b9,h9,J,Q);Y.layers=this.layers,this.add(Y);let X=new I0(b9,h9,J,Q);X.layers=this.layers,this.add(X)}updateCoordinateSystem(){let J=this.coordinateSystem,Q=this.children.concat(),[$,Z,W,K,H,Y]=Q;for(let X of Q)this.remove(X);if(J===2000)$.up.set(0,1,0),$.lookAt(1,0,0),Z.up.set(0,1,0),Z.lookAt(-1,0,0),W.up.set(0,0,-1),W.lookAt(0,1,0),K.up.set(0,0,1),K.lookAt(0,-1,0),H.up.set(0,1,0),H.lookAt(0,0,1),Y.up.set(0,1,0),Y.lookAt(0,0,-1);else if(J===2001)$.up.set(0,-1,0),$.lookAt(-1,0,0),Z.up.set(0,-1,0),Z.lookAt(1,0,0),W.up.set(0,0,1),W.lookAt(0,1,0),K.up.set(0,0,-1),K.lookAt(0,-1,0),H.up.set(0,-1,0),H.lookAt(0,0,1),Y.up.set(0,-1,0),Y.lookAt(0,0,-1);else throw Error("THREE.CubeCamera.updateCoordinateSystem(): Invalid coordinate system: "+J);for(let X of Q)this.add(X),X.updateMatrixWorld()}update(J,Q){if(this.parent===null)this.updateMatrixWorld();let{renderTarget:$,activeMipmapLevel:Z}=this;if(this.coordinateSystem!==J.coordinateSystem)this.coordinateSystem=J.coordinateSystem,this.updateCoordinateSystem();let[W,K,H,Y,X,U]=this.children,G=J.getRenderTarget(),E=J.getActiveCubeFace(),N=J.getActiveMipmapLevel(),q=J.xr.enabled;J.xr.enabled=!1;let R=$.texture.generateMipmaps;$.texture.generateMipmaps=!1,J.setRenderTarget($,0,Z),J.render(Q,W),J.setRenderTarget($,1,Z),J.render(Q,K),J.setRenderTarget($,2,Z),J.render(Q,H),J.setRenderTarget($,3,Z),J.render(Q,Y),J.setRenderTarget($,4,Z),J.render(Q,X),$.texture.generateMipmaps=R,J.setRenderTarget($,5,Z),J.render(Q,U),J.setRenderTarget(G,E,N),J.xr.enabled=q,$.texture.needsPMREMUpdate=!0}}class X6 extends F0{constructor(J=[],Q=301,$,Z,W,K,H,Y,X,U){super(J,Q,$,Z,W,K,H,Y,X,U);this.isCubeTexture=!0,this.flipY=!1}get images(){return this.image}set images(J){this.image=J}}class lZ extends Y8{constructor(J=1,Q={}){super(J,J,Q);this.isWebGLCubeRenderTarget=!0;let $={width:J,height:J,depth:1},Z=[$,$,$,$,$,$];this.texture=new X6(Z),this._setTextureOptions(Q),this.texture.isRenderTargetTexture=!0}fromEquirectangularTexture(J,Q){this.texture.type=Q.type,this.texture.colorSpace=Q.colorSpace,this.texture.generateMipmaps=Q.generateMipmaps,this.texture.minFilter=Q.minFilter,this.texture.magFilter=Q.magFilter;let $={uniforms:{tEquirect:{value:null}},vertexShader:`

				varying vec3 vWorldDirection;

				vec3 transformDirection( in vec3 dir, in mat4 matrix ) {

					return normalize( ( matrix * vec4( dir, 0.0 ) ).xyz );

				}

				void main() {

					vWorldDirection = transformDirection( position, modelMatrix );

					#include <begin_vertex>
					#include <project_vertex>

				}
			`,fragmentShader:`

				uniform sampler2D tEquirect;

				varying vec3 vWorldDirection;

				#include <common>

				void main() {

					vec3 direction = normalize( vWorldDirection );

					vec2 sampleUV = equirectUv( direction );

					gl_FragColor = texture2D( tEquirect, sampleUV );

				}
			`},Z=new M9(5,5,5),W=new e0({name:"CubemapFromEquirect",uniforms:k9($.uniforms),vertexShader:$.vertexShader,fragmentShader:$.fragmentShader,side:1,blending:0});W.uniforms.tEquirect.value=Q;let K=new k0(Z,W),H=Q.minFilter;if(Q.minFilter===1008)Q.minFilter=1006;return new dZ(1,10,this).update(J,K),Q.minFilter=H,K.geometry.dispose(),K.material.dispose(),this}clear(J,Q=!0,$=!0,Z=!0){let W=J.getRenderTarget();for(let K=0;K<6;K++)J.setRenderTarget(this,K),J.clear(Q,$,Z);J.setRenderTarget(W)}}class Y9 extends Q0{constructor(){super();this.isGroup=!0,this.type="Group"}}var WE={type:"move"};class o6{constructor(){this._targetRay=null,this._grip=null,this._hand=null}getHandSpace(){if(this._hand===null)this._hand=new Y9,this._hand.matrixAutoUpdate=!1,this._hand.visible=!1,this._hand.joints={},this._hand.inputState={pinching:!1};return this._hand}getTargetRaySpace(){if(this._targetRay===null)this._targetRay=new Y9,this._targetRay.matrixAutoUpdate=!1,this._targetRay.visible=!1,this._targetRay.hasLinearVelocity=!1,this._targetRay.linearVelocity=new w,this._targetRay.hasAngularVelocity=!1,this._targetRay.angularVelocity=new w;return this._targetRay}getGripSpace(){if(this._grip===null)this._grip=new Y9,this._grip.matrixAutoUpdate=!1,this._grip.visible=!1,this._grip.hasLinearVelocity=!1,this._grip.linearVelocity=new w,this._grip.hasAngularVelocity=!1,this._grip.angularVelocity=new w;return this._grip}dispatchEvent(J){if(this._targetRay!==null)this._targetRay.dispatchEvent(J);if(this._grip!==null)this._grip.dispatchEvent(J);if(this._hand!==null)this._hand.dispatchEvent(J);return this}connect(J){if(J&&J.hand){let Q=this._hand;if(Q)for(let $ of J.hand.values())this._getHandJoint(Q,$)}return this.dispatchEvent({type:"connected",data:J}),this}disconnect(J){if(this.dispatchEvent({type:"disconnected",data:J}),this._targetRay!==null)this._targetRay.visible=!1;if(this._grip!==null)this._grip.visible=!1;if(this._hand!==null)this._hand.visible=!1;return this}update(J,Q,$){let Z=null,W=null,K=null,H=this._targetRay,Y=this._grip,X=this._hand;if(J&&Q.session.visibilityState!=="visible-blurred"){if(X&&J.hand){K=!0;for(let R of J.hand.values()){let F=Q.getJointPose(R,$),O=this._getHandJoint(X,R);if(F!==null)O.matrix.fromArray(F.transform.matrix),O.matrix.decompose(O.position,O.rotation,O.scale),O.matrixWorldNeedsUpdate=!0,O.jointRadius=F.radius;O.visible=F!==null}let U=X.joints["index-finger-tip"],G=X.joints["thumb-tip"],E=U.position.distanceTo(G.position),N=0.02,q=0.005;if(X.inputState.pinching&&E>N+q)X.inputState.pinching=!1,this.dispatchEvent({type:"pinchend",handedness:J.handedness,target:this});else if(!X.inputState.pinching&&E<=N-q)X.inputState.pinching=!0,this.dispatchEvent({type:"pinchstart",handedness:J.handedness,target:this})}else if(Y!==null&&J.gripSpace){if(W=Q.getPose(J.gripSpace,$),W!==null){if(Y.matrix.fromArray(W.transform.matrix),Y.matrix.decompose(Y.position,Y.rotation,Y.scale),Y.matrixWorldNeedsUpdate=!0,W.linearVelocity)Y.hasLinearVelocity=!0,Y.linearVelocity.copy(W.linearVelocity);else Y.hasLinearVelocity=!1;if(W.angularVelocity)Y.hasAngularVelocity=!0,Y.angularVelocity.copy(W.angularVelocity);else Y.hasAngularVelocity=!1}}if(H!==null){if(Z=Q.getPose(J.targetRaySpace,$),Z===null&&W!==null)Z=W;if(Z!==null){if(H.matrix.fromArray(Z.transform.matrix),H.matrix.decompose(H.position,H.rotation,H.scale),H.matrixWorldNeedsUpdate=!0,Z.linearVelocity)H.hasLinearVelocity=!0,H.linearVelocity.copy(Z.linearVelocity);else H.hasLinearVelocity=!1;if(Z.angularVelocity)H.hasAngularVelocity=!0,H.angularVelocity.copy(Z.angularVelocity);else H.hasAngularVelocity=!1;this.dispatchEvent(WE)}}}if(H!==null)H.visible=Z!==null;if(Y!==null)Y.visible=W!==null;if(X!==null)X.visible=K!==null;return this}_getHandJoint(J,Q){if(J.joints[Q.jointName]===void 0){let $=new Y9;$.matrixAutoUpdate=!1,$.visible=!1,J.joints[Q.jointName]=$,J.add($)}return J.joints[Q.jointName]}}class MQ{constructor(J,Q=0.00025){this.isFogExp2=!0,this.name="",this.color=new kJ(J),this.density=Q}clone(){return new MQ(this.color,this.density)}toJSON(){return{type:"FogExp2",name:this.name,color:this.color.getHex(),density:this.density}}}class kQ{constructor(J,Q=1,$=1000){this.isFog=!0,this.name="",this.color=new kJ(J),this.near=Q,this.far=$}clone(){return new kQ(this.color,this.near,this.far)}toJSON(){return{type:"Fog",name:this.name,color:this.color.getHex(),near:this.near,far:this.far}}}class uZ extends Q0{constructor(){super();if(this.isScene=!0,this.type="Scene",this.background=null,this.environment=null,this.fog=null,this.backgroundBlurriness=0,this.backgroundIntensity=1,this.backgroundRotation=new s0,this.environmentIntensity=1,this.environmentRotation=new s0,this.overrideMaterial=null,typeof __THREE_DEVTOOLS__<"u")__THREE_DEVTOOLS__.dispatchEvent(new CustomEvent("observe",{detail:this}))}copy(J,Q){if(super.copy(J,Q),J.background!==null)this.background=J.background.clone();if(J.environment!==null)this.environment=J.environment.clone();if(J.fog!==null)this.fog=J.fog.clone();if(this.backgroundBlurriness=J.backgroundBlurriness,this.backgroundIntensity=J.backgroundIntensity,this.backgroundRotation.copy(J.backgroundRotation),this.environmentIntensity=J.environmentIntensity,this.environmentRotation.copy(J.environmentRotation),J.overrideMaterial!==null)this.overrideMaterial=J.overrideMaterial.clone();return this.matrixAutoUpdate=J.matrixAutoUpdate,this}toJSON(J){let Q=super.toJSON(J);if(this.fog!==null)Q.object.fog=this.fog.toJSON();if(this.backgroundBlurriness>0)Q.object.backgroundBlurriness=this.backgroundBlurriness;if(this.backgroundIntensity!==1)Q.object.backgroundIntensity=this.backgroundIntensity;if(Q.object.backgroundRotation=this.backgroundRotation.toArray(),this.environmentIntensity!==1)Q.object.environmentIntensity=this.environmentIntensity;return Q.object.environmentRotation=this.environmentRotation.toArray(),Q}}class a6{constructor(J,Q){this.isInterleavedBuffer=!0,this.array=J,this.stride=Q,this.count=J!==void 0?J.length/Q:0,this.usage=35044,this.updateRanges=[],this.version=0,this.uuid=n0()}onUploadCallback(){}set needsUpdate(J){if(J===!0)this.version++}setUsage(J){return this.usage=J,this}addUpdateRange(J,Q){this.updateRanges.push({start:J,count:Q})}clearUpdateRanges(){this.updateRanges.length=0}copy(J){return this.array=new J.array.constructor(J.array),this.count=J.count,this.stride=J.stride,this.usage=J.usage,this}copyAt(J,Q,$){J*=this.stride,$*=Q.stride;for(let Z=0,W=this.stride;Z<W;Z++)this.array[J+Z]=Q.array[$+Z];return this}set(J,Q=0){return this.array.set(J,Q),this}clone(J){if(J.arrayBuffers===void 0)J.arrayBuffers={};if(this.array.buffer._uuid===void 0)this.array.buffer._uuid=n0();if(J.arrayBuffers[this.array.buffer._uuid]===void 0)J.arrayBuffers[this.array.buffer._uuid]=this.array.slice(0).buffer;let Q=new this.array.constructor(J.arrayBuffers[this.array.buffer._uuid]),$=new this.constructor(Q,this.stride);return $.setUsage(this.usage),$}onUpload(J){return this.onUploadCallback=J,this}toJSON(J){if(J.arrayBuffers===void 0)J.arrayBuffers={};if(this.array.buffer._uuid===void 0)this.array.buffer._uuid=n0();if(J.arrayBuffers[this.array.buffer._uuid]===void 0)J.arrayBuffers[this.array.buffer._uuid]=Array.from(new Uint32Array(this.array.buffer));return{uuid:this.uuid,buffer:this.array.buffer._uuid,type:this.array.constructor.name,stride:this.stride}}}var v0=new w;class E9{constructor(J,Q,$,Z=!1){this.isInterleavedBufferAttribute=!0,this.name="",this.data=J,this.itemSize=Q,this.offset=$,this.normalized=Z}get count(){return this.data.count}get array(){return this.data.array}set needsUpdate(J){this.data.needsUpdate=J}applyMatrix4(J){for(let Q=0,$=this.data.count;Q<$;Q++)v0.fromBufferAttribute(this,Q),v0.applyMatrix4(J),this.setXYZ(Q,v0.x,v0.y,v0.z);return this}applyNormalMatrix(J){for(let Q=0,$=this.count;Q<$;Q++)v0.fromBufferAttribute(this,Q),v0.applyNormalMatrix(J),this.setXYZ(Q,v0.x,v0.y,v0.z);return this}transformDirection(J){for(let Q=0,$=this.count;Q<$;Q++)v0.fromBufferAttribute(this,Q),v0.transformDirection(J),this.setXYZ(Q,v0.x,v0.y,v0.z);return this}getComponent(J,Q){let $=this.array[J*this.data.stride+this.offset+Q];if(this.normalized)$=f0($,this.array);return $}setComponent(J,Q,$){if(this.normalized)$=cJ($,this.array);return this.data.array[J*this.data.stride+this.offset+Q]=$,this}setX(J,Q){if(this.normalized)Q=cJ(Q,this.array);return this.data.array[J*this.data.stride+this.offset]=Q,this}setY(J,Q){if(this.normalized)Q=cJ(Q,this.array);return this.data.array[J*this.data.stride+this.offset+1]=Q,this}setZ(J,Q){if(this.normalized)Q=cJ(Q,this.array);return this.data.array[J*this.data.stride+this.offset+2]=Q,this}setW(J,Q){if(this.normalized)Q=cJ(Q,this.array);return this.data.array[J*this.data.stride+this.offset+3]=Q,this}getX(J){let Q=this.data.array[J*this.data.stride+this.offset];if(this.normalized)Q=f0(Q,this.array);return Q}getY(J){let Q=this.data.array[J*this.data.stride+this.offset+1];if(this.normalized)Q=f0(Q,this.array);return Q}getZ(J){let Q=this.data.array[J*this.data.stride+this.offset+2];if(this.normalized)Q=f0(Q,this.array);return Q}getW(J){let Q=this.data.array[J*this.data.stride+this.offset+3];if(this.normalized)Q=f0(Q,this.array);return Q}setXY(J,Q,$){if(J=J*this.data.stride+this.offset,this.normalized)Q=cJ(Q,this.array),$=cJ($,this.array);return this.data.array[J+0]=Q,this.data.array[J+1]=$,this}setXYZ(J,Q,$,Z){if(J=J*this.data.stride+this.offset,this.normalized)Q=cJ(Q,this.array),$=cJ($,this.array),Z=cJ(Z,this.array);return this.data.array[J+0]=Q,this.data.array[J+1]=$,this.data.array[J+2]=Z,this}setXYZW(J,Q,$,Z,W){if(J=J*this.data.stride+this.offset,this.normalized)Q=cJ(Q,this.array),$=cJ($,this.array),Z=cJ(Z,this.array),W=cJ(W,this.array);return this.data.array[J+0]=Q,this.data.array[J+1]=$,this.data.array[J+2]=Z,this.data.array[J+3]=W,this}clone(J){if(J===void 0){console.log("THREE.InterleavedBufferAttribute.clone(): Cloning an interleaved buffer attribute will de-interleave buffer data.");let Q=[];for(let $=0;$<this.count;$++){let Z=$*this.data.stride+this.offset;for(let W=0;W<this.itemSize;W++)Q.push(this.data.array[Z+W])}return new Z0(new this.array.constructor(Q),this.itemSize,this.normalized)}else{if(J.interleavedBuffers===void 0)J.interleavedBuffers={};if(J.interleavedBuffers[this.data.uuid]===void 0)J.interleavedBuffers[this.data.uuid]=this.data.clone(J);return new E9(J.interleavedBuffers[this.data.uuid],this.itemSize,this.offset,this.normalized)}}toJSON(J){if(J===void 0){console.log("THREE.InterleavedBufferAttribute.toJSON(): Serializing an interleaved buffer attribute will de-interleave buffer data.");let Q=[];for(let $=0;$<this.count;$++){let Z=$*this.data.stride+this.offset;for(let W=0;W<this.itemSize;W++)Q.push(this.data.array[Z+W])}return{itemSize:this.itemSize,type:this.array.constructor.name,array:Q,normalized:this.normalized}}else{if(J.interleavedBuffers===void 0)J.interleavedBuffers={};if(J.interleavedBuffers[this.data.uuid]===void 0)J.interleavedBuffers[this.data.uuid]=this.data.toJSON(J);return{isInterleavedBufferAttribute:!0,itemSize:this.itemSize,data:this.data.uuid,offset:this.offset,normalized:this.normalized}}}}class VQ extends C0{constructor(J){super();this.isSpriteMaterial=!0,this.type="SpriteMaterial",this.color=new kJ(16777215),this.map=null,this.alphaMap=null,this.rotation=0,this.sizeAttenuation=!0,this.transparent=!0,this.fog=!0,this.setValues(J)}copy(J){return super.copy(J),this.color.copy(J.color),this.map=J.map,this.alphaMap=J.alphaMap,this.rotation=J.rotation,this.sizeAttenuation=J.sizeAttenuation,this.fog=J.fog,this}}var x9,V6=new w,g9=new w,p9=new w,m9=new t,L6=new t,zY=new hJ,I7=new w,z6=new w,_7=new w,FK=new t,w$=new t,MK=new t;class cZ extends Q0{constructor(J=new VQ){super();if(this.isSprite=!0,this.type="Sprite",x9===void 0){x9=new nJ;let Q=new Float32Array([-0.5,-0.5,0,0,0,0.5,-0.5,0,1,0,0.5,0.5,0,1,1,-0.5,0.5,0,0,1]),$=new a6(Q,5);x9.setIndex([0,1,2,0,2,3]),x9.setAttribute("position",new E9($,3,0,!1)),x9.setAttribute("uv",new E9($,2,3,!1))}this.geometry=x9,this.material=J,this.center=new t(0.5,0.5),this.count=1}raycast(J,Q){if(J.camera===null)console.error('THREE.Sprite: "Raycaster.camera" needs to be set in order to raycast against sprites.');if(g9.setFromMatrixScale(this.matrixWorld),zY.copy(J.camera.matrixWorld),this.modelViewMatrix.multiplyMatrices(J.camera.matrixWorldInverse,this.matrixWorld),p9.setFromMatrixPosition(this.modelViewMatrix),J.camera.isPerspectiveCamera&&this.material.sizeAttenuation===!1)g9.multiplyScalar(-p9.z);let $=this.material.rotation,Z,W;if($!==0)W=Math.cos($),Z=Math.sin($);let K=this.center;w7(I7.set(-0.5,-0.5,0),p9,K,g9,Z,W),w7(z6.set(0.5,-0.5,0),p9,K,g9,Z,W),w7(_7.set(0.5,0.5,0),p9,K,g9,Z,W),FK.set(0,0),w$.set(1,0),MK.set(1,1);let H=J.ray.intersectTriangle(I7,z6,_7,!1,V6);if(H===null){if(w7(z6.set(-0.5,0.5,0),p9,K,g9,Z,W),w$.set(0,1),H=J.ray.intersectTriangle(I7,_7,z6,!1,V6),H===null)return}let Y=J.ray.origin.distanceTo(V6);if(Y<J.near||Y>J.far)return;Q.push({distance:Y,point:V6.clone(),uv:m0.getInterpolation(V6,I7,z6,_7,FK,w$,MK,new t),face:null,object:this})}copy(J,Q){if(super.copy(J,Q),J.center!==void 0)this.center.copy(J.center);return this.material=J.material,this}}function w7(J,Q,$,Z,W,K){if(m9.subVectors(J,$).addScalar(0.5).multiply(Z),W!==void 0)L6.x=K*m9.x-W*m9.y,L6.y=W*m9.x+K*m9.y;else L6.copy(m9);J.copy(Q),J.x+=L6.x,J.y+=L6.y,J.applyMatrix4(zY)}var C7=new w,kK=new w;class nZ extends Q0{constructor(){super();this.isLOD=!0,this._currentLevel=0,this.type="LOD",Object.defineProperties(this,{levels:{enumerable:!0,value:[]}}),this.autoUpdate=!0}copy(J){super.copy(J,!1);let Q=J.levels;for(let $=0,Z=Q.length;$<Z;$++){let W=Q[$];this.addLevel(W.object.clone(),W.distance,W.hysteresis)}return this.autoUpdate=J.autoUpdate,this}addLevel(J,Q=0,$=0){Q=Math.abs(Q);let Z=this.levels,W;for(W=0;W<Z.length;W++)if(Q<Z[W].distance)break;return Z.splice(W,0,{distance:Q,hysteresis:$,object:J}),this.add(J),this}removeLevel(J){let Q=this.levels;for(let $=0;$<Q.length;$++)if(Q[$].distance===J){let Z=Q.splice($,1);return this.remove(Z[0].object),!0}return!1}getCurrentLevel(){return this._currentLevel}getObjectForDistance(J){let Q=this.levels;if(Q.length>0){let $,Z;for($=1,Z=Q.length;$<Z;$++){let W=Q[$].distance;if(Q[$].object.visible)W-=W*Q[$].hysteresis;if(J<W)break}return Q[$-1].object}return null}raycast(J,Q){if(this.levels.length>0){C7.setFromMatrixPosition(this.matrixWorld);let Z=J.ray.origin.distanceTo(C7);this.getObjectForDistance(Z).raycast(J,Q)}}update(J){let Q=this.levels;if(Q.length>1){C7.setFromMatrixPosition(J.matrixWorld),kK.setFromMatrixPosition(this.matrixWorld);let $=C7.distanceTo(kK)/J.zoom;Q[0].object.visible=!0;let Z,W;for(Z=1,W=Q.length;Z<W;Z++){let K=Q[Z].distance;if(Q[Z].object.visible)K-=K*Q[Z].hysteresis;if($>=K)Q[Z-1].object.visible=!1,Q[Z].object.visible=!0;else break}this._currentLevel=Z-1;for(;Z<W;Z++)Q[Z].object.visible=!1}}toJSON(J){let Q=super.toJSON(J);if(this.autoUpdate===!1)Q.object.autoUpdate=!1;Q.object.levels=[];let $=this.levels;for(let Z=0,W=$.length;Z<W;Z++){let K=$[Z];Q.object.levels.push({object:K.object.uuid,distance:K.distance,hysteresis:K.hysteresis})}return Q}}var VK=new w,LK=new J0,zK=new J0,KE=new w,BK=new hJ,P7=new w,C$=new _0,IK=new hJ,P$=new F9;class sZ extends k0{constructor(J,Q){super(J,Q);this.isSkinnedMesh=!0,this.type="SkinnedMesh",this.bindMode="attached",this.bindMatrix=new hJ,this.bindMatrixInverse=new hJ,this.boundingBox=null,this.boundingSphere=null}computeBoundingBox(){let J=this.geometry;if(this.boundingBox===null)this.boundingBox=new w0;this.boundingBox.makeEmpty();let Q=J.getAttribute("position");for(let $=0;$<Q.count;$++)this.getVertexPosition($,P7),this.boundingBox.expandByPoint(P7)}computeBoundingSphere(){let J=this.geometry;if(this.boundingSphere===null)this.boundingSphere=new _0;this.boundingSphere.makeEmpty();let Q=J.getAttribute("position");for(let $=0;$<Q.count;$++)this.getVertexPosition($,P7),this.boundingSphere.expandByPoint(P7)}copy(J,Q){if(super.copy(J,Q),this.bindMode=J.bindMode,this.bindMatrix.copy(J.bindMatrix),this.bindMatrixInverse.copy(J.bindMatrixInverse),this.skeleton=J.skeleton,J.boundingBox!==null)this.boundingBox=J.boundingBox.clone();if(J.boundingSphere!==null)this.boundingSphere=J.boundingSphere.clone();return this}raycast(J,Q){let $=this.material,Z=this.matrixWorld;if($===void 0)return;if(this.boundingSphere===null)this.computeBoundingSphere();if(C$.copy(this.boundingSphere),C$.applyMatrix4(Z),J.ray.intersectsSphere(C$)===!1)return;if(IK.copy(Z).invert(),P$.copy(J.ray).applyMatrix4(IK),this.boundingBox!==null){if(P$.intersectsBox(this.boundingBox)===!1)return}this._computeIntersections(J,Q,P$)}getVertexPosition(J,Q){return super.getVertexPosition(J,Q),this.applyBoneTransform(J,Q),Q}bind(J,Q){if(this.skeleton=J,Q===void 0)this.updateMatrixWorld(!0),this.skeleton.calculateInverses(),Q=this.matrixWorld;this.bindMatrix.copy(Q),this.bindMatrixInverse.copy(Q).invert()}pose(){this.skeleton.pose()}normalizeSkinWeights(){let J=new J0,Q=this.geometry.attributes.skinWeight;for(let $=0,Z=Q.count;$<Z;$++){J.fromBufferAttribute(Q,$);let W=1/J.manhattanLength();if(W!==1/0)J.multiplyScalar(W);else J.set(1,0,0,0);Q.setXYZW($,J.x,J.y,J.z,J.w)}}updateMatrixWorld(J){if(super.updateMatrixWorld(J),this.bindMode==="attached")this.bindMatrixInverse.copy(this.matrixWorld).invert();else if(this.bindMode==="detached")this.bindMatrixInverse.copy(this.bindMatrix).invert();else console.warn("THREE.SkinnedMesh: Unrecognized bindMode: "+this.bindMode)}applyBoneTransform(J,Q){let $=this.skeleton,Z=this.geometry;LK.fromBufferAttribute(Z.attributes.skinIndex,J),zK.fromBufferAttribute(Z.attributes.skinWeight,J),VK.copy(Q).applyMatrix4(this.bindMatrix),Q.set(0,0,0);for(let W=0;W<4;W++){let K=zK.getComponent(W);if(K!==0){let H=LK.getComponent(W);BK.multiplyMatrices($.bones[H].matrixWorld,$.boneInverses[H]),Q.addScaledVector(KE.copy(VK).applyMatrix4(BK),K)}}return Q.applyMatrix4(this.bindMatrixInverse)}}class LQ extends Q0{constructor(){super();this.isBone=!0,this.type="Bone"}}class K8 extends F0{constructor(J=null,Q=1,$=1,Z,W,K,H,Y,X=1003,U=1003,G,E){super(null,K,H,Y,X,U,Z,W,G,E);this.isDataTexture=!0,this.image={data:J,width:Q,height:$},this.generateMipmaps=!1,this.flipY=!1,this.unpackAlignment=1}}var _K=new hJ,HE=new hJ;class zQ{constructor(J=[],Q=[]){this.uuid=n0(),this.bones=J.slice(0),this.boneInverses=Q,this.boneMatrices=null,this.boneTexture=null,this.init()}init(){let J=this.bones,Q=this.boneInverses;if(this.boneMatrices=new Float32Array(J.length*16),Q.length===0)this.calculateInverses();else if(J.length!==Q.length){console.warn("THREE.Skeleton: Number of inverse bone matrices does not match amount of bones."),this.boneInverses=[];for(let $=0,Z=this.bones.length;$<Z;$++)this.boneInverses.push(new hJ)}}calculateInverses(){this.boneInverses.length=0;for(let J=0,Q=this.bones.length;J<Q;J++){let $=new hJ;if(this.bones[J])$.copy(this.bones[J].matrixWorld).invert();this.boneInverses.push($)}}pose(){for(let J=0,Q=this.bones.length;J<Q;J++){let $=this.bones[J];if($)$.matrixWorld.copy(this.boneInverses[J]).invert()}for(let J=0,Q=this.bones.length;J<Q;J++){let $=this.bones[J];if($){if($.parent&&$.parent.isBone)$.matrix.copy($.parent.matrixWorld).invert(),$.matrix.multiply($.matrixWorld);else $.matrix.copy($.matrixWorld);$.matrix.decompose($.position,$.quaternion,$.scale)}}}update(){let J=this.bones,Q=this.boneInverses,$=this.boneMatrices,Z=this.boneTexture;for(let W=0,K=J.length;W<K;W++){let H=J[W]?J[W].matrixWorld:HE;_K.multiplyMatrices(H,Q[W]),_K.toArray($,W*16)}if(Z!==null)Z.needsUpdate=!0}clone(){return new zQ(this.bones,this.boneInverses)}computeBoneTexture(){let J=Math.sqrt(this.bones.length*4);J=Math.ceil(J/4)*4,J=Math.max(J,4);let Q=new Float32Array(J*J*4);Q.set(this.boneMatrices);let $=new K8(Q,J,J,1023,1015);return $.needsUpdate=!0,this.boneMatrices=Q,this.boneTexture=$,this}getBoneByName(J){for(let Q=0,$=this.bones.length;Q<$;Q++){let Z=this.bones[Q];if(Z.name===J)return Z}return}dispose(){if(this.boneTexture!==null)this.boneTexture.dispose(),this.boneTexture=null}fromJSON(J,Q){this.uuid=J.uuid;for(let $=0,Z=J.bones.length;$<Z;$++){let W=J.bones[$],K=Q[W];if(K===void 0)console.warn("THREE.Skeleton: No bone found with UUID:",W),K=new LQ;this.bones.push(K),this.boneInverses.push(new hJ().fromArray(J.boneInverses[$]))}return this.init(),this}toJSON(){let J={metadata:{version:4.7,type:"Skeleton",generator:"Skeleton.toJSON"},bones:[],boneInverses:[]};J.uuid=this.uuid;let Q=this.bones,$=this.boneInverses;for(let Z=0,W=Q.length;Z<W;Z++){let K=Q[Z];J.bones.push(K.uuid);let H=$[Z];J.boneInverses.push(H.toArray())}return J}}class N9 extends Z0{constructor(J,Q,$,Z=1){super(J,Q,$);this.isInstancedBufferAttribute=!0,this.meshPerAttribute=Z}copy(J){return super.copy(J),this.meshPerAttribute=J.meshPerAttribute,this}toJSON(){let J=super.toJSON();return J.meshPerAttribute=this.meshPerAttribute,J.isInstancedBufferAttribute=!0,J}}var d9=new hJ,wK=new hJ,A7=[],CK=new w0,YE=new hJ,B6=new k0,I6=new _0;class iZ extends k0{constructor(J,Q,$){super(J,Q);this.isInstancedMesh=!0,this.instanceMatrix=new N9(new Float32Array($*16),16),this.instanceColor=null,this.morphTexture=null,this.count=$,this.boundingBox=null,this.boundingSphere=null;for(let Z=0;Z<$;Z++)this.setMatrixAt(Z,YE)}computeBoundingBox(){let J=this.geometry,Q=this.count;if(this.boundingBox===null)this.boundingBox=new w0;if(J.boundingBox===null)J.computeBoundingBox();this.boundingBox.makeEmpty();for(let $=0;$<Q;$++)this.getMatrixAt($,d9),CK.copy(J.boundingBox).applyMatrix4(d9),this.boundingBox.union(CK)}computeBoundingSphere(){let J=this.geometry,Q=this.count;if(this.boundingSphere===null)this.boundingSphere=new _0;if(J.boundingSphere===null)J.computeBoundingSphere();this.boundingSphere.makeEmpty();for(let $=0;$<Q;$++)this.getMatrixAt($,d9),I6.copy(J.boundingSphere).applyMatrix4(d9),this.boundingSphere.union(I6)}copy(J,Q){if(super.copy(J,Q),this.instanceMatrix.copy(J.instanceMatrix),J.morphTexture!==null)this.morphTexture=J.morphTexture.clone();if(J.instanceColor!==null)this.instanceColor=J.instanceColor.clone();if(this.count=J.count,J.boundingBox!==null)this.boundingBox=J.boundingBox.clone();if(J.boundingSphere!==null)this.boundingSphere=J.boundingSphere.clone();return this}getColorAt(J,Q){Q.fromArray(this.instanceColor.array,J*3)}getMatrixAt(J,Q){Q.fromArray(this.instanceMatrix.array,J*16)}getMorphAt(J,Q){let $=Q.morphTargetInfluences,Z=this.morphTexture.source.data.data,W=$.length+1,K=J*W+1;for(let H=0;H<$.length;H++)$[H]=Z[K+H]}raycast(J,Q){let $=this.matrixWorld,Z=this.count;if(B6.geometry=this.geometry,B6.material=this.material,B6.material===void 0)return;if(this.boundingSphere===null)this.computeBoundingSphere();if(I6.copy(this.boundingSphere),I6.applyMatrix4($),J.ray.intersectsSphere(I6)===!1)return;for(let W=0;W<Z;W++){this.getMatrixAt(W,d9),wK.multiplyMatrices($,d9),B6.matrixWorld=wK,B6.raycast(J,A7);for(let K=0,H=A7.length;K<H;K++){let Y=A7[K];Y.instanceId=W,Y.object=this,Q.push(Y)}A7.length=0}}setColorAt(J,Q){if(this.instanceColor===null)this.instanceColor=new N9(new Float32Array(this.instanceMatrix.count*3).fill(1),3);Q.toArray(this.instanceColor.array,J*3)}setMatrixAt(J,Q){Q.toArray(this.instanceMatrix.array,J*16)}setMorphAt(J,Q){let $=Q.morphTargetInfluences,Z=$.length+1;if(this.morphTexture===null)this.morphTexture=new K8(new Float32Array(Z*this.count),Z,this.count,1028,1015);let W=this.morphTexture.source.data.data,K=0;for(let X=0;X<$.length;X++)K+=$[X];let H=this.geometry.morphTargetsRelative?1:1-K,Y=Z*J;W[Y]=H,W.set($,Y+1)}updateMorphTargets(){}dispose(){if(this.dispatchEvent({type:"dispose"}),this.morphTexture!==null)this.morphTexture.dispose(),this.morphTexture=null}}var A$=new w,XE=new w,UE=new dJ;class _8{constructor(J=new w(1,0,0),Q=0){this.isPlane=!0,this.normal=J,this.constant=Q}set(J,Q){return this.normal.copy(J),this.constant=Q,this}setComponents(J,Q,$,Z){return this.normal.set(J,Q,$),this.constant=Z,this}setFromNormalAndCoplanarPoint(J,Q){return this.normal.copy(J),this.constant=-Q.dot(this.normal),this}setFromCoplanarPoints(J,Q,$){let Z=A$.subVectors($,Q).cross(XE.subVectors(J,Q)).normalize();return this.setFromNormalAndCoplanarPoint(Z,J),this}copy(J){return this.normal.copy(J.normal),this.constant=J.constant,this}normalize(){let J=1/this.normal.length();return this.normal.multiplyScalar(J),this.constant*=J,this}negate(){return this.constant*=-1,this.normal.negate(),this}distanceToPoint(J){return this.normal.dot(J)+this.constant}distanceToSphere(J){return this.distanceToPoint(J.center)-J.radius}projectPoint(J,Q){return Q.copy(J).addScaledVector(this.normal,-this.distanceToPoint(J))}intersectLine(J,Q){let $=J.delta(A$),Z=this.normal.dot($);if(Z===0){if(this.distanceToPoint(J.start)===0)return Q.copy(J.start);return null}let W=-(J.start.dot(this.normal)+this.constant)/Z;if(W<0||W>1)return null;return Q.copy(J.start).addScaledVector($,W)}intersectsLine(J){let Q=this.distanceToPoint(J.start),$=this.distanceToPoint(J.end);return Q<0&&$>0||$<0&&Q>0}intersectsBox(J){return J.intersectsPlane(this)}intersectsSphere(J){return J.intersectsPlane(this)}coplanarPoint(J){return J.copy(this.normal).multiplyScalar(-this.constant)}applyMatrix4(J,Q){let $=Q||UE.getNormalMatrix(J),Z=this.coplanarPoint(A$).applyMatrix4(J),W=this.normal.applyMatrix3($).normalize();return this.constant=-Z.dot(W),this}translate(J){return this.constant-=J.dot(this.normal),this}equals(J){return J.normal.equals(this.normal)&&J.constant===this.constant}clone(){return new this.constructor().copy(this)}}var t8=new _0,GE=new t(0.5,0.5),T7=new w;class V9{constructor(J=new _8,Q=new _8,$=new _8,Z=new _8,W=new _8,K=new _8){this.planes=[J,Q,$,Z,W,K]}set(J,Q,$,Z,W,K){let H=this.planes;return H[0].copy(J),H[1].copy(Q),H[2].copy($),H[3].copy(Z),H[4].copy(W),H[5].copy(K),this}copy(J){let Q=this.planes;for(let $=0;$<6;$++)Q[$].copy(J.planes[$]);return this}setFromProjectionMatrix(J,Q=2000,$=!1){let Z=this.planes,W=J.elements,K=W[0],H=W[1],Y=W[2],X=W[3],U=W[4],G=W[5],E=W[6],N=W[7],q=W[8],R=W[9],F=W[10],O=W[11],D=W[12],k=W[13],M=W[14],L=W[15];if(Z[0].setComponents(X-K,N-U,O-q,L-D).normalize(),Z[1].setComponents(X+K,N+U,O+q,L+D).normalize(),Z[2].setComponents(X+H,N+G,O+R,L+k).normalize(),Z[3].setComponents(X-H,N-G,O-R,L-k).normalize(),$)Z[4].setComponents(Y,E,F,M).normalize(),Z[5].setComponents(X-Y,N-E,O-F,L-M).normalize();else if(Z[4].setComponents(X-Y,N-E,O-F,L-M).normalize(),Q===2000)Z[5].setComponents(X+Y,N+E,O+F,L+M).normalize();else if(Q===2001)Z[5].setComponents(Y,E,F,M).normalize();else throw Error("THREE.Frustum.setFromProjectionMatrix(): Invalid coordinate system: "+Q);return this}intersectsObject(J){if(J.boundingSphere!==void 0){if(J.boundingSphere===null)J.computeBoundingSphere();t8.copy(J.boundingSphere).applyMatrix4(J.matrixWorld)}else{let Q=J.geometry;if(Q.boundingSphere===null)Q.computeBoundingSphere();t8.copy(Q.boundingSphere).applyMatrix4(J.matrixWorld)}return this.intersectsSphere(t8)}intersectsSprite(J){t8.center.set(0,0,0);let Q=GE.distanceTo(J.center);return t8.radius=0.7071067811865476+Q,t8.applyMatrix4(J.matrixWorld),this.intersectsSphere(t8)}intersectsSphere(J){let Q=this.planes,$=J.center,Z=-J.radius;for(let W=0;W<6;W++)if(Q[W].distanceToPoint($)<Z)return!1;return!0}intersectsBox(J){let Q=this.planes;for(let $=0;$<6;$++){let Z=Q[$];if(T7.x=Z.normal.x>0?J.max.x:J.min.x,T7.y=Z.normal.y>0?J.max.y:J.min.y,T7.z=Z.normal.z>0?J.max.z:J.min.z,Z.distanceToPoint(T7)<0)return!1}return!0}containsPoint(J){let Q=this.planes;for(let $=0;$<6;$++)if(Q[$].distanceToPoint(J)<0)return!1;return!0}clone(){return new this.constructor().copy(this)}}var E8=new hJ,N8=new V9;class BQ{constructor(){this.coordinateSystem=2000}intersectsObject(J,Q){if(!Q.isArrayCamera||Q.cameras.length===0)return!1;for(let $=0;$<Q.cameras.length;$++){let Z=Q.cameras[$];if(E8.multiplyMatrices(Z.projectionMatrix,Z.matrixWorldInverse),N8.setFromProjectionMatrix(E8,Z.coordinateSystem,Z.reversedDepth),N8.intersectsObject(J))return!0}return!1}intersectsSprite(J,Q){if(!Q||!Q.cameras||Q.cameras.length===0)return!1;for(let $=0;$<Q.cameras.length;$++){let Z=Q.cameras[$];if(E8.multiplyMatrices(Z.projectionMatrix,Z.matrixWorldInverse),N8.setFromProjectionMatrix(E8,Z.coordinateSystem,Z.reversedDepth),N8.intersectsSprite(J))return!0}return!1}intersectsSphere(J,Q){if(!Q||!Q.cameras||Q.cameras.length===0)return!1;for(let $=0;$<Q.cameras.length;$++){let Z=Q.cameras[$];if(E8.multiplyMatrices(Z.projectionMatrix,Z.matrixWorldInverse),N8.setFromProjectionMatrix(E8,Z.coordinateSystem,Z.reversedDepth),N8.intersectsSphere(J))return!0}return!1}intersectsBox(J,Q){if(!Q||!Q.cameras||Q.cameras.length===0)return!1;for(let $=0;$<Q.cameras.length;$++){let Z=Q.cameras[$];if(E8.multiplyMatrices(Z.projectionMatrix,Z.matrixWorldInverse),N8.setFromProjectionMatrix(E8,Z.coordinateSystem,Z.reversedDepth),N8.intersectsBox(J))return!0}return!1}containsPoint(J,Q){if(!Q||!Q.cameras||Q.cameras.length===0)return!1;for(let $=0;$<Q.cameras.length;$++){let Z=Q.cameras[$];if(E8.multiplyMatrices(Z.projectionMatrix,Z.matrixWorldInverse),N8.setFromProjectionMatrix(E8,Z.coordinateSystem,Z.reversedDepth),N8.containsPoint(J))return!0}return!1}clone(){return new BQ}}function T$(J,Q){return J-Q}function EE(J,Q){return J.z-Q.z}function NE(J,Q){return Q.z-J.z}class BY{constructor(){this.index=0,this.pool=[],this.list=[]}push(J,Q,$,Z){let W=this.pool,K=this.list;if(this.index>=W.length)W.push({start:-1,count:-1,z:-1,index:-1});let H=W[this.index];K.push(H),this.index++,H.start=J,H.count=Q,H.z=$,H.index=Z}reset(){this.list.length=0,this.index=0}}var g0=new hJ,qE=new kJ(1,1,1),PK=new V9,DE=new BQ,S7=new w0,e8=new _0,_6=new w,AK=new w,OE=new w,S$=new BY,T0=new k0,j7=[];function RE(J,Q,$=0){let Z=Q.itemSize;if(J.isInterleavedBufferAttribute||J.array.constructor!==Q.array.constructor){let W=J.count;for(let K=0;K<W;K++)for(let H=0;H<Z;H++)Q.setComponent(K+$,H,J.getComponent(K,H))}else Q.array.set(J.array,$*Z);Q.needsUpdate=!0}function J9(J,Q){if(J.constructor!==Q.constructor){let $=Math.min(J.length,Q.length);for(let Z=0;Z<$;Z++)Q[Z]=J[Z]}else{let $=Math.min(J.length,Q.length);Q.set(new J.constructor(J.buffer,0,$))}}class oZ extends k0{constructor(J,Q,$=Q*2,Z){super(new nJ,Z);this.isBatchedMesh=!0,this.perObjectFrustumCulled=!0,this.sortObjects=!0,this.boundingBox=null,this.boundingSphere=null,this.customSort=null,this._instanceInfo=[],this._geometryInfo=[],this._availableInstanceIds=[],this._availableGeometryIds=[],this._nextIndexStart=0,this._nextVertexStart=0,this._geometryCount=0,this._visibilityChanged=!0,this._geometryInitialized=!1,this._maxInstanceCount=J,this._maxVertexCount=Q,this._maxIndexCount=$,this._multiDrawCounts=new Int32Array(J),this._multiDrawStarts=new Int32Array(J),this._multiDrawCount=0,this._multiDrawInstances=null,this._matricesTexture=null,this._indirectTexture=null,this._colorsTexture=null,this._initMatricesTexture(),this._initIndirectTexture()}get maxInstanceCount(){return this._maxInstanceCount}get instanceCount(){return this._instanceInfo.length-this._availableInstanceIds.length}get unusedVertexCount(){return this._maxVertexCount-this._nextVertexStart}get unusedIndexCount(){return this._maxIndexCount-this._nextIndexStart}_initMatricesTexture(){let J=Math.sqrt(this._maxInstanceCount*4);J=Math.ceil(J/4)*4,J=Math.max(J,4);let Q=new Float32Array(J*J*4),$=new K8(Q,J,J,1023,1015);this._matricesTexture=$}_initIndirectTexture(){let J=Math.sqrt(this._maxInstanceCount);J=Math.ceil(J);let Q=new Uint32Array(J*J),$=new K8(Q,J,J,1029,1014);this._indirectTexture=$}_initColorsTexture(){let J=Math.sqrt(this._maxInstanceCount);J=Math.ceil(J);let Q=new Float32Array(J*J*4).fill(1),$=new K8(Q,J,J,1023,1015);$.colorSpace=tJ.workingColorSpace,this._colorsTexture=$}_initializeGeometry(J){let Q=this.geometry,$=this._maxVertexCount,Z=this._maxIndexCount;if(this._geometryInitialized===!1){for(let W in J.attributes){let K=J.getAttribute(W),{array:H,itemSize:Y,normalized:X}=K,U=new H.constructor($*Y),G=new Z0(U,Y,X);Q.setAttribute(W,G)}if(J.getIndex()!==null){let W=$>65535?new Uint32Array(Z):new Uint16Array(Z);Q.setIndex(new Z0(W,1))}this._geometryInitialized=!0}}_validateGeometry(J){let Q=this.geometry;if(Boolean(J.getIndex())!==Boolean(Q.getIndex()))throw Error('THREE.BatchedMesh: All geometries must consistently have "index".');for(let $ in Q.attributes){if(!J.hasAttribute($))throw Error(`THREE.BatchedMesh: Added geometry missing "${$}". All geometries must have consistent attributes.`);let Z=J.getAttribute($),W=Q.getAttribute($);if(Z.itemSize!==W.itemSize||Z.normalized!==W.normalized)throw Error("THREE.BatchedMesh: All attributes must have a consistent itemSize and normalized value.")}}validateInstanceId(J){let Q=this._instanceInfo;if(J<0||J>=Q.length||Q[J].active===!1)throw Error(`THREE.BatchedMesh: Invalid instanceId ${J}. Instance is either out of range or has been deleted.`)}validateGeometryId(J){let Q=this._geometryInfo;if(J<0||J>=Q.length||Q[J].active===!1)throw Error(`THREE.BatchedMesh: Invalid geometryId ${J}. Geometry is either out of range or has been deleted.`)}setCustomSort(J){return this.customSort=J,this}computeBoundingBox(){if(this.boundingBox===null)this.boundingBox=new w0;let J=this.boundingBox,Q=this._instanceInfo;J.makeEmpty();for(let $=0,Z=Q.length;$<Z;$++){if(Q[$].active===!1)continue;let W=Q[$].geometryIndex;this.getMatrixAt($,g0),this.getBoundingBoxAt(W,S7).applyMatrix4(g0),J.union(S7)}}computeBoundingSphere(){if(this.boundingSphere===null)this.boundingSphere=new _0;let J=this.boundingSphere,Q=this._instanceInfo;J.makeEmpty();for(let $=0,Z=Q.length;$<Z;$++){if(Q[$].active===!1)continue;let W=Q[$].geometryIndex;this.getMatrixAt($,g0),this.getBoundingSphereAt(W,e8).applyMatrix4(g0),J.union(e8)}}addInstance(J){if(this._instanceInfo.length>=this.maxInstanceCount&&this._availableInstanceIds.length===0)throw Error("THREE.BatchedMesh: Maximum item count reached.");let $={visible:!0,active:!0,geometryIndex:J},Z=null;if(this._availableInstanceIds.length>0)this._availableInstanceIds.sort(T$),Z=this._availableInstanceIds.shift(),this._instanceInfo[Z]=$;else Z=this._instanceInfo.length,this._instanceInfo.push($);let W=this._matricesTexture;g0.identity().toArray(W.image.data,Z*16),W.needsUpdate=!0;let K=this._colorsTexture;if(K)qE.toArray(K.image.data,Z*4),K.needsUpdate=!0;return this._visibilityChanged=!0,Z}addGeometry(J,Q=-1,$=-1){this._initializeGeometry(J),this._validateGeometry(J);let Z={vertexStart:-1,vertexCount:-1,reservedVertexCount:-1,indexStart:-1,indexCount:-1,reservedIndexCount:-1,start:-1,count:-1,boundingBox:null,boundingSphere:null,active:!0},W=this._geometryInfo;Z.vertexStart=this._nextVertexStart,Z.reservedVertexCount=Q===-1?J.getAttribute("position").count:Q;let K=J.getIndex();if(K!==null)Z.indexStart=this._nextIndexStart,Z.reservedIndexCount=$===-1?K.count:$;if(Z.indexStart!==-1&&Z.indexStart+Z.reservedIndexCount>this._maxIndexCount||Z.vertexStart+Z.reservedVertexCount>this._maxVertexCount)throw Error("THREE.BatchedMesh: Reserved space request exceeds the maximum buffer size.");let Y;if(this._availableGeometryIds.length>0)this._availableGeometryIds.sort(T$),Y=this._availableGeometryIds.shift(),W[Y]=Z;else Y=this._geometryCount,this._geometryCount++,W.push(Z);return this.setGeometryAt(Y,J),this._nextIndexStart=Z.indexStart+Z.reservedIndexCount,this._nextVertexStart=Z.vertexStart+Z.reservedVertexCount,Y}setGeometryAt(J,Q){if(J>=this._geometryCount)throw Error("THREE.BatchedMesh: Maximum geometry count reached.");this._validateGeometry(Q);let $=this.geometry,Z=$.getIndex()!==null,W=$.getIndex(),K=Q.getIndex(),H=this._geometryInfo[J];if(Z&&K.count>H.reservedIndexCount||Q.attributes.position.count>H.reservedVertexCount)throw Error("THREE.BatchedMesh: Reserved space not large enough for provided geometry.");let{vertexStart:Y,reservedVertexCount:X}=H;H.vertexCount=Q.getAttribute("position").count;for(let U in $.attributes){let G=Q.getAttribute(U),E=$.getAttribute(U);RE(G,E,Y);let N=G.itemSize;for(let q=G.count,R=X;q<R;q++){let F=Y+q;for(let O=0;O<N;O++)E.setComponent(F,O,0)}E.needsUpdate=!0,E.addUpdateRange(Y*N,X*N)}if(Z){let{indexStart:U,reservedIndexCount:G}=H;H.indexCount=Q.getIndex().count;for(let E=0;E<K.count;E++)W.setX(U+E,Y+K.getX(E));for(let E=K.count,N=G;E<N;E++)W.setX(U+E,Y);W.needsUpdate=!0,W.addUpdateRange(U,H.reservedIndexCount)}if(H.start=Z?H.indexStart:H.vertexStart,H.count=Z?H.indexCount:H.vertexCount,H.boundingBox=null,Q.boundingBox!==null)H.boundingBox=Q.boundingBox.clone();if(H.boundingSphere=null,Q.boundingSphere!==null)H.boundingSphere=Q.boundingSphere.clone();return this._visibilityChanged=!0,J}deleteGeometry(J){let Q=this._geometryInfo;if(J>=Q.length||Q[J].active===!1)return this;let $=this._instanceInfo;for(let Z=0,W=$.length;Z<W;Z++)if($[Z].active&&$[Z].geometryIndex===J)this.deleteInstance(Z);return Q[J].active=!1,this._availableGeometryIds.push(J),this._visibilityChanged=!0,this}deleteInstance(J){return this.validateInstanceId(J),this._instanceInfo[J].active=!1,this._availableInstanceIds.push(J),this._visibilityChanged=!0,this}optimize(){let J=0,Q=0,$=this._geometryInfo,Z=$.map((K,H)=>H).sort((K,H)=>{return $[K].vertexStart-$[H].vertexStart}),W=this.geometry;for(let K=0,H=$.length;K<H;K++){let Y=Z[K],X=$[Y];if(X.active===!1)continue;if(W.index!==null){if(X.indexStart!==Q){let{indexStart:U,vertexStart:G,reservedIndexCount:E}=X,N=W.index,q=N.array,R=J-G;for(let F=U;F<U+E;F++)q[F]=q[F]+R;N.array.copyWithin(Q,U,U+E),N.addUpdateRange(Q,E),X.indexStart=Q}Q+=X.reservedIndexCount}if(X.vertexStart!==J){let{vertexStart:U,reservedVertexCount:G}=X,E=W.attributes;for(let N in E){let q=E[N],{array:R,itemSize:F}=q;R.copyWithin(J*F,U*F,(U+G)*F),q.addUpdateRange(J*F,G*F)}X.vertexStart=J}J+=X.reservedVertexCount,X.start=W.index?X.indexStart:X.vertexStart,this._nextIndexStart=W.index?X.indexStart+X.reservedIndexCount:0,this._nextVertexStart=X.vertexStart+X.reservedVertexCount}return this}getBoundingBoxAt(J,Q){if(J>=this._geometryCount)return null;let $=this.geometry,Z=this._geometryInfo[J];if(Z.boundingBox===null){let W=new w0,K=$.index,H=$.attributes.position;for(let Y=Z.start,X=Z.start+Z.count;Y<X;Y++){let U=Y;if(K)U=K.getX(U);W.expandByPoint(_6.fromBufferAttribute(H,U))}Z.boundingBox=W}return Q.copy(Z.boundingBox),Q}getBoundingSphereAt(J,Q){if(J>=this._geometryCount)return null;let $=this.geometry,Z=this._geometryInfo[J];if(Z.boundingSphere===null){let W=new _0;this.getBoundingBoxAt(J,S7),S7.getCenter(W.center);let K=$.index,H=$.attributes.position,Y=0;for(let X=Z.start,U=Z.start+Z.count;X<U;X++){let G=X;if(K)G=K.getX(G);_6.fromBufferAttribute(H,G),Y=Math.max(Y,W.center.distanceToSquared(_6))}W.radius=Math.sqrt(Y),Z.boundingSphere=W}return Q.copy(Z.boundingSphere),Q}setMatrixAt(J,Q){this.validateInstanceId(J);let $=this._matricesTexture,Z=this._matricesTexture.image.data;return Q.toArray(Z,J*16),$.needsUpdate=!0,this}getMatrixAt(J,Q){return this.validateInstanceId(J),Q.fromArray(this._matricesTexture.image.data,J*16)}setColorAt(J,Q){if(this.validateInstanceId(J),this._colorsTexture===null)this._initColorsTexture();return Q.toArray(this._colorsTexture.image.data,J*4),this._colorsTexture.needsUpdate=!0,this}getColorAt(J,Q){return this.validateInstanceId(J),Q.fromArray(this._colorsTexture.image.data,J*4)}setVisibleAt(J,Q){if(this.validateInstanceId(J),this._instanceInfo[J].visible===Q)return this;return this._instanceInfo[J].visible=Q,this._visibilityChanged=!0,this}getVisibleAt(J){return this.validateInstanceId(J),this._instanceInfo[J].visible}setGeometryIdAt(J,Q){return this.validateInstanceId(J),this.validateGeometryId(Q),this._instanceInfo[J].geometryIndex=Q,this}getGeometryIdAt(J){return this.validateInstanceId(J),this._instanceInfo[J].geometryIndex}getGeometryRangeAt(J,Q={}){this.validateGeometryId(J);let $=this._geometryInfo[J];return Q.vertexStart=$.vertexStart,Q.vertexCount=$.vertexCount,Q.reservedVertexCount=$.reservedVertexCount,Q.indexStart=$.indexStart,Q.indexCount=$.indexCount,Q.reservedIndexCount=$.reservedIndexCount,Q.start=$.start,Q.count=$.count,Q}setInstanceCount(J){let Q=this._availableInstanceIds,$=this._instanceInfo;Q.sort(T$);while(Q[Q.length-1]===$.length-1)$.pop(),Q.pop();if(J<$.length)throw Error(`BatchedMesh: Instance ids outside the range ${J} are being used. Cannot shrink instance count.`);let Z=new Int32Array(J),W=new Int32Array(J);J9(this._multiDrawCounts,Z),J9(this._multiDrawStarts,W),this._multiDrawCounts=Z,this._multiDrawStarts=W,this._maxInstanceCount=J;let K=this._indirectTexture,H=this._matricesTexture,Y=this._colorsTexture;if(K.dispose(),this._initIndirectTexture(),J9(K.image.data,this._indirectTexture.image.data),H.dispose(),this._initMatricesTexture(),J9(H.image.data,this._matricesTexture.image.data),Y)Y.dispose(),this._initColorsTexture(),J9(Y.image.data,this._colorsTexture.image.data)}setGeometrySize(J,Q){let $=[...this._geometryInfo].filter((H)=>H.active);if(Math.max(...$.map((H)=>H.vertexStart+H.reservedVertexCount))>J)throw Error(`BatchedMesh: Geometry vertex values are being used outside the range ${Q}. Cannot shrink further.`);if(this.geometry.index){if(Math.max(...$.map((Y)=>Y.indexStart+Y.reservedIndexCount))>Q)throw Error(`BatchedMesh: Geometry index values are being used outside the range ${Q}. Cannot shrink further.`)}let W=this.geometry;if(W.dispose(),this._maxVertexCount=J,this._maxIndexCount=Q,this._geometryInitialized)this._geometryInitialized=!1,this.geometry=new nJ,this._initializeGeometry(W);let K=this.geometry;if(W.index)J9(W.index.array,K.index.array);for(let H in W.attributes)J9(W.attributes[H].array,K.attributes[H].array)}raycast(J,Q){let $=this._instanceInfo,Z=this._geometryInfo,W=this.matrixWorld,K=this.geometry;if(T0.material=this.material,T0.geometry.index=K.index,T0.geometry.attributes=K.attributes,T0.geometry.boundingBox===null)T0.geometry.boundingBox=new w0;if(T0.geometry.boundingSphere===null)T0.geometry.boundingSphere=new _0;for(let H=0,Y=$.length;H<Y;H++){if(!$[H].visible||!$[H].active)continue;let X=$[H].geometryIndex,U=Z[X];T0.geometry.setDrawRange(U.start,U.count),this.getMatrixAt(H,T0.matrixWorld).premultiply(W),this.getBoundingBoxAt(X,T0.geometry.boundingBox),this.getBoundingSphereAt(X,T0.geometry.boundingSphere),T0.raycast(J,j7);for(let G=0,E=j7.length;G<E;G++){let N=j7[G];N.object=this,N.batchId=H,Q.push(N)}j7.length=0}T0.material=null,T0.geometry.index=null,T0.geometry.attributes={},T0.geometry.setDrawRange(0,1/0)}copy(J){if(super.copy(J),this.geometry=J.geometry.clone(),this.perObjectFrustumCulled=J.perObjectFrustumCulled,this.sortObjects=J.sortObjects,this.boundingBox=J.boundingBox!==null?J.boundingBox.clone():null,this.boundingSphere=J.boundingSphere!==null?J.boundingSphere.clone():null,this._geometryInfo=J._geometryInfo.map((Q)=>({...Q,boundingBox:Q.boundingBox!==null?Q.boundingBox.clone():null,boundingSphere:Q.boundingSphere!==null?Q.boundingSphere.clone():null})),this._instanceInfo=J._instanceInfo.map((Q)=>({...Q})),this._availableInstanceIds=J._availableInstanceIds.slice(),this._availableGeometryIds=J._availableGeometryIds.slice(),this._nextIndexStart=J._nextIndexStart,this._nextVertexStart=J._nextVertexStart,this._geometryCount=J._geometryCount,this._maxInstanceCount=J._maxInstanceCount,this._maxVertexCount=J._maxVertexCount,this._maxIndexCount=J._maxIndexCount,this._geometryInitialized=J._geometryInitialized,this._multiDrawCounts=J._multiDrawCounts.slice(),this._multiDrawStarts=J._multiDrawStarts.slice(),this._indirectTexture=J._indirectTexture.clone(),this._indirectTexture.image.data=this._indirectTexture.image.data.slice(),this._matricesTexture=J._matricesTexture.clone(),this._matricesTexture.image.data=this._matricesTexture.image.data.slice(),this._colorsTexture!==null)this._colorsTexture=J._colorsTexture.clone(),this._colorsTexture.image.data=this._colorsTexture.image.data.slice();return this}dispose(){if(this.geometry.dispose(),this._matricesTexture.dispose(),this._matricesTexture=null,this._indirectTexture.dispose(),this._indirectTexture=null,this._colorsTexture!==null)this._colorsTexture.dispose(),this._colorsTexture=null}onBeforeRender(J,Q,$,Z,W){if(!this._visibilityChanged&&!this.perObjectFrustumCulled&&!this.sortObjects)return;let K=Z.getIndex(),H=K===null?1:K.array.BYTES_PER_ELEMENT,Y=this._instanceInfo,X=this._multiDrawStarts,U=this._multiDrawCounts,G=this._geometryInfo,E=this.perObjectFrustumCulled,N=this._indirectTexture,q=N.image.data,R=$.isArrayCamera?DE:PK;if(E&&!$.isArrayCamera)g0.multiplyMatrices($.projectionMatrix,$.matrixWorldInverse).multiply(this.matrixWorld),PK.setFromProjectionMatrix(g0,$.coordinateSystem,$.reversedDepth);let F=0;if(this.sortObjects){g0.copy(this.matrixWorld).invert(),_6.setFromMatrixPosition($.matrixWorld).applyMatrix4(g0),AK.set(0,0,-1).transformDirection($.matrixWorld).transformDirection(g0);for(let k=0,M=Y.length;k<M;k++)if(Y[k].visible&&Y[k].active){let L=Y[k].geometryIndex;this.getMatrixAt(k,g0),this.getBoundingSphereAt(L,e8).applyMatrix4(g0);let A=!1;if(E)A=!R.intersectsSphere(e8,$);if(!A){let _=G[L],C=OE.subVectors(e8.center,_6).dot(AK);S$.push(_.start,_.count,C,k)}}let O=S$.list,D=this.customSort;if(D===null)O.sort(W.transparent?NE:EE);else D.call(this,O,$);for(let k=0,M=O.length;k<M;k++){let L=O[k];X[F]=L.start*H,U[F]=L.count,q[F]=L.index,F++}S$.reset()}else for(let O=0,D=Y.length;O<D;O++)if(Y[O].visible&&Y[O].active){let k=Y[O].geometryIndex,M=!1;if(E)this.getMatrixAt(O,g0),this.getBoundingSphereAt(k,e8).applyMatrix4(g0),M=!R.intersectsSphere(e8,$);if(!M){let L=G[k];X[F]=L.start*H,U[F]=L.count,q[F]=O,F++}}N.needsUpdate=!0,this._multiDrawCount=F,this._visibilityChanged=!1}onBeforeShadow(J,Q,$,Z,W,K){this.onBeforeRender(J,null,Z,W,K)}}class j0 extends C0{constructor(J){super();this.isLineBasicMaterial=!0,this.type="LineBasicMaterial",this.color=new kJ(16777215),this.map=null,this.linewidth=1,this.linecap="round",this.linejoin="round",this.fog=!0,this.setValues(J)}copy(J){return super.copy(J),this.color.copy(J.color),this.map=J.map,this.linewidth=J.linewidth,this.linecap=J.linecap,this.linejoin=J.linejoin,this.fog=J.fog,this}}var a7=new w,r7=new w,TK=new hJ,w6=new F9,y7=new _0,j$=new w,SK=new w;class A8 extends Q0{constructor(J=new nJ,Q=new j0){super();this.isLine=!0,this.type="Line",this.geometry=J,this.material=Q,this.morphTargetDictionary=void 0,this.morphTargetInfluences=void 0,this.updateMorphTargets()}copy(J,Q){return super.copy(J,Q),this.material=Array.isArray(J.material)?J.material.slice():J.material,this.geometry=J.geometry,this}computeLineDistances(){let J=this.geometry;if(J.index===null){let Q=J.attributes.position,$=[0];for(let Z=1,W=Q.count;Z<W;Z++)a7.fromBufferAttribute(Q,Z-1),r7.fromBufferAttribute(Q,Z),$[Z]=$[Z-1],$[Z]+=a7.distanceTo(r7);J.setAttribute("lineDistance",new BJ($,1))}else console.warn("THREE.Line.computeLineDistances(): Computation only possible with non-indexed BufferGeometry.");return this}raycast(J,Q){let $=this.geometry,Z=this.matrixWorld,W=J.params.Line.threshold,K=$.drawRange;if($.boundingSphere===null)$.computeBoundingSphere();if(y7.copy($.boundingSphere),y7.applyMatrix4(Z),y7.radius+=W,J.ray.intersectsSphere(y7)===!1)return;TK.copy(Z).invert(),w6.copy(J.ray).applyMatrix4(TK);let H=W/((this.scale.x+this.scale.y+this.scale.z)/3),Y=H*H,X=this.isLineSegments?2:1,U=$.index,E=$.attributes.position;if(U!==null){let N=Math.max(0,K.start),q=Math.min(U.count,K.start+K.count);for(let R=N,F=q-1;R<F;R+=X){let O=U.getX(R),D=U.getX(R+1),k=v7(this,J,w6,Y,O,D,R);if(k)Q.push(k)}if(this.isLineLoop){let R=U.getX(q-1),F=U.getX(N),O=v7(this,J,w6,Y,R,F,q-1);if(O)Q.push(O)}}else{let N=Math.max(0,K.start),q=Math.min(E.count,K.start+K.count);for(let R=N,F=q-1;R<F;R+=X){let O=v7(this,J,w6,Y,R,R+1,R);if(O)Q.push(O)}if(this.isLineLoop){let R=v7(this,J,w6,Y,q-1,N,q-1);if(R)Q.push(R)}}}updateMorphTargets(){let Q=this.geometry.morphAttributes,$=Object.keys(Q);if($.length>0){let Z=Q[$[0]];if(Z!==void 0){this.morphTargetInfluences=[],this.morphTargetDictionary={};for(let W=0,K=Z.length;W<K;W++){let H=Z[W].name||String(W);this.morphTargetInfluences.push(0),this.morphTargetDictionary[H]=W}}}}}function v7(J,Q,$,Z,W,K,H){let Y=J.geometry.attributes.position;if(a7.fromBufferAttribute(Y,W),r7.fromBufferAttribute(Y,K),$.distanceSqToSegment(a7,r7,j$,SK)>Z)return;j$.applyMatrix4(J.matrixWorld);let U=Q.ray.origin.distanceTo(j$);if(U<Q.near||U>Q.far)return;return{distance:U,point:SK.clone().applyMatrix4(J.matrixWorld),index:H,face:null,faceIndex:null,barycoord:null,object:J}}var jK=new w,yK=new w;class X8 extends A8{constructor(J,Q){super(J,Q);this.isLineSegments=!0,this.type="LineSegments"}computeLineDistances(){let J=this.geometry;if(J.index===null){let Q=J.attributes.position,$=[];for(let Z=0,W=Q.count;Z<W;Z+=2)jK.fromBufferAttribute(Q,Z),yK.fromBufferAttribute(Q,Z+1),$[Z]=Z===0?0:$[Z-1],$[Z+1]=$[Z]+jK.distanceTo(yK);J.setAttribute("lineDistance",new BJ($,1))}else console.warn("THREE.LineSegments.computeLineDistances(): Computation only possible with non-indexed BufferGeometry.");return this}}class aZ extends A8{constructor(J,Q){super(J,Q);this.isLineLoop=!0,this.type="LineLoop"}}class IQ extends C0{constructor(J){super();this.isPointsMaterial=!0,this.type="PointsMaterial",this.color=new kJ(16777215),this.map=null,this.alphaMap=null,this.size=1,this.sizeAttenuation=!0,this.fog=!0,this.setValues(J)}copy(J){return super.copy(J),this.color.copy(J.color),this.map=J.map,this.alphaMap=J.alphaMap,this.size=J.size,this.sizeAttenuation=J.sizeAttenuation,this.fog=J.fog,this}}var vK=new hJ,u$=new F9,f7=new _0,b7=new w;class rZ extends Q0{constructor(J=new nJ,Q=new IQ){super();this.isPoints=!0,this.type="Points",this.geometry=J,this.material=Q,this.morphTargetDictionary=void 0,this.morphTargetInfluences=void 0,this.updateMorphTargets()}copy(J,Q){return super.copy(J,Q),this.material=Array.isArray(J.material)?J.material.slice():J.material,this.geometry=J.geometry,this}raycast(J,Q){let $=this.geometry,Z=this.matrixWorld,W=J.params.Points.threshold,K=$.drawRange;if($.boundingSphere===null)$.computeBoundingSphere();if(f7.copy($.boundingSphere),f7.applyMatrix4(Z),f7.radius+=W,J.ray.intersectsSphere(f7)===!1)return;vK.copy(Z).invert(),u$.copy(J.ray).applyMatrix4(vK);let H=W/((this.scale.x+this.scale.y+this.scale.z)/3),Y=H*H,X=$.index,G=$.attributes.position;if(X!==null){let E=Math.max(0,K.start),N=Math.min(X.count,K.start+K.count);for(let q=E,R=N;q<R;q++){let F=X.getX(q);b7.fromBufferAttribute(G,F),fK(b7,F,Y,Z,J,Q,this)}}else{let E=Math.max(0,K.start),N=Math.min(G.count,K.start+K.count);for(let q=E,R=N;q<R;q++)b7.fromBufferAttribute(G,q),fK(b7,q,Y,Z,J,Q,this)}}updateMorphTargets(){let Q=this.geometry.morphAttributes,$=Object.keys(Q);if($.length>0){let Z=Q[$[0]];if(Z!==void 0){this.morphTargetInfluences=[],this.morphTargetDictionary={};for(let W=0,K=Z.length;W<K;W++){let H=Z[W].name||String(W);this.morphTargetInfluences.push(0),this.morphTargetDictionary[H]=W}}}}}function fK(J,Q,$,Z,W,K,H){let Y=u$.distanceSqToPoint(J);if(Y<$){let X=new w;u$.closestPointToPoint(J,X),X.applyMatrix4(Z);let U=W.ray.origin.distanceTo(X);if(U<W.near||U>W.far)return;K.push({distance:U,distanceToRay:Math.sqrt(Y),point:X,index:Q,face:null,faceIndex:null,barycoord:null,object:H})}}class tZ extends F0{constructor(J,Q,$,Z,W=1006,K=1006,H,Y,X){super(J,Q,$,Z,W,K,H,Y,X);this.isVideoTexture=!0,this.generateMipmaps=!1,this._requestVideoFrameCallbackId=0;let U=this;function G(){U.needsUpdate=!0,U._requestVideoFrameCallbackId=J.requestVideoFrameCallback(G)}if("requestVideoFrameCallback"in J)this._requestVideoFrameCallbackId=J.requestVideoFrameCallback(G)}clone(){return new this.constructor(this.image).copy(this)}update(){let J=this.image;if("requestVideoFrameCallback"in J===!1&&J.readyState>=J.HAVE_CURRENT_DATA)this.needsUpdate=!0}dispose(){if(this._requestVideoFrameCallbackId!==0)this.source.data.cancelVideoFrameCallback(this._requestVideoFrameCallbackId);super.dispose()}}class IY extends tZ{constructor(J,Q,$,Z,W,K,H,Y){super({},J,Q,$,Z,W,K,H,Y);this.isVideoFrameTexture=!0}update(){}clone(){return new this.constructor().copy(this)}setFrame(J){this.image=J,this.needsUpdate=!0}}class _Y extends F0{constructor(J,Q){super({width:J,height:Q});this.isFramebufferTexture=!0,this.magFilter=1003,this.minFilter=1003,this.generateMipmaps=!1,this.needsUpdate=!0}}class r6 extends F0{constructor(J,Q,$,Z,W,K,H,Y,X,U,G,E){super(null,K,H,Y,X,U,Z,W,G,E);this.isCompressedTexture=!0,this.image={width:Q,height:$},this.mipmaps=J,this.flipY=!1,this.generateMipmaps=!1}}class wY extends r6{constructor(J,Q,$,Z,W,K){super(J,Q,$,W,K);this.isCompressedArrayTexture=!0,this.image.depth=Z,this.wrapR=1001,this.layerUpdates=new Set}addLayerUpdate(J){this.layerUpdates.add(J)}clearLayerUpdates(){this.layerUpdates.clear()}}class CY extends r6{constructor(J,Q,$){super(void 0,J[0].width,J[0].height,Q,$,301);this.isCompressedCubeTexture=!0,this.isCubeTexture=!0,this.image=J}}class PY extends F0{constructor(J,Q,$,Z,W,K,H,Y,X){super(J,Q,$,Z,W,K,H,Y,X);this.isCanvasTexture=!0,this.needsUpdate=!0}}class _Q extends F0{constructor(J,Q,$=1014,Z,W,K,H=1003,Y=1003,X,U=1026,G=1){if(U!==1026&&U!==1027)throw Error("DepthTexture format must be either THREE.DepthFormat or THREE.DepthStencilFormat");let E={width:J,height:Q,depth:G};super(E,Z,W,K,H,Y,U,$,X);this.isDepthTexture=!0,this.flipY=!1,this.generateMipmaps=!1,this.compareFunction=null}copy(J){return super.copy(J),this.source=new C8(Object.assign({},J.image)),this.compareFunction=J.compareFunction,this}toJSON(J){let Q=super.toJSON(J);if(this.compareFunction!==null)Q.compareFunction=this.compareFunction;return Q}}class wQ extends F0{constructor(J=null){super();this.sourceTexture=J,this.isExternalTexture=!0}copy(J){return super.copy(J),this.sourceTexture=J.sourceTexture,this}}class CQ extends nJ{constructor(J=1,Q=1,$=4,Z=8,W=1){super();this.type="CapsuleGeometry",this.parameters={radius:J,height:Q,capSegments:$,radialSegments:Z,heightSegments:W},Q=Math.max(0,Q),$=Math.max(1,Math.floor($)),Z=Math.max(3,Math.floor(Z)),W=Math.max(1,Math.floor(W));let K=[],H=[],Y=[],X=[],U=Q/2,G=Math.PI/2*J,E=Q,N=2*G+E,q=$*2+W,R=Z+1,F=new w,O=new w;for(let D=0;D<=q;D++){let k=0,M=0,L=0,A=0;if(D<=$){let y=D/$,z=y*Math.PI/2;M=-U-J*Math.cos(z),L=J*Math.sin(z),A=-J*Math.cos(z),k=y*G}else if(D<=$+W){let y=(D-$)/W;M=-U+y*Q,L=J,A=0,k=G+y*E}else{let y=(D-$-W)/$,z=y*Math.PI/2;M=U+J*Math.sin(z),L=J*Math.cos(z),A=J*Math.sin(z),k=G+E+y*G}let _=Math.max(0,Math.min(1,k/N)),C=0;if(D===0)C=0.5/Z;else if(D===q)C=-0.5/Z;for(let y=0;y<=Z;y++){let z=y/Z,I=z*Math.PI*2,S=Math.sin(I),p=Math.cos(I);O.x=-L*p,O.y=M,O.z=L*S,H.push(O.x,O.y,O.z),F.set(-L*p,A,L*S),F.normalize(),Y.push(F.x,F.y,F.z),X.push(z+C,_)}if(D>0){let y=(D-1)*R;for(let z=0;z<Z;z++){let I=y+z,S=y+z+1,p=D*R+z,d=D*R+z+1;K.push(I,S,p),K.push(S,d,p)}}}this.setIndex(K),this.setAttribute("position",new BJ(H,3)),this.setAttribute("normal",new BJ(Y,3)),this.setAttribute("uv",new BJ(X,2))}copy(J){return super.copy(J),this.parameters=Object.assign({},J.parameters),this}static fromJSON(J){return new CQ(J.radius,J.height,J.capSegments,J.radialSegments,J.heightSegments)}}class PQ extends nJ{constructor(J=1,Q=32,$=0,Z=Math.PI*2){super();this.type="CircleGeometry",this.parameters={radius:J,segments:Q,thetaStart:$,thetaLength:Z},Q=Math.max(3,Q);let W=[],K=[],H=[],Y=[],X=new w,U=new t;K.push(0,0,0),H.push(0,0,1),Y.push(0.5,0.5);for(let G=0,E=3;G<=Q;G++,E+=3){let N=$+G/Q*Z;X.x=J*Math.cos(N),X.y=J*Math.sin(N),K.push(X.x,X.y,X.z),H.push(0,0,1),U.x=(K[E]/J+1)/2,U.y=(K[E+1]/J+1)/2,Y.push(U.x,U.y)}for(let G=1;G<=Q;G++)W.push(G,G+1,0);this.setIndex(W),this.setAttribute("position",new BJ(K,3)),this.setAttribute("normal",new BJ(H,3)),this.setAttribute("uv",new BJ(Y,2))}copy(J){return super.copy(J),this.parameters=Object.assign({},J.parameters),this}static fromJSON(J){return new PQ(J.radius,J.segments,J.thetaStart,J.thetaLength)}}class t6 extends nJ{constructor(J=1,Q=1,$=1,Z=32,W=1,K=!1,H=0,Y=Math.PI*2){super();this.type="CylinderGeometry",this.parameters={radiusTop:J,radiusBottom:Q,height:$,radialSegments:Z,heightSegments:W,openEnded:K,thetaStart:H,thetaLength:Y};let X=this;Z=Math.floor(Z),W=Math.floor(W);let U=[],G=[],E=[],N=[],q=0,R=[],F=$/2,O=0;if(D(),K===!1){if(J>0)k(!0);if(Q>0)k(!1)}this.setIndex(U),this.setAttribute("position",new BJ(G,3)),this.setAttribute("normal",new BJ(E,3)),this.setAttribute("uv",new BJ(N,2));function D(){let M=new w,L=new w,A=0,_=(Q-J)/$;for(let C=0;C<=W;C++){let y=[],z=C/W,I=z*(Q-J)+J;for(let S=0;S<=Z;S++){let p=S/Z,d=p*Y+H,x=Math.sin(d),o=Math.cos(d);L.x=I*x,L.y=-z*$+F,L.z=I*o,G.push(L.x,L.y,L.z),M.set(x,_,o).normalize(),E.push(M.x,M.y,M.z),N.push(p,1-z),y.push(q++)}R.push(y)}for(let C=0;C<Z;C++)for(let y=0;y<W;y++){let z=R[y][C],I=R[y+1][C],S=R[y+1][C+1],p=R[y][C+1];if(J>0||y!==0)U.push(z,I,p),A+=3;if(Q>0||y!==W-1)U.push(I,S,p),A+=3}X.addGroup(O,A,0),O+=A}function k(M){let L=q,A=new t,_=new w,C=0,y=M===!0?J:Q,z=M===!0?1:-1;for(let S=1;S<=Z;S++)G.push(0,F*z,0),E.push(0,z,0),N.push(0.5,0.5),q++;let I=q;for(let S=0;S<=Z;S++){let d=S/Z*Y+H,x=Math.cos(d),o=Math.sin(d);_.x=y*o,_.y=F*z,_.z=y*x,G.push(_.x,_.y,_.z),E.push(0,z,0),A.x=x*0.5+0.5,A.y=o*0.5*z+0.5,N.push(A.x,A.y),q++}for(let S=0;S<Z;S++){let p=L+S,d=I+S;if(M===!0)U.push(d,d+1,p);else U.push(d+1,d,p);C+=3}X.addGroup(O,C,M===!0?1:2),O+=C}}copy(J){return super.copy(J),this.parameters=Object.assign({},J.parameters),this}static fromJSON(J){return new t6(J.radiusTop,J.radiusBottom,J.height,J.radialSegments,J.heightSegments,J.openEnded,J.thetaStart,J.thetaLength)}}class e6 extends t6{constructor(J=1,Q=1,$=32,Z=1,W=!1,K=0,H=Math.PI*2){super(0,J,Q,$,Z,W,K,H);this.type="ConeGeometry",this.parameters={radius:J,height:Q,radialSegments:$,heightSegments:Z,openEnded:W,thetaStart:K,thetaLength:H}}static fromJSON(J){return new e6(J.radius,J.height,J.radialSegments,J.heightSegments,J.openEnded,J.thetaStart,J.thetaLength)}}class u8 extends nJ{constructor(J=[],Q=[],$=1,Z=0){super();this.type="PolyhedronGeometry",this.parameters={vertices:J,indices:Q,radius:$,detail:Z};let W=[],K=[];if(H(Z),X($),U(),this.setAttribute("position",new BJ(W,3)),this.setAttribute("normal",new BJ(W.slice(),3)),this.setAttribute("uv",new BJ(K,2)),Z===0)this.computeVertexNormals();else this.normalizeNormals();function H(D){let k=new w,M=new w,L=new w;for(let A=0;A<Q.length;A+=3)N(Q[A+0],k),N(Q[A+1],M),N(Q[A+2],L),Y(k,M,L,D)}function Y(D,k,M,L){let A=L+1,_=[];for(let C=0;C<=A;C++){_[C]=[];let y=D.clone().lerp(M,C/A),z=k.clone().lerp(M,C/A),I=A-C;for(let S=0;S<=I;S++)if(S===0&&C===A)_[C][S]=y;else _[C][S]=y.clone().lerp(z,S/I)}for(let C=0;C<A;C++)for(let y=0;y<2*(A-C)-1;y++){let z=Math.floor(y/2);if(y%2===0)E(_[C][z+1]),E(_[C+1][z]),E(_[C][z]);else E(_[C][z+1]),E(_[C+1][z+1]),E(_[C+1][z])}}function X(D){let k=new w;for(let M=0;M<W.length;M+=3)k.x=W[M+0],k.y=W[M+1],k.z=W[M+2],k.normalize().multiplyScalar(D),W[M+0]=k.x,W[M+1]=k.y,W[M+2]=k.z}function U(){let D=new w;for(let k=0;k<W.length;k+=3){D.x=W[k+0],D.y=W[k+1],D.z=W[k+2];let M=F(D)/2/Math.PI+0.5,L=O(D)/Math.PI+0.5;K.push(M,1-L)}q(),G()}function G(){for(let D=0;D<K.length;D+=6){let k=K[D+0],M=K[D+2],L=K[D+4],A=Math.max(k,M,L),_=Math.min(k,M,L);if(A>0.9&&_<0.1){if(k<0.2)K[D+0]+=1;if(M<0.2)K[D+2]+=1;if(L<0.2)K[D+4]+=1}}}function E(D){W.push(D.x,D.y,D.z)}function N(D,k){let M=D*3;k.x=J[M+0],k.y=J[M+1],k.z=J[M+2]}function q(){let D=new w,k=new w,M=new w,L=new w,A=new t,_=new t,C=new t;for(let y=0,z=0;y<W.length;y+=9,z+=6){D.set(W[y+0],W[y+1],W[y+2]),k.set(W[y+3],W[y+4],W[y+5]),M.set(W[y+6],W[y+7],W[y+8]),A.set(K[z+0],K[z+1]),_.set(K[z+2],K[z+3]),C.set(K[z+4],K[z+5]),L.copy(D).add(k).add(M).divideScalar(3);let I=F(L);R(A,z+0,D,I),R(_,z+2,k,I),R(C,z+4,M,I)}}function R(D,k,M,L){if(L<0&&D.x===1)K[k]=D.x-1;if(M.x===0&&M.z===0)K[k]=L/2/Math.PI+0.5}function F(D){return Math.atan2(D.z,-D.x)}function O(D){return Math.atan2(-D.y,Math.sqrt(D.x*D.x+D.z*D.z))}}copy(J){return super.copy(J),this.parameters=Object.assign({},J.parameters),this}static fromJSON(J){return new u8(J.vertices,J.indices,J.radius,J.details)}}class AQ extends u8{constructor(J=1,Q=0){let $=(1+Math.sqrt(5))/2,Z=1/$,W=[-1,-1,-1,-1,-1,1,-1,1,-1,-1,1,1,1,-1,-1,1,-1,1,1,1,-1,1,1,1,0,-Z,-$,0,-Z,$,0,Z,-$,0,Z,$,-Z,-$,0,-Z,$,0,Z,-$,0,Z,$,0,-$,0,-Z,$,0,-Z,-$,0,Z,$,0,Z],K=[3,11,7,3,7,15,3,15,13,7,19,17,7,17,6,7,6,15,17,4,8,17,8,10,17,10,6,8,0,16,8,16,2,8,2,10,0,12,1,0,1,18,0,18,16,6,10,2,6,2,13,6,13,15,2,16,18,2,18,3,2,3,13,18,1,9,18,9,11,18,11,3,4,14,12,4,12,0,4,0,8,11,9,5,11,5,19,11,19,7,19,5,14,19,14,4,19,4,17,1,12,14,1,14,5,1,5,9];super(W,K,J,Q);this.type="DodecahedronGeometry",this.parameters={radius:J,detail:Q}}static fromJSON(J){return new AQ(J.radius,J.detail)}}var h7=new w,x7=new w,y$=new w,g7=new m0;class eZ extends nJ{constructor(J=null,Q=1){super();if(this.type="EdgesGeometry",this.parameters={geometry:J,thresholdAngle:Q},J!==null){let Z=Math.pow(10,4),W=Math.cos(U9*Q),K=J.getIndex(),H=J.getAttribute("position"),Y=K?K.count:H.count,X=[0,0,0],U=["a","b","c"],G=[,,,],E={},N=[];for(let q=0;q<Y;q+=3){if(K)X[0]=K.getX(q),X[1]=K.getX(q+1),X[2]=K.getX(q+2);else X[0]=q,X[1]=q+1,X[2]=q+2;let{a:R,b:F,c:O}=g7;if(R.fromBufferAttribute(H,X[0]),F.fromBufferAttribute(H,X[1]),O.fromBufferAttribute(H,X[2]),g7.getNormal(y$),G[0]=`${Math.round(R.x*Z)},${Math.round(R.y*Z)},${Math.round(R.z*Z)}`,G[1]=`${Math.round(F.x*Z)},${Math.round(F.y*Z)},${Math.round(F.z*Z)}`,G[2]=`${Math.round(O.x*Z)},${Math.round(O.y*Z)},${Math.round(O.z*Z)}`,G[0]===G[1]||G[1]===G[2]||G[2]===G[0])continue;for(let D=0;D<3;D++){let k=(D+1)%3,M=G[D],L=G[k],A=g7[U[D]],_=g7[U[k]],C=`${M}_${L}`,y=`${L}_${M}`;if(y in E&&E[y]){if(y$.dot(E[y].normal)<=W)N.push(A.x,A.y,A.z),N.push(_.x,_.y,_.z);E[y]=null}else if(!(C in E))E[C]={index0:X[D],index1:X[k],normal:y$.clone()}}}for(let q in E)if(E[q]){let{index0:R,index1:F}=E[q];h7.fromBufferAttribute(H,R),x7.fromBufferAttribute(H,F),N.push(h7.x,h7.y,h7.z),N.push(x7.x,x7.y,x7.z)}this.setAttribute("position",new BJ(N,3))}}copy(J){return super.copy(J),this.parameters=Object.assign({},J.parameters),this}}class J8{constructor(){this.type="Curve",this.arcLengthDivisions=200,this.needsUpdate=!1,this.cacheArcLengths=null}getPoint(){console.warn("THREE.Curve: .getPoint() not implemented.")}getPointAt(J,Q){let $=this.getUtoTmapping(J);return this.getPoint($,Q)}getPoints(J=5){let Q=[];for(let $=0;$<=J;$++)Q.push(this.getPoint($/J));return Q}getSpacedPoints(J=5){let Q=[];for(let $=0;$<=J;$++)Q.push(this.getPointAt($/J));return Q}getLength(){let J=this.getLengths();return J[J.length-1]}getLengths(J=this.arcLengthDivisions){if(this.cacheArcLengths&&this.cacheArcLengths.length===J+1&&!this.needsUpdate)return this.cacheArcLengths;this.needsUpdate=!1;let Q=[],$,Z=this.getPoint(0),W=0;Q.push(0);for(let K=1;K<=J;K++)$=this.getPoint(K/J),W+=$.distanceTo(Z),Q.push(W),Z=$;return this.cacheArcLengths=Q,Q}updateArcLengths(){this.needsUpdate=!0,this.getLengths()}getUtoTmapping(J,Q=null){let $=this.getLengths(),Z=0,W=$.length,K;if(Q)K=Q;else K=J*$[W-1];let H=0,Y=W-1,X;while(H<=Y)if(Z=Math.floor(H+(Y-H)/2),X=$[Z]-K,X<0)H=Z+1;else if(X>0)Y=Z-1;else{Y=Z;break}if(Z=Y,$[Z]===K)return Z/(W-1);let U=$[Z],E=$[Z+1]-U,N=(K-U)/E;return(Z+N)/(W-1)}getTangent(J,Q){let Z=J-0.0001,W=J+0.0001;if(Z<0)Z=0;if(W>1)W=1;let K=this.getPoint(Z),H=this.getPoint(W),Y=Q||(K.isVector2?new t:new w);return Y.copy(H).sub(K).normalize(),Y}getTangentAt(J,Q){let $=this.getUtoTmapping(J);return this.getTangent($,Q)}computeFrenetFrames(J,Q=!1){let $=new w,Z=[],W=[],K=[],H=new w,Y=new hJ;for(let N=0;N<=J;N++){let q=N/J;Z[N]=this.getTangentAt(q,new w)}W[0]=new w,K[0]=new w;let X=Number.MAX_VALUE,U=Math.abs(Z[0].x),G=Math.abs(Z[0].y),E=Math.abs(Z[0].z);if(U<=X)X=U,$.set(1,0,0);if(G<=X)X=G,$.set(0,1,0);if(E<=X)$.set(0,0,1);H.crossVectors(Z[0],$).normalize(),W[0].crossVectors(Z[0],H),K[0].crossVectors(Z[0],W[0]);for(let N=1;N<=J;N++){if(W[N]=W[N-1].clone(),K[N]=K[N-1].clone(),H.crossVectors(Z[N-1],Z[N]),H.length()>Number.EPSILON){H.normalize();let q=Math.acos(bJ(Z[N-1].dot(Z[N]),-1,1));W[N].applyMatrix4(Y.makeRotationAxis(H,q))}K[N].crossVectors(Z[N],W[N])}if(Q===!0){let N=Math.acos(bJ(W[0].dot(W[J]),-1,1));if(N/=J,Z[0].dot(H.crossVectors(W[0],W[J]))>0)N=-N;for(let q=1;q<=J;q++)W[q].applyMatrix4(Y.makeRotationAxis(Z[q],N*q)),K[q].crossVectors(Z[q],W[q])}return{tangents:Z,normals:W,binormals:K}}clone(){return new this.constructor().copy(this)}copy(J){return this.arcLengthDivisions=J.arcLengthDivisions,this}toJSON(){let J={metadata:{version:4.7,type:"Curve",generator:"Curve.toJSON"}};return J.arcLengthDivisions=this.arcLengthDivisions,J.type=this.type,J}fromJSON(J){return this.arcLengthDivisions=J.arcLengthDivisions,this}}class J7 extends J8{constructor(J=0,Q=0,$=1,Z=1,W=0,K=Math.PI*2,H=!1,Y=0){super();this.isEllipseCurve=!0,this.type="EllipseCurve",this.aX=J,this.aY=Q,this.xRadius=$,this.yRadius=Z,this.aStartAngle=W,this.aEndAngle=K,this.aClockwise=H,this.aRotation=Y}getPoint(J,Q=new t){let $=Q,Z=Math.PI*2,W=this.aEndAngle-this.aStartAngle,K=Math.abs(W)<Number.EPSILON;while(W<0)W+=Z;while(W>Z)W-=Z;if(W<Number.EPSILON)if(K)W=0;else W=Z;if(this.aClockwise===!0&&!K)if(W===Z)W=-Z;else W=W-Z;let H=this.aStartAngle+J*W,Y=this.aX+this.xRadius*Math.cos(H),X=this.aY+this.yRadius*Math.sin(H);if(this.aRotation!==0){let U=Math.cos(this.aRotation),G=Math.sin(this.aRotation),E=Y-this.aX,N=X-this.aY;Y=E*U-N*G+this.aX,X=E*G+N*U+this.aY}return $.set(Y,X)}copy(J){return super.copy(J),this.aX=J.aX,this.aY=J.aY,this.xRadius=J.xRadius,this.yRadius=J.yRadius,this.aStartAngle=J.aStartAngle,this.aEndAngle=J.aEndAngle,this.aClockwise=J.aClockwise,this.aRotation=J.aRotation,this}toJSON(){let J=super.toJSON();return J.aX=this.aX,J.aY=this.aY,J.xRadius=this.xRadius,J.yRadius=this.yRadius,J.aStartAngle=this.aStartAngle,J.aEndAngle=this.aEndAngle,J.aClockwise=this.aClockwise,J.aRotation=this.aRotation,J}fromJSON(J){return super.fromJSON(J),this.aX=J.aX,this.aY=J.aY,this.xRadius=J.xRadius,this.yRadius=J.yRadius,this.aStartAngle=J.aStartAngle,this.aEndAngle=J.aEndAngle,this.aClockwise=J.aClockwise,this.aRotation=J.aRotation,this}}class JW extends J7{constructor(J,Q,$,Z,W,K){super(J,Q,$,$,Z,W,K);this.isArcCurve=!0,this.type="ArcCurve"}}function QW(){let J=0,Q=0,$=0,Z=0;function W(K,H,Y,X){J=K,Q=Y,$=-3*K+3*H-2*Y-X,Z=2*K-2*H+Y+X}return{initCatmullRom:function(K,H,Y,X,U){W(H,Y,U*(Y-K),U*(X-H))},initNonuniformCatmullRom:function(K,H,Y,X,U,G,E){let N=(H-K)/U-(Y-K)/(U+G)+(Y-H)/G,q=(Y-H)/G-(X-H)/(G+E)+(X-Y)/E;N*=G,q*=G,W(H,Y,N,q)},calc:function(K){let H=K*K,Y=H*K;return J+Q*K+$*H+Z*Y}}}var p7=new w,v$=new QW,f$=new QW,b$=new QW;class $W extends J8{constructor(J=[],Q=!1,$="centripetal",Z=0.5){super();this.isCatmullRomCurve3=!0,this.type="CatmullRomCurve3",this.points=J,this.closed=Q,this.curveType=$,this.tension=Z}getPoint(J,Q=new w){let $=Q,Z=this.points,W=Z.length,K=(W-(this.closed?0:1))*J,H=Math.floor(K),Y=K-H;if(this.closed)H+=H>0?0:(Math.floor(Math.abs(H)/W)+1)*W;else if(Y===0&&H===W-1)H=W-2,Y=1;let X,U;if(this.closed||H>0)X=Z[(H-1)%W];else p7.subVectors(Z[0],Z[1]).add(Z[0]),X=p7;let G=Z[H%W],E=Z[(H+1)%W];if(this.closed||H+2<W)U=Z[(H+2)%W];else p7.subVectors(Z[W-1],Z[W-2]).add(Z[W-1]),U=p7;if(this.curveType==="centripetal"||this.curveType==="chordal"){let N=this.curveType==="chordal"?0.5:0.25,q=Math.pow(X.distanceToSquared(G),N),R=Math.pow(G.distanceToSquared(E),N),F=Math.pow(E.distanceToSquared(U),N);if(R<0.0001)R=1;if(q<0.0001)q=R;if(F<0.0001)F=R;v$.initNonuniformCatmullRom(X.x,G.x,E.x,U.x,q,R,F),f$.initNonuniformCatmullRom(X.y,G.y,E.y,U.y,q,R,F),b$.initNonuniformCatmullRom(X.z,G.z,E.z,U.z,q,R,F)}else if(this.curveType==="catmullrom")v$.initCatmullRom(X.x,G.x,E.x,U.x,this.tension),f$.initCatmullRom(X.y,G.y,E.y,U.y,this.tension),b$.initCatmullRom(X.z,G.z,E.z,U.z,this.tension);return $.set(v$.calc(Y),f$.calc(Y),b$.calc(Y)),$}copy(J){super.copy(J),this.points=[];for(let Q=0,$=J.points.length;Q<$;Q++){let Z=J.points[Q];this.points.push(Z.clone())}return this.closed=J.closed,this.curveType=J.curveType,this.tension=J.tension,this}toJSON(){let J=super.toJSON();J.points=[];for(let Q=0,$=this.points.length;Q<$;Q++){let Z=this.points[Q];J.points.push(Z.toArray())}return J.closed=this.closed,J.curveType=this.curveType,J.tension=this.tension,J}fromJSON(J){super.fromJSON(J),this.points=[];for(let Q=0,$=J.points.length;Q<$;Q++){let Z=J.points[Q];this.points.push(new w().fromArray(Z))}return this.closed=J.closed,this.curveType=J.curveType,this.tension=J.tension,this}}function bK(J,Q,$,Z,W){let K=(Z-Q)*0.5,H=(W-$)*0.5,Y=J*J,X=J*Y;return(2*$-2*Z+K+H)*X+(-3*$+3*Z-2*K-H)*Y+K*J+$}function FE(J,Q){let $=1-J;return $*$*Q}function ME(J,Q){return 2*(1-J)*J*Q}function kE(J,Q){return J*J*Q}function S6(J,Q,$,Z){return FE(J,Q)+ME(J,$)+kE(J,Z)}function VE(J,Q){let $=1-J;return $*$*$*Q}function LE(J,Q){let $=1-J;return 3*$*$*J*Q}function zE(J,Q){return 3*(1-J)*J*J*Q}function BE(J,Q){return J*J*J*Q}function j6(J,Q,$,Z,W){return VE(J,Q)+LE(J,$)+zE(J,Z)+BE(J,W)}class TQ extends J8{constructor(J=new t,Q=new t,$=new t,Z=new t){super();this.isCubicBezierCurve=!0,this.type="CubicBezierCurve",this.v0=J,this.v1=Q,this.v2=$,this.v3=Z}getPoint(J,Q=new t){let $=Q,Z=this.v0,W=this.v1,K=this.v2,H=this.v3;return $.set(j6(J,Z.x,W.x,K.x,H.x),j6(J,Z.y,W.y,K.y,H.y)),$}copy(J){return super.copy(J),this.v0.copy(J.v0),this.v1.copy(J.v1),this.v2.copy(J.v2),this.v3.copy(J.v3),this}toJSON(){let J=super.toJSON();return J.v0=this.v0.toArray(),J.v1=this.v1.toArray(),J.v2=this.v2.toArray(),J.v3=this.v3.toArray(),J}fromJSON(J){return super.fromJSON(J),this.v0.fromArray(J.v0),this.v1.fromArray(J.v1),this.v2.fromArray(J.v2),this.v3.fromArray(J.v3),this}}class ZW extends J8{constructor(J=new w,Q=new w,$=new w,Z=new w){super();this.isCubicBezierCurve3=!0,this.type="CubicBezierCurve3",this.v0=J,this.v1=Q,this.v2=$,this.v3=Z}getPoint(J,Q=new w){let $=Q,Z=this.v0,W=this.v1,K=this.v2,H=this.v3;return $.set(j6(J,Z.x,W.x,K.x,H.x),j6(J,Z.y,W.y,K.y,H.y),j6(J,Z.z,W.z,K.z,H.z)),$}copy(J){return super.copy(J),this.v0.copy(J.v0),this.v1.copy(J.v1),this.v2.copy(J.v2),this.v3.copy(J.v3),this}toJSON(){let J=super.toJSON();return J.v0=this.v0.toArray(),J.v1=this.v1.toArray(),J.v2=this.v2.toArray(),J.v3=this.v3.toArray(),J}fromJSON(J){return super.fromJSON(J),this.v0.fromArray(J.v0),this.v1.fromArray(J.v1),this.v2.fromArray(J.v2),this.v3.fromArray(J.v3),this}}class SQ extends J8{constructor(J=new t,Q=new t){super();this.isLineCurve=!0,this.type="LineCurve",this.v1=J,this.v2=Q}getPoint(J,Q=new t){let $=Q;if(J===1)$.copy(this.v2);else $.copy(this.v2).sub(this.v1),$.multiplyScalar(J).add(this.v1);return $}getPointAt(J,Q){return this.getPoint(J,Q)}getTangent(J,Q=new t){return Q.subVectors(this.v2,this.v1).normalize()}getTangentAt(J,Q){return this.getTangent(J,Q)}copy(J){return super.copy(J),this.v1.copy(J.v1),this.v2.copy(J.v2),this}toJSON(){let J=super.toJSON();return J.v1=this.v1.toArray(),J.v2=this.v2.toArray(),J}fromJSON(J){return super.fromJSON(J),this.v1.fromArray(J.v1),this.v2.fromArray(J.v2),this}}class WW extends J8{constructor(J=new w,Q=new w){super();this.isLineCurve3=!0,this.type="LineCurve3",this.v1=J,this.v2=Q}getPoint(J,Q=new w){let $=Q;if(J===1)$.copy(this.v2);else $.copy(this.v2).sub(this.v1),$.multiplyScalar(J).add(this.v1);return $}getPointAt(J,Q){return this.getPoint(J,Q)}getTangent(J,Q=new w){return Q.subVectors(this.v2,this.v1).normalize()}getTangentAt(J,Q){return this.getTangent(J,Q)}copy(J){return super.copy(J),this.v1.copy(J.v1),this.v2.copy(J.v2),this}toJSON(){let J=super.toJSON();return J.v1=this.v1.toArray(),J.v2=this.v2.toArray(),J}fromJSON(J){return super.fromJSON(J),this.v1.fromArray(J.v1),this.v2.fromArray(J.v2),this}}class jQ extends J8{constructor(J=new t,Q=new t,$=new t){super();this.isQuadraticBezierCurve=!0,this.type="QuadraticBezierCurve",this.v0=J,this.v1=Q,this.v2=$}getPoint(J,Q=new t){let $=Q,Z=this.v0,W=this.v1,K=this.v2;return $.set(S6(J,Z.x,W.x,K.x),S6(J,Z.y,W.y,K.y)),$}copy(J){return super.copy(J),this.v0.copy(J.v0),this.v1.copy(J.v1),this.v2.copy(J.v2),this}toJSON(){let J=super.toJSON();return J.v0=this.v0.toArray(),J.v1=this.v1.toArray(),J.v2=this.v2.toArray(),J}fromJSON(J){return super.fromJSON(J),this.v0.fromArray(J.v0),this.v1.fromArray(J.v1),this.v2.fromArray(J.v2),this}}class yQ extends J8{constructor(J=new w,Q=new w,$=new w){super();this.isQuadraticBezierCurve3=!0,this.type="QuadraticBezierCurve3",this.v0=J,this.v1=Q,this.v2=$}getPoint(J,Q=new w){let $=Q,Z=this.v0,W=this.v1,K=this.v2;return $.set(S6(J,Z.x,W.x,K.x),S6(J,Z.y,W.y,K.y),S6(J,Z.z,W.z,K.z)),$}copy(J){return super.copy(J),this.v0.copy(J.v0),this.v1.copy(J.v1),this.v2.copy(J.v2),this}toJSON(){let J=super.toJSON();return J.v0=this.v0.toArray(),J.v1=this.v1.toArray(),J.v2=this.v2.toArray(),J}fromJSON(J){return super.fromJSON(J),this.v0.fromArray(J.v0),this.v1.fromArray(J.v1),this.v2.fromArray(J.v2),this}}class vQ extends J8{constructor(J=[]){super();this.isSplineCurve=!0,this.type="SplineCurve",this.points=J}getPoint(J,Q=new t){let $=Q,Z=this.points,W=(Z.length-1)*J,K=Math.floor(W),H=W-K,Y=Z[K===0?K:K-1],X=Z[K],U=Z[K>Z.length-2?Z.length-1:K+1],G=Z[K>Z.length-3?Z.length-1:K+2];return $.set(bK(H,Y.x,X.x,U.x,G.x),bK(H,Y.y,X.y,U.y,G.y)),$}copy(J){super.copy(J),this.points=[];for(let Q=0,$=J.points.length;Q<$;Q++){let Z=J.points[Q];this.points.push(Z.clone())}return this}toJSON(){let J=super.toJSON();J.points=[];for(let Q=0,$=this.points.length;Q<$;Q++){let Z=this.points[Q];J.points.push(Z.toArray())}return J}fromJSON(J){super.fromJSON(J),this.points=[];for(let Q=0,$=J.points.length;Q<$;Q++){let Z=J.points[Q];this.points.push(new t().fromArray(Z))}return this}}var t7=Object.freeze({__proto__:null,ArcCurve:JW,CatmullRomCurve3:$W,CubicBezierCurve:TQ,CubicBezierCurve3:ZW,EllipseCurve:J7,LineCurve:SQ,LineCurve3:WW,QuadraticBezierCurve:jQ,QuadraticBezierCurve3:yQ,SplineCurve:vQ});class KW extends J8{constructor(){super();this.type="CurvePath",this.curves=[],this.autoClose=!1}add(J){this.curves.push(J)}closePath(){let J=this.curves[0].getPoint(0),Q=this.curves[this.curves.length-1].getPoint(1);if(!J.equals(Q)){let $=J.isVector2===!0?"LineCurve":"LineCurve3";this.curves.push(new t7[$](Q,J))}return this}getPoint(J,Q){let $=J*this.getLength(),Z=this.getCurveLengths(),W=0;while(W<Z.length){if(Z[W]>=$){let K=Z[W]-$,H=this.curves[W],Y=H.getLength(),X=Y===0?0:1-K/Y;return H.getPointAt(X,Q)}W++}return null}getLength(){let J=this.getCurveLengths();return J[J.length-1]}updateArcLengths(){this.needsUpdate=!0,this.cacheLengths=null,this.getCurveLengths()}getCurveLengths(){if(this.cacheLengths&&this.cacheLengths.length===this.curves.length)return this.cacheLengths;let J=[],Q=0;for(let $=0,Z=this.curves.length;$<Z;$++)Q+=this.curves[$].getLength(),J.push(Q);return this.cacheLengths=J,J}getSpacedPoints(J=40){let Q=[];for(let $=0;$<=J;$++)Q.push(this.getPoint($/J));if(this.autoClose)Q.push(Q[0]);return Q}getPoints(J=12){let Q=[],$;for(let Z=0,W=this.curves;Z<W.length;Z++){let K=W[Z],H=K.isEllipseCurve?J*2:K.isLineCurve||K.isLineCurve3?1:K.isSplineCurve?J*K.points.length:J,Y=K.getPoints(H);for(let X=0;X<Y.length;X++){let U=Y[X];if($&&$.equals(U))continue;Q.push(U),$=U}}if(this.autoClose&&Q.length>1&&!Q[Q.length-1].equals(Q[0]))Q.push(Q[0]);return Q}copy(J){super.copy(J),this.curves=[];for(let Q=0,$=J.curves.length;Q<$;Q++){let Z=J.curves[Q];this.curves.push(Z.clone())}return this.autoClose=J.autoClose,this}toJSON(){let J=super.toJSON();J.autoClose=this.autoClose,J.curves=[];for(let Q=0,$=this.curves.length;Q<$;Q++){let Z=this.curves[Q];J.curves.push(Z.toJSON())}return J}fromJSON(J){super.fromJSON(J),this.autoClose=J.autoClose,this.curves=[];for(let Q=0,$=J.curves.length;Q<$;Q++){let Z=J.curves[Q];this.curves.push(new t7[Z.type]().fromJSON(Z))}return this}}class y6 extends KW{constructor(J){super();if(this.type="Path",this.currentPoint=new t,J)this.setFromPoints(J)}setFromPoints(J){this.moveTo(J[0].x,J[0].y);for(let Q=1,$=J.length;Q<$;Q++)this.lineTo(J[Q].x,J[Q].y);return this}moveTo(J,Q){return this.currentPoint.set(J,Q),this}lineTo(J,Q){let $=new SQ(this.currentPoint.clone(),new t(J,Q));return this.curves.push($),this.currentPoint.set(J,Q),this}quadraticCurveTo(J,Q,$,Z){let W=new jQ(this.currentPoint.clone(),new t(J,Q),new t($,Z));return this.curves.push(W),this.currentPoint.set($,Z),this}bezierCurveTo(J,Q,$,Z,W,K){let H=new TQ(this.currentPoint.clone(),new t(J,Q),new t($,Z),new t(W,K));return this.curves.push(H),this.currentPoint.set(W,K),this}splineThru(J){let Q=[this.currentPoint.clone()].concat(J),$=new vQ(Q);return this.curves.push($),this.currentPoint.copy(J[J.length-1]),this}arc(J,Q,$,Z,W,K){let H=this.currentPoint.x,Y=this.currentPoint.y;return this.absarc(J+H,Q+Y,$,Z,W,K),this}absarc(J,Q,$,Z,W,K){return this.absellipse(J,Q,$,$,Z,W,K),this}ellipse(J,Q,$,Z,W,K,H,Y){let X=this.currentPoint.x,U=this.currentPoint.y;return this.absellipse(J+X,Q+U,$,Z,W,K,H,Y),this}absellipse(J,Q,$,Z,W,K,H,Y){let X=new J7(J,Q,$,Z,W,K,H,Y);if(this.curves.length>0){let G=X.getPoint(0);if(!G.equals(this.currentPoint))this.lineTo(G.x,G.y)}this.curves.push(X);let U=X.getPoint(1);return this.currentPoint.copy(U),this}copy(J){return super.copy(J),this.currentPoint.copy(J.currentPoint),this}toJSON(){let J=super.toJSON();return J.currentPoint=this.currentPoint.toArray(),J}fromJSON(J){return super.fromJSON(J),this.currentPoint.fromArray(J.currentPoint),this}}class p8 extends y6{constructor(J){super(J);this.uuid=n0(),this.type="Shape",this.holes=[]}getPointsHoles(J){let Q=[];for(let $=0,Z=this.holes.length;$<Z;$++)Q[$]=this.holes[$].getPoints(J);return Q}extractPoints(J){return{shape:this.getPoints(J),holes:this.getPointsHoles(J)}}copy(J){super.copy(J),this.holes=[];for(let Q=0,$=J.holes.length;Q<$;Q++){let Z=J.holes[Q];this.holes.push(Z.clone())}return this}toJSON(){let J=super.toJSON();J.uuid=this.uuid,J.holes=[];for(let Q=0,$=this.holes.length;Q<$;Q++){let Z=this.holes[Q];J.holes.push(Z.toJSON())}return J}fromJSON(J){super.fromJSON(J),this.uuid=J.uuid,this.holes=[];for(let Q=0,$=J.holes.length;Q<$;Q++){let Z=J.holes[Q];this.holes.push(new y6().fromJSON(Z))}return this}}function IE(J,Q,$=2){let Z=Q&&Q.length,W=Z?Q[0]*$:J.length,K=AY(J,0,W,$,!0),H=[];if(!K||K.next===K.prev)return H;let Y,X,U;if(Z)K=AE(J,Q,K,$);if(J.length>80*$){Y=1/0,X=1/0;let G=-1/0,E=-1/0;for(let N=$;N<W;N+=$){let q=J[N],R=J[N+1];if(q<Y)Y=q;if(R<X)X=R;if(q>G)G=q;if(R>E)E=R}U=Math.max(G-Y,E-X),U=U!==0?32767/U:0}return v6(K,H,$,Y,X,U,0),H}function AY(J,Q,$,Z,W){let K;if(W===pE(J,Q,$,Z)>0)for(let H=Q;H<$;H+=Z)K=hK(H/Z|0,J[H],J[H+1],K);else for(let H=$-Z;H>=Q;H-=Z)K=hK(H/Z|0,J[H],J[H+1],K);if(K&&a9(K,K.next))b6(K),K=K.next;return K}function q9(J,Q){if(!J)return J;if(!Q)Q=J;let $=J,Z;do if(Z=!1,!$.steiner&&(a9($,$.next)||D0($.prev,$,$.next)===0)){if(b6($),$=Q=$.prev,$===$.next)break;Z=!0}else $=$.next;while(Z||$!==Q);return Q}function v6(J,Q,$,Z,W,K,H){if(!J)return;if(!H&&K)vE(J,Z,W,K);let Y=J;while(J.prev!==J.next){let{prev:X,next:U}=J;if(K?wE(J,Z,W,K):_E(J)){Q.push(X.i,J.i,U.i),b6(J),J=U.next,Y=U.next;continue}if(J=U,J===Y){if(!H)v6(q9(J),Q,$,Z,W,K,1);else if(H===1)J=CE(q9(J),Q),v6(J,Q,$,Z,W,K,2);else if(H===2)PE(J,Q,$,Z,W,K);break}}}function _E(J){let Q=J.prev,$=J,Z=J.next;if(D0(Q,$,Z)>=0)return!1;let W=Q.x,K=$.x,H=Z.x,Y=Q.y,X=$.y,U=Z.y,G=Math.min(W,K,H),E=Math.min(Y,X,U),N=Math.max(W,K,H),q=Math.max(Y,X,U),R=Z.next;while(R!==Q){if(R.x>=G&&R.x<=N&&R.y>=E&&R.y<=q&&A6(W,Y,K,X,H,U,R.x,R.y)&&D0(R.prev,R,R.next)>=0)return!1;R=R.next}return!0}function wE(J,Q,$,Z){let W=J.prev,K=J,H=J.next;if(D0(W,K,H)>=0)return!1;let Y=W.x,X=K.x,U=H.x,G=W.y,E=K.y,N=H.y,q=Math.min(Y,X,U),R=Math.min(G,E,N),F=Math.max(Y,X,U),O=Math.max(G,E,N),D=c$(q,R,Q,$,Z),k=c$(F,O,Q,$,Z),M=J.prevZ,L=J.nextZ;while(M&&M.z>=D&&L&&L.z<=k){if(M.x>=q&&M.x<=F&&M.y>=R&&M.y<=O&&M!==W&&M!==H&&A6(Y,G,X,E,U,N,M.x,M.y)&&D0(M.prev,M,M.next)>=0)return!1;if(M=M.prevZ,L.x>=q&&L.x<=F&&L.y>=R&&L.y<=O&&L!==W&&L!==H&&A6(Y,G,X,E,U,N,L.x,L.y)&&D0(L.prev,L,L.next)>=0)return!1;L=L.nextZ}while(M&&M.z>=D){if(M.x>=q&&M.x<=F&&M.y>=R&&M.y<=O&&M!==W&&M!==H&&A6(Y,G,X,E,U,N,M.x,M.y)&&D0(M.prev,M,M.next)>=0)return!1;M=M.prevZ}while(L&&L.z<=k){if(L.x>=q&&L.x<=F&&L.y>=R&&L.y<=O&&L!==W&&L!==H&&A6(Y,G,X,E,U,N,L.x,L.y)&&D0(L.prev,L,L.next)>=0)return!1;L=L.nextZ}return!0}function CE(J,Q){let $=J;do{let Z=$.prev,W=$.next.next;if(!a9(Z,W)&&SY(Z,$,$.next,W)&&f6(Z,W)&&f6(W,Z))Q.push(Z.i,$.i,W.i),b6($),b6($.next),$=J=W;$=$.next}while($!==J);return q9($)}function PE(J,Q,$,Z,W,K){let H=J;do{let Y=H.next.next;while(Y!==H.prev){if(H.i!==Y.i&&hE(H,Y)){let X=jY(H,Y);H=q9(H,H.next),X=q9(X,X.next),v6(H,Q,$,Z,W,K,0),v6(X,Q,$,Z,W,K,0);return}Y=Y.next}H=H.next}while(H!==J)}function AE(J,Q,$,Z){let W=[];for(let K=0,H=Q.length;K<H;K++){let Y=Q[K]*Z,X=K<H-1?Q[K+1]*Z:J.length,U=AY(J,Y,X,Z,!1);if(U===U.next)U.steiner=!0;W.push(bE(U))}W.sort(TE);for(let K=0;K<W.length;K++)$=SE(W[K],$);return $}function TE(J,Q){let $=J.x-Q.x;if($===0){if($=J.y-Q.y,$===0){let Z=(J.next.y-J.y)/(J.next.x-J.x),W=(Q.next.y-Q.y)/(Q.next.x-Q.x);$=Z-W}}return $}function SE(J,Q){let $=jE(J,Q);if(!$)return Q;let Z=jY($,J);return q9(Z,Z.next),q9($,$.next)}function jE(J,Q){let $=Q,Z=J.x,W=J.y,K=-1/0,H;if(a9(J,$))return $;do{if(a9(J,$.next))return $.next;else if(W<=$.y&&W>=$.next.y&&$.next.y!==$.y){let E=$.x+(W-$.y)*($.next.x-$.x)/($.next.y-$.y);if(E<=Z&&E>K){if(K=E,H=$.x<$.next.x?$:$.next,E===Z)return H}}$=$.next}while($!==Q);if(!H)return null;let Y=H,X=H.x,U=H.y,G=1/0;$=H;do{if(Z>=$.x&&$.x>=X&&Z!==$.x&&TY(W<U?Z:K,W,X,U,W<U?K:Z,W,$.x,$.y)){let E=Math.abs(W-$.y)/(Z-$.x);if(f6($,J)&&(E<G||E===G&&($.x>H.x||$.x===H.x&&yE(H,$))))H=$,G=E}$=$.next}while($!==Y);return H}function yE(J,Q){return D0(J.prev,J,Q.prev)<0&&D0(Q.next,J,J.next)<0}function vE(J,Q,$,Z){let W=J;do{if(W.z===0)W.z=c$(W.x,W.y,Q,$,Z);W.prevZ=W.prev,W.nextZ=W.next,W=W.next}while(W!==J);W.prevZ.nextZ=null,W.prevZ=null,fE(W)}function fE(J){let Q,$=1;do{let Z=J,W;J=null;let K=null;Q=0;while(Z){Q++;let H=Z,Y=0;for(let U=0;U<$;U++)if(Y++,H=H.nextZ,!H)break;let X=$;while(Y>0||X>0&&H){if(Y!==0&&(X===0||!H||Z.z<=H.z))W=Z,Z=Z.nextZ,Y--;else W=H,H=H.nextZ,X--;if(K)K.nextZ=W;else J=W;W.prevZ=K,K=W}Z=H}K.nextZ=null,$*=2}while(Q>1);return J}function c$(J,Q,$,Z,W){return J=(J-$)*W|0,Q=(Q-Z)*W|0,J=(J|J<<8)&16711935,J=(J|J<<4)&252645135,J=(J|J<<2)&858993459,J=(J|J<<1)&1431655765,Q=(Q|Q<<8)&16711935,Q=(Q|Q<<4)&252645135,Q=(Q|Q<<2)&858993459,Q=(Q|Q<<1)&1431655765,J|Q<<1}function bE(J){let Q=J,$=J;do{if(Q.x<$.x||Q.x===$.x&&Q.y<$.y)$=Q;Q=Q.next}while(Q!==J);return $}function TY(J,Q,$,Z,W,K,H,Y){return(W-H)*(Q-Y)>=(J-H)*(K-Y)&&(J-H)*(Z-Y)>=($-H)*(Q-Y)&&($-H)*(K-Y)>=(W-H)*(Z-Y)}function A6(J,Q,$,Z,W,K,H,Y){return!(J===H&&Q===Y)&&TY(J,Q,$,Z,W,K,H,Y)}function hE(J,Q){return J.next.i!==Q.i&&J.prev.i!==Q.i&&!xE(J,Q)&&(f6(J,Q)&&f6(Q,J)&&gE(J,Q)&&(D0(J.prev,J,Q.prev)||D0(J,Q.prev,Q))||a9(J,Q)&&D0(J.prev,J,J.next)>0&&D0(Q.prev,Q,Q.next)>0)}function D0(J,Q,$){return(Q.y-J.y)*($.x-Q.x)-(Q.x-J.x)*($.y-Q.y)}function a9(J,Q){return J.x===Q.x&&J.y===Q.y}function SY(J,Q,$,Z){let W=d7(D0(J,Q,$)),K=d7(D0(J,Q,Z)),H=d7(D0($,Z,J)),Y=d7(D0($,Z,Q));if(W!==K&&H!==Y)return!0;if(W===0&&m7(J,$,Q))return!0;if(K===0&&m7(J,Z,Q))return!0;if(H===0&&m7($,J,Z))return!0;if(Y===0&&m7($,Q,Z))return!0;return!1}function m7(J,Q,$){return Q.x<=Math.max(J.x,$.x)&&Q.x>=Math.min(J.x,$.x)&&Q.y<=Math.max(J.y,$.y)&&Q.y>=Math.min(J.y,$.y)}function d7(J){return J>0?1:J<0?-1:0}function xE(J,Q){let $=J;do{if($.i!==J.i&&$.next.i!==J.i&&$.i!==Q.i&&$.next.i!==Q.i&&SY($,$.next,J,Q))return!0;$=$.next}while($!==J);return!1}function f6(J,Q){return D0(J.prev,J,J.next)<0?D0(J,Q,J.next)>=0&&D0(J,J.prev,Q)>=0:D0(J,Q,J.prev)<0||D0(J,J.next,Q)<0}function gE(J,Q){let $=J,Z=!1,W=(J.x+Q.x)/2,K=(J.y+Q.y)/2;do{if($.y>K!==$.next.y>K&&$.next.y!==$.y&&W<($.next.x-$.x)*(K-$.y)/($.next.y-$.y)+$.x)Z=!Z;$=$.next}while($!==J);return Z}function jY(J,Q){let $=n$(J.i,J.x,J.y),Z=n$(Q.i,Q.x,Q.y),W=J.next,K=Q.prev;return J.next=Q,Q.prev=J,$.next=W,W.prev=$,Z.next=$,$.prev=Z,K.next=Z,Z.prev=K,Z}function hK(J,Q,$,Z){let W=n$(J,Q,$);if(!Z)W.prev=W,W.next=W;else W.next=Z.next,W.prev=Z,Z.next.prev=W,Z.next=W;return W}function b6(J){if(J.next.prev=J.prev,J.prev.next=J.next,J.prevZ)J.prevZ.nextZ=J.nextZ;if(J.nextZ)J.nextZ.prevZ=J.prevZ}function n$(J,Q,$){return{i:J,x:Q,y:$,prev:null,next:null,z:0,prevZ:null,nextZ:null,steiner:!1}}function pE(J,Q,$,Z){let W=0;for(let K=Q,H=$-Z;K<$;K+=Z)W+=(J[H]-J[K])*(J[K+1]+J[H+1]),H=K;return W}class yY{static triangulate(J,Q,$=2){return IE(J,Q,$)}}class W8{static area(J){let Q=J.length,$=0;for(let Z=Q-1,W=0;W<Q;Z=W++)$+=J[Z].x*J[W].y-J[W].x*J[Z].y;return $*0.5}static isClockWise(J){return W8.area(J)<0}static triangulateShape(J,Q){let $=[],Z=[],W=[];xK(J),gK($,J);let K=J.length;Q.forEach(xK);for(let Y=0;Y<Q.length;Y++)Z.push(K),K+=Q[Y].length,gK($,Q[Y]);let H=yY.triangulate($,Z);for(let Y=0;Y<H.length;Y+=3)W.push(H.slice(Y,Y+3));return W}}function xK(J){let Q=J.length;if(Q>2&&J[Q-1].equals(J[0]))J.pop()}function gK(J,Q){for(let $=0;$<Q.length;$++)J.push(Q[$].x),J.push(Q[$].y)}class fQ extends nJ{constructor(J=new p8([new t(0.5,0.5),new t(-0.5,0.5),new t(-0.5,-0.5),new t(0.5,-0.5)]),Q={}){super();this.type="ExtrudeGeometry",this.parameters={shapes:J,options:Q},J=Array.isArray(J)?J:[J];let $=this,Z=[],W=[];for(let H=0,Y=J.length;H<Y;H++){let X=J[H];K(X)}this.setAttribute("position",new BJ(Z,3)),this.setAttribute("uv",new BJ(W,2)),this.computeVertexNormals();function K(H){let Y=[],X=Q.curveSegments!==void 0?Q.curveSegments:12,U=Q.steps!==void 0?Q.steps:1,G=Q.depth!==void 0?Q.depth:1,E=Q.bevelEnabled!==void 0?Q.bevelEnabled:!0,N=Q.bevelThickness!==void 0?Q.bevelThickness:0.2,q=Q.bevelSize!==void 0?Q.bevelSize:N-0.1,R=Q.bevelOffset!==void 0?Q.bevelOffset:0,F=Q.bevelSegments!==void 0?Q.bevelSegments:3,O=Q.extrudePath,D=Q.UVGenerator!==void 0?Q.UVGenerator:mE,k,M=!1,L,A,_,C;if(O)k=O.getSpacedPoints(U),M=!0,E=!1,L=O.computeFrenetFrames(U,!1),A=new w,_=new w,C=new w;if(!E)F=0,N=0,q=0,R=0;let y=H.extractPoints(X),z=y.shape,I=y.holes;if(!W8.isClockWise(z)){z=z.reverse();for(let e=0,a=I.length;e<a;e++){let i=I[e];if(W8.isClockWise(i))I[e]=i.reverse()}}function p(e){let n=e[0];for(let UJ=1;UJ<=e.length;UJ++){let HJ=UJ%e.length,ZJ=e[HJ],lJ=ZJ.x-n.x,uJ=ZJ.y-n.y,sJ=lJ*lJ+uJ*uJ,P=Math.max(Math.abs(ZJ.x),Math.abs(ZJ.y),Math.abs(n.x),Math.abs(n.y)),V=0.000000000000000000010000000000000001*P*P;if(sJ<=V){e.splice(HJ,1),UJ--;continue}n=ZJ}}p(z),I.forEach(p);let d=I.length,x=z;for(let e=0;e<d;e++){let a=I[e];z=z.concat(a)}function o(e,a,i){if(!a)console.error("THREE.ExtrudeGeometry: vec does not exist");return e.clone().addScaledVector(a,i)}let l=z.length;function QJ(e,a,i){let n,UJ,HJ,ZJ=e.x-a.x,lJ=e.y-a.y,uJ=i.x-e.x,sJ=i.y-e.y,P=ZJ*ZJ+lJ*lJ,V=ZJ*sJ-lJ*uJ;if(Math.abs(V)>Number.EPSILON){let v=Math.sqrt(P),c=Math.sqrt(uJ*uJ+sJ*sJ),JJ=a.x-lJ/v,u=a.y+ZJ/v,VJ=i.x-sJ/c,YJ=i.y+uJ/c,_J=((VJ-JJ)*sJ-(YJ-u)*uJ)/(ZJ*sJ-lJ*uJ);n=JJ+ZJ*_J-e.x,UJ=u+lJ*_J-e.y;let vJ=n*n+UJ*UJ;if(vJ<=2)return new t(n,UJ);else HJ=Math.sqrt(vJ/2)}else{let v=!1;if(ZJ>Number.EPSILON){if(uJ>Number.EPSILON)v=!0}else if(ZJ<-Number.EPSILON){if(uJ<-Number.EPSILON)v=!0}else if(Math.sign(lJ)===Math.sign(sJ))v=!0;if(v)n=-lJ,UJ=ZJ,HJ=Math.sqrt(P);else n=ZJ,UJ=lJ,HJ=Math.sqrt(P/2)}return new t(n/HJ,UJ/HJ)}let m=[];for(let e=0,a=x.length,i=a-1,n=e+1;e<a;e++,i++,n++){if(i===a)i=0;if(n===a)n=0;m[e]=QJ(x[e],x[i],x[n])}let EJ=[],NJ,SJ=m.concat();for(let e=0,a=d;e<a;e++){let i=I[e];NJ=[];for(let n=0,UJ=i.length,HJ=UJ-1,ZJ=n+1;n<UJ;n++,HJ++,ZJ++){if(HJ===UJ)HJ=0;if(ZJ===UJ)ZJ=0;NJ[n]=QJ(i[n],i[HJ],i[ZJ])}EJ.push(NJ),SJ=SJ.concat(NJ)}let mJ;if(F===0)mJ=W8.triangulateShape(x,I);else{let e=[],a=[];for(let i=0;i<F;i++){let n=i/F,UJ=N*Math.cos(n*Math.PI/2),HJ=q*Math.sin(n*Math.PI/2)+R;for(let ZJ=0,lJ=x.length;ZJ<lJ;ZJ++){let uJ=o(x[ZJ],m[ZJ],HJ);if(LJ(uJ.x,uJ.y,-UJ),n===0)e.push(uJ)}for(let ZJ=0,lJ=d;ZJ<lJ;ZJ++){let uJ=I[ZJ];NJ=EJ[ZJ];let sJ=[];for(let P=0,V=uJ.length;P<V;P++){let v=o(uJ[P],NJ[P],HJ);if(LJ(v.x,v.y,-UJ),n===0)sJ.push(v)}if(n===0)a.push(sJ)}}mJ=W8.triangulateShape(e,a)}let U0=mJ.length,rJ=q+R;for(let e=0;e<l;e++){let a=E?o(z[e],SJ[e],rJ):z[e];if(!M)LJ(a.x,a.y,0);else _.copy(L.normals[0]).multiplyScalar(a.x),A.copy(L.binormals[0]).multiplyScalar(a.y),C.copy(k[0]).add(_).add(A),LJ(C.x,C.y,C.z)}for(let e=1;e<=U;e++)for(let a=0;a<l;a++){let i=E?o(z[a],SJ[a],rJ):z[a];if(!M)LJ(i.x,i.y,G/U*e);else _.copy(L.normals[e]).multiplyScalar(i.x),A.copy(L.binormals[e]).multiplyScalar(i.y),C.copy(k[e]).add(_).add(A),LJ(C.x,C.y,C.z)}for(let e=F-1;e>=0;e--){let a=e/F,i=N*Math.cos(a*Math.PI/2),n=q*Math.sin(a*Math.PI/2)+R;for(let UJ=0,HJ=x.length;UJ<HJ;UJ++){let ZJ=o(x[UJ],m[UJ],n);LJ(ZJ.x,ZJ.y,G+i)}for(let UJ=0,HJ=I.length;UJ<HJ;UJ++){let ZJ=I[UJ];NJ=EJ[UJ];for(let lJ=0,uJ=ZJ.length;lJ<uJ;lJ++){let sJ=o(ZJ[lJ],NJ[lJ],n);if(!M)LJ(sJ.x,sJ.y,G+i);else LJ(sJ.x,sJ.y+k[U-1].y,k[U-1].x+i)}}}s(),qJ();function s(){let e=Z.length/3;if(E){let a=0,i=l*a;for(let n=0;n<U0;n++){let UJ=mJ[n];yJ(UJ[2]+i,UJ[1]+i,UJ[0]+i)}a=U+F*2,i=l*a;for(let n=0;n<U0;n++){let UJ=mJ[n];yJ(UJ[0]+i,UJ[1]+i,UJ[2]+i)}}else{for(let a=0;a<U0;a++){let i=mJ[a];yJ(i[2],i[1],i[0])}for(let a=0;a<U0;a++){let i=mJ[a];yJ(i[0]+l*U,i[1]+l*U,i[2]+l*U)}}$.addGroup(e,Z.length/3-e,0)}function qJ(){let e=Z.length/3,a=0;XJ(x,a),a+=x.length;for(let i=0,n=I.length;i<n;i++){let UJ=I[i];XJ(UJ,a),a+=UJ.length}$.addGroup(e,Z.length/3-e,1)}function XJ(e,a){let i=e.length;while(--i>=0){let n=i,UJ=i-1;if(UJ<0)UJ=e.length-1;for(let HJ=0,ZJ=U+F*2;HJ<ZJ;HJ++){let lJ=l*HJ,uJ=l*(HJ+1),sJ=a+n+lJ,P=a+UJ+lJ,V=a+UJ+uJ,v=a+n+uJ;xJ(sJ,P,V,v)}}}function LJ(e,a,i){Y.push(e),Y.push(a),Y.push(i)}function yJ(e,a,i){W0(e),W0(a),W0(i);let n=Z.length/3,UJ=D.generateTopUV($,Z,n-3,n-2,n-1);T(UJ[0]),T(UJ[1]),T(UJ[2])}function xJ(e,a,i,n){W0(e),W0(a),W0(n),W0(a),W0(i),W0(n);let UJ=Z.length/3,HJ=D.generateSideWallUV($,Z,UJ-6,UJ-3,UJ-2,UJ-1);T(HJ[0]),T(HJ[1]),T(HJ[3]),T(HJ[1]),T(HJ[2]),T(HJ[3])}function W0(e){Z.push(Y[e*3+0]),Z.push(Y[e*3+1]),Z.push(Y[e*3+2])}function T(e){W.push(e.x),W.push(e.y)}}}copy(J){return super.copy(J),this.parameters=Object.assign({},J.parameters),this}toJSON(){let J=super.toJSON(),Q=this.parameters.shapes,$=this.parameters.options;return dE(Q,$,J)}static fromJSON(J,Q){let $=[];for(let W=0,K=J.shapes.length;W<K;W++){let H=Q[J.shapes[W]];$.push(H)}let Z=J.options.extrudePath;if(Z!==void 0)J.options.extrudePath=new t7[Z.type]().fromJSON(Z);return new fQ($,J.options)}}var mE={generateTopUV:function(J,Q,$,Z,W){let K=Q[$*3],H=Q[$*3+1],Y=Q[Z*3],X=Q[Z*3+1],U=Q[W*3],G=Q[W*3+1];return[new t(K,H),new t(Y,X),new t(U,G)]},generateSideWallUV:function(J,Q,$,Z,W,K){let H=Q[$*3],Y=Q[$*3+1],X=Q[$*3+2],U=Q[Z*3],G=Q[Z*3+1],E=Q[Z*3+2],N=Q[W*3],q=Q[W*3+1],R=Q[W*3+2],F=Q[K*3],O=Q[K*3+1],D=Q[K*3+2];if(Math.abs(Y-G)<Math.abs(H-U))return[new t(H,1-X),new t(U,1-E),new t(N,1-R),new t(F,1-D)];else return[new t(Y,1-X),new t(G,1-E),new t(q,1-R),new t(O,1-D)]}};function dE(J,Q,$){if($.shapes=[],Array.isArray(J))for(let Z=0,W=J.length;Z<W;Z++){let K=J[Z];$.shapes.push(K.uuid)}else $.shapes.push(J.uuid);if($.options=Object.assign({},Q),Q.extrudePath!==void 0)$.options.extrudePath=Q.extrudePath.toJSON();return $}class bQ extends u8{constructor(J=1,Q=0){let $=(1+Math.sqrt(5))/2,Z=[-1,$,0,1,$,0,-1,-$,0,1,-$,0,0,-1,$,0,1,$,0,-1,-$,0,1,-$,$,0,-1,$,0,1,-$,0,-1,-$,0,1],W=[0,11,5,0,5,1,0,1,7,0,7,10,0,10,11,1,5,9,5,11,4,11,10,2,10,7,6,7,1,8,3,9,4,3,4,2,3,2,6,3,6,8,3,8,9,4,9,5,2,4,11,6,2,10,8,6,7,9,8,1];super(Z,W,J,Q);this.type="IcosahedronGeometry",this.parameters={radius:J,detail:Q}}static fromJSON(J){return new bQ(J.radius,J.detail)}}class hQ extends nJ{constructor(J=[new t(0,-0.5),new t(0.5,0),new t(0,0.5)],Q=12,$=0,Z=Math.PI*2){super();this.type="LatheGeometry",this.parameters={points:J,segments:Q,phiStart:$,phiLength:Z},Q=Math.floor(Q),Z=bJ(Z,0,Math.PI*2);let W=[],K=[],H=[],Y=[],X=[],U=1/Q,G=new w,E=new t,N=new w,q=new w,R=new w,F=0,O=0;for(let D=0;D<=J.length-1;D++)switch(D){case 0:F=J[D+1].x-J[D].x,O=J[D+1].y-J[D].y,N.x=O*1,N.y=-F,N.z=O*0,R.copy(N),N.normalize(),Y.push(N.x,N.y,N.z);break;case J.length-1:Y.push(R.x,R.y,R.z);break;default:F=J[D+1].x-J[D].x,O=J[D+1].y-J[D].y,N.x=O*1,N.y=-F,N.z=O*0,q.copy(N),N.x+=R.x,N.y+=R.y,N.z+=R.z,N.normalize(),Y.push(N.x,N.y,N.z),R.copy(q)}for(let D=0;D<=Q;D++){let k=$+D*U*Z,M=Math.sin(k),L=Math.cos(k);for(let A=0;A<=J.length-1;A++){G.x=J[A].x*M,G.y=J[A].y,G.z=J[A].x*L,K.push(G.x,G.y,G.z),E.x=D/Q,E.y=A/(J.length-1),H.push(E.x,E.y);let _=Y[3*A+0]*M,C=Y[3*A+1],y=Y[3*A+0]*L;X.push(_,C,y)}}for(let D=0;D<Q;D++)for(let k=0;k<J.length-1;k++){let M=k+D*J.length,L=M,A=M+J.length,_=M+J.length+1,C=M+1;W.push(L,A,C),W.push(_,C,A)}this.setIndex(W),this.setAttribute("position",new BJ(K,3)),this.setAttribute("uv",new BJ(H,2)),this.setAttribute("normal",new BJ(X,3))}copy(J){return super.copy(J),this.parameters=Object.assign({},J.parameters),this}static fromJSON(J){return new hQ(J.points,J.segments,J.phiStart,J.phiLength)}}class Q7 extends u8{constructor(J=1,Q=0){let $=[1,0,0,-1,0,0,0,1,0,0,-1,0,0,0,1,0,0,-1],Z=[0,2,4,0,4,3,0,3,5,0,5,2,1,2,5,1,5,3,1,3,4,1,4,2];super($,Z,J,Q);this.type="OctahedronGeometry",this.parameters={radius:J,detail:Q}}static fromJSON(J){return new Q7(J.radius,J.detail)}}class U6 extends nJ{constructor(J=1,Q=1,$=1,Z=1){super();this.type="PlaneGeometry",this.parameters={width:J,height:Q,widthSegments:$,heightSegments:Z};let W=J/2,K=Q/2,H=Math.floor($),Y=Math.floor(Z),X=H+1,U=Y+1,G=J/H,E=Q/Y,N=[],q=[],R=[],F=[];for(let O=0;O<U;O++){let D=O*E-K;for(let k=0;k<X;k++){let M=k*G-W;q.push(M,-D,0),R.push(0,0,1),F.push(k/H),F.push(1-O/Y)}}for(let O=0;O<Y;O++)for(let D=0;D<H;D++){let k=D+X*O,M=D+X*(O+1),L=D+1+X*(O+1),A=D+1+X*O;N.push(k,M,A),N.push(M,L,A)}this.setIndex(N),this.setAttribute("position",new BJ(q,3)),this.setAttribute("normal",new BJ(R,3)),this.setAttribute("uv",new BJ(F,2))}copy(J){return super.copy(J),this.parameters=Object.assign({},J.parameters),this}static fromJSON(J){return new U6(J.width,J.height,J.widthSegments,J.heightSegments)}}class xQ extends nJ{constructor(J=0.5,Q=1,$=32,Z=1,W=0,K=Math.PI*2){super();this.type="RingGeometry",this.parameters={innerRadius:J,outerRadius:Q,thetaSegments:$,phiSegments:Z,thetaStart:W,thetaLength:K},$=Math.max(3,$),Z=Math.max(1,Z);let H=[],Y=[],X=[],U=[],G=J,E=(Q-J)/Z,N=new w,q=new t;for(let R=0;R<=Z;R++){for(let F=0;F<=$;F++){let O=W+F/$*K;N.x=G*Math.cos(O),N.y=G*Math.sin(O),Y.push(N.x,N.y,N.z),X.push(0,0,1),q.x=(N.x/Q+1)/2,q.y=(N.y/Q+1)/2,U.push(q.x,q.y)}G+=E}for(let R=0;R<Z;R++){let F=R*($+1);for(let O=0;O<$;O++){let D=O+F,k=D,M=D+$+1,L=D+$+2,A=D+1;H.push(k,M,A),H.push(M,L,A)}}this.setIndex(H),this.setAttribute("position",new BJ(Y,3)),this.setAttribute("normal",new BJ(X,3)),this.setAttribute("uv",new BJ(U,2))}copy(J){return super.copy(J),this.parameters=Object.assign({},J.parameters),this}static fromJSON(J){return new xQ(J.innerRadius,J.outerRadius,J.thetaSegments,J.phiSegments,J.thetaStart,J.thetaLength)}}class gQ extends nJ{constructor(J=new p8([new t(0,0.5),new t(-0.5,-0.5),new t(0.5,-0.5)]),Q=12){super();this.type="ShapeGeometry",this.parameters={shapes:J,curveSegments:Q};let $=[],Z=[],W=[],K=[],H=0,Y=0;if(Array.isArray(J)===!1)X(J);else for(let U=0;U<J.length;U++)X(J[U]),this.addGroup(H,Y,U),H+=Y,Y=0;this.setIndex($),this.setAttribute("position",new BJ(Z,3)),this.setAttribute("normal",new BJ(W,3)),this.setAttribute("uv",new BJ(K,2));function X(U){let G=Z.length/3,E=U.extractPoints(Q),N=E.shape,q=E.holes;if(W8.isClockWise(N)===!1)N=N.reverse();for(let F=0,O=q.length;F<O;F++){let D=q[F];if(W8.isClockWise(D)===!0)q[F]=D.reverse()}let R=W8.triangulateShape(N,q);for(let F=0,O=q.length;F<O;F++){let D=q[F];N=N.concat(D)}for(let F=0,O=N.length;F<O;F++){let D=N[F];Z.push(D.x,D.y,0),W.push(0,0,1),K.push(D.x,D.y)}for(let F=0,O=R.length;F<O;F++){let D=R[F],k=D[0]+G,M=D[1]+G,L=D[2]+G;$.push(k,M,L),Y+=3}}}copy(J){return super.copy(J),this.parameters=Object.assign({},J.parameters),this}toJSON(){let J=super.toJSON(),Q=this.parameters.shapes;return lE(Q,J)}static fromJSON(J,Q){let $=[];for(let Z=0,W=J.shapes.length;Z<W;Z++){let K=Q[J.shapes[Z]];$.push(K)}return new gQ($,J.curveSegments)}}function lE(J,Q){if(Q.shapes=[],Array.isArray(J))for(let $=0,Z=J.length;$<Z;$++){let W=J[$];Q.shapes.push(W.uuid)}else Q.shapes.push(J.uuid);return Q}class $7 extends nJ{constructor(J=1,Q=32,$=16,Z=0,W=Math.PI*2,K=0,H=Math.PI){super();this.type="SphereGeometry",this.parameters={radius:J,widthSegments:Q,heightSegments:$,phiStart:Z,phiLength:W,thetaStart:K,thetaLength:H},Q=Math.max(3,Math.floor(Q)),$=Math.max(2,Math.floor($));let Y=Math.min(K+H,Math.PI),X=0,U=[],G=new w,E=new w,N=[],q=[],R=[],F=[];for(let O=0;O<=$;O++){let D=[],k=O/$,M=0;if(O===0&&K===0)M=0.5/Q;else if(O===$&&Y===Math.PI)M=-0.5/Q;for(let L=0;L<=Q;L++){let A=L/Q;G.x=-J*Math.cos(Z+A*W)*Math.sin(K+k*H),G.y=J*Math.cos(K+k*H),G.z=J*Math.sin(Z+A*W)*Math.sin(K+k*H),q.push(G.x,G.y,G.z),E.copy(G).normalize(),R.push(E.x,E.y,E.z),F.push(A+M,1-k),D.push(X++)}U.push(D)}for(let O=0;O<$;O++)for(let D=0;D<Q;D++){let k=U[O][D+1],M=U[O][D],L=U[O+1][D],A=U[O+1][D+1];if(O!==0||K>0)N.push(k,M,A);if(O!==$-1||Y<Math.PI)N.push(M,L,A)}this.setIndex(N),this.setAttribute("position",new BJ(q,3)),this.setAttribute("normal",new BJ(R,3)),this.setAttribute("uv",new BJ(F,2))}copy(J){return super.copy(J),this.parameters=Object.assign({},J.parameters),this}static fromJSON(J){return new $7(J.radius,J.widthSegments,J.heightSegments,J.phiStart,J.phiLength,J.thetaStart,J.thetaLength)}}class pQ extends u8{constructor(J=1,Q=0){let $=[1,1,1,-1,-1,1,-1,1,-1,1,-1,-1],Z=[2,1,0,0,3,2,1,3,0,2,3,1];super($,Z,J,Q);this.type="TetrahedronGeometry",this.parameters={radius:J,detail:Q}}static fromJSON(J){return new pQ(J.radius,J.detail)}}class mQ extends nJ{constructor(J=1,Q=0.4,$=12,Z=48,W=Math.PI*2){super();this.type="TorusGeometry",this.parameters={radius:J,tube:Q,radialSegments:$,tubularSegments:Z,arc:W},$=Math.floor($),Z=Math.floor(Z);let K=[],H=[],Y=[],X=[],U=new w,G=new w,E=new w;for(let N=0;N<=$;N++)for(let q=0;q<=Z;q++){let R=q/Z*W,F=N/$*Math.PI*2;G.x=(J+Q*Math.cos(F))*Math.cos(R),G.y=(J+Q*Math.cos(F))*Math.sin(R),G.z=Q*Math.sin(F),H.push(G.x,G.y,G.z),U.x=J*Math.cos(R),U.y=J*Math.sin(R),E.subVectors(G,U).normalize(),Y.push(E.x,E.y,E.z),X.push(q/Z),X.push(N/$)}for(let N=1;N<=$;N++)for(let q=1;q<=Z;q++){let R=(Z+1)*N+q-1,F=(Z+1)*(N-1)+q-1,O=(Z+1)*(N-1)+q,D=(Z+1)*N+q;K.push(R,F,D),K.push(F,O,D)}this.setIndex(K),this.setAttribute("position",new BJ(H,3)),this.setAttribute("normal",new BJ(Y,3)),this.setAttribute("uv",new BJ(X,2))}copy(J){return super.copy(J),this.parameters=Object.assign({},J.parameters),this}static fromJSON(J){return new mQ(J.radius,J.tube,J.radialSegments,J.tubularSegments,J.arc)}}class dQ extends nJ{constructor(J=1,Q=0.4,$=64,Z=8,W=2,K=3){super();this.type="TorusKnotGeometry",this.parameters={radius:J,tube:Q,tubularSegments:$,radialSegments:Z,p:W,q:K},$=Math.floor($),Z=Math.floor(Z);let H=[],Y=[],X=[],U=[],G=new w,E=new w,N=new w,q=new w,R=new w,F=new w,O=new w;for(let k=0;k<=$;++k){let M=k/$*W*Math.PI*2;D(M,W,K,J,N),D(M+0.01,W,K,J,q),F.subVectors(q,N),O.addVectors(q,N),R.crossVectors(F,O),O.crossVectors(R,F),R.normalize(),O.normalize();for(let L=0;L<=Z;++L){let A=L/Z*Math.PI*2,_=-Q*Math.cos(A),C=Q*Math.sin(A);G.x=N.x+(_*O.x+C*R.x),G.y=N.y+(_*O.y+C*R.y),G.z=N.z+(_*O.z+C*R.z),Y.push(G.x,G.y,G.z),E.subVectors(G,N).normalize(),X.push(E.x,E.y,E.z),U.push(k/$),U.push(L/Z)}}for(let k=1;k<=$;k++)for(let M=1;M<=Z;M++){let L=(Z+1)*(k-1)+(M-1),A=(Z+1)*k+(M-1),_=(Z+1)*k+M,C=(Z+1)*(k-1)+M;H.push(L,A,C),H.push(A,_,C)}this.setIndex(H),this.setAttribute("position",new BJ(Y,3)),this.setAttribute("normal",new BJ(X,3)),this.setAttribute("uv",new BJ(U,2));function D(k,M,L,A,_){let C=Math.cos(k),y=Math.sin(k),z=L/M*k,I=Math.cos(z);_.x=A*(2+I)*0.5*C,_.y=A*(2+I)*y*0.5,_.z=A*Math.sin(z)*0.5}}copy(J){return super.copy(J),this.parameters=Object.assign({},J.parameters),this}static fromJSON(J){return new dQ(J.radius,J.tube,J.tubularSegments,J.radialSegments,J.p,J.q)}}class lQ extends nJ{constructor(J=new yQ(new w(-1,-1,0),new w(-1,1,0),new w(1,1,0)),Q=64,$=1,Z=8,W=!1){super();this.type="TubeGeometry",this.parameters={path:J,tubularSegments:Q,radius:$,radialSegments:Z,closed:W};let K=J.computeFrenetFrames(Q,W);this.tangents=K.tangents,this.normals=K.normals,this.binormals=K.binormals;let H=new w,Y=new w,X=new t,U=new w,G=[],E=[],N=[],q=[];R(),this.setIndex(q),this.setAttribute("position",new BJ(G,3)),this.setAttribute("normal",new BJ(E,3)),this.setAttribute("uv",new BJ(N,2));function R(){for(let k=0;k<Q;k++)F(k);F(W===!1?Q:0),D(),O()}function F(k){U=J.getPointAt(k/Q,U);let M=K.normals[k],L=K.binormals[k];for(let A=0;A<=Z;A++){let _=A/Z*Math.PI*2,C=Math.sin(_),y=-Math.cos(_);Y.x=y*M.x+C*L.x,Y.y=y*M.y+C*L.y,Y.z=y*M.z+C*L.z,Y.normalize(),E.push(Y.x,Y.y,Y.z),H.x=U.x+$*Y.x,H.y=U.y+$*Y.y,H.z=U.z+$*Y.z,G.push(H.x,H.y,H.z)}}function O(){for(let k=1;k<=Q;k++)for(let M=1;M<=Z;M++){let L=(Z+1)*(k-1)+(M-1),A=(Z+1)*k+(M-1),_=(Z+1)*k+M,C=(Z+1)*(k-1)+M;q.push(L,A,C),q.push(A,_,C)}}function D(){for(let k=0;k<=Q;k++)for(let M=0;M<=Z;M++)X.x=k/Q,X.y=M/Z,N.push(X.x,X.y)}}copy(J){return super.copy(J),this.parameters=Object.assign({},J.parameters),this}toJSON(){let J=super.toJSON();return J.path=this.parameters.path.toJSON(),J}static fromJSON(J){return new lQ(new t7[J.path.type]().fromJSON(J.path),J.tubularSegments,J.radius,J.radialSegments,J.closed)}}class HW extends nJ{constructor(J=null){super();if(this.type="WireframeGeometry",this.parameters={geometry:J},J!==null){let Q=[],$=new Set,Z=new w,W=new w;if(J.index!==null){let K=J.attributes.position,H=J.index,Y=J.groups;if(Y.length===0)Y=[{start:0,count:H.count,materialIndex:0}];for(let X=0,U=Y.length;X<U;++X){let G=Y[X],E=G.start,N=G.count;for(let q=E,R=E+N;q<R;q+=3)for(let F=0;F<3;F++){let O=H.getX(q+F),D=H.getX(q+(F+1)%3);if(Z.fromBufferAttribute(K,O),W.fromBufferAttribute(K,D),pK(Z,W,$)===!0)Q.push(Z.x,Z.y,Z.z),Q.push(W.x,W.y,W.z)}}}else{let K=J.attributes.position;for(let H=0,Y=K.count/3;H<Y;H++)for(let X=0;X<3;X++){let U=3*H+X,G=3*H+(X+1)%3;if(Z.fromBufferAttribute(K,U),W.fromBufferAttribute(K,G),pK(Z,W,$)===!0)Q.push(Z.x,Z.y,Z.z),Q.push(W.x,W.y,W.z)}}this.setAttribute("position",new BJ(Q,3))}}copy(J){return super.copy(J),this.parameters=Object.assign({},J.parameters),this}}function pK(J,Q,$){let Z=`${J.x},${J.y},${J.z}-${Q.x},${Q.y},${Q.z}`,W=`${Q.x},${Q.y},${Q.z}-${J.x},${J.y},${J.z}`;if($.has(Z)===!0||$.has(W)===!0)return!1;else return $.add(Z),$.add(W),!0}var mK=Object.freeze({__proto__:null,BoxGeometry:M9,CapsuleGeometry:CQ,CircleGeometry:PQ,ConeGeometry:e6,CylinderGeometry:t6,DodecahedronGeometry:AQ,EdgesGeometry:eZ,ExtrudeGeometry:fQ,IcosahedronGeometry:bQ,LatheGeometry:hQ,OctahedronGeometry:Q7,PlaneGeometry:U6,PolyhedronGeometry:u8,RingGeometry:xQ,ShapeGeometry:gQ,SphereGeometry:$7,TetrahedronGeometry:pQ,TorusGeometry:mQ,TorusKnotGeometry:dQ,TubeGeometry:lQ,WireframeGeometry:HW});class YW extends C0{constructor(J){super();this.isShadowMaterial=!0,this.type="ShadowMaterial",this.color=new kJ(0),this.transparent=!0,this.fog=!0,this.setValues(J)}copy(J){return super.copy(J),this.color.copy(J.color),this.fog=J.fog,this}}class XW extends e0{constructor(J){super(J);this.isRawShaderMaterial=!0,this.type="RawShaderMaterial"}}class uQ extends C0{constructor(J){super();this.isMeshStandardMaterial=!0,this.type="MeshStandardMaterial",this.defines={STANDARD:""},this.color=new kJ(16777215),this.roughness=1,this.metalness=0,this.map=null,this.lightMap=null,this.lightMapIntensity=1,this.aoMap=null,this.aoMapIntensity=1,this.emissive=new kJ(0),this.emissiveIntensity=1,this.emissiveMap=null,this.bumpMap=null,this.bumpScale=1,this.normalMap=null,this.normalMapType=0,this.normalScale=new t(1,1),this.displacementMap=null,this.displacementScale=1,this.displacementBias=0,this.roughnessMap=null,this.metalnessMap=null,this.alphaMap=null,this.envMap=null,this.envMapRotation=new s0,this.envMapIntensity=1,this.wireframe=!1,this.wireframeLinewidth=1,this.wireframeLinecap="round",this.wireframeLinejoin="round",this.flatShading=!1,this.fog=!0,this.setValues(J)}copy(J){return super.copy(J),this.defines={STANDARD:""},this.color.copy(J.color),this.roughness=J.roughness,this.metalness=J.metalness,this.map=J.map,this.lightMap=J.lightMap,this.lightMapIntensity=J.lightMapIntensity,this.aoMap=J.aoMap,this.aoMapIntensity=J.aoMapIntensity,this.emissive.copy(J.emissive),this.emissiveMap=J.emissiveMap,this.emissiveIntensity=J.emissiveIntensity,this.bumpMap=J.bumpMap,this.bumpScale=J.bumpScale,this.normalMap=J.normalMap,this.normalMapType=J.normalMapType,this.normalScale.copy(J.normalScale),this.displacementMap=J.displacementMap,this.displacementScale=J.displacementScale,this.displacementBias=J.displacementBias,this.roughnessMap=J.roughnessMap,this.metalnessMap=J.metalnessMap,this.alphaMap=J.alphaMap,this.envMap=J.envMap,this.envMapRotation.copy(J.envMapRotation),this.envMapIntensity=J.envMapIntensity,this.wireframe=J.wireframe,this.wireframeLinewidth=J.wireframeLinewidth,this.wireframeLinecap=J.wireframeLinecap,this.wireframeLinejoin=J.wireframeLinejoin,this.flatShading=J.flatShading,this.fog=J.fog,this}}class UW extends uQ{constructor(J){super();this.isMeshPhysicalMaterial=!0,this.defines={STANDARD:"",PHYSICAL:""},this.type="MeshPhysicalMaterial",this.anisotropyRotation=0,this.anisotropyMap=null,this.clearcoatMap=null,this.clearcoatRoughness=0,this.clearcoatRoughnessMap=null,this.clearcoatNormalScale=new t(1,1),this.clearcoatNormalMap=null,this.ior=1.5,Object.defineProperty(this,"reflectivity",{get:function(){return bJ(2.5*(this.ior-1)/(this.ior+1),0,1)},set:function(Q){this.ior=(1+0.4*Q)/(1-0.4*Q)}}),this.iridescenceMap=null,this.iridescenceIOR=1.3,this.iridescenceThicknessRange=[100,400],this.iridescenceThicknessMap=null,this.sheenColor=new kJ(0),this.sheenColorMap=null,this.sheenRoughness=1,this.sheenRoughnessMap=null,this.transmissionMap=null,this.thickness=0,this.thicknessMap=null,this.attenuationDistance=1/0,this.attenuationColor=new kJ(1,1,1),this.specularIntensity=1,this.specularIntensityMap=null,this.specularColor=new kJ(1,1,1),this.specularColorMap=null,this._anisotropy=0,this._clearcoat=0,this._dispersion=0,this._iridescence=0,this._sheen=0,this._transmission=0,this.setValues(J)}get anisotropy(){return this._anisotropy}set anisotropy(J){if(this._anisotropy>0!==J>0)this.version++;this._anisotropy=J}get clearcoat(){return this._clearcoat}set clearcoat(J){if(this._clearcoat>0!==J>0)this.version++;this._clearcoat=J}get iridescence(){return this._iridescence}set iridescence(J){if(this._iridescence>0!==J>0)this.version++;this._iridescence=J}get dispersion(){return this._dispersion}set dispersion(J){if(this._dispersion>0!==J>0)this.version++;this._dispersion=J}get sheen(){return this._sheen}set sheen(J){if(this._sheen>0!==J>0)this.version++;this._sheen=J}get transmission(){return this._transmission}set transmission(J){if(this._transmission>0!==J>0)this.version++;this._transmission=J}copy(J){return super.copy(J),this.defines={STANDARD:"",PHYSICAL:""},this.anisotropy=J.anisotropy,this.anisotropyRotation=J.anisotropyRotation,this.anisotropyMap=J.anisotropyMap,this.clearcoat=J.clearcoat,this.clearcoatMap=J.clearcoatMap,this.clearcoatRoughness=J.clearcoatRoughness,this.clearcoatRoughnessMap=J.clearcoatRoughnessMap,this.clearcoatNormalMap=J.clearcoatNormalMap,this.clearcoatNormalScale.copy(J.clearcoatNormalScale),this.dispersion=J.dispersion,this.ior=J.ior,this.iridescence=J.iridescence,this.iridescenceMap=J.iridescenceMap,this.iridescenceIOR=J.iridescenceIOR,this.iridescenceThicknessRange=[...J.iridescenceThicknessRange],this.iridescenceThicknessMap=J.iridescenceThicknessMap,this.sheen=J.sheen,this.sheenColor.copy(J.sheenColor),this.sheenColorMap=J.sheenColorMap,this.sheenRoughness=J.sheenRoughness,this.sheenRoughnessMap=J.sheenRoughnessMap,this.transmission=J.transmission,this.transmissionMap=J.transmissionMap,this.thickness=J.thickness,this.thicknessMap=J.thicknessMap,this.attenuationDistance=J.attenuationDistance,this.attenuationColor.copy(J.attenuationColor),this.specularIntensity=J.specularIntensity,this.specularIntensityMap=J.specularIntensityMap,this.specularColor.copy(J.specularColor),this.specularColorMap=J.specularColorMap,this}}class GW extends C0{constructor(J){super();this.isMeshPhongMaterial=!0,this.type="MeshPhongMaterial",this.color=new kJ(16777215),this.specular=new kJ(1118481),this.shininess=30,this.map=null,this.lightMap=null,this.lightMapIntensity=1,this.aoMap=null,this.aoMapIntensity=1,this.emissive=new kJ(0),this.emissiveIntensity=1,this.emissiveMap=null,this.bumpMap=null,this.bumpScale=1,this.normalMap=null,this.normalMapType=0,this.normalScale=new t(1,1),this.displacementMap=null,this.displacementScale=1,this.displacementBias=0,this.specularMap=null,this.alphaMap=null,this.envMap=null,this.envMapRotation=new s0,this.combine=0,this.reflectivity=1,this.refractionRatio=0.98,this.wireframe=!1,this.wireframeLinewidth=1,this.wireframeLinecap="round",this.wireframeLinejoin="round",this.flatShading=!1,this.fog=!0,this.setValues(J)}copy(J){return super.copy(J),this.color.copy(J.color),this.specular.copy(J.specular),this.shininess=J.shininess,this.map=J.map,this.lightMap=J.lightMap,this.lightMapIntensity=J.lightMapIntensity,this.aoMap=J.aoMap,this.aoMapIntensity=J.aoMapIntensity,this.emissive.copy(J.emissive),this.emissiveMap=J.emissiveMap,this.emissiveIntensity=J.emissiveIntensity,this.bumpMap=J.bumpMap,this.bumpScale=J.bumpScale,this.normalMap=J.normalMap,this.normalMapType=J.normalMapType,this.normalScale.copy(J.normalScale),this.displacementMap=J.displacementMap,this.displacementScale=J.displacementScale,this.displacementBias=J.displacementBias,this.specularMap=J.specularMap,this.alphaMap=J.alphaMap,this.envMap=J.envMap,this.envMapRotation.copy(J.envMapRotation),this.combine=J.combine,this.reflectivity=J.reflectivity,this.refractionRatio=J.refractionRatio,this.wireframe=J.wireframe,this.wireframeLinewidth=J.wireframeLinewidth,this.wireframeLinecap=J.wireframeLinecap,this.wireframeLinejoin=J.wireframeLinejoin,this.flatShading=J.flatShading,this.fog=J.fog,this}}class EW extends C0{constructor(J){super();this.isMeshToonMaterial=!0,this.defines={TOON:""},this.type="MeshToonMaterial",this.color=new kJ(16777215),this.map=null,this.gradientMap=null,this.lightMap=null,this.lightMapIntensity=1,this.aoMap=null,this.aoMapIntensity=1,this.emissive=new kJ(0),this.emissiveIntensity=1,this.emissiveMap=null,this.bumpMap=null,this.bumpScale=1,this.normalMap=null,this.normalMapType=0,this.normalScale=new t(1,1),this.displacementMap=null,this.displacementScale=1,this.displacementBias=0,this.alphaMap=null,this.wireframe=!1,this.wireframeLinewidth=1,this.wireframeLinecap="round",this.wireframeLinejoin="round",this.fog=!0,this.setValues(J)}copy(J){return super.copy(J),this.color.copy(J.color),this.map=J.map,this.gradientMap=J.gradientMap,this.lightMap=J.lightMap,this.lightMapIntensity=J.lightMapIntensity,this.aoMap=J.aoMap,this.aoMapIntensity=J.aoMapIntensity,this.emissive.copy(J.emissive),this.emissiveMap=J.emissiveMap,this.emissiveIntensity=J.emissiveIntensity,this.bumpMap=J.bumpMap,this.bumpScale=J.bumpScale,this.normalMap=J.normalMap,this.normalMapType=J.normalMapType,this.normalScale.copy(J.normalScale),this.displacementMap=J.displacementMap,this.displacementScale=J.displacementScale,this.displacementBias=J.displacementBias,this.alphaMap=J.alphaMap,this.wireframe=J.wireframe,this.wireframeLinewidth=J.wireframeLinewidth,this.wireframeLinecap=J.wireframeLinecap,this.wireframeLinejoin=J.wireframeLinejoin,this.fog=J.fog,this}}class NW extends C0{constructor(J){super();this.isMeshNormalMaterial=!0,this.type="MeshNormalMaterial",this.bumpMap=null,this.bumpScale=1,this.normalMap=null,this.normalMapType=0,this.normalScale=new t(1,1),this.displacementMap=null,this.displacementScale=1,this.displacementBias=0,this.wireframe=!1,this.wireframeLinewidth=1,this.flatShading=!1,this.setValues(J)}copy(J){return super.copy(J),this.bumpMap=J.bumpMap,this.bumpScale=J.bumpScale,this.normalMap=J.normalMap,this.normalMapType=J.normalMapType,this.normalScale.copy(J.normalScale),this.displacementMap=J.displacementMap,this.displacementScale=J.displacementScale,this.displacementBias=J.displacementBias,this.wireframe=J.wireframe,this.wireframeLinewidth=J.wireframeLinewidth,this.flatShading=J.flatShading,this}}class qW extends C0{constructor(J){super();this.isMeshLambertMaterial=!0,this.type="MeshLambertMaterial",this.color=new kJ(16777215),this.map=null,this.lightMap=null,this.lightMapIntensity=1,this.aoMap=null,this.aoMapIntensity=1,this.emissive=new kJ(0),this.emissiveIntensity=1,this.emissiveMap=null,this.bumpMap=null,this.bumpScale=1,this.normalMap=null,this.normalMapType=0,this.normalScale=new t(1,1),this.displacementMap=null,this.displacementScale=1,this.displacementBias=0,this.specularMap=null,this.alphaMap=null,this.envMap=null,this.envMapRotation=new s0,this.combine=0,this.reflectivity=1,this.refractionRatio=0.98,this.wireframe=!1,this.wireframeLinewidth=1,this.wireframeLinecap="round",this.wireframeLinejoin="round",this.flatShading=!1,this.fog=!0,this.setValues(J)}copy(J){return super.copy(J),this.color.copy(J.color),this.map=J.map,this.lightMap=J.lightMap,this.lightMapIntensity=J.lightMapIntensity,this.aoMap=J.aoMap,this.aoMapIntensity=J.aoMapIntensity,this.emissive.copy(J.emissive),this.emissiveMap=J.emissiveMap,this.emissiveIntensity=J.emissiveIntensity,this.bumpMap=J.bumpMap,this.bumpScale=J.bumpScale,this.normalMap=J.normalMap,this.normalMapType=J.normalMapType,this.normalScale.copy(J.normalScale),this.displacementMap=J.displacementMap,this.displacementScale=J.displacementScale,this.displacementBias=J.displacementBias,this.specularMap=J.specularMap,this.alphaMap=J.alphaMap,this.envMap=J.envMap,this.envMapRotation.copy(J.envMapRotation),this.combine=J.combine,this.reflectivity=J.reflectivity,this.refractionRatio=J.refractionRatio,this.wireframe=J.wireframe,this.wireframeLinewidth=J.wireframeLinewidth,this.wireframeLinecap=J.wireframeLinecap,this.wireframeLinejoin=J.wireframeLinejoin,this.flatShading=J.flatShading,this.fog=J.fog,this}}class cQ extends C0{constructor(J){super();this.isMeshDepthMaterial=!0,this.type="MeshDepthMaterial",this.depthPacking=3200,this.map=null,this.alphaMap=null,this.displacementMap=null,this.displacementScale=1,this.displacementBias=0,this.wireframe=!1,this.wireframeLinewidth=1,this.setValues(J)}copy(J){return super.copy(J),this.depthPacking=J.depthPacking,this.map=J.map,this.alphaMap=J.alphaMap,this.displacementMap=J.displacementMap,this.displacementScale=J.displacementScale,this.displacementBias=J.displacementBias,this.wireframe=J.wireframe,this.wireframeLinewidth=J.wireframeLinewidth,this}}class nQ extends C0{constructor(J){super();this.isMeshDistanceMaterial=!0,this.type="MeshDistanceMaterial",this.map=null,this.alphaMap=null,this.displacementMap=null,this.displacementScale=1,this.displacementBias=0,this.setValues(J)}copy(J){return super.copy(J),this.map=J.map,this.alphaMap=J.alphaMap,this.displacementMap=J.displacementMap,this.displacementScale=J.displacementScale,this.displacementBias=J.displacementBias,this}}class DW extends C0{constructor(J){super();this.isMeshMatcapMaterial=!0,this.defines={MATCAP:""},this.type="MeshMatcapMaterial",this.color=new kJ(16777215),this.matcap=null,this.map=null,this.bumpMap=null,this.bumpScale=1,this.normalMap=null,this.normalMapType=0,this.normalScale=new t(1,1),this.displacementMap=null,this.displacementScale=1,this.displacementBias=0,this.alphaMap=null,this.flatShading=!1,this.fog=!0,this.setValues(J)}copy(J){return super.copy(J),this.defines={MATCAP:""},this.color.copy(J.color),this.matcap=J.matcap,this.map=J.map,this.bumpMap=J.bumpMap,this.bumpScale=J.bumpScale,this.normalMap=J.normalMap,this.normalMapType=J.normalMapType,this.normalScale.copy(J.normalScale),this.displacementMap=J.displacementMap,this.displacementScale=J.displacementScale,this.displacementBias=J.displacementBias,this.alphaMap=J.alphaMap,this.flatShading=J.flatShading,this.fog=J.fog,this}}class OW extends j0{constructor(J){super();this.isLineDashedMaterial=!0,this.type="LineDashedMaterial",this.scale=1,this.dashSize=3,this.gapSize=1,this.setValues(J)}copy(J){return super.copy(J),this.scale=J.scale,this.dashSize=J.dashSize,this.gapSize=J.gapSize,this}}function X9(J,Q){if(!J||J.constructor===Q)return J;if(typeof Q.BYTES_PER_ELEMENT==="number")return new Q(J);return Array.prototype.slice.call(J)}function vY(J){return ArrayBuffer.isView(J)&&!(J instanceof DataView)}function fY(J){function Q(W,K){return J[W]-J[K]}let $=J.length,Z=Array($);for(let W=0;W!==$;++W)Z[W]=W;return Z.sort(Q),Z}function s$(J,Q,$){let Z=J.length,W=new J.constructor(Z);for(let K=0,H=0;H!==Z;++K){let Y=$[K]*Q;for(let X=0;X!==Q;++X)W[H++]=J[Y+X]}return W}function RW(J,Q,$,Z){let W=1,K=J[0];while(K!==void 0&&K[Z]===void 0)K=J[W++];if(K===void 0)return;let H=K[Z];if(H===void 0)return;if(Array.isArray(H))do{if(H=K[Z],H!==void 0)Q.push(K.time),$.push(...H);K=J[W++]}while(K!==void 0);else if(H.toArray!==void 0)do{if(H=K[Z],H!==void 0)Q.push(K.time),H.toArray($,$.length);K=J[W++]}while(K!==void 0);else do{if(H=K[Z],H!==void 0)Q.push(K.time),$.push(H);K=J[W++]}while(K!==void 0)}function uE(J,Q,$,Z,W=30){let K=J.clone();K.name=Q;let H=[];for(let X=0;X<K.tracks.length;++X){let U=K.tracks[X],G=U.getValueSize(),E=[],N=[];for(let q=0;q<U.times.length;++q){let R=U.times[q]*W;if(R<$||R>=Z)continue;E.push(U.times[q]);for(let F=0;F<G;++F)N.push(U.values[q*G+F])}if(E.length===0)continue;U.times=X9(E,U.times.constructor),U.values=X9(N,U.values.constructor),H.push(U)}K.tracks=H;let Y=1/0;for(let X=0;X<K.tracks.length;++X)if(Y>K.tracks[X].times[0])Y=K.tracks[X].times[0];for(let X=0;X<K.tracks.length;++X)K.tracks[X].shift(-1*Y);return K.resetDuration(),K}function cE(J,Q=0,$=J,Z=30){if(Z<=0)Z=30;let W=$.tracks.length,K=Q/Z;for(let H=0;H<W;++H){let Y=$.tracks[H],X=Y.ValueTypeName;if(X==="bool"||X==="string")continue;let U=J.tracks.find(function(D){return D.name===Y.name&&D.ValueTypeName===X});if(U===void 0)continue;let G=0,E=Y.getValueSize();if(Y.createInterpolant.isInterpolantFactoryMethodGLTFCubicSpline)G=E/3;let N=0,q=U.getValueSize();if(U.createInterpolant.isInterpolantFactoryMethodGLTFCubicSpline)N=q/3;let R=Y.times.length-1,F;if(K<=Y.times[0]){let D=G,k=E-G;F=Y.values.slice(D,k)}else if(K>=Y.times[R]){let D=R*E+G,k=D+E-G;F=Y.values.slice(D,k)}else{let D=Y.createInterpolant(),k=G,M=E-G;D.evaluate(K),F=D.resultBuffer.slice(k,M)}if(X==="quaternion")new b0().fromArray(F).normalize().conjugate().toArray(F);let O=U.times.length;for(let D=0;D<O;++D){let k=D*q+N;if(X==="quaternion")b0.multiplyQuaternionsFlat(U.values,k,F,0,U.values,k);else{let M=q-N*2;for(let L=0;L<M;++L)U.values[k+L]-=F[L]}}}return J.blendMode=2501,J}class bY{static convertArray(J,Q){return X9(J,Q)}static isTypedArray(J){return vY(J)}static getKeyframeOrder(J){return fY(J)}static sortedArray(J,Q,$){return s$(J,Q,$)}static flattenJSON(J,Q,$,Z){RW(J,Q,$,Z)}static subclip(J,Q,$,Z,W=30){return uE(J,Q,$,Z,W)}static makeClipAdditive(J,Q=0,$=J,Z=30){return cE(J,Q,$,Z)}}class G6{constructor(J,Q,$,Z){this.parameterPositions=J,this._cachedIndex=0,this.resultBuffer=Z!==void 0?Z:new Q.constructor($),this.sampleValues=Q,this.valueSize=$,this.settings=null,this.DefaultSettings_={}}evaluate(J){let Q=this.parameterPositions,$=this._cachedIndex,Z=Q[$],W=Q[$-1];J:{Q:{let K;$:{Z:if(!(J<Z)){for(let H=$+2;;){if(Z===void 0){if(J<W)break Z;return $=Q.length,this._cachedIndex=$,this.copySampleValue_($-1)}if($===H)break;if(W=Z,Z=Q[++$],J<Z)break Q}K=Q.length;break $}if(!(J>=W)){let H=Q[1];if(J<H)$=2,W=H;for(let Y=$-2;;){if(W===void 0)return this._cachedIndex=0,this.copySampleValue_(0);if($===Y)break;if(Z=W,W=Q[--$-1],J>=W)break Q}K=$,$=0;break $}break J}while($<K){let H=$+K>>>1;if(J<Q[H])K=H;else $=H+1}if(Z=Q[$],W=Q[$-1],W===void 0)return this._cachedIndex=0,this.copySampleValue_(0);if(Z===void 0)return $=Q.length,this._cachedIndex=$,this.copySampleValue_($-1)}this._cachedIndex=$,this.intervalChanged_($,W,Z)}return this.interpolate_($,W,J,Z)}getSettings_(){return this.settings||this.DefaultSettings_}copySampleValue_(J){let Q=this.resultBuffer,$=this.sampleValues,Z=this.valueSize,W=J*Z;for(let K=0;K!==Z;++K)Q[K]=$[W+K];return Q}interpolate_(){throw Error("call to abstract method")}intervalChanged_(){}}class FW extends G6{constructor(J,Q,$,Z){super(J,Q,$,Z);this._weightPrev=-0,this._offsetPrev=-0,this._weightNext=-0,this._offsetNext=-0,this.DefaultSettings_={endingStart:2400,endingEnd:2400}}intervalChanged_(J,Q,$){let Z=this.parameterPositions,W=J-2,K=J+1,H=Z[W],Y=Z[K];if(H===void 0)switch(this.getSettings_().endingStart){case 2401:W=J,H=2*Q-$;break;case 2402:W=Z.length-2,H=Q+Z[W]-Z[W+1];break;default:W=J,H=$}if(Y===void 0)switch(this.getSettings_().endingEnd){case 2401:K=J,Y=2*$-Q;break;case 2402:K=1,Y=$+Z[1]-Z[0];break;default:K=J-1,Y=Q}let X=($-Q)*0.5,U=this.valueSize;this._weightPrev=X/(Q-H),this._weightNext=X/(Y-$),this._offsetPrev=W*U,this._offsetNext=K*U}interpolate_(J,Q,$,Z){let W=this.resultBuffer,K=this.sampleValues,H=this.valueSize,Y=J*H,X=Y-H,U=this._offsetPrev,G=this._offsetNext,E=this._weightPrev,N=this._weightNext,q=($-Q)/(Z-Q),R=q*q,F=R*q,O=-E*F+2*E*R-E*q,D=(1+E)*F+(-1.5-2*E)*R+(-0.5+E)*q+1,k=(-1-N)*F+(1.5+N)*R+0.5*q,M=N*F-N*R;for(let L=0;L!==H;++L)W[L]=O*K[U+L]+D*K[X+L]+k*K[Y+L]+M*K[G+L];return W}}class sQ extends G6{constructor(J,Q,$,Z){super(J,Q,$,Z)}interpolate_(J,Q,$,Z){let W=this.resultBuffer,K=this.sampleValues,H=this.valueSize,Y=J*H,X=Y-H,U=($-Q)/(Z-Q),G=1-U;for(let E=0;E!==H;++E)W[E]=K[X+E]*G+K[Y+E]*U;return W}}class MW extends G6{constructor(J,Q,$,Z){super(J,Q,$,Z)}interpolate_(J){return this.copySampleValue_(J-1)}}class o0{constructor(J,Q,$,Z){if(J===void 0)throw Error("THREE.KeyframeTrack: track name is undefined");if(Q===void 0||Q.length===0)throw Error("THREE.KeyframeTrack: no keyframes in track named "+J);this.name=J,this.times=X9(Q,this.TimeBufferType),this.values=X9($,this.ValueBufferType),this.setInterpolation(Z||this.DefaultInterpolation)}static toJSON(J){let Q=J.constructor,$;if(Q.toJSON!==this.toJSON)$=Q.toJSON(J);else{$={name:J.name,times:X9(J.times,Array),values:X9(J.values,Array)};let Z=J.getInterpolation();if(Z!==J.DefaultInterpolation)$.interpolation=Z}return $.type=J.ValueTypeName,$}InterpolantFactoryMethodDiscrete(J){return new MW(this.times,this.values,this.getValueSize(),J)}InterpolantFactoryMethodLinear(J){return new sQ(this.times,this.values,this.getValueSize(),J)}InterpolantFactoryMethodSmooth(J){return new FW(this.times,this.values,this.getValueSize(),J)}setInterpolation(J){let Q;switch(J){case 2300:Q=this.InterpolantFactoryMethodDiscrete;break;case 2301:Q=this.InterpolantFactoryMethodLinear;break;case 2302:Q=this.InterpolantFactoryMethodSmooth;break}if(Q===void 0){let $="unsupported interpolation for "+this.ValueTypeName+" keyframe track named "+this.name;if(this.createInterpolant===void 0)if(J!==this.DefaultInterpolation)this.setInterpolation(this.DefaultInterpolation);else throw Error($);return console.warn("THREE.KeyframeTrack:",$),this}return this.createInterpolant=Q,this}getInterpolation(){switch(this.createInterpolant){case this.InterpolantFactoryMethodDiscrete:return 2300;case this.InterpolantFactoryMethodLinear:return 2301;case this.InterpolantFactoryMethodSmooth:return 2302}}getValueSize(){return this.values.length/this.times.length}shift(J){if(J!==0){let Q=this.times;for(let $=0,Z=Q.length;$!==Z;++$)Q[$]+=J}return this}scale(J){if(J!==1){let Q=this.times;for(let $=0,Z=Q.length;$!==Z;++$)Q[$]*=J}return this}trim(J,Q){let $=this.times,Z=$.length,W=0,K=Z-1;while(W!==Z&&$[W]<J)++W;while(K!==-1&&$[K]>Q)--K;if(++K,W!==0||K!==Z){if(W>=K)K=Math.max(K,1),W=K-1;let H=this.getValueSize();this.times=$.slice(W,K),this.values=this.values.slice(W*H,K*H)}return this}validate(){let J=!0,Q=this.getValueSize();if(Q-Math.floor(Q)!==0)console.error("THREE.KeyframeTrack: Invalid value size in track.",this),J=!1;let $=this.times,Z=this.values,W=$.length;if(W===0)console.error("THREE.KeyframeTrack: Track is empty.",this),J=!1;let K=null;for(let H=0;H!==W;H++){let Y=$[H];if(typeof Y==="number"&&isNaN(Y)){console.error("THREE.KeyframeTrack: Time is not a valid number.",this,H,Y),J=!1;break}if(K!==null&&K>Y){console.error("THREE.KeyframeTrack: Out of order keys.",this,H,Y,K),J=!1;break}K=Y}if(Z!==void 0){if(vY(Z))for(let H=0,Y=Z.length;H!==Y;++H){let X=Z[H];if(isNaN(X)){console.error("THREE.KeyframeTrack: Value is not a valid number.",this,H,X),J=!1;break}}}return J}optimize(){let J=this.times.slice(),Q=this.values.slice(),$=this.getValueSize(),Z=this.getInterpolation()===2302,W=J.length-1,K=1;for(let H=1;H<W;++H){let Y=!1,X=J[H],U=J[H+1];if(X!==U&&(H!==1||X!==J[0]))if(!Z){let G=H*$,E=G-$,N=G+$;for(let q=0;q!==$;++q){let R=Q[G+q];if(R!==Q[E+q]||R!==Q[N+q]){Y=!0;break}}}else Y=!0;if(Y){if(H!==K){J[K]=J[H];let G=H*$,E=K*$;for(let N=0;N!==$;++N)Q[E+N]=Q[G+N]}++K}}if(W>0){J[K]=J[W];for(let H=W*$,Y=K*$,X=0;X!==$;++X)Q[Y+X]=Q[H+X];++K}if(K!==J.length)this.times=J.slice(0,K),this.values=Q.slice(0,K*$);else this.times=J,this.values=Q;return this}clone(){let J=this.times.slice(),Q=this.values.slice(),Z=new this.constructor(this.name,J,Q);return Z.createInterpolant=this.createInterpolant,Z}}o0.prototype.ValueTypeName="";o0.prototype.TimeBufferType=Float32Array;o0.prototype.ValueBufferType=Float32Array;o0.prototype.DefaultInterpolation=2301;class c8 extends o0{constructor(J,Q,$){super(J,Q,$)}}c8.prototype.ValueTypeName="bool";c8.prototype.ValueBufferType=Array;c8.prototype.DefaultInterpolation=2300;c8.prototype.InterpolantFactoryMethodLinear=void 0;c8.prototype.InterpolantFactoryMethodSmooth=void 0;class iQ extends o0{constructor(J,Q,$,Z){super(J,Q,$,Z)}}iQ.prototype.ValueTypeName="color";class r9 extends o0{constructor(J,Q,$,Z){super(J,Q,$,Z)}}r9.prototype.ValueTypeName="number";class kW extends G6{constructor(J,Q,$,Z){super(J,Q,$,Z)}interpolate_(J,Q,$,Z){let W=this.resultBuffer,K=this.sampleValues,H=this.valueSize,Y=($-Q)/(Z-Q),X=J*H;for(let U=X+H;X!==U;X+=4)b0.slerpFlat(W,0,K,X-H,K,X,Y);return W}}class E6 extends o0{constructor(J,Q,$,Z){super(J,Q,$,Z)}InterpolantFactoryMethodLinear(J){return new kW(this.times,this.values,this.getValueSize(),J)}}E6.prototype.ValueTypeName="quaternion";E6.prototype.InterpolantFactoryMethodSmooth=void 0;class n8 extends o0{constructor(J,Q,$){super(J,Q,$)}}n8.prototype.ValueTypeName="string";n8.prototype.ValueBufferType=Array;n8.prototype.DefaultInterpolation=2300;n8.prototype.InterpolantFactoryMethodLinear=void 0;n8.prototype.InterpolantFactoryMethodSmooth=void 0;class t9 extends o0{constructor(J,Q,$,Z){super(J,Q,$,Z)}}t9.prototype.ValueTypeName="vector";class e9{constructor(J="",Q=-1,$=[],Z=2500){if(this.name=J,this.tracks=$,this.duration=Q,this.blendMode=Z,this.uuid=n0(),this.userData={},this.duration<0)this.resetDuration()}static parse(J){let Q=[],$=J.tracks,Z=1/(J.fps||1);for(let K=0,H=$.length;K!==H;++K)Q.push(sE($[K]).scale(Z));let W=new this(J.name,J.duration,Q,J.blendMode);return W.uuid=J.uuid,W.userData=JSON.parse(J.userData||"{}"),W}static toJSON(J){let Q=[],$=J.tracks,Z={name:J.name,duration:J.duration,tracks:Q,uuid:J.uuid,blendMode:J.blendMode,userData:JSON.stringify(J.userData)};for(let W=0,K=$.length;W!==K;++W)Q.push(o0.toJSON($[W]));return Z}static CreateFromMorphTargetSequence(J,Q,$,Z){let W=Q.length,K=[];for(let H=0;H<W;H++){let Y=[],X=[];Y.push((H+W-1)%W,H,(H+1)%W),X.push(0,1,0);let U=fY(Y);if(Y=s$(Y,1,U),X=s$(X,1,U),!Z&&Y[0]===0)Y.push(W),X.push(X[0]);K.push(new r9(".morphTargetInfluences["+Q[H].name+"]",Y,X).scale(1/$))}return new this(J,-1,K)}static findByName(J,Q){let $=J;if(!Array.isArray(J)){let Z=J;$=Z.geometry&&Z.geometry.animations||Z.animations}for(let Z=0;Z<$.length;Z++)if($[Z].name===Q)return $[Z];return null}static CreateClipsFromMorphTargetSequences(J,Q,$){let Z={},W=/^([\w-]*?)([\d]+)$/;for(let H=0,Y=J.length;H<Y;H++){let X=J[H],U=X.name.match(W);if(U&&U.length>1){let G=U[1],E=Z[G];if(!E)Z[G]=E=[];E.push(X)}}let K=[];for(let H in Z)K.push(this.CreateFromMorphTargetSequence(H,Z[H],Q,$));return K}static parseAnimation(J,Q){if(console.warn("THREE.AnimationClip: parseAnimation() is deprecated and will be removed with r185"),!J)return console.error("THREE.AnimationClip: No animation in JSONLoader data."),null;let $=function(G,E,N,q,R){if(N.length!==0){let F=[],O=[];if(RW(N,F,O,q),F.length!==0)R.push(new G(E,F,O))}},Z=[],W=J.name||"default",K=J.fps||30,H=J.blendMode,Y=J.length||-1,X=J.hierarchy||[];for(let G=0;G<X.length;G++){let E=X[G].keys;if(!E||E.length===0)continue;if(E[0].morphTargets){let N={},q;for(q=0;q<E.length;q++)if(E[q].morphTargets)for(let R=0;R<E[q].morphTargets.length;R++)N[E[q].morphTargets[R]]=-1;for(let R in N){let F=[],O=[];for(let D=0;D!==E[q].morphTargets.length;++D){let k=E[q];F.push(k.time),O.push(k.morphTarget===R?1:0)}Z.push(new r9(".morphTargetInfluence["+R+"]",F,O))}Y=N.length*K}else{let N=".bones["+Q[G].name+"]";$(t9,N+".position",E,"pos",Z),$(E6,N+".quaternion",E,"rot",Z),$(t9,N+".scale",E,"scl",Z)}}if(Z.length===0)return null;return new this(W,Y,Z,H)}resetDuration(){let J=this.tracks,Q=0;for(let $=0,Z=J.length;$!==Z;++$){let W=this.tracks[$];Q=Math.max(Q,W.times[W.times.length-1])}return this.duration=Q,this}trim(){for(let J=0;J<this.tracks.length;J++)this.tracks[J].trim(0,this.duration);return this}validate(){let J=!0;for(let Q=0;Q<this.tracks.length;Q++)J=J&&this.tracks[Q].validate();return J}optimize(){for(let J=0;J<this.tracks.length;J++)this.tracks[J].optimize();return this}clone(){let J=[];for(let $=0;$<this.tracks.length;$++)J.push(this.tracks[$].clone());let Q=new this.constructor(this.name,this.duration,J,this.blendMode);return Q.userData=JSON.parse(JSON.stringify(this.userData)),Q}toJSON(){return this.constructor.toJSON(this)}}function nE(J){switch(J.toLowerCase()){case"scalar":case"double":case"float":case"number":case"integer":return r9;case"vector":case"vector2":case"vector3":case"vector4":return t9;case"color":return iQ;case"quaternion":return E6;case"bool":case"boolean":return c8;case"string":return n8}throw Error("THREE.KeyframeTrack: Unsupported typeName: "+J)}function sE(J){if(J.type===void 0)throw Error("THREE.KeyframeTrack: track type undefined, can not parse");let Q=nE(J.type);if(J.times===void 0){let $=[],Z=[];RW(J.keys,$,Z,"value"),J.times=$,J.values=Z}if(Q.parse!==void 0)return Q.parse(J);else return new Q(J.name,J.times,J.values,J.interpolation)}var q8={enabled:!1,files:{},add:function(J,Q){if(this.enabled===!1)return;this.files[J]=Q},get:function(J){if(this.enabled===!1)return;return this.files[J]},remove:function(J){delete this.files[J]},clear:function(){this.files={}}};class oQ{constructor(J,Q,$){let Z=this,W=!1,K=0,H=0,Y=void 0,X=[];this.onStart=void 0,this.onLoad=J,this.onProgress=Q,this.onError=$,this.abortController=new AbortController,this.itemStart=function(U){if(H++,W===!1){if(Z.onStart!==void 0)Z.onStart(U,K,H)}W=!0},this.itemEnd=function(U){if(K++,Z.onProgress!==void 0)Z.onProgress(U,K,H);if(K===H){if(W=!1,Z.onLoad!==void 0)Z.onLoad()}},this.itemError=function(U){if(Z.onError!==void 0)Z.onError(U)},this.resolveURL=function(U){if(Y)return Y(U);return U},this.setURLModifier=function(U){return Y=U,this},this.addHandler=function(U,G){return X.push(U,G),this},this.removeHandler=function(U){let G=X.indexOf(U);if(G!==-1)X.splice(G,2);return this},this.getHandler=function(U){for(let G=0,E=X.length;G<E;G+=2){let N=X[G],q=X[G+1];if(N.global)N.lastIndex=0;if(N.test(U))return q}return null},this.abort=function(){return this.abortController.abort(),this.abortController=new AbortController,this}}}var hY=new oQ;class h0{constructor(J){this.manager=J!==void 0?J:hY,this.crossOrigin="anonymous",this.withCredentials=!1,this.path="",this.resourcePath="",this.requestHeader={}}load(){}loadAsync(J,Q){let $=this;return new Promise(function(Z,W){$.load(J,Z,Q,W)})}parse(){}setCrossOrigin(J){return this.crossOrigin=J,this}setWithCredentials(J){return this.withCredentials=J,this}setPath(J){return this.path=J,this}setResourcePath(J){return this.resourcePath=J,this}setRequestHeader(J){return this.requestHeader=J,this}abort(){return this}}h0.DEFAULT_MATERIAL_NAME="__DEFAULT";var I8={};class xY extends Error{constructor(J,Q){super(J);this.response=Q}}class D8 extends h0{constructor(J){super(J);this.mimeType="",this.responseType="",this._abortController=new AbortController}load(J,Q,$,Z){if(J===void 0)J="";if(this.path!==void 0)J=this.path+J;J=this.manager.resolveURL(J);let W=q8.get(`file:${J}`);if(W!==void 0)return this.manager.itemStart(J),setTimeout(()=>{if(Q)Q(W);this.manager.itemEnd(J)},0),W;if(I8[J]!==void 0){I8[J].push({onLoad:Q,onProgress:$,onError:Z});return}I8[J]=[],I8[J].push({onLoad:Q,onProgress:$,onError:Z});let K=new Request(J,{headers:new Headers(this.requestHeader),credentials:this.withCredentials?"include":"same-origin",signal:typeof AbortSignal.any==="function"?AbortSignal.any([this._abortController.signal,this.manager.abortController.signal]):this._abortController.signal}),H=this.mimeType,Y=this.responseType;fetch(K).then((X)=>{if(X.status===200||X.status===0){if(X.status===0)console.warn("THREE.FileLoader: HTTP Status 0 received.");if(typeof ReadableStream>"u"||X.body===void 0||X.body.getReader===void 0)return X;let U=I8[J],G=X.body.getReader(),E=X.headers.get("X-File-Size")||X.headers.get("Content-Length"),N=E?parseInt(E):0,q=N!==0,R=0,F=new ReadableStream({start(O){D();function D(){G.read().then(({done:k,value:M})=>{if(k)O.close();else{R+=M.byteLength;let L=new ProgressEvent("progress",{lengthComputable:q,loaded:R,total:N});for(let A=0,_=U.length;A<_;A++){let C=U[A];if(C.onProgress)C.onProgress(L)}O.enqueue(M),D()}},(k)=>{O.error(k)})}}});return new Response(F)}else throw new xY(`fetch for "${X.url}" responded with ${X.status}: ${X.statusText}`,X)}).then((X)=>{switch(Y){case"arraybuffer":return X.arrayBuffer();case"blob":return X.blob();case"document":return X.text().then((U)=>{return new DOMParser().parseFromString(U,H)});case"json":return X.json();default:if(H==="")return X.text();else{let G=/charset="?([^;"\s]*)"?/i.exec(H),E=G&&G[1]?G[1].toLowerCase():void 0,N=new TextDecoder(E);return X.arrayBuffer().then((q)=>N.decode(q))}}}).then((X)=>{q8.add(`file:${J}`,X);let U=I8[J];delete I8[J];for(let G=0,E=U.length;G<E;G++){let N=U[G];if(N.onLoad)N.onLoad(X)}}).catch((X)=>{let U=I8[J];if(U===void 0)throw this.manager.itemError(J),X;delete I8[J];for(let G=0,E=U.length;G<E;G++){let N=U[G];if(N.onError)N.onError(X)}this.manager.itemError(J)}).finally(()=>{this.manager.itemEnd(J)}),this.manager.itemStart(J)}setResponseType(J){return this.responseType=J,this}setMimeType(J){return this.mimeType=J,this}abort(){return this._abortController.abort(),this._abortController=new AbortController,this}}class gY extends h0{constructor(J){super(J)}load(J,Q,$,Z){let W=this,K=new D8(this.manager);K.setPath(this.path),K.setRequestHeader(this.requestHeader),K.setWithCredentials(this.withCredentials),K.load(J,function(H){try{Q(W.parse(JSON.parse(H)))}catch(Y){if(Z)Z(Y);else console.error(Y);W.manager.itemError(J)}},$,Z)}parse(J){let Q=[];for(let $=0;$<J.length;$++){let Z=e9.parse(J[$]);Q.push(Z)}return Q}}class pY extends h0{constructor(J){super(J)}load(J,Q,$,Z){let W=this,K=[],H=new r6,Y=new D8(this.manager);Y.setPath(this.path),Y.setResponseType("arraybuffer"),Y.setRequestHeader(this.requestHeader),Y.setWithCredentials(W.withCredentials);let X=0;function U(G){Y.load(J[G],function(E){let N=W.parse(E,!0);if(K[G]={width:N.width,height:N.height,format:N.format,mipmaps:N.mipmaps},X+=1,X===6){if(N.mipmapCount===1)H.minFilter=1006;if(H.image=K,H.format=N.format,H.needsUpdate=!0,Q)Q(H)}},$,Z)}if(Array.isArray(J))for(let G=0,E=J.length;G<E;++G)U(G);else Y.load(J,function(G){let E=W.parse(G,!0);if(E.isCubemap){let N=E.mipmaps.length/E.mipmapCount;for(let q=0;q<N;q++){K[q]={mipmaps:[]};for(let R=0;R<E.mipmapCount;R++)K[q].mipmaps.push(E.mipmaps[q*E.mipmapCount+R]),K[q].format=E.format,K[q].width=E.width,K[q].height=E.height}H.image=K}else H.image.width=E.width,H.image.height=E.height,H.mipmaps=E.mipmaps;if(E.mipmapCount===1)H.minFilter=1006;if(H.format=E.format,H.needsUpdate=!0,Q)Q(H)},$,Z);return H}}var l9=new WeakMap;class J6 extends h0{constructor(J){super(J)}load(J,Q,$,Z){if(this.path!==void 0)J=this.path+J;J=this.manager.resolveURL(J);let W=this,K=q8.get(`image:${J}`);if(K!==void 0){if(K.complete===!0)W.manager.itemStart(J),setTimeout(function(){if(Q)Q(K);W.manager.itemEnd(J)},0);else{let G=l9.get(K);if(G===void 0)G=[],l9.set(K,G);G.push({onLoad:Q,onError:Z})}return K}let H=i9("img");function Y(){if(U(),Q)Q(this);let G=l9.get(this)||[];for(let E=0;E<G.length;E++){let N=G[E];if(N.onLoad)N.onLoad(this)}l9.delete(this),W.manager.itemEnd(J)}function X(G){if(U(),Z)Z(G);q8.remove(`image:${J}`);let E=l9.get(this)||[];for(let N=0;N<E.length;N++){let q=E[N];if(q.onError)q.onError(G)}l9.delete(this),W.manager.itemError(J),W.manager.itemEnd(J)}function U(){H.removeEventListener("load",Y,!1),H.removeEventListener("error",X,!1)}if(H.addEventListener("load",Y,!1),H.addEventListener("error",X,!1),J.slice(0,5)!=="data:"){if(this.crossOrigin!==void 0)H.crossOrigin=this.crossOrigin}return q8.add(`image:${J}`,H),W.manager.itemStart(J),H.src=J,H}}class mY extends h0{constructor(J){super(J)}load(J,Q,$,Z){let W=new X6;W.colorSpace="srgb";let K=new J6(this.manager);K.setCrossOrigin(this.crossOrigin),K.setPath(this.path);let H=0;function Y(X){K.load(J[X],function(U){if(W.images[X]=U,H++,H===6){if(W.needsUpdate=!0,Q)Q(W)}},void 0,Z)}for(let X=0;X<J.length;++X)Y(X);return W}}class dY extends h0{constructor(J){super(J)}load(J,Q,$,Z){let W=this,K=new K8,H=new D8(this.manager);return H.setResponseType("arraybuffer"),H.setRequestHeader(this.requestHeader),H.setPath(this.path),H.setWithCredentials(W.withCredentials),H.load(J,function(Y){let X;try{X=W.parse(Y)}catch(U){if(Z!==void 0)Z(U);else{console.error(U);return}}if(X.image!==void 0)K.image=X.image;else if(X.data!==void 0)K.image.width=X.width,K.image.height=X.height,K.image.data=X.data;if(K.wrapS=X.wrapS!==void 0?X.wrapS:1001,K.wrapT=X.wrapT!==void 0?X.wrapT:1001,K.magFilter=X.magFilter!==void 0?X.magFilter:1006,K.minFilter=X.minFilter!==void 0?X.minFilter:1006,K.anisotropy=X.anisotropy!==void 0?X.anisotropy:1,X.colorSpace!==void 0)K.colorSpace=X.colorSpace;if(X.flipY!==void 0)K.flipY=X.flipY;if(X.format!==void 0)K.format=X.format;if(X.type!==void 0)K.type=X.type;if(X.mipmaps!==void 0)K.mipmaps=X.mipmaps,K.minFilter=1008;if(X.mipmapCount===1)K.minFilter=1006;if(X.generateMipmaps!==void 0)K.generateMipmaps=X.generateMipmaps;if(K.needsUpdate=!0,Q)Q(K,X)},$,Z),K}}class lY extends h0{constructor(J){super(J)}load(J,Q,$,Z){let W=new F0,K=new J6(this.manager);return K.setCrossOrigin(this.crossOrigin),K.setPath(this.path),K.load(J,function(H){if(W.image=H,W.needsUpdate=!0,Q!==void 0)Q(W)},$,Z),W}}class j8 extends Q0{constructor(J,Q=1){super();this.isLight=!0,this.type="Light",this.color=new kJ(J),this.intensity=Q}dispose(){}copy(J,Q){return super.copy(J,Q),this.color.copy(J.color),this.intensity=J.intensity,this}toJSON(J){let Q=super.toJSON(J);if(Q.object.color=this.color.getHex(),Q.object.intensity=this.intensity,this.groundColor!==void 0)Q.object.groundColor=this.groundColor.getHex();if(this.distance!==void 0)Q.object.distance=this.distance;if(this.angle!==void 0)Q.object.angle=this.angle;if(this.decay!==void 0)Q.object.decay=this.decay;if(this.penumbra!==void 0)Q.object.penumbra=this.penumbra;if(this.shadow!==void 0)Q.object.shadow=this.shadow.toJSON();if(this.target!==void 0)Q.object.target=this.target.uuid;return Q}}class VW extends j8{constructor(J,Q,$){super(J,$);this.isHemisphereLight=!0,this.type="HemisphereLight",this.position.copy(Q0.DEFAULT_UP),this.updateMatrix(),this.groundColor=new kJ(Q)}copy(J,Q){return super.copy(J,Q),this.groundColor.copy(J.groundColor),this}}var h$=new hJ,dK=new w,lK=new w;class aQ{constructor(J){this.camera=J,this.intensity=1,this.bias=0,this.normalBias=0,this.radius=1,this.blurSamples=8,this.mapSize=new t(512,512),this.mapType=1009,this.map=null,this.mapPass=null,this.matrix=new hJ,this.autoUpdate=!0,this.needsUpdate=!1,this._frustum=new V9,this._frameExtents=new t(1,1),this._viewportCount=1,this._viewports=[new J0(0,0,1,1)]}getViewportCount(){return this._viewportCount}getFrustum(){return this._frustum}updateMatrices(J){let Q=this.camera,$=this.matrix;if(dK.setFromMatrixPosition(J.matrixWorld),Q.position.copy(dK),lK.setFromMatrixPosition(J.target.matrixWorld),Q.lookAt(lK),Q.updateMatrixWorld(),h$.multiplyMatrices(Q.projectionMatrix,Q.matrixWorldInverse),this._frustum.setFromProjectionMatrix(h$,Q.coordinateSystem,Q.reversedDepth),Q.reversedDepth)$.set(0.5,0,0,0.5,0,0.5,0,0.5,0,0,1,0,0,0,0,1);else $.set(0.5,0,0,0.5,0,0.5,0,0.5,0,0,0.5,0.5,0,0,0,1);$.multiply(h$)}getViewport(J){return this._viewports[J]}getFrameExtents(){return this._frameExtents}dispose(){if(this.map)this.map.dispose();if(this.mapPass)this.mapPass.dispose()}copy(J){return this.camera=J.camera.clone(),this.intensity=J.intensity,this.bias=J.bias,this.radius=J.radius,this.autoUpdate=J.autoUpdate,this.needsUpdate=J.needsUpdate,this.normalBias=J.normalBias,this.blurSamples=J.blurSamples,this.mapSize.copy(J.mapSize),this}clone(){return new this.constructor().copy(this)}toJSON(){let J={};if(this.intensity!==1)J.intensity=this.intensity;if(this.bias!==0)J.bias=this.bias;if(this.normalBias!==0)J.normalBias=this.normalBias;if(this.radius!==1)J.radius=this.radius;if(this.mapSize.x!==512||this.mapSize.y!==512)J.mapSize=this.mapSize.toArray();return J.camera=this.camera.toJSON(!1).object,delete J.camera.matrix,J}}class uY extends aQ{constructor(){super(new I0(50,1,0.5,500));this.isSpotLightShadow=!0,this.focus=1,this.aspect=1}updateMatrices(J){let Q=this.camera,$=G9*2*J.angle*this.focus,Z=this.mapSize.width/this.mapSize.height*this.aspect,W=J.distance||Q.far;if($!==Q.fov||Z!==Q.aspect||W!==Q.far)Q.fov=$,Q.aspect=Z,Q.far=W,Q.updateProjectionMatrix();super.updateMatrices(J)}copy(J){return super.copy(J),this.focus=J.focus,this}}class LW extends j8{constructor(J,Q,$=0,Z=Math.PI/3,W=0,K=2){super(J,Q);this.isSpotLight=!0,this.type="SpotLight",this.position.copy(Q0.DEFAULT_UP),this.updateMatrix(),this.target=new Q0,this.distance=$,this.angle=Z,this.penumbra=W,this.decay=K,this.map=null,this.shadow=new uY}get power(){return this.intensity*Math.PI}set power(J){this.intensity=J/Math.PI}dispose(){this.shadow.dispose()}copy(J,Q){return super.copy(J,Q),this.distance=J.distance,this.angle=J.angle,this.penumbra=J.penumbra,this.decay=J.decay,this.target=J.target.clone(),this.shadow=J.shadow.clone(),this}}var uK=new hJ,C6=new w,x$=new w;class cY extends aQ{constructor(){super(new I0(90,1,0.5,500));this.isPointLightShadow=!0,this._frameExtents=new t(4,2),this._viewportCount=6,this._viewports=[new J0(2,1,1,1),new J0(0,1,1,1),new J0(3,1,1,1),new J0(1,1,1,1),new J0(3,0,1,1),new J0(1,0,1,1)],this._cubeDirections=[new w(1,0,0),new w(-1,0,0),new w(0,0,1),new w(0,0,-1),new w(0,1,0),new w(0,-1,0)],this._cubeUps=[new w(0,1,0),new w(0,1,0),new w(0,1,0),new w(0,1,0),new w(0,0,1),new w(0,0,-1)]}updateMatrices(J,Q=0){let $=this.camera,Z=this.matrix,W=J.distance||$.far;if(W!==$.far)$.far=W,$.updateProjectionMatrix();C6.setFromMatrixPosition(J.matrixWorld),$.position.copy(C6),x$.copy($.position),x$.add(this._cubeDirections[Q]),$.up.copy(this._cubeUps[Q]),$.lookAt(x$),$.updateMatrixWorld(),Z.makeTranslation(-C6.x,-C6.y,-C6.z),uK.multiplyMatrices($.projectionMatrix,$.matrixWorldInverse),this._frustum.setFromProjectionMatrix(uK,$.coordinateSystem,$.reversedDepth)}}class zW extends j8{constructor(J,Q,$=0,Z=2){super(J,Q);this.isPointLight=!0,this.type="PointLight",this.distance=$,this.decay=Z,this.shadow=new cY}get power(){return this.intensity*4*Math.PI}set power(J){this.intensity=J/(4*Math.PI)}dispose(){this.shadow.dispose()}copy(J,Q){return super.copy(J,Q),this.distance=J.distance,this.decay=J.decay,this.shadow=J.shadow.clone(),this}}class Z7 extends i6{constructor(J=-1,Q=1,$=1,Z=-1,W=0.1,K=2000){super();this.isOrthographicCamera=!0,this.type="OrthographicCamera",this.zoom=1,this.view=null,this.left=J,this.right=Q,this.top=$,this.bottom=Z,this.near=W,this.far=K,this.updateProjectionMatrix()}copy(J,Q){return super.copy(J,Q),this.left=J.left,this.right=J.right,this.top=J.top,this.bottom=J.bottom,this.near=J.near,this.far=J.far,this.zoom=J.zoom,this.view=J.view===null?null:Object.assign({},J.view),this}setViewOffset(J,Q,$,Z,W,K){if(this.view===null)this.view={enabled:!0,fullWidth:1,fullHeight:1,offsetX:0,offsetY:0,width:1,height:1};this.view.enabled=!0,this.view.fullWidth=J,this.view.fullHeight=Q,this.view.offsetX=$,this.view.offsetY=Z,this.view.width=W,this.view.height=K,this.updateProjectionMatrix()}clearViewOffset(){if(this.view!==null)this.view.enabled=!1;this.updateProjectionMatrix()}updateProjectionMatrix(){let J=(this.right-this.left)/(2*this.zoom),Q=(this.top-this.bottom)/(2*this.zoom),$=(this.right+this.left)/2,Z=(this.top+this.bottom)/2,W=$-J,K=$+J,H=Z+Q,Y=Z-Q;if(this.view!==null&&this.view.enabled){let X=(this.right-this.left)/this.view.fullWidth/this.zoom,U=(this.top-this.bottom)/this.view.fullHeight/this.zoom;W+=X*this.view.offsetX,K=W+X*this.view.width,H-=U*this.view.offsetY,Y=H-U*this.view.height}this.projectionMatrix.makeOrthographic(W,K,H,Y,this.near,this.far,this.coordinateSystem,this.reversedDepth),this.projectionMatrixInverse.copy(this.projectionMatrix).invert()}toJSON(J){let Q=super.toJSON(J);if(Q.object.zoom=this.zoom,Q.object.left=this.left,Q.object.right=this.right,Q.object.top=this.top,Q.object.bottom=this.bottom,Q.object.near=this.near,Q.object.far=this.far,this.view!==null)Q.object.view=Object.assign({},this.view);return Q}}class nY extends aQ{constructor(){super(new Z7(-5,5,5,-5,0.5,500));this.isDirectionalLightShadow=!0}}class BW extends j8{constructor(J,Q){super(J,Q);this.isDirectionalLight=!0,this.type="DirectionalLight",this.position.copy(Q0.DEFAULT_UP),this.updateMatrix(),this.target=new Q0,this.shadow=new nY}dispose(){this.shadow.dispose()}copy(J){return super.copy(J),this.target=J.target.clone(),this.shadow=J.shadow.clone(),this}}class IW extends j8{constructor(J,Q){super(J,Q);this.isAmbientLight=!0,this.type="AmbientLight"}}class _W extends j8{constructor(J,Q,$=10,Z=10){super(J,Q);this.isRectAreaLight=!0,this.type="RectAreaLight",this.width=$,this.height=Z}get power(){return this.intensity*this.width*this.height*Math.PI}set power(J){this.intensity=J/(this.width*this.height*Math.PI)}copy(J){return super.copy(J),this.width=J.width,this.height=J.height,this}toJSON(J){let Q=super.toJSON(J);return Q.object.width=this.width,Q.object.height=this.height,Q}}class wW{constructor(){this.isSphericalHarmonics3=!0,this.coefficients=[];for(let J=0;J<9;J++)this.coefficients.push(new w)}set(J){for(let Q=0;Q<9;Q++)this.coefficients[Q].copy(J[Q]);return this}zero(){for(let J=0;J<9;J++)this.coefficients[J].set(0,0,0);return this}getAt(J,Q){let{x:$,y:Z,z:W}=J,K=this.coefficients;return Q.copy(K[0]).multiplyScalar(0.282095),Q.addScaledVector(K[1],0.488603*Z),Q.addScaledVector(K[2],0.488603*W),Q.addScaledVector(K[3],0.488603*$),Q.addScaledVector(K[4],1.092548*($*Z)),Q.addScaledVector(K[5],1.092548*(Z*W)),Q.addScaledVector(K[6],0.315392*(3*W*W-1)),Q.addScaledVector(K[7],1.092548*($*W)),Q.addScaledVector(K[8],0.546274*($*$-Z*Z)),Q}getIrradianceAt(J,Q){let{x:$,y:Z,z:W}=J,K=this.coefficients;return Q.copy(K[0]).multiplyScalar(0.886227),Q.addScaledVector(K[1],1.023328*Z),Q.addScaledVector(K[2],1.023328*W),Q.addScaledVector(K[3],1.023328*$),Q.addScaledVector(K[4],0.858086*$*Z),Q.addScaledVector(K[5],0.858086*Z*W),Q.addScaledVector(K[6],0.743125*W*W-0.247708),Q.addScaledVector(K[7],0.858086*$*W),Q.addScaledVector(K[8],0.429043*($*$-Z*Z)),Q}add(J){for(let Q=0;Q<9;Q++)this.coefficients[Q].add(J.coefficients[Q]);return this}addScaledSH(J,Q){for(let $=0;$<9;$++)this.coefficients[$].addScaledVector(J.coefficients[$],Q);return this}scale(J){for(let Q=0;Q<9;Q++)this.coefficients[Q].multiplyScalar(J);return this}lerp(J,Q){for(let $=0;$<9;$++)this.coefficients[$].lerp(J.coefficients[$],Q);return this}equals(J){for(let Q=0;Q<9;Q++)if(!this.coefficients[Q].equals(J.coefficients[Q]))return!1;return!0}copy(J){return this.set(J.coefficients)}clone(){return new this.constructor().copy(this)}fromArray(J,Q=0){let $=this.coefficients;for(let Z=0;Z<9;Z++)$[Z].fromArray(J,Q+Z*3);return this}toArray(J=[],Q=0){let $=this.coefficients;for(let Z=0;Z<9;Z++)$[Z].toArray(J,Q+Z*3);return J}static getBasisAt(J,Q){let{x:$,y:Z,z:W}=J;Q[0]=0.282095,Q[1]=0.488603*Z,Q[2]=0.488603*W,Q[3]=0.488603*$,Q[4]=1.092548*$*Z,Q[5]=1.092548*Z*W,Q[6]=0.315392*(3*W*W-1),Q[7]=1.092548*$*W,Q[8]=0.546274*($*$-Z*Z)}}class CW extends j8{constructor(J=new wW,Q=1){super(void 0,Q);this.isLightProbe=!0,this.sh=J}copy(J){return super.copy(J),this.sh.copy(J.sh),this}fromJSON(J){return this.intensity=J.intensity,this.sh.fromArray(J.sh),this}toJSON(J){let Q=super.toJSON(J);return Q.object.sh=this.sh.toArray(),Q}}class rQ extends h0{constructor(J){super(J);this.textures={}}load(J,Q,$,Z){let W=this,K=new D8(W.manager);K.setPath(W.path),K.setRequestHeader(W.requestHeader),K.setWithCredentials(W.withCredentials),K.load(J,function(H){try{Q(W.parse(JSON.parse(H)))}catch(Y){if(Z)Z(Y);else console.error(Y);W.manager.itemError(J)}},$,Z)}parse(J){let Q=this.textures;function $(W){if(Q[W]===void 0)console.warn("THREE.MaterialLoader: Undefined texture",W);return Q[W]}let Z=this.createMaterialFromType(J.type);if(J.uuid!==void 0)Z.uuid=J.uuid;if(J.name!==void 0)Z.name=J.name;if(J.color!==void 0&&Z.color!==void 0)Z.color.setHex(J.color);if(J.roughness!==void 0)Z.roughness=J.roughness;if(J.metalness!==void 0)Z.metalness=J.metalness;if(J.sheen!==void 0)Z.sheen=J.sheen;if(J.sheenColor!==void 0)Z.sheenColor=new kJ().setHex(J.sheenColor);if(J.sheenRoughness!==void 0)Z.sheenRoughness=J.sheenRoughness;if(J.emissive!==void 0&&Z.emissive!==void 0)Z.emissive.setHex(J.emissive);if(J.specular!==void 0&&Z.specular!==void 0)Z.specular.setHex(J.specular);if(J.specularIntensity!==void 0)Z.specularIntensity=J.specularIntensity;if(J.specularColor!==void 0&&Z.specularColor!==void 0)Z.specularColor.setHex(J.specularColor);if(J.shininess!==void 0)Z.shininess=J.shininess;if(J.clearcoat!==void 0)Z.clearcoat=J.clearcoat;if(J.clearcoatRoughness!==void 0)Z.clearcoatRoughness=J.clearcoatRoughness;if(J.dispersion!==void 0)Z.dispersion=J.dispersion;if(J.iridescence!==void 0)Z.iridescence=J.iridescence;if(J.iridescenceIOR!==void 0)Z.iridescenceIOR=J.iridescenceIOR;if(J.iridescenceThicknessRange!==void 0)Z.iridescenceThicknessRange=J.iridescenceThicknessRange;if(J.transmission!==void 0)Z.transmission=J.transmission;if(J.thickness!==void 0)Z.thickness=J.thickness;if(J.attenuationDistance!==void 0)Z.attenuationDistance=J.attenuationDistance;if(J.attenuationColor!==void 0&&Z.attenuationColor!==void 0)Z.attenuationColor.setHex(J.attenuationColor);if(J.anisotropy!==void 0)Z.anisotropy=J.anisotropy;if(J.anisotropyRotation!==void 0)Z.anisotropyRotation=J.anisotropyRotation;if(J.fog!==void 0)Z.fog=J.fog;if(J.flatShading!==void 0)Z.flatShading=J.flatShading;if(J.blending!==void 0)Z.blending=J.blending;if(J.combine!==void 0)Z.combine=J.combine;if(J.side!==void 0)Z.side=J.side;if(J.shadowSide!==void 0)Z.shadowSide=J.shadowSide;if(J.opacity!==void 0)Z.opacity=J.opacity;if(J.transparent!==void 0)Z.transparent=J.transparent;if(J.alphaTest!==void 0)Z.alphaTest=J.alphaTest;if(J.alphaHash!==void 0)Z.alphaHash=J.alphaHash;if(J.depthFunc!==void 0)Z.depthFunc=J.depthFunc;if(J.depthTest!==void 0)Z.depthTest=J.depthTest;if(J.depthWrite!==void 0)Z.depthWrite=J.depthWrite;if(J.colorWrite!==void 0)Z.colorWrite=J.colorWrite;if(J.blendSrc!==void 0)Z.blendSrc=J.blendSrc;if(J.blendDst!==void 0)Z.blendDst=J.blendDst;if(J.blendEquation!==void 0)Z.blendEquation=J.blendEquation;if(J.blendSrcAlpha!==void 0)Z.blendSrcAlpha=J.blendSrcAlpha;if(J.blendDstAlpha!==void 0)Z.blendDstAlpha=J.blendDstAlpha;if(J.blendEquationAlpha!==void 0)Z.blendEquationAlpha=J.blendEquationAlpha;if(J.blendColor!==void 0&&Z.blendColor!==void 0)Z.blendColor.setHex(J.blendColor);if(J.blendAlpha!==void 0)Z.blendAlpha=J.blendAlpha;if(J.stencilWriteMask!==void 0)Z.stencilWriteMask=J.stencilWriteMask;if(J.stencilFunc!==void 0)Z.stencilFunc=J.stencilFunc;if(J.stencilRef!==void 0)Z.stencilRef=J.stencilRef;if(J.stencilFuncMask!==void 0)Z.stencilFuncMask=J.stencilFuncMask;if(J.stencilFail!==void 0)Z.stencilFail=J.stencilFail;if(J.stencilZFail!==void 0)Z.stencilZFail=J.stencilZFail;if(J.stencilZPass!==void 0)Z.stencilZPass=J.stencilZPass;if(J.stencilWrite!==void 0)Z.stencilWrite=J.stencilWrite;if(J.wireframe!==void 0)Z.wireframe=J.wireframe;if(J.wireframeLinewidth!==void 0)Z.wireframeLinewidth=J.wireframeLinewidth;if(J.wireframeLinecap!==void 0)Z.wireframeLinecap=J.wireframeLinecap;if(J.wireframeLinejoin!==void 0)Z.wireframeLinejoin=J.wireframeLinejoin;if(J.rotation!==void 0)Z.rotation=J.rotation;if(J.linewidth!==void 0)Z.linewidth=J.linewidth;if(J.dashSize!==void 0)Z.dashSize=J.dashSize;if(J.gapSize!==void 0)Z.gapSize=J.gapSize;if(J.scale!==void 0)Z.scale=J.scale;if(J.polygonOffset!==void 0)Z.polygonOffset=J.polygonOffset;if(J.polygonOffsetFactor!==void 0)Z.polygonOffsetFactor=J.polygonOffsetFactor;if(J.polygonOffsetUnits!==void 0)Z.polygonOffsetUnits=J.polygonOffsetUnits;if(J.dithering!==void 0)Z.dithering=J.dithering;if(J.alphaToCoverage!==void 0)Z.alphaToCoverage=J.alphaToCoverage;if(J.premultipliedAlpha!==void 0)Z.premultipliedAlpha=J.premultipliedAlpha;if(J.forceSinglePass!==void 0)Z.forceSinglePass=J.forceSinglePass;if(J.visible!==void 0)Z.visible=J.visible;if(J.toneMapped!==void 0)Z.toneMapped=J.toneMapped;if(J.userData!==void 0)Z.userData=J.userData;if(J.vertexColors!==void 0)if(typeof J.vertexColors==="number")Z.vertexColors=J.vertexColors>0?!0:!1;else Z.vertexColors=J.vertexColors;if(J.uniforms!==void 0)for(let W in J.uniforms){let K=J.uniforms[W];switch(Z.uniforms[W]={},K.type){case"t":Z.uniforms[W].value=$(K.value);break;case"c":Z.uniforms[W].value=new kJ().setHex(K.value);break;case"v2":Z.uniforms[W].value=new t().fromArray(K.value);break;case"v3":Z.uniforms[W].value=new w().fromArray(K.value);break;case"v4":Z.uniforms[W].value=new J0().fromArray(K.value);break;case"m3":Z.uniforms[W].value=new dJ().fromArray(K.value);break;case"m4":Z.uniforms[W].value=new hJ().fromArray(K.value);break;default:Z.uniforms[W].value=K.value}}if(J.defines!==void 0)Z.defines=J.defines;if(J.vertexShader!==void 0)Z.vertexShader=J.vertexShader;if(J.fragmentShader!==void 0)Z.fragmentShader=J.fragmentShader;if(J.glslVersion!==void 0)Z.glslVersion=J.glslVersion;if(J.extensions!==void 0)for(let W in J.extensions)Z.extensions[W]=J.extensions[W];if(J.lights!==void 0)Z.lights=J.lights;if(J.clipping!==void 0)Z.clipping=J.clipping;if(J.size!==void 0)Z.size=J.size;if(J.sizeAttenuation!==void 0)Z.sizeAttenuation=J.sizeAttenuation;if(J.map!==void 0)Z.map=$(J.map);if(J.matcap!==void 0)Z.matcap=$(J.matcap);if(J.alphaMap!==void 0)Z.alphaMap=$(J.alphaMap);if(J.bumpMap!==void 0)Z.bumpMap=$(J.bumpMap);if(J.bumpScale!==void 0)Z.bumpScale=J.bumpScale;if(J.normalMap!==void 0)Z.normalMap=$(J.normalMap);if(J.normalMapType!==void 0)Z.normalMapType=J.normalMapType;if(J.normalScale!==void 0){let W=J.normalScale;if(Array.isArray(W)===!1)W=[W,W];Z.normalScale=new t().fromArray(W)}if(J.displacementMap!==void 0)Z.displacementMap=$(J.displacementMap);if(J.displacementScale!==void 0)Z.displacementScale=J.displacementScale;if(J.displacementBias!==void 0)Z.displacementBias=J.displacementBias;if(J.roughnessMap!==void 0)Z.roughnessMap=$(J.roughnessMap);if(J.metalnessMap!==void 0)Z.metalnessMap=$(J.metalnessMap);if(J.emissiveMap!==void 0)Z.emissiveMap=$(J.emissiveMap);if(J.emissiveIntensity!==void 0)Z.emissiveIntensity=J.emissiveIntensity;if(J.specularMap!==void 0)Z.specularMap=$(J.specularMap);if(J.specularIntensityMap!==void 0)Z.specularIntensityMap=$(J.specularIntensityMap);if(J.specularColorMap!==void 0)Z.specularColorMap=$(J.specularColorMap);if(J.envMap!==void 0)Z.envMap=$(J.envMap);if(J.envMapRotation!==void 0)Z.envMapRotation.fromArray(J.envMapRotation);if(J.envMapIntensity!==void 0)Z.envMapIntensity=J.envMapIntensity;if(J.reflectivity!==void 0)Z.reflectivity=J.reflectivity;if(J.refractionRatio!==void 0)Z.refractionRatio=J.refractionRatio;if(J.lightMap!==void 0)Z.lightMap=$(J.lightMap);if(J.lightMapIntensity!==void 0)Z.lightMapIntensity=J.lightMapIntensity;if(J.aoMap!==void 0)Z.aoMap=$(J.aoMap);if(J.aoMapIntensity!==void 0)Z.aoMapIntensity=J.aoMapIntensity;if(J.gradientMap!==void 0)Z.gradientMap=$(J.gradientMap);if(J.clearcoatMap!==void 0)Z.clearcoatMap=$(J.clearcoatMap);if(J.clearcoatRoughnessMap!==void 0)Z.clearcoatRoughnessMap=$(J.clearcoatRoughnessMap);if(J.clearcoatNormalMap!==void 0)Z.clearcoatNormalMap=$(J.clearcoatNormalMap);if(J.clearcoatNormalScale!==void 0)Z.clearcoatNormalScale=new t().fromArray(J.clearcoatNormalScale);if(J.iridescenceMap!==void 0)Z.iridescenceMap=$(J.iridescenceMap);if(J.iridescenceThicknessMap!==void 0)Z.iridescenceThicknessMap=$(J.iridescenceThicknessMap);if(J.transmissionMap!==void 0)Z.transmissionMap=$(J.transmissionMap);if(J.thicknessMap!==void 0)Z.thicknessMap=$(J.thicknessMap);if(J.anisotropyMap!==void 0)Z.anisotropyMap=$(J.anisotropyMap);if(J.sheenColorMap!==void 0)Z.sheenColorMap=$(J.sheenColorMap);if(J.sheenRoughnessMap!==void 0)Z.sheenRoughnessMap=$(J.sheenRoughnessMap);return Z}setTextures(J){return this.textures=J,this}createMaterialFromType(J){return rQ.createMaterialFromType(J)}static createMaterialFromType(J){return new{ShadowMaterial:YW,SpriteMaterial:VQ,RawShaderMaterial:XW,ShaderMaterial:e0,PointsMaterial:IQ,MeshPhysicalMaterial:UW,MeshStandardMaterial:uQ,MeshPhongMaterial:GW,MeshToonMaterial:EW,MeshNormalMaterial:NW,MeshLambertMaterial:qW,MeshDepthMaterial:cQ,MeshDistanceMaterial:nQ,MeshBasicMaterial:S8,MeshMatcapMaterial:DW,LineDashedMaterial:OW,LineBasicMaterial:j0,Material:C0}[J]}}class e7{static extractUrlBase(J){let Q=J.lastIndexOf("/");if(Q===-1)return"./";return J.slice(0,Q+1)}static resolveURL(J,Q){if(typeof J!=="string"||J==="")return"";if(/^https?:\/\//i.test(Q)&&/^\//.test(J))Q=Q.replace(/(^https?:\/\/[^\/]+).*/i,"$1");if(/^(https?:)?\/\//i.test(J))return J;if(/^data:.*,.*$/i.test(J))return J;if(/^blob:.*$/i.test(J))return J;return Q+J}}class PW extends nJ{constructor(){super();this.isInstancedBufferGeometry=!0,this.type="InstancedBufferGeometry",this.instanceCount=1/0}copy(J){return super.copy(J),this.instanceCount=J.instanceCount,this}toJSON(){let J=super.toJSON();return J.instanceCount=this.instanceCount,J.isInstancedBufferGeometry=!0,J}}class AW extends h0{constructor(J){super(J)}load(J,Q,$,Z){let W=this,K=new D8(W.manager);K.setPath(W.path),K.setRequestHeader(W.requestHeader),K.setWithCredentials(W.withCredentials),K.load(J,function(H){try{Q(W.parse(JSON.parse(H)))}catch(Y){if(Z)Z(Y);else console.error(Y);W.manager.itemError(J)}},$,Z)}parse(J){let Q={},$={};function Z(N,q){if(Q[q]!==void 0)return Q[q];let F=N.interleavedBuffers[q],O=W(N,F.buffer),D=n9(F.type,O),k=new a6(D,F.stride);return k.uuid=F.uuid,Q[q]=k,k}function W(N,q){if($[q]!==void 0)return $[q];let F=N.arrayBuffers[q],O=new Uint32Array(F).buffer;return $[q]=O,O}let K=J.isInstancedBufferGeometry?new PW:new nJ,H=J.data.index;if(H!==void 0){let N=n9(H.type,H.array);K.setIndex(new Z0(N,1))}let Y=J.data.attributes;for(let N in Y){let q=Y[N],R;if(q.isInterleavedBufferAttribute){let F=Z(J.data,q.data);R=new E9(F,q.itemSize,q.offset,q.normalized)}else{let F=n9(q.type,q.array);R=new(q.isInstancedBufferAttribute?N9:Z0)(F,q.itemSize,q.normalized)}if(q.name!==void 0)R.name=q.name;if(q.usage!==void 0)R.setUsage(q.usage);K.setAttribute(N,R)}let X=J.data.morphAttributes;if(X)for(let N in X){let q=X[N],R=[];for(let F=0,O=q.length;F<O;F++){let D=q[F],k;if(D.isInterleavedBufferAttribute){let M=Z(J.data,D.data);k=new E9(M,D.itemSize,D.offset,D.normalized)}else{let M=n9(D.type,D.array);k=new Z0(M,D.itemSize,D.normalized)}if(D.name!==void 0)k.name=D.name;R.push(k)}K.morphAttributes[N]=R}if(J.data.morphTargetsRelative)K.morphTargetsRelative=!0;let G=J.data.groups||J.data.drawcalls||J.data.offsets;if(G!==void 0)for(let N=0,q=G.length;N!==q;++N){let R=G[N];K.addGroup(R.start,R.count,R.materialIndex)}let E=J.data.boundingSphere;if(E!==void 0)K.boundingSphere=new _0().fromJSON(E);if(J.name)K.name=J.name;if(J.userData)K.userData=J.userData;return K}}class sY extends h0{constructor(J){super(J)}load(J,Q,$,Z){let W=this,K=this.path===""?e7.extractUrlBase(J):this.path;this.resourcePath=this.resourcePath||K;let H=new D8(this.manager);H.setPath(this.path),H.setRequestHeader(this.requestHeader),H.setWithCredentials(this.withCredentials),H.load(J,function(Y){let X=null;try{X=JSON.parse(Y)}catch(G){if(Z!==void 0)Z(G);console.error("THREE:ObjectLoader: Can't parse "+J+".",G.message);return}let U=X.metadata;if(U===void 0||U.type===void 0||U.type.toLowerCase()==="geometry"){if(Z!==void 0)Z(Error("THREE.ObjectLoader: Can't load "+J));console.error("THREE.ObjectLoader: Can't load "+J);return}W.parse(X,Q)},$,Z)}async loadAsync(J,Q){let $=this,Z=this.path===""?e7.extractUrlBase(J):this.path;this.resourcePath=this.resourcePath||Z;let W=new D8(this.manager);W.setPath(this.path),W.setRequestHeader(this.requestHeader),W.setWithCredentials(this.withCredentials);let K=await W.loadAsync(J,Q),H=JSON.parse(K),Y=H.metadata;if(Y===void 0||Y.type===void 0||Y.type.toLowerCase()==="geometry")throw Error("THREE.ObjectLoader: Can't load "+J);return await $.parseAsync(H)}parse(J,Q){let $=this.parseAnimations(J.animations),Z=this.parseShapes(J.shapes),W=this.parseGeometries(J.geometries,Z),K=this.parseImages(J.images,function(){if(Q!==void 0)Q(X)}),H=this.parseTextures(J.textures,K),Y=this.parseMaterials(J.materials,H),X=this.parseObject(J.object,W,Y,H,$),U=this.parseSkeletons(J.skeletons,X);if(this.bindSkeletons(X,U),this.bindLightTargets(X),Q!==void 0){let G=!1;for(let E in K)if(K[E].data instanceof HTMLImageElement){G=!0;break}if(G===!1)Q(X)}return X}async parseAsync(J){let Q=this.parseAnimations(J.animations),$=this.parseShapes(J.shapes),Z=this.parseGeometries(J.geometries,$),W=await this.parseImagesAsync(J.images),K=this.parseTextures(J.textures,W),H=this.parseMaterials(J.materials,K),Y=this.parseObject(J.object,Z,H,K,Q),X=this.parseSkeletons(J.skeletons,Y);return this.bindSkeletons(Y,X),this.bindLightTargets(Y),Y}parseShapes(J){let Q={};if(J!==void 0)for(let $=0,Z=J.length;$<Z;$++){let W=new p8().fromJSON(J[$]);Q[W.uuid]=W}return Q}parseSkeletons(J,Q){let $={},Z={};if(Q.traverse(function(W){if(W.isBone)Z[W.uuid]=W}),J!==void 0)for(let W=0,K=J.length;W<K;W++){let H=new zQ().fromJSON(J[W],Z);$[H.uuid]=H}return $}parseGeometries(J,Q){let $={};if(J!==void 0){let Z=new AW;for(let W=0,K=J.length;W<K;W++){let H,Y=J[W];switch(Y.type){case"BufferGeometry":case"InstancedBufferGeometry":H=Z.parse(Y);break;default:if(Y.type in mK)H=mK[Y.type].fromJSON(Y,Q);else console.warn(`THREE.ObjectLoader: Unsupported geometry type "${Y.type}"`)}if(H.uuid=Y.uuid,Y.name!==void 0)H.name=Y.name;if(Y.userData!==void 0)H.userData=Y.userData;$[Y.uuid]=H}}return $}parseMaterials(J,Q){let $={},Z={};if(J!==void 0){let W=new rQ;W.setTextures(Q);for(let K=0,H=J.length;K<H;K++){let Y=J[K];if($[Y.uuid]===void 0)$[Y.uuid]=W.parse(Y);Z[Y.uuid]=$[Y.uuid]}}return Z}parseAnimations(J){let Q={};if(J!==void 0)for(let $=0;$<J.length;$++){let Z=J[$],W=e9.parse(Z);Q[W.uuid]=W}return Q}parseImages(J,Q){let $=this,Z={},W;function K(Y){return $.manager.itemStart(Y),W.load(Y,function(){$.manager.itemEnd(Y)},void 0,function(){$.manager.itemError(Y),$.manager.itemEnd(Y)})}function H(Y){if(typeof Y==="string"){let X=Y,U=/^(\/\/)|([a-z]+:(\/\/)?)/i.test(X)?X:$.resourcePath+X;return K(U)}else if(Y.data)return{data:n9(Y.type,Y.data),width:Y.width,height:Y.height};else return null}if(J!==void 0&&J.length>0){let Y=new oQ(Q);W=new J6(Y),W.setCrossOrigin(this.crossOrigin);for(let X=0,U=J.length;X<U;X++){let G=J[X],E=G.url;if(Array.isArray(E)){let N=[];for(let q=0,R=E.length;q<R;q++){let F=E[q],O=H(F);if(O!==null)if(O instanceof HTMLImageElement)N.push(O);else N.push(new K8(O.data,O.width,O.height))}Z[G.uuid]=new C8(N)}else{let N=H(G.url);Z[G.uuid]=new C8(N)}}}return Z}async parseImagesAsync(J){let Q=this,$={},Z;async function W(K){if(typeof K==="string"){let H=K,Y=/^(\/\/)|([a-z]+:(\/\/)?)/i.test(H)?H:Q.resourcePath+H;return await Z.loadAsync(Y)}else if(K.data)return{data:n9(K.type,K.data),width:K.width,height:K.height};else return null}if(J!==void 0&&J.length>0){Z=new J6(this.manager),Z.setCrossOrigin(this.crossOrigin);for(let K=0,H=J.length;K<H;K++){let Y=J[K],X=Y.url;if(Array.isArray(X)){let U=[];for(let G=0,E=X.length;G<E;G++){let N=X[G],q=await W(N);if(q!==null)if(q instanceof HTMLImageElement)U.push(q);else U.push(new K8(q.data,q.width,q.height))}$[Y.uuid]=new C8(U)}else{let U=await W(Y.url);$[Y.uuid]=new C8(U)}}}return $}parseTextures(J,Q){function $(W,K){if(typeof W==="number")return W;return console.warn("THREE.ObjectLoader.parseTexture: Constant should be in numeric form.",W),K[W]}let Z={};if(J!==void 0)for(let W=0,K=J.length;W<K;W++){let H=J[W];if(H.image===void 0)console.warn('THREE.ObjectLoader: No "image" specified for',H.uuid);if(Q[H.image]===void 0)console.warn("THREE.ObjectLoader: Undefined image",H.image);let Y=Q[H.image],X=Y.data,U;if(Array.isArray(X)){if(U=new X6,X.length===6)U.needsUpdate=!0}else{if(X&&X.data)U=new K8;else U=new F0;if(X)U.needsUpdate=!0}if(U.source=Y,U.uuid=H.uuid,H.name!==void 0)U.name=H.name;if(H.mapping!==void 0)U.mapping=$(H.mapping,iE);if(H.channel!==void 0)U.channel=H.channel;if(H.offset!==void 0)U.offset.fromArray(H.offset);if(H.repeat!==void 0)U.repeat.fromArray(H.repeat);if(H.center!==void 0)U.center.fromArray(H.center);if(H.rotation!==void 0)U.rotation=H.rotation;if(H.wrap!==void 0)U.wrapS=$(H.wrap[0],cK),U.wrapT=$(H.wrap[1],cK);if(H.format!==void 0)U.format=H.format;if(H.internalFormat!==void 0)U.internalFormat=H.internalFormat;if(H.type!==void 0)U.type=H.type;if(H.colorSpace!==void 0)U.colorSpace=H.colorSpace;if(H.minFilter!==void 0)U.minFilter=$(H.minFilter,nK);if(H.magFilter!==void 0)U.magFilter=$(H.magFilter,nK);if(H.anisotropy!==void 0)U.anisotropy=H.anisotropy;if(H.flipY!==void 0)U.flipY=H.flipY;if(H.generateMipmaps!==void 0)U.generateMipmaps=H.generateMipmaps;if(H.premultiplyAlpha!==void 0)U.premultiplyAlpha=H.premultiplyAlpha;if(H.unpackAlignment!==void 0)U.unpackAlignment=H.unpackAlignment;if(H.compareFunction!==void 0)U.compareFunction=H.compareFunction;if(H.userData!==void 0)U.userData=H.userData;Z[H.uuid]=U}return Z}parseObject(J,Q,$,Z,W){let K;function H(E){if(Q[E]===void 0)console.warn("THREE.ObjectLoader: Undefined geometry",E);return Q[E]}function Y(E){if(E===void 0)return;if(Array.isArray(E)){let N=[];for(let q=0,R=E.length;q<R;q++){let F=E[q];if($[F]===void 0)console.warn("THREE.ObjectLoader: Undefined material",F);N.push($[F])}return N}if($[E]===void 0)console.warn("THREE.ObjectLoader: Undefined material",E);return $[E]}function X(E){if(Z[E]===void 0)console.warn("THREE.ObjectLoader: Undefined texture",E);return Z[E]}let U,G;switch(J.type){case"Scene":if(K=new uZ,J.background!==void 0)if(Number.isInteger(J.background))K.background=new kJ(J.background);else K.background=X(J.background);if(J.environment!==void 0)K.environment=X(J.environment);if(J.fog!==void 0){if(J.fog.type==="Fog")K.fog=new kQ(J.fog.color,J.fog.near,J.fog.far);else if(J.fog.type==="FogExp2")K.fog=new MQ(J.fog.color,J.fog.density);if(J.fog.name!=="")K.fog.name=J.fog.name}if(J.backgroundBlurriness!==void 0)K.backgroundBlurriness=J.backgroundBlurriness;if(J.backgroundIntensity!==void 0)K.backgroundIntensity=J.backgroundIntensity;if(J.backgroundRotation!==void 0)K.backgroundRotation.fromArray(J.backgroundRotation);if(J.environmentIntensity!==void 0)K.environmentIntensity=J.environmentIntensity;if(J.environmentRotation!==void 0)K.environmentRotation.fromArray(J.environmentRotation);break;case"PerspectiveCamera":if(K=new I0(J.fov,J.aspect,J.near,J.far),J.focus!==void 0)K.focus=J.focus;if(J.zoom!==void 0)K.zoom=J.zoom;if(J.filmGauge!==void 0)K.filmGauge=J.filmGauge;if(J.filmOffset!==void 0)K.filmOffset=J.filmOffset;if(J.view!==void 0)K.view=Object.assign({},J.view);break;case"OrthographicCamera":if(K=new Z7(J.left,J.right,J.top,J.bottom,J.near,J.far),J.zoom!==void 0)K.zoom=J.zoom;if(J.view!==void 0)K.view=Object.assign({},J.view);break;case"AmbientLight":K=new IW(J.color,J.intensity);break;case"DirectionalLight":K=new BW(J.color,J.intensity),K.target=J.target||"";break;case"PointLight":K=new zW(J.color,J.intensity,J.distance,J.decay);break;case"RectAreaLight":K=new _W(J.color,J.intensity,J.width,J.height);break;case"SpotLight":K=new LW(J.color,J.intensity,J.distance,J.angle,J.penumbra,J.decay),K.target=J.target||"";break;case"HemisphereLight":K=new VW(J.color,J.groundColor,J.intensity);break;case"LightProbe":K=new CW().fromJSON(J);break;case"SkinnedMesh":if(U=H(J.geometry),G=Y(J.material),K=new sZ(U,G),J.bindMode!==void 0)K.bindMode=J.bindMode;if(J.bindMatrix!==void 0)K.bindMatrix.fromArray(J.bindMatrix);if(J.skeleton!==void 0)K.skeleton=J.skeleton;break;case"Mesh":U=H(J.geometry),G=Y(J.material),K=new k0(U,G);break;case"InstancedMesh":U=H(J.geometry),G=Y(J.material);let{count:E,instanceMatrix:N,instanceColor:q}=J;if(K=new iZ(U,G,E),K.instanceMatrix=new N9(new Float32Array(N.array),16),q!==void 0)K.instanceColor=new N9(new Float32Array(q.array),q.itemSize);break;case"BatchedMesh":if(U=H(J.geometry),G=Y(J.material),K=new oZ(J.maxInstanceCount,J.maxVertexCount,J.maxIndexCount,G),K.geometry=U,K.perObjectFrustumCulled=J.perObjectFrustumCulled,K.sortObjects=J.sortObjects,K._drawRanges=J.drawRanges,K._reservedRanges=J.reservedRanges,K._geometryInfo=J.geometryInfo.map((R)=>{let F=null,O=null;if(R.boundingBox!==void 0)F=new w0().fromJSON(R.boundingBox);if(R.boundingSphere!==void 0)O=new _0().fromJSON(R.boundingSphere);return{...R,boundingBox:F,boundingSphere:O}}),K._instanceInfo=J.instanceInfo,K._availableInstanceIds=J._availableInstanceIds,K._availableGeometryIds=J._availableGeometryIds,K._nextIndexStart=J.nextIndexStart,K._nextVertexStart=J.nextVertexStart,K._geometryCount=J.geometryCount,K._maxInstanceCount=J.maxInstanceCount,K._maxVertexCount=J.maxVertexCount,K._maxIndexCount=J.maxIndexCount,K._geometryInitialized=J.geometryInitialized,K._matricesTexture=X(J.matricesTexture.uuid),K._indirectTexture=X(J.indirectTexture.uuid),J.colorsTexture!==void 0)K._colorsTexture=X(J.colorsTexture.uuid);if(J.boundingSphere!==void 0)K.boundingSphere=new _0().fromJSON(J.boundingSphere);if(J.boundingBox!==void 0)K.boundingBox=new w0().fromJSON(J.boundingBox);break;case"LOD":K=new nZ;break;case"Line":K=new A8(H(J.geometry),Y(J.material));break;case"LineLoop":K=new aZ(H(J.geometry),Y(J.material));break;case"LineSegments":K=new X8(H(J.geometry),Y(J.material));break;case"PointCloud":case"Points":K=new rZ(H(J.geometry),Y(J.material));break;case"Sprite":K=new cZ(Y(J.material));break;case"Group":K=new Y9;break;case"Bone":K=new LQ;break;default:K=new Q0}if(K.uuid=J.uuid,J.name!==void 0)K.name=J.name;if(J.matrix!==void 0){if(K.matrix.fromArray(J.matrix),J.matrixAutoUpdate!==void 0)K.matrixAutoUpdate=J.matrixAutoUpdate;if(K.matrixAutoUpdate)K.matrix.decompose(K.position,K.quaternion,K.scale)}else{if(J.position!==void 0)K.position.fromArray(J.position);if(J.rotation!==void 0)K.rotation.fromArray(J.rotation);if(J.quaternion!==void 0)K.quaternion.fromArray(J.quaternion);if(J.scale!==void 0)K.scale.fromArray(J.scale)}if(J.up!==void 0)K.up.fromArray(J.up);if(J.castShadow!==void 0)K.castShadow=J.castShadow;if(J.receiveShadow!==void 0)K.receiveShadow=J.receiveShadow;if(J.shadow){if(J.shadow.intensity!==void 0)K.shadow.intensity=J.shadow.intensity;if(J.shadow.bias!==void 0)K.shadow.bias=J.shadow.bias;if(J.shadow.normalBias!==void 0)K.shadow.normalBias=J.shadow.normalBias;if(J.shadow.radius!==void 0)K.shadow.radius=J.shadow.radius;if(J.shadow.mapSize!==void 0)K.shadow.mapSize.fromArray(J.shadow.mapSize);if(J.shadow.camera!==void 0)K.shadow.camera=this.parseObject(J.shadow.camera)}if(J.visible!==void 0)K.visible=J.visible;if(J.frustumCulled!==void 0)K.frustumCulled=J.frustumCulled;if(J.renderOrder!==void 0)K.renderOrder=J.renderOrder;if(J.userData!==void 0)K.userData=J.userData;if(J.layers!==void 0)K.layers.mask=J.layers;if(J.children!==void 0){let E=J.children;for(let N=0;N<E.length;N++)K.add(this.parseObject(E[N],Q,$,Z,W))}if(J.animations!==void 0){let E=J.animations;for(let N=0;N<E.length;N++){let q=E[N];K.animations.push(W[q])}}if(J.type==="LOD"){if(J.autoUpdate!==void 0)K.autoUpdate=J.autoUpdate;let E=J.levels;for(let N=0;N<E.length;N++){let q=E[N],R=K.getObjectByProperty("uuid",q.object);if(R!==void 0)K.addLevel(R,q.distance,q.hysteresis)}}return K}bindSkeletons(J,Q){if(Object.keys(Q).length===0)return;J.traverse(function($){if($.isSkinnedMesh===!0&&$.skeleton!==void 0){let Z=Q[$.skeleton];if(Z===void 0)console.warn("THREE.ObjectLoader: No skeleton found with UUID:",$.skeleton);else $.bind(Z,$.bindMatrix)}})}bindLightTargets(J){J.traverse(function(Q){if(Q.isDirectionalLight||Q.isSpotLight){let $=Q.target,Z=J.getObjectByProperty("uuid",$);if(Z!==void 0)Q.target=Z;else Q.target=new Q0}})}}var iE={UVMapping:300,CubeReflectionMapping:301,CubeRefractionMapping:302,EquirectangularReflectionMapping:303,EquirectangularRefractionMapping:304,CubeUVReflectionMapping:306},cK={RepeatWrapping:1000,ClampToEdgeWrapping:1001,MirroredRepeatWrapping:1002},nK={NearestFilter:1003,NearestMipmapNearestFilter:1004,NearestMipmapLinearFilter:1005,LinearFilter:1006,LinearMipmapNearestFilter:1007,LinearMipmapLinearFilter:1008},g$=new WeakMap;class iY extends h0{constructor(J){super(J);if(this.isImageBitmapLoader=!0,typeof createImageBitmap>"u")console.warn("THREE.ImageBitmapLoader: createImageBitmap() not supported.");if(typeof fetch>"u")console.warn("THREE.ImageBitmapLoader: fetch() not supported.");this.options={premultiplyAlpha:"none"},this._abortController=new AbortController}setOptions(J){return this.options=J,this}load(J,Q,$,Z){if(J===void 0)J="";if(this.path!==void 0)J=this.path+J;J=this.manager.resolveURL(J);let W=this,K=q8.get(`image-bitmap:${J}`);if(K!==void 0){if(W.manager.itemStart(J),K.then){K.then((X)=>{if(g$.has(K)===!0){if(Z)Z(g$.get(K));W.manager.itemError(J),W.manager.itemEnd(J)}else{if(Q)Q(X);return W.manager.itemEnd(J),X}});return}return setTimeout(function(){if(Q)Q(K);W.manager.itemEnd(J)},0),K}let H={};H.credentials=this.crossOrigin==="anonymous"?"same-origin":"include",H.headers=this.requestHeader,H.signal=typeof AbortSignal.any==="function"?AbortSignal.any([this._abortController.signal,this.manager.abortController.signal]):this._abortController.signal;let Y=fetch(J,H).then(function(X){return X.blob()}).then(function(X){return createImageBitmap(X,Object.assign(W.options,{colorSpaceConversion:"none"}))}).then(function(X){if(q8.add(`image-bitmap:${J}`,X),Q)Q(X);return W.manager.itemEnd(J),X}).catch(function(X){if(Z)Z(X);g$.set(Y,X),q8.remove(`image-bitmap:${J}`),W.manager.itemError(J),W.manager.itemEnd(J)});q8.add(`image-bitmap:${J}`,Y),W.manager.itemStart(J)}abort(){return this._abortController.abort(),this._abortController=new AbortController,this}}var l7;class tQ{static getContext(){if(l7===void 0)l7=new(window.AudioContext||window.webkitAudioContext);return l7}static setContext(J){l7=J}}class oY extends h0{constructor(J){super(J)}load(J,Q,$,Z){let W=this,K=new D8(this.manager);K.setResponseType("arraybuffer"),K.setPath(this.path),K.setRequestHeader(this.requestHeader),K.setWithCredentials(this.withCredentials),K.load(J,function(Y){try{let X=Y.slice(0);tQ.getContext().decodeAudioData(X,function(G){Q(G)}).catch(H)}catch(X){H(X)}},$,Z);function H(Y){if(Z)Z(Y);else console.error(Y);W.manager.itemError(J)}}}var sK=new hJ,iK=new hJ,Q9=new hJ;class aY{constructor(){this.type="StereoCamera",this.aspect=1,this.eyeSep=0.064,this.cameraL=new I0,this.cameraL.layers.enable(1),this.cameraL.matrixAutoUpdate=!1,this.cameraR=new I0,this.cameraR.layers.enable(2),this.cameraR.matrixAutoUpdate=!1,this._cache={focus:null,fov:null,aspect:null,near:null,far:null,zoom:null,eyeSep:null}}update(J){let Q=this._cache;if(Q.focus!==J.focus||Q.fov!==J.fov||Q.aspect!==J.aspect*this.aspect||Q.near!==J.near||Q.far!==J.far||Q.zoom!==J.zoom||Q.eyeSep!==this.eyeSep){Q.focus=J.focus,Q.fov=J.fov,Q.aspect=J.aspect*this.aspect,Q.near=J.near,Q.far=J.far,Q.zoom=J.zoom,Q.eyeSep=this.eyeSep,Q9.copy(J.projectionMatrix);let Z=Q.eyeSep/2,W=Z*Q.near/Q.focus,K=Q.near*Math.tan(U9*Q.fov*0.5)/Q.zoom,H,Y;iK.elements[12]=-Z,sK.elements[12]=Z,H=-K*Q.aspect+W,Y=K*Q.aspect+W,Q9.elements[0]=2*Q.near/(Y-H),Q9.elements[8]=(Y+H)/(Y-H),this.cameraL.projectionMatrix.copy(Q9),H=-K*Q.aspect-W,Y=K*Q.aspect-W,Q9.elements[0]=2*Q.near/(Y-H),Q9.elements[8]=(Y+H)/(Y-H),this.cameraR.projectionMatrix.copy(Q9)}this.cameraL.matrixWorld.copy(J.matrixWorld).multiply(iK),this.cameraR.matrixWorld.copy(J.matrixWorld).multiply(sK)}}class TW extends I0{constructor(J=[]){super();this.isArrayCamera=!0,this.isMultiViewCamera=!1,this.cameras=J}}class SW{constructor(J=!0){this.autoStart=J,this.startTime=0,this.oldTime=0,this.elapsedTime=0,this.running=!1}start(){this.startTime=performance.now(),this.oldTime=this.startTime,this.elapsedTime=0,this.running=!0}stop(){this.getElapsedTime(),this.running=!1,this.autoStart=!1}getElapsedTime(){return this.getDelta(),this.elapsedTime}getDelta(){let J=0;if(this.autoStart&&!this.running)return this.start(),0;if(this.running){let Q=performance.now();J=(Q-this.oldTime)/1000,this.oldTime=Q,this.elapsedTime+=J}return J}}var $9=new w,p$=new b0,oE=new w,Z9=new w,W9=new w;class rY extends Q0{constructor(){super();this.type="AudioListener",this.context=tQ.getContext(),this.gain=this.context.createGain(),this.gain.connect(this.context.destination),this.filter=null,this.timeDelta=0,this._clock=new SW}getInput(){return this.gain}removeFilter(){if(this.filter!==null)this.gain.disconnect(this.filter),this.filter.disconnect(this.context.destination),this.gain.connect(this.context.destination),this.filter=null;return this}getFilter(){return this.filter}setFilter(J){if(this.filter!==null)this.gain.disconnect(this.filter),this.filter.disconnect(this.context.destination);else this.gain.disconnect(this.context.destination);return this.filter=J,this.gain.connect(this.filter),this.filter.connect(this.context.destination),this}getMasterVolume(){return this.gain.gain.value}setMasterVolume(J){return this.gain.gain.setTargetAtTime(J,this.context.currentTime,0.01),this}updateMatrixWorld(J){super.updateMatrixWorld(J);let Q=this.context.listener;if(this.timeDelta=this._clock.getDelta(),this.matrixWorld.decompose($9,p$,oE),Z9.set(0,0,-1).applyQuaternion(p$),W9.set(0,1,0).applyQuaternion(p$),Q.positionX){let $=this.context.currentTime+this.timeDelta;Q.positionX.linearRampToValueAtTime($9.x,$),Q.positionY.linearRampToValueAtTime($9.y,$),Q.positionZ.linearRampToValueAtTime($9.z,$),Q.forwardX.linearRampToValueAtTime(Z9.x,$),Q.forwardY.linearRampToValueAtTime(Z9.y,$),Q.forwardZ.linearRampToValueAtTime(Z9.z,$),Q.upX.linearRampToValueAtTime(W9.x,$),Q.upY.linearRampToValueAtTime(W9.y,$),Q.upZ.linearRampToValueAtTime(W9.z,$)}else Q.setPosition($9.x,$9.y,$9.z),Q.setOrientation(Z9.x,Z9.y,Z9.z,W9.x,W9.y,W9.z)}}class jW extends Q0{constructor(J){super();this.type="Audio",this.listener=J,this.context=J.context,this.gain=this.context.createGain(),this.gain.connect(J.getInput()),this.autoplay=!1,this.buffer=null,this.detune=0,this.loop=!1,this.loopStart=0,this.loopEnd=0,this.offset=0,this.duration=void 0,this.playbackRate=1,this.isPlaying=!1,this.hasPlaybackControl=!0,this.source=null,this.sourceType="empty",this._startedAt=0,this._progress=0,this._connected=!1,this.filters=[]}getOutput(){return this.gain}setNodeSource(J){return this.hasPlaybackControl=!1,this.sourceType="audioNode",this.source=J,this.connect(),this}setMediaElementSource(J){return this.hasPlaybackControl=!1,this.sourceType="mediaNode",this.source=this.context.createMediaElementSource(J),this.connect(),this}setMediaStreamSource(J){return this.hasPlaybackControl=!1,this.sourceType="mediaStreamNode",this.source=this.context.createMediaStreamSource(J),this.connect(),this}setBuffer(J){if(this.buffer=J,this.sourceType="buffer",this.autoplay)this.play();return this}play(J=0){if(this.isPlaying===!0){console.warn("THREE.Audio: Audio is already playing.");return}if(this.hasPlaybackControl===!1){console.warn("THREE.Audio: this Audio has no playback control.");return}this._startedAt=this.context.currentTime+J;let Q=this.context.createBufferSource();return Q.buffer=this.buffer,Q.loop=this.loop,Q.loopStart=this.loopStart,Q.loopEnd=this.loopEnd,Q.onended=this.onEnded.bind(this),Q.start(this._startedAt,this._progress+this.offset,this.duration),this.isPlaying=!0,this.source=Q,this.setDetune(this.detune),this.setPlaybackRate(this.playbackRate),this.connect()}pause(){if(this.hasPlaybackControl===!1){console.warn("THREE.Audio: this Audio has no playback control.");return}if(this.isPlaying===!0){if(this._progress+=Math.max(this.context.currentTime-this._startedAt,0)*this.playbackRate,this.loop===!0)this._progress=this._progress%(this.duration||this.buffer.duration);this.source.stop(),this.source.onended=null,this.isPlaying=!1}return this}stop(J=0){if(this.hasPlaybackControl===!1){console.warn("THREE.Audio: this Audio has no playback control.");return}if(this._progress=0,this.source!==null)this.source.stop(this.context.currentTime+J),this.source.onended=null;return this.isPlaying=!1,this}connect(){if(this.filters.length>0){this.source.connect(this.filters[0]);for(let J=1,Q=this.filters.length;J<Q;J++)this.filters[J-1].connect(this.filters[J]);this.filters[this.filters.length-1].connect(this.getOutput())}else this.source.connect(this.getOutput());return this._connected=!0,this}disconnect(){if(this._connected===!1)return;if(this.filters.length>0){this.source.disconnect(this.filters[0]);for(let J=1,Q=this.filters.length;J<Q;J++)this.filters[J-1].disconnect(this.filters[J]);this.filters[this.filters.length-1].disconnect(this.getOutput())}else this.source.disconnect(this.getOutput());return this._connected=!1,this}getFilters(){return this.filters}setFilters(J){if(!J)J=[];if(this._connected===!0)this.disconnect(),this.filters=J.slice(),this.connect();else this.filters=J.slice();return this}setDetune(J){if(this.detune=J,this.isPlaying===!0&&this.source.detune!==void 0)this.source.detune.setTargetAtTime(this.detune,this.context.currentTime,0.01);return this}getDetune(){return this.detune}getFilter(){return this.getFilters()[0]}setFilter(J){return this.setFilters(J?[J]:[])}setPlaybackRate(J){if(this.hasPlaybackControl===!1){console.warn("THREE.Audio: this Audio has no playback control.");return}if(this.playbackRate=J,this.isPlaying===!0)this.source.playbackRate.setTargetAtTime(this.playbackRate,this.context.currentTime,0.01);return this}getPlaybackRate(){return this.playbackRate}onEnded(){this.isPlaying=!1,this._progress=0}getLoop(){if(this.hasPlaybackControl===!1)return console.warn("THREE.Audio: this Audio has no playback control."),!1;return this.loop}setLoop(J){if(this.hasPlaybackControl===!1){console.warn("THREE.Audio: this Audio has no playback control.");return}if(this.loop=J,this.isPlaying===!0)this.source.loop=this.loop;return this}setLoopStart(J){return this.loopStart=J,this}setLoopEnd(J){return this.loopEnd=J,this}getVolume(){return this.gain.gain.value}setVolume(J){return this.gain.gain.setTargetAtTime(J,this.context.currentTime,0.01),this}copy(J,Q){if(super.copy(J,Q),J.sourceType!=="buffer")return console.warn("THREE.Audio: Audio source type cannot be copied."),this;return this.autoplay=J.autoplay,this.buffer=J.buffer,this.detune=J.detune,this.loop=J.loop,this.loopStart=J.loopStart,this.loopEnd=J.loopEnd,this.offset=J.offset,this.duration=J.duration,this.playbackRate=J.playbackRate,this.hasPlaybackControl=J.hasPlaybackControl,this.sourceType=J.sourceType,this.filters=J.filters.slice(),this}clone(J){return new this.constructor(this.listener).copy(this,J)}}var K9=new w,oK=new b0,aE=new w,H9=new w;class tY extends jW{constructor(J){super(J);this.panner=this.context.createPanner(),this.panner.panningModel="HRTF",this.panner.connect(this.gain)}connect(){return super.connect(),this.panner.connect(this.gain),this}disconnect(){return super.disconnect(),this.panner.disconnect(this.gain),this}getOutput(){return this.panner}getRefDistance(){return this.panner.refDistance}setRefDistance(J){return this.panner.refDistance=J,this}getRolloffFactor(){return this.panner.rolloffFactor}setRolloffFactor(J){return this.panner.rolloffFactor=J,this}getDistanceModel(){return this.panner.distanceModel}setDistanceModel(J){return this.panner.distanceModel=J,this}getMaxDistance(){return this.panner.maxDistance}setMaxDistance(J){return this.panner.maxDistance=J,this}setDirectionalCone(J,Q,$){return this.panner.coneInnerAngle=J,this.panner.coneOuterAngle=Q,this.panner.coneOuterGain=$,this}updateMatrixWorld(J){if(super.updateMatrixWorld(J),this.hasPlaybackControl===!0&&this.isPlaying===!1)return;this.matrixWorld.decompose(K9,oK,aE),H9.set(0,0,1).applyQuaternion(oK);let Q=this.panner;if(Q.positionX){let $=this.context.currentTime+this.listener.timeDelta;Q.positionX.linearRampToValueAtTime(K9.x,$),Q.positionY.linearRampToValueAtTime(K9.y,$),Q.positionZ.linearRampToValueAtTime(K9.z,$),Q.orientationX.linearRampToValueAtTime(H9.x,$),Q.orientationY.linearRampToValueAtTime(H9.y,$),Q.orientationZ.linearRampToValueAtTime(H9.z,$)}else Q.setPosition(K9.x,K9.y,K9.z),Q.setOrientation(H9.x,H9.y,H9.z)}}class eY{constructor(J,Q=2048){this.analyser=J.context.createAnalyser(),this.analyser.fftSize=Q,this.data=new Uint8Array(this.analyser.frequencyBinCount),J.getOutput().connect(this.analyser)}getFrequencyData(){return this.analyser.getByteFrequencyData(this.data),this.data}getAverageFrequency(){let J=0,Q=this.getFrequencyData();for(let $=0;$<Q.length;$++)J+=Q[$];return J/Q.length}}class yW{constructor(J,Q,$){this.binding=J,this.valueSize=$;let Z,W,K;switch(Q){case"quaternion":Z=this._slerp,W=this._slerpAdditive,K=this._setAdditiveIdentityQuaternion,this.buffer=new Float64Array($*6),this._workIndex=5;break;case"string":case"bool":Z=this._select,W=this._select,K=this._setAdditiveIdentityOther,this.buffer=Array($*5);break;default:Z=this._lerp,W=this._lerpAdditive,K=this._setAdditiveIdentityNumeric,this.buffer=new Float64Array($*5)}this._mixBufferRegion=Z,this._mixBufferRegionAdditive=W,this._setIdentity=K,this._origIndex=3,this._addIndex=4,this.cumulativeWeight=0,this.cumulativeWeightAdditive=0,this.useCount=0,this.referenceCount=0}accumulate(J,Q){let $=this.buffer,Z=this.valueSize,W=J*Z+Z,K=this.cumulativeWeight;if(K===0){for(let H=0;H!==Z;++H)$[W+H]=$[H];K=Q}else{K+=Q;let H=Q/K;this._mixBufferRegion($,W,0,H,Z)}this.cumulativeWeight=K}accumulateAdditive(J){let Q=this.buffer,$=this.valueSize,Z=$*this._addIndex;if(this.cumulativeWeightAdditive===0)this._setIdentity();this._mixBufferRegionAdditive(Q,Z,0,J,$),this.cumulativeWeightAdditive+=J}apply(J){let Q=this.valueSize,$=this.buffer,Z=J*Q+Q,W=this.cumulativeWeight,K=this.cumulativeWeightAdditive,H=this.binding;if(this.cumulativeWeight=0,this.cumulativeWeightAdditive=0,W<1){let Y=Q*this._origIndex;this._mixBufferRegion($,Z,Y,1-W,Q)}if(K>0)this._mixBufferRegionAdditive($,Z,this._addIndex*Q,1,Q);for(let Y=Q,X=Q+Q;Y!==X;++Y)if($[Y]!==$[Y+Q]){H.setValue($,Z);break}}saveOriginalState(){let J=this.binding,Q=this.buffer,$=this.valueSize,Z=$*this._origIndex;J.getValue(Q,Z);for(let W=$,K=Z;W!==K;++W)Q[W]=Q[Z+W%$];this._setIdentity(),this.cumulativeWeight=0,this.cumulativeWeightAdditive=0}restoreOriginalState(){let J=this.valueSize*3;this.binding.setValue(this.buffer,J)}_setAdditiveIdentityNumeric(){let J=this._addIndex*this.valueSize,Q=J+this.valueSize;for(let $=J;$<Q;$++)this.buffer[$]=0}_setAdditiveIdentityQuaternion(){this._setAdditiveIdentityNumeric(),this.buffer[this._addIndex*this.valueSize+3]=1}_setAdditiveIdentityOther(){let J=this._origIndex*this.valueSize,Q=this._addIndex*this.valueSize;for(let $=0;$<this.valueSize;$++)this.buffer[Q+$]=this.buffer[J+$]}_select(J,Q,$,Z,W){if(Z>=0.5)for(let K=0;K!==W;++K)J[Q+K]=J[$+K]}_slerp(J,Q,$,Z){b0.slerpFlat(J,Q,J,Q,J,$,Z)}_slerpAdditive(J,Q,$,Z,W){let K=this._workIndex*W;b0.multiplyQuaternionsFlat(J,K,J,Q,J,$),b0.slerpFlat(J,Q,J,Q,J,K,Z)}_lerp(J,Q,$,Z,W){let K=1-Z;for(let H=0;H!==W;++H){let Y=Q+H;J[Y]=J[Y]*K+J[$+H]*Z}}_lerpAdditive(J,Q,$,Z,W){for(let K=0;K!==W;++K){let H=Q+K;J[H]=J[H]+J[$+K]*Z}}}var vW="\\[\\]\\.:\\/",rE=new RegExp("["+vW+"]","g"),fW="[^"+vW+"]",tE="[^"+vW.replace("\\.","")+"]",eE=/((?:WC+[\/:])*)/.source.replace("WC",fW),JN=/(WCOD+)?/.source.replace("WCOD",tE),QN=/(?:\.(WC+)(?:\[(.+)\])?)?/.source.replace("WC",fW),$N=/\.(WC+)(?:\[(.+)\])?/.source.replace("WC",fW),ZN=new RegExp("^"+eE+JN+QN+$N+"$"),WN=["material","materials","bones","map"];class JX{constructor(J,Q,$){let Z=$||eJ.parseTrackName(Q);this._targetGroup=J,this._bindings=J.subscribe_(Q,Z)}getValue(J,Q){this.bind();let $=this._targetGroup.nCachedObjects_,Z=this._bindings[$];if(Z!==void 0)Z.getValue(J,Q)}setValue(J,Q){let $=this._bindings;for(let Z=this._targetGroup.nCachedObjects_,W=$.length;Z!==W;++Z)$[Z].setValue(J,Q)}bind(){let J=this._bindings;for(let Q=this._targetGroup.nCachedObjects_,$=J.length;Q!==$;++Q)J[Q].bind()}unbind(){let J=this._bindings;for(let Q=this._targetGroup.nCachedObjects_,$=J.length;Q!==$;++Q)J[Q].unbind()}}class eJ{constructor(J,Q,$){this.path=Q,this.parsedPath=$||eJ.parseTrackName(Q),this.node=eJ.findNode(J,this.parsedPath.nodeName),this.rootNode=J,this.getValue=this._getValue_unbound,this.setValue=this._setValue_unbound}static create(J,Q,$){if(!(J&&J.isAnimationObjectGroup))return new eJ(J,Q,$);else return new eJ.Composite(J,Q,$)}static sanitizeNodeName(J){return J.replace(/\s/g,"_").replace(rE,"")}static parseTrackName(J){let Q=ZN.exec(J);if(Q===null)throw Error("PropertyBinding: Cannot parse trackName: "+J);let $={nodeName:Q[2],objectName:Q[3],objectIndex:Q[4],propertyName:Q[5],propertyIndex:Q[6]},Z=$.nodeName&&$.nodeName.lastIndexOf(".");if(Z!==void 0&&Z!==-1){let W=$.nodeName.substring(Z+1);if(WN.indexOf(W)!==-1)$.nodeName=$.nodeName.substring(0,Z),$.objectName=W}if($.propertyName===null||$.propertyName.length===0)throw Error("PropertyBinding: can not parse propertyName from trackName: "+J);return $}static findNode(J,Q){if(Q===void 0||Q===""||Q==="."||Q===-1||Q===J.name||Q===J.uuid)return J;if(J.skeleton){let $=J.skeleton.getBoneByName(Q);if($!==void 0)return $}if(J.children){let $=function(W){for(let K=0;K<W.length;K++){let H=W[K];if(H.name===Q||H.uuid===Q)return H;let Y=$(H.children);if(Y)return Y}return null},Z=$(J.children);if(Z)return Z}return null}_getValue_unavailable(){}_setValue_unavailable(){}_getValue_direct(J,Q){J[Q]=this.targetObject[this.propertyName]}_getValue_array(J,Q){let $=this.resolvedProperty;for(let Z=0,W=$.length;Z!==W;++Z)J[Q++]=$[Z]}_getValue_arrayElement(J,Q){J[Q]=this.resolvedProperty[this.propertyIndex]}_getValue_toArray(J,Q){this.resolvedProperty.toArray(J,Q)}_setValue_direct(J,Q){this.targetObject[this.propertyName]=J[Q]}_setValue_direct_setNeedsUpdate(J,Q){this.targetObject[this.propertyName]=J[Q],this.targetObject.needsUpdate=!0}_setValue_direct_setMatrixWorldNeedsUpdate(J,Q){this.targetObject[this.propertyName]=J[Q],this.targetObject.matrixWorldNeedsUpdate=!0}_setValue_array(J,Q){let $=this.resolvedProperty;for(let Z=0,W=$.length;Z!==W;++Z)$[Z]=J[Q++]}_setValue_array_setNeedsUpdate(J,Q){let $=this.resolvedProperty;for(let Z=0,W=$.length;Z!==W;++Z)$[Z]=J[Q++];this.targetObject.needsUpdate=!0}_setValue_array_setMatrixWorldNeedsUpdate(J,Q){let $=this.resolvedProperty;for(let Z=0,W=$.length;Z!==W;++Z)$[Z]=J[Q++];this.targetObject.matrixWorldNeedsUpdate=!0}_setValue_arrayElement(J,Q){this.resolvedProperty[this.propertyIndex]=J[Q]}_setValue_arrayElement_setNeedsUpdate(J,Q){this.resolvedProperty[this.propertyIndex]=J[Q],this.targetObject.needsUpdate=!0}_setValue_arrayElement_setMatrixWorldNeedsUpdate(J,Q){this.resolvedProperty[this.propertyIndex]=J[Q],this.targetObject.matrixWorldNeedsUpdate=!0}_setValue_fromArray(J,Q){this.resolvedProperty.fromArray(J,Q)}_setValue_fromArray_setNeedsUpdate(J,Q){this.resolvedProperty.fromArray(J,Q),this.targetObject.needsUpdate=!0}_setValue_fromArray_setMatrixWorldNeedsUpdate(J,Q){this.resolvedProperty.fromArray(J,Q),this.targetObject.matrixWorldNeedsUpdate=!0}_getValue_unbound(J,Q){this.bind(),this.getValue(J,Q)}_setValue_unbound(J,Q){this.bind(),this.setValue(J,Q)}bind(){let J=this.node,Q=this.parsedPath,$=Q.objectName,Z=Q.propertyName,W=Q.propertyIndex;if(!J)J=eJ.findNode(this.rootNode,Q.nodeName),this.node=J;if(this.getValue=this._getValue_unavailable,this.setValue=this._setValue_unavailable,!J){console.warn("THREE.PropertyBinding: No target node found for track: "+this.path+".");return}if($){let X=Q.objectIndex;switch($){case"materials":if(!J.material){console.error("THREE.PropertyBinding: Can not bind to material as node does not have a material.",this);return}if(!J.material.materials){console.error("THREE.PropertyBinding: Can not bind to material.materials as node.material does not have a materials array.",this);return}J=J.material.materials;break;case"bones":if(!J.skeleton){console.error("THREE.PropertyBinding: Can not bind to bones as node does not have a skeleton.",this);return}J=J.skeleton.bones;for(let U=0;U<J.length;U++)if(J[U].name===X){X=U;break}break;case"map":if("map"in J){J=J.map;break}if(!J.material){console.error("THREE.PropertyBinding: Can not bind to material as node does not have a material.",this);return}if(!J.material.map){console.error("THREE.PropertyBinding: Can not bind to material.map as node.material does not have a map.",this);return}J=J.material.map;break;default:if(J[$]===void 0){console.error("THREE.PropertyBinding: Can not bind to objectName of node undefined.",this);return}J=J[$]}if(X!==void 0){if(J[X]===void 0){console.error("THREE.PropertyBinding: Trying to bind to objectIndex of objectName, but is undefined.",this,J);return}J=J[X]}}let K=J[Z];if(K===void 0){let X=Q.nodeName;console.error("THREE.PropertyBinding: Trying to update property for track: "+X+"."+Z+" but it wasn't found.",J);return}let H=this.Versioning.None;if(this.targetObject=J,J.isMaterial===!0)H=this.Versioning.NeedsUpdate;else if(J.isObject3D===!0)H=this.Versioning.MatrixWorldNeedsUpdate;let Y=this.BindingType.Direct;if(W!==void 0){if(Z==="morphTargetInfluences"){if(!J.geometry){console.error("THREE.PropertyBinding: Can not bind to morphTargetInfluences because node does not have a geometry.",this);return}if(!J.geometry.morphAttributes){console.error("THREE.PropertyBinding: Can not bind to morphTargetInfluences because node does not have a geometry.morphAttributes.",this);return}if(J.morphTargetDictionary[W]!==void 0)W=J.morphTargetDictionary[W]}Y=this.BindingType.ArrayElement,this.resolvedProperty=K,this.propertyIndex=W}else if(K.fromArray!==void 0&&K.toArray!==void 0)Y=this.BindingType.HasFromToArray,this.resolvedProperty=K;else if(Array.isArray(K))Y=this.BindingType.EntireArray,this.resolvedProperty=K;else this.propertyName=Z;this.getValue=this.GetterByBindingType[Y],this.setValue=this.SetterByBindingTypeAndVersioning[Y][H]}unbind(){this.node=null,this.getValue=this._getValue_unbound,this.setValue=this._setValue_unbound}}eJ.Composite=JX;eJ.prototype.BindingType={Direct:0,EntireArray:1,ArrayElement:2,HasFromToArray:3};eJ.prototype.Versioning={None:0,NeedsUpdate:1,MatrixWorldNeedsUpdate:2};eJ.prototype.GetterByBindingType=[eJ.prototype._getValue_direct,eJ.prototype._getValue_array,eJ.prototype._getValue_arrayElement,eJ.prototype._getValue_toArray];eJ.prototype.SetterByBindingTypeAndVersioning=[[eJ.prototype._setValue_direct,eJ.prototype._setValue_direct_setNeedsUpdate,eJ.prototype._setValue_direct_setMatrixWorldNeedsUpdate],[eJ.prototype._setValue_array,eJ.prototype._setValue_array_setNeedsUpdate,eJ.prototype._setValue_array_setMatrixWorldNeedsUpdate],[eJ.prototype._setValue_arrayElement,eJ.prototype._setValue_arrayElement_setNeedsUpdate,eJ.prototype._setValue_arrayElement_setMatrixWorldNeedsUpdate],[eJ.prototype._setValue_fromArray,eJ.prototype._setValue_fromArray_setNeedsUpdate,eJ.prototype._setValue_fromArray_setMatrixWorldNeedsUpdate]];class QX{constructor(){this.isAnimationObjectGroup=!0,this.uuid=n0(),this._objects=Array.prototype.slice.call(arguments),this.nCachedObjects_=0;let J={};this._indicesByUUID=J;for(let $=0,Z=arguments.length;$!==Z;++$)J[arguments[$].uuid]=$;this._paths=[],this._parsedPaths=[],this._bindings=[],this._bindingsIndicesByPath={};let Q=this;this.stats={objects:{get total(){return Q._objects.length},get inUse(){return this.total-Q.nCachedObjects_}},get bindingsPerObject(){return Q._bindings.length}}}add(){let J=this._objects,Q=this._indicesByUUID,$=this._paths,Z=this._parsedPaths,W=this._bindings,K=W.length,H=void 0,Y=J.length,X=this.nCachedObjects_;for(let U=0,G=arguments.length;U!==G;++U){let E=arguments[U],N=E.uuid,q=Q[N];if(q===void 0){q=Y++,Q[N]=q,J.push(E);for(let R=0,F=K;R!==F;++R)W[R].push(new eJ(E,$[R],Z[R]))}else if(q<X){H=J[q];let R=--X,F=J[R];Q[F.uuid]=q,J[q]=F,Q[N]=R,J[R]=E;for(let O=0,D=K;O!==D;++O){let k=W[O],M=k[R],L=k[q];if(k[q]=M,L===void 0)L=new eJ(E,$[O],Z[O]);k[R]=L}}else if(J[q]!==H)console.error("THREE.AnimationObjectGroup: Different objects with the same UUID detected. Clean the caches or recreate your infrastructure when reloading scenes.")}this.nCachedObjects_=X}remove(){let J=this._objects,Q=this._indicesByUUID,$=this._bindings,Z=$.length,W=this.nCachedObjects_;for(let K=0,H=arguments.length;K!==H;++K){let Y=arguments[K],X=Y.uuid,U=Q[X];if(U!==void 0&&U>=W){let G=W++,E=J[G];Q[E.uuid]=U,J[U]=E,Q[X]=G,J[G]=Y;for(let N=0,q=Z;N!==q;++N){let R=$[N],F=R[G],O=R[U];R[U]=F,R[G]=O}}}this.nCachedObjects_=W}uncache(){let J=this._objects,Q=this._indicesByUUID,$=this._bindings,Z=$.length,W=this.nCachedObjects_,K=J.length;for(let H=0,Y=arguments.length;H!==Y;++H){let X=arguments[H],U=X.uuid,G=Q[U];if(G!==void 0)if(delete Q[U],G<W){let E=--W,N=J[E],q=--K,R=J[q];Q[N.uuid]=G,J[G]=N,Q[R.uuid]=E,J[E]=R,J.pop();for(let F=0,O=Z;F!==O;++F){let D=$[F],k=D[E],M=D[q];D[G]=k,D[E]=M,D.pop()}}else{let E=--K,N=J[E];if(E>0)Q[N.uuid]=G;J[G]=N,J.pop();for(let q=0,R=Z;q!==R;++q){let F=$[q];F[G]=F[E],F.pop()}}}this.nCachedObjects_=W}subscribe_(J,Q){let $=this._bindingsIndicesByPath,Z=$[J],W=this._bindings;if(Z!==void 0)return W[Z];let K=this._paths,H=this._parsedPaths,Y=this._objects,X=Y.length,U=this.nCachedObjects_,G=Array(X);Z=W.length,$[J]=Z,K.push(J),H.push(Q),W.push(G);for(let E=U,N=Y.length;E!==N;++E){let q=Y[E];G[E]=new eJ(q,J,Q)}return G}unsubscribe_(J){let Q=this._bindingsIndicesByPath,$=Q[J];if($!==void 0){let Z=this._paths,W=this._parsedPaths,K=this._bindings,H=K.length-1,Y=K[H],X=J[H];Q[X]=$,K[$]=Y,K.pop(),W[$]=W[H],W.pop(),Z[$]=Z[H],Z.pop()}}}class bW{constructor(J,Q,$=null,Z=Q.blendMode){this._mixer=J,this._clip=Q,this._localRoot=$,this.blendMode=Z;let W=Q.tracks,K=W.length,H=Array(K),Y={endingStart:2400,endingEnd:2400};for(let X=0;X!==K;++X){let U=W[X].createInterpolant(null);H[X]=U,U.settings=Y}this._interpolantSettings=Y,this._interpolants=H,this._propertyBindings=Array(K),this._cacheIndex=null,this._byClipCacheIndex=null,this._timeScaleInterpolant=null,this._weightInterpolant=null,this.loop=2201,this._loopCount=-1,this._startTime=null,this.time=0,this.timeScale=1,this._effectiveTimeScale=1,this.weight=1,this._effectiveWeight=1,this.repetitions=1/0,this.paused=!1,this.enabled=!0,this.clampWhenFinished=!1,this.zeroSlopeAtStart=!0,this.zeroSlopeAtEnd=!0}play(){return this._mixer._activateAction(this),this}stop(){return this._mixer._deactivateAction(this),this.reset()}reset(){return this.paused=!1,this.enabled=!0,this.time=0,this._loopCount=-1,this._startTime=null,this.stopFading().stopWarping()}isRunning(){return this.enabled&&!this.paused&&this.timeScale!==0&&this._startTime===null&&this._mixer._isActiveAction(this)}isScheduled(){return this._mixer._isActiveAction(this)}startAt(J){return this._startTime=J,this}setLoop(J,Q){return this.loop=J,this.repetitions=Q,this}setEffectiveWeight(J){return this.weight=J,this._effectiveWeight=this.enabled?J:0,this.stopFading()}getEffectiveWeight(){return this._effectiveWeight}fadeIn(J){return this._scheduleFading(J,0,1)}fadeOut(J){return this._scheduleFading(J,1,0)}crossFadeFrom(J,Q,$=!1){if(J.fadeOut(Q),this.fadeIn(Q),$===!0){let Z=this._clip.duration,W=J._clip.duration,K=W/Z,H=Z/W;J.warp(1,K,Q),this.warp(H,1,Q)}return this}crossFadeTo(J,Q,$=!1){return J.crossFadeFrom(this,Q,$)}stopFading(){let J=this._weightInterpolant;if(J!==null)this._weightInterpolant=null,this._mixer._takeBackControlInterpolant(J);return this}setEffectiveTimeScale(J){return this.timeScale=J,this._effectiveTimeScale=this.paused?0:J,this.stopWarping()}getEffectiveTimeScale(){return this._effectiveTimeScale}setDuration(J){return this.timeScale=this._clip.duration/J,this.stopWarping()}syncWith(J){return this.time=J.time,this.timeScale=J.timeScale,this.stopWarping()}halt(J){return this.warp(this._effectiveTimeScale,0,J)}warp(J,Q,$){let Z=this._mixer,W=Z.time,K=this.timeScale,H=this._timeScaleInterpolant;if(H===null)H=Z._lendControlInterpolant(),this._timeScaleInterpolant=H;let{parameterPositions:Y,sampleValues:X}=H;return Y[0]=W,Y[1]=W+$,X[0]=J/K,X[1]=Q/K,this}stopWarping(){let J=this._timeScaleInterpolant;if(J!==null)this._timeScaleInterpolant=null,this._mixer._takeBackControlInterpolant(J);return this}getMixer(){return this._mixer}getClip(){return this._clip}getRoot(){return this._localRoot||this._mixer._root}_update(J,Q,$,Z){if(!this.enabled){this._updateWeight(J);return}let W=this._startTime;if(W!==null){let Y=(J-W)*$;if(Y<0||$===0)Q=0;else this._startTime=null,Q=$*Y}Q*=this._updateTimeScale(J);let K=this._updateTime(Q),H=this._updateWeight(J);if(H>0){let Y=this._interpolants,X=this._propertyBindings;switch(this.blendMode){case 2501:for(let U=0,G=Y.length;U!==G;++U)Y[U].evaluate(K),X[U].accumulateAdditive(H);break;case 2500:default:for(let U=0,G=Y.length;U!==G;++U)Y[U].evaluate(K),X[U].accumulate(Z,H)}}}_updateWeight(J){let Q=0;if(this.enabled){Q=this.weight;let $=this._weightInterpolant;if($!==null){let Z=$.evaluate(J)[0];if(Q*=Z,J>$.parameterPositions[1]){if(this.stopFading(),Z===0)this.enabled=!1}}}return this._effectiveWeight=Q,Q}_updateTimeScale(J){let Q=0;if(!this.paused){Q=this.timeScale;let $=this._timeScaleInterpolant;if($!==null){let Z=$.evaluate(J)[0];if(Q*=Z,J>$.parameterPositions[1])if(this.stopWarping(),Q===0)this.paused=!0;else this.timeScale=Q}}return this._effectiveTimeScale=Q,Q}_updateTime(J){let Q=this._clip.duration,$=this.loop,Z=this.time+J,W=this._loopCount,K=$===2202;if(J===0){if(W===-1)return Z;return K&&(W&1)===1?Q-Z:Z}if($===2200){if(W===-1)this._loopCount=0,this._setEndings(!0,!0,!1);J:{if(Z>=Q)Z=Q;else if(Z<0)Z=0;else{this.time=Z;break J}if(this.clampWhenFinished)this.paused=!0;else this.enabled=!1;this.time=Z,this._mixer.dispatchEvent({type:"finished",action:this,direction:J<0?-1:1})}}else{if(W===-1)if(J>=0)W=0,this._setEndings(!0,this.repetitions===0,K);else this._setEndings(this.repetitions===0,!0,K);if(Z>=Q||Z<0){let H=Math.floor(Z/Q);Z-=Q*H,W+=Math.abs(H);let Y=this.repetitions-W;if(Y<=0){if(this.clampWhenFinished)this.paused=!0;else this.enabled=!1;Z=J>0?Q:0,this.time=Z,this._mixer.dispatchEvent({type:"finished",action:this,direction:J>0?1:-1})}else{if(Y===1){let X=J<0;this._setEndings(X,!X,K)}else this._setEndings(!1,!1,K);this._loopCount=W,this.time=Z,this._mixer.dispatchEvent({type:"loop",action:this,loopDelta:H})}}else this.time=Z;if(K&&(W&1)===1)return Q-Z}return Z}_setEndings(J,Q,$){let Z=this._interpolantSettings;if($)Z.endingStart=2401,Z.endingEnd=2401;else{if(J)Z.endingStart=this.zeroSlopeAtStart?2401:2400;else Z.endingStart=2402;if(Q)Z.endingEnd=this.zeroSlopeAtEnd?2401:2400;else Z.endingEnd=2402}}_scheduleFading(J,Q,$){let Z=this._mixer,W=Z.time,K=this._weightInterpolant;if(K===null)K=Z._lendControlInterpolant(),this._weightInterpolant=K;let{parameterPositions:H,sampleValues:Y}=K;return H[0]=W,Y[0]=Q,H[1]=W+J,Y[1]=$,this}}var KN=new Float32Array(1);class $X extends H8{constructor(J){super();this._root=J,this._initMemoryManager(),this._accuIndex=0,this.time=0,this.timeScale=1}_bindAction(J,Q){let $=J._localRoot||this._root,Z=J._clip.tracks,W=Z.length,K=J._propertyBindings,H=J._interpolants,Y=$.uuid,X=this._bindingsByRootAndName,U=X[Y];if(U===void 0)U={},X[Y]=U;for(let G=0;G!==W;++G){let E=Z[G],N=E.name,q=U[N];if(q!==void 0)++q.referenceCount,K[G]=q;else{if(q=K[G],q!==void 0){if(q._cacheIndex===null)++q.referenceCount,this._addInactiveBinding(q,Y,N);continue}let R=Q&&Q._propertyBindings[G].binding.parsedPath;q=new yW(eJ.create($,N,R),E.ValueTypeName,E.getValueSize()),++q.referenceCount,this._addInactiveBinding(q,Y,N),K[G]=q}H[G].resultBuffer=q.buffer}}_activateAction(J){if(!this._isActiveAction(J)){if(J._cacheIndex===null){let $=(J._localRoot||this._root).uuid,Z=J._clip.uuid,W=this._actionsByClip[Z];this._bindAction(J,W&&W.knownActions[0]),this._addInactiveAction(J,Z,$)}let Q=J._propertyBindings;for(let $=0,Z=Q.length;$!==Z;++$){let W=Q[$];if(W.useCount++===0)this._lendBinding(W),W.saveOriginalState()}this._lendAction(J)}}_deactivateAction(J){if(this._isActiveAction(J)){let Q=J._propertyBindings;for(let $=0,Z=Q.length;$!==Z;++$){let W=Q[$];if(--W.useCount===0)W.restoreOriginalState(),this._takeBackBinding(W)}this._takeBackAction(J)}}_initMemoryManager(){this._actions=[],this._nActiveActions=0,this._actionsByClip={},this._bindings=[],this._nActiveBindings=0,this._bindingsByRootAndName={},this._controlInterpolants=[],this._nActiveControlInterpolants=0;let J=this;this.stats={actions:{get total(){return J._actions.length},get inUse(){return J._nActiveActions}},bindings:{get total(){return J._bindings.length},get inUse(){return J._nActiveBindings}},controlInterpolants:{get total(){return J._controlInterpolants.length},get inUse(){return J._nActiveControlInterpolants}}}}_isActiveAction(J){let Q=J._cacheIndex;return Q!==null&&Q<this._nActiveActions}_addInactiveAction(J,Q,$){let Z=this._actions,W=this._actionsByClip,K=W[Q];if(K===void 0)K={knownActions:[J],actionByRoot:{}},J._byClipCacheIndex=0,W[Q]=K;else{let H=K.knownActions;J._byClipCacheIndex=H.length,H.push(J)}J._cacheIndex=Z.length,Z.push(J),K.actionByRoot[$]=J}_removeInactiveAction(J){let Q=this._actions,$=Q[Q.length-1],Z=J._cacheIndex;$._cacheIndex=Z,Q[Z]=$,Q.pop(),J._cacheIndex=null;let W=J._clip.uuid,K=this._actionsByClip,H=K[W],Y=H.knownActions,X=Y[Y.length-1],U=J._byClipCacheIndex;X._byClipCacheIndex=U,Y[U]=X,Y.pop(),J._byClipCacheIndex=null;let G=H.actionByRoot,E=(J._localRoot||this._root).uuid;if(delete G[E],Y.length===0)delete K[W];this._removeInactiveBindingsForAction(J)}_removeInactiveBindingsForAction(J){let Q=J._propertyBindings;for(let $=0,Z=Q.length;$!==Z;++$){let W=Q[$];if(--W.referenceCount===0)this._removeInactiveBinding(W)}}_lendAction(J){let Q=this._actions,$=J._cacheIndex,Z=this._nActiveActions++,W=Q[Z];J._cacheIndex=Z,Q[Z]=J,W._cacheIndex=$,Q[$]=W}_takeBackAction(J){let Q=this._actions,$=J._cacheIndex,Z=--this._nActiveActions,W=Q[Z];J._cacheIndex=Z,Q[Z]=J,W._cacheIndex=$,Q[$]=W}_addInactiveBinding(J,Q,$){let Z=this._bindingsByRootAndName,W=this._bindings,K=Z[Q];if(K===void 0)K={},Z[Q]=K;K[$]=J,J._cacheIndex=W.length,W.push(J)}_removeInactiveBinding(J){let Q=this._bindings,$=J.binding,Z=$.rootNode.uuid,W=$.path,K=this._bindingsByRootAndName,H=K[Z],Y=Q[Q.length-1],X=J._cacheIndex;if(Y._cacheIndex=X,Q[X]=Y,Q.pop(),delete H[W],Object.keys(H).length===0)delete K[Z]}_lendBinding(J){let Q=this._bindings,$=J._cacheIndex,Z=this._nActiveBindings++,W=Q[Z];J._cacheIndex=Z,Q[Z]=J,W._cacheIndex=$,Q[$]=W}_takeBackBinding(J){let Q=this._bindings,$=J._cacheIndex,Z=--this._nActiveBindings,W=Q[Z];J._cacheIndex=Z,Q[Z]=J,W._cacheIndex=$,Q[$]=W}_lendControlInterpolant(){let J=this._controlInterpolants,Q=this._nActiveControlInterpolants++,$=J[Q];if($===void 0)$=new sQ(new Float32Array(2),new Float32Array(2),1,KN),$.__cacheIndex=Q,J[Q]=$;return $}_takeBackControlInterpolant(J){let Q=this._controlInterpolants,$=J.__cacheIndex,Z=--this._nActiveControlInterpolants,W=Q[Z];J.__cacheIndex=Z,Q[Z]=J,W.__cacheIndex=$,Q[$]=W}clipAction(J,Q,$){let Z=Q||this._root,W=Z.uuid,K=typeof J==="string"?e9.findByName(Z,J):J,H=K!==null?K.uuid:J,Y=this._actionsByClip[H],X=null;if($===void 0)if(K!==null)$=K.blendMode;else $=2500;if(Y!==void 0){let G=Y.actionByRoot[W];if(G!==void 0&&G.blendMode===$)return G;if(X=Y.knownActions[0],K===null)K=X._clip}if(K===null)return null;let U=new bW(this,K,Q,$);return this._bindAction(U,X),this._addInactiveAction(U,H,W),U}existingAction(J,Q){let $=Q||this._root,Z=$.uuid,W=typeof J==="string"?e9.findByName($,J):J,K=W?W.uuid:J,H=this._actionsByClip[K];if(H!==void 0)return H.actionByRoot[Z]||null;return null}stopAllAction(){let J=this._actions,Q=this._nActiveActions;for(let $=Q-1;$>=0;--$)J[$].stop();return this}update(J){J*=this.timeScale;let Q=this._actions,$=this._nActiveActions,Z=this.time+=J,W=Math.sign(J),K=this._accuIndex^=1;for(let X=0;X!==$;++X)Q[X]._update(Z,J,W,K);let H=this._bindings,Y=this._nActiveBindings;for(let X=0;X!==Y;++X)H[X].apply(K);return this}setTime(J){this.time=0;for(let Q=0;Q<this._actions.length;Q++)this._actions[Q].time=0;return this.update(J)}getRoot(){return this._root}uncacheClip(J){let Q=this._actions,$=J.uuid,Z=this._actionsByClip,W=Z[$];if(W!==void 0){let K=W.knownActions;for(let H=0,Y=K.length;H!==Y;++H){let X=K[H];this._deactivateAction(X);let U=X._cacheIndex,G=Q[Q.length-1];X._cacheIndex=null,X._byClipCacheIndex=null,G._cacheIndex=U,Q[U]=G,Q.pop(),this._removeInactiveBindingsForAction(X)}delete Z[$]}}uncacheRoot(J){let Q=J.uuid,$=this._actionsByClip;for(let K in $){let H=$[K].actionByRoot,Y=H[Q];if(Y!==void 0)this._deactivateAction(Y),this._removeInactiveAction(Y)}let Z=this._bindingsByRootAndName,W=Z[Q];if(W!==void 0)for(let K in W){let H=W[K];H.restoreOriginalState(),this._removeInactiveBinding(H)}}uncacheAction(J,Q){let $=this.existingAction(J,Q);if($!==null)this._deactivateAction($),this._removeInactiveAction($)}}class ZX extends OQ{constructor(J=1,Q=1,$=1,Z={}){super(J,Q,Z);this.isRenderTarget3D=!0,this.depth=$,this.texture=new n6(null,J,Q,$),this._setTextureOptions(Z),this.texture.isRenderTargetTexture=!0}}class hW{constructor(J){this.value=J}clone(){return new hW(this.value.clone===void 0?this.value:this.value.clone())}}var HN=0;class WX extends H8{constructor(){super();this.isUniformsGroup=!0,Object.defineProperty(this,"id",{value:HN++}),this.name="",this.usage=35044,this.uniforms=[]}add(J){return this.uniforms.push(J),this}remove(J){let Q=this.uniforms.indexOf(J);if(Q!==-1)this.uniforms.splice(Q,1);return this}setName(J){return this.name=J,this}setUsage(J){return this.usage=J,this}dispose(){this.dispatchEvent({type:"dispose"})}copy(J){this.name=J.name,this.usage=J.usage;let Q=J.uniforms;this.uniforms.length=0;for(let $=0,Z=Q.length;$<Z;$++){let W=Array.isArray(Q[$])?Q[$]:[Q[$]];for(let K=0;K<W.length;K++)this.uniforms.push(W[K].clone())}return this}clone(){return new this.constructor().copy(this)}}class KX extends a6{constructor(J,Q,$=1){super(J,Q);this.isInstancedInterleavedBuffer=!0,this.meshPerAttribute=$}copy(J){return super.copy(J),this.meshPerAttribute=J.meshPerAttribute,this}clone(J){let Q=super.clone(J);return Q.meshPerAttribute=this.meshPerAttribute,Q}toJSON(J){let Q=super.toJSON(J);return Q.isInstancedInterleavedBuffer=!0,Q.meshPerAttribute=this.meshPerAttribute,Q}}class HX{constructor(J,Q,$,Z,W,K=!1){this.isGLBufferAttribute=!0,this.name="",this.buffer=J,this.type=Q,this.itemSize=$,this.elementSize=Z,this.count=W,this.normalized=K,this.version=0}set needsUpdate(J){if(J===!0)this.version++}setBuffer(J){return this.buffer=J,this}setType(J,Q){return this.type=J,this.elementSize=Q,this}setItemSize(J){return this.itemSize=J,this}setCount(J){return this.count=J,this}}var aK=new hJ;class YX{constructor(J,Q,$=0,Z=1/0){this.ray=new F9(J,Q),this.near=$,this.far=Z,this.camera=null,this.layers=new s6,this.params={Mesh:{},Line:{threshold:1},LOD:{},Points:{threshold:1},Sprite:{}}}set(J,Q){this.ray.set(J,Q)}setFromCamera(J,Q){if(Q.isPerspectiveCamera)this.ray.origin.setFromMatrixPosition(Q.matrixWorld),this.ray.direction.set(J.x,J.y,0.5).unproject(Q).sub(this.ray.origin).normalize(),this.camera=Q;else if(Q.isOrthographicCamera)this.ray.origin.set(J.x,J.y,(Q.near+Q.far)/(Q.near-Q.far)).unproject(Q),this.ray.direction.set(0,0,-1).transformDirection(Q.matrixWorld),this.camera=Q;else console.error("THREE.Raycaster: Unsupported camera type: "+Q.type)}setFromXRController(J){return aK.identity().extractRotation(J.matrixWorld),this.ray.origin.setFromMatrixPosition(J.matrixWorld),this.ray.direction.set(0,0,-1).applyMatrix4(aK),this}intersectObject(J,Q=!0,$=[]){return i$(J,this,$,Q),$.sort(rK),$}intersectObjects(J,Q=!0,$=[]){for(let Z=0,W=J.length;Z<W;Z++)i$(J[Z],this,$,Q);return $.sort(rK),$}}function rK(J,Q){return J.distance-Q.distance}function i$(J,Q,$,Z){let W=!0;if(J.layers.test(Q.layers)){if(J.raycast(Q,$)===!1)W=!1}if(W===!0&&Z===!0){let K=J.children;for(let H=0,Y=K.length;H<Y;H++)i$(K[H],Q,$,!0)}}class XX{constructor(){this._previousTime=0,this._currentTime=0,this._startTime=performance.now(),this._delta=0,this._elapsed=0,this._timescale=1,this._document=null,this._pageVisibilityHandler=null}connect(J){if(this._document=J,J.hidden!==void 0)this._pageVisibilityHandler=YN.bind(this),J.addEventListener("visibilitychange",this._pageVisibilityHandler,!1)}disconnect(){if(this._pageVisibilityHandler!==null)this._document.removeEventListener("visibilitychange",this._pageVisibilityHandler),this._pageVisibilityHandler=null;this._document=null}getDelta(){return this._delta/1000}getElapsed(){return this._elapsed/1000}getTimescale(){return this._timescale}setTimescale(J){return this._timescale=J,this}reset(){return this._currentTime=performance.now()-this._startTime,this}dispose(){this.disconnect()}update(J){if(this._pageVisibilityHandler!==null&&this._document.hidden===!0)this._delta=0;else this._previousTime=this._currentTime,this._currentTime=(J!==void 0?J:performance.now())-this._startTime,this._delta=(this._currentTime-this._previousTime)*this._timescale,this._elapsed+=this._delta;return this}}function YN(){if(this._document.hidden===!1)this.reset()}class UX{constructor(J=1,Q=0,$=0){this.radius=J,this.phi=Q,this.theta=$}set(J,Q,$){return this.radius=J,this.phi=Q,this.theta=$,this}copy(J){return this.radius=J.radius,this.phi=J.phi,this.theta=J.theta,this}makeSafe(){return this.phi=bJ(this.phi,0.000001,Math.PI-0.000001),this}setFromVector3(J){return this.setFromCartesianCoords(J.x,J.y,J.z)}setFromCartesianCoords(J,Q,$){if(this.radius=Math.sqrt(J*J+Q*Q+$*$),this.radius===0)this.theta=0,this.phi=0;else this.theta=Math.atan2(J,$),this.phi=Math.acos(bJ(Q/this.radius,-1,1));return this}clone(){return new this.constructor().copy(this)}}class GX{constructor(J=1,Q=0,$=0){this.radius=J,this.theta=Q,this.y=$}set(J,Q,$){return this.radius=J,this.theta=Q,this.y=$,this}copy(J){return this.radius=J.radius,this.theta=J.theta,this.y=J.y,this}setFromVector3(J){return this.setFromCartesianCoords(J.x,J.y,J.z)}setFromCartesianCoords(J,Q,$){return this.radius=Math.sqrt(J*J+$*$),this.theta=Math.atan2(J,$),this.y=Q,this}clone(){return new this.constructor().copy(this)}}class xW{constructor(J,Q,$,Z){if(xW.prototype.isMatrix2=!0,this.elements=[1,0,0,1],J!==void 0)this.set(J,Q,$,Z)}identity(){return this.set(1,0,0,1),this}fromArray(J,Q=0){for(let $=0;$<4;$++)this.elements[$]=J[$+Q];return this}set(J,Q,$,Z){let W=this.elements;return W[0]=J,W[2]=Q,W[1]=$,W[3]=Z,this}}var tK=new t;class EX{constructor(J=new t(1/0,1/0),Q=new t(-1/0,-1/0)){this.isBox2=!0,this.min=J,this.max=Q}set(J,Q){return this.min.copy(J),this.max.copy(Q),this}setFromPoints(J){this.makeEmpty();for(let Q=0,$=J.length;Q<$;Q++)this.expandByPoint(J[Q]);return this}setFromCenterAndSize(J,Q){let $=tK.copy(Q).multiplyScalar(0.5);return this.min.copy(J).sub($),this.max.copy(J).add($),this}clone(){return new this.constructor().copy(this)}copy(J){return this.min.copy(J.min),this.max.copy(J.max),this}makeEmpty(){return this.min.x=this.min.y=1/0,this.max.x=this.max.y=-1/0,this}isEmpty(){return this.max.x<this.min.x||this.max.y<this.min.y}getCenter(J){return this.isEmpty()?J.set(0,0):J.addVectors(this.min,this.max).multiplyScalar(0.5)}getSize(J){return this.isEmpty()?J.set(0,0):J.subVectors(this.max,this.min)}expandByPoint(J){return this.min.min(J),this.max.max(J),this}expandByVector(J){return this.min.sub(J),this.max.add(J),this}expandByScalar(J){return this.min.addScalar(-J),this.max.addScalar(J),this}containsPoint(J){return J.x>=this.min.x&&J.x<=this.max.x&&J.y>=this.min.y&&J.y<=this.max.y}containsBox(J){return this.min.x<=J.min.x&&J.max.x<=this.max.x&&this.min.y<=J.min.y&&J.max.y<=this.max.y}getParameter(J,Q){return Q.set((J.x-this.min.x)/(this.max.x-this.min.x),(J.y-this.min.y)/(this.max.y-this.min.y))}intersectsBox(J){return J.max.x>=this.min.x&&J.min.x<=this.max.x&&J.max.y>=this.min.y&&J.min.y<=this.max.y}clampPoint(J,Q){return Q.copy(J).clamp(this.min,this.max)}distanceToPoint(J){return this.clampPoint(J,tK).distanceTo(J)}intersect(J){if(this.min.max(J.min),this.max.min(J.max),this.isEmpty())this.makeEmpty();return this}union(J){return this.min.min(J.min),this.max.max(J.max),this}translate(J){return this.min.add(J),this.max.add(J),this}equals(J){return J.min.equals(this.min)&&J.max.equals(this.max)}}var eK=new w,u7=new w,u9=new w,c9=new w,m$=new w,XN=new w,UN=new w;class NX{constructor(J=new w,Q=new w){this.start=J,this.end=Q}set(J,Q){return this.start.copy(J),this.end.copy(Q),this}copy(J){return this.start.copy(J.start),this.end.copy(J.end),this}getCenter(J){return J.addVectors(this.start,this.end).multiplyScalar(0.5)}delta(J){return J.subVectors(this.end,this.start)}distanceSq(){return this.start.distanceToSquared(this.end)}distance(){return this.start.distanceTo(this.end)}at(J,Q){return this.delta(Q).multiplyScalar(J).add(this.start)}closestPointToPointParameter(J,Q){eK.subVectors(J,this.start),u7.subVectors(this.end,this.start);let $=u7.dot(u7),W=u7.dot(eK)/$;if(Q)W=bJ(W,0,1);return W}closestPointToPoint(J,Q,$){let Z=this.closestPointToPointParameter(J,Q);return this.delta($).multiplyScalar(Z).add(this.start)}distanceSqToLine3(J,Q=XN,$=UN){let W,K,H=this.start,Y=J.start,X=this.end,U=J.end;u9.subVectors(X,H),c9.subVectors(U,Y),m$.subVectors(H,Y);let G=u9.dot(u9),E=c9.dot(c9),N=c9.dot(m$);if(G<=0.00000000000000010000000000000001&&E<=0.00000000000000010000000000000001)return Q.copy(H),$.copy(Y),Q.sub($),Q.dot(Q);if(G<=0.00000000000000010000000000000001)W=0,K=N/E,K=bJ(K,0,1);else{let q=u9.dot(m$);if(E<=0.00000000000000010000000000000001)K=0,W=bJ(-q/G,0,1);else{let R=u9.dot(c9),F=G*E-R*R;if(F!==0)W=bJ((R*N-q*E)/F,0,1);else W=0;if(K=(R*W+N)/E,K<0)K=0,W=bJ(-q/G,0,1);else if(K>1)K=1,W=bJ((R-q)/G,0,1)}}return Q.copy(H).add(u9.multiplyScalar(W)),$.copy(Y).add(c9.multiplyScalar(K)),Q.sub($),Q.dot(Q)}applyMatrix4(J){return this.start.applyMatrix4(J),this.end.applyMatrix4(J),this}equals(J){return J.start.equals(this.start)&&J.end.equals(this.end)}clone(){return new this.constructor().copy(this)}}var JH=new w;class qX extends Q0{constructor(J,Q){super();this.light=J,this.matrixAutoUpdate=!1,this.color=Q,this.type="SpotLightHelper";let $=new nJ,Z=[0,0,0,0,0,1,0,0,0,1,0,1,0,0,0,-1,0,1,0,0,0,0,1,1,0,0,0,0,-1,1];for(let K=0,H=1,Y=32;K<Y;K++,H++){let X=K/Y*Math.PI*2,U=H/Y*Math.PI*2;Z.push(Math.cos(X),Math.sin(X),1,Math.cos(U),Math.sin(U),1)}$.setAttribute("position",new BJ(Z,3));let W=new j0({fog:!1,toneMapped:!1});this.cone=new X8($,W),this.add(this.cone),this.update()}dispose(){this.cone.geometry.dispose(),this.cone.material.dispose()}update(){if(this.light.updateWorldMatrix(!0,!1),this.light.target.updateWorldMatrix(!0,!1),this.parent)this.parent.updateWorldMatrix(!0),this.matrix.copy(this.parent.matrixWorld).invert().multiply(this.light.matrixWorld);else this.matrix.copy(this.light.matrixWorld);this.matrixWorld.copy(this.light.matrixWorld);let J=this.light.distance?this.light.distance:1000,Q=J*Math.tan(this.light.angle);if(this.cone.scale.set(Q,Q,J),JH.setFromMatrixPosition(this.light.target.matrixWorld),this.cone.lookAt(JH),this.color!==void 0)this.cone.material.color.set(this.color);else this.cone.material.color.copy(this.light.color)}}var g8=new w,c7=new hJ,d$=new hJ;class DX extends X8{constructor(J){let Q=OX(J),$=new nJ,Z=[],W=[];for(let X=0;X<Q.length;X++){let U=Q[X];if(U.parent&&U.parent.isBone)Z.push(0,0,0),Z.push(0,0,0),W.push(0,0,0),W.push(0,0,0)}$.setAttribute("position",new BJ(Z,3)),$.setAttribute("color",new BJ(W,3));let K=new j0({vertexColors:!0,depthTest:!1,depthWrite:!1,toneMapped:!1,transparent:!0});super($,K);this.isSkeletonHelper=!0,this.type="SkeletonHelper",this.root=J,this.bones=Q,this.matrix=J.matrixWorld,this.matrixAutoUpdate=!1;let H=new kJ(255),Y=new kJ(65280);this.setColors(H,Y)}updateMatrixWorld(J){let Q=this.bones,$=this.geometry,Z=$.getAttribute("position");d$.copy(this.root.matrixWorld).invert();for(let W=0,K=0;W<Q.length;W++){let H=Q[W];if(H.parent&&H.parent.isBone)c7.multiplyMatrices(d$,H.matrixWorld),g8.setFromMatrixPosition(c7),Z.setXYZ(K,g8.x,g8.y,g8.z),c7.multiplyMatrices(d$,H.parent.matrixWorld),g8.setFromMatrixPosition(c7),Z.setXYZ(K+1,g8.x,g8.y,g8.z),K+=2}$.getAttribute("position").needsUpdate=!0,super.updateMatrixWorld(J)}setColors(J,Q){let Z=this.geometry.getAttribute("color");for(let W=0;W<Z.count;W+=2)Z.setXYZ(W,J.r,J.g,J.b),Z.setXYZ(W+1,Q.r,Q.g,Q.b);return Z.needsUpdate=!0,this}dispose(){this.geometry.dispose(),this.material.dispose()}}function OX(J){let Q=[];if(J.isBone===!0)Q.push(J);for(let $=0;$<J.children.length;$++)Q.push(...OX(J.children[$]));return Q}class RX extends k0{constructor(J,Q,$){let Z=new $7(Q,4,2),W=new S8({wireframe:!0,fog:!1,toneMapped:!1});super(Z,W);this.light=J,this.color=$,this.type="PointLightHelper",this.matrix=this.light.matrixWorld,this.matrixAutoUpdate=!1,this.update()}dispose(){this.geometry.dispose(),this.material.dispose()}update(){if(this.light.updateWorldMatrix(!0,!1),this.color!==void 0)this.material.color.set(this.color);else this.material.color.copy(this.light.color)}}var GN=new w,QH=new kJ,$H=new kJ;class FX extends Q0{constructor(J,Q,$){super();this.light=J,this.matrix=J.matrixWorld,this.matrixAutoUpdate=!1,this.color=$,this.type="HemisphereLightHelper";let Z=new Q7(Q);if(Z.rotateY(Math.PI*0.5),this.material=new S8({wireframe:!0,fog:!1,toneMapped:!1}),this.color===void 0)this.material.vertexColors=!0;let W=Z.getAttribute("position"),K=new Float32Array(W.count*3);Z.setAttribute("color",new Z0(K,3)),this.add(new k0(Z,this.material)),this.update()}dispose(){this.children[0].geometry.dispose(),this.children[0].material.dispose()}update(){let J=this.children[0];if(this.color!==void 0)this.material.color.set(this.color);else{let Q=J.geometry.getAttribute("color");QH.copy(this.light.color),$H.copy(this.light.groundColor);for(let $=0,Z=Q.count;$<Z;$++){let W=$<Z/2?QH:$H;Q.setXYZ($,W.r,W.g,W.b)}Q.needsUpdate=!0}this.light.updateWorldMatrix(!0,!1),J.lookAt(GN.setFromMatrixPosition(this.light.matrixWorld).negate())}}class MX extends X8{constructor(J=10,Q=10,$=4473924,Z=8947848){$=new kJ($),Z=new kJ(Z);let W=Q/2,K=J/Q,H=J/2,Y=[],X=[];for(let E=0,N=0,q=-H;E<=Q;E++,q+=K){Y.push(-H,0,q,H,0,q),Y.push(q,0,-H,q,0,H);let R=E===W?$:Z;R.toArray(X,N),N+=3,R.toArray(X,N),N+=3,R.toArray(X,N),N+=3,R.toArray(X,N),N+=3}let U=new nJ;U.setAttribute("position",new BJ(Y,3)),U.setAttribute("color",new BJ(X,3));let G=new j0({vertexColors:!0,toneMapped:!1});super(U,G);this.type="GridHelper"}dispose(){this.geometry.dispose(),this.material.dispose()}}class kX extends X8{constructor(J=10,Q=16,$=8,Z=64,W=4473924,K=8947848){W=new kJ(W),K=new kJ(K);let H=[],Y=[];if(Q>1)for(let G=0;G<Q;G++){let E=G/Q*(Math.PI*2),N=Math.sin(E)*J,q=Math.cos(E)*J;H.push(0,0,0),H.push(N,0,q);let R=G&1?W:K;Y.push(R.r,R.g,R.b),Y.push(R.r,R.g,R.b)}for(let G=0;G<$;G++){let E=G&1?W:K,N=J-J/$*G;for(let q=0;q<Z;q++){let R=q/Z*(Math.PI*2),F=Math.sin(R)*N,O=Math.cos(R)*N;H.push(F,0,O),Y.push(E.r,E.g,E.b),R=(q+1)/Z*(Math.PI*2),F=Math.sin(R)*N,O=Math.cos(R)*N,H.push(F,0,O),Y.push(E.r,E.g,E.b)}}let X=new nJ;X.setAttribute("position",new BJ(H,3)),X.setAttribute("color",new BJ(Y,3));let U=new j0({vertexColors:!0,toneMapped:!1});super(X,U);this.type="PolarGridHelper"}dispose(){this.geometry.dispose(),this.material.dispose()}}var ZH=new w,n7=new w,WH=new w;class VX extends Q0{constructor(J,Q,$){super();if(this.light=J,this.matrix=J.matrixWorld,this.matrixAutoUpdate=!1,this.color=$,this.type="DirectionalLightHelper",Q===void 0)Q=1;let Z=new nJ;Z.setAttribute("position",new BJ([-Q,Q,0,Q,Q,0,Q,-Q,0,-Q,-Q,0,-Q,Q,0],3));let W=new j0({fog:!1,toneMapped:!1});this.lightPlane=new A8(Z,W),this.add(this.lightPlane),Z=new nJ,Z.setAttribute("position",new BJ([0,0,0,0,0,1],3)),this.targetLine=new A8(Z,W),this.add(this.targetLine),this.update()}dispose(){this.lightPlane.geometry.dispose(),this.lightPlane.material.dispose(),this.targetLine.geometry.dispose(),this.targetLine.material.dispose()}update(){if(this.light.updateWorldMatrix(!0,!1),this.light.target.updateWorldMatrix(!0,!1),ZH.setFromMatrixPosition(this.light.matrixWorld),n7.setFromMatrixPosition(this.light.target.matrixWorld),WH.subVectors(n7,ZH),this.lightPlane.lookAt(n7),this.color!==void 0)this.lightPlane.material.color.set(this.color),this.targetLine.material.color.set(this.color);else this.lightPlane.material.color.copy(this.light.color),this.targetLine.material.color.copy(this.light.color);this.targetLine.lookAt(n7),this.targetLine.scale.z=WH.length()}}var s7=new w,R0=new i6;class LX extends X8{constructor(J){let Q=new nJ,$=new j0({color:16777215,vertexColors:!0,toneMapped:!1}),Z=[],W=[],K={};H("n1","n2"),H("n2","n4"),H("n4","n3"),H("n3","n1"),H("f1","f2"),H("f2","f4"),H("f4","f3"),H("f3","f1"),H("n1","f1"),H("n2","f2"),H("n3","f3"),H("n4","f4"),H("p","n1"),H("p","n2"),H("p","n3"),H("p","n4"),H("u1","u2"),H("u2","u3"),H("u3","u1"),H("c","t"),H("p","c"),H("cn1","cn2"),H("cn3","cn4"),H("cf1","cf2"),H("cf3","cf4");function H(q,R){Y(q),Y(R)}function Y(q){if(Z.push(0,0,0),W.push(0,0,0),K[q]===void 0)K[q]=[];K[q].push(Z.length/3-1)}Q.setAttribute("position",new BJ(Z,3)),Q.setAttribute("color",new BJ(W,3));super(Q,$);if(this.type="CameraHelper",this.camera=J,this.camera.updateProjectionMatrix)this.camera.updateProjectionMatrix();this.matrix=J.matrixWorld,this.matrixAutoUpdate=!1,this.pointMap=K,this.update();let X=new kJ(16755200),U=new kJ(16711680),G=new kJ(43775),E=new kJ(16777215),N=new kJ(3355443);this.setColors(X,U,G,E,N)}setColors(J,Q,$,Z,W){let H=this.geometry.getAttribute("color");return H.setXYZ(0,J.r,J.g,J.b),H.setXYZ(1,J.r,J.g,J.b),H.setXYZ(2,J.r,J.g,J.b),H.setXYZ(3,J.r,J.g,J.b),H.setXYZ(4,J.r,J.g,J.b),H.setXYZ(5,J.r,J.g,J.b),H.setXYZ(6,J.r,J.g,J.b),H.setXYZ(7,J.r,J.g,J.b),H.setXYZ(8,J.r,J.g,J.b),H.setXYZ(9,J.r,J.g,J.b),H.setXYZ(10,J.r,J.g,J.b),H.setXYZ(11,J.r,J.g,J.b),H.setXYZ(12,J.r,J.g,J.b),H.setXYZ(13,J.r,J.g,J.b),H.setXYZ(14,J.r,J.g,J.b),H.setXYZ(15,J.r,J.g,J.b),H.setXYZ(16,J.r,J.g,J.b),H.setXYZ(17,J.r,J.g,J.b),H.setXYZ(18,J.r,J.g,J.b),H.setXYZ(19,J.r,J.g,J.b),H.setXYZ(20,J.r,J.g,J.b),H.setXYZ(21,J.r,J.g,J.b),H.setXYZ(22,J.r,J.g,J.b),H.setXYZ(23,J.r,J.g,J.b),H.setXYZ(24,Q.r,Q.g,Q.b),H.setXYZ(25,Q.r,Q.g,Q.b),H.setXYZ(26,Q.r,Q.g,Q.b),H.setXYZ(27,Q.r,Q.g,Q.b),H.setXYZ(28,Q.r,Q.g,Q.b),H.setXYZ(29,Q.r,Q.g,Q.b),H.setXYZ(30,Q.r,Q.g,Q.b),H.setXYZ(31,Q.r,Q.g,Q.b),H.setXYZ(32,$.r,$.g,$.b),H.setXYZ(33,$.r,$.g,$.b),H.setXYZ(34,$.r,$.g,$.b),H.setXYZ(35,$.r,$.g,$.b),H.setXYZ(36,$.r,$.g,$.b),H.setXYZ(37,$.r,$.g,$.b),H.setXYZ(38,Z.r,Z.g,Z.b),H.setXYZ(39,Z.r,Z.g,Z.b),H.setXYZ(40,W.r,W.g,W.b),H.setXYZ(41,W.r,W.g,W.b),H.setXYZ(42,W.r,W.g,W.b),H.setXYZ(43,W.r,W.g,W.b),H.setXYZ(44,W.r,W.g,W.b),H.setXYZ(45,W.r,W.g,W.b),H.setXYZ(46,W.r,W.g,W.b),H.setXYZ(47,W.r,W.g,W.b),H.setXYZ(48,W.r,W.g,W.b),H.setXYZ(49,W.r,W.g,W.b),H.needsUpdate=!0,this}update(){let J=this.geometry,Q=this.pointMap,$=1,Z=1,W,K;if(R0.projectionMatrixInverse.copy(this.camera.projectionMatrixInverse),this.camera.reversedDepth===!0)W=1,K=0;else if(this.camera.coordinateSystem===2000)W=-1,K=1;else if(this.camera.coordinateSystem===2001)W=0,K=1;else throw Error("THREE.CameraHelper.update(): Invalid coordinate system: "+this.camera.coordinateSystem);M0("c",Q,J,R0,0,0,W),M0("t",Q,J,R0,0,0,K),M0("n1",Q,J,R0,-1,-1,W),M0("n2",Q,J,R0,1,-1,W),M0("n3",Q,J,R0,-1,1,W),M0("n4",Q,J,R0,1,1,W),M0("f1",Q,J,R0,-1,-1,K),M0("f2",Q,J,R0,1,-1,K),M0("f3",Q,J,R0,-1,1,K),M0("f4",Q,J,R0,1,1,K),M0("u1",Q,J,R0,0.7,1.1,W),M0("u2",Q,J,R0,-0.7,1.1,W),M0("u3",Q,J,R0,0,2,W),M0("cf1",Q,J,R0,-1,0,K),M0("cf2",Q,J,R0,1,0,K),M0("cf3",Q,J,R0,0,-1,K),M0("cf4",Q,J,R0,0,1,K),M0("cn1",Q,J,R0,-1,0,W),M0("cn2",Q,J,R0,1,0,W),M0("cn3",Q,J,R0,0,-1,W),M0("cn4",Q,J,R0,0,1,W),J.getAttribute("position").needsUpdate=!0}dispose(){this.geometry.dispose(),this.material.dispose()}}function M0(J,Q,$,Z,W,K,H){s7.set(W,K,H).unproject(Z);let Y=Q[J];if(Y!==void 0){let X=$.getAttribute("position");for(let U=0,G=Y.length;U<G;U++)X.setXYZ(Y[U],s7.x,s7.y,s7.z)}}var i7=new w0;class zX extends X8{constructor(J,Q=16776960){let $=new Uint16Array([0,1,1,2,2,3,3,0,4,5,5,6,6,7,7,4,0,4,1,5,2,6,3,7]),Z=new Float32Array(24),W=new nJ;W.setIndex(new Z0($,1)),W.setAttribute("position",new Z0(Z,3));super(W,new j0({color:Q,toneMapped:!1}));this.object=J,this.type="BoxHelper",this.matrixAutoUpdate=!1,this.update()}update(){if(this.object!==void 0)i7.setFromObject(this.object);if(i7.isEmpty())return;let{min:J,max:Q}=i7,$=this.geometry.attributes.position,Z=$.array;Z[0]=Q.x,Z[1]=Q.y,Z[2]=Q.z,Z[3]=J.x,Z[4]=Q.y,Z[5]=Q.z,Z[6]=J.x,Z[7]=J.y,Z[8]=Q.z,Z[9]=Q.x,Z[10]=J.y,Z[11]=Q.z,Z[12]=Q.x,Z[13]=Q.y,Z[14]=J.z,Z[15]=J.x,Z[16]=Q.y,Z[17]=J.z,Z[18]=J.x,Z[19]=J.y,Z[20]=J.z,Z[21]=Q.x,Z[22]=J.y,Z[23]=J.z,$.needsUpdate=!0,this.geometry.computeBoundingSphere()}setFromObject(J){return this.object=J,this.update(),this}copy(J,Q){return super.copy(J,Q),this.object=J.object,this}dispose(){this.geometry.dispose(),this.material.dispose()}}class BX extends X8{constructor(J,Q=16776960){let $=new Uint16Array([0,1,1,2,2,3,3,0,4,5,5,6,6,7,7,4,0,4,1,5,2,6,3,7]),Z=[1,1,1,-1,1,1,-1,-1,1,1,-1,1,1,1,-1,-1,1,-1,-1,-1,-1,1,-1,-1],W=new nJ;W.setIndex(new Z0($,1)),W.setAttribute("position",new BJ(Z,3));super(W,new j0({color:Q,toneMapped:!1}));this.box=J,this.type="Box3Helper",this.geometry.computeBoundingSphere()}updateMatrixWorld(J){let Q=this.box;if(Q.isEmpty())return;Q.getCenter(this.position),Q.getSize(this.scale),this.scale.multiplyScalar(0.5),super.updateMatrixWorld(J)}dispose(){this.geometry.dispose(),this.material.dispose()}}class IX extends A8{constructor(J,Q=1,$=16776960){let Z=$,W=[1,-1,0,-1,1,0,-1,-1,0,1,1,0,-1,1,0,-1,-1,0,1,-1,0,1,1,0],K=new nJ;K.setAttribute("position",new BJ(W,3)),K.computeBoundingSphere();super(K,new j0({color:Z,toneMapped:!1}));this.type="PlaneHelper",this.plane=J,this.size=Q;let H=[1,1,0,-1,1,0,-1,-1,0,1,1,0,-1,-1,0,1,-1,0],Y=new nJ;Y.setAttribute("position",new BJ(H,3)),Y.computeBoundingSphere(),this.add(new k0(Y,new S8({color:Z,opacity:0.2,transparent:!0,depthWrite:!1,toneMapped:!1})))}updateMatrixWorld(J){this.position.set(0,0,0),this.scale.set(0.5*this.size,0.5*this.size,1),this.lookAt(this.plane.normal),this.translateZ(-this.plane.constant),super.updateMatrixWorld(J)}dispose(){this.geometry.dispose(),this.material.dispose(),this.children[0].geometry.dispose(),this.children[0].material.dispose()}}var KH=new w,o7,l$;class _X extends Q0{constructor(J=new w(0,0,1),Q=new w(0,0,0),$=1,Z=16776960,W=$*0.2,K=W*0.2){super();if(this.type="ArrowHelper",o7===void 0)o7=new nJ,o7.setAttribute("position",new BJ([0,0,0,0,1,0],3)),l$=new e6(0.5,1,5,1),l$.translate(0,-0.5,0);this.position.copy(Q),this.line=new A8(o7,new j0({color:Z,toneMapped:!1})),this.line.matrixAutoUpdate=!1,this.add(this.line),this.cone=new k0(l$,new S8({color:Z,toneMapped:!1})),this.cone.matrixAutoUpdate=!1,this.add(this.cone),this.setDirection(J),this.setLength($,W,K)}setDirection(J){if(J.y>0.99999)this.quaternion.set(0,0,0,1);else if(J.y<-0.99999)this.quaternion.set(1,0,0,0);else{KH.set(J.z,0,-J.x).normalize();let Q=Math.acos(J.y);this.quaternion.setFromAxisAngle(KH,Q)}}setLength(J,Q=J*0.2,$=Q*0.2){this.line.scale.set(1,Math.max(0.0001,J-Q),1),this.line.updateMatrix(),this.cone.scale.set($,Q,$),this.cone.position.y=J,this.cone.updateMatrix()}setColor(J){this.line.material.color.set(J),this.cone.material.color.set(J)}copy(J){return super.copy(J,!1),this.line.copy(J.line),this.cone.copy(J.cone),this}dispose(){this.line.geometry.dispose(),this.line.material.dispose(),this.cone.geometry.dispose(),this.cone.material.dispose()}}class wX extends X8{constructor(J=1){let Q=[0,0,0,J,0,0,0,0,0,0,J,0,0,0,0,0,0,J],$=[1,0,0,1,0.6,0,0,1,0,0.6,1,0,0,0,1,0,0.6,1],Z=new nJ;Z.setAttribute("position",new BJ(Q,3)),Z.setAttribute("color",new BJ($,3));let W=new j0({vertexColors:!0,toneMapped:!1});super(Z,W);this.type="AxesHelper"}setColors(J,Q,$){let Z=new kJ,W=this.geometry.attributes.color.array;return Z.set(J),Z.toArray(W,0),Z.toArray(W,3),Z.set(Q),Z.toArray(W,6),Z.toArray(W,9),Z.set($),Z.toArray(W,12),Z.toArray(W,15),this.geometry.attributes.color.needsUpdate=!0,this}dispose(){this.geometry.dispose(),this.material.dispose()}}class CX{constructor(){this.type="ShapePath",this.color=new kJ,this.subPaths=[],this.currentPath=null}moveTo(J,Q){return this.currentPath=new y6,this.subPaths.push(this.currentPath),this.currentPath.moveTo(J,Q),this}lineTo(J,Q){return this.currentPath.lineTo(J,Q),this}quadraticCurveTo(J,Q,$,Z){return this.currentPath.quadraticCurveTo(J,Q,$,Z),this}bezierCurveTo(J,Q,$,Z,W,K){return this.currentPath.bezierCurveTo(J,Q,$,Z,W,K),this}splineThru(J){return this.currentPath.splineThru(J),this}toShapes(J){function Q(O){let D=[];for(let k=0,M=O.length;k<M;k++){let L=O[k],A=new p8;A.curves=L.curves,D.push(A)}return D}function $(O,D){let k=D.length,M=!1;for(let L=k-1,A=0;A<k;L=A++){let _=D[L],C=D[A],y=C.x-_.x,z=C.y-_.y;if(Math.abs(z)>Number.EPSILON){if(z<0)_=D[A],y=-y,C=D[L],z=-z;if(O.y<_.y||O.y>C.y)continue;if(O.y===_.y){if(O.x===_.x)return!0}else{let I=z*(O.x-_.x)-y*(O.y-_.y);if(I===0)return!0;if(I<0)continue;M=!M}}else{if(O.y!==_.y)continue;if(C.x<=O.x&&O.x<=_.x||_.x<=O.x&&O.x<=C.x)return!0}}return M}let Z=W8.isClockWise,W=this.subPaths;if(W.length===0)return[];let K,H,Y,X=[];if(W.length===1)return H=W[0],Y=new p8,Y.curves=H.curves,X.push(Y),X;let U=!Z(W[0].getPoints());U=J?!U:U;let G=[],E=[],N=[],q=0,R;E[q]=void 0,N[q]=[];for(let O=0,D=W.length;O<D;O++)if(H=W[O],R=H.getPoints(),K=Z(R),K=J?!K:K,K){if(!U&&E[q])q++;if(E[q]={s:new p8,p:R},E[q].s.curves=H.curves,U)q++;N[q]=[]}else N[q].push({h:H,p:R[0]});if(!E[0])return Q(W);if(E.length>1){let O=!1,D=0;for(let k=0,M=E.length;k<M;k++)G[k]=[];for(let k=0,M=E.length;k<M;k++){let L=N[k];for(let A=0;A<L.length;A++){let _=L[A],C=!0;for(let y=0;y<E.length;y++)if($(_.p,E[y].p)){if(k!==y)D++;if(C)C=!1,G[y].push(_);else O=!0}if(C)G[k].push(_)}}if(D>0&&O===!1)N=G}let F;for(let O=0,D=E.length;O<D;O++){Y=E[O].s,X.push(Y),F=N[O];for(let k=0,M=F.length;k<M;k++)Y.holes.push(F[k].h)}return X}}class PX extends H8{constructor(J,Q=null){super();this.object=J,this.domElement=Q,this.enabled=!0,this.state=-1,this.keys={},this.mouseButtons={LEFT:null,MIDDLE:null,RIGHT:null},this.touches={ONE:null,TWO:null}}connect(J){if(J===void 0){console.warn("THREE.Controls: connect() now requires an element.");return}if(this.domElement!==null)this.disconnect();this.domElement=J}disconnect(){}dispose(){}update(){}}function EN(J,Q){let $=J.image&&J.image.width?J.image.width/J.image.height:1;if($>Q)J.repeat.x=1,J.repeat.y=$/Q,J.offset.x=0,J.offset.y=(1-J.repeat.y)/2;else J.repeat.x=Q/$,J.repeat.y=1,J.offset.x=(1-J.repeat.x)/2,J.offset.y=0;return J}function NN(J,Q){let $=J.image&&J.image.width?J.image.width/J.image.height:1;if($>Q)J.repeat.x=Q/$,J.repeat.y=1,J.offset.x=(1-J.repeat.x)/2,J.offset.y=0;else J.repeat.x=1,J.repeat.y=$/Q,J.offset.x=0,J.offset.y=(1-J.repeat.y)/2;return J}function qN(J){return J.repeat.x=1,J.repeat.y=1,J.offset.x=0,J.offset.y=0,J}function eQ(J,Q,$,Z){let W=DN(Z);switch($){case 1021:return J*Q;case 1028:return J*Q/W.components*W.byteLength;case 1029:return J*Q/W.components*W.byteLength;case 1030:return J*Q*2/W.components*W.byteLength;case 1031:return J*Q*2/W.components*W.byteLength;case 1022:return J*Q*3/W.components*W.byteLength;case 1023:return J*Q*4/W.components*W.byteLength;case 1033:return J*Q*4/W.components*W.byteLength;case 33776:case 33777:return Math.floor((J+3)/4)*Math.floor((Q+3)/4)*8;case 33778:case 33779:return Math.floor((J+3)/4)*Math.floor((Q+3)/4)*16;case 35841:case 35843:return Math.max(J,16)*Math.max(Q,8)/4;case 35840:case 35842:return Math.max(J,8)*Math.max(Q,8)/2;case 36196:case 37492:return Math.floor((J+3)/4)*Math.floor((Q+3)/4)*8;case 37496:return Math.floor((J+3)/4)*Math.floor((Q+3)/4)*16;case 37808:return Math.floor((J+3)/4)*Math.floor((Q+3)/4)*16;case 37809:return Math.floor((J+4)/5)*Math.floor((Q+3)/4)*16;case 37810:return Math.floor((J+4)/5)*Math.floor((Q+4)/5)*16;case 37811:return Math.floor((J+5)/6)*Math.floor((Q+4)/5)*16;case 37812:return Math.floor((J+5)/6)*Math.floor((Q+5)/6)*16;case 37813:return Math.floor((J+7)/8)*Math.floor((Q+4)/5)*16;case 37814:return Math.floor((J+7)/8)*Math.floor((Q+5)/6)*16;case 37815:return Math.floor((J+7)/8)*Math.floor((Q+7)/8)*16;case 37816:return Math.floor((J+9)/10)*Math.floor((Q+4)/5)*16;case 37817:return Math.floor((J+9)/10)*Math.floor((Q+5)/6)*16;case 37818:return Math.floor((J+9)/10)*Math.floor((Q+7)/8)*16;case 37819:return Math.floor((J+9)/10)*Math.floor((Q+9)/10)*16;case 37820:return Math.floor((J+11)/12)*Math.floor((Q+9)/10)*16;case 37821:return Math.floor((J+11)/12)*Math.floor((Q+11)/12)*16;case 36492:case 36494:case 36495:return Math.ceil(J/4)*Math.ceil(Q/4)*16;case 36283:case 36284:return Math.ceil(J/4)*Math.ceil(Q/4)*8;case 36285:case 36286:return Math.ceil(J/4)*Math.ceil(Q/4)*16}throw Error(`Unable to determine texture byte length for ${$} format.`)}function DN(J){switch(J){case 1009:case 1010:return{byteLength:1,components:1};case 1012:case 1011:case 1016:return{byteLength:2,components:1};case 1017:case 1018:return{byteLength:2,components:4};case 1014:case 1013:case 1015:return{byteLength:4,components:1};case 35902:case 35899:return{byteLength:4,components:3}}throw Error(`Unknown texture type ${J}.`)}class AX{static contain(J,Q){return EN(J,Q)}static cover(J,Q){return NN(J,Q)}static fill(J){return qN(J)}static getByteLength(J,Q,$,Z){return eQ(J,Q,$,Z)}}if(typeof __THREE_DEVTOOLS__<"u")__THREE_DEVTOOLS__.dispatchEvent(new CustomEvent("register",{detail:{revision:"180"}}));if(typeof window<"u")if(window.__THREE__)console.warn("WARNING: Multiple instances of Three.js being imported.");else window.__THREE__="180";function eX(){let J=null,Q=!1,$=null,Z=null;function W(K,H){$(K,H),Z=J.requestAnimationFrame(W)}return{start:function(){if(Q===!0)return;if($===null)return;Z=J.requestAnimationFrame(W),Q=!0},stop:function(){J.cancelAnimationFrame(Z),Q=!1},setAnimationLoop:function(K){$=K},setContext:function(K){J=K}}}function ON(J){let Q=new WeakMap;function $(Y,X){let{array:U,usage:G}=Y,E=U.byteLength,N=J.createBuffer();J.bindBuffer(X,N),J.bufferData(X,U,G),Y.onUploadCallback();let q;if(U instanceof Float32Array)q=J.FLOAT;else if(typeof Float16Array<"u"&&U instanceof Float16Array)q=J.HALF_FLOAT;else if(U instanceof Uint16Array)if(Y.isFloat16BufferAttribute)q=J.HALF_FLOAT;else q=J.UNSIGNED_SHORT;else if(U instanceof Int16Array)q=J.SHORT;else if(U instanceof Uint32Array)q=J.UNSIGNED_INT;else if(U instanceof Int32Array)q=J.INT;else if(U instanceof Int8Array)q=J.BYTE;else if(U instanceof Uint8Array)q=J.UNSIGNED_BYTE;else if(U instanceof Uint8ClampedArray)q=J.UNSIGNED_BYTE;else throw Error("THREE.WebGLAttributes: Unsupported buffer data format: "+U);return{buffer:N,type:q,bytesPerElement:U.BYTES_PER_ELEMENT,version:Y.version,size:E}}function Z(Y,X,U){let{array:G,updateRanges:E}=X;if(J.bindBuffer(U,Y),E.length===0)J.bufferSubData(U,0,G);else{E.sort((q,R)=>q.start-R.start);let N=0;for(let q=1;q<E.length;q++){let R=E[N],F=E[q];if(F.start<=R.start+R.count+1)R.count=Math.max(R.count,F.start+F.count-R.start);else++N,E[N]=F}E.length=N+1;for(let q=0,R=E.length;q<R;q++){let F=E[q];J.bufferSubData(U,F.start*G.BYTES_PER_ELEMENT,G,F.start,F.count)}X.clearUpdateRanges()}X.onUploadCallback()}function W(Y){if(Y.isInterleavedBufferAttribute)Y=Y.data;return Q.get(Y)}function K(Y){if(Y.isInterleavedBufferAttribute)Y=Y.data;let X=Q.get(Y);if(X)J.deleteBuffer(X.buffer),Q.delete(Y)}function H(Y,X){if(Y.isInterleavedBufferAttribute)Y=Y.data;if(Y.isGLBufferAttribute){let G=Q.get(Y);if(!G||G.version<Y.version)Q.set(Y,{buffer:Y.buffer,type:Y.type,bytesPerElement:Y.elementSize,version:Y.version});return}let U=Q.get(Y);if(U===void 0)Q.set(Y,$(Y,X));else if(U.version<Y.version){if(U.size!==Y.array.byteLength)throw Error("THREE.WebGLAttributes: The size of the buffer attribute's array buffer does not match the original size. Resizing buffer attributes is not supported.");Z(U.buffer,Y,X),U.version=Y.version}}return{get:W,remove:K,update:H}}var RN=`#ifdef USE_ALPHAHASH
	if ( diffuseColor.a < getAlphaHashThreshold( vPosition ) ) discard;
#endif`,FN=`#ifdef USE_ALPHAHASH
	const float ALPHA_HASH_SCALE = 0.05;
	float hash2D( vec2 value ) {
		return fract( 1.0e4 * sin( 17.0 * value.x + 0.1 * value.y ) * ( 0.1 + abs( sin( 13.0 * value.y + value.x ) ) ) );
	}
	float hash3D( vec3 value ) {
		return hash2D( vec2( hash2D( value.xy ), value.z ) );
	}
	float getAlphaHashThreshold( vec3 position ) {
		float maxDeriv = max(
			length( dFdx( position.xyz ) ),
			length( dFdy( position.xyz ) )
		);
		float pixScale = 1.0 / ( ALPHA_HASH_SCALE * maxDeriv );
		vec2 pixScales = vec2(
			exp2( floor( log2( pixScale ) ) ),
			exp2( ceil( log2( pixScale ) ) )
		);
		vec2 alpha = vec2(
			hash3D( floor( pixScales.x * position.xyz ) ),
			hash3D( floor( pixScales.y * position.xyz ) )
		);
		float lerpFactor = fract( log2( pixScale ) );
		float x = ( 1.0 - lerpFactor ) * alpha.x + lerpFactor * alpha.y;
		float a = min( lerpFactor, 1.0 - lerpFactor );
		vec3 cases = vec3(
			x * x / ( 2.0 * a * ( 1.0 - a ) ),
			( x - 0.5 * a ) / ( 1.0 - a ),
			1.0 - ( ( 1.0 - x ) * ( 1.0 - x ) / ( 2.0 * a * ( 1.0 - a ) ) )
		);
		float threshold = ( x < ( 1.0 - a ) )
			? ( ( x < a ) ? cases.x : cases.y )
			: cases.z;
		return clamp( threshold , 1.0e-6, 1.0 );
	}
#endif`,MN=`#ifdef USE_ALPHAMAP
	diffuseColor.a *= texture2D( alphaMap, vAlphaMapUv ).g;
#endif`,kN=`#ifdef USE_ALPHAMAP
	uniform sampler2D alphaMap;
#endif`,VN=`#ifdef USE_ALPHATEST
	#ifdef ALPHA_TO_COVERAGE
	diffuseColor.a = smoothstep( alphaTest, alphaTest + fwidth( diffuseColor.a ), diffuseColor.a );
	if ( diffuseColor.a == 0.0 ) discard;
	#else
	if ( diffuseColor.a < alphaTest ) discard;
	#endif
#endif`,LN=`#ifdef USE_ALPHATEST
	uniform float alphaTest;
#endif`,zN=`#ifdef USE_AOMAP
	float ambientOcclusion = ( texture2D( aoMap, vAoMapUv ).r - 1.0 ) * aoMapIntensity + 1.0;
	reflectedLight.indirectDiffuse *= ambientOcclusion;
	#if defined( USE_CLEARCOAT ) 
		clearcoatSpecularIndirect *= ambientOcclusion;
	#endif
	#if defined( USE_SHEEN ) 
		sheenSpecularIndirect *= ambientOcclusion;
	#endif
	#if defined( USE_ENVMAP ) && defined( STANDARD )
		float dotNV = saturate( dot( geometryNormal, geometryViewDir ) );
		reflectedLight.indirectSpecular *= computeSpecularOcclusion( dotNV, ambientOcclusion, material.roughness );
	#endif
#endif`,BN=`#ifdef USE_AOMAP
	uniform sampler2D aoMap;
	uniform float aoMapIntensity;
#endif`,IN=`#ifdef USE_BATCHING
	#if ! defined( GL_ANGLE_multi_draw )
	#define gl_DrawID _gl_DrawID
	uniform int _gl_DrawID;
	#endif
	uniform highp sampler2D batchingTexture;
	uniform highp usampler2D batchingIdTexture;
	mat4 getBatchingMatrix( const in float i ) {
		int size = textureSize( batchingTexture, 0 ).x;
		int j = int( i ) * 4;
		int x = j % size;
		int y = j / size;
		vec4 v1 = texelFetch( batchingTexture, ivec2( x, y ), 0 );
		vec4 v2 = texelFetch( batchingTexture, ivec2( x + 1, y ), 0 );
		vec4 v3 = texelFetch( batchingTexture, ivec2( x + 2, y ), 0 );
		vec4 v4 = texelFetch( batchingTexture, ivec2( x + 3, y ), 0 );
		return mat4( v1, v2, v3, v4 );
	}
	float getIndirectIndex( const in int i ) {
		int size = textureSize( batchingIdTexture, 0 ).x;
		int x = i % size;
		int y = i / size;
		return float( texelFetch( batchingIdTexture, ivec2( x, y ), 0 ).r );
	}
#endif
#ifdef USE_BATCHING_COLOR
	uniform sampler2D batchingColorTexture;
	vec3 getBatchingColor( const in float i ) {
		int size = textureSize( batchingColorTexture, 0 ).x;
		int j = int( i );
		int x = j % size;
		int y = j / size;
		return texelFetch( batchingColorTexture, ivec2( x, y ), 0 ).rgb;
	}
#endif`,_N=`#ifdef USE_BATCHING
	mat4 batchingMatrix = getBatchingMatrix( getIndirectIndex( gl_DrawID ) );
#endif`,wN=`vec3 transformed = vec3( position );
#ifdef USE_ALPHAHASH
	vPosition = vec3( position );
#endif`,CN=`vec3 objectNormal = vec3( normal );
#ifdef USE_TANGENT
	vec3 objectTangent = vec3( tangent.xyz );
#endif`,PN=`float G_BlinnPhong_Implicit( ) {
	return 0.25;
}
float D_BlinnPhong( const in float shininess, const in float dotNH ) {
	return RECIPROCAL_PI * ( shininess * 0.5 + 1.0 ) * pow( dotNH, shininess );
}
vec3 BRDF_BlinnPhong( const in vec3 lightDir, const in vec3 viewDir, const in vec3 normal, const in vec3 specularColor, const in float shininess ) {
	vec3 halfDir = normalize( lightDir + viewDir );
	float dotNH = saturate( dot( normal, halfDir ) );
	float dotVH = saturate( dot( viewDir, halfDir ) );
	vec3 F = F_Schlick( specularColor, 1.0, dotVH );
	float G = G_BlinnPhong_Implicit( );
	float D = D_BlinnPhong( shininess, dotNH );
	return F * ( G * D );
} // validated`,AN=`#ifdef USE_IRIDESCENCE
	const mat3 XYZ_TO_REC709 = mat3(
		 3.2404542, -0.9692660,  0.0556434,
		-1.5371385,  1.8760108, -0.2040259,
		-0.4985314,  0.0415560,  1.0572252
	);
	vec3 Fresnel0ToIor( vec3 fresnel0 ) {
		vec3 sqrtF0 = sqrt( fresnel0 );
		return ( vec3( 1.0 ) + sqrtF0 ) / ( vec3( 1.0 ) - sqrtF0 );
	}
	vec3 IorToFresnel0( vec3 transmittedIor, float incidentIor ) {
		return pow2( ( transmittedIor - vec3( incidentIor ) ) / ( transmittedIor + vec3( incidentIor ) ) );
	}
	float IorToFresnel0( float transmittedIor, float incidentIor ) {
		return pow2( ( transmittedIor - incidentIor ) / ( transmittedIor + incidentIor ));
	}
	vec3 evalSensitivity( float OPD, vec3 shift ) {
		float phase = 2.0 * PI * OPD * 1.0e-9;
		vec3 val = vec3( 5.4856e-13, 4.4201e-13, 5.2481e-13 );
		vec3 pos = vec3( 1.6810e+06, 1.7953e+06, 2.2084e+06 );
		vec3 var = vec3( 4.3278e+09, 9.3046e+09, 6.6121e+09 );
		vec3 xyz = val * sqrt( 2.0 * PI * var ) * cos( pos * phase + shift ) * exp( - pow2( phase ) * var );
		xyz.x += 9.7470e-14 * sqrt( 2.0 * PI * 4.5282e+09 ) * cos( 2.2399e+06 * phase + shift[ 0 ] ) * exp( - 4.5282e+09 * pow2( phase ) );
		xyz /= 1.0685e-7;
		vec3 rgb = XYZ_TO_REC709 * xyz;
		return rgb;
	}
	vec3 evalIridescence( float outsideIOR, float eta2, float cosTheta1, float thinFilmThickness, vec3 baseF0 ) {
		vec3 I;
		float iridescenceIOR = mix( outsideIOR, eta2, smoothstep( 0.0, 0.03, thinFilmThickness ) );
		float sinTheta2Sq = pow2( outsideIOR / iridescenceIOR ) * ( 1.0 - pow2( cosTheta1 ) );
		float cosTheta2Sq = 1.0 - sinTheta2Sq;
		if ( cosTheta2Sq < 0.0 ) {
			return vec3( 1.0 );
		}
		float cosTheta2 = sqrt( cosTheta2Sq );
		float R0 = IorToFresnel0( iridescenceIOR, outsideIOR );
		float R12 = F_Schlick( R0, 1.0, cosTheta1 );
		float T121 = 1.0 - R12;
		float phi12 = 0.0;
		if ( iridescenceIOR < outsideIOR ) phi12 = PI;
		float phi21 = PI - phi12;
		vec3 baseIOR = Fresnel0ToIor( clamp( baseF0, 0.0, 0.9999 ) );		vec3 R1 = IorToFresnel0( baseIOR, iridescenceIOR );
		vec3 R23 = F_Schlick( R1, 1.0, cosTheta2 );
		vec3 phi23 = vec3( 0.0 );
		if ( baseIOR[ 0 ] < iridescenceIOR ) phi23[ 0 ] = PI;
		if ( baseIOR[ 1 ] < iridescenceIOR ) phi23[ 1 ] = PI;
		if ( baseIOR[ 2 ] < iridescenceIOR ) phi23[ 2 ] = PI;
		float OPD = 2.0 * iridescenceIOR * thinFilmThickness * cosTheta2;
		vec3 phi = vec3( phi21 ) + phi23;
		vec3 R123 = clamp( R12 * R23, 1e-5, 0.9999 );
		vec3 r123 = sqrt( R123 );
		vec3 Rs = pow2( T121 ) * R23 / ( vec3( 1.0 ) - R123 );
		vec3 C0 = R12 + Rs;
		I = C0;
		vec3 Cm = Rs - T121;
		for ( int m = 1; m <= 2; ++ m ) {
			Cm *= r123;
			vec3 Sm = 2.0 * evalSensitivity( float( m ) * OPD, float( m ) * phi );
			I += Cm * Sm;
		}
		return max( I, vec3( 0.0 ) );
	}
#endif`,TN=`#ifdef USE_BUMPMAP
	uniform sampler2D bumpMap;
	uniform float bumpScale;
	vec2 dHdxy_fwd() {
		vec2 dSTdx = dFdx( vBumpMapUv );
		vec2 dSTdy = dFdy( vBumpMapUv );
		float Hll = bumpScale * texture2D( bumpMap, vBumpMapUv ).x;
		float dBx = bumpScale * texture2D( bumpMap, vBumpMapUv + dSTdx ).x - Hll;
		float dBy = bumpScale * texture2D( bumpMap, vBumpMapUv + dSTdy ).x - Hll;
		return vec2( dBx, dBy );
	}
	vec3 perturbNormalArb( vec3 surf_pos, vec3 surf_norm, vec2 dHdxy, float faceDirection ) {
		vec3 vSigmaX = normalize( dFdx( surf_pos.xyz ) );
		vec3 vSigmaY = normalize( dFdy( surf_pos.xyz ) );
		vec3 vN = surf_norm;
		vec3 R1 = cross( vSigmaY, vN );
		vec3 R2 = cross( vN, vSigmaX );
		float fDet = dot( vSigmaX, R1 ) * faceDirection;
		vec3 vGrad = sign( fDet ) * ( dHdxy.x * R1 + dHdxy.y * R2 );
		return normalize( abs( fDet ) * surf_norm - vGrad );
	}
#endif`,SN=`#if NUM_CLIPPING_PLANES > 0
	vec4 plane;
	#ifdef ALPHA_TO_COVERAGE
		float distanceToPlane, distanceGradient;
		float clipOpacity = 1.0;
		#pragma unroll_loop_start
		for ( int i = 0; i < UNION_CLIPPING_PLANES; i ++ ) {
			plane = clippingPlanes[ i ];
			distanceToPlane = - dot( vClipPosition, plane.xyz ) + plane.w;
			distanceGradient = fwidth( distanceToPlane ) / 2.0;
			clipOpacity *= smoothstep( - distanceGradient, distanceGradient, distanceToPlane );
			if ( clipOpacity == 0.0 ) discard;
		}
		#pragma unroll_loop_end
		#if UNION_CLIPPING_PLANES < NUM_CLIPPING_PLANES
			float unionClipOpacity = 1.0;
			#pragma unroll_loop_start
			for ( int i = UNION_CLIPPING_PLANES; i < NUM_CLIPPING_PLANES; i ++ ) {
				plane = clippingPlanes[ i ];
				distanceToPlane = - dot( vClipPosition, plane.xyz ) + plane.w;
				distanceGradient = fwidth( distanceToPlane ) / 2.0;
				unionClipOpacity *= 1.0 - smoothstep( - distanceGradient, distanceGradient, distanceToPlane );
			}
			#pragma unroll_loop_end
			clipOpacity *= 1.0 - unionClipOpacity;
		#endif
		diffuseColor.a *= clipOpacity;
		if ( diffuseColor.a == 0.0 ) discard;
	#else
		#pragma unroll_loop_start
		for ( int i = 0; i < UNION_CLIPPING_PLANES; i ++ ) {
			plane = clippingPlanes[ i ];
			if ( dot( vClipPosition, plane.xyz ) > plane.w ) discard;
		}
		#pragma unroll_loop_end
		#if UNION_CLIPPING_PLANES < NUM_CLIPPING_PLANES
			bool clipped = true;
			#pragma unroll_loop_start
			for ( int i = UNION_CLIPPING_PLANES; i < NUM_CLIPPING_PLANES; i ++ ) {
				plane = clippingPlanes[ i ];
				clipped = ( dot( vClipPosition, plane.xyz ) > plane.w ) && clipped;
			}
			#pragma unroll_loop_end
			if ( clipped ) discard;
		#endif
	#endif
#endif`,jN=`#if NUM_CLIPPING_PLANES > 0
	varying vec3 vClipPosition;
	uniform vec4 clippingPlanes[ NUM_CLIPPING_PLANES ];
#endif`,yN=`#if NUM_CLIPPING_PLANES > 0
	varying vec3 vClipPosition;
#endif`,vN=`#if NUM_CLIPPING_PLANES > 0
	vClipPosition = - mvPosition.xyz;
#endif`,fN=`#if defined( USE_COLOR_ALPHA )
	diffuseColor *= vColor;
#elif defined( USE_COLOR )
	diffuseColor.rgb *= vColor;
#endif`,bN=`#if defined( USE_COLOR_ALPHA )
	varying vec4 vColor;
#elif defined( USE_COLOR )
	varying vec3 vColor;
#endif`,hN=`#if defined( USE_COLOR_ALPHA )
	varying vec4 vColor;
#elif defined( USE_COLOR ) || defined( USE_INSTANCING_COLOR ) || defined( USE_BATCHING_COLOR )
	varying vec3 vColor;
#endif`,xN=`#if defined( USE_COLOR_ALPHA )
	vColor = vec4( 1.0 );
#elif defined( USE_COLOR ) || defined( USE_INSTANCING_COLOR ) || defined( USE_BATCHING_COLOR )
	vColor = vec3( 1.0 );
#endif
#ifdef USE_COLOR
	vColor *= color;
#endif
#ifdef USE_INSTANCING_COLOR
	vColor.xyz *= instanceColor.xyz;
#endif
#ifdef USE_BATCHING_COLOR
	vec3 batchingColor = getBatchingColor( getIndirectIndex( gl_DrawID ) );
	vColor.xyz *= batchingColor.xyz;
#endif`,gN=`#define PI 3.141592653589793
#define PI2 6.283185307179586
#define PI_HALF 1.5707963267948966
#define RECIPROCAL_PI 0.3183098861837907
#define RECIPROCAL_PI2 0.15915494309189535
#define EPSILON 1e-6
#ifndef saturate
#define saturate( a ) clamp( a, 0.0, 1.0 )
#endif
#define whiteComplement( a ) ( 1.0 - saturate( a ) )
float pow2( const in float x ) { return x*x; }
vec3 pow2( const in vec3 x ) { return x*x; }
float pow3( const in float x ) { return x*x*x; }
float pow4( const in float x ) { float x2 = x*x; return x2*x2; }
float max3( const in vec3 v ) { return max( max( v.x, v.y ), v.z ); }
float average( const in vec3 v ) { return dot( v, vec3( 0.3333333 ) ); }
highp float rand( const in vec2 uv ) {
	const highp float a = 12.9898, b = 78.233, c = 43758.5453;
	highp float dt = dot( uv.xy, vec2( a,b ) ), sn = mod( dt, PI );
	return fract( sin( sn ) * c );
}
#ifdef HIGH_PRECISION
	float precisionSafeLength( vec3 v ) { return length( v ); }
#else
	float precisionSafeLength( vec3 v ) {
		float maxComponent = max3( abs( v ) );
		return length( v / maxComponent ) * maxComponent;
	}
#endif
struct IncidentLight {
	vec3 color;
	vec3 direction;
	bool visible;
};
struct ReflectedLight {
	vec3 directDiffuse;
	vec3 directSpecular;
	vec3 indirectDiffuse;
	vec3 indirectSpecular;
};
#ifdef USE_ALPHAHASH
	varying vec3 vPosition;
#endif
vec3 transformDirection( in vec3 dir, in mat4 matrix ) {
	return normalize( ( matrix * vec4( dir, 0.0 ) ).xyz );
}
vec3 inverseTransformDirection( in vec3 dir, in mat4 matrix ) {
	return normalize( ( vec4( dir, 0.0 ) * matrix ).xyz );
}
mat3 transposeMat3( const in mat3 m ) {
	mat3 tmp;
	tmp[ 0 ] = vec3( m[ 0 ].x, m[ 1 ].x, m[ 2 ].x );
	tmp[ 1 ] = vec3( m[ 0 ].y, m[ 1 ].y, m[ 2 ].y );
	tmp[ 2 ] = vec3( m[ 0 ].z, m[ 1 ].z, m[ 2 ].z );
	return tmp;
}
bool isPerspectiveMatrix( mat4 m ) {
	return m[ 2 ][ 3 ] == - 1.0;
}
vec2 equirectUv( in vec3 dir ) {
	float u = atan( dir.z, dir.x ) * RECIPROCAL_PI2 + 0.5;
	float v = asin( clamp( dir.y, - 1.0, 1.0 ) ) * RECIPROCAL_PI + 0.5;
	return vec2( u, v );
}
vec3 BRDF_Lambert( const in vec3 diffuseColor ) {
	return RECIPROCAL_PI * diffuseColor;
}
vec3 F_Schlick( const in vec3 f0, const in float f90, const in float dotVH ) {
	float fresnel = exp2( ( - 5.55473 * dotVH - 6.98316 ) * dotVH );
	return f0 * ( 1.0 - fresnel ) + ( f90 * fresnel );
}
float F_Schlick( const in float f0, const in float f90, const in float dotVH ) {
	float fresnel = exp2( ( - 5.55473 * dotVH - 6.98316 ) * dotVH );
	return f0 * ( 1.0 - fresnel ) + ( f90 * fresnel );
} // validated`,pN=`#ifdef ENVMAP_TYPE_CUBE_UV
	#define cubeUV_minMipLevel 4.0
	#define cubeUV_minTileSize 16.0
	float getFace( vec3 direction ) {
		vec3 absDirection = abs( direction );
		float face = - 1.0;
		if ( absDirection.x > absDirection.z ) {
			if ( absDirection.x > absDirection.y )
				face = direction.x > 0.0 ? 0.0 : 3.0;
			else
				face = direction.y > 0.0 ? 1.0 : 4.0;
		} else {
			if ( absDirection.z > absDirection.y )
				face = direction.z > 0.0 ? 2.0 : 5.0;
			else
				face = direction.y > 0.0 ? 1.0 : 4.0;
		}
		return face;
	}
	vec2 getUV( vec3 direction, float face ) {
		vec2 uv;
		if ( face == 0.0 ) {
			uv = vec2( direction.z, direction.y ) / abs( direction.x );
		} else if ( face == 1.0 ) {
			uv = vec2( - direction.x, - direction.z ) / abs( direction.y );
		} else if ( face == 2.0 ) {
			uv = vec2( - direction.x, direction.y ) / abs( direction.z );
		} else if ( face == 3.0 ) {
			uv = vec2( - direction.z, direction.y ) / abs( direction.x );
		} else if ( face == 4.0 ) {
			uv = vec2( - direction.x, direction.z ) / abs( direction.y );
		} else {
			uv = vec2( direction.x, direction.y ) / abs( direction.z );
		}
		return 0.5 * ( uv + 1.0 );
	}
	vec3 bilinearCubeUV( sampler2D envMap, vec3 direction, float mipInt ) {
		float face = getFace( direction );
		float filterInt = max( cubeUV_minMipLevel - mipInt, 0.0 );
		mipInt = max( mipInt, cubeUV_minMipLevel );
		float faceSize = exp2( mipInt );
		highp vec2 uv = getUV( direction, face ) * ( faceSize - 2.0 ) + 1.0;
		if ( face > 2.0 ) {
			uv.y += faceSize;
			face -= 3.0;
		}
		uv.x += face * faceSize;
		uv.x += filterInt * 3.0 * cubeUV_minTileSize;
		uv.y += 4.0 * ( exp2( CUBEUV_MAX_MIP ) - faceSize );
		uv.x *= CUBEUV_TEXEL_WIDTH;
		uv.y *= CUBEUV_TEXEL_HEIGHT;
		#ifdef texture2DGradEXT
			return texture2DGradEXT( envMap, uv, vec2( 0.0 ), vec2( 0.0 ) ).rgb;
		#else
			return texture2D( envMap, uv ).rgb;
		#endif
	}
	#define cubeUV_r0 1.0
	#define cubeUV_m0 - 2.0
	#define cubeUV_r1 0.8
	#define cubeUV_m1 - 1.0
	#define cubeUV_r4 0.4
	#define cubeUV_m4 2.0
	#define cubeUV_r5 0.305
	#define cubeUV_m5 3.0
	#define cubeUV_r6 0.21
	#define cubeUV_m6 4.0
	float roughnessToMip( float roughness ) {
		float mip = 0.0;
		if ( roughness >= cubeUV_r1 ) {
			mip = ( cubeUV_r0 - roughness ) * ( cubeUV_m1 - cubeUV_m0 ) / ( cubeUV_r0 - cubeUV_r1 ) + cubeUV_m0;
		} else if ( roughness >= cubeUV_r4 ) {
			mip = ( cubeUV_r1 - roughness ) * ( cubeUV_m4 - cubeUV_m1 ) / ( cubeUV_r1 - cubeUV_r4 ) + cubeUV_m1;
		} else if ( roughness >= cubeUV_r5 ) {
			mip = ( cubeUV_r4 - roughness ) * ( cubeUV_m5 - cubeUV_m4 ) / ( cubeUV_r4 - cubeUV_r5 ) + cubeUV_m4;
		} else if ( roughness >= cubeUV_r6 ) {
			mip = ( cubeUV_r5 - roughness ) * ( cubeUV_m6 - cubeUV_m5 ) / ( cubeUV_r5 - cubeUV_r6 ) + cubeUV_m5;
		} else {
			mip = - 2.0 * log2( 1.16 * roughness );		}
		return mip;
	}
	vec4 textureCubeUV( sampler2D envMap, vec3 sampleDir, float roughness ) {
		float mip = clamp( roughnessToMip( roughness ), cubeUV_m0, CUBEUV_MAX_MIP );
		float mipF = fract( mip );
		float mipInt = floor( mip );
		vec3 color0 = bilinearCubeUV( envMap, sampleDir, mipInt );
		if ( mipF == 0.0 ) {
			return vec4( color0, 1.0 );
		} else {
			vec3 color1 = bilinearCubeUV( envMap, sampleDir, mipInt + 1.0 );
			return vec4( mix( color0, color1, mipF ), 1.0 );
		}
	}
#endif`,mN=`vec3 transformedNormal = objectNormal;
#ifdef USE_TANGENT
	vec3 transformedTangent = objectTangent;
#endif
#ifdef USE_BATCHING
	mat3 bm = mat3( batchingMatrix );
	transformedNormal /= vec3( dot( bm[ 0 ], bm[ 0 ] ), dot( bm[ 1 ], bm[ 1 ] ), dot( bm[ 2 ], bm[ 2 ] ) );
	transformedNormal = bm * transformedNormal;
	#ifdef USE_TANGENT
		transformedTangent = bm * transformedTangent;
	#endif
#endif
#ifdef USE_INSTANCING
	mat3 im = mat3( instanceMatrix );
	transformedNormal /= vec3( dot( im[ 0 ], im[ 0 ] ), dot( im[ 1 ], im[ 1 ] ), dot( im[ 2 ], im[ 2 ] ) );
	transformedNormal = im * transformedNormal;
	#ifdef USE_TANGENT
		transformedTangent = im * transformedTangent;
	#endif
#endif
transformedNormal = normalMatrix * transformedNormal;
#ifdef FLIP_SIDED
	transformedNormal = - transformedNormal;
#endif
#ifdef USE_TANGENT
	transformedTangent = ( modelViewMatrix * vec4( transformedTangent, 0.0 ) ).xyz;
	#ifdef FLIP_SIDED
		transformedTangent = - transformedTangent;
	#endif
#endif`,dN=`#ifdef USE_DISPLACEMENTMAP
	uniform sampler2D displacementMap;
	uniform float displacementScale;
	uniform float displacementBias;
#endif`,lN=`#ifdef USE_DISPLACEMENTMAP
	transformed += normalize( objectNormal ) * ( texture2D( displacementMap, vDisplacementMapUv ).x * displacementScale + displacementBias );
#endif`,uN=`#ifdef USE_EMISSIVEMAP
	vec4 emissiveColor = texture2D( emissiveMap, vEmissiveMapUv );
	#ifdef DECODE_VIDEO_TEXTURE_EMISSIVE
		emissiveColor = sRGBTransferEOTF( emissiveColor );
	#endif
	totalEmissiveRadiance *= emissiveColor.rgb;
#endif`,cN=`#ifdef USE_EMISSIVEMAP
	uniform sampler2D emissiveMap;
#endif`,nN="gl_FragColor = linearToOutputTexel( gl_FragColor );",sN=`vec4 LinearTransferOETF( in vec4 value ) {
	return value;
}
vec4 sRGBTransferEOTF( in vec4 value ) {
	return vec4( mix( pow( value.rgb * 0.9478672986 + vec3( 0.0521327014 ), vec3( 2.4 ) ), value.rgb * 0.0773993808, vec3( lessThanEqual( value.rgb, vec3( 0.04045 ) ) ) ), value.a );
}
vec4 sRGBTransferOETF( in vec4 value ) {
	return vec4( mix( pow( value.rgb, vec3( 0.41666 ) ) * 1.055 - vec3( 0.055 ), value.rgb * 12.92, vec3( lessThanEqual( value.rgb, vec3( 0.0031308 ) ) ) ), value.a );
}`,iN=`#ifdef USE_ENVMAP
	#ifdef ENV_WORLDPOS
		vec3 cameraToFrag;
		if ( isOrthographic ) {
			cameraToFrag = normalize( vec3( - viewMatrix[ 0 ][ 2 ], - viewMatrix[ 1 ][ 2 ], - viewMatrix[ 2 ][ 2 ] ) );
		} else {
			cameraToFrag = normalize( vWorldPosition - cameraPosition );
		}
		vec3 worldNormal = inverseTransformDirection( normal, viewMatrix );
		#ifdef ENVMAP_MODE_REFLECTION
			vec3 reflectVec = reflect( cameraToFrag, worldNormal );
		#else
			vec3 reflectVec = refract( cameraToFrag, worldNormal, refractionRatio );
		#endif
	#else
		vec3 reflectVec = vReflect;
	#endif
	#ifdef ENVMAP_TYPE_CUBE
		vec4 envColor = textureCube( envMap, envMapRotation * vec3( flipEnvMap * reflectVec.x, reflectVec.yz ) );
	#else
		vec4 envColor = vec4( 0.0 );
	#endif
	#ifdef ENVMAP_BLENDING_MULTIPLY
		outgoingLight = mix( outgoingLight, outgoingLight * envColor.xyz, specularStrength * reflectivity );
	#elif defined( ENVMAP_BLENDING_MIX )
		outgoingLight = mix( outgoingLight, envColor.xyz, specularStrength * reflectivity );
	#elif defined( ENVMAP_BLENDING_ADD )
		outgoingLight += envColor.xyz * specularStrength * reflectivity;
	#endif
#endif`,oN=`#ifdef USE_ENVMAP
	uniform float envMapIntensity;
	uniform float flipEnvMap;
	uniform mat3 envMapRotation;
	#ifdef ENVMAP_TYPE_CUBE
		uniform samplerCube envMap;
	#else
		uniform sampler2D envMap;
	#endif
	
#endif`,aN=`#ifdef USE_ENVMAP
	uniform float reflectivity;
	#if defined( USE_BUMPMAP ) || defined( USE_NORMALMAP ) || defined( PHONG ) || defined( LAMBERT )
		#define ENV_WORLDPOS
	#endif
	#ifdef ENV_WORLDPOS
		varying vec3 vWorldPosition;
		uniform float refractionRatio;
	#else
		varying vec3 vReflect;
	#endif
#endif`,rN=`#ifdef USE_ENVMAP
	#if defined( USE_BUMPMAP ) || defined( USE_NORMALMAP ) || defined( PHONG ) || defined( LAMBERT )
		#define ENV_WORLDPOS
	#endif
	#ifdef ENV_WORLDPOS
		
		varying vec3 vWorldPosition;
	#else
		varying vec3 vReflect;
		uniform float refractionRatio;
	#endif
#endif`,tN=`#ifdef USE_ENVMAP
	#ifdef ENV_WORLDPOS
		vWorldPosition = worldPosition.xyz;
	#else
		vec3 cameraToVertex;
		if ( isOrthographic ) {
			cameraToVertex = normalize( vec3( - viewMatrix[ 0 ][ 2 ], - viewMatrix[ 1 ][ 2 ], - viewMatrix[ 2 ][ 2 ] ) );
		} else {
			cameraToVertex = normalize( worldPosition.xyz - cameraPosition );
		}
		vec3 worldNormal = inverseTransformDirection( transformedNormal, viewMatrix );
		#ifdef ENVMAP_MODE_REFLECTION
			vReflect = reflect( cameraToVertex, worldNormal );
		#else
			vReflect = refract( cameraToVertex, worldNormal, refractionRatio );
		#endif
	#endif
#endif`,eN=`#ifdef USE_FOG
	vFogDepth = - mvPosition.z;
#endif`,J1=`#ifdef USE_FOG
	varying float vFogDepth;
#endif`,Q1=`#ifdef USE_FOG
	#ifdef FOG_EXP2
		float fogFactor = 1.0 - exp( - fogDensity * fogDensity * vFogDepth * vFogDepth );
	#else
		float fogFactor = smoothstep( fogNear, fogFar, vFogDepth );
	#endif
	gl_FragColor.rgb = mix( gl_FragColor.rgb, fogColor, fogFactor );
#endif`,$1=`#ifdef USE_FOG
	uniform vec3 fogColor;
	varying float vFogDepth;
	#ifdef FOG_EXP2
		uniform float fogDensity;
	#else
		uniform float fogNear;
		uniform float fogFar;
	#endif
#endif`,Z1=`#ifdef USE_GRADIENTMAP
	uniform sampler2D gradientMap;
#endif
vec3 getGradientIrradiance( vec3 normal, vec3 lightDirection ) {
	float dotNL = dot( normal, lightDirection );
	vec2 coord = vec2( dotNL * 0.5 + 0.5, 0.0 );
	#ifdef USE_GRADIENTMAP
		return vec3( texture2D( gradientMap, coord ).r );
	#else
		vec2 fw = fwidth( coord ) * 0.5;
		return mix( vec3( 0.7 ), vec3( 1.0 ), smoothstep( 0.7 - fw.x, 0.7 + fw.x, coord.x ) );
	#endif
}`,W1=`#ifdef USE_LIGHTMAP
	uniform sampler2D lightMap;
	uniform float lightMapIntensity;
#endif`,K1=`LambertMaterial material;
material.diffuseColor = diffuseColor.rgb;
material.specularStrength = specularStrength;`,H1=`varying vec3 vViewPosition;
struct LambertMaterial {
	vec3 diffuseColor;
	float specularStrength;
};
void RE_Direct_Lambert( const in IncidentLight directLight, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in LambertMaterial material, inout ReflectedLight reflectedLight ) {
	float dotNL = saturate( dot( geometryNormal, directLight.direction ) );
	vec3 irradiance = dotNL * directLight.color;
	reflectedLight.directDiffuse += irradiance * BRDF_Lambert( material.diffuseColor );
}
void RE_IndirectDiffuse_Lambert( const in vec3 irradiance, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in LambertMaterial material, inout ReflectedLight reflectedLight ) {
	reflectedLight.indirectDiffuse += irradiance * BRDF_Lambert( material.diffuseColor );
}
#define RE_Direct				RE_Direct_Lambert
#define RE_IndirectDiffuse		RE_IndirectDiffuse_Lambert`,Y1=`uniform bool receiveShadow;
uniform vec3 ambientLightColor;
#if defined( USE_LIGHT_PROBES )
	uniform vec3 lightProbe[ 9 ];
#endif
vec3 shGetIrradianceAt( in vec3 normal, in vec3 shCoefficients[ 9 ] ) {
	float x = normal.x, y = normal.y, z = normal.z;
	vec3 result = shCoefficients[ 0 ] * 0.886227;
	result += shCoefficients[ 1 ] * 2.0 * 0.511664 * y;
	result += shCoefficients[ 2 ] * 2.0 * 0.511664 * z;
	result += shCoefficients[ 3 ] * 2.0 * 0.511664 * x;
	result += shCoefficients[ 4 ] * 2.0 * 0.429043 * x * y;
	result += shCoefficients[ 5 ] * 2.0 * 0.429043 * y * z;
	result += shCoefficients[ 6 ] * ( 0.743125 * z * z - 0.247708 );
	result += shCoefficients[ 7 ] * 2.0 * 0.429043 * x * z;
	result += shCoefficients[ 8 ] * 0.429043 * ( x * x - y * y );
	return result;
}
vec3 getLightProbeIrradiance( const in vec3 lightProbe[ 9 ], const in vec3 normal ) {
	vec3 worldNormal = inverseTransformDirection( normal, viewMatrix );
	vec3 irradiance = shGetIrradianceAt( worldNormal, lightProbe );
	return irradiance;
}
vec3 getAmbientLightIrradiance( const in vec3 ambientLightColor ) {
	vec3 irradiance = ambientLightColor;
	return irradiance;
}
float getDistanceAttenuation( const in float lightDistance, const in float cutoffDistance, const in float decayExponent ) {
	float distanceFalloff = 1.0 / max( pow( lightDistance, decayExponent ), 0.01 );
	if ( cutoffDistance > 0.0 ) {
		distanceFalloff *= pow2( saturate( 1.0 - pow4( lightDistance / cutoffDistance ) ) );
	}
	return distanceFalloff;
}
float getSpotAttenuation( const in float coneCosine, const in float penumbraCosine, const in float angleCosine ) {
	return smoothstep( coneCosine, penumbraCosine, angleCosine );
}
#if NUM_DIR_LIGHTS > 0
	struct DirectionalLight {
		vec3 direction;
		vec3 color;
	};
	uniform DirectionalLight directionalLights[ NUM_DIR_LIGHTS ];
	void getDirectionalLightInfo( const in DirectionalLight directionalLight, out IncidentLight light ) {
		light.color = directionalLight.color;
		light.direction = directionalLight.direction;
		light.visible = true;
	}
#endif
#if NUM_POINT_LIGHTS > 0
	struct PointLight {
		vec3 position;
		vec3 color;
		float distance;
		float decay;
	};
	uniform PointLight pointLights[ NUM_POINT_LIGHTS ];
	void getPointLightInfo( const in PointLight pointLight, const in vec3 geometryPosition, out IncidentLight light ) {
		vec3 lVector = pointLight.position - geometryPosition;
		light.direction = normalize( lVector );
		float lightDistance = length( lVector );
		light.color = pointLight.color;
		light.color *= getDistanceAttenuation( lightDistance, pointLight.distance, pointLight.decay );
		light.visible = ( light.color != vec3( 0.0 ) );
	}
#endif
#if NUM_SPOT_LIGHTS > 0
	struct SpotLight {
		vec3 position;
		vec3 direction;
		vec3 color;
		float distance;
		float decay;
		float coneCos;
		float penumbraCos;
	};
	uniform SpotLight spotLights[ NUM_SPOT_LIGHTS ];
	void getSpotLightInfo( const in SpotLight spotLight, const in vec3 geometryPosition, out IncidentLight light ) {
		vec3 lVector = spotLight.position - geometryPosition;
		light.direction = normalize( lVector );
		float angleCos = dot( light.direction, spotLight.direction );
		float spotAttenuation = getSpotAttenuation( spotLight.coneCos, spotLight.penumbraCos, angleCos );
		if ( spotAttenuation > 0.0 ) {
			float lightDistance = length( lVector );
			light.color = spotLight.color * spotAttenuation;
			light.color *= getDistanceAttenuation( lightDistance, spotLight.distance, spotLight.decay );
			light.visible = ( light.color != vec3( 0.0 ) );
		} else {
			light.color = vec3( 0.0 );
			light.visible = false;
		}
	}
#endif
#if NUM_RECT_AREA_LIGHTS > 0
	struct RectAreaLight {
		vec3 color;
		vec3 position;
		vec3 halfWidth;
		vec3 halfHeight;
	};
	uniform sampler2D ltc_1;	uniform sampler2D ltc_2;
	uniform RectAreaLight rectAreaLights[ NUM_RECT_AREA_LIGHTS ];
#endif
#if NUM_HEMI_LIGHTS > 0
	struct HemisphereLight {
		vec3 direction;
		vec3 skyColor;
		vec3 groundColor;
	};
	uniform HemisphereLight hemisphereLights[ NUM_HEMI_LIGHTS ];
	vec3 getHemisphereLightIrradiance( const in HemisphereLight hemiLight, const in vec3 normal ) {
		float dotNL = dot( normal, hemiLight.direction );
		float hemiDiffuseWeight = 0.5 * dotNL + 0.5;
		vec3 irradiance = mix( hemiLight.groundColor, hemiLight.skyColor, hemiDiffuseWeight );
		return irradiance;
	}
#endif`,X1=`#ifdef USE_ENVMAP
	vec3 getIBLIrradiance( const in vec3 normal ) {
		#ifdef ENVMAP_TYPE_CUBE_UV
			vec3 worldNormal = inverseTransformDirection( normal, viewMatrix );
			vec4 envMapColor = textureCubeUV( envMap, envMapRotation * worldNormal, 1.0 );
			return PI * envMapColor.rgb * envMapIntensity;
		#else
			return vec3( 0.0 );
		#endif
	}
	vec3 getIBLRadiance( const in vec3 viewDir, const in vec3 normal, const in float roughness ) {
		#ifdef ENVMAP_TYPE_CUBE_UV
			vec3 reflectVec = reflect( - viewDir, normal );
			reflectVec = normalize( mix( reflectVec, normal, roughness * roughness) );
			reflectVec = inverseTransformDirection( reflectVec, viewMatrix );
			vec4 envMapColor = textureCubeUV( envMap, envMapRotation * reflectVec, roughness );
			return envMapColor.rgb * envMapIntensity;
		#else
			return vec3( 0.0 );
		#endif
	}
	#ifdef USE_ANISOTROPY
		vec3 getIBLAnisotropyRadiance( const in vec3 viewDir, const in vec3 normal, const in float roughness, const in vec3 bitangent, const in float anisotropy ) {
			#ifdef ENVMAP_TYPE_CUBE_UV
				vec3 bentNormal = cross( bitangent, viewDir );
				bentNormal = normalize( cross( bentNormal, bitangent ) );
				bentNormal = normalize( mix( bentNormal, normal, pow2( pow2( 1.0 - anisotropy * ( 1.0 - roughness ) ) ) ) );
				return getIBLRadiance( viewDir, bentNormal, roughness );
			#else
				return vec3( 0.0 );
			#endif
		}
	#endif
#endif`,U1=`ToonMaterial material;
material.diffuseColor = diffuseColor.rgb;`,G1=`varying vec3 vViewPosition;
struct ToonMaterial {
	vec3 diffuseColor;
};
void RE_Direct_Toon( const in IncidentLight directLight, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in ToonMaterial material, inout ReflectedLight reflectedLight ) {
	vec3 irradiance = getGradientIrradiance( geometryNormal, directLight.direction ) * directLight.color;
	reflectedLight.directDiffuse += irradiance * BRDF_Lambert( material.diffuseColor );
}
void RE_IndirectDiffuse_Toon( const in vec3 irradiance, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in ToonMaterial material, inout ReflectedLight reflectedLight ) {
	reflectedLight.indirectDiffuse += irradiance * BRDF_Lambert( material.diffuseColor );
}
#define RE_Direct				RE_Direct_Toon
#define RE_IndirectDiffuse		RE_IndirectDiffuse_Toon`,E1=`BlinnPhongMaterial material;
material.diffuseColor = diffuseColor.rgb;
material.specularColor = specular;
material.specularShininess = shininess;
material.specularStrength = specularStrength;`,N1=`varying vec3 vViewPosition;
struct BlinnPhongMaterial {
	vec3 diffuseColor;
	vec3 specularColor;
	float specularShininess;
	float specularStrength;
};
void RE_Direct_BlinnPhong( const in IncidentLight directLight, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in BlinnPhongMaterial material, inout ReflectedLight reflectedLight ) {
	float dotNL = saturate( dot( geometryNormal, directLight.direction ) );
	vec3 irradiance = dotNL * directLight.color;
	reflectedLight.directDiffuse += irradiance * BRDF_Lambert( material.diffuseColor );
	reflectedLight.directSpecular += irradiance * BRDF_BlinnPhong( directLight.direction, geometryViewDir, geometryNormal, material.specularColor, material.specularShininess ) * material.specularStrength;
}
void RE_IndirectDiffuse_BlinnPhong( const in vec3 irradiance, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in BlinnPhongMaterial material, inout ReflectedLight reflectedLight ) {
	reflectedLight.indirectDiffuse += irradiance * BRDF_Lambert( material.diffuseColor );
}
#define RE_Direct				RE_Direct_BlinnPhong
#define RE_IndirectDiffuse		RE_IndirectDiffuse_BlinnPhong`,q1=`PhysicalMaterial material;
material.diffuseColor = diffuseColor.rgb * ( 1.0 - metalnessFactor );
vec3 dxy = max( abs( dFdx( nonPerturbedNormal ) ), abs( dFdy( nonPerturbedNormal ) ) );
float geometryRoughness = max( max( dxy.x, dxy.y ), dxy.z );
material.roughness = max( roughnessFactor, 0.0525 );material.roughness += geometryRoughness;
material.roughness = min( material.roughness, 1.0 );
#ifdef IOR
	material.ior = ior;
	#ifdef USE_SPECULAR
		float specularIntensityFactor = specularIntensity;
		vec3 specularColorFactor = specularColor;
		#ifdef USE_SPECULAR_COLORMAP
			specularColorFactor *= texture2D( specularColorMap, vSpecularColorMapUv ).rgb;
		#endif
		#ifdef USE_SPECULAR_INTENSITYMAP
			specularIntensityFactor *= texture2D( specularIntensityMap, vSpecularIntensityMapUv ).a;
		#endif
		material.specularF90 = mix( specularIntensityFactor, 1.0, metalnessFactor );
	#else
		float specularIntensityFactor = 1.0;
		vec3 specularColorFactor = vec3( 1.0 );
		material.specularF90 = 1.0;
	#endif
	material.specularColor = mix( min( pow2( ( material.ior - 1.0 ) / ( material.ior + 1.0 ) ) * specularColorFactor, vec3( 1.0 ) ) * specularIntensityFactor, diffuseColor.rgb, metalnessFactor );
#else
	material.specularColor = mix( vec3( 0.04 ), diffuseColor.rgb, metalnessFactor );
	material.specularF90 = 1.0;
#endif
#ifdef USE_CLEARCOAT
	material.clearcoat = clearcoat;
	material.clearcoatRoughness = clearcoatRoughness;
	material.clearcoatF0 = vec3( 0.04 );
	material.clearcoatF90 = 1.0;
	#ifdef USE_CLEARCOATMAP
		material.clearcoat *= texture2D( clearcoatMap, vClearcoatMapUv ).x;
	#endif
	#ifdef USE_CLEARCOAT_ROUGHNESSMAP
		material.clearcoatRoughness *= texture2D( clearcoatRoughnessMap, vClearcoatRoughnessMapUv ).y;
	#endif
	material.clearcoat = saturate( material.clearcoat );	material.clearcoatRoughness = max( material.clearcoatRoughness, 0.0525 );
	material.clearcoatRoughness += geometryRoughness;
	material.clearcoatRoughness = min( material.clearcoatRoughness, 1.0 );
#endif
#ifdef USE_DISPERSION
	material.dispersion = dispersion;
#endif
#ifdef USE_IRIDESCENCE
	material.iridescence = iridescence;
	material.iridescenceIOR = iridescenceIOR;
	#ifdef USE_IRIDESCENCEMAP
		material.iridescence *= texture2D( iridescenceMap, vIridescenceMapUv ).r;
	#endif
	#ifdef USE_IRIDESCENCE_THICKNESSMAP
		material.iridescenceThickness = (iridescenceThicknessMaximum - iridescenceThicknessMinimum) * texture2D( iridescenceThicknessMap, vIridescenceThicknessMapUv ).g + iridescenceThicknessMinimum;
	#else
		material.iridescenceThickness = iridescenceThicknessMaximum;
	#endif
#endif
#ifdef USE_SHEEN
	material.sheenColor = sheenColor;
	#ifdef USE_SHEEN_COLORMAP
		material.sheenColor *= texture2D( sheenColorMap, vSheenColorMapUv ).rgb;
	#endif
	material.sheenRoughness = clamp( sheenRoughness, 0.07, 1.0 );
	#ifdef USE_SHEEN_ROUGHNESSMAP
		material.sheenRoughness *= texture2D( sheenRoughnessMap, vSheenRoughnessMapUv ).a;
	#endif
#endif
#ifdef USE_ANISOTROPY
	#ifdef USE_ANISOTROPYMAP
		mat2 anisotropyMat = mat2( anisotropyVector.x, anisotropyVector.y, - anisotropyVector.y, anisotropyVector.x );
		vec3 anisotropyPolar = texture2D( anisotropyMap, vAnisotropyMapUv ).rgb;
		vec2 anisotropyV = anisotropyMat * normalize( 2.0 * anisotropyPolar.rg - vec2( 1.0 ) ) * anisotropyPolar.b;
	#else
		vec2 anisotropyV = anisotropyVector;
	#endif
	material.anisotropy = length( anisotropyV );
	if( material.anisotropy == 0.0 ) {
		anisotropyV = vec2( 1.0, 0.0 );
	} else {
		anisotropyV /= material.anisotropy;
		material.anisotropy = saturate( material.anisotropy );
	}
	material.alphaT = mix( pow2( material.roughness ), 1.0, pow2( material.anisotropy ) );
	material.anisotropyT = tbn[ 0 ] * anisotropyV.x + tbn[ 1 ] * anisotropyV.y;
	material.anisotropyB = tbn[ 1 ] * anisotropyV.x - tbn[ 0 ] * anisotropyV.y;
#endif`,D1=`struct PhysicalMaterial {
	vec3 diffuseColor;
	float roughness;
	vec3 specularColor;
	float specularF90;
	float dispersion;
	#ifdef USE_CLEARCOAT
		float clearcoat;
		float clearcoatRoughness;
		vec3 clearcoatF0;
		float clearcoatF90;
	#endif
	#ifdef USE_IRIDESCENCE
		float iridescence;
		float iridescenceIOR;
		float iridescenceThickness;
		vec3 iridescenceFresnel;
		vec3 iridescenceF0;
	#endif
	#ifdef USE_SHEEN
		vec3 sheenColor;
		float sheenRoughness;
	#endif
	#ifdef IOR
		float ior;
	#endif
	#ifdef USE_TRANSMISSION
		float transmission;
		float transmissionAlpha;
		float thickness;
		float attenuationDistance;
		vec3 attenuationColor;
	#endif
	#ifdef USE_ANISOTROPY
		float anisotropy;
		float alphaT;
		vec3 anisotropyT;
		vec3 anisotropyB;
	#endif
};
vec3 clearcoatSpecularDirect = vec3( 0.0 );
vec3 clearcoatSpecularIndirect = vec3( 0.0 );
vec3 sheenSpecularDirect = vec3( 0.0 );
vec3 sheenSpecularIndirect = vec3(0.0 );
vec3 Schlick_to_F0( const in vec3 f, const in float f90, const in float dotVH ) {
    float x = clamp( 1.0 - dotVH, 0.0, 1.0 );
    float x2 = x * x;
    float x5 = clamp( x * x2 * x2, 0.0, 0.9999 );
    return ( f - vec3( f90 ) * x5 ) / ( 1.0 - x5 );
}
float V_GGX_SmithCorrelated( const in float alpha, const in float dotNL, const in float dotNV ) {
	float a2 = pow2( alpha );
	float gv = dotNL * sqrt( a2 + ( 1.0 - a2 ) * pow2( dotNV ) );
	float gl = dotNV * sqrt( a2 + ( 1.0 - a2 ) * pow2( dotNL ) );
	return 0.5 / max( gv + gl, EPSILON );
}
float D_GGX( const in float alpha, const in float dotNH ) {
	float a2 = pow2( alpha );
	float denom = pow2( dotNH ) * ( a2 - 1.0 ) + 1.0;
	return RECIPROCAL_PI * a2 / pow2( denom );
}
#ifdef USE_ANISOTROPY
	float V_GGX_SmithCorrelated_Anisotropic( const in float alphaT, const in float alphaB, const in float dotTV, const in float dotBV, const in float dotTL, const in float dotBL, const in float dotNV, const in float dotNL ) {
		float gv = dotNL * length( vec3( alphaT * dotTV, alphaB * dotBV, dotNV ) );
		float gl = dotNV * length( vec3( alphaT * dotTL, alphaB * dotBL, dotNL ) );
		float v = 0.5 / ( gv + gl );
		return saturate(v);
	}
	float D_GGX_Anisotropic( const in float alphaT, const in float alphaB, const in float dotNH, const in float dotTH, const in float dotBH ) {
		float a2 = alphaT * alphaB;
		highp vec3 v = vec3( alphaB * dotTH, alphaT * dotBH, a2 * dotNH );
		highp float v2 = dot( v, v );
		float w2 = a2 / v2;
		return RECIPROCAL_PI * a2 * pow2 ( w2 );
	}
#endif
#ifdef USE_CLEARCOAT
	vec3 BRDF_GGX_Clearcoat( const in vec3 lightDir, const in vec3 viewDir, const in vec3 normal, const in PhysicalMaterial material) {
		vec3 f0 = material.clearcoatF0;
		float f90 = material.clearcoatF90;
		float roughness = material.clearcoatRoughness;
		float alpha = pow2( roughness );
		vec3 halfDir = normalize( lightDir + viewDir );
		float dotNL = saturate( dot( normal, lightDir ) );
		float dotNV = saturate( dot( normal, viewDir ) );
		float dotNH = saturate( dot( normal, halfDir ) );
		float dotVH = saturate( dot( viewDir, halfDir ) );
		vec3 F = F_Schlick( f0, f90, dotVH );
		float V = V_GGX_SmithCorrelated( alpha, dotNL, dotNV );
		float D = D_GGX( alpha, dotNH );
		return F * ( V * D );
	}
#endif
vec3 BRDF_GGX( const in vec3 lightDir, const in vec3 viewDir, const in vec3 normal, const in PhysicalMaterial material ) {
	vec3 f0 = material.specularColor;
	float f90 = material.specularF90;
	float roughness = material.roughness;
	float alpha = pow2( roughness );
	vec3 halfDir = normalize( lightDir + viewDir );
	float dotNL = saturate( dot( normal, lightDir ) );
	float dotNV = saturate( dot( normal, viewDir ) );
	float dotNH = saturate( dot( normal, halfDir ) );
	float dotVH = saturate( dot( viewDir, halfDir ) );
	vec3 F = F_Schlick( f0, f90, dotVH );
	#ifdef USE_IRIDESCENCE
		F = mix( F, material.iridescenceFresnel, material.iridescence );
	#endif
	#ifdef USE_ANISOTROPY
		float dotTL = dot( material.anisotropyT, lightDir );
		float dotTV = dot( material.anisotropyT, viewDir );
		float dotTH = dot( material.anisotropyT, halfDir );
		float dotBL = dot( material.anisotropyB, lightDir );
		float dotBV = dot( material.anisotropyB, viewDir );
		float dotBH = dot( material.anisotropyB, halfDir );
		float V = V_GGX_SmithCorrelated_Anisotropic( material.alphaT, alpha, dotTV, dotBV, dotTL, dotBL, dotNV, dotNL );
		float D = D_GGX_Anisotropic( material.alphaT, alpha, dotNH, dotTH, dotBH );
	#else
		float V = V_GGX_SmithCorrelated( alpha, dotNL, dotNV );
		float D = D_GGX( alpha, dotNH );
	#endif
	return F * ( V * D );
}
vec2 LTC_Uv( const in vec3 N, const in vec3 V, const in float roughness ) {
	const float LUT_SIZE = 64.0;
	const float LUT_SCALE = ( LUT_SIZE - 1.0 ) / LUT_SIZE;
	const float LUT_BIAS = 0.5 / LUT_SIZE;
	float dotNV = saturate( dot( N, V ) );
	vec2 uv = vec2( roughness, sqrt( 1.0 - dotNV ) );
	uv = uv * LUT_SCALE + LUT_BIAS;
	return uv;
}
float LTC_ClippedSphereFormFactor( const in vec3 f ) {
	float l = length( f );
	return max( ( l * l + f.z ) / ( l + 1.0 ), 0.0 );
}
vec3 LTC_EdgeVectorFormFactor( const in vec3 v1, const in vec3 v2 ) {
	float x = dot( v1, v2 );
	float y = abs( x );
	float a = 0.8543985 + ( 0.4965155 + 0.0145206 * y ) * y;
	float b = 3.4175940 + ( 4.1616724 + y ) * y;
	float v = a / b;
	float theta_sintheta = ( x > 0.0 ) ? v : 0.5 * inversesqrt( max( 1.0 - x * x, 1e-7 ) ) - v;
	return cross( v1, v2 ) * theta_sintheta;
}
vec3 LTC_Evaluate( const in vec3 N, const in vec3 V, const in vec3 P, const in mat3 mInv, const in vec3 rectCoords[ 4 ] ) {
	vec3 v1 = rectCoords[ 1 ] - rectCoords[ 0 ];
	vec3 v2 = rectCoords[ 3 ] - rectCoords[ 0 ];
	vec3 lightNormal = cross( v1, v2 );
	if( dot( lightNormal, P - rectCoords[ 0 ] ) < 0.0 ) return vec3( 0.0 );
	vec3 T1, T2;
	T1 = normalize( V - N * dot( V, N ) );
	T2 = - cross( N, T1 );
	mat3 mat = mInv * transposeMat3( mat3( T1, T2, N ) );
	vec3 coords[ 4 ];
	coords[ 0 ] = mat * ( rectCoords[ 0 ] - P );
	coords[ 1 ] = mat * ( rectCoords[ 1 ] - P );
	coords[ 2 ] = mat * ( rectCoords[ 2 ] - P );
	coords[ 3 ] = mat * ( rectCoords[ 3 ] - P );
	coords[ 0 ] = normalize( coords[ 0 ] );
	coords[ 1 ] = normalize( coords[ 1 ] );
	coords[ 2 ] = normalize( coords[ 2 ] );
	coords[ 3 ] = normalize( coords[ 3 ] );
	vec3 vectorFormFactor = vec3( 0.0 );
	vectorFormFactor += LTC_EdgeVectorFormFactor( coords[ 0 ], coords[ 1 ] );
	vectorFormFactor += LTC_EdgeVectorFormFactor( coords[ 1 ], coords[ 2 ] );
	vectorFormFactor += LTC_EdgeVectorFormFactor( coords[ 2 ], coords[ 3 ] );
	vectorFormFactor += LTC_EdgeVectorFormFactor( coords[ 3 ], coords[ 0 ] );
	float result = LTC_ClippedSphereFormFactor( vectorFormFactor );
	return vec3( result );
}
#if defined( USE_SHEEN )
float D_Charlie( float roughness, float dotNH ) {
	float alpha = pow2( roughness );
	float invAlpha = 1.0 / alpha;
	float cos2h = dotNH * dotNH;
	float sin2h = max( 1.0 - cos2h, 0.0078125 );
	return ( 2.0 + invAlpha ) * pow( sin2h, invAlpha * 0.5 ) / ( 2.0 * PI );
}
float V_Neubelt( float dotNV, float dotNL ) {
	return saturate( 1.0 / ( 4.0 * ( dotNL + dotNV - dotNL * dotNV ) ) );
}
vec3 BRDF_Sheen( const in vec3 lightDir, const in vec3 viewDir, const in vec3 normal, vec3 sheenColor, const in float sheenRoughness ) {
	vec3 halfDir = normalize( lightDir + viewDir );
	float dotNL = saturate( dot( normal, lightDir ) );
	float dotNV = saturate( dot( normal, viewDir ) );
	float dotNH = saturate( dot( normal, halfDir ) );
	float D = D_Charlie( sheenRoughness, dotNH );
	float V = V_Neubelt( dotNV, dotNL );
	return sheenColor * ( D * V );
}
#endif
float IBLSheenBRDF( const in vec3 normal, const in vec3 viewDir, const in float roughness ) {
	float dotNV = saturate( dot( normal, viewDir ) );
	float r2 = roughness * roughness;
	float a = roughness < 0.25 ? -339.2 * r2 + 161.4 * roughness - 25.9 : -8.48 * r2 + 14.3 * roughness - 9.95;
	float b = roughness < 0.25 ? 44.0 * r2 - 23.7 * roughness + 3.26 : 1.97 * r2 - 3.27 * roughness + 0.72;
	float DG = exp( a * dotNV + b ) + ( roughness < 0.25 ? 0.0 : 0.1 * ( roughness - 0.25 ) );
	return saturate( DG * RECIPROCAL_PI );
}
vec2 DFGApprox( const in vec3 normal, const in vec3 viewDir, const in float roughness ) {
	float dotNV = saturate( dot( normal, viewDir ) );
	const vec4 c0 = vec4( - 1, - 0.0275, - 0.572, 0.022 );
	const vec4 c1 = vec4( 1, 0.0425, 1.04, - 0.04 );
	vec4 r = roughness * c0 + c1;
	float a004 = min( r.x * r.x, exp2( - 9.28 * dotNV ) ) * r.x + r.y;
	vec2 fab = vec2( - 1.04, 1.04 ) * a004 + r.zw;
	return fab;
}
vec3 EnvironmentBRDF( const in vec3 normal, const in vec3 viewDir, const in vec3 specularColor, const in float specularF90, const in float roughness ) {
	vec2 fab = DFGApprox( normal, viewDir, roughness );
	return specularColor * fab.x + specularF90 * fab.y;
}
#ifdef USE_IRIDESCENCE
void computeMultiscatteringIridescence( const in vec3 normal, const in vec3 viewDir, const in vec3 specularColor, const in float specularF90, const in float iridescence, const in vec3 iridescenceF0, const in float roughness, inout vec3 singleScatter, inout vec3 multiScatter ) {
#else
void computeMultiscattering( const in vec3 normal, const in vec3 viewDir, const in vec3 specularColor, const in float specularF90, const in float roughness, inout vec3 singleScatter, inout vec3 multiScatter ) {
#endif
	vec2 fab = DFGApprox( normal, viewDir, roughness );
	#ifdef USE_IRIDESCENCE
		vec3 Fr = mix( specularColor, iridescenceF0, iridescence );
	#else
		vec3 Fr = specularColor;
	#endif
	vec3 FssEss = Fr * fab.x + specularF90 * fab.y;
	float Ess = fab.x + fab.y;
	float Ems = 1.0 - Ess;
	vec3 Favg = Fr + ( 1.0 - Fr ) * 0.047619;	vec3 Fms = FssEss * Favg / ( 1.0 - Ems * Favg );
	singleScatter += FssEss;
	multiScatter += Fms * Ems;
}
#if NUM_RECT_AREA_LIGHTS > 0
	void RE_Direct_RectArea_Physical( const in RectAreaLight rectAreaLight, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in PhysicalMaterial material, inout ReflectedLight reflectedLight ) {
		vec3 normal = geometryNormal;
		vec3 viewDir = geometryViewDir;
		vec3 position = geometryPosition;
		vec3 lightPos = rectAreaLight.position;
		vec3 halfWidth = rectAreaLight.halfWidth;
		vec3 halfHeight = rectAreaLight.halfHeight;
		vec3 lightColor = rectAreaLight.color;
		float roughness = material.roughness;
		vec3 rectCoords[ 4 ];
		rectCoords[ 0 ] = lightPos + halfWidth - halfHeight;		rectCoords[ 1 ] = lightPos - halfWidth - halfHeight;
		rectCoords[ 2 ] = lightPos - halfWidth + halfHeight;
		rectCoords[ 3 ] = lightPos + halfWidth + halfHeight;
		vec2 uv = LTC_Uv( normal, viewDir, roughness );
		vec4 t1 = texture2D( ltc_1, uv );
		vec4 t2 = texture2D( ltc_2, uv );
		mat3 mInv = mat3(
			vec3( t1.x, 0, t1.y ),
			vec3(    0, 1,    0 ),
			vec3( t1.z, 0, t1.w )
		);
		vec3 fresnel = ( material.specularColor * t2.x + ( vec3( 1.0 ) - material.specularColor ) * t2.y );
		reflectedLight.directSpecular += lightColor * fresnel * LTC_Evaluate( normal, viewDir, position, mInv, rectCoords );
		reflectedLight.directDiffuse += lightColor * material.diffuseColor * LTC_Evaluate( normal, viewDir, position, mat3( 1.0 ), rectCoords );
	}
#endif
void RE_Direct_Physical( const in IncidentLight directLight, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in PhysicalMaterial material, inout ReflectedLight reflectedLight ) {
	float dotNL = saturate( dot( geometryNormal, directLight.direction ) );
	vec3 irradiance = dotNL * directLight.color;
	#ifdef USE_CLEARCOAT
		float dotNLcc = saturate( dot( geometryClearcoatNormal, directLight.direction ) );
		vec3 ccIrradiance = dotNLcc * directLight.color;
		clearcoatSpecularDirect += ccIrradiance * BRDF_GGX_Clearcoat( directLight.direction, geometryViewDir, geometryClearcoatNormal, material );
	#endif
	#ifdef USE_SHEEN
		sheenSpecularDirect += irradiance * BRDF_Sheen( directLight.direction, geometryViewDir, geometryNormal, material.sheenColor, material.sheenRoughness );
	#endif
	reflectedLight.directSpecular += irradiance * BRDF_GGX( directLight.direction, geometryViewDir, geometryNormal, material );
	reflectedLight.directDiffuse += irradiance * BRDF_Lambert( material.diffuseColor );
}
void RE_IndirectDiffuse_Physical( const in vec3 irradiance, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in PhysicalMaterial material, inout ReflectedLight reflectedLight ) {
	reflectedLight.indirectDiffuse += irradiance * BRDF_Lambert( material.diffuseColor );
}
void RE_IndirectSpecular_Physical( const in vec3 radiance, const in vec3 irradiance, const in vec3 clearcoatRadiance, const in vec3 geometryPosition, const in vec3 geometryNormal, const in vec3 geometryViewDir, const in vec3 geometryClearcoatNormal, const in PhysicalMaterial material, inout ReflectedLight reflectedLight) {
	#ifdef USE_CLEARCOAT
		clearcoatSpecularIndirect += clearcoatRadiance * EnvironmentBRDF( geometryClearcoatNormal, geometryViewDir, material.clearcoatF0, material.clearcoatF90, material.clearcoatRoughness );
	#endif
	#ifdef USE_SHEEN
		sheenSpecularIndirect += irradiance * material.sheenColor * IBLSheenBRDF( geometryNormal, geometryViewDir, material.sheenRoughness );
	#endif
	vec3 singleScattering = vec3( 0.0 );
	vec3 multiScattering = vec3( 0.0 );
	vec3 cosineWeightedIrradiance = irradiance * RECIPROCAL_PI;
	#ifdef USE_IRIDESCENCE
		computeMultiscatteringIridescence( geometryNormal, geometryViewDir, material.specularColor, material.specularF90, material.iridescence, material.iridescenceFresnel, material.roughness, singleScattering, multiScattering );
	#else
		computeMultiscattering( geometryNormal, geometryViewDir, material.specularColor, material.specularF90, material.roughness, singleScattering, multiScattering );
	#endif
	vec3 totalScattering = singleScattering + multiScattering;
	vec3 diffuse = material.diffuseColor * ( 1.0 - max( max( totalScattering.r, totalScattering.g ), totalScattering.b ) );
	reflectedLight.indirectSpecular += radiance * singleScattering;
	reflectedLight.indirectSpecular += multiScattering * cosineWeightedIrradiance;
	reflectedLight.indirectDiffuse += diffuse * cosineWeightedIrradiance;
}
#define RE_Direct				RE_Direct_Physical
#define RE_Direct_RectArea		RE_Direct_RectArea_Physical
#define RE_IndirectDiffuse		RE_IndirectDiffuse_Physical
#define RE_IndirectSpecular		RE_IndirectSpecular_Physical
float computeSpecularOcclusion( const in float dotNV, const in float ambientOcclusion, const in float roughness ) {
	return saturate( pow( dotNV + ambientOcclusion, exp2( - 16.0 * roughness - 1.0 ) ) - 1.0 + ambientOcclusion );
}`,O1=`
vec3 geometryPosition = - vViewPosition;
vec3 geometryNormal = normal;
vec3 geometryViewDir = ( isOrthographic ) ? vec3( 0, 0, 1 ) : normalize( vViewPosition );
vec3 geometryClearcoatNormal = vec3( 0.0 );
#ifdef USE_CLEARCOAT
	geometryClearcoatNormal = clearcoatNormal;
#endif
#ifdef USE_IRIDESCENCE
	float dotNVi = saturate( dot( normal, geometryViewDir ) );
	if ( material.iridescenceThickness == 0.0 ) {
		material.iridescence = 0.0;
	} else {
		material.iridescence = saturate( material.iridescence );
	}
	if ( material.iridescence > 0.0 ) {
		material.iridescenceFresnel = evalIridescence( 1.0, material.iridescenceIOR, dotNVi, material.iridescenceThickness, material.specularColor );
		material.iridescenceF0 = Schlick_to_F0( material.iridescenceFresnel, 1.0, dotNVi );
	}
#endif
IncidentLight directLight;
#if ( NUM_POINT_LIGHTS > 0 ) && defined( RE_Direct )
	PointLight pointLight;
	#if defined( USE_SHADOWMAP ) && NUM_POINT_LIGHT_SHADOWS > 0
	PointLightShadow pointLightShadow;
	#endif
	#pragma unroll_loop_start
	for ( int i = 0; i < NUM_POINT_LIGHTS; i ++ ) {
		pointLight = pointLights[ i ];
		getPointLightInfo( pointLight, geometryPosition, directLight );
		#if defined( USE_SHADOWMAP ) && ( UNROLLED_LOOP_INDEX < NUM_POINT_LIGHT_SHADOWS )
		pointLightShadow = pointLightShadows[ i ];
		directLight.color *= ( directLight.visible && receiveShadow ) ? getPointShadow( pointShadowMap[ i ], pointLightShadow.shadowMapSize, pointLightShadow.shadowIntensity, pointLightShadow.shadowBias, pointLightShadow.shadowRadius, vPointShadowCoord[ i ], pointLightShadow.shadowCameraNear, pointLightShadow.shadowCameraFar ) : 1.0;
		#endif
		RE_Direct( directLight, geometryPosition, geometryNormal, geometryViewDir, geometryClearcoatNormal, material, reflectedLight );
	}
	#pragma unroll_loop_end
#endif
#if ( NUM_SPOT_LIGHTS > 0 ) && defined( RE_Direct )
	SpotLight spotLight;
	vec4 spotColor;
	vec3 spotLightCoord;
	bool inSpotLightMap;
	#if defined( USE_SHADOWMAP ) && NUM_SPOT_LIGHT_SHADOWS > 0
	SpotLightShadow spotLightShadow;
	#endif
	#pragma unroll_loop_start
	for ( int i = 0; i < NUM_SPOT_LIGHTS; i ++ ) {
		spotLight = spotLights[ i ];
		getSpotLightInfo( spotLight, geometryPosition, directLight );
		#if ( UNROLLED_LOOP_INDEX < NUM_SPOT_LIGHT_SHADOWS_WITH_MAPS )
		#define SPOT_LIGHT_MAP_INDEX UNROLLED_LOOP_INDEX
		#elif ( UNROLLED_LOOP_INDEX < NUM_SPOT_LIGHT_SHADOWS )
		#define SPOT_LIGHT_MAP_INDEX NUM_SPOT_LIGHT_MAPS
		#else
		#define SPOT_LIGHT_MAP_INDEX ( UNROLLED_LOOP_INDEX - NUM_SPOT_LIGHT_SHADOWS + NUM_SPOT_LIGHT_SHADOWS_WITH_MAPS )
		#endif
		#if ( SPOT_LIGHT_MAP_INDEX < NUM_SPOT_LIGHT_MAPS )
			spotLightCoord = vSpotLightCoord[ i ].xyz / vSpotLightCoord[ i ].w;
			inSpotLightMap = all( lessThan( abs( spotLightCoord * 2. - 1. ), vec3( 1.0 ) ) );
			spotColor = texture2D( spotLightMap[ SPOT_LIGHT_MAP_INDEX ], spotLightCoord.xy );
			directLight.color = inSpotLightMap ? directLight.color * spotColor.rgb : directLight.color;
		#endif
		#undef SPOT_LIGHT_MAP_INDEX
		#if defined( USE_SHADOWMAP ) && ( UNROLLED_LOOP_INDEX < NUM_SPOT_LIGHT_SHADOWS )
		spotLightShadow = spotLightShadows[ i ];
		directLight.color *= ( directLight.visible && receiveShadow ) ? getShadow( spotShadowMap[ i ], spotLightShadow.shadowMapSize, spotLightShadow.shadowIntensity, spotLightShadow.shadowBias, spotLightShadow.shadowRadius, vSpotLightCoord[ i ] ) : 1.0;
		#endif
		RE_Direct( directLight, geometryPosition, geometryNormal, geometryViewDir, geometryClearcoatNormal, material, reflectedLight );
	}
	#pragma unroll_loop_end
#endif
#if ( NUM_DIR_LIGHTS > 0 ) && defined( RE_Direct )
	DirectionalLight directionalLight;
	#if defined( USE_SHADOWMAP ) && NUM_DIR_LIGHT_SHADOWS > 0
	DirectionalLightShadow directionalLightShadow;
	#endif
	#pragma unroll_loop_start
	for ( int i = 0; i < NUM_DIR_LIGHTS; i ++ ) {
		directionalLight = directionalLights[ i ];
		getDirectionalLightInfo( directionalLight, directLight );
		#if defined( USE_SHADOWMAP ) && ( UNROLLED_LOOP_INDEX < NUM_DIR_LIGHT_SHADOWS )
		directionalLightShadow = directionalLightShadows[ i ];
		directLight.color *= ( directLight.visible && receiveShadow ) ? getShadow( directionalShadowMap[ i ], directionalLightShadow.shadowMapSize, directionalLightShadow.shadowIntensity, directionalLightShadow.shadowBias, directionalLightShadow.shadowRadius, vDirectionalShadowCoord[ i ] ) : 1.0;
		#endif
		RE_Direct( directLight, geometryPosition, geometryNormal, geometryViewDir, geometryClearcoatNormal, material, reflectedLight );
	}
	#pragma unroll_loop_end
#endif
#if ( NUM_RECT_AREA_LIGHTS > 0 ) && defined( RE_Direct_RectArea )
	RectAreaLight rectAreaLight;
	#pragma unroll_loop_start
	for ( int i = 0; i < NUM_RECT_AREA_LIGHTS; i ++ ) {
		rectAreaLight = rectAreaLights[ i ];
		RE_Direct_RectArea( rectAreaLight, geometryPosition, geometryNormal, geometryViewDir, geometryClearcoatNormal, material, reflectedLight );
	}
	#pragma unroll_loop_end
#endif
#if defined( RE_IndirectDiffuse )
	vec3 iblIrradiance = vec3( 0.0 );
	vec3 irradiance = getAmbientLightIrradiance( ambientLightColor );
	#if defined( USE_LIGHT_PROBES )
		irradiance += getLightProbeIrradiance( lightProbe, geometryNormal );
	#endif
	#if ( NUM_HEMI_LIGHTS > 0 )
		#pragma unroll_loop_start
		for ( int i = 0; i < NUM_HEMI_LIGHTS; i ++ ) {
			irradiance += getHemisphereLightIrradiance( hemisphereLights[ i ], geometryNormal );
		}
		#pragma unroll_loop_end
	#endif
#endif
#if defined( RE_IndirectSpecular )
	vec3 radiance = vec3( 0.0 );
	vec3 clearcoatRadiance = vec3( 0.0 );
#endif`,R1=`#if defined( RE_IndirectDiffuse )
	#ifdef USE_LIGHTMAP
		vec4 lightMapTexel = texture2D( lightMap, vLightMapUv );
		vec3 lightMapIrradiance = lightMapTexel.rgb * lightMapIntensity;
		irradiance += lightMapIrradiance;
	#endif
	#if defined( USE_ENVMAP ) && defined( STANDARD ) && defined( ENVMAP_TYPE_CUBE_UV )
		iblIrradiance += getIBLIrradiance( geometryNormal );
	#endif
#endif
#if defined( USE_ENVMAP ) && defined( RE_IndirectSpecular )
	#ifdef USE_ANISOTROPY
		radiance += getIBLAnisotropyRadiance( geometryViewDir, geometryNormal, material.roughness, material.anisotropyB, material.anisotropy );
	#else
		radiance += getIBLRadiance( geometryViewDir, geometryNormal, material.roughness );
	#endif
	#ifdef USE_CLEARCOAT
		clearcoatRadiance += getIBLRadiance( geometryViewDir, geometryClearcoatNormal, material.clearcoatRoughness );
	#endif
#endif`,F1=`#if defined( RE_IndirectDiffuse )
	RE_IndirectDiffuse( irradiance, geometryPosition, geometryNormal, geometryViewDir, geometryClearcoatNormal, material, reflectedLight );
#endif
#if defined( RE_IndirectSpecular )
	RE_IndirectSpecular( radiance, iblIrradiance, clearcoatRadiance, geometryPosition, geometryNormal, geometryViewDir, geometryClearcoatNormal, material, reflectedLight );
#endif`,M1=`#if defined( USE_LOGARITHMIC_DEPTH_BUFFER )
	gl_FragDepth = vIsPerspective == 0.0 ? gl_FragCoord.z : log2( vFragDepth ) * logDepthBufFC * 0.5;
#endif`,k1=`#if defined( USE_LOGARITHMIC_DEPTH_BUFFER )
	uniform float logDepthBufFC;
	varying float vFragDepth;
	varying float vIsPerspective;
#endif`,V1=`#ifdef USE_LOGARITHMIC_DEPTH_BUFFER
	varying float vFragDepth;
	varying float vIsPerspective;
#endif`,L1=`#ifdef USE_LOGARITHMIC_DEPTH_BUFFER
	vFragDepth = 1.0 + gl_Position.w;
	vIsPerspective = float( isPerspectiveMatrix( projectionMatrix ) );
#endif`,z1=`#ifdef USE_MAP
	vec4 sampledDiffuseColor = texture2D( map, vMapUv );
	#ifdef DECODE_VIDEO_TEXTURE
		sampledDiffuseColor = sRGBTransferEOTF( sampledDiffuseColor );
	#endif
	diffuseColor *= sampledDiffuseColor;
#endif`,B1=`#ifdef USE_MAP
	uniform sampler2D map;
#endif`,I1=`#if defined( USE_MAP ) || defined( USE_ALPHAMAP )
	#if defined( USE_POINTS_UV )
		vec2 uv = vUv;
	#else
		vec2 uv = ( uvTransform * vec3( gl_PointCoord.x, 1.0 - gl_PointCoord.y, 1 ) ).xy;
	#endif
#endif
#ifdef USE_MAP
	diffuseColor *= texture2D( map, uv );
#endif
#ifdef USE_ALPHAMAP
	diffuseColor.a *= texture2D( alphaMap, uv ).g;
#endif`,_1=`#if defined( USE_POINTS_UV )
	varying vec2 vUv;
#else
	#if defined( USE_MAP ) || defined( USE_ALPHAMAP )
		uniform mat3 uvTransform;
	#endif
#endif
#ifdef USE_MAP
	uniform sampler2D map;
#endif
#ifdef USE_ALPHAMAP
	uniform sampler2D alphaMap;
#endif`,w1=`float metalnessFactor = metalness;
#ifdef USE_METALNESSMAP
	vec4 texelMetalness = texture2D( metalnessMap, vMetalnessMapUv );
	metalnessFactor *= texelMetalness.b;
#endif`,C1=`#ifdef USE_METALNESSMAP
	uniform sampler2D metalnessMap;
#endif`,P1=`#ifdef USE_INSTANCING_MORPH
	float morphTargetInfluences[ MORPHTARGETS_COUNT ];
	float morphTargetBaseInfluence = texelFetch( morphTexture, ivec2( 0, gl_InstanceID ), 0 ).r;
	for ( int i = 0; i < MORPHTARGETS_COUNT; i ++ ) {
		morphTargetInfluences[i] =  texelFetch( morphTexture, ivec2( i + 1, gl_InstanceID ), 0 ).r;
	}
#endif`,A1=`#if defined( USE_MORPHCOLORS )
	vColor *= morphTargetBaseInfluence;
	for ( int i = 0; i < MORPHTARGETS_COUNT; i ++ ) {
		#if defined( USE_COLOR_ALPHA )
			if ( morphTargetInfluences[ i ] != 0.0 ) vColor += getMorph( gl_VertexID, i, 2 ) * morphTargetInfluences[ i ];
		#elif defined( USE_COLOR )
			if ( morphTargetInfluences[ i ] != 0.0 ) vColor += getMorph( gl_VertexID, i, 2 ).rgb * morphTargetInfluences[ i ];
		#endif
	}
#endif`,T1=`#ifdef USE_MORPHNORMALS
	objectNormal *= morphTargetBaseInfluence;
	for ( int i = 0; i < MORPHTARGETS_COUNT; i ++ ) {
		if ( morphTargetInfluences[ i ] != 0.0 ) objectNormal += getMorph( gl_VertexID, i, 1 ).xyz * morphTargetInfluences[ i ];
	}
#endif`,S1=`#ifdef USE_MORPHTARGETS
	#ifndef USE_INSTANCING_MORPH
		uniform float morphTargetBaseInfluence;
		uniform float morphTargetInfluences[ MORPHTARGETS_COUNT ];
	#endif
	uniform sampler2DArray morphTargetsTexture;
	uniform ivec2 morphTargetsTextureSize;
	vec4 getMorph( const in int vertexIndex, const in int morphTargetIndex, const in int offset ) {
		int texelIndex = vertexIndex * MORPHTARGETS_TEXTURE_STRIDE + offset;
		int y = texelIndex / morphTargetsTextureSize.x;
		int x = texelIndex - y * morphTargetsTextureSize.x;
		ivec3 morphUV = ivec3( x, y, morphTargetIndex );
		return texelFetch( morphTargetsTexture, morphUV, 0 );
	}
#endif`,j1=`#ifdef USE_MORPHTARGETS
	transformed *= morphTargetBaseInfluence;
	for ( int i = 0; i < MORPHTARGETS_COUNT; i ++ ) {
		if ( morphTargetInfluences[ i ] != 0.0 ) transformed += getMorph( gl_VertexID, i, 0 ).xyz * morphTargetInfluences[ i ];
	}
#endif`,y1=`float faceDirection = gl_FrontFacing ? 1.0 : - 1.0;
#ifdef FLAT_SHADED
	vec3 fdx = dFdx( vViewPosition );
	vec3 fdy = dFdy( vViewPosition );
	vec3 normal = normalize( cross( fdx, fdy ) );
#else
	vec3 normal = normalize( vNormal );
	#ifdef DOUBLE_SIDED
		normal *= faceDirection;
	#endif
#endif
#if defined( USE_NORMALMAP_TANGENTSPACE ) || defined( USE_CLEARCOAT_NORMALMAP ) || defined( USE_ANISOTROPY )
	#ifdef USE_TANGENT
		mat3 tbn = mat3( normalize( vTangent ), normalize( vBitangent ), normal );
	#else
		mat3 tbn = getTangentFrame( - vViewPosition, normal,
		#if defined( USE_NORMALMAP )
			vNormalMapUv
		#elif defined( USE_CLEARCOAT_NORMALMAP )
			vClearcoatNormalMapUv
		#else
			vUv
		#endif
		);
	#endif
	#if defined( DOUBLE_SIDED ) && ! defined( FLAT_SHADED )
		tbn[0] *= faceDirection;
		tbn[1] *= faceDirection;
	#endif
#endif
#ifdef USE_CLEARCOAT_NORMALMAP
	#ifdef USE_TANGENT
		mat3 tbn2 = mat3( normalize( vTangent ), normalize( vBitangent ), normal );
	#else
		mat3 tbn2 = getTangentFrame( - vViewPosition, normal, vClearcoatNormalMapUv );
	#endif
	#if defined( DOUBLE_SIDED ) && ! defined( FLAT_SHADED )
		tbn2[0] *= faceDirection;
		tbn2[1] *= faceDirection;
	#endif
#endif
vec3 nonPerturbedNormal = normal;`,v1=`#ifdef USE_NORMALMAP_OBJECTSPACE
	normal = texture2D( normalMap, vNormalMapUv ).xyz * 2.0 - 1.0;
	#ifdef FLIP_SIDED
		normal = - normal;
	#endif
	#ifdef DOUBLE_SIDED
		normal = normal * faceDirection;
	#endif
	normal = normalize( normalMatrix * normal );
#elif defined( USE_NORMALMAP_TANGENTSPACE )
	vec3 mapN = texture2D( normalMap, vNormalMapUv ).xyz * 2.0 - 1.0;
	mapN.xy *= normalScale;
	normal = normalize( tbn * mapN );
#elif defined( USE_BUMPMAP )
	normal = perturbNormalArb( - vViewPosition, normal, dHdxy_fwd(), faceDirection );
#endif`,f1=`#ifndef FLAT_SHADED
	varying vec3 vNormal;
	#ifdef USE_TANGENT
		varying vec3 vTangent;
		varying vec3 vBitangent;
	#endif
#endif`,b1=`#ifndef FLAT_SHADED
	varying vec3 vNormal;
	#ifdef USE_TANGENT
		varying vec3 vTangent;
		varying vec3 vBitangent;
	#endif
#endif`,h1=`#ifndef FLAT_SHADED
	vNormal = normalize( transformedNormal );
	#ifdef USE_TANGENT
		vTangent = normalize( transformedTangent );
		vBitangent = normalize( cross( vNormal, vTangent ) * tangent.w );
	#endif
#endif`,x1=`#ifdef USE_NORMALMAP
	uniform sampler2D normalMap;
	uniform vec2 normalScale;
#endif
#ifdef USE_NORMALMAP_OBJECTSPACE
	uniform mat3 normalMatrix;
#endif
#if ! defined ( USE_TANGENT ) && ( defined ( USE_NORMALMAP_TANGENTSPACE ) || defined ( USE_CLEARCOAT_NORMALMAP ) || defined( USE_ANISOTROPY ) )
	mat3 getTangentFrame( vec3 eye_pos, vec3 surf_norm, vec2 uv ) {
		vec3 q0 = dFdx( eye_pos.xyz );
		vec3 q1 = dFdy( eye_pos.xyz );
		vec2 st0 = dFdx( uv.st );
		vec2 st1 = dFdy( uv.st );
		vec3 N = surf_norm;
		vec3 q1perp = cross( q1, N );
		vec3 q0perp = cross( N, q0 );
		vec3 T = q1perp * st0.x + q0perp * st1.x;
		vec3 B = q1perp * st0.y + q0perp * st1.y;
		float det = max( dot( T, T ), dot( B, B ) );
		float scale = ( det == 0.0 ) ? 0.0 : inversesqrt( det );
		return mat3( T * scale, B * scale, N );
	}
#endif`,g1=`#ifdef USE_CLEARCOAT
	vec3 clearcoatNormal = nonPerturbedNormal;
#endif`,p1=`#ifdef USE_CLEARCOAT_NORMALMAP
	vec3 clearcoatMapN = texture2D( clearcoatNormalMap, vClearcoatNormalMapUv ).xyz * 2.0 - 1.0;
	clearcoatMapN.xy *= clearcoatNormalScale;
	clearcoatNormal = normalize( tbn2 * clearcoatMapN );
#endif`,m1=`#ifdef USE_CLEARCOATMAP
	uniform sampler2D clearcoatMap;
#endif
#ifdef USE_CLEARCOAT_NORMALMAP
	uniform sampler2D clearcoatNormalMap;
	uniform vec2 clearcoatNormalScale;
#endif
#ifdef USE_CLEARCOAT_ROUGHNESSMAP
	uniform sampler2D clearcoatRoughnessMap;
#endif`,d1=`#ifdef USE_IRIDESCENCEMAP
	uniform sampler2D iridescenceMap;
#endif
#ifdef USE_IRIDESCENCE_THICKNESSMAP
	uniform sampler2D iridescenceThicknessMap;
#endif`,l1=`#ifdef OPAQUE
diffuseColor.a = 1.0;
#endif
#ifdef USE_TRANSMISSION
diffuseColor.a *= material.transmissionAlpha;
#endif
gl_FragColor = vec4( outgoingLight, diffuseColor.a );`,u1=`vec3 packNormalToRGB( const in vec3 normal ) {
	return normalize( normal ) * 0.5 + 0.5;
}
vec3 unpackRGBToNormal( const in vec3 rgb ) {
	return 2.0 * rgb.xyz - 1.0;
}
const float PackUpscale = 256. / 255.;const float UnpackDownscale = 255. / 256.;const float ShiftRight8 = 1. / 256.;
const float Inv255 = 1. / 255.;
const vec4 PackFactors = vec4( 1.0, 256.0, 256.0 * 256.0, 256.0 * 256.0 * 256.0 );
const vec2 UnpackFactors2 = vec2( UnpackDownscale, 1.0 / PackFactors.g );
const vec3 UnpackFactors3 = vec3( UnpackDownscale / PackFactors.rg, 1.0 / PackFactors.b );
const vec4 UnpackFactors4 = vec4( UnpackDownscale / PackFactors.rgb, 1.0 / PackFactors.a );
vec4 packDepthToRGBA( const in float v ) {
	if( v <= 0.0 )
		return vec4( 0., 0., 0., 0. );
	if( v >= 1.0 )
		return vec4( 1., 1., 1., 1. );
	float vuf;
	float af = modf( v * PackFactors.a, vuf );
	float bf = modf( vuf * ShiftRight8, vuf );
	float gf = modf( vuf * ShiftRight8, vuf );
	return vec4( vuf * Inv255, gf * PackUpscale, bf * PackUpscale, af );
}
vec3 packDepthToRGB( const in float v ) {
	if( v <= 0.0 )
		return vec3( 0., 0., 0. );
	if( v >= 1.0 )
		return vec3( 1., 1., 1. );
	float vuf;
	float bf = modf( v * PackFactors.b, vuf );
	float gf = modf( vuf * ShiftRight8, vuf );
	return vec3( vuf * Inv255, gf * PackUpscale, bf );
}
vec2 packDepthToRG( const in float v ) {
	if( v <= 0.0 )
		return vec2( 0., 0. );
	if( v >= 1.0 )
		return vec2( 1., 1. );
	float vuf;
	float gf = modf( v * 256., vuf );
	return vec2( vuf * Inv255, gf );
}
float unpackRGBAToDepth( const in vec4 v ) {
	return dot( v, UnpackFactors4 );
}
float unpackRGBToDepth( const in vec3 v ) {
	return dot( v, UnpackFactors3 );
}
float unpackRGToDepth( const in vec2 v ) {
	return v.r * UnpackFactors2.r + v.g * UnpackFactors2.g;
}
vec4 pack2HalfToRGBA( const in vec2 v ) {
	vec4 r = vec4( v.x, fract( v.x * 255.0 ), v.y, fract( v.y * 255.0 ) );
	return vec4( r.x - r.y / 255.0, r.y, r.z - r.w / 255.0, r.w );
}
vec2 unpackRGBATo2Half( const in vec4 v ) {
	return vec2( v.x + ( v.y / 255.0 ), v.z + ( v.w / 255.0 ) );
}
float viewZToOrthographicDepth( const in float viewZ, const in float near, const in float far ) {
	return ( viewZ + near ) / ( near - far );
}
float orthographicDepthToViewZ( const in float depth, const in float near, const in float far ) {
	return depth * ( near - far ) - near;
}
float viewZToPerspectiveDepth( const in float viewZ, const in float near, const in float far ) {
	return ( ( near + viewZ ) * far ) / ( ( far - near ) * viewZ );
}
float perspectiveDepthToViewZ( const in float depth, const in float near, const in float far ) {
	return ( near * far ) / ( ( far - near ) * depth - far );
}`,c1=`#ifdef PREMULTIPLIED_ALPHA
	gl_FragColor.rgb *= gl_FragColor.a;
#endif`,n1=`vec4 mvPosition = vec4( transformed, 1.0 );
#ifdef USE_BATCHING
	mvPosition = batchingMatrix * mvPosition;
#endif
#ifdef USE_INSTANCING
	mvPosition = instanceMatrix * mvPosition;
#endif
mvPosition = modelViewMatrix * mvPosition;
gl_Position = projectionMatrix * mvPosition;`,s1=`#ifdef DITHERING
	gl_FragColor.rgb = dithering( gl_FragColor.rgb );
#endif`,i1=`#ifdef DITHERING
	vec3 dithering( vec3 color ) {
		float grid_position = rand( gl_FragCoord.xy );
		vec3 dither_shift_RGB = vec3( 0.25 / 255.0, -0.25 / 255.0, 0.25 / 255.0 );
		dither_shift_RGB = mix( 2.0 * dither_shift_RGB, -2.0 * dither_shift_RGB, grid_position );
		return color + dither_shift_RGB;
	}
#endif`,o1=`float roughnessFactor = roughness;
#ifdef USE_ROUGHNESSMAP
	vec4 texelRoughness = texture2D( roughnessMap, vRoughnessMapUv );
	roughnessFactor *= texelRoughness.g;
#endif`,a1=`#ifdef USE_ROUGHNESSMAP
	uniform sampler2D roughnessMap;
#endif`,r1=`#if NUM_SPOT_LIGHT_COORDS > 0
	varying vec4 vSpotLightCoord[ NUM_SPOT_LIGHT_COORDS ];
#endif
#if NUM_SPOT_LIGHT_MAPS > 0
	uniform sampler2D spotLightMap[ NUM_SPOT_LIGHT_MAPS ];
#endif
#ifdef USE_SHADOWMAP
	#if NUM_DIR_LIGHT_SHADOWS > 0
		uniform sampler2D directionalShadowMap[ NUM_DIR_LIGHT_SHADOWS ];
		varying vec4 vDirectionalShadowCoord[ NUM_DIR_LIGHT_SHADOWS ];
		struct DirectionalLightShadow {
			float shadowIntensity;
			float shadowBias;
			float shadowNormalBias;
			float shadowRadius;
			vec2 shadowMapSize;
		};
		uniform DirectionalLightShadow directionalLightShadows[ NUM_DIR_LIGHT_SHADOWS ];
	#endif
	#if NUM_SPOT_LIGHT_SHADOWS > 0
		uniform sampler2D spotShadowMap[ NUM_SPOT_LIGHT_SHADOWS ];
		struct SpotLightShadow {
			float shadowIntensity;
			float shadowBias;
			float shadowNormalBias;
			float shadowRadius;
			vec2 shadowMapSize;
		};
		uniform SpotLightShadow spotLightShadows[ NUM_SPOT_LIGHT_SHADOWS ];
	#endif
	#if NUM_POINT_LIGHT_SHADOWS > 0
		uniform sampler2D pointShadowMap[ NUM_POINT_LIGHT_SHADOWS ];
		varying vec4 vPointShadowCoord[ NUM_POINT_LIGHT_SHADOWS ];
		struct PointLightShadow {
			float shadowIntensity;
			float shadowBias;
			float shadowNormalBias;
			float shadowRadius;
			vec2 shadowMapSize;
			float shadowCameraNear;
			float shadowCameraFar;
		};
		uniform PointLightShadow pointLightShadows[ NUM_POINT_LIGHT_SHADOWS ];
	#endif
	float texture2DCompare( sampler2D depths, vec2 uv, float compare ) {
		float depth = unpackRGBAToDepth( texture2D( depths, uv ) );
		#ifdef USE_REVERSED_DEPTH_BUFFER
			return step( depth, compare );
		#else
			return step( compare, depth );
		#endif
	}
	vec2 texture2DDistribution( sampler2D shadow, vec2 uv ) {
		return unpackRGBATo2Half( texture2D( shadow, uv ) );
	}
	float VSMShadow( sampler2D shadow, vec2 uv, float compare ) {
		float occlusion = 1.0;
		vec2 distribution = texture2DDistribution( shadow, uv );
		#ifdef USE_REVERSED_DEPTH_BUFFER
			float hard_shadow = step( distribution.x, compare );
		#else
			float hard_shadow = step( compare, distribution.x );
		#endif
		if ( hard_shadow != 1.0 ) {
			float distance = compare - distribution.x;
			float variance = max( 0.00000, distribution.y * distribution.y );
			float softness_probability = variance / (variance + distance * distance );			softness_probability = clamp( ( softness_probability - 0.3 ) / ( 0.95 - 0.3 ), 0.0, 1.0 );			occlusion = clamp( max( hard_shadow, softness_probability ), 0.0, 1.0 );
		}
		return occlusion;
	}
	float getShadow( sampler2D shadowMap, vec2 shadowMapSize, float shadowIntensity, float shadowBias, float shadowRadius, vec4 shadowCoord ) {
		float shadow = 1.0;
		shadowCoord.xyz /= shadowCoord.w;
		shadowCoord.z += shadowBias;
		bool inFrustum = shadowCoord.x >= 0.0 && shadowCoord.x <= 1.0 && shadowCoord.y >= 0.0 && shadowCoord.y <= 1.0;
		bool frustumTest = inFrustum && shadowCoord.z <= 1.0;
		if ( frustumTest ) {
		#if defined( SHADOWMAP_TYPE_PCF )
			vec2 texelSize = vec2( 1.0 ) / shadowMapSize;
			float dx0 = - texelSize.x * shadowRadius;
			float dy0 = - texelSize.y * shadowRadius;
			float dx1 = + texelSize.x * shadowRadius;
			float dy1 = + texelSize.y * shadowRadius;
			float dx2 = dx0 / 2.0;
			float dy2 = dy0 / 2.0;
			float dx3 = dx1 / 2.0;
			float dy3 = dy1 / 2.0;
			shadow = (
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx0, dy0 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( 0.0, dy0 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx1, dy0 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx2, dy2 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( 0.0, dy2 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx3, dy2 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx0, 0.0 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx2, 0.0 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy, shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx3, 0.0 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx1, 0.0 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx2, dy3 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( 0.0, dy3 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx3, dy3 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx0, dy1 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( 0.0, dy1 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, shadowCoord.xy + vec2( dx1, dy1 ), shadowCoord.z )
			) * ( 1.0 / 17.0 );
		#elif defined( SHADOWMAP_TYPE_PCF_SOFT )
			vec2 texelSize = vec2( 1.0 ) / shadowMapSize;
			float dx = texelSize.x;
			float dy = texelSize.y;
			vec2 uv = shadowCoord.xy;
			vec2 f = fract( uv * shadowMapSize + 0.5 );
			uv -= f * texelSize;
			shadow = (
				texture2DCompare( shadowMap, uv, shadowCoord.z ) +
				texture2DCompare( shadowMap, uv + vec2( dx, 0.0 ), shadowCoord.z ) +
				texture2DCompare( shadowMap, uv + vec2( 0.0, dy ), shadowCoord.z ) +
				texture2DCompare( shadowMap, uv + texelSize, shadowCoord.z ) +
				mix( texture2DCompare( shadowMap, uv + vec2( -dx, 0.0 ), shadowCoord.z ),
					 texture2DCompare( shadowMap, uv + vec2( 2.0 * dx, 0.0 ), shadowCoord.z ),
					 f.x ) +
				mix( texture2DCompare( shadowMap, uv + vec2( -dx, dy ), shadowCoord.z ),
					 texture2DCompare( shadowMap, uv + vec2( 2.0 * dx, dy ), shadowCoord.z ),
					 f.x ) +
				mix( texture2DCompare( shadowMap, uv + vec2( 0.0, -dy ), shadowCoord.z ),
					 texture2DCompare( shadowMap, uv + vec2( 0.0, 2.0 * dy ), shadowCoord.z ),
					 f.y ) +
				mix( texture2DCompare( shadowMap, uv + vec2( dx, -dy ), shadowCoord.z ),
					 texture2DCompare( shadowMap, uv + vec2( dx, 2.0 * dy ), shadowCoord.z ),
					 f.y ) +
				mix( mix( texture2DCompare( shadowMap, uv + vec2( -dx, -dy ), shadowCoord.z ),
						  texture2DCompare( shadowMap, uv + vec2( 2.0 * dx, -dy ), shadowCoord.z ),
						  f.x ),
					 mix( texture2DCompare( shadowMap, uv + vec2( -dx, 2.0 * dy ), shadowCoord.z ),
						  texture2DCompare( shadowMap, uv + vec2( 2.0 * dx, 2.0 * dy ), shadowCoord.z ),
						  f.x ),
					 f.y )
			) * ( 1.0 / 9.0 );
		#elif defined( SHADOWMAP_TYPE_VSM )
			shadow = VSMShadow( shadowMap, shadowCoord.xy, shadowCoord.z );
		#else
			shadow = texture2DCompare( shadowMap, shadowCoord.xy, shadowCoord.z );
		#endif
		}
		return mix( 1.0, shadow, shadowIntensity );
	}
	vec2 cubeToUV( vec3 v, float texelSizeY ) {
		vec3 absV = abs( v );
		float scaleToCube = 1.0 / max( absV.x, max( absV.y, absV.z ) );
		absV *= scaleToCube;
		v *= scaleToCube * ( 1.0 - 2.0 * texelSizeY );
		vec2 planar = v.xy;
		float almostATexel = 1.5 * texelSizeY;
		float almostOne = 1.0 - almostATexel;
		if ( absV.z >= almostOne ) {
			if ( v.z > 0.0 )
				planar.x = 4.0 - v.x;
		} else if ( absV.x >= almostOne ) {
			float signX = sign( v.x );
			planar.x = v.z * signX + 2.0 * signX;
		} else if ( absV.y >= almostOne ) {
			float signY = sign( v.y );
			planar.x = v.x + 2.0 * signY + 2.0;
			planar.y = v.z * signY - 2.0;
		}
		return vec2( 0.125, 0.25 ) * planar + vec2( 0.375, 0.75 );
	}
	float getPointShadow( sampler2D shadowMap, vec2 shadowMapSize, float shadowIntensity, float shadowBias, float shadowRadius, vec4 shadowCoord, float shadowCameraNear, float shadowCameraFar ) {
		float shadow = 1.0;
		vec3 lightToPosition = shadowCoord.xyz;
		
		float lightToPositionLength = length( lightToPosition );
		if ( lightToPositionLength - shadowCameraFar <= 0.0 && lightToPositionLength - shadowCameraNear >= 0.0 ) {
			float dp = ( lightToPositionLength - shadowCameraNear ) / ( shadowCameraFar - shadowCameraNear );			dp += shadowBias;
			vec3 bd3D = normalize( lightToPosition );
			vec2 texelSize = vec2( 1.0 ) / ( shadowMapSize * vec2( 4.0, 2.0 ) );
			#if defined( SHADOWMAP_TYPE_PCF ) || defined( SHADOWMAP_TYPE_PCF_SOFT ) || defined( SHADOWMAP_TYPE_VSM )
				vec2 offset = vec2( - 1, 1 ) * shadowRadius * texelSize.y;
				shadow = (
					texture2DCompare( shadowMap, cubeToUV( bd3D + offset.xyy, texelSize.y ), dp ) +
					texture2DCompare( shadowMap, cubeToUV( bd3D + offset.yyy, texelSize.y ), dp ) +
					texture2DCompare( shadowMap, cubeToUV( bd3D + offset.xyx, texelSize.y ), dp ) +
					texture2DCompare( shadowMap, cubeToUV( bd3D + offset.yyx, texelSize.y ), dp ) +
					texture2DCompare( shadowMap, cubeToUV( bd3D, texelSize.y ), dp ) +
					texture2DCompare( shadowMap, cubeToUV( bd3D + offset.xxy, texelSize.y ), dp ) +
					texture2DCompare( shadowMap, cubeToUV( bd3D + offset.yxy, texelSize.y ), dp ) +
					texture2DCompare( shadowMap, cubeToUV( bd3D + offset.xxx, texelSize.y ), dp ) +
					texture2DCompare( shadowMap, cubeToUV( bd3D + offset.yxx, texelSize.y ), dp )
				) * ( 1.0 / 9.0 );
			#else
				shadow = texture2DCompare( shadowMap, cubeToUV( bd3D, texelSize.y ), dp );
			#endif
		}
		return mix( 1.0, shadow, shadowIntensity );
	}
#endif`,t1=`#if NUM_SPOT_LIGHT_COORDS > 0
	uniform mat4 spotLightMatrix[ NUM_SPOT_LIGHT_COORDS ];
	varying vec4 vSpotLightCoord[ NUM_SPOT_LIGHT_COORDS ];
#endif
#ifdef USE_SHADOWMAP
	#if NUM_DIR_LIGHT_SHADOWS > 0
		uniform mat4 directionalShadowMatrix[ NUM_DIR_LIGHT_SHADOWS ];
		varying vec4 vDirectionalShadowCoord[ NUM_DIR_LIGHT_SHADOWS ];
		struct DirectionalLightShadow {
			float shadowIntensity;
			float shadowBias;
			float shadowNormalBias;
			float shadowRadius;
			vec2 shadowMapSize;
		};
		uniform DirectionalLightShadow directionalLightShadows[ NUM_DIR_LIGHT_SHADOWS ];
	#endif
	#if NUM_SPOT_LIGHT_SHADOWS > 0
		struct SpotLightShadow {
			float shadowIntensity;
			float shadowBias;
			float shadowNormalBias;
			float shadowRadius;
			vec2 shadowMapSize;
		};
		uniform SpotLightShadow spotLightShadows[ NUM_SPOT_LIGHT_SHADOWS ];
	#endif
	#if NUM_POINT_LIGHT_SHADOWS > 0
		uniform mat4 pointShadowMatrix[ NUM_POINT_LIGHT_SHADOWS ];
		varying vec4 vPointShadowCoord[ NUM_POINT_LIGHT_SHADOWS ];
		struct PointLightShadow {
			float shadowIntensity;
			float shadowBias;
			float shadowNormalBias;
			float shadowRadius;
			vec2 shadowMapSize;
			float shadowCameraNear;
			float shadowCameraFar;
		};
		uniform PointLightShadow pointLightShadows[ NUM_POINT_LIGHT_SHADOWS ];
	#endif
#endif`,e1=`#if ( defined( USE_SHADOWMAP ) && ( NUM_DIR_LIGHT_SHADOWS > 0 || NUM_POINT_LIGHT_SHADOWS > 0 ) ) || ( NUM_SPOT_LIGHT_COORDS > 0 )
	vec3 shadowWorldNormal = inverseTransformDirection( transformedNormal, viewMatrix );
	vec4 shadowWorldPosition;
#endif
#if defined( USE_SHADOWMAP )
	#if NUM_DIR_LIGHT_SHADOWS > 0
		#pragma unroll_loop_start
		for ( int i = 0; i < NUM_DIR_LIGHT_SHADOWS; i ++ ) {
			shadowWorldPosition = worldPosition + vec4( shadowWorldNormal * directionalLightShadows[ i ].shadowNormalBias, 0 );
			vDirectionalShadowCoord[ i ] = directionalShadowMatrix[ i ] * shadowWorldPosition;
		}
		#pragma unroll_loop_end
	#endif
	#if NUM_POINT_LIGHT_SHADOWS > 0
		#pragma unroll_loop_start
		for ( int i = 0; i < NUM_POINT_LIGHT_SHADOWS; i ++ ) {
			shadowWorldPosition = worldPosition + vec4( shadowWorldNormal * pointLightShadows[ i ].shadowNormalBias, 0 );
			vPointShadowCoord[ i ] = pointShadowMatrix[ i ] * shadowWorldPosition;
		}
		#pragma unroll_loop_end
	#endif
#endif
#if NUM_SPOT_LIGHT_COORDS > 0
	#pragma unroll_loop_start
	for ( int i = 0; i < NUM_SPOT_LIGHT_COORDS; i ++ ) {
		shadowWorldPosition = worldPosition;
		#if ( defined( USE_SHADOWMAP ) && UNROLLED_LOOP_INDEX < NUM_SPOT_LIGHT_SHADOWS )
			shadowWorldPosition.xyz += shadowWorldNormal * spotLightShadows[ i ].shadowNormalBias;
		#endif
		vSpotLightCoord[ i ] = spotLightMatrix[ i ] * shadowWorldPosition;
	}
	#pragma unroll_loop_end
#endif`,Jq=`float getShadowMask() {
	float shadow = 1.0;
	#ifdef USE_SHADOWMAP
	#if NUM_DIR_LIGHT_SHADOWS > 0
	DirectionalLightShadow directionalLight;
	#pragma unroll_loop_start
	for ( int i = 0; i < NUM_DIR_LIGHT_SHADOWS; i ++ ) {
		directionalLight = directionalLightShadows[ i ];
		shadow *= receiveShadow ? getShadow( directionalShadowMap[ i ], directionalLight.shadowMapSize, directionalLight.shadowIntensity, directionalLight.shadowBias, directionalLight.shadowRadius, vDirectionalShadowCoord[ i ] ) : 1.0;
	}
	#pragma unroll_loop_end
	#endif
	#if NUM_SPOT_LIGHT_SHADOWS > 0
	SpotLightShadow spotLight;
	#pragma unroll_loop_start
	for ( int i = 0; i < NUM_SPOT_LIGHT_SHADOWS; i ++ ) {
		spotLight = spotLightShadows[ i ];
		shadow *= receiveShadow ? getShadow( spotShadowMap[ i ], spotLight.shadowMapSize, spotLight.shadowIntensity, spotLight.shadowBias, spotLight.shadowRadius, vSpotLightCoord[ i ] ) : 1.0;
	}
	#pragma unroll_loop_end
	#endif
	#if NUM_POINT_LIGHT_SHADOWS > 0
	PointLightShadow pointLight;
	#pragma unroll_loop_start
	for ( int i = 0; i < NUM_POINT_LIGHT_SHADOWS; i ++ ) {
		pointLight = pointLightShadows[ i ];
		shadow *= receiveShadow ? getPointShadow( pointShadowMap[ i ], pointLight.shadowMapSize, pointLight.shadowIntensity, pointLight.shadowBias, pointLight.shadowRadius, vPointShadowCoord[ i ], pointLight.shadowCameraNear, pointLight.shadowCameraFar ) : 1.0;
	}
	#pragma unroll_loop_end
	#endif
	#endif
	return shadow;
}`,Qq=`#ifdef USE_SKINNING
	mat4 boneMatX = getBoneMatrix( skinIndex.x );
	mat4 boneMatY = getBoneMatrix( skinIndex.y );
	mat4 boneMatZ = getBoneMatrix( skinIndex.z );
	mat4 boneMatW = getBoneMatrix( skinIndex.w );
#endif`,$q=`#ifdef USE_SKINNING
	uniform mat4 bindMatrix;
	uniform mat4 bindMatrixInverse;
	uniform highp sampler2D boneTexture;
	mat4 getBoneMatrix( const in float i ) {
		int size = textureSize( boneTexture, 0 ).x;
		int j = int( i ) * 4;
		int x = j % size;
		int y = j / size;
		vec4 v1 = texelFetch( boneTexture, ivec2( x, y ), 0 );
		vec4 v2 = texelFetch( boneTexture, ivec2( x + 1, y ), 0 );
		vec4 v3 = texelFetch( boneTexture, ivec2( x + 2, y ), 0 );
		vec4 v4 = texelFetch( boneTexture, ivec2( x + 3, y ), 0 );
		return mat4( v1, v2, v3, v4 );
	}
#endif`,Zq=`#ifdef USE_SKINNING
	vec4 skinVertex = bindMatrix * vec4( transformed, 1.0 );
	vec4 skinned = vec4( 0.0 );
	skinned += boneMatX * skinVertex * skinWeight.x;
	skinned += boneMatY * skinVertex * skinWeight.y;
	skinned += boneMatZ * skinVertex * skinWeight.z;
	skinned += boneMatW * skinVertex * skinWeight.w;
	transformed = ( bindMatrixInverse * skinned ).xyz;
#endif`,Wq=`#ifdef USE_SKINNING
	mat4 skinMatrix = mat4( 0.0 );
	skinMatrix += skinWeight.x * boneMatX;
	skinMatrix += skinWeight.y * boneMatY;
	skinMatrix += skinWeight.z * boneMatZ;
	skinMatrix += skinWeight.w * boneMatW;
	skinMatrix = bindMatrixInverse * skinMatrix * bindMatrix;
	objectNormal = vec4( skinMatrix * vec4( objectNormal, 0.0 ) ).xyz;
	#ifdef USE_TANGENT
		objectTangent = vec4( skinMatrix * vec4( objectTangent, 0.0 ) ).xyz;
	#endif
#endif`,Kq=`float specularStrength;
#ifdef USE_SPECULARMAP
	vec4 texelSpecular = texture2D( specularMap, vSpecularMapUv );
	specularStrength = texelSpecular.r;
#else
	specularStrength = 1.0;
#endif`,Hq=`#ifdef USE_SPECULARMAP
	uniform sampler2D specularMap;
#endif`,Yq=`#if defined( TONE_MAPPING )
	gl_FragColor.rgb = toneMapping( gl_FragColor.rgb );
#endif`,Xq=`#ifndef saturate
#define saturate( a ) clamp( a, 0.0, 1.0 )
#endif
uniform float toneMappingExposure;
vec3 LinearToneMapping( vec3 color ) {
	return saturate( toneMappingExposure * color );
}
vec3 ReinhardToneMapping( vec3 color ) {
	color *= toneMappingExposure;
	return saturate( color / ( vec3( 1.0 ) + color ) );
}
vec3 CineonToneMapping( vec3 color ) {
	color *= toneMappingExposure;
	color = max( vec3( 0.0 ), color - 0.004 );
	return pow( ( color * ( 6.2 * color + 0.5 ) ) / ( color * ( 6.2 * color + 1.7 ) + 0.06 ), vec3( 2.2 ) );
}
vec3 RRTAndODTFit( vec3 v ) {
	vec3 a = v * ( v + 0.0245786 ) - 0.000090537;
	vec3 b = v * ( 0.983729 * v + 0.4329510 ) + 0.238081;
	return a / b;
}
vec3 ACESFilmicToneMapping( vec3 color ) {
	const mat3 ACESInputMat = mat3(
		vec3( 0.59719, 0.07600, 0.02840 ),		vec3( 0.35458, 0.90834, 0.13383 ),
		vec3( 0.04823, 0.01566, 0.83777 )
	);
	const mat3 ACESOutputMat = mat3(
		vec3(  1.60475, -0.10208, -0.00327 ),		vec3( -0.53108,  1.10813, -0.07276 ),
		vec3( -0.07367, -0.00605,  1.07602 )
	);
	color *= toneMappingExposure / 0.6;
	color = ACESInputMat * color;
	color = RRTAndODTFit( color );
	color = ACESOutputMat * color;
	return saturate( color );
}
const mat3 LINEAR_REC2020_TO_LINEAR_SRGB = mat3(
	vec3( 1.6605, - 0.1246, - 0.0182 ),
	vec3( - 0.5876, 1.1329, - 0.1006 ),
	vec3( - 0.0728, - 0.0083, 1.1187 )
);
const mat3 LINEAR_SRGB_TO_LINEAR_REC2020 = mat3(
	vec3( 0.6274, 0.0691, 0.0164 ),
	vec3( 0.3293, 0.9195, 0.0880 ),
	vec3( 0.0433, 0.0113, 0.8956 )
);
vec3 agxDefaultContrastApprox( vec3 x ) {
	vec3 x2 = x * x;
	vec3 x4 = x2 * x2;
	return + 15.5 * x4 * x2
		- 40.14 * x4 * x
		+ 31.96 * x4
		- 6.868 * x2 * x
		+ 0.4298 * x2
		+ 0.1191 * x
		- 0.00232;
}
vec3 AgXToneMapping( vec3 color ) {
	const mat3 AgXInsetMatrix = mat3(
		vec3( 0.856627153315983, 0.137318972929847, 0.11189821299995 ),
		vec3( 0.0951212405381588, 0.761241990602591, 0.0767994186031903 ),
		vec3( 0.0482516061458583, 0.101439036467562, 0.811302368396859 )
	);
	const mat3 AgXOutsetMatrix = mat3(
		vec3( 1.1271005818144368, - 0.1413297634984383, - 0.14132976349843826 ),
		vec3( - 0.11060664309660323, 1.157823702216272, - 0.11060664309660294 ),
		vec3( - 0.016493938717834573, - 0.016493938717834257, 1.2519364065950405 )
	);
	const float AgxMinEv = - 12.47393;	const float AgxMaxEv = 4.026069;
	color *= toneMappingExposure;
	color = LINEAR_SRGB_TO_LINEAR_REC2020 * color;
	color = AgXInsetMatrix * color;
	color = max( color, 1e-10 );	color = log2( color );
	color = ( color - AgxMinEv ) / ( AgxMaxEv - AgxMinEv );
	color = clamp( color, 0.0, 1.0 );
	color = agxDefaultContrastApprox( color );
	color = AgXOutsetMatrix * color;
	color = pow( max( vec3( 0.0 ), color ), vec3( 2.2 ) );
	color = LINEAR_REC2020_TO_LINEAR_SRGB * color;
	color = clamp( color, 0.0, 1.0 );
	return color;
}
vec3 NeutralToneMapping( vec3 color ) {
	const float StartCompression = 0.8 - 0.04;
	const float Desaturation = 0.15;
	color *= toneMappingExposure;
	float x = min( color.r, min( color.g, color.b ) );
	float offset = x < 0.08 ? x - 6.25 * x * x : 0.04;
	color -= offset;
	float peak = max( color.r, max( color.g, color.b ) );
	if ( peak < StartCompression ) return color;
	float d = 1. - StartCompression;
	float newPeak = 1. - d * d / ( peak + d - StartCompression );
	color *= newPeak / peak;
	float g = 1. - 1. / ( Desaturation * ( peak - newPeak ) + 1. );
	return mix( color, vec3( newPeak ), g );
}
vec3 CustomToneMapping( vec3 color ) { return color; }`,Uq=`#ifdef USE_TRANSMISSION
	material.transmission = transmission;
	material.transmissionAlpha = 1.0;
	material.thickness = thickness;
	material.attenuationDistance = attenuationDistance;
	material.attenuationColor = attenuationColor;
	#ifdef USE_TRANSMISSIONMAP
		material.transmission *= texture2D( transmissionMap, vTransmissionMapUv ).r;
	#endif
	#ifdef USE_THICKNESSMAP
		material.thickness *= texture2D( thicknessMap, vThicknessMapUv ).g;
	#endif
	vec3 pos = vWorldPosition;
	vec3 v = normalize( cameraPosition - pos );
	vec3 n = inverseTransformDirection( normal, viewMatrix );
	vec4 transmitted = getIBLVolumeRefraction(
		n, v, material.roughness, material.diffuseColor, material.specularColor, material.specularF90,
		pos, modelMatrix, viewMatrix, projectionMatrix, material.dispersion, material.ior, material.thickness,
		material.attenuationColor, material.attenuationDistance );
	material.transmissionAlpha = mix( material.transmissionAlpha, transmitted.a, material.transmission );
	totalDiffuse = mix( totalDiffuse, transmitted.rgb, material.transmission );
#endif`,Gq=`#ifdef USE_TRANSMISSION
	uniform float transmission;
	uniform float thickness;
	uniform float attenuationDistance;
	uniform vec3 attenuationColor;
	#ifdef USE_TRANSMISSIONMAP
		uniform sampler2D transmissionMap;
	#endif
	#ifdef USE_THICKNESSMAP
		uniform sampler2D thicknessMap;
	#endif
	uniform vec2 transmissionSamplerSize;
	uniform sampler2D transmissionSamplerMap;
	uniform mat4 modelMatrix;
	uniform mat4 projectionMatrix;
	varying vec3 vWorldPosition;
	float w0( float a ) {
		return ( 1.0 / 6.0 ) * ( a * ( a * ( - a + 3.0 ) - 3.0 ) + 1.0 );
	}
	float w1( float a ) {
		return ( 1.0 / 6.0 ) * ( a *  a * ( 3.0 * a - 6.0 ) + 4.0 );
	}
	float w2( float a ){
		return ( 1.0 / 6.0 ) * ( a * ( a * ( - 3.0 * a + 3.0 ) + 3.0 ) + 1.0 );
	}
	float w3( float a ) {
		return ( 1.0 / 6.0 ) * ( a * a * a );
	}
	float g0( float a ) {
		return w0( a ) + w1( a );
	}
	float g1( float a ) {
		return w2( a ) + w3( a );
	}
	float h0( float a ) {
		return - 1.0 + w1( a ) / ( w0( a ) + w1( a ) );
	}
	float h1( float a ) {
		return 1.0 + w3( a ) / ( w2( a ) + w3( a ) );
	}
	vec4 bicubic( sampler2D tex, vec2 uv, vec4 texelSize, float lod ) {
		uv = uv * texelSize.zw + 0.5;
		vec2 iuv = floor( uv );
		vec2 fuv = fract( uv );
		float g0x = g0( fuv.x );
		float g1x = g1( fuv.x );
		float h0x = h0( fuv.x );
		float h1x = h1( fuv.x );
		float h0y = h0( fuv.y );
		float h1y = h1( fuv.y );
		vec2 p0 = ( vec2( iuv.x + h0x, iuv.y + h0y ) - 0.5 ) * texelSize.xy;
		vec2 p1 = ( vec2( iuv.x + h1x, iuv.y + h0y ) - 0.5 ) * texelSize.xy;
		vec2 p2 = ( vec2( iuv.x + h0x, iuv.y + h1y ) - 0.5 ) * texelSize.xy;
		vec2 p3 = ( vec2( iuv.x + h1x, iuv.y + h1y ) - 0.5 ) * texelSize.xy;
		return g0( fuv.y ) * ( g0x * textureLod( tex, p0, lod ) + g1x * textureLod( tex, p1, lod ) ) +
			g1( fuv.y ) * ( g0x * textureLod( tex, p2, lod ) + g1x * textureLod( tex, p3, lod ) );
	}
	vec4 textureBicubic( sampler2D sampler, vec2 uv, float lod ) {
		vec2 fLodSize = vec2( textureSize( sampler, int( lod ) ) );
		vec2 cLodSize = vec2( textureSize( sampler, int( lod + 1.0 ) ) );
		vec2 fLodSizeInv = 1.0 / fLodSize;
		vec2 cLodSizeInv = 1.0 / cLodSize;
		vec4 fSample = bicubic( sampler, uv, vec4( fLodSizeInv, fLodSize ), floor( lod ) );
		vec4 cSample = bicubic( sampler, uv, vec4( cLodSizeInv, cLodSize ), ceil( lod ) );
		return mix( fSample, cSample, fract( lod ) );
	}
	vec3 getVolumeTransmissionRay( const in vec3 n, const in vec3 v, const in float thickness, const in float ior, const in mat4 modelMatrix ) {
		vec3 refractionVector = refract( - v, normalize( n ), 1.0 / ior );
		vec3 modelScale;
		modelScale.x = length( vec3( modelMatrix[ 0 ].xyz ) );
		modelScale.y = length( vec3( modelMatrix[ 1 ].xyz ) );
		modelScale.z = length( vec3( modelMatrix[ 2 ].xyz ) );
		return normalize( refractionVector ) * thickness * modelScale;
	}
	float applyIorToRoughness( const in float roughness, const in float ior ) {
		return roughness * clamp( ior * 2.0 - 2.0, 0.0, 1.0 );
	}
	vec4 getTransmissionSample( const in vec2 fragCoord, const in float roughness, const in float ior ) {
		float lod = log2( transmissionSamplerSize.x ) * applyIorToRoughness( roughness, ior );
		return textureBicubic( transmissionSamplerMap, fragCoord.xy, lod );
	}
	vec3 volumeAttenuation( const in float transmissionDistance, const in vec3 attenuationColor, const in float attenuationDistance ) {
		if ( isinf( attenuationDistance ) ) {
			return vec3( 1.0 );
		} else {
			vec3 attenuationCoefficient = -log( attenuationColor ) / attenuationDistance;
			vec3 transmittance = exp( - attenuationCoefficient * transmissionDistance );			return transmittance;
		}
	}
	vec4 getIBLVolumeRefraction( const in vec3 n, const in vec3 v, const in float roughness, const in vec3 diffuseColor,
		const in vec3 specularColor, const in float specularF90, const in vec3 position, const in mat4 modelMatrix,
		const in mat4 viewMatrix, const in mat4 projMatrix, const in float dispersion, const in float ior, const in float thickness,
		const in vec3 attenuationColor, const in float attenuationDistance ) {
		vec4 transmittedLight;
		vec3 transmittance;
		#ifdef USE_DISPERSION
			float halfSpread = ( ior - 1.0 ) * 0.025 * dispersion;
			vec3 iors = vec3( ior - halfSpread, ior, ior + halfSpread );
			for ( int i = 0; i < 3; i ++ ) {
				vec3 transmissionRay = getVolumeTransmissionRay( n, v, thickness, iors[ i ], modelMatrix );
				vec3 refractedRayExit = position + transmissionRay;
				vec4 ndcPos = projMatrix * viewMatrix * vec4( refractedRayExit, 1.0 );
				vec2 refractionCoords = ndcPos.xy / ndcPos.w;
				refractionCoords += 1.0;
				refractionCoords /= 2.0;
				vec4 transmissionSample = getTransmissionSample( refractionCoords, roughness, iors[ i ] );
				transmittedLight[ i ] = transmissionSample[ i ];
				transmittedLight.a += transmissionSample.a;
				transmittance[ i ] = diffuseColor[ i ] * volumeAttenuation( length( transmissionRay ), attenuationColor, attenuationDistance )[ i ];
			}
			transmittedLight.a /= 3.0;
		#else
			vec3 transmissionRay = getVolumeTransmissionRay( n, v, thickness, ior, modelMatrix );
			vec3 refractedRayExit = position + transmissionRay;
			vec4 ndcPos = projMatrix * viewMatrix * vec4( refractedRayExit, 1.0 );
			vec2 refractionCoords = ndcPos.xy / ndcPos.w;
			refractionCoords += 1.0;
			refractionCoords /= 2.0;
			transmittedLight = getTransmissionSample( refractionCoords, roughness, ior );
			transmittance = diffuseColor * volumeAttenuation( length( transmissionRay ), attenuationColor, attenuationDistance );
		#endif
		vec3 attenuatedColor = transmittance * transmittedLight.rgb;
		vec3 F = EnvironmentBRDF( n, v, specularColor, specularF90, roughness );
		float transmittanceFactor = ( transmittance.r + transmittance.g + transmittance.b ) / 3.0;
		return vec4( ( 1.0 - F ) * attenuatedColor, 1.0 - ( 1.0 - transmittedLight.a ) * transmittanceFactor );
	}
#endif`,Eq=`#if defined( USE_UV ) || defined( USE_ANISOTROPY )
	varying vec2 vUv;
#endif
#ifdef USE_MAP
	varying vec2 vMapUv;
#endif
#ifdef USE_ALPHAMAP
	varying vec2 vAlphaMapUv;
#endif
#ifdef USE_LIGHTMAP
	varying vec2 vLightMapUv;
#endif
#ifdef USE_AOMAP
	varying vec2 vAoMapUv;
#endif
#ifdef USE_BUMPMAP
	varying vec2 vBumpMapUv;
#endif
#ifdef USE_NORMALMAP
	varying vec2 vNormalMapUv;
#endif
#ifdef USE_EMISSIVEMAP
	varying vec2 vEmissiveMapUv;
#endif
#ifdef USE_METALNESSMAP
	varying vec2 vMetalnessMapUv;
#endif
#ifdef USE_ROUGHNESSMAP
	varying vec2 vRoughnessMapUv;
#endif
#ifdef USE_ANISOTROPYMAP
	varying vec2 vAnisotropyMapUv;
#endif
#ifdef USE_CLEARCOATMAP
	varying vec2 vClearcoatMapUv;
#endif
#ifdef USE_CLEARCOAT_NORMALMAP
	varying vec2 vClearcoatNormalMapUv;
#endif
#ifdef USE_CLEARCOAT_ROUGHNESSMAP
	varying vec2 vClearcoatRoughnessMapUv;
#endif
#ifdef USE_IRIDESCENCEMAP
	varying vec2 vIridescenceMapUv;
#endif
#ifdef USE_IRIDESCENCE_THICKNESSMAP
	varying vec2 vIridescenceThicknessMapUv;
#endif
#ifdef USE_SHEEN_COLORMAP
	varying vec2 vSheenColorMapUv;
#endif
#ifdef USE_SHEEN_ROUGHNESSMAP
	varying vec2 vSheenRoughnessMapUv;
#endif
#ifdef USE_SPECULARMAP
	varying vec2 vSpecularMapUv;
#endif
#ifdef USE_SPECULAR_COLORMAP
	varying vec2 vSpecularColorMapUv;
#endif
#ifdef USE_SPECULAR_INTENSITYMAP
	varying vec2 vSpecularIntensityMapUv;
#endif
#ifdef USE_TRANSMISSIONMAP
	uniform mat3 transmissionMapTransform;
	varying vec2 vTransmissionMapUv;
#endif
#ifdef USE_THICKNESSMAP
	uniform mat3 thicknessMapTransform;
	varying vec2 vThicknessMapUv;
#endif`,Nq=`#if defined( USE_UV ) || defined( USE_ANISOTROPY )
	varying vec2 vUv;
#endif
#ifdef USE_MAP
	uniform mat3 mapTransform;
	varying vec2 vMapUv;
#endif
#ifdef USE_ALPHAMAP
	uniform mat3 alphaMapTransform;
	varying vec2 vAlphaMapUv;
#endif
#ifdef USE_LIGHTMAP
	uniform mat3 lightMapTransform;
	varying vec2 vLightMapUv;
#endif
#ifdef USE_AOMAP
	uniform mat3 aoMapTransform;
	varying vec2 vAoMapUv;
#endif
#ifdef USE_BUMPMAP
	uniform mat3 bumpMapTransform;
	varying vec2 vBumpMapUv;
#endif
#ifdef USE_NORMALMAP
	uniform mat3 normalMapTransform;
	varying vec2 vNormalMapUv;
#endif
#ifdef USE_DISPLACEMENTMAP
	uniform mat3 displacementMapTransform;
	varying vec2 vDisplacementMapUv;
#endif
#ifdef USE_EMISSIVEMAP
	uniform mat3 emissiveMapTransform;
	varying vec2 vEmissiveMapUv;
#endif
#ifdef USE_METALNESSMAP
	uniform mat3 metalnessMapTransform;
	varying vec2 vMetalnessMapUv;
#endif
#ifdef USE_ROUGHNESSMAP
	uniform mat3 roughnessMapTransform;
	varying vec2 vRoughnessMapUv;
#endif
#ifdef USE_ANISOTROPYMAP
	uniform mat3 anisotropyMapTransform;
	varying vec2 vAnisotropyMapUv;
#endif
#ifdef USE_CLEARCOATMAP
	uniform mat3 clearcoatMapTransform;
	varying vec2 vClearcoatMapUv;
#endif
#ifdef USE_CLEARCOAT_NORMALMAP
	uniform mat3 clearcoatNormalMapTransform;
	varying vec2 vClearcoatNormalMapUv;
#endif
#ifdef USE_CLEARCOAT_ROUGHNESSMAP
	uniform mat3 clearcoatRoughnessMapTransform;
	varying vec2 vClearcoatRoughnessMapUv;
#endif
#ifdef USE_SHEEN_COLORMAP
	uniform mat3 sheenColorMapTransform;
	varying vec2 vSheenColorMapUv;
#endif
#ifdef USE_SHEEN_ROUGHNESSMAP
	uniform mat3 sheenRoughnessMapTransform;
	varying vec2 vSheenRoughnessMapUv;
#endif
#ifdef USE_IRIDESCENCEMAP
	uniform mat3 iridescenceMapTransform;
	varying vec2 vIridescenceMapUv;
#endif
#ifdef USE_IRIDESCENCE_THICKNESSMAP
	uniform mat3 iridescenceThicknessMapTransform;
	varying vec2 vIridescenceThicknessMapUv;
#endif
#ifdef USE_SPECULARMAP
	uniform mat3 specularMapTransform;
	varying vec2 vSpecularMapUv;
#endif
#ifdef USE_SPECULAR_COLORMAP
	uniform mat3 specularColorMapTransform;
	varying vec2 vSpecularColorMapUv;
#endif
#ifdef USE_SPECULAR_INTENSITYMAP
	uniform mat3 specularIntensityMapTransform;
	varying vec2 vSpecularIntensityMapUv;
#endif
#ifdef USE_TRANSMISSIONMAP
	uniform mat3 transmissionMapTransform;
	varying vec2 vTransmissionMapUv;
#endif
#ifdef USE_THICKNESSMAP
	uniform mat3 thicknessMapTransform;
	varying vec2 vThicknessMapUv;
#endif`,qq=`#if defined( USE_UV ) || defined( USE_ANISOTROPY )
	vUv = vec3( uv, 1 ).xy;
#endif
#ifdef USE_MAP
	vMapUv = ( mapTransform * vec3( MAP_UV, 1 ) ).xy;
#endif
#ifdef USE_ALPHAMAP
	vAlphaMapUv = ( alphaMapTransform * vec3( ALPHAMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_LIGHTMAP
	vLightMapUv = ( lightMapTransform * vec3( LIGHTMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_AOMAP
	vAoMapUv = ( aoMapTransform * vec3( AOMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_BUMPMAP
	vBumpMapUv = ( bumpMapTransform * vec3( BUMPMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_NORMALMAP
	vNormalMapUv = ( normalMapTransform * vec3( NORMALMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_DISPLACEMENTMAP
	vDisplacementMapUv = ( displacementMapTransform * vec3( DISPLACEMENTMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_EMISSIVEMAP
	vEmissiveMapUv = ( emissiveMapTransform * vec3( EMISSIVEMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_METALNESSMAP
	vMetalnessMapUv = ( metalnessMapTransform * vec3( METALNESSMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_ROUGHNESSMAP
	vRoughnessMapUv = ( roughnessMapTransform * vec3( ROUGHNESSMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_ANISOTROPYMAP
	vAnisotropyMapUv = ( anisotropyMapTransform * vec3( ANISOTROPYMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_CLEARCOATMAP
	vClearcoatMapUv = ( clearcoatMapTransform * vec3( CLEARCOATMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_CLEARCOAT_NORMALMAP
	vClearcoatNormalMapUv = ( clearcoatNormalMapTransform * vec3( CLEARCOAT_NORMALMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_CLEARCOAT_ROUGHNESSMAP
	vClearcoatRoughnessMapUv = ( clearcoatRoughnessMapTransform * vec3( CLEARCOAT_ROUGHNESSMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_IRIDESCENCEMAP
	vIridescenceMapUv = ( iridescenceMapTransform * vec3( IRIDESCENCEMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_IRIDESCENCE_THICKNESSMAP
	vIridescenceThicknessMapUv = ( iridescenceThicknessMapTransform * vec3( IRIDESCENCE_THICKNESSMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_SHEEN_COLORMAP
	vSheenColorMapUv = ( sheenColorMapTransform * vec3( SHEEN_COLORMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_SHEEN_ROUGHNESSMAP
	vSheenRoughnessMapUv = ( sheenRoughnessMapTransform * vec3( SHEEN_ROUGHNESSMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_SPECULARMAP
	vSpecularMapUv = ( specularMapTransform * vec3( SPECULARMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_SPECULAR_COLORMAP
	vSpecularColorMapUv = ( specularColorMapTransform * vec3( SPECULAR_COLORMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_SPECULAR_INTENSITYMAP
	vSpecularIntensityMapUv = ( specularIntensityMapTransform * vec3( SPECULAR_INTENSITYMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_TRANSMISSIONMAP
	vTransmissionMapUv = ( transmissionMapTransform * vec3( TRANSMISSIONMAP_UV, 1 ) ).xy;
#endif
#ifdef USE_THICKNESSMAP
	vThicknessMapUv = ( thicknessMapTransform * vec3( THICKNESSMAP_UV, 1 ) ).xy;
#endif`,Dq=`#if defined( USE_ENVMAP ) || defined( DISTANCE ) || defined ( USE_SHADOWMAP ) || defined ( USE_TRANSMISSION ) || NUM_SPOT_LIGHT_COORDS > 0
	vec4 worldPosition = vec4( transformed, 1.0 );
	#ifdef USE_BATCHING
		worldPosition = batchingMatrix * worldPosition;
	#endif
	#ifdef USE_INSTANCING
		worldPosition = instanceMatrix * worldPosition;
	#endif
	worldPosition = modelMatrix * worldPosition;
#endif`,Oq=`varying vec2 vUv;
uniform mat3 uvTransform;
void main() {
	vUv = ( uvTransform * vec3( uv, 1 ) ).xy;
	gl_Position = vec4( position.xy, 1.0, 1.0 );
}`,Rq=`uniform sampler2D t2D;
uniform float backgroundIntensity;
varying vec2 vUv;
void main() {
	vec4 texColor = texture2D( t2D, vUv );
	#ifdef DECODE_VIDEO_TEXTURE
		texColor = vec4( mix( pow( texColor.rgb * 0.9478672986 + vec3( 0.0521327014 ), vec3( 2.4 ) ), texColor.rgb * 0.0773993808, vec3( lessThanEqual( texColor.rgb, vec3( 0.04045 ) ) ) ), texColor.w );
	#endif
	texColor.rgb *= backgroundIntensity;
	gl_FragColor = texColor;
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
}`,Fq=`varying vec3 vWorldDirection;
#include <common>
void main() {
	vWorldDirection = transformDirection( position, modelMatrix );
	#include <begin_vertex>
	#include <project_vertex>
	gl_Position.z = gl_Position.w;
}`,Mq=`#ifdef ENVMAP_TYPE_CUBE
	uniform samplerCube envMap;
#elif defined( ENVMAP_TYPE_CUBE_UV )
	uniform sampler2D envMap;
#endif
uniform float flipEnvMap;
uniform float backgroundBlurriness;
uniform float backgroundIntensity;
uniform mat3 backgroundRotation;
varying vec3 vWorldDirection;
#include <cube_uv_reflection_fragment>
void main() {
	#ifdef ENVMAP_TYPE_CUBE
		vec4 texColor = textureCube( envMap, backgroundRotation * vec3( flipEnvMap * vWorldDirection.x, vWorldDirection.yz ) );
	#elif defined( ENVMAP_TYPE_CUBE_UV )
		vec4 texColor = textureCubeUV( envMap, backgroundRotation * vWorldDirection, backgroundBlurriness );
	#else
		vec4 texColor = vec4( 0.0, 0.0, 0.0, 1.0 );
	#endif
	texColor.rgb *= backgroundIntensity;
	gl_FragColor = texColor;
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
}`,kq=`varying vec3 vWorldDirection;
#include <common>
void main() {
	vWorldDirection = transformDirection( position, modelMatrix );
	#include <begin_vertex>
	#include <project_vertex>
	gl_Position.z = gl_Position.w;
}`,Vq=`uniform samplerCube tCube;
uniform float tFlip;
uniform float opacity;
varying vec3 vWorldDirection;
void main() {
	vec4 texColor = textureCube( tCube, vec3( tFlip * vWorldDirection.x, vWorldDirection.yz ) );
	gl_FragColor = texColor;
	gl_FragColor.a *= opacity;
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
}`,Lq=`#include <common>
#include <batching_pars_vertex>
#include <uv_pars_vertex>
#include <displacementmap_pars_vertex>
#include <morphtarget_pars_vertex>
#include <skinning_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <clipping_planes_pars_vertex>
varying vec2 vHighPrecisionZW;
void main() {
	#include <uv_vertex>
	#include <batching_vertex>
	#include <skinbase_vertex>
	#include <morphinstance_vertex>
	#ifdef USE_DISPLACEMENTMAP
		#include <beginnormal_vertex>
		#include <morphnormal_vertex>
		#include <skinnormal_vertex>
	#endif
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <skinning_vertex>
	#include <displacementmap_vertex>
	#include <project_vertex>
	#include <logdepthbuf_vertex>
	#include <clipping_planes_vertex>
	vHighPrecisionZW = gl_Position.zw;
}`,zq=`#if DEPTH_PACKING == 3200
	uniform float opacity;
#endif
#include <common>
#include <packing>
#include <uv_pars_fragment>
#include <map_pars_fragment>
#include <alphamap_pars_fragment>
#include <alphatest_pars_fragment>
#include <alphahash_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>
varying vec2 vHighPrecisionZW;
void main() {
	vec4 diffuseColor = vec4( 1.0 );
	#include <clipping_planes_fragment>
	#if DEPTH_PACKING == 3200
		diffuseColor.a = opacity;
	#endif
	#include <map_fragment>
	#include <alphamap_fragment>
	#include <alphatest_fragment>
	#include <alphahash_fragment>
	#include <logdepthbuf_fragment>
	#ifdef USE_REVERSED_DEPTH_BUFFER
		float fragCoordZ = vHighPrecisionZW[ 0 ] / vHighPrecisionZW[ 1 ];
	#else
		float fragCoordZ = 0.5 * vHighPrecisionZW[ 0 ] / vHighPrecisionZW[ 1 ] + 0.5;
	#endif
	#if DEPTH_PACKING == 3200
		gl_FragColor = vec4( vec3( 1.0 - fragCoordZ ), opacity );
	#elif DEPTH_PACKING == 3201
		gl_FragColor = packDepthToRGBA( fragCoordZ );
	#elif DEPTH_PACKING == 3202
		gl_FragColor = vec4( packDepthToRGB( fragCoordZ ), 1.0 );
	#elif DEPTH_PACKING == 3203
		gl_FragColor = vec4( packDepthToRG( fragCoordZ ), 0.0, 1.0 );
	#endif
}`,Bq=`#define DISTANCE
varying vec3 vWorldPosition;
#include <common>
#include <batching_pars_vertex>
#include <uv_pars_vertex>
#include <displacementmap_pars_vertex>
#include <morphtarget_pars_vertex>
#include <skinning_pars_vertex>
#include <clipping_planes_pars_vertex>
void main() {
	#include <uv_vertex>
	#include <batching_vertex>
	#include <skinbase_vertex>
	#include <morphinstance_vertex>
	#ifdef USE_DISPLACEMENTMAP
		#include <beginnormal_vertex>
		#include <morphnormal_vertex>
		#include <skinnormal_vertex>
	#endif
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <skinning_vertex>
	#include <displacementmap_vertex>
	#include <project_vertex>
	#include <worldpos_vertex>
	#include <clipping_planes_vertex>
	vWorldPosition = worldPosition.xyz;
}`,Iq=`#define DISTANCE
uniform vec3 referencePosition;
uniform float nearDistance;
uniform float farDistance;
varying vec3 vWorldPosition;
#include <common>
#include <packing>
#include <uv_pars_fragment>
#include <map_pars_fragment>
#include <alphamap_pars_fragment>
#include <alphatest_pars_fragment>
#include <alphahash_pars_fragment>
#include <clipping_planes_pars_fragment>
void main () {
	vec4 diffuseColor = vec4( 1.0 );
	#include <clipping_planes_fragment>
	#include <map_fragment>
	#include <alphamap_fragment>
	#include <alphatest_fragment>
	#include <alphahash_fragment>
	float dist = length( vWorldPosition - referencePosition );
	dist = ( dist - nearDistance ) / ( farDistance - nearDistance );
	dist = saturate( dist );
	gl_FragColor = packDepthToRGBA( dist );
}`,_q=`varying vec3 vWorldDirection;
#include <common>
void main() {
	vWorldDirection = transformDirection( position, modelMatrix );
	#include <begin_vertex>
	#include <project_vertex>
}`,wq=`uniform sampler2D tEquirect;
varying vec3 vWorldDirection;
#include <common>
void main() {
	vec3 direction = normalize( vWorldDirection );
	vec2 sampleUV = equirectUv( direction );
	gl_FragColor = texture2D( tEquirect, sampleUV );
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
}`,Cq=`uniform float scale;
attribute float lineDistance;
varying float vLineDistance;
#include <common>
#include <uv_pars_vertex>
#include <color_pars_vertex>
#include <fog_pars_vertex>
#include <morphtarget_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <clipping_planes_pars_vertex>
void main() {
	vLineDistance = scale * lineDistance;
	#include <uv_vertex>
	#include <color_vertex>
	#include <morphinstance_vertex>
	#include <morphcolor_vertex>
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <project_vertex>
	#include <logdepthbuf_vertex>
	#include <clipping_planes_vertex>
	#include <fog_vertex>
}`,Pq=`uniform vec3 diffuse;
uniform float opacity;
uniform float dashSize;
uniform float totalSize;
varying float vLineDistance;
#include <common>
#include <color_pars_fragment>
#include <uv_pars_fragment>
#include <map_pars_fragment>
#include <fog_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>
void main() {
	vec4 diffuseColor = vec4( diffuse, opacity );
	#include <clipping_planes_fragment>
	if ( mod( vLineDistance, totalSize ) > dashSize ) {
		discard;
	}
	vec3 outgoingLight = vec3( 0.0 );
	#include <logdepthbuf_fragment>
	#include <map_fragment>
	#include <color_fragment>
	outgoingLight = diffuseColor.rgb;
	#include <opaque_fragment>
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
	#include <fog_fragment>
	#include <premultiplied_alpha_fragment>
}`,Aq=`#include <common>
#include <batching_pars_vertex>
#include <uv_pars_vertex>
#include <envmap_pars_vertex>
#include <color_pars_vertex>
#include <fog_pars_vertex>
#include <morphtarget_pars_vertex>
#include <skinning_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <clipping_planes_pars_vertex>
void main() {
	#include <uv_vertex>
	#include <color_vertex>
	#include <morphinstance_vertex>
	#include <morphcolor_vertex>
	#include <batching_vertex>
	#if defined ( USE_ENVMAP ) || defined ( USE_SKINNING )
		#include <beginnormal_vertex>
		#include <morphnormal_vertex>
		#include <skinbase_vertex>
		#include <skinnormal_vertex>
		#include <defaultnormal_vertex>
	#endif
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <skinning_vertex>
	#include <project_vertex>
	#include <logdepthbuf_vertex>
	#include <clipping_planes_vertex>
	#include <worldpos_vertex>
	#include <envmap_vertex>
	#include <fog_vertex>
}`,Tq=`uniform vec3 diffuse;
uniform float opacity;
#ifndef FLAT_SHADED
	varying vec3 vNormal;
#endif
#include <common>
#include <dithering_pars_fragment>
#include <color_pars_fragment>
#include <uv_pars_fragment>
#include <map_pars_fragment>
#include <alphamap_pars_fragment>
#include <alphatest_pars_fragment>
#include <alphahash_pars_fragment>
#include <aomap_pars_fragment>
#include <lightmap_pars_fragment>
#include <envmap_common_pars_fragment>
#include <envmap_pars_fragment>
#include <fog_pars_fragment>
#include <specularmap_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>
void main() {
	vec4 diffuseColor = vec4( diffuse, opacity );
	#include <clipping_planes_fragment>
	#include <logdepthbuf_fragment>
	#include <map_fragment>
	#include <color_fragment>
	#include <alphamap_fragment>
	#include <alphatest_fragment>
	#include <alphahash_fragment>
	#include <specularmap_fragment>
	ReflectedLight reflectedLight = ReflectedLight( vec3( 0.0 ), vec3( 0.0 ), vec3( 0.0 ), vec3( 0.0 ) );
	#ifdef USE_LIGHTMAP
		vec4 lightMapTexel = texture2D( lightMap, vLightMapUv );
		reflectedLight.indirectDiffuse += lightMapTexel.rgb * lightMapIntensity * RECIPROCAL_PI;
	#else
		reflectedLight.indirectDiffuse += vec3( 1.0 );
	#endif
	#include <aomap_fragment>
	reflectedLight.indirectDiffuse *= diffuseColor.rgb;
	vec3 outgoingLight = reflectedLight.indirectDiffuse;
	#include <envmap_fragment>
	#include <opaque_fragment>
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
	#include <fog_fragment>
	#include <premultiplied_alpha_fragment>
	#include <dithering_fragment>
}`,Sq=`#define LAMBERT
varying vec3 vViewPosition;
#include <common>
#include <batching_pars_vertex>
#include <uv_pars_vertex>
#include <displacementmap_pars_vertex>
#include <envmap_pars_vertex>
#include <color_pars_vertex>
#include <fog_pars_vertex>
#include <normal_pars_vertex>
#include <morphtarget_pars_vertex>
#include <skinning_pars_vertex>
#include <shadowmap_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <clipping_planes_pars_vertex>
void main() {
	#include <uv_vertex>
	#include <color_vertex>
	#include <morphinstance_vertex>
	#include <morphcolor_vertex>
	#include <batching_vertex>
	#include <beginnormal_vertex>
	#include <morphnormal_vertex>
	#include <skinbase_vertex>
	#include <skinnormal_vertex>
	#include <defaultnormal_vertex>
	#include <normal_vertex>
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <skinning_vertex>
	#include <displacementmap_vertex>
	#include <project_vertex>
	#include <logdepthbuf_vertex>
	#include <clipping_planes_vertex>
	vViewPosition = - mvPosition.xyz;
	#include <worldpos_vertex>
	#include <envmap_vertex>
	#include <shadowmap_vertex>
	#include <fog_vertex>
}`,jq=`#define LAMBERT
uniform vec3 diffuse;
uniform vec3 emissive;
uniform float opacity;
#include <common>
#include <packing>
#include <dithering_pars_fragment>
#include <color_pars_fragment>
#include <uv_pars_fragment>
#include <map_pars_fragment>
#include <alphamap_pars_fragment>
#include <alphatest_pars_fragment>
#include <alphahash_pars_fragment>
#include <aomap_pars_fragment>
#include <lightmap_pars_fragment>
#include <emissivemap_pars_fragment>
#include <envmap_common_pars_fragment>
#include <envmap_pars_fragment>
#include <fog_pars_fragment>
#include <bsdfs>
#include <lights_pars_begin>
#include <normal_pars_fragment>
#include <lights_lambert_pars_fragment>
#include <shadowmap_pars_fragment>
#include <bumpmap_pars_fragment>
#include <normalmap_pars_fragment>
#include <specularmap_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>
void main() {
	vec4 diffuseColor = vec4( diffuse, opacity );
	#include <clipping_planes_fragment>
	ReflectedLight reflectedLight = ReflectedLight( vec3( 0.0 ), vec3( 0.0 ), vec3( 0.0 ), vec3( 0.0 ) );
	vec3 totalEmissiveRadiance = emissive;
	#include <logdepthbuf_fragment>
	#include <map_fragment>
	#include <color_fragment>
	#include <alphamap_fragment>
	#include <alphatest_fragment>
	#include <alphahash_fragment>
	#include <specularmap_fragment>
	#include <normal_fragment_begin>
	#include <normal_fragment_maps>
	#include <emissivemap_fragment>
	#include <lights_lambert_fragment>
	#include <lights_fragment_begin>
	#include <lights_fragment_maps>
	#include <lights_fragment_end>
	#include <aomap_fragment>
	vec3 outgoingLight = reflectedLight.directDiffuse + reflectedLight.indirectDiffuse + totalEmissiveRadiance;
	#include <envmap_fragment>
	#include <opaque_fragment>
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
	#include <fog_fragment>
	#include <premultiplied_alpha_fragment>
	#include <dithering_fragment>
}`,yq=`#define MATCAP
varying vec3 vViewPosition;
#include <common>
#include <batching_pars_vertex>
#include <uv_pars_vertex>
#include <color_pars_vertex>
#include <displacementmap_pars_vertex>
#include <fog_pars_vertex>
#include <normal_pars_vertex>
#include <morphtarget_pars_vertex>
#include <skinning_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <clipping_planes_pars_vertex>
void main() {
	#include <uv_vertex>
	#include <color_vertex>
	#include <morphinstance_vertex>
	#include <morphcolor_vertex>
	#include <batching_vertex>
	#include <beginnormal_vertex>
	#include <morphnormal_vertex>
	#include <skinbase_vertex>
	#include <skinnormal_vertex>
	#include <defaultnormal_vertex>
	#include <normal_vertex>
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <skinning_vertex>
	#include <displacementmap_vertex>
	#include <project_vertex>
	#include <logdepthbuf_vertex>
	#include <clipping_planes_vertex>
	#include <fog_vertex>
	vViewPosition = - mvPosition.xyz;
}`,vq=`#define MATCAP
uniform vec3 diffuse;
uniform float opacity;
uniform sampler2D matcap;
varying vec3 vViewPosition;
#include <common>
#include <dithering_pars_fragment>
#include <color_pars_fragment>
#include <uv_pars_fragment>
#include <map_pars_fragment>
#include <alphamap_pars_fragment>
#include <alphatest_pars_fragment>
#include <alphahash_pars_fragment>
#include <fog_pars_fragment>
#include <normal_pars_fragment>
#include <bumpmap_pars_fragment>
#include <normalmap_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>
void main() {
	vec4 diffuseColor = vec4( diffuse, opacity );
	#include <clipping_planes_fragment>
	#include <logdepthbuf_fragment>
	#include <map_fragment>
	#include <color_fragment>
	#include <alphamap_fragment>
	#include <alphatest_fragment>
	#include <alphahash_fragment>
	#include <normal_fragment_begin>
	#include <normal_fragment_maps>
	vec3 viewDir = normalize( vViewPosition );
	vec3 x = normalize( vec3( viewDir.z, 0.0, - viewDir.x ) );
	vec3 y = cross( viewDir, x );
	vec2 uv = vec2( dot( x, normal ), dot( y, normal ) ) * 0.495 + 0.5;
	#ifdef USE_MATCAP
		vec4 matcapColor = texture2D( matcap, uv );
	#else
		vec4 matcapColor = vec4( vec3( mix( 0.2, 0.8, uv.y ) ), 1.0 );
	#endif
	vec3 outgoingLight = diffuseColor.rgb * matcapColor.rgb;
	#include <opaque_fragment>
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
	#include <fog_fragment>
	#include <premultiplied_alpha_fragment>
	#include <dithering_fragment>
}`,fq=`#define NORMAL
#if defined( FLAT_SHADED ) || defined( USE_BUMPMAP ) || defined( USE_NORMALMAP_TANGENTSPACE )
	varying vec3 vViewPosition;
#endif
#include <common>
#include <batching_pars_vertex>
#include <uv_pars_vertex>
#include <displacementmap_pars_vertex>
#include <normal_pars_vertex>
#include <morphtarget_pars_vertex>
#include <skinning_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <clipping_planes_pars_vertex>
void main() {
	#include <uv_vertex>
	#include <batching_vertex>
	#include <beginnormal_vertex>
	#include <morphinstance_vertex>
	#include <morphnormal_vertex>
	#include <skinbase_vertex>
	#include <skinnormal_vertex>
	#include <defaultnormal_vertex>
	#include <normal_vertex>
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <skinning_vertex>
	#include <displacementmap_vertex>
	#include <project_vertex>
	#include <logdepthbuf_vertex>
	#include <clipping_planes_vertex>
#if defined( FLAT_SHADED ) || defined( USE_BUMPMAP ) || defined( USE_NORMALMAP_TANGENTSPACE )
	vViewPosition = - mvPosition.xyz;
#endif
}`,bq=`#define NORMAL
uniform float opacity;
#if defined( FLAT_SHADED ) || defined( USE_BUMPMAP ) || defined( USE_NORMALMAP_TANGENTSPACE )
	varying vec3 vViewPosition;
#endif
#include <packing>
#include <uv_pars_fragment>
#include <normal_pars_fragment>
#include <bumpmap_pars_fragment>
#include <normalmap_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>
void main() {
	vec4 diffuseColor = vec4( 0.0, 0.0, 0.0, opacity );
	#include <clipping_planes_fragment>
	#include <logdepthbuf_fragment>
	#include <normal_fragment_begin>
	#include <normal_fragment_maps>
	gl_FragColor = vec4( packNormalToRGB( normal ), diffuseColor.a );
	#ifdef OPAQUE
		gl_FragColor.a = 1.0;
	#endif
}`,hq=`#define PHONG
varying vec3 vViewPosition;
#include <common>
#include <batching_pars_vertex>
#include <uv_pars_vertex>
#include <displacementmap_pars_vertex>
#include <envmap_pars_vertex>
#include <color_pars_vertex>
#include <fog_pars_vertex>
#include <normal_pars_vertex>
#include <morphtarget_pars_vertex>
#include <skinning_pars_vertex>
#include <shadowmap_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <clipping_planes_pars_vertex>
void main() {
	#include <uv_vertex>
	#include <color_vertex>
	#include <morphcolor_vertex>
	#include <batching_vertex>
	#include <beginnormal_vertex>
	#include <morphinstance_vertex>
	#include <morphnormal_vertex>
	#include <skinbase_vertex>
	#include <skinnormal_vertex>
	#include <defaultnormal_vertex>
	#include <normal_vertex>
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <skinning_vertex>
	#include <displacementmap_vertex>
	#include <project_vertex>
	#include <logdepthbuf_vertex>
	#include <clipping_planes_vertex>
	vViewPosition = - mvPosition.xyz;
	#include <worldpos_vertex>
	#include <envmap_vertex>
	#include <shadowmap_vertex>
	#include <fog_vertex>
}`,xq=`#define PHONG
uniform vec3 diffuse;
uniform vec3 emissive;
uniform vec3 specular;
uniform float shininess;
uniform float opacity;
#include <common>
#include <packing>
#include <dithering_pars_fragment>
#include <color_pars_fragment>
#include <uv_pars_fragment>
#include <map_pars_fragment>
#include <alphamap_pars_fragment>
#include <alphatest_pars_fragment>
#include <alphahash_pars_fragment>
#include <aomap_pars_fragment>
#include <lightmap_pars_fragment>
#include <emissivemap_pars_fragment>
#include <envmap_common_pars_fragment>
#include <envmap_pars_fragment>
#include <fog_pars_fragment>
#include <bsdfs>
#include <lights_pars_begin>
#include <normal_pars_fragment>
#include <lights_phong_pars_fragment>
#include <shadowmap_pars_fragment>
#include <bumpmap_pars_fragment>
#include <normalmap_pars_fragment>
#include <specularmap_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>
void main() {
	vec4 diffuseColor = vec4( diffuse, opacity );
	#include <clipping_planes_fragment>
	ReflectedLight reflectedLight = ReflectedLight( vec3( 0.0 ), vec3( 0.0 ), vec3( 0.0 ), vec3( 0.0 ) );
	vec3 totalEmissiveRadiance = emissive;
	#include <logdepthbuf_fragment>
	#include <map_fragment>
	#include <color_fragment>
	#include <alphamap_fragment>
	#include <alphatest_fragment>
	#include <alphahash_fragment>
	#include <specularmap_fragment>
	#include <normal_fragment_begin>
	#include <normal_fragment_maps>
	#include <emissivemap_fragment>
	#include <lights_phong_fragment>
	#include <lights_fragment_begin>
	#include <lights_fragment_maps>
	#include <lights_fragment_end>
	#include <aomap_fragment>
	vec3 outgoingLight = reflectedLight.directDiffuse + reflectedLight.indirectDiffuse + reflectedLight.directSpecular + reflectedLight.indirectSpecular + totalEmissiveRadiance;
	#include <envmap_fragment>
	#include <opaque_fragment>
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
	#include <fog_fragment>
	#include <premultiplied_alpha_fragment>
	#include <dithering_fragment>
}`,gq=`#define STANDARD
varying vec3 vViewPosition;
#ifdef USE_TRANSMISSION
	varying vec3 vWorldPosition;
#endif
#include <common>
#include <batching_pars_vertex>
#include <uv_pars_vertex>
#include <displacementmap_pars_vertex>
#include <color_pars_vertex>
#include <fog_pars_vertex>
#include <normal_pars_vertex>
#include <morphtarget_pars_vertex>
#include <skinning_pars_vertex>
#include <shadowmap_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <clipping_planes_pars_vertex>
void main() {
	#include <uv_vertex>
	#include <color_vertex>
	#include <morphinstance_vertex>
	#include <morphcolor_vertex>
	#include <batching_vertex>
	#include <beginnormal_vertex>
	#include <morphnormal_vertex>
	#include <skinbase_vertex>
	#include <skinnormal_vertex>
	#include <defaultnormal_vertex>
	#include <normal_vertex>
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <skinning_vertex>
	#include <displacementmap_vertex>
	#include <project_vertex>
	#include <logdepthbuf_vertex>
	#include <clipping_planes_vertex>
	vViewPosition = - mvPosition.xyz;
	#include <worldpos_vertex>
	#include <shadowmap_vertex>
	#include <fog_vertex>
#ifdef USE_TRANSMISSION
	vWorldPosition = worldPosition.xyz;
#endif
}`,pq=`#define STANDARD
#ifdef PHYSICAL
	#define IOR
	#define USE_SPECULAR
#endif
uniform vec3 diffuse;
uniform vec3 emissive;
uniform float roughness;
uniform float metalness;
uniform float opacity;
#ifdef IOR
	uniform float ior;
#endif
#ifdef USE_SPECULAR
	uniform float specularIntensity;
	uniform vec3 specularColor;
	#ifdef USE_SPECULAR_COLORMAP
		uniform sampler2D specularColorMap;
	#endif
	#ifdef USE_SPECULAR_INTENSITYMAP
		uniform sampler2D specularIntensityMap;
	#endif
#endif
#ifdef USE_CLEARCOAT
	uniform float clearcoat;
	uniform float clearcoatRoughness;
#endif
#ifdef USE_DISPERSION
	uniform float dispersion;
#endif
#ifdef USE_IRIDESCENCE
	uniform float iridescence;
	uniform float iridescenceIOR;
	uniform float iridescenceThicknessMinimum;
	uniform float iridescenceThicknessMaximum;
#endif
#ifdef USE_SHEEN
	uniform vec3 sheenColor;
	uniform float sheenRoughness;
	#ifdef USE_SHEEN_COLORMAP
		uniform sampler2D sheenColorMap;
	#endif
	#ifdef USE_SHEEN_ROUGHNESSMAP
		uniform sampler2D sheenRoughnessMap;
	#endif
#endif
#ifdef USE_ANISOTROPY
	uniform vec2 anisotropyVector;
	#ifdef USE_ANISOTROPYMAP
		uniform sampler2D anisotropyMap;
	#endif
#endif
varying vec3 vViewPosition;
#include <common>
#include <packing>
#include <dithering_pars_fragment>
#include <color_pars_fragment>
#include <uv_pars_fragment>
#include <map_pars_fragment>
#include <alphamap_pars_fragment>
#include <alphatest_pars_fragment>
#include <alphahash_pars_fragment>
#include <aomap_pars_fragment>
#include <lightmap_pars_fragment>
#include <emissivemap_pars_fragment>
#include <iridescence_fragment>
#include <cube_uv_reflection_fragment>
#include <envmap_common_pars_fragment>
#include <envmap_physical_pars_fragment>
#include <fog_pars_fragment>
#include <lights_pars_begin>
#include <normal_pars_fragment>
#include <lights_physical_pars_fragment>
#include <transmission_pars_fragment>
#include <shadowmap_pars_fragment>
#include <bumpmap_pars_fragment>
#include <normalmap_pars_fragment>
#include <clearcoat_pars_fragment>
#include <iridescence_pars_fragment>
#include <roughnessmap_pars_fragment>
#include <metalnessmap_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>
void main() {
	vec4 diffuseColor = vec4( diffuse, opacity );
	#include <clipping_planes_fragment>
	ReflectedLight reflectedLight = ReflectedLight( vec3( 0.0 ), vec3( 0.0 ), vec3( 0.0 ), vec3( 0.0 ) );
	vec3 totalEmissiveRadiance = emissive;
	#include <logdepthbuf_fragment>
	#include <map_fragment>
	#include <color_fragment>
	#include <alphamap_fragment>
	#include <alphatest_fragment>
	#include <alphahash_fragment>
	#include <roughnessmap_fragment>
	#include <metalnessmap_fragment>
	#include <normal_fragment_begin>
	#include <normal_fragment_maps>
	#include <clearcoat_normal_fragment_begin>
	#include <clearcoat_normal_fragment_maps>
	#include <emissivemap_fragment>
	#include <lights_physical_fragment>
	#include <lights_fragment_begin>
	#include <lights_fragment_maps>
	#include <lights_fragment_end>
	#include <aomap_fragment>
	vec3 totalDiffuse = reflectedLight.directDiffuse + reflectedLight.indirectDiffuse;
	vec3 totalSpecular = reflectedLight.directSpecular + reflectedLight.indirectSpecular;
	#include <transmission_fragment>
	vec3 outgoingLight = totalDiffuse + totalSpecular + totalEmissiveRadiance;
	#ifdef USE_SHEEN
		float sheenEnergyComp = 1.0 - 0.157 * max3( material.sheenColor );
		outgoingLight = outgoingLight * sheenEnergyComp + sheenSpecularDirect + sheenSpecularIndirect;
	#endif
	#ifdef USE_CLEARCOAT
		float dotNVcc = saturate( dot( geometryClearcoatNormal, geometryViewDir ) );
		vec3 Fcc = F_Schlick( material.clearcoatF0, material.clearcoatF90, dotNVcc );
		outgoingLight = outgoingLight * ( 1.0 - material.clearcoat * Fcc ) + ( clearcoatSpecularDirect + clearcoatSpecularIndirect ) * material.clearcoat;
	#endif
	#include <opaque_fragment>
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
	#include <fog_fragment>
	#include <premultiplied_alpha_fragment>
	#include <dithering_fragment>
}`,mq=`#define TOON
varying vec3 vViewPosition;
#include <common>
#include <batching_pars_vertex>
#include <uv_pars_vertex>
#include <displacementmap_pars_vertex>
#include <color_pars_vertex>
#include <fog_pars_vertex>
#include <normal_pars_vertex>
#include <morphtarget_pars_vertex>
#include <skinning_pars_vertex>
#include <shadowmap_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <clipping_planes_pars_vertex>
void main() {
	#include <uv_vertex>
	#include <color_vertex>
	#include <morphinstance_vertex>
	#include <morphcolor_vertex>
	#include <batching_vertex>
	#include <beginnormal_vertex>
	#include <morphnormal_vertex>
	#include <skinbase_vertex>
	#include <skinnormal_vertex>
	#include <defaultnormal_vertex>
	#include <normal_vertex>
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <skinning_vertex>
	#include <displacementmap_vertex>
	#include <project_vertex>
	#include <logdepthbuf_vertex>
	#include <clipping_planes_vertex>
	vViewPosition = - mvPosition.xyz;
	#include <worldpos_vertex>
	#include <shadowmap_vertex>
	#include <fog_vertex>
}`,dq=`#define TOON
uniform vec3 diffuse;
uniform vec3 emissive;
uniform float opacity;
#include <common>
#include <packing>
#include <dithering_pars_fragment>
#include <color_pars_fragment>
#include <uv_pars_fragment>
#include <map_pars_fragment>
#include <alphamap_pars_fragment>
#include <alphatest_pars_fragment>
#include <alphahash_pars_fragment>
#include <aomap_pars_fragment>
#include <lightmap_pars_fragment>
#include <emissivemap_pars_fragment>
#include <gradientmap_pars_fragment>
#include <fog_pars_fragment>
#include <bsdfs>
#include <lights_pars_begin>
#include <normal_pars_fragment>
#include <lights_toon_pars_fragment>
#include <shadowmap_pars_fragment>
#include <bumpmap_pars_fragment>
#include <normalmap_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>
void main() {
	vec4 diffuseColor = vec4( diffuse, opacity );
	#include <clipping_planes_fragment>
	ReflectedLight reflectedLight = ReflectedLight( vec3( 0.0 ), vec3( 0.0 ), vec3( 0.0 ), vec3( 0.0 ) );
	vec3 totalEmissiveRadiance = emissive;
	#include <logdepthbuf_fragment>
	#include <map_fragment>
	#include <color_fragment>
	#include <alphamap_fragment>
	#include <alphatest_fragment>
	#include <alphahash_fragment>
	#include <normal_fragment_begin>
	#include <normal_fragment_maps>
	#include <emissivemap_fragment>
	#include <lights_toon_fragment>
	#include <lights_fragment_begin>
	#include <lights_fragment_maps>
	#include <lights_fragment_end>
	#include <aomap_fragment>
	vec3 outgoingLight = reflectedLight.directDiffuse + reflectedLight.indirectDiffuse + totalEmissiveRadiance;
	#include <opaque_fragment>
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
	#include <fog_fragment>
	#include <premultiplied_alpha_fragment>
	#include <dithering_fragment>
}`,lq=`uniform float size;
uniform float scale;
#include <common>
#include <color_pars_vertex>
#include <fog_pars_vertex>
#include <morphtarget_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <clipping_planes_pars_vertex>
#ifdef USE_POINTS_UV
	varying vec2 vUv;
	uniform mat3 uvTransform;
#endif
void main() {
	#ifdef USE_POINTS_UV
		vUv = ( uvTransform * vec3( uv, 1 ) ).xy;
	#endif
	#include <color_vertex>
	#include <morphinstance_vertex>
	#include <morphcolor_vertex>
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <project_vertex>
	gl_PointSize = size;
	#ifdef USE_SIZEATTENUATION
		bool isPerspective = isPerspectiveMatrix( projectionMatrix );
		if ( isPerspective ) gl_PointSize *= ( scale / - mvPosition.z );
	#endif
	#include <logdepthbuf_vertex>
	#include <clipping_planes_vertex>
	#include <worldpos_vertex>
	#include <fog_vertex>
}`,uq=`uniform vec3 diffuse;
uniform float opacity;
#include <common>
#include <color_pars_fragment>
#include <map_particle_pars_fragment>
#include <alphatest_pars_fragment>
#include <alphahash_pars_fragment>
#include <fog_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>
void main() {
	vec4 diffuseColor = vec4( diffuse, opacity );
	#include <clipping_planes_fragment>
	vec3 outgoingLight = vec3( 0.0 );
	#include <logdepthbuf_fragment>
	#include <map_particle_fragment>
	#include <color_fragment>
	#include <alphatest_fragment>
	#include <alphahash_fragment>
	outgoingLight = diffuseColor.rgb;
	#include <opaque_fragment>
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
	#include <fog_fragment>
	#include <premultiplied_alpha_fragment>
}`,cq=`#include <common>
#include <batching_pars_vertex>
#include <fog_pars_vertex>
#include <morphtarget_pars_vertex>
#include <skinning_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <shadowmap_pars_vertex>
void main() {
	#include <batching_vertex>
	#include <beginnormal_vertex>
	#include <morphinstance_vertex>
	#include <morphnormal_vertex>
	#include <skinbase_vertex>
	#include <skinnormal_vertex>
	#include <defaultnormal_vertex>
	#include <begin_vertex>
	#include <morphtarget_vertex>
	#include <skinning_vertex>
	#include <project_vertex>
	#include <logdepthbuf_vertex>
	#include <worldpos_vertex>
	#include <shadowmap_vertex>
	#include <fog_vertex>
}`,nq=`uniform vec3 color;
uniform float opacity;
#include <common>
#include <packing>
#include <fog_pars_fragment>
#include <bsdfs>
#include <lights_pars_begin>
#include <logdepthbuf_pars_fragment>
#include <shadowmap_pars_fragment>
#include <shadowmask_pars_fragment>
void main() {
	#include <logdepthbuf_fragment>
	gl_FragColor = vec4( color, opacity * ( 1.0 - getShadowMask() ) );
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
	#include <fog_fragment>
}`,sq=`uniform float rotation;
uniform vec2 center;
#include <common>
#include <uv_pars_vertex>
#include <fog_pars_vertex>
#include <logdepthbuf_pars_vertex>
#include <clipping_planes_pars_vertex>
void main() {
	#include <uv_vertex>
	vec4 mvPosition = modelViewMatrix[ 3 ];
	vec2 scale = vec2( length( modelMatrix[ 0 ].xyz ), length( modelMatrix[ 1 ].xyz ) );
	#ifndef USE_SIZEATTENUATION
		bool isPerspective = isPerspectiveMatrix( projectionMatrix );
		if ( isPerspective ) scale *= - mvPosition.z;
	#endif
	vec2 alignedPosition = ( position.xy - ( center - vec2( 0.5 ) ) ) * scale;
	vec2 rotatedPosition;
	rotatedPosition.x = cos( rotation ) * alignedPosition.x - sin( rotation ) * alignedPosition.y;
	rotatedPosition.y = sin( rotation ) * alignedPosition.x + cos( rotation ) * alignedPosition.y;
	mvPosition.xy += rotatedPosition;
	gl_Position = projectionMatrix * mvPosition;
	#include <logdepthbuf_vertex>
	#include <clipping_planes_vertex>
	#include <fog_vertex>
}`,iq=`uniform vec3 diffuse;
uniform float opacity;
#include <common>
#include <uv_pars_fragment>
#include <map_pars_fragment>
#include <alphamap_pars_fragment>
#include <alphatest_pars_fragment>
#include <alphahash_pars_fragment>
#include <fog_pars_fragment>
#include <logdepthbuf_pars_fragment>
#include <clipping_planes_pars_fragment>
void main() {
	vec4 diffuseColor = vec4( diffuse, opacity );
	#include <clipping_planes_fragment>
	vec3 outgoingLight = vec3( 0.0 );
	#include <logdepthbuf_fragment>
	#include <map_fragment>
	#include <alphamap_fragment>
	#include <alphatest_fragment>
	#include <alphahash_fragment>
	outgoingLight = diffuseColor.rgb;
	#include <opaque_fragment>
	#include <tonemapping_fragment>
	#include <colorspace_fragment>
	#include <fog_fragment>
}`,iJ={alphahash_fragment:RN,alphahash_pars_fragment:FN,alphamap_fragment:MN,alphamap_pars_fragment:kN,alphatest_fragment:VN,alphatest_pars_fragment:LN,aomap_fragment:zN,aomap_pars_fragment:BN,batching_pars_vertex:IN,batching_vertex:_N,begin_vertex:wN,beginnormal_vertex:CN,bsdfs:PN,iridescence_fragment:AN,bumpmap_pars_fragment:TN,clipping_planes_fragment:SN,clipping_planes_pars_fragment:jN,clipping_planes_pars_vertex:yN,clipping_planes_vertex:vN,color_fragment:fN,color_pars_fragment:bN,color_pars_vertex:hN,color_vertex:xN,common:gN,cube_uv_reflection_fragment:pN,defaultnormal_vertex:mN,displacementmap_pars_vertex:dN,displacementmap_vertex:lN,emissivemap_fragment:uN,emissivemap_pars_fragment:cN,colorspace_fragment:nN,colorspace_pars_fragment:sN,envmap_fragment:iN,envmap_common_pars_fragment:oN,envmap_pars_fragment:aN,envmap_pars_vertex:rN,envmap_physical_pars_fragment:X1,envmap_vertex:tN,fog_vertex:eN,fog_pars_vertex:J1,fog_fragment:Q1,fog_pars_fragment:$1,gradientmap_pars_fragment:Z1,lightmap_pars_fragment:W1,lights_lambert_fragment:K1,lights_lambert_pars_fragment:H1,lights_pars_begin:Y1,lights_toon_fragment:U1,lights_toon_pars_fragment:G1,lights_phong_fragment:E1,lights_phong_pars_fragment:N1,lights_physical_fragment:q1,lights_physical_pars_fragment:D1,lights_fragment_begin:O1,lights_fragment_maps:R1,lights_fragment_end:F1,logdepthbuf_fragment:M1,logdepthbuf_pars_fragment:k1,logdepthbuf_pars_vertex:V1,logdepthbuf_vertex:L1,map_fragment:z1,map_pars_fragment:B1,map_particle_fragment:I1,map_particle_pars_fragment:_1,metalnessmap_fragment:w1,metalnessmap_pars_fragment:C1,morphinstance_vertex:P1,morphcolor_vertex:A1,morphnormal_vertex:T1,morphtarget_pars_vertex:S1,morphtarget_vertex:j1,normal_fragment_begin:y1,normal_fragment_maps:v1,normal_pars_fragment:f1,normal_pars_vertex:b1,normal_vertex:h1,normalmap_pars_fragment:x1,clearcoat_normal_fragment_begin:g1,clearcoat_normal_fragment_maps:p1,clearcoat_pars_fragment:m1,iridescence_pars_fragment:d1,opaque_fragment:l1,packing:u1,premultiplied_alpha_fragment:c1,project_vertex:n1,dithering_fragment:s1,dithering_pars_fragment:i1,roughnessmap_fragment:o1,roughnessmap_pars_fragment:a1,shadowmap_pars_fragment:r1,shadowmap_pars_vertex:t1,shadowmap_vertex:e1,shadowmask_pars_fragment:Jq,skinbase_vertex:Qq,skinning_pars_vertex:$q,skinning_vertex:Zq,skinnormal_vertex:Wq,specularmap_fragment:Kq,specularmap_pars_fragment:Hq,tonemapping_fragment:Yq,tonemapping_pars_fragment:Xq,transmission_fragment:Uq,transmission_pars_fragment:Gq,uv_pars_fragment:Eq,uv_pars_vertex:Nq,uv_vertex:qq,worldpos_vertex:Dq,background_vert:Oq,background_frag:Rq,backgroundCube_vert:Fq,backgroundCube_frag:Mq,cube_vert:kq,cube_frag:Vq,depth_vert:Lq,depth_frag:zq,distanceRGBA_vert:Bq,distanceRGBA_frag:Iq,equirect_vert:_q,equirect_frag:wq,linedashed_vert:Cq,linedashed_frag:Pq,meshbasic_vert:Aq,meshbasic_frag:Tq,meshlambert_vert:Sq,meshlambert_frag:jq,meshmatcap_vert:yq,meshmatcap_frag:vq,meshnormal_vert:fq,meshnormal_frag:bq,meshphong_vert:hq,meshphong_frag:xq,meshphysical_vert:gq,meshphysical_frag:pq,meshtoon_vert:mq,meshtoon_frag:dq,points_vert:lq,points_frag:uq,shadow_vert:cq,shadow_frag:nq,sprite_vert:sq,sprite_frag:iq},DJ={common:{diffuse:{value:new kJ(16777215)},opacity:{value:1},map:{value:null},mapTransform:{value:new dJ},alphaMap:{value:null},alphaMapTransform:{value:new dJ},alphaTest:{value:0}},specularmap:{specularMap:{value:null},specularMapTransform:{value:new dJ}},envmap:{envMap:{value:null},envMapRotation:{value:new dJ},flipEnvMap:{value:-1},reflectivity:{value:1},ior:{value:1.5},refractionRatio:{value:0.98}},aomap:{aoMap:{value:null},aoMapIntensity:{value:1},aoMapTransform:{value:new dJ}},lightmap:{lightMap:{value:null},lightMapIntensity:{value:1},lightMapTransform:{value:new dJ}},bumpmap:{bumpMap:{value:null},bumpMapTransform:{value:new dJ},bumpScale:{value:1}},normalmap:{normalMap:{value:null},normalMapTransform:{value:new dJ},normalScale:{value:new t(1,1)}},displacementmap:{displacementMap:{value:null},displacementMapTransform:{value:new dJ},displacementScale:{value:1},displacementBias:{value:0}},emissivemap:{emissiveMap:{value:null},emissiveMapTransform:{value:new dJ}},metalnessmap:{metalnessMap:{value:null},metalnessMapTransform:{value:new dJ}},roughnessmap:{roughnessMap:{value:null},roughnessMapTransform:{value:new dJ}},gradientmap:{gradientMap:{value:null}},fog:{fogDensity:{value:0.00025},fogNear:{value:1},fogFar:{value:2000},fogColor:{value:new kJ(16777215)}},lights:{ambientLightColor:{value:[]},lightProbe:{value:[]},directionalLights:{value:[],properties:{direction:{},color:{}}},directionalLightShadows:{value:[],properties:{shadowIntensity:1,shadowBias:{},shadowNormalBias:{},shadowRadius:{},shadowMapSize:{}}},directionalShadowMap:{value:[]},directionalShadowMatrix:{value:[]},spotLights:{value:[],properties:{color:{},position:{},direction:{},distance:{},coneCos:{},penumbraCos:{},decay:{}}},spotLightShadows:{value:[],properties:{shadowIntensity:1,shadowBias:{},shadowNormalBias:{},shadowRadius:{},shadowMapSize:{}}},spotLightMap:{value:[]},spotShadowMap:{value:[]},spotLightMatrix:{value:[]},pointLights:{value:[],properties:{color:{},position:{},decay:{},distance:{}}},pointLightShadows:{value:[],properties:{shadowIntensity:1,shadowBias:{},shadowNormalBias:{},shadowRadius:{},shadowMapSize:{},shadowCameraNear:{},shadowCameraFar:{}}},pointShadowMap:{value:[]},pointShadowMatrix:{value:[]},hemisphereLights:{value:[],properties:{direction:{},skyColor:{},groundColor:{}}},rectAreaLights:{value:[],properties:{color:{},position:{},width:{},height:{}}},ltc_1:{value:null},ltc_2:{value:null}},points:{diffuse:{value:new kJ(16777215)},opacity:{value:1},size:{value:1},scale:{value:1},map:{value:null},alphaMap:{value:null},alphaMapTransform:{value:new dJ},alphaTest:{value:0},uvTransform:{value:new dJ}},sprite:{diffuse:{value:new kJ(16777215)},opacity:{value:1},center:{value:new t(0.5,0.5)},rotation:{value:0},map:{value:null},mapTransform:{value:new dJ},alphaMap:{value:null},alphaMapTransform:{value:new dJ},alphaTest:{value:0}}},M8={basic:{uniforms:S0([DJ.common,DJ.specularmap,DJ.envmap,DJ.aomap,DJ.lightmap,DJ.fog]),vertexShader:iJ.meshbasic_vert,fragmentShader:iJ.meshbasic_frag},lambert:{uniforms:S0([DJ.common,DJ.specularmap,DJ.envmap,DJ.aomap,DJ.lightmap,DJ.emissivemap,DJ.bumpmap,DJ.normalmap,DJ.displacementmap,DJ.fog,DJ.lights,{emissive:{value:new kJ(0)}}]),vertexShader:iJ.meshlambert_vert,fragmentShader:iJ.meshlambert_frag},phong:{uniforms:S0([DJ.common,DJ.specularmap,DJ.envmap,DJ.aomap,DJ.lightmap,DJ.emissivemap,DJ.bumpmap,DJ.normalmap,DJ.displacementmap,DJ.fog,DJ.lights,{emissive:{value:new kJ(0)},specular:{value:new kJ(1118481)},shininess:{value:30}}]),vertexShader:iJ.meshphong_vert,fragmentShader:iJ.meshphong_frag},standard:{uniforms:S0([DJ.common,DJ.envmap,DJ.aomap,DJ.lightmap,DJ.emissivemap,DJ.bumpmap,DJ.normalmap,DJ.displacementmap,DJ.roughnessmap,DJ.metalnessmap,DJ.fog,DJ.lights,{emissive:{value:new kJ(0)},roughness:{value:1},metalness:{value:0},envMapIntensity:{value:1}}]),vertexShader:iJ.meshphysical_vert,fragmentShader:iJ.meshphysical_frag},toon:{uniforms:S0([DJ.common,DJ.aomap,DJ.lightmap,DJ.emissivemap,DJ.bumpmap,DJ.normalmap,DJ.displacementmap,DJ.gradientmap,DJ.fog,DJ.lights,{emissive:{value:new kJ(0)}}]),vertexShader:iJ.meshtoon_vert,fragmentShader:iJ.meshtoon_frag},matcap:{uniforms:S0([DJ.common,DJ.bumpmap,DJ.normalmap,DJ.displacementmap,DJ.fog,{matcap:{value:null}}]),vertexShader:iJ.meshmatcap_vert,fragmentShader:iJ.meshmatcap_frag},points:{uniforms:S0([DJ.points,DJ.fog]),vertexShader:iJ.points_vert,fragmentShader:iJ.points_frag},dashed:{uniforms:S0([DJ.common,DJ.fog,{scale:{value:1},dashSize:{value:1},totalSize:{value:2}}]),vertexShader:iJ.linedashed_vert,fragmentShader:iJ.linedashed_frag},depth:{uniforms:S0([DJ.common,DJ.displacementmap]),vertexShader:iJ.depth_vert,fragmentShader:iJ.depth_frag},normal:{uniforms:S0([DJ.common,DJ.bumpmap,DJ.normalmap,DJ.displacementmap,{opacity:{value:1}}]),vertexShader:iJ.meshnormal_vert,fragmentShader:iJ.meshnormal_frag},sprite:{uniforms:S0([DJ.sprite,DJ.fog]),vertexShader:iJ.sprite_vert,fragmentShader:iJ.sprite_frag},background:{uniforms:{uvTransform:{value:new dJ},t2D:{value:null},backgroundIntensity:{value:1}},vertexShader:iJ.background_vert,fragmentShader:iJ.background_frag},backgroundCube:{uniforms:{envMap:{value:null},flipEnvMap:{value:-1},backgroundBlurriness:{value:0},backgroundIntensity:{value:1},backgroundRotation:{value:new dJ}},vertexShader:iJ.backgroundCube_vert,fragmentShader:iJ.backgroundCube_frag},cube:{uniforms:{tCube:{value:null},tFlip:{value:-1},opacity:{value:1}},vertexShader:iJ.cube_vert,fragmentShader:iJ.cube_frag},equirect:{uniforms:{tEquirect:{value:null}},vertexShader:iJ.equirect_vert,fragmentShader:iJ.equirect_frag},distanceRGBA:{uniforms:S0([DJ.common,DJ.displacementmap,{referencePosition:{value:new w},nearDistance:{value:1},farDistance:{value:1000}}]),vertexShader:iJ.distanceRGBA_vert,fragmentShader:iJ.distanceRGBA_frag},shadow:{uniforms:S0([DJ.lights,DJ.fog,{color:{value:new kJ(0)},opacity:{value:1}}]),vertexShader:iJ.shadow_vert,fragmentShader:iJ.shadow_frag}};M8.physical={uniforms:S0([M8.standard.uniforms,{clearcoat:{value:0},clearcoatMap:{value:null},clearcoatMapTransform:{value:new dJ},clearcoatNormalMap:{value:null},clearcoatNormalMapTransform:{value:new dJ},clearcoatNormalScale:{value:new t(1,1)},clearcoatRoughness:{value:0},clearcoatRoughnessMap:{value:null},clearcoatRoughnessMapTransform:{value:new dJ},dispersion:{value:0},iridescence:{value:0},iridescenceMap:{value:null},iridescenceMapTransform:{value:new dJ},iridescenceIOR:{value:1.3},iridescenceThicknessMinimum:{value:100},iridescenceThicknessMaximum:{value:400},iridescenceThicknessMap:{value:null},iridescenceThicknessMapTransform:{value:new dJ},sheen:{value:0},sheenColor:{value:new kJ(0)},sheenColorMap:{value:null},sheenColorMapTransform:{value:new dJ},sheenRoughness:{value:1},sheenRoughnessMap:{value:null},sheenRoughnessMapTransform:{value:new dJ},transmission:{value:0},transmissionMap:{value:null},transmissionMapTransform:{value:new dJ},transmissionSamplerSize:{value:new t},transmissionSamplerMap:{value:null},thickness:{value:0},thicknessMap:{value:null},thicknessMapTransform:{value:new dJ},attenuationDistance:{value:0},attenuationColor:{value:new kJ(0)},specularColor:{value:new kJ(1,1,1)},specularColorMap:{value:null},specularColorMapTransform:{value:new dJ},specularIntensity:{value:1},specularIntensityMap:{value:null},specularIntensityMapTransform:{value:new dJ},anisotropyVector:{value:new t},anisotropyMap:{value:null},anisotropyMapTransform:{value:new dJ}}]),vertexShader:iJ.meshphysical_vert,fragmentShader:iJ.meshphysical_frag};var J$={r:0,b:0,g:0},L9=new s0,oq=new hJ;function aq(J,Q,$,Z,W,K,H){let Y=new kJ(0),X=K===!0?0:1,U,G,E=null,N=0,q=null;function R(M){let L=M.isScene===!0?M.background:null;if(L&&L.isTexture)L=(M.backgroundBlurriness>0?$:Q).get(L);return L}function F(M){let L=!1,A=R(M);if(A===null)D(Y,X);else if(A&&A.isColor)D(A,1),L=!0;let _=J.xr.getEnvironmentBlendMode();if(_==="additive")Z.buffers.color.setClear(0,0,0,1,H);else if(_==="alpha-blend")Z.buffers.color.setClear(0,0,0,0,H);if(J.autoClear||L)Z.buffers.depth.setTest(!0),Z.buffers.depth.setMask(!0),Z.buffers.color.setMask(!0),J.clear(J.autoClearColor,J.autoClearDepth,J.autoClearStencil)}function O(M,L){let A=R(L);if(A&&(A.isCubeTexture||A.mapping===g6)){if(G===void 0)G=new k0(new M9(1,1,1),new e0({name:"BackgroundCubeMaterial",uniforms:k9(M8.backgroundCube.uniforms),vertexShader:M8.backgroundCube.vertexShader,fragmentShader:M8.backgroundCube.fragmentShader,side:i0,depthTest:!1,depthWrite:!1,fog:!1,allowOverride:!1})),G.geometry.deleteAttribute("normal"),G.geometry.deleteAttribute("uv"),G.onBeforeRender=function(_,C,y){this.matrixWorld.copyPosition(y.matrixWorld)},Object.defineProperty(G.material,"envMap",{get:function(){return this.uniforms.envMap.value}}),W.update(G);if(L9.copy(L.backgroundRotation),L9.x*=-1,L9.y*=-1,L9.z*=-1,A.isCubeTexture&&A.isRenderTargetTexture===!1)L9.y*=-1,L9.z*=-1;if(G.material.uniforms.envMap.value=A,G.material.uniforms.flipEnvMap.value=A.isCubeTexture&&A.isRenderTargetTexture===!1?-1:1,G.material.uniforms.backgroundBlurriness.value=L.backgroundBlurriness,G.material.uniforms.backgroundIntensity.value=L.backgroundIntensity,G.material.uniforms.backgroundRotation.value.setFromMatrix4(oq.makeRotationFromEuler(L9)),G.material.toneMapped=tJ.getTransfer(A.colorSpace)!==G0,E!==A||N!==A.version||q!==J.toneMapping)G.material.needsUpdate=!0,E=A,N=A.version,q=J.toneMapping;G.layers.enableAll(),M.unshift(G,G.geometry,G.material,0,0,null)}else if(A&&A.isTexture){if(U===void 0)U=new k0(new U6(2,2),new e0({name:"BackgroundMaterial",uniforms:k9(M8.background.uniforms),vertexShader:M8.background.vertexShader,fragmentShader:M8.background.fragmentShader,side:Q6,depthTest:!1,depthWrite:!1,fog:!1,allowOverride:!1})),U.geometry.deleteAttribute("normal"),Object.defineProperty(U.material,"map",{get:function(){return this.uniforms.t2D.value}}),W.update(U);if(U.material.uniforms.t2D.value=A,U.material.uniforms.backgroundIntensity.value=L.backgroundIntensity,U.material.toneMapped=tJ.getTransfer(A.colorSpace)!==G0,A.matrixAutoUpdate===!0)A.updateMatrix();if(U.material.uniforms.uvTransform.value.copy(A.matrix),E!==A||N!==A.version||q!==J.toneMapping)U.material.needsUpdate=!0,E=A,N=A.version,q=J.toneMapping;U.layers.enableAll(),M.unshift(U,U.geometry,U.material,0,0,null)}}function D(M,L){M.getRGB(J$,mZ(J)),Z.buffers.color.setClear(J$.r,J$.g,J$.b,L,H)}function k(){if(G!==void 0)G.geometry.dispose(),G.material.dispose(),G=void 0;if(U!==void 0)U.geometry.dispose(),U.material.dispose(),U=void 0}return{getClearColor:function(){return Y},setClearColor:function(M,L=1){Y.set(M),X=L,D(Y,X)},getClearAlpha:function(){return X},setClearAlpha:function(M){X=M,D(Y,X)},render:F,addToRenderList:O,dispose:k}}function rq(J,Q){let $=J.getParameter(J.MAX_VERTEX_ATTRIBS),Z={},W=N(null),K=W,H=!1;function Y(I,S,p,d,x){let o=!1,l=E(d,p,S);if(K!==l)K=l,U(K.object);if(o=q(I,d,p,x),o)R(I,d,p,x);if(x!==null)Q.update(x,J.ELEMENT_ARRAY_BUFFER);if(o||H){if(H=!1,L(I,S,p,d),x!==null)J.bindBuffer(J.ELEMENT_ARRAY_BUFFER,Q.get(x).buffer)}}function X(){return J.createVertexArray()}function U(I){return J.bindVertexArray(I)}function G(I){return J.deleteVertexArray(I)}function E(I,S,p){let d=p.wireframe===!0,x=Z[I.id];if(x===void 0)x={},Z[I.id]=x;let o=x[S.id];if(o===void 0)o={},x[S.id]=o;let l=o[d];if(l===void 0)l=N(X()),o[d]=l;return l}function N(I){let S=[],p=[],d=[];for(let x=0;x<$;x++)S[x]=0,p[x]=0,d[x]=0;return{geometry:null,program:null,wireframe:!1,newAttributes:S,enabledAttributes:p,attributeDivisors:d,object:I,attributes:{},index:null}}function q(I,S,p,d){let x=K.attributes,o=S.attributes,l=0,QJ=p.getAttributes();for(let m in QJ)if(QJ[m].location>=0){let NJ=x[m],SJ=o[m];if(SJ===void 0){if(m==="instanceMatrix"&&I.instanceMatrix)SJ=I.instanceMatrix;if(m==="instanceColor"&&I.instanceColor)SJ=I.instanceColor}if(NJ===void 0)return!0;if(NJ.attribute!==SJ)return!0;if(SJ&&NJ.data!==SJ.data)return!0;l++}if(K.attributesNum!==l)return!0;if(K.index!==d)return!0;return!1}function R(I,S,p,d){let x={},o=S.attributes,l=0,QJ=p.getAttributes();for(let m in QJ)if(QJ[m].location>=0){let NJ=o[m];if(NJ===void 0){if(m==="instanceMatrix"&&I.instanceMatrix)NJ=I.instanceMatrix;if(m==="instanceColor"&&I.instanceColor)NJ=I.instanceColor}let SJ={};if(SJ.attribute=NJ,NJ&&NJ.data)SJ.data=NJ.data;x[m]=SJ,l++}K.attributes=x,K.attributesNum=l,K.index=d}function F(){let I=K.newAttributes;for(let S=0,p=I.length;S<p;S++)I[S]=0}function O(I){D(I,0)}function D(I,S){let{newAttributes:p,enabledAttributes:d,attributeDivisors:x}=K;if(p[I]=1,d[I]===0)J.enableVertexAttribArray(I),d[I]=1;if(x[I]!==S)J.vertexAttribDivisor(I,S),x[I]=S}function k(){let{newAttributes:I,enabledAttributes:S}=K;for(let p=0,d=S.length;p<d;p++)if(S[p]!==I[p])J.disableVertexAttribArray(p),S[p]=0}function M(I,S,p,d,x,o,l){if(l===!0)J.vertexAttribIPointer(I,S,p,x,o);else J.vertexAttribPointer(I,S,p,d,x,o)}function L(I,S,p,d){F();let x=d.attributes,o=p.getAttributes(),l=S.defaultAttributeValues;for(let QJ in o){let m=o[QJ];if(m.location>=0){let EJ=x[QJ];if(EJ===void 0){if(QJ==="instanceMatrix"&&I.instanceMatrix)EJ=I.instanceMatrix;if(QJ==="instanceColor"&&I.instanceColor)EJ=I.instanceColor}if(EJ!==void 0){let{normalized:NJ,itemSize:SJ}=EJ,mJ=Q.get(EJ);if(mJ===void 0)continue;let{buffer:U0,type:rJ,bytesPerElement:s}=mJ,qJ=rJ===J.INT||rJ===J.UNSIGNED_INT||EJ.gpuType===JZ;if(EJ.isInterleavedBufferAttribute){let XJ=EJ.data,LJ=XJ.stride,yJ=EJ.offset;if(XJ.isInstancedInterleavedBuffer){for(let xJ=0;xJ<m.locationSize;xJ++)D(m.location+xJ,XJ.meshPerAttribute);if(I.isInstancedMesh!==!0&&d._maxInstanceCount===void 0)d._maxInstanceCount=XJ.meshPerAttribute*XJ.count}else for(let xJ=0;xJ<m.locationSize;xJ++)O(m.location+xJ);J.bindBuffer(J.ARRAY_BUFFER,U0);for(let xJ=0;xJ<m.locationSize;xJ++)M(m.location+xJ,SJ/m.locationSize,rJ,NJ,LJ*s,(yJ+SJ/m.locationSize*xJ)*s,qJ)}else{if(EJ.isInstancedBufferAttribute){for(let XJ=0;XJ<m.locationSize;XJ++)D(m.location+XJ,EJ.meshPerAttribute);if(I.isInstancedMesh!==!0&&d._maxInstanceCount===void 0)d._maxInstanceCount=EJ.meshPerAttribute*EJ.count}else for(let XJ=0;XJ<m.locationSize;XJ++)O(m.location+XJ);J.bindBuffer(J.ARRAY_BUFFER,U0);for(let XJ=0;XJ<m.locationSize;XJ++)M(m.location+XJ,SJ/m.locationSize,rJ,NJ,SJ*s,SJ/m.locationSize*XJ*s,qJ)}}else if(l!==void 0){let NJ=l[QJ];if(NJ!==void 0)switch(NJ.length){case 2:J.vertexAttrib2fv(m.location,NJ);break;case 3:J.vertexAttrib3fv(m.location,NJ);break;case 4:J.vertexAttrib4fv(m.location,NJ);break;default:J.vertexAttrib1fv(m.location,NJ)}}}}k()}function A(){y();for(let I in Z){let S=Z[I];for(let p in S){let d=S[p];for(let x in d)G(d[x].object),delete d[x];delete S[p]}delete Z[I]}}function _(I){if(Z[I.id]===void 0)return;let S=Z[I.id];for(let p in S){let d=S[p];for(let x in d)G(d[x].object),delete d[x];delete S[p]}delete Z[I.id]}function C(I){for(let S in Z){let p=Z[S];if(p[I.id]===void 0)continue;let d=p[I.id];for(let x in d)G(d[x].object),delete d[x];delete p[I.id]}}function y(){if(z(),H=!0,K===W)return;K=W,U(K.object)}function z(){W.geometry=null,W.program=null,W.wireframe=!1}return{setup:Y,reset:y,resetDefaultState:z,dispose:A,releaseStatesOfGeometry:_,releaseStatesOfProgram:C,initAttributes:F,enableAttribute:O,disableUnusedAttributes:k}}function tq(J,Q,$){let Z;function W(U){Z=U}function K(U,G){J.drawArrays(Z,U,G),$.update(G,Z,1)}function H(U,G,E){if(E===0)return;J.drawArraysInstanced(Z,U,G,E),$.update(G,Z,E)}function Y(U,G,E){if(E===0)return;Q.get("WEBGL_multi_draw").multiDrawArraysWEBGL(Z,U,0,G,0,E);let q=0;for(let R=0;R<E;R++)q+=G[R];$.update(q,Z,1)}function X(U,G,E,N){if(E===0)return;let q=Q.get("WEBGL_multi_draw");if(q===null)for(let R=0;R<U.length;R++)H(U[R],G[R],N[R]);else{q.multiDrawArraysInstancedWEBGL(Z,U,0,G,0,N,0,E);let R=0;for(let F=0;F<E;F++)R+=G[F]*N[F];$.update(R,Z,1)}}this.setMode=W,this.render=K,this.renderInstances=H,this.renderMultiDraw=Y,this.renderMultiDrawInstances=X}function eq(J,Q,$,Z){let W;function K(){if(W!==void 0)return W;if(Q.has("EXT_texture_filter_anisotropic")===!0){let C=Q.get("EXT_texture_filter_anisotropic");W=J.getParameter(C.MAX_TEXTURE_MAX_ANISOTROPY_EXT)}else W=0;return W}function H(C){if(C!==F8&&Z.convert(C)!==J.getParameter(J.IMPLEMENTATION_COLOR_READ_FORMAT))return!1;return!0}function Y(C){let y=C===d6&&(Q.has("EXT_color_buffer_half_float")||Q.has("EXT_color_buffer_float"));if(C!==d8&&Z.convert(C)!==J.getParameter(J.IMPLEMENTATION_COLOR_READ_TYPE)&&C!==l8&&!y)return!1;return!0}function X(C){if(C==="highp"){if(J.getShaderPrecisionFormat(J.VERTEX_SHADER,J.HIGH_FLOAT).precision>0&&J.getShaderPrecisionFormat(J.FRAGMENT_SHADER,J.HIGH_FLOAT).precision>0)return"highp";C="mediump"}if(C==="mediump"){if(J.getShaderPrecisionFormat(J.VERTEX_SHADER,J.MEDIUM_FLOAT).precision>0&&J.getShaderPrecisionFormat(J.FRAGMENT_SHADER,J.MEDIUM_FLOAT).precision>0)return"mediump"}return"lowp"}let U=$.precision!==void 0?$.precision:"highp",G=X(U);if(G!==U)console.warn("THREE.WebGLRenderer:",U,"not supported, using",G,"instead."),U=G;let E=$.logarithmicDepthBuffer===!0,N=$.reversedDepthBuffer===!0&&Q.has("EXT_clip_control"),q=J.getParameter(J.MAX_TEXTURE_IMAGE_UNITS),R=J.getParameter(J.MAX_VERTEX_TEXTURE_IMAGE_UNITS),F=J.getParameter(J.MAX_TEXTURE_SIZE),O=J.getParameter(J.MAX_CUBE_MAP_TEXTURE_SIZE),D=J.getParameter(J.MAX_VERTEX_ATTRIBS),k=J.getParameter(J.MAX_VERTEX_UNIFORM_VECTORS),M=J.getParameter(J.MAX_VARYING_VECTORS),L=J.getParameter(J.MAX_FRAGMENT_UNIFORM_VECTORS),A=R>0,_=J.getParameter(J.MAX_SAMPLES);return{isWebGL2:!0,getMaxAnisotropy:K,getMaxPrecision:X,textureFormatReadable:H,textureTypeReadable:Y,precision:U,logarithmicDepthBuffer:E,reversedDepthBuffer:N,maxTextures:q,maxVertexTextures:R,maxTextureSize:F,maxCubemapSize:O,maxAttributes:D,maxVertexUniforms:k,maxVaryings:M,maxFragmentUniforms:L,vertexTextures:A,maxSamples:_}}function JD(J){let Q=this,$=null,Z=0,W=!1,K=!1,H=new _8,Y=new dJ,X={value:null,needsUpdate:!1};this.uniform=X,this.numPlanes=0,this.numIntersection=0,this.init=function(E,N){let q=E.length!==0||N||Z!==0||W;return W=N,Z=E.length,q},this.beginShadows=function(){K=!0,G(null)},this.endShadows=function(){K=!1},this.setGlobalState=function(E,N){$=G(E,N,0)},this.setState=function(E,N,q){let{clippingPlanes:R,clipIntersection:F,clipShadows:O}=E,D=J.get(E);if(!W||R===null||R.length===0||K&&!O)if(K)G(null);else U();else{let k=K?0:Z,M=k*4,L=D.clippingState||null;X.value=L,L=G(R,N,M,q);for(let A=0;A!==M;++A)L[A]=$[A];D.clippingState=L,this.numIntersection=F?this.numPlanes:0,this.numPlanes+=k}};function U(){if(X.value!==$)X.value=$,X.needsUpdate=Z>0;Q.numPlanes=Z,Q.numIntersection=0}function G(E,N,q,R){let F=E!==null?E.length:0,O=null;if(F!==0){if(O=X.value,R!==!0||O===null){let D=q+F*4,k=N.matrixWorldInverse;if(Y.getNormalMatrix(k),O===null||O.length<D)O=new Float32Array(D);for(let M=0,L=q;M!==F;++M,L+=4)H.copy(E[M]).applyMatrix4(k,Y),H.normal.toArray(O,L),O[L+3]=H.constant}X.value=O,X.needsUpdate=!0}return Q.numPlanes=F,Q.numIntersection=0,O}}function QD(J){let Q=new WeakMap;function $(H,Y){if(Y===YQ)H.mapping=Z6;else if(Y===XQ)H.mapping=D9;return H}function Z(H){if(H&&H.isTexture){let Y=H.mapping;if(Y===YQ||Y===XQ)if(Q.has(H)){let X=Q.get(H).texture;return $(X,H.mapping)}else{let X=H.image;if(X&&X.height>0){let U=new lZ(X.height);return U.fromEquirectangularTexture(J,H),Q.set(H,U),H.addEventListener("dispose",W),$(U.texture,H.mapping)}else return null}}return H}function W(H){let Y=H.target;Y.removeEventListener("dispose",W);let X=Q.get(Y);if(X!==void 0)Q.delete(Y),X.dispose()}function K(){Q=new WeakMap}return{get:Z,dispose:K}}var q6=4,TX=[0.125,0.215,0.35,0.446,0.526,0.582],I9=20,gW=new Z7,SX=new kJ,pW=null,mW=0,dW=0,lW=!1,B9=(1+Math.sqrt(5))/2,N6=1/B9,jX=[new w(-B9,N6,0),new w(B9,N6,0),new w(-N6,0,B9),new w(N6,0,B9),new w(0,B9,-N6),new w(0,B9,N6),new w(-1,1,-1),new w(1,1,-1),new w(-1,1,1),new w(1,1,1)],$D=new w;class cW{constructor(J){this._renderer=J,this._pingPongRenderTarget=null,this._lodMax=0,this._cubeSize=0,this._lodPlanes=[],this._sizeLods=[],this._sigmas=[],this._blurMaterial=null,this._cubemapMaterial=null,this._equirectMaterial=null,this._compileMaterial(this._blurMaterial)}fromScene(J,Q=0,$=0.1,Z=100,W={}){let{size:K=256,position:H=$D}=W;pW=this._renderer.getRenderTarget(),mW=this._renderer.getActiveCubeFace(),dW=this._renderer.getActiveMipmapLevel(),lW=this._renderer.xr.enabled,this._renderer.xr.enabled=!1,this._setSize(K);let Y=this._allocateTargets();if(Y.depthBuffer=!0,this._sceneToCubeUV(J,$,Z,Y,H),Q>0)this._blur(Y,0,0,Q);return this._applyPMREM(Y),this._cleanup(Y),Y}fromEquirectangular(J,Q=null){return this._fromTexture(J,Q)}fromCubemap(J,Q=null){return this._fromTexture(J,Q)}compileCubemapShader(){if(this._cubemapMaterial===null)this._cubemapMaterial=fX(),this._compileMaterial(this._cubemapMaterial)}compileEquirectangularShader(){if(this._equirectMaterial===null)this._equirectMaterial=vX(),this._compileMaterial(this._equirectMaterial)}dispose(){if(this._dispose(),this._cubemapMaterial!==null)this._cubemapMaterial.dispose();if(this._equirectMaterial!==null)this._equirectMaterial.dispose()}_setSize(J){this._lodMax=Math.floor(Math.log2(J)),this._cubeSize=Math.pow(2,this._lodMax)}_dispose(){if(this._blurMaterial!==null)this._blurMaterial.dispose();if(this._pingPongRenderTarget!==null)this._pingPongRenderTarget.dispose();for(let J=0;J<this._lodPlanes.length;J++)this._lodPlanes[J].dispose()}_cleanup(J){this._renderer.setRenderTarget(pW,mW,dW),this._renderer.xr.enabled=lW,J.scissorTest=!1,Q$(J,0,0,J.width,J.height)}_fromTexture(J,Q){if(J.mapping===Z6||J.mapping===D9)this._setSize(J.image.length===0?16:J.image[0].width||J.image[0].image.width);else this._setSize(J.image.width/4);pW=this._renderer.getRenderTarget(),mW=this._renderer.getActiveCubeFace(),dW=this._renderer.getActiveMipmapLevel(),lW=this._renderer.xr.enabled,this._renderer.xr.enabled=!1;let $=Q||this._allocateTargets();return this._textureToCubeUV(J,$),this._applyPMREM($),this._cleanup($),$}_allocateTargets(){let J=3*Math.max(this._cubeSize,112),Q=4*this._cubeSize,$={magFilter:O9,minFilter:O9,generateMipmaps:!1,type:d6,format:F8,colorSpace:u6,depthBuffer:!1},Z=yX(J,Q,$);if(this._pingPongRenderTarget===null||this._pingPongRenderTarget.width!==J||this._pingPongRenderTarget.height!==Q){if(this._pingPongRenderTarget!==null)this._dispose();this._pingPongRenderTarget=yX(J,Q,$);let{_lodMax:W}=this;({sizeLods:this._sizeLods,lodPlanes:this._lodPlanes,sigmas:this._sigmas}=ZD(W)),this._blurMaterial=WD(W,J,Q)}return Z}_compileMaterial(J){let Q=new k0(this._lodPlanes[0],J);this._renderer.compile(Q,gW)}_sceneToCubeUV(J,Q,$,Z,W){let Y=new I0(90,1,Q,$),X=[1,-1,1,1,1,1],U=[1,1,1,-1,-1,-1],G=this._renderer,E=G.autoClear,N=G.toneMapping;if(G.getClearColor(SX),G.toneMapping=T8,G.autoClear=!1,G.state.buffers.depth.getReversed())G.setRenderTarget(Z),G.clearDepth(),G.setRenderTarget(null);let R=new S8({name:"PMREM.Background",side:i0,depthWrite:!1,depthTest:!1}),F=new k0(new M9,R),O=!1,D=J.background;if(D){if(D.isColor)R.color.copy(D),J.background=null,O=!0}else R.color.copy(SX),O=!0;for(let k=0;k<6;k++){let M=k%3;if(M===0)Y.up.set(0,X[k],0),Y.position.set(W.x,W.y,W.z),Y.lookAt(W.x+U[k],W.y,W.z);else if(M===1)Y.up.set(0,0,X[k]),Y.position.set(W.x,W.y,W.z),Y.lookAt(W.x,W.y+U[k],W.z);else Y.up.set(0,X[k],0),Y.position.set(W.x,W.y,W.z),Y.lookAt(W.x,W.y,W.z+U[k]);let L=this._cubeSize;if(Q$(Z,M*L,k>2?L:0,L,L),G.setRenderTarget(Z),O)G.render(F,Y);G.render(J,Y)}F.geometry.dispose(),F.material.dispose(),G.toneMapping=N,G.autoClear=E,J.background=D}_textureToCubeUV(J,Q){let $=this._renderer,Z=J.mapping===Z6||J.mapping===D9;if(Z){if(this._cubemapMaterial===null)this._cubemapMaterial=fX();this._cubemapMaterial.uniforms.flipEnvMap.value=J.isRenderTargetTexture===!1?-1:1}else if(this._equirectMaterial===null)this._equirectMaterial=vX();let W=Z?this._cubemapMaterial:this._equirectMaterial,K=new k0(this._lodPlanes[0],W),H=W.uniforms;H.envMap.value=J;let Y=this._cubeSize;Q$(Q,0,0,3*Y,2*Y),$.setRenderTarget(Q),$.render(K,gW)}_applyPMREM(J){let Q=this._renderer,$=Q.autoClear;Q.autoClear=!1;let Z=this._lodPlanes.length;for(let W=1;W<Z;W++){let K=Math.sqrt(this._sigmas[W]*this._sigmas[W]-this._sigmas[W-1]*this._sigmas[W-1]),H=jX[(Z-W-1)%jX.length];this._blur(J,W-1,W,K,H)}Q.autoClear=$}_blur(J,Q,$,Z,W){let K=this._pingPongRenderTarget;this._halfBlur(J,K,Q,$,Z,"latitudinal",W),this._halfBlur(K,J,$,$,Z,"longitudinal",W)}_halfBlur(J,Q,$,Z,W,K,H){let Y=this._renderer,X=this._blurMaterial;if(K!=="latitudinal"&&K!=="longitudinal")console.error("blur direction must be either latitudinal or longitudinal!");let U=3,G=new k0(this._lodPlanes[Z],X),E=X.uniforms,N=this._sizeLods[$]-1,q=isFinite(W)?Math.PI/(2*N):2*Math.PI/(2*I9-1),R=W/q,F=isFinite(W)?1+Math.floor(U*R):I9;if(F>I9)console.warn(`sigmaRadians, ${W}, is too large and will clip, as it requested ${F} samples when the maximum is set to ${I9}`);let O=[],D=0;for(let _=0;_<I9;++_){let C=_/R,y=Math.exp(-C*C/2);if(O.push(y),_===0)D+=y;else if(_<F)D+=2*y}for(let _=0;_<O.length;_++)O[_]=O[_]/D;if(E.envMap.value=J.texture,E.samples.value=F,E.weights.value=O,E.latitudinal.value=K==="latitudinal",H)E.poleAxis.value=H;let{_lodMax:k}=this;E.dTheta.value=q,E.mipInt.value=k-$;let M=this._sizeLods[Z],L=3*M*(Z>k-q6?Z-k+q6:0),A=4*(this._cubeSize-M);Q$(Q,L,A,3*M,2*M),Y.setRenderTarget(Q),Y.render(G,gW)}}function ZD(J){let Q=[],$=[],Z=[],W=J,K=J-q6+1+TX.length;for(let H=0;H<K;H++){let Y=Math.pow(2,W);$.push(Y);let X=1/Y;if(H>J-q6)X=TX[H-J+q6-1];else if(H===0)X=0;Z.push(X);let U=1/(Y-2),G=-U,E=1+U,N=[G,G,E,G,E,E,G,G,E,E,G,E],q=6,R=6,F=3,O=2,D=1,k=new Float32Array(F*R*q),M=new Float32Array(O*R*q),L=new Float32Array(D*R*q);for(let _=0;_<q;_++){let C=_%3*2/3-1,y=_>2?0:-1,z=[C,y,0,C+0.6666666666666666,y,0,C+0.6666666666666666,y+1,0,C,y,0,C+0.6666666666666666,y+1,0,C,y+1,0];k.set(z,F*R*_),M.set(N,O*R*_);let I=[_,_,_,_,_,_];L.set(I,D*R*_)}let A=new nJ;if(A.setAttribute("position",new Z0(k,F)),A.setAttribute("uv",new Z0(M,O)),A.setAttribute("faceIndex",new Z0(L,D)),Q.push(A),W>q6)W--}return{lodPlanes:Q,sizeLods:$,sigmas:Z}}function yX(J,Q,$){let Z=new Y8(J,Q,$);return Z.texture.mapping=g6,Z.texture.name="PMREM.cubeUv",Z.scissorTest=!0,Z}function Q$(J,Q,$,Z,W){J.viewport.set(Q,$,Z,W),J.scissor.set(Q,$,Z,W)}function WD(J,Q,$){let Z=new Float32Array(I9),W=new w(0,1,0);return new e0({name:"SphericalGaussianBlur",defines:{n:I9,CUBEUV_TEXEL_WIDTH:1/Q,CUBEUV_TEXEL_HEIGHT:1/$,CUBEUV_MAX_MIP:`${J}.0`},uniforms:{envMap:{value:null},samples:{value:1},weights:{value:Z},latitudinal:{value:!1},dTheta:{value:0},mipInt:{value:0},poleAxis:{value:W}},vertexShader:sW(),fragmentShader:`

			precision mediump float;
			precision mediump int;

			varying vec3 vOutputDirection;

			uniform sampler2D envMap;
			uniform int samples;
			uniform float weights[ n ];
			uniform bool latitudinal;
			uniform float dTheta;
			uniform float mipInt;
			uniform vec3 poleAxis;

			#define ENVMAP_TYPE_CUBE_UV
			#include <cube_uv_reflection_fragment>

			vec3 getSample( float theta, vec3 axis ) {

				float cosTheta = cos( theta );
				// Rodrigues' axis-angle rotation
				vec3 sampleDirection = vOutputDirection * cosTheta
					+ cross( axis, vOutputDirection ) * sin( theta )
					+ axis * dot( axis, vOutputDirection ) * ( 1.0 - cosTheta );

				return bilinearCubeUV( envMap, sampleDirection, mipInt );

			}

			void main() {

				vec3 axis = latitudinal ? poleAxis : cross( poleAxis, vOutputDirection );

				if ( all( equal( axis, vec3( 0.0 ) ) ) ) {

					axis = vec3( vOutputDirection.z, 0.0, - vOutputDirection.x );

				}

				axis = normalize( axis );

				gl_FragColor = vec4( 0.0, 0.0, 0.0, 1.0 );
				gl_FragColor.rgb += weights[ 0 ] * getSample( 0.0, axis );

				for ( int i = 1; i < n; i++ ) {

					if ( i >= samples ) {

						break;

					}

					float theta = dTheta * float( i );
					gl_FragColor.rgb += weights[ i ] * getSample( -1.0 * theta, axis );
					gl_FragColor.rgb += weights[ i ] * getSample( theta, axis );

				}

			}
		`,blending:m8,depthTest:!1,depthWrite:!1})}function vX(){return new e0({name:"EquirectangularToCubeUV",uniforms:{envMap:{value:null}},vertexShader:sW(),fragmentShader:`

			precision mediump float;
			precision mediump int;

			varying vec3 vOutputDirection;

			uniform sampler2D envMap;

			#include <common>

			void main() {

				vec3 outputDirection = normalize( vOutputDirection );
				vec2 uv = equirectUv( outputDirection );

				gl_FragColor = vec4( texture2D ( envMap, uv ).rgb, 1.0 );

			}
		`,blending:m8,depthTest:!1,depthWrite:!1})}function fX(){return new e0({name:"CubemapToCubeUV",uniforms:{envMap:{value:null},flipEnvMap:{value:-1}},vertexShader:sW(),fragmentShader:`

			precision mediump float;
			precision mediump int;

			uniform float flipEnvMap;

			varying vec3 vOutputDirection;

			uniform samplerCube envMap;

			void main() {

				gl_FragColor = textureCube( envMap, vec3( flipEnvMap * vOutputDirection.x, vOutputDirection.yz ) );

			}
		`,blending:m8,depthTest:!1,depthWrite:!1})}function sW(){return`

		precision mediump float;
		precision mediump int;

		attribute float faceIndex;

		varying vec3 vOutputDirection;

		// RH coordinate system; PMREM face-indexing convention
		vec3 getDirection( vec2 uv, float face ) {

			uv = 2.0 * uv - 1.0;

			vec3 direction = vec3( uv, 1.0 );

			if ( face == 0.0 ) {

				direction = direction.zyx; // ( 1, v, u ) pos x

			} else if ( face == 1.0 ) {

				direction = direction.xzy;
				direction.xz *= -1.0; // ( -u, 1, -v ) pos y

			} else if ( face == 2.0 ) {

				direction.x *= -1.0; // ( -u, v, 1 ) pos z

			} else if ( face == 3.0 ) {

				direction = direction.zyx;
				direction.xz *= -1.0; // ( -1, v, -u ) neg x

			} else if ( face == 4.0 ) {

				direction = direction.xzy;
				direction.xy *= -1.0; // ( -u, -1, v ) neg y

			} else if ( face == 5.0 ) {

				direction.z *= -1.0; // ( u, v, -1 ) neg z

			}

			return direction;

		}

		void main() {

			vOutputDirection = getDirection( uv, faceIndex );
			gl_Position = vec4( position, 1.0 );

		}
	`}function KD(J){let Q=new WeakMap,$=null;function Z(Y){if(Y&&Y.isTexture){let X=Y.mapping,U=X===YQ||X===XQ,G=X===Z6||X===D9;if(U||G){let E=Q.get(Y),N=E!==void 0?E.texture.pmremVersion:0;if(Y.isRenderTargetTexture&&Y.pmremVersion!==N){if($===null)$=new cW(J);return E=U?$.fromEquirectangular(Y,E):$.fromCubemap(Y,E),E.texture.pmremVersion=Y.pmremVersion,Q.set(Y,E),E.texture}else if(E!==void 0)return E.texture;else{let q=Y.image;if(U&&q&&q.height>0||G&&q&&W(q)){if($===null)$=new cW(J);return E=U?$.fromEquirectangular(Y):$.fromCubemap(Y),E.texture.pmremVersion=Y.pmremVersion,Q.set(Y,E),Y.addEventListener("dispose",K),E.texture}else return null}}}return Y}function W(Y){let X=0,U=6;for(let G=0;G<U;G++)if(Y[G]!==void 0)X++;return X===U}function K(Y){let X=Y.target;X.removeEventListener("dispose",K);let U=Q.get(X);if(U!==void 0)Q.delete(X),U.dispose()}function H(){if(Q=new WeakMap,$!==null)$.dispose(),$=null}return{get:Z,dispose:H}}function HD(J){let Q={};function $(Z){if(Q[Z]!==void 0)return Q[Z];let W;switch(Z){case"WEBGL_depth_texture":W=J.getExtension("WEBGL_depth_texture")||J.getExtension("MOZ_WEBGL_depth_texture")||J.getExtension("WEBKIT_WEBGL_depth_texture");break;case"EXT_texture_filter_anisotropic":W=J.getExtension("EXT_texture_filter_anisotropic")||J.getExtension("MOZ_EXT_texture_filter_anisotropic")||J.getExtension("WEBKIT_EXT_texture_filter_anisotropic");break;case"WEBGL_compressed_texture_s3tc":W=J.getExtension("WEBGL_compressed_texture_s3tc")||J.getExtension("MOZ_WEBGL_compressed_texture_s3tc")||J.getExtension("WEBKIT_WEBGL_compressed_texture_s3tc");break;case"WEBGL_compressed_texture_pvrtc":W=J.getExtension("WEBGL_compressed_texture_pvrtc")||J.getExtension("WEBKIT_WEBGL_compressed_texture_pvrtc");break;default:W=J.getExtension(Z)}return Q[Z]=W,W}return{has:function(Z){return $(Z)!==null},init:function(){$("EXT_color_buffer_float"),$("WEBGL_clip_cull_distance"),$("OES_texture_float_linear"),$("EXT_color_buffer_half_float"),$("WEBGL_multisampled_render_to_texture"),$("WEBGL_render_shared_exponent")},get:function(Z){let W=$(Z);if(W===null)o9("THREE.WebGLRenderer: "+Z+" extension not supported.");return W}}}function YD(J,Q,$,Z){let W={},K=new WeakMap;function H(E){let N=E.target;if(N.index!==null)Q.remove(N.index);for(let R in N.attributes)Q.remove(N.attributes[R]);N.removeEventListener("dispose",H),delete W[N.id];let q=K.get(N);if(q)Q.remove(q),K.delete(N);if(Z.releaseStatesOfGeometry(N),N.isInstancedBufferGeometry===!0)delete N._maxInstanceCount;$.memory.geometries--}function Y(E,N){if(W[N.id]===!0)return N;return N.addEventListener("dispose",H),W[N.id]=!0,$.memory.geometries++,N}function X(E){let N=E.attributes;for(let q in N)Q.update(N[q],J.ARRAY_BUFFER)}function U(E){let N=[],q=E.index,R=E.attributes.position,F=0;if(q!==null){let k=q.array;F=q.version;for(let M=0,L=k.length;M<L;M+=3){let A=k[M+0],_=k[M+1],C=k[M+2];N.push(A,_,_,C,C,A)}}else if(R!==void 0){let k=R.array;F=R.version;for(let M=0,L=k.length/3-1;M<L;M+=3){let A=M+0,_=M+1,C=M+2;N.push(A,_,_,C,C,A)}}else return;let O=new((gZ(N))?FQ:RQ)(N,1);O.version=F;let D=K.get(E);if(D)Q.remove(D);K.set(E,O)}function G(E){let N=K.get(E);if(N){let q=E.index;if(q!==null){if(N.version<q.version)U(E)}}else U(E);return K.get(E)}return{get:Y,update:X,getWireframeAttribute:G}}function XD(J,Q,$){let Z;function W(N){Z=N}let K,H;function Y(N){K=N.type,H=N.bytesPerElement}function X(N,q){J.drawElements(Z,q,K,N*H),$.update(q,Z,1)}function U(N,q,R){if(R===0)return;J.drawElementsInstanced(Z,q,K,N*H,R),$.update(q,Z,R)}function G(N,q,R){if(R===0)return;Q.get("WEBGL_multi_draw").multiDrawElementsWEBGL(Z,q,0,K,N,0,R);let O=0;for(let D=0;D<R;D++)O+=q[D];$.update(O,Z,1)}function E(N,q,R,F){if(R===0)return;let O=Q.get("WEBGL_multi_draw");if(O===null)for(let D=0;D<N.length;D++)U(N[D]/H,q[D],F[D]);else{O.multiDrawElementsInstancedWEBGL(Z,q,0,K,N,0,F,0,R);let D=0;for(let k=0;k<R;k++)D+=q[k]*F[k];$.update(D,Z,1)}}this.setMode=W,this.setIndex=Y,this.render=X,this.renderInstances=U,this.renderMultiDraw=G,this.renderMultiDrawInstances=E}function UD(J){let Q={geometries:0,textures:0},$={frame:0,calls:0,triangles:0,points:0,lines:0};function Z(K,H,Y){switch($.calls++,H){case J.TRIANGLES:$.triangles+=Y*(K/3);break;case J.LINES:$.lines+=Y*(K/2);break;case J.LINE_STRIP:$.lines+=Y*(K-1);break;case J.LINE_LOOP:$.lines+=Y*K;break;case J.POINTS:$.points+=Y*K;break;default:console.error("THREE.WebGLInfo: Unknown draw mode:",H);break}}function W(){$.calls=0,$.triangles=0,$.points=0,$.lines=0}return{memory:Q,render:$,programs:null,autoReset:!0,reset:W,update:Z}}function GD(J,Q,$){let Z=new WeakMap,W=new J0;function K(H,Y,X){let U=H.morphTargetInfluences,G=Y.morphAttributes.position||Y.morphAttributes.normal||Y.morphAttributes.color,E=G!==void 0?G.length:0,N=Z.get(Y);if(N===void 0||N.count!==E){let z=function(){C.dispose(),Z.delete(Y),Y.removeEventListener("dispose",z)};if(N!==void 0)N.texture.dispose();let q=Y.morphAttributes.position!==void 0,R=Y.morphAttributes.normal!==void 0,F=Y.morphAttributes.color!==void 0,O=Y.morphAttributes.position||[],D=Y.morphAttributes.normal||[],k=Y.morphAttributes.color||[],M=0;if(q===!0)M=1;if(R===!0)M=2;if(F===!0)M=3;let L=Y.attributes.position.count*M,A=1;if(L>Q.maxTextureSize)A=Math.ceil(L/Q.maxTextureSize),L=Q.maxTextureSize;let _=new Float32Array(L*A*4*E),C=new c6(_,L,A,E);C.type=l8,C.needsUpdate=!0;let y=M*4;for(let I=0;I<E;I++){let S=O[I],p=D[I],d=k[I],x=L*A*4*I;for(let o=0;o<S.count;o++){let l=o*y;if(q===!0)W.fromBufferAttribute(S,o),_[x+l+0]=W.x,_[x+l+1]=W.y,_[x+l+2]=W.z,_[x+l+3]=0;if(R===!0)W.fromBufferAttribute(p,o),_[x+l+4]=W.x,_[x+l+5]=W.y,_[x+l+6]=W.z,_[x+l+7]=0;if(F===!0)W.fromBufferAttribute(d,o),_[x+l+8]=W.x,_[x+l+9]=W.y,_[x+l+10]=W.z,_[x+l+11]=d.itemSize===4?W.w:1}}N={count:E,texture:C,size:new t(L,A)},Z.set(Y,N),Y.addEventListener("dispose",z)}if(H.isInstancedMesh===!0&&H.morphTexture!==null)X.getUniforms().setValue(J,"morphTexture",H.morphTexture,$);else{let q=0;for(let F=0;F<U.length;F++)q+=U[F];let R=Y.morphTargetsRelative?1:1-q;X.getUniforms().setValue(J,"morphTargetBaseInfluence",R),X.getUniforms().setValue(J,"morphTargetInfluences",U)}X.getUniforms().setValue(J,"morphTargetsTexture",N.texture,$),X.getUniforms().setValue(J,"morphTargetsTextureSize",N.size)}return{update:K}}function ED(J,Q,$,Z){let W=new WeakMap;function K(X){let U=Z.render.frame,G=X.geometry,E=Q.get(X,G);if(W.get(E)!==U)Q.update(E),W.set(E,U);if(X.isInstancedMesh){if(X.hasEventListener("dispose",Y)===!1)X.addEventListener("dispose",Y);if(W.get(X)!==U){if($.update(X.instanceMatrix,J.ARRAY_BUFFER),X.instanceColor!==null)$.update(X.instanceColor,J.ARRAY_BUFFER);W.set(X,U)}}if(X.isSkinnedMesh){let N=X.skeleton;if(W.get(N)!==U)N.update(),W.set(N,U)}return E}function H(){W=new WeakMap}function Y(X){let U=X.target;if(U.removeEventListener("dispose",Y),$.remove(U.instanceMatrix),U.instanceColor!==null)$.remove(U.instanceColor)}return{update:K,dispose:H}}var JU=new F0,bX=new _Q(1,1),QU=new c6,$U=new n6,ZU=new X6,hX=[],xX=[],gX=new Float32Array(16),pX=new Float32Array(9),mX=new Float32Array(4);function D6(J,Q,$){let Z=J[0];if(Z<=0||Z>0)return J;let W=Q*$,K=hX[W];if(K===void 0)K=new Float32Array(W),hX[W]=K;if(Q!==0){Z.toArray(K,0);for(let H=1,Y=0;H!==Q;++H)Y+=$,J[H].toArray(K,Y)}return K}function L0(J,Q){if(J.length!==Q.length)return!1;for(let $=0,Z=J.length;$<Z;$++)if(J[$]!==Q[$])return!1;return!0}function z0(J,Q){for(let $=0,Z=Q.length;$<Z;$++)J[$]=Q[$]}function Z$(J,Q){let $=xX[Q];if($===void 0)$=new Int32Array(Q),xX[Q]=$;for(let Z=0;Z!==Q;++Z)$[Z]=J.allocateTextureUnit();return $}function ND(J,Q){let $=this.cache;if($[0]===Q)return;J.uniform1f(this.addr,Q),$[0]=Q}function qD(J,Q){let $=this.cache;if(Q.x!==void 0){if($[0]!==Q.x||$[1]!==Q.y)J.uniform2f(this.addr,Q.x,Q.y),$[0]=Q.x,$[1]=Q.y}else{if(L0($,Q))return;J.uniform2fv(this.addr,Q),z0($,Q)}}function DD(J,Q){let $=this.cache;if(Q.x!==void 0){if($[0]!==Q.x||$[1]!==Q.y||$[2]!==Q.z)J.uniform3f(this.addr,Q.x,Q.y,Q.z),$[0]=Q.x,$[1]=Q.y,$[2]=Q.z}else if(Q.r!==void 0){if($[0]!==Q.r||$[1]!==Q.g||$[2]!==Q.b)J.uniform3f(this.addr,Q.r,Q.g,Q.b),$[0]=Q.r,$[1]=Q.g,$[2]=Q.b}else{if(L0($,Q))return;J.uniform3fv(this.addr,Q),z0($,Q)}}function OD(J,Q){let $=this.cache;if(Q.x!==void 0){if($[0]!==Q.x||$[1]!==Q.y||$[2]!==Q.z||$[3]!==Q.w)J.uniform4f(this.addr,Q.x,Q.y,Q.z,Q.w),$[0]=Q.x,$[1]=Q.y,$[2]=Q.z,$[3]=Q.w}else{if(L0($,Q))return;J.uniform4fv(this.addr,Q),z0($,Q)}}function RD(J,Q){let $=this.cache,Z=Q.elements;if(Z===void 0){if(L0($,Q))return;J.uniformMatrix2fv(this.addr,!1,Q),z0($,Q)}else{if(L0($,Z))return;mX.set(Z),J.uniformMatrix2fv(this.addr,!1,mX),z0($,Z)}}function FD(J,Q){let $=this.cache,Z=Q.elements;if(Z===void 0){if(L0($,Q))return;J.uniformMatrix3fv(this.addr,!1,Q),z0($,Q)}else{if(L0($,Z))return;pX.set(Z),J.uniformMatrix3fv(this.addr,!1,pX),z0($,Z)}}function MD(J,Q){let $=this.cache,Z=Q.elements;if(Z===void 0){if(L0($,Q))return;J.uniformMatrix4fv(this.addr,!1,Q),z0($,Q)}else{if(L0($,Z))return;gX.set(Z),J.uniformMatrix4fv(this.addr,!1,gX),z0($,Z)}}function kD(J,Q){let $=this.cache;if($[0]===Q)return;J.uniform1i(this.addr,Q),$[0]=Q}function VD(J,Q){let $=this.cache;if(Q.x!==void 0){if($[0]!==Q.x||$[1]!==Q.y)J.uniform2i(this.addr,Q.x,Q.y),$[0]=Q.x,$[1]=Q.y}else{if(L0($,Q))return;J.uniform2iv(this.addr,Q),z0($,Q)}}function LD(J,Q){let $=this.cache;if(Q.x!==void 0){if($[0]!==Q.x||$[1]!==Q.y||$[2]!==Q.z)J.uniform3i(this.addr,Q.x,Q.y,Q.z),$[0]=Q.x,$[1]=Q.y,$[2]=Q.z}else{if(L0($,Q))return;J.uniform3iv(this.addr,Q),z0($,Q)}}function zD(J,Q){let $=this.cache;if(Q.x!==void 0){if($[0]!==Q.x||$[1]!==Q.y||$[2]!==Q.z||$[3]!==Q.w)J.uniform4i(this.addr,Q.x,Q.y,Q.z,Q.w),$[0]=Q.x,$[1]=Q.y,$[2]=Q.z,$[3]=Q.w}else{if(L0($,Q))return;J.uniform4iv(this.addr,Q),z0($,Q)}}function BD(J,Q){let $=this.cache;if($[0]===Q)return;J.uniform1ui(this.addr,Q),$[0]=Q}function ID(J,Q){let $=this.cache;if(Q.x!==void 0){if($[0]!==Q.x||$[1]!==Q.y)J.uniform2ui(this.addr,Q.x,Q.y),$[0]=Q.x,$[1]=Q.y}else{if(L0($,Q))return;J.uniform2uiv(this.addr,Q),z0($,Q)}}function _D(J,Q){let $=this.cache;if(Q.x!==void 0){if($[0]!==Q.x||$[1]!==Q.y||$[2]!==Q.z)J.uniform3ui(this.addr,Q.x,Q.y,Q.z),$[0]=Q.x,$[1]=Q.y,$[2]=Q.z}else{if(L0($,Q))return;J.uniform3uiv(this.addr,Q),z0($,Q)}}function wD(J,Q){let $=this.cache;if(Q.x!==void 0){if($[0]!==Q.x||$[1]!==Q.y||$[2]!==Q.z||$[3]!==Q.w)J.uniform4ui(this.addr,Q.x,Q.y,Q.z,Q.w),$[0]=Q.x,$[1]=Q.y,$[2]=Q.z,$[3]=Q.w}else{if(L0($,Q))return;J.uniform4uiv(this.addr,Q),z0($,Q)}}function CD(J,Q,$){let Z=this.cache,W=$.allocateTextureUnit();if(Z[0]!==W)J.uniform1i(this.addr,W),Z[0]=W;let K;if(this.type===J.SAMPLER_2D_SHADOW)bX.compareFunction=fZ,K=bX;else K=JU;$.setTexture2D(Q||K,W)}function PD(J,Q,$){let Z=this.cache,W=$.allocateTextureUnit();if(Z[0]!==W)J.uniform1i(this.addr,W),Z[0]=W;$.setTexture3D(Q||$U,W)}function AD(J,Q,$){let Z=this.cache,W=$.allocateTextureUnit();if(Z[0]!==W)J.uniform1i(this.addr,W),Z[0]=W;$.setTextureCube(Q||ZU,W)}function TD(J,Q,$){let Z=this.cache,W=$.allocateTextureUnit();if(Z[0]!==W)J.uniform1i(this.addr,W),Z[0]=W;$.setTexture2DArray(Q||QU,W)}function SD(J){switch(J){case 5126:return ND;case 35664:return qD;case 35665:return DD;case 35666:return OD;case 35674:return RD;case 35675:return FD;case 35676:return MD;case 5124:case 35670:return kD;case 35667:case 35671:return VD;case 35668:case 35672:return LD;case 35669:case 35673:return zD;case 5125:return BD;case 36294:return ID;case 36295:return _D;case 36296:return wD;case 35678:case 36198:case 36298:case 36306:case 35682:return CD;case 35679:case 36299:case 36307:return PD;case 35680:case 36300:case 36308:case 36293:return AD;case 36289:case 36303:case 36311:case 36292:return TD}}function jD(J,Q){J.uniform1fv(this.addr,Q)}function yD(J,Q){let $=D6(Q,this.size,2);J.uniform2fv(this.addr,$)}function vD(J,Q){let $=D6(Q,this.size,3);J.uniform3fv(this.addr,$)}function fD(J,Q){let $=D6(Q,this.size,4);J.uniform4fv(this.addr,$)}function bD(J,Q){let $=D6(Q,this.size,4);J.uniformMatrix2fv(this.addr,!1,$)}function hD(J,Q){let $=D6(Q,this.size,9);J.uniformMatrix3fv(this.addr,!1,$)}function xD(J,Q){let $=D6(Q,this.size,16);J.uniformMatrix4fv(this.addr,!1,$)}function gD(J,Q){J.uniform1iv(this.addr,Q)}function pD(J,Q){J.uniform2iv(this.addr,Q)}function mD(J,Q){J.uniform3iv(this.addr,Q)}function dD(J,Q){J.uniform4iv(this.addr,Q)}function lD(J,Q){J.uniform1uiv(this.addr,Q)}function uD(J,Q){J.uniform2uiv(this.addr,Q)}function cD(J,Q){J.uniform3uiv(this.addr,Q)}function nD(J,Q){J.uniform4uiv(this.addr,Q)}function sD(J,Q,$){let Z=this.cache,W=Q.length,K=Z$($,W);if(!L0(Z,K))J.uniform1iv(this.addr,K),z0(Z,K);for(let H=0;H!==W;++H)$.setTexture2D(Q[H]||JU,K[H])}function iD(J,Q,$){let Z=this.cache,W=Q.length,K=Z$($,W);if(!L0(Z,K))J.uniform1iv(this.addr,K),z0(Z,K);for(let H=0;H!==W;++H)$.setTexture3D(Q[H]||$U,K[H])}function oD(J,Q,$){let Z=this.cache,W=Q.length,K=Z$($,W);if(!L0(Z,K))J.uniform1iv(this.addr,K),z0(Z,K);for(let H=0;H!==W;++H)$.setTextureCube(Q[H]||ZU,K[H])}function aD(J,Q,$){let Z=this.cache,W=Q.length,K=Z$($,W);if(!L0(Z,K))J.uniform1iv(this.addr,K),z0(Z,K);for(let H=0;H!==W;++H)$.setTexture2DArray(Q[H]||QU,K[H])}function rD(J){switch(J){case 5126:return jD;case 35664:return yD;case 35665:return vD;case 35666:return fD;case 35674:return bD;case 35675:return hD;case 35676:return xD;case 5124:case 35670:return gD;case 35667:case 35671:return pD;case 35668:case 35672:return mD;case 35669:case 35673:return dD;case 5125:return lD;case 36294:return uD;case 36295:return cD;case 36296:return nD;case 35678:case 36198:case 36298:case 36306:case 35682:return sD;case 35679:case 36299:case 36307:return iD;case 35680:case 36300:case 36308:case 36293:return oD;case 36289:case 36303:case 36311:case 36292:return aD}}class WU{constructor(J,Q,$){this.id=J,this.addr=$,this.cache=[],this.type=Q.type,this.setValue=SD(Q.type)}}class KU{constructor(J,Q,$){this.id=J,this.addr=$,this.cache=[],this.type=Q.type,this.size=Q.size,this.setValue=rD(Q.type)}}class HU{constructor(J){this.id=J,this.seq=[],this.map={}}setValue(J,Q,$){let Z=this.seq;for(let W=0,K=Z.length;W!==K;++W){let H=Z[W];H.setValue(J,Q[H.id],$)}}}var uW=/(\w+)(\])?(\[|\.)?/g;function dX(J,Q){J.seq.push(Q),J.map[Q.id]=Q}function tD(J,Q,$){let Z=J.name,W=Z.length;uW.lastIndex=0;while(!0){let K=uW.exec(Z),H=uW.lastIndex,Y=K[1],X=K[2]==="]",U=K[3];if(X)Y=Y|0;if(U===void 0||U==="["&&H+2===W){dX($,U===void 0?new WU(Y,J,Q):new KU(Y,J,Q));break}else{let E=$.map[Y];if(E===void 0)E=new HU(Y),dX($,E);$=E}}}class K7{constructor(J,Q){this.seq=[],this.map={};let $=J.getProgramParameter(Q,J.ACTIVE_UNIFORMS);for(let Z=0;Z<$;++Z){let W=J.getActiveUniform(Q,Z),K=J.getUniformLocation(Q,W.name);tD(W,K,this)}}setValue(J,Q,$,Z){let W=this.map[Q];if(W!==void 0)W.setValue(J,$,Z)}setOptional(J,Q,$){let Z=Q[$];if(Z!==void 0)this.setValue(J,$,Z)}static upload(J,Q,$,Z){for(let W=0,K=Q.length;W!==K;++W){let H=Q[W],Y=$[H.id];if(Y.needsUpdate!==!1)H.setValue(J,Y.value,Z)}}static seqWithValue(J,Q){let $=[];for(let Z=0,W=J.length;Z!==W;++Z){let K=J[Z];if(K.id in Q)$.push(K)}return $}}function lX(J,Q,$){let Z=J.createShader(Q);return J.shaderSource(Z,$),J.compileShader(Z),Z}var eD=37297,J5=0;function Q5(J,Q){let $=J.split(`
`),Z=[],W=Math.max(Q-6,0),K=Math.min(Q+6,$.length);for(let H=W;H<K;H++){let Y=H+1;Z.push(`${Y===Q?">":" "} ${Y}: ${$[H]}`)}return Z.join(`
`)}var uX=new dJ;function $5(J){tJ._getMatrix(uX,tJ.workingColorSpace,J);let Q=`mat3( ${uX.elements.map(($)=>$.toFixed(4))} )`;switch(tJ.getTransfer(J)){case vZ:return[Q,"LinearTransferOETF"];case G0:return[Q,"sRGBTransferOETF"];default:return console.warn("THREE.WebGLProgram: Unsupported color space: ",J),[Q,"LinearTransferOETF"]}}function cX(J,Q,$){let Z=J.getShaderParameter(Q,J.COMPILE_STATUS),K=(J.getShaderInfoLog(Q)||"").trim();if(Z&&K==="")return"";let H=/ERROR: 0:(\d+)/.exec(K);if(H){let Y=parseInt(H[1]);return $.toUpperCase()+`

`+K+`

`+Q5(J.getShaderSource(Q),Y)}else return K}function Z5(J,Q){let $=$5(Q);return[`vec4 ${J}( vec4 value ) {`,`	return ${$[1]}( vec4( value.rgb * ${$[0]}, value.a ) );`,"}"].join(`
`)}function W5(J,Q){let $;switch(Q){case yH:$="Linear";break;case vH:$="Reinhard";break;case fH:$="Cineon";break;case bH:$="ACESFilmic";break;case xH:$="AgX";break;case gH:$="Neutral";break;case hH:$="Custom";break;default:console.warn("THREE.WebGLProgram: Unsupported toneMapping:",Q),$="Linear"}return"vec3 "+J+"( vec3 color ) { return "+$+"ToneMapping( color ); }"}var $$=new w;function K5(){tJ.getLuminanceCoefficients($$);let J=$$.x.toFixed(4),Q=$$.y.toFixed(4),$=$$.z.toFixed(4);return["float luminance( const in vec3 rgb ) {",`	const vec3 weights = vec3( ${J}, ${Q}, ${$} );`,"\treturn dot( weights, rgb );","}"].join(`
`)}function H5(J){return[J.extensionClipCullDistance?"#extension GL_ANGLE_clip_cull_distance : require":"",J.extensionMultiDraw?"#extension GL_ANGLE_multi_draw : require":""].filter(W7).join(`
`)}function Y5(J){let Q=[];for(let $ in J){let Z=J[$];if(Z===!1)continue;Q.push("#define "+$+" "+Z)}return Q.join(`
`)}function X5(J,Q){let $={},Z=J.getProgramParameter(Q,J.ACTIVE_ATTRIBUTES);for(let W=0;W<Z;W++){let K=J.getActiveAttrib(Q,W),H=K.name,Y=1;if(K.type===J.FLOAT_MAT2)Y=2;if(K.type===J.FLOAT_MAT3)Y=3;if(K.type===J.FLOAT_MAT4)Y=4;$[H]={type:K.type,location:J.getAttribLocation(Q,H),locationSize:Y}}return $}function W7(J){return J!==""}function nX(J,Q){let $=Q.numSpotLightShadows+Q.numSpotLightMaps-Q.numSpotLightShadowsWithMaps;return J.replace(/NUM_DIR_LIGHTS/g,Q.numDirLights).replace(/NUM_SPOT_LIGHTS/g,Q.numSpotLights).replace(/NUM_SPOT_LIGHT_MAPS/g,Q.numSpotLightMaps).replace(/NUM_SPOT_LIGHT_COORDS/g,$).replace(/NUM_RECT_AREA_LIGHTS/g,Q.numRectAreaLights).replace(/NUM_POINT_LIGHTS/g,Q.numPointLights).replace(/NUM_HEMI_LIGHTS/g,Q.numHemiLights).replace(/NUM_DIR_LIGHT_SHADOWS/g,Q.numDirLightShadows).replace(/NUM_SPOT_LIGHT_SHADOWS_WITH_MAPS/g,Q.numSpotLightShadowsWithMaps).replace(/NUM_SPOT_LIGHT_SHADOWS/g,Q.numSpotLightShadows).replace(/NUM_POINT_LIGHT_SHADOWS/g,Q.numPointLightShadows)}function sX(J,Q){return J.replace(/NUM_CLIPPING_PLANES/g,Q.numClippingPlanes).replace(/UNION_CLIPPING_PLANES/g,Q.numClippingPlanes-Q.numClipIntersection)}var U5=/^[ \t]*#include +<([\w\d./]+)>/gm;function nW(J){return J.replace(U5,E5)}var G5=new Map;function E5(J,Q){let $=iJ[Q];if($===void 0){let Z=G5.get(Q);if(Z!==void 0)$=iJ[Z],console.warn('THREE.WebGLRenderer: Shader chunk "%s" has been deprecated. Use "%s" instead.',Q,Z);else throw Error("Can not resolve #include <"+Q+">")}return nW($)}var N5=/#pragma unroll_loop_start\s+for\s*\(\s*int\s+i\s*=\s*(\d+)\s*;\s*i\s*<\s*(\d+)\s*;\s*i\s*\+\+\s*\)\s*{([\s\S]+?)}\s+#pragma unroll_loop_end/g;function iX(J){return J.replace(N5,q5)}function q5(J,Q,$,Z){let W="";for(let K=parseInt(Q);K<parseInt($);K++)W+=Z.replace(/\[\s*i\s*\]/g,"[ "+K+" ]").replace(/UNROLLED_LOOP_INDEX/g,K);return W}function oX(J){let Q=`precision ${J.precision} float;
	precision ${J.precision} int;
	precision ${J.precision} sampler2D;
	precision ${J.precision} samplerCube;
	precision ${J.precision} sampler3D;
	precision ${J.precision} sampler2DArray;
	precision ${J.precision} sampler2DShadow;
	precision ${J.precision} samplerCubeShadow;
	precision ${J.precision} sampler2DArrayShadow;
	precision ${J.precision} isampler2D;
	precision ${J.precision} isampler3D;
	precision ${J.precision} isamplerCube;
	precision ${J.precision} isampler2DArray;
	precision ${J.precision} usampler2D;
	precision ${J.precision} usampler3D;
	precision ${J.precision} usamplerCube;
	precision ${J.precision} usampler2DArray;
	`;if(J.precision==="highp")Q+=`
#define HIGH_PRECISION`;else if(J.precision==="mediump")Q+=`
#define MEDIUM_PRECISION`;else if(J.precision==="lowp")Q+=`
#define LOW_PRECISION`;return Q}function D5(J){let Q="SHADOWMAP_TYPE_BASIC";if(J.shadowMapType===a$)Q="SHADOWMAP_TYPE_PCF";else if(J.shadowMapType===UH)Q="SHADOWMAP_TYPE_PCF_SOFT";else if(J.shadowMapType===O8)Q="SHADOWMAP_TYPE_VSM";return Q}function O5(J){let Q="ENVMAP_TYPE_CUBE";if(J.envMap)switch(J.envMapMode){case Z6:case D9:Q="ENVMAP_TYPE_CUBE";break;case g6:Q="ENVMAP_TYPE_CUBE_UV";break}return Q}function R5(J){let Q="ENVMAP_MODE_REFLECTION";if(J.envMap)switch(J.envMapMode){case D9:Q="ENVMAP_MODE_REFRACTION";break}return Q}function F5(J){let Q="ENVMAP_BLENDING_NONE";if(J.envMap)switch(J.combine){case TH:Q="ENVMAP_BLENDING_MULTIPLY";break;case SH:Q="ENVMAP_BLENDING_MIX";break;case jH:Q="ENVMAP_BLENDING_ADD";break}return Q}function M5(J){let Q=J.envMapCubeUVHeight;if(Q===null)return null;let $=Math.log2(Q)-2,Z=1/Q;return{texelWidth:1/(3*Math.max(Math.pow(2,$),112)),texelHeight:Z,maxMip:$}}function k5(J,Q,$,Z){let W=J.getContext(),K=$.defines,H=$.vertexShader,Y=$.fragmentShader,X=D5($),U=O5($),G=R5($),E=F5($),N=M5($),q=H5($),R=Y5(K),F=W.createProgram(),O,D,k=$.glslVersion?"#version "+$.glslVersion+`
`:"";if($.isRawShaderMaterial){if(O=["#define SHADER_TYPE "+$.shaderType,"#define SHADER_NAME "+$.shaderName,R].filter(W7).join(`
`),O.length>0)O+=`
`;if(D=["#define SHADER_TYPE "+$.shaderType,"#define SHADER_NAME "+$.shaderName,R].filter(W7).join(`
`),D.length>0)D+=`
`}else O=[oX($),"#define SHADER_TYPE "+$.shaderType,"#define SHADER_NAME "+$.shaderName,R,$.extensionClipCullDistance?"#define USE_CLIP_DISTANCE":"",$.batching?"#define USE_BATCHING":"",$.batchingColor?"#define USE_BATCHING_COLOR":"",$.instancing?"#define USE_INSTANCING":"",$.instancingColor?"#define USE_INSTANCING_COLOR":"",$.instancingMorph?"#define USE_INSTANCING_MORPH":"",$.useFog&&$.fog?"#define USE_FOG":"",$.useFog&&$.fogExp2?"#define FOG_EXP2":"",$.map?"#define USE_MAP":"",$.envMap?"#define USE_ENVMAP":"",$.envMap?"#define "+G:"",$.lightMap?"#define USE_LIGHTMAP":"",$.aoMap?"#define USE_AOMAP":"",$.bumpMap?"#define USE_BUMPMAP":"",$.normalMap?"#define USE_NORMALMAP":"",$.normalMapObjectSpace?"#define USE_NORMALMAP_OBJECTSPACE":"",$.normalMapTangentSpace?"#define USE_NORMALMAP_TANGENTSPACE":"",$.displacementMap?"#define USE_DISPLACEMENTMAP":"",$.emissiveMap?"#define USE_EMISSIVEMAP":"",$.anisotropy?"#define USE_ANISOTROPY":"",$.anisotropyMap?"#define USE_ANISOTROPYMAP":"",$.clearcoatMap?"#define USE_CLEARCOATMAP":"",$.clearcoatRoughnessMap?"#define USE_CLEARCOAT_ROUGHNESSMAP":"",$.clearcoatNormalMap?"#define USE_CLEARCOAT_NORMALMAP":"",$.iridescenceMap?"#define USE_IRIDESCENCEMAP":"",$.iridescenceThicknessMap?"#define USE_IRIDESCENCE_THICKNESSMAP":"",$.specularMap?"#define USE_SPECULARMAP":"",$.specularColorMap?"#define USE_SPECULAR_COLORMAP":"",$.specularIntensityMap?"#define USE_SPECULAR_INTENSITYMAP":"",$.roughnessMap?"#define USE_ROUGHNESSMAP":"",$.metalnessMap?"#define USE_METALNESSMAP":"",$.alphaMap?"#define USE_ALPHAMAP":"",$.alphaHash?"#define USE_ALPHAHASH":"",$.transmission?"#define USE_TRANSMISSION":"",$.transmissionMap?"#define USE_TRANSMISSIONMAP":"",$.thicknessMap?"#define USE_THICKNESSMAP":"",$.sheenColorMap?"#define USE_SHEEN_COLORMAP":"",$.sheenRoughnessMap?"#define USE_SHEEN_ROUGHNESSMAP":"",$.mapUv?"#define MAP_UV "+$.mapUv:"",$.alphaMapUv?"#define ALPHAMAP_UV "+$.alphaMapUv:"",$.lightMapUv?"#define LIGHTMAP_UV "+$.lightMapUv:"",$.aoMapUv?"#define AOMAP_UV "+$.aoMapUv:"",$.emissiveMapUv?"#define EMISSIVEMAP_UV "+$.emissiveMapUv:"",$.bumpMapUv?"#define BUMPMAP_UV "+$.bumpMapUv:"",$.normalMapUv?"#define NORMALMAP_UV "+$.normalMapUv:"",$.displacementMapUv?"#define DISPLACEMENTMAP_UV "+$.displacementMapUv:"",$.metalnessMapUv?"#define METALNESSMAP_UV "+$.metalnessMapUv:"",$.roughnessMapUv?"#define ROUGHNESSMAP_UV "+$.roughnessMapUv:"",$.anisotropyMapUv?"#define ANISOTROPYMAP_UV "+$.anisotropyMapUv:"",$.clearcoatMapUv?"#define CLEARCOATMAP_UV "+$.clearcoatMapUv:"",$.clearcoatNormalMapUv?"#define CLEARCOAT_NORMALMAP_UV "+$.clearcoatNormalMapUv:"",$.clearcoatRoughnessMapUv?"#define CLEARCOAT_ROUGHNESSMAP_UV "+$.clearcoatRoughnessMapUv:"",$.iridescenceMapUv?"#define IRIDESCENCEMAP_UV "+$.iridescenceMapUv:"",$.iridescenceThicknessMapUv?"#define IRIDESCENCE_THICKNESSMAP_UV "+$.iridescenceThicknessMapUv:"",$.sheenColorMapUv?"#define SHEEN_COLORMAP_UV "+$.sheenColorMapUv:"",$.sheenRoughnessMapUv?"#define SHEEN_ROUGHNESSMAP_UV "+$.sheenRoughnessMapUv:"",$.specularMapUv?"#define SPECULARMAP_UV "+$.specularMapUv:"",$.specularColorMapUv?"#define SPECULAR_COLORMAP_UV "+$.specularColorMapUv:"",$.specularIntensityMapUv?"#define SPECULAR_INTENSITYMAP_UV "+$.specularIntensityMapUv:"",$.transmissionMapUv?"#define TRANSMISSIONMAP_UV "+$.transmissionMapUv:"",$.thicknessMapUv?"#define THICKNESSMAP_UV "+$.thicknessMapUv:"",$.vertexTangents&&$.flatShading===!1?"#define USE_TANGENT":"",$.vertexColors?"#define USE_COLOR":"",$.vertexAlphas?"#define USE_COLOR_ALPHA":"",$.vertexUv1s?"#define USE_UV1":"",$.vertexUv2s?"#define USE_UV2":"",$.vertexUv3s?"#define USE_UV3":"",$.pointsUvs?"#define USE_POINTS_UV":"",$.flatShading?"#define FLAT_SHADED":"",$.skinning?"#define USE_SKINNING":"",$.morphTargets?"#define USE_MORPHTARGETS":"",$.morphNormals&&$.flatShading===!1?"#define USE_MORPHNORMALS":"",$.morphColors?"#define USE_MORPHCOLORS":"",$.morphTargetsCount>0?"#define MORPHTARGETS_TEXTURE_STRIDE "+$.morphTextureStride:"",$.morphTargetsCount>0?"#define MORPHTARGETS_COUNT "+$.morphTargetsCount:"",$.doubleSided?"#define DOUBLE_SIDED":"",$.flipSided?"#define FLIP_SIDED":"",$.shadowMapEnabled?"#define USE_SHADOWMAP":"",$.shadowMapEnabled?"#define "+X:"",$.sizeAttenuation?"#define USE_SIZEATTENUATION":"",$.numLightProbes>0?"#define USE_LIGHT_PROBES":"",$.logarithmicDepthBuffer?"#define USE_LOGARITHMIC_DEPTH_BUFFER":"",$.reversedDepthBuffer?"#define USE_REVERSED_DEPTH_BUFFER":"","uniform mat4 modelMatrix;","uniform mat4 modelViewMatrix;","uniform mat4 projectionMatrix;","uniform mat4 viewMatrix;","uniform mat3 normalMatrix;","uniform vec3 cameraPosition;","uniform bool isOrthographic;","#ifdef USE_INSTANCING","\tattribute mat4 instanceMatrix;","#endif","#ifdef USE_INSTANCING_COLOR","\tattribute vec3 instanceColor;","#endif","#ifdef USE_INSTANCING_MORPH","\tuniform sampler2D morphTexture;","#endif","attribute vec3 position;","attribute vec3 normal;","attribute vec2 uv;","#ifdef USE_UV1","\tattribute vec2 uv1;","#endif","#ifdef USE_UV2","\tattribute vec2 uv2;","#endif","#ifdef USE_UV3","\tattribute vec2 uv3;","#endif","#ifdef USE_TANGENT","\tattribute vec4 tangent;","#endif","#if defined( USE_COLOR_ALPHA )","\tattribute vec4 color;","#elif defined( USE_COLOR )","\tattribute vec3 color;","#endif","#ifdef USE_SKINNING","\tattribute vec4 skinIndex;","\tattribute vec4 skinWeight;","#endif",`
`].filter(W7).join(`
`),D=[oX($),"#define SHADER_TYPE "+$.shaderType,"#define SHADER_NAME "+$.shaderName,R,$.useFog&&$.fog?"#define USE_FOG":"",$.useFog&&$.fogExp2?"#define FOG_EXP2":"",$.alphaToCoverage?"#define ALPHA_TO_COVERAGE":"",$.map?"#define USE_MAP":"",$.matcap?"#define USE_MATCAP":"",$.envMap?"#define USE_ENVMAP":"",$.envMap?"#define "+U:"",$.envMap?"#define "+G:"",$.envMap?"#define "+E:"",N?"#define CUBEUV_TEXEL_WIDTH "+N.texelWidth:"",N?"#define CUBEUV_TEXEL_HEIGHT "+N.texelHeight:"",N?"#define CUBEUV_MAX_MIP "+N.maxMip+".0":"",$.lightMap?"#define USE_LIGHTMAP":"",$.aoMap?"#define USE_AOMAP":"",$.bumpMap?"#define USE_BUMPMAP":"",$.normalMap?"#define USE_NORMALMAP":"",$.normalMapObjectSpace?"#define USE_NORMALMAP_OBJECTSPACE":"",$.normalMapTangentSpace?"#define USE_NORMALMAP_TANGENTSPACE":"",$.emissiveMap?"#define USE_EMISSIVEMAP":"",$.anisotropy?"#define USE_ANISOTROPY":"",$.anisotropyMap?"#define USE_ANISOTROPYMAP":"",$.clearcoat?"#define USE_CLEARCOAT":"",$.clearcoatMap?"#define USE_CLEARCOATMAP":"",$.clearcoatRoughnessMap?"#define USE_CLEARCOAT_ROUGHNESSMAP":"",$.clearcoatNormalMap?"#define USE_CLEARCOAT_NORMALMAP":"",$.dispersion?"#define USE_DISPERSION":"",$.iridescence?"#define USE_IRIDESCENCE":"",$.iridescenceMap?"#define USE_IRIDESCENCEMAP":"",$.iridescenceThicknessMap?"#define USE_IRIDESCENCE_THICKNESSMAP":"",$.specularMap?"#define USE_SPECULARMAP":"",$.specularColorMap?"#define USE_SPECULAR_COLORMAP":"",$.specularIntensityMap?"#define USE_SPECULAR_INTENSITYMAP":"",$.roughnessMap?"#define USE_ROUGHNESSMAP":"",$.metalnessMap?"#define USE_METALNESSMAP":"",$.alphaMap?"#define USE_ALPHAMAP":"",$.alphaTest?"#define USE_ALPHATEST":"",$.alphaHash?"#define USE_ALPHAHASH":"",$.sheen?"#define USE_SHEEN":"",$.sheenColorMap?"#define USE_SHEEN_COLORMAP":"",$.sheenRoughnessMap?"#define USE_SHEEN_ROUGHNESSMAP":"",$.transmission?"#define USE_TRANSMISSION":"",$.transmissionMap?"#define USE_TRANSMISSIONMAP":"",$.thicknessMap?"#define USE_THICKNESSMAP":"",$.vertexTangents&&$.flatShading===!1?"#define USE_TANGENT":"",$.vertexColors||$.instancingColor||$.batchingColor?"#define USE_COLOR":"",$.vertexAlphas?"#define USE_COLOR_ALPHA":"",$.vertexUv1s?"#define USE_UV1":"",$.vertexUv2s?"#define USE_UV2":"",$.vertexUv3s?"#define USE_UV3":"",$.pointsUvs?"#define USE_POINTS_UV":"",$.gradientMap?"#define USE_GRADIENTMAP":"",$.flatShading?"#define FLAT_SHADED":"",$.doubleSided?"#define DOUBLE_SIDED":"",$.flipSided?"#define FLIP_SIDED":"",$.shadowMapEnabled?"#define USE_SHADOWMAP":"",$.shadowMapEnabled?"#define "+X:"",$.premultipliedAlpha?"#define PREMULTIPLIED_ALPHA":"",$.numLightProbes>0?"#define USE_LIGHT_PROBES":"",$.decodeVideoTexture?"#define DECODE_VIDEO_TEXTURE":"",$.decodeVideoTextureEmissive?"#define DECODE_VIDEO_TEXTURE_EMISSIVE":"",$.logarithmicDepthBuffer?"#define USE_LOGARITHMIC_DEPTH_BUFFER":"",$.reversedDepthBuffer?"#define USE_REVERSED_DEPTH_BUFFER":"","uniform mat4 viewMatrix;","uniform vec3 cameraPosition;","uniform bool isOrthographic;",$.toneMapping!==T8?"#define TONE_MAPPING":"",$.toneMapping!==T8?iJ.tonemapping_pars_fragment:"",$.toneMapping!==T8?W5("toneMapping",$.toneMapping):"",$.dithering?"#define DITHERING":"",$.opaque?"#define OPAQUE":"",iJ.colorspace_pars_fragment,Z5("linearToOutputTexel",$.outputColorSpace),K5(),$.useDepthPacking?"#define DEPTH_PACKING "+$.depthPacking:"",`
`].filter(W7).join(`
`);if(H=nW(H),H=nX(H,$),H=sX(H,$),Y=nW(Y),Y=nX(Y,$),Y=sX(Y,$),H=iX(H),Y=iX(Y),$.isRawShaderMaterial!==!0)k=`#version 300 es
`,O=[q,"#define attribute in","#define varying out","#define texture2D texture"].join(`
`)+`
`+O,D=["#define varying in",$.glslVersion===bZ?"":"layout(location = 0) out highp vec4 pc_fragColor;",$.glslVersion===bZ?"":"#define gl_FragColor pc_fragColor","#define gl_FragDepthEXT gl_FragDepth","#define texture2D texture","#define textureCube texture","#define texture2DProj textureProj","#define texture2DLodEXT textureLod","#define texture2DProjLodEXT textureProjLod","#define textureCubeLodEXT textureLod","#define texture2DGradEXT textureGrad","#define texture2DProjGradEXT textureProjGrad","#define textureCubeGradEXT textureGrad"].join(`
`)+`
`+D;let M=k+O+H,L=k+D+Y,A=lX(W,W.VERTEX_SHADER,M),_=lX(W,W.FRAGMENT_SHADER,L);if(W.attachShader(F,A),W.attachShader(F,_),$.index0AttributeName!==void 0)W.bindAttribLocation(F,0,$.index0AttributeName);else if($.morphTargets===!0)W.bindAttribLocation(F,0,"position");W.linkProgram(F);function C(S){if(J.debug.checkShaderErrors){let p=W.getProgramInfoLog(F)||"",d=W.getShaderInfoLog(A)||"",x=W.getShaderInfoLog(_)||"",o=p.trim(),l=d.trim(),QJ=x.trim(),m=!0,EJ=!0;if(W.getProgramParameter(F,W.LINK_STATUS)===!1)if(m=!1,typeof J.debug.onShaderError==="function")J.debug.onShaderError(W,F,A,_);else{let NJ=cX(W,A,"vertex"),SJ=cX(W,_,"fragment");console.error("THREE.WebGLProgram: Shader Error "+W.getError()+" - VALIDATE_STATUS "+W.getProgramParameter(F,W.VALIDATE_STATUS)+`

Material Name: `+S.name+`
Material Type: `+S.type+`

Program Info Log: `+o+`
`+NJ+`
`+SJ)}else if(o!=="")console.warn("THREE.WebGLProgram: Program Info Log:",o);else if(l===""||QJ==="")EJ=!1;if(EJ)S.diagnostics={runnable:m,programLog:o,vertexShader:{log:l,prefix:O},fragmentShader:{log:QJ,prefix:D}}}W.deleteShader(A),W.deleteShader(_),y=new K7(W,F),z=X5(W,F)}let y;this.getUniforms=function(){if(y===void 0)C(this);return y};let z;this.getAttributes=function(){if(z===void 0)C(this);return z};let I=$.rendererExtensionParallelShaderCompile===!1;return this.isReady=function(){if(I===!1)I=W.getProgramParameter(F,eD);return I},this.destroy=function(){Z.releaseStatesOfProgram(this),W.deleteProgram(F),this.program=void 0},this.type=$.shaderType,this.name=$.shaderName,this.id=J5++,this.cacheKey=Q,this.usedTimes=1,this.program=F,this.vertexShader=A,this.fragmentShader=_,this}var V5=0;class YU{constructor(){this.shaderCache=new Map,this.materialCache=new Map}update(J){let{vertexShader:Q,fragmentShader:$}=J,Z=this._getShaderStage(Q),W=this._getShaderStage($),K=this._getShaderCacheForMaterial(J);if(K.has(Z)===!1)K.add(Z),Z.usedTimes++;if(K.has(W)===!1)K.add(W),W.usedTimes++;return this}remove(J){let Q=this.materialCache.get(J);for(let $ of Q)if($.usedTimes--,$.usedTimes===0)this.shaderCache.delete($.code);return this.materialCache.delete(J),this}getVertexShaderID(J){return this._getShaderStage(J.vertexShader).id}getFragmentShaderID(J){return this._getShaderStage(J.fragmentShader).id}dispose(){this.shaderCache.clear(),this.materialCache.clear()}_getShaderCacheForMaterial(J){let Q=this.materialCache,$=Q.get(J);if($===void 0)$=new Set,Q.set(J,$);return $}_getShaderStage(J){let Q=this.shaderCache,$=Q.get(J);if($===void 0)$=new XU(J),Q.set(J,$);return $}}class XU{constructor(J){this.id=V5++,this.code=J,this.usedTimes=0}}function L5(J,Q,$,Z,W,K,H){let Y=new s6,X=new YU,U=new Set,G=[],E=W.logarithmicDepthBuffer,N=W.vertexTextures,q=W.precision,R={MeshDepthMaterial:"depth",MeshDistanceMaterial:"distanceRGBA",MeshNormalMaterial:"normal",MeshBasicMaterial:"basic",MeshLambertMaterial:"lambert",MeshPhongMaterial:"phong",MeshToonMaterial:"toon",MeshStandardMaterial:"physical",MeshPhysicalMaterial:"physical",MeshMatcapMaterial:"matcap",LineBasicMaterial:"basic",LineDashedMaterial:"dashed",PointsMaterial:"points",ShadowMaterial:"shadow",SpriteMaterial:"sprite"};function F(z){if(U.add(z),z===0)return"uv";return`uv${z}`}function O(z,I,S,p,d){let x=p.fog,o=d.geometry,l=z.isMeshStandardMaterial?p.environment:null,QJ=(z.isMeshStandardMaterial?$:Q).get(z.envMap||l),m=!!QJ&&QJ.mapping===g6?QJ.image.height:null,EJ=R[z.type];if(z.precision!==null){if(q=W.getMaxPrecision(z.precision),q!==z.precision)console.warn("THREE.WebGLProgram.getParameters:",z.precision,"not supported, using",q,"instead.")}let NJ=o.morphAttributes.position||o.morphAttributes.normal||o.morphAttributes.color,SJ=NJ!==void 0?NJ.length:0,mJ=0;if(o.morphAttributes.position!==void 0)mJ=1;if(o.morphAttributes.normal!==void 0)mJ=2;if(o.morphAttributes.color!==void 0)mJ=3;let U0,rJ,s,qJ;if(EJ){let K0=M8[EJ];U0=K0.vertexShader,rJ=K0.fragmentShader}else U0=z.vertexShader,rJ=z.fragmentShader,X.update(z),s=X.getVertexShaderID(z),qJ=X.getFragmentShaderID(z);let XJ=J.getRenderTarget(),LJ=J.state.buffers.depth.getReversed(),yJ=d.isInstancedMesh===!0,xJ=d.isBatchedMesh===!0,W0=!!z.map,T=!!z.matcap,e=!!QJ,a=!!z.aoMap,i=!!z.lightMap,n=!!z.bumpMap,UJ=!!z.normalMap,HJ=!!z.displacementMap,ZJ=!!z.emissiveMap,lJ=!!z.metalnessMap,uJ=!!z.roughnessMap,sJ=z.anisotropy>0,P=z.clearcoat>0,V=z.dispersion>0,v=z.iridescence>0,c=z.sheen>0,JJ=z.transmission>0,u=sJ&&!!z.anisotropyMap,VJ=P&&!!z.clearcoatMap,YJ=P&&!!z.clearcoatNormalMap,_J=P&&!!z.clearcoatRoughnessMap,vJ=v&&!!z.iridescenceMap,KJ=v&&!!z.iridescenceThicknessMap,FJ=c&&!!z.sheenColorMap,PJ=c&&!!z.sheenRoughnessMap,AJ=!!z.specularMap,MJ=!!z.specularColorMap,oJ=!!z.specularIntensityMap,j=JJ&&!!z.transmissionMap,OJ=JJ&&!!z.thicknessMap,GJ=!!z.gradientMap,IJ=!!z.alphaMap,$J=z.alphaTest>0,r=!!z.alphaHash,CJ=!!z.extensions,pJ=T8;if(z.toneMapped){if(XJ===null||XJ.isXRRenderTarget===!0)pJ=J.toneMapping}let Y0={shaderID:EJ,shaderType:z.type,shaderName:z.name,vertexShader:U0,fragmentShader:rJ,defines:z.defines,customVertexShaderID:s,customFragmentShaderID:qJ,isRawShaderMaterial:z.isRawShaderMaterial===!0,glslVersion:z.glslVersion,precision:q,batching:xJ,batchingColor:xJ&&d._colorsTexture!==null,instancing:yJ,instancingColor:yJ&&d.instanceColor!==null,instancingMorph:yJ&&d.morphTexture!==null,supportsVertexTextures:N,outputColorSpace:XJ===null?J.outputColorSpace:XJ.isXRRenderTarget===!0?XJ.texture.colorSpace:u6,alphaToCoverage:!!z.alphaToCoverage,map:W0,matcap:T,envMap:e,envMapMode:e&&QJ.mapping,envMapCubeUVHeight:m,aoMap:a,lightMap:i,bumpMap:n,normalMap:UJ,displacementMap:N&&HJ,emissiveMap:ZJ,normalMapObjectSpace:UJ&&z.normalMapType===JY,normalMapTangentSpace:UJ&&z.normalMapType===eH,metalnessMap:lJ,roughnessMap:uJ,anisotropy:sJ,anisotropyMap:u,clearcoat:P,clearcoatMap:VJ,clearcoatNormalMap:YJ,clearcoatRoughnessMap:_J,dispersion:V,iridescence:v,iridescenceMap:vJ,iridescenceThicknessMap:KJ,sheen:c,sheenColorMap:FJ,sheenRoughnessMap:PJ,specularMap:AJ,specularColorMap:MJ,specularIntensityMap:oJ,transmission:JJ,transmissionMap:j,thicknessMap:OJ,gradientMap:GJ,opaque:z.transparent===!1&&z.blending===h6&&z.alphaToCoverage===!1,alphaMap:IJ,alphaTest:$J,alphaHash:r,combine:z.combine,mapUv:W0&&F(z.map.channel),aoMapUv:a&&F(z.aoMap.channel),lightMapUv:i&&F(z.lightMap.channel),bumpMapUv:n&&F(z.bumpMap.channel),normalMapUv:UJ&&F(z.normalMap.channel),displacementMapUv:HJ&&F(z.displacementMap.channel),emissiveMapUv:ZJ&&F(z.emissiveMap.channel),metalnessMapUv:lJ&&F(z.metalnessMap.channel),roughnessMapUv:uJ&&F(z.roughnessMap.channel),anisotropyMapUv:u&&F(z.anisotropyMap.channel),clearcoatMapUv:VJ&&F(z.clearcoatMap.channel),clearcoatNormalMapUv:YJ&&F(z.clearcoatNormalMap.channel),clearcoatRoughnessMapUv:_J&&F(z.clearcoatRoughnessMap.channel),iridescenceMapUv:vJ&&F(z.iridescenceMap.channel),iridescenceThicknessMapUv:KJ&&F(z.iridescenceThicknessMap.channel),sheenColorMapUv:FJ&&F(z.sheenColorMap.channel),sheenRoughnessMapUv:PJ&&F(z.sheenRoughnessMap.channel),specularMapUv:AJ&&F(z.specularMap.channel),specularColorMapUv:MJ&&F(z.specularColorMap.channel),specularIntensityMapUv:oJ&&F(z.specularIntensityMap.channel),transmissionMapUv:j&&F(z.transmissionMap.channel),thicknessMapUv:OJ&&F(z.thicknessMap.channel),alphaMapUv:IJ&&F(z.alphaMap.channel),vertexTangents:!!o.attributes.tangent&&(UJ||sJ),vertexColors:z.vertexColors,vertexAlphas:z.vertexColors===!0&&!!o.attributes.color&&o.attributes.color.itemSize===4,pointsUvs:d.isPoints===!0&&!!o.attributes.uv&&(W0||IJ),fog:!!x,useFog:z.fog===!0,fogExp2:!!x&&x.isFogExp2,flatShading:z.flatShading===!0&&z.wireframe===!1,sizeAttenuation:z.sizeAttenuation===!0,logarithmicDepthBuffer:E,reversedDepthBuffer:LJ,skinning:d.isSkinnedMesh===!0,morphTargets:o.morphAttributes.position!==void 0,morphNormals:o.morphAttributes.normal!==void 0,morphColors:o.morphAttributes.color!==void 0,morphTargetsCount:SJ,morphTextureStride:mJ,numDirLights:I.directional.length,numPointLights:I.point.length,numSpotLights:I.spot.length,numSpotLightMaps:I.spotLightMap.length,numRectAreaLights:I.rectArea.length,numHemiLights:I.hemi.length,numDirLightShadows:I.directionalShadowMap.length,numPointLightShadows:I.pointShadowMap.length,numSpotLightShadows:I.spotShadowMap.length,numSpotLightShadowsWithMaps:I.numSpotLightShadowsWithMaps,numLightProbes:I.numLightProbes,numClippingPlanes:H.numPlanes,numClipIntersection:H.numIntersection,dithering:z.dithering,shadowMapEnabled:J.shadowMap.enabled&&S.length>0,shadowMapType:J.shadowMap.type,toneMapping:pJ,decodeVideoTexture:W0&&z.map.isVideoTexture===!0&&tJ.getTransfer(z.map.colorSpace)===G0,decodeVideoTextureEmissive:ZJ&&z.emissiveMap.isVideoTexture===!0&&tJ.getTransfer(z.emissiveMap.colorSpace)===G0,premultipliedAlpha:z.premultipliedAlpha,doubleSided:z.side===R8,flipSided:z.side===i0,useDepthPacking:z.depthPacking>=0,depthPacking:z.depthPacking||0,index0AttributeName:z.index0AttributeName,extensionClipCullDistance:CJ&&z.extensions.clipCullDistance===!0&&Z.has("WEBGL_clip_cull_distance"),extensionMultiDraw:(CJ&&z.extensions.multiDraw===!0||xJ)&&Z.has("WEBGL_multi_draw"),rendererExtensionParallelShaderCompile:Z.has("KHR_parallel_shader_compile"),customProgramCacheKey:z.customProgramCacheKey()};return Y0.vertexUv1s=U.has(1),Y0.vertexUv2s=U.has(2),Y0.vertexUv3s=U.has(3),U.clear(),Y0}function D(z){let I=[];if(z.shaderID)I.push(z.shaderID);else I.push(z.customVertexShaderID),I.push(z.customFragmentShaderID);if(z.defines!==void 0)for(let S in z.defines)I.push(S),I.push(z.defines[S]);if(z.isRawShaderMaterial===!1)k(I,z),M(I,z),I.push(J.outputColorSpace);return I.push(z.customProgramCacheKey),I.join()}function k(z,I){z.push(I.precision),z.push(I.outputColorSpace),z.push(I.envMapMode),z.push(I.envMapCubeUVHeight),z.push(I.mapUv),z.push(I.alphaMapUv),z.push(I.lightMapUv),z.push(I.aoMapUv),z.push(I.bumpMapUv),z.push(I.normalMapUv),z.push(I.displacementMapUv),z.push(I.emissiveMapUv),z.push(I.metalnessMapUv),z.push(I.roughnessMapUv),z.push(I.anisotropyMapUv),z.push(I.clearcoatMapUv),z.push(I.clearcoatNormalMapUv),z.push(I.clearcoatRoughnessMapUv),z.push(I.iridescenceMapUv),z.push(I.iridescenceThicknessMapUv),z.push(I.sheenColorMapUv),z.push(I.sheenRoughnessMapUv),z.push(I.specularMapUv),z.push(I.specularColorMapUv),z.push(I.specularIntensityMapUv),z.push(I.transmissionMapUv),z.push(I.thicknessMapUv),z.push(I.combine),z.push(I.fogExp2),z.push(I.sizeAttenuation),z.push(I.morphTargetsCount),z.push(I.morphAttributeCount),z.push(I.numDirLights),z.push(I.numPointLights),z.push(I.numSpotLights),z.push(I.numSpotLightMaps),z.push(I.numHemiLights),z.push(I.numRectAreaLights),z.push(I.numDirLightShadows),z.push(I.numPointLightShadows),z.push(I.numSpotLightShadows),z.push(I.numSpotLightShadowsWithMaps),z.push(I.numLightProbes),z.push(I.shadowMapType),z.push(I.toneMapping),z.push(I.numClippingPlanes),z.push(I.numClipIntersection),z.push(I.depthPacking)}function M(z,I){if(Y.disableAll(),I.supportsVertexTextures)Y.enable(0);if(I.instancing)Y.enable(1);if(I.instancingColor)Y.enable(2);if(I.instancingMorph)Y.enable(3);if(I.matcap)Y.enable(4);if(I.envMap)Y.enable(5);if(I.normalMapObjectSpace)Y.enable(6);if(I.normalMapTangentSpace)Y.enable(7);if(I.clearcoat)Y.enable(8);if(I.iridescence)Y.enable(9);if(I.alphaTest)Y.enable(10);if(I.vertexColors)Y.enable(11);if(I.vertexAlphas)Y.enable(12);if(I.vertexUv1s)Y.enable(13);if(I.vertexUv2s)Y.enable(14);if(I.vertexUv3s)Y.enable(15);if(I.vertexTangents)Y.enable(16);if(I.anisotropy)Y.enable(17);if(I.alphaHash)Y.enable(18);if(I.batching)Y.enable(19);if(I.dispersion)Y.enable(20);if(I.batchingColor)Y.enable(21);if(I.gradientMap)Y.enable(22);if(z.push(Y.mask),Y.disableAll(),I.fog)Y.enable(0);if(I.useFog)Y.enable(1);if(I.flatShading)Y.enable(2);if(I.logarithmicDepthBuffer)Y.enable(3);if(I.reversedDepthBuffer)Y.enable(4);if(I.skinning)Y.enable(5);if(I.morphTargets)Y.enable(6);if(I.morphNormals)Y.enable(7);if(I.morphColors)Y.enable(8);if(I.premultipliedAlpha)Y.enable(9);if(I.shadowMapEnabled)Y.enable(10);if(I.doubleSided)Y.enable(11);if(I.flipSided)Y.enable(12);if(I.useDepthPacking)Y.enable(13);if(I.dithering)Y.enable(14);if(I.transmission)Y.enable(15);if(I.sheen)Y.enable(16);if(I.opaque)Y.enable(17);if(I.pointsUvs)Y.enable(18);if(I.decodeVideoTexture)Y.enable(19);if(I.decodeVideoTextureEmissive)Y.enable(20);if(I.alphaToCoverage)Y.enable(21);z.push(Y.mask)}function L(z){let I=R[z.type],S;if(I){let p=M8[I];S=LY.clone(p.uniforms)}else S=z.uniforms;return S}function A(z,I){let S;for(let p=0,d=G.length;p<d;p++){let x=G[p];if(x.cacheKey===I){S=x,++S.usedTimes;break}}if(S===void 0)S=new k5(J,I,z,K),G.push(S);return S}function _(z){if(--z.usedTimes===0){let I=G.indexOf(z);G[I]=G[G.length-1],G.pop(),z.destroy()}}function C(z){X.remove(z)}function y(){X.dispose()}return{getParameters:O,getProgramCacheKey:D,getUniforms:L,acquireProgram:A,releaseProgram:_,releaseShaderCache:C,programs:G,dispose:y}}function z5(){let J=new WeakMap;function Q(H){return J.has(H)}function $(H){let Y=J.get(H);if(Y===void 0)Y={},J.set(H,Y);return Y}function Z(H){J.delete(H)}function W(H,Y,X){J.get(H)[Y]=X}function K(){J=new WeakMap}return{has:Q,get:$,remove:Z,update:W,dispose:K}}function B5(J,Q){if(J.groupOrder!==Q.groupOrder)return J.groupOrder-Q.groupOrder;else if(J.renderOrder!==Q.renderOrder)return J.renderOrder-Q.renderOrder;else if(J.material.id!==Q.material.id)return J.material.id-Q.material.id;else if(J.z!==Q.z)return J.z-Q.z;else return J.id-Q.id}function aX(J,Q){if(J.groupOrder!==Q.groupOrder)return J.groupOrder-Q.groupOrder;else if(J.renderOrder!==Q.renderOrder)return J.renderOrder-Q.renderOrder;else if(J.z!==Q.z)return Q.z-J.z;else return J.id-Q.id}function rX(){let J=[],Q=0,$=[],Z=[],W=[];function K(){Q=0,$.length=0,Z.length=0,W.length=0}function H(E,N,q,R,F,O){let D=J[Q];if(D===void 0)D={id:E.id,object:E,geometry:N,material:q,groupOrder:R,renderOrder:E.renderOrder,z:F,group:O},J[Q]=D;else D.id=E.id,D.object=E,D.geometry=N,D.material=q,D.groupOrder=R,D.renderOrder=E.renderOrder,D.z=F,D.group=O;return Q++,D}function Y(E,N,q,R,F,O){let D=H(E,N,q,R,F,O);if(q.transmission>0)Z.push(D);else if(q.transparent===!0)W.push(D);else $.push(D)}function X(E,N,q,R,F,O){let D=H(E,N,q,R,F,O);if(q.transmission>0)Z.unshift(D);else if(q.transparent===!0)W.unshift(D);else $.unshift(D)}function U(E,N){if($.length>1)$.sort(E||B5);if(Z.length>1)Z.sort(N||aX);if(W.length>1)W.sort(N||aX)}function G(){for(let E=Q,N=J.length;E<N;E++){let q=J[E];if(q.id===null)break;q.id=null,q.object=null,q.geometry=null,q.material=null,q.group=null}}return{opaque:$,transmissive:Z,transparent:W,init:K,push:Y,unshift:X,finish:G,sort:U}}function I5(){let J=new WeakMap;function Q(Z,W){let K=J.get(Z),H;if(K===void 0)H=new rX,J.set(Z,[H]);else if(W>=K.length)H=new rX,K.push(H);else H=K[W];return H}function $(){J=new WeakMap}return{get:Q,dispose:$}}function _5(){let J={};return{get:function(Q){if(J[Q.id]!==void 0)return J[Q.id];let $;switch(Q.type){case"DirectionalLight":$={direction:new w,color:new kJ};break;case"SpotLight":$={position:new w,direction:new w,color:new kJ,distance:0,coneCos:0,penumbraCos:0,decay:0};break;case"PointLight":$={position:new w,color:new kJ,distance:0,decay:0};break;case"HemisphereLight":$={direction:new w,skyColor:new kJ,groundColor:new kJ};break;case"RectAreaLight":$={color:new kJ,position:new w,halfWidth:new w,halfHeight:new w};break}return J[Q.id]=$,$}}}function w5(){let J={};return{get:function(Q){if(J[Q.id]!==void 0)return J[Q.id];let $;switch(Q.type){case"DirectionalLight":$={shadowIntensity:1,shadowBias:0,shadowNormalBias:0,shadowRadius:1,shadowMapSize:new t};break;case"SpotLight":$={shadowIntensity:1,shadowBias:0,shadowNormalBias:0,shadowRadius:1,shadowMapSize:new t};break;case"PointLight":$={shadowIntensity:1,shadowBias:0,shadowNormalBias:0,shadowRadius:1,shadowMapSize:new t,shadowCameraNear:1,shadowCameraFar:1000};break}return J[Q.id]=$,$}}}var C5=0;function P5(J,Q){return(Q.castShadow?2:0)-(J.castShadow?2:0)+(Q.map?1:0)-(J.map?1:0)}function A5(J){let Q=new _5,$=w5(),Z={version:0,hash:{directionalLength:-1,pointLength:-1,spotLength:-1,rectAreaLength:-1,hemiLength:-1,numDirectionalShadows:-1,numPointShadows:-1,numSpotShadows:-1,numSpotMaps:-1,numLightProbes:-1},ambient:[0,0,0],probe:[],directional:[],directionalShadow:[],directionalShadowMap:[],directionalShadowMatrix:[],spot:[],spotLightMap:[],spotShadow:[],spotShadowMap:[],spotLightMatrix:[],rectArea:[],rectAreaLTC1:null,rectAreaLTC2:null,point:[],pointShadow:[],pointShadowMap:[],pointShadowMatrix:[],hemi:[],numSpotLightShadowsWithMaps:0,numLightProbes:0};for(let U=0;U<9;U++)Z.probe.push(new w);let W=new w,K=new hJ,H=new hJ;function Y(U){let G=0,E=0,N=0;for(let z=0;z<9;z++)Z.probe[z].set(0,0,0);let q=0,R=0,F=0,O=0,D=0,k=0,M=0,L=0,A=0,_=0,C=0;U.sort(P5);for(let z=0,I=U.length;z<I;z++){let S=U[z],p=S.color,d=S.intensity,x=S.distance,o=S.shadow&&S.shadow.map?S.shadow.map.texture:null;if(S.isAmbientLight)G+=p.r*d,E+=p.g*d,N+=p.b*d;else if(S.isLightProbe){for(let l=0;l<9;l++)Z.probe[l].addScaledVector(S.sh.coefficients[l],d);C++}else if(S.isDirectionalLight){let l=Q.get(S);if(l.color.copy(S.color).multiplyScalar(S.intensity),S.castShadow){let QJ=S.shadow,m=$.get(S);m.shadowIntensity=QJ.intensity,m.shadowBias=QJ.bias,m.shadowNormalBias=QJ.normalBias,m.shadowRadius=QJ.radius,m.shadowMapSize=QJ.mapSize,Z.directionalShadow[q]=m,Z.directionalShadowMap[q]=o,Z.directionalShadowMatrix[q]=S.shadow.matrix,k++}Z.directional[q]=l,q++}else if(S.isSpotLight){let l=Q.get(S);l.position.setFromMatrixPosition(S.matrixWorld),l.color.copy(p).multiplyScalar(d),l.distance=x,l.coneCos=Math.cos(S.angle),l.penumbraCos=Math.cos(S.angle*(1-S.penumbra)),l.decay=S.decay,Z.spot[F]=l;let QJ=S.shadow;if(S.map){if(Z.spotLightMap[A]=S.map,A++,QJ.updateMatrices(S),S.castShadow)_++}if(Z.spotLightMatrix[F]=QJ.matrix,S.castShadow){let m=$.get(S);m.shadowIntensity=QJ.intensity,m.shadowBias=QJ.bias,m.shadowNormalBias=QJ.normalBias,m.shadowRadius=QJ.radius,m.shadowMapSize=QJ.mapSize,Z.spotShadow[F]=m,Z.spotShadowMap[F]=o,L++}F++}else if(S.isRectAreaLight){let l=Q.get(S);l.color.copy(p).multiplyScalar(d),l.halfWidth.set(S.width*0.5,0,0),l.halfHeight.set(0,S.height*0.5,0),Z.rectArea[O]=l,O++}else if(S.isPointLight){let l=Q.get(S);if(l.color.copy(S.color).multiplyScalar(S.intensity),l.distance=S.distance,l.decay=S.decay,S.castShadow){let QJ=S.shadow,m=$.get(S);m.shadowIntensity=QJ.intensity,m.shadowBias=QJ.bias,m.shadowNormalBias=QJ.normalBias,m.shadowRadius=QJ.radius,m.shadowMapSize=QJ.mapSize,m.shadowCameraNear=QJ.camera.near,m.shadowCameraFar=QJ.camera.far,Z.pointShadow[R]=m,Z.pointShadowMap[R]=o,Z.pointShadowMatrix[R]=S.shadow.matrix,M++}Z.point[R]=l,R++}else if(S.isHemisphereLight){let l=Q.get(S);l.skyColor.copy(S.color).multiplyScalar(d),l.groundColor.copy(S.groundColor).multiplyScalar(d),Z.hemi[D]=l,D++}}if(O>0)if(J.has("OES_texture_float_linear")===!0)Z.rectAreaLTC1=DJ.LTC_FLOAT_1,Z.rectAreaLTC2=DJ.LTC_FLOAT_2;else Z.rectAreaLTC1=DJ.LTC_HALF_1,Z.rectAreaLTC2=DJ.LTC_HALF_2;Z.ambient[0]=G,Z.ambient[1]=E,Z.ambient[2]=N;let y=Z.hash;if(y.directionalLength!==q||y.pointLength!==R||y.spotLength!==F||y.rectAreaLength!==O||y.hemiLength!==D||y.numDirectionalShadows!==k||y.numPointShadows!==M||y.numSpotShadows!==L||y.numSpotMaps!==A||y.numLightProbes!==C)Z.directional.length=q,Z.spot.length=F,Z.rectArea.length=O,Z.point.length=R,Z.hemi.length=D,Z.directionalShadow.length=k,Z.directionalShadowMap.length=k,Z.pointShadow.length=M,Z.pointShadowMap.length=M,Z.spotShadow.length=L,Z.spotShadowMap.length=L,Z.directionalShadowMatrix.length=k,Z.pointShadowMatrix.length=M,Z.spotLightMatrix.length=L+A-_,Z.spotLightMap.length=A,Z.numSpotLightShadowsWithMaps=_,Z.numLightProbes=C,y.directionalLength=q,y.pointLength=R,y.spotLength=F,y.rectAreaLength=O,y.hemiLength=D,y.numDirectionalShadows=k,y.numPointShadows=M,y.numSpotShadows=L,y.numSpotMaps=A,y.numLightProbes=C,Z.version=C5++}function X(U,G){let E=0,N=0,q=0,R=0,F=0,O=G.matrixWorldInverse;for(let D=0,k=U.length;D<k;D++){let M=U[D];if(M.isDirectionalLight){let L=Z.directional[E];L.direction.setFromMatrixPosition(M.matrixWorld),W.setFromMatrixPosition(M.target.matrixWorld),L.direction.sub(W),L.direction.transformDirection(O),E++}else if(M.isSpotLight){let L=Z.spot[q];L.position.setFromMatrixPosition(M.matrixWorld),L.position.applyMatrix4(O),L.direction.setFromMatrixPosition(M.matrixWorld),W.setFromMatrixPosition(M.target.matrixWorld),L.direction.sub(W),L.direction.transformDirection(O),q++}else if(M.isRectAreaLight){let L=Z.rectArea[R];L.position.setFromMatrixPosition(M.matrixWorld),L.position.applyMatrix4(O),H.identity(),K.copy(M.matrixWorld),K.premultiply(O),H.extractRotation(K),L.halfWidth.set(M.width*0.5,0,0),L.halfHeight.set(0,M.height*0.5,0),L.halfWidth.applyMatrix4(H),L.halfHeight.applyMatrix4(H),R++}else if(M.isPointLight){let L=Z.point[N];L.position.setFromMatrixPosition(M.matrixWorld),L.position.applyMatrix4(O),N++}else if(M.isHemisphereLight){let L=Z.hemi[F];L.direction.setFromMatrixPosition(M.matrixWorld),L.direction.transformDirection(O),F++}}}return{setup:Y,setupView:X,state:Z}}function tX(J){let Q=new A5(J),$=[],Z=[];function W(G){U.camera=G,$.length=0,Z.length=0}function K(G){$.push(G)}function H(G){Z.push(G)}function Y(){Q.setup($)}function X(G){Q.setupView($,G)}let U={lightsArray:$,shadowsArray:Z,camera:null,lights:Q,transmissionRenderTarget:{}};return{init:W,state:U,setupLights:Y,setupLightsView:X,pushLight:K,pushShadow:H}}function T5(J){let Q=new WeakMap;function $(W,K=0){let H=Q.get(W),Y;if(H===void 0)Y=new tX(J),Q.set(W,[Y]);else if(K>=H.length)Y=new tX(J),H.push(Y);else Y=H[K];return Y}function Z(){Q=new WeakMap}return{get:$,dispose:Z}}var S5=`void main() {
	gl_Position = vec4( position, 1.0 );
}`,j5=`uniform sampler2D shadow_pass;
uniform vec2 resolution;
uniform float radius;
#include <packing>
void main() {
	const float samples = float( VSM_SAMPLES );
	float mean = 0.0;
	float squared_mean = 0.0;
	float uvStride = samples <= 1.0 ? 0.0 : 2.0 / ( samples - 1.0 );
	float uvStart = samples <= 1.0 ? 0.0 : - 1.0;
	for ( float i = 0.0; i < samples; i ++ ) {
		float uvOffset = uvStart + i * uvStride;
		#ifdef HORIZONTAL_PASS
			vec2 distribution = unpackRGBATo2Half( texture2D( shadow_pass, ( gl_FragCoord.xy + vec2( uvOffset, 0.0 ) * radius ) / resolution ) );
			mean += distribution.x;
			squared_mean += distribution.y * distribution.y + distribution.x * distribution.x;
		#else
			float depth = unpackRGBAToDepth( texture2D( shadow_pass, ( gl_FragCoord.xy + vec2( 0.0, uvOffset ) * radius ) / resolution ) );
			mean += depth;
			squared_mean += depth * depth;
		#endif
	}
	mean = mean / samples;
	squared_mean = squared_mean / samples;
	float std_dev = sqrt( squared_mean - mean * mean );
	gl_FragColor = pack2HalfToRGBA( vec2( mean, std_dev ) );
}`;function y5(J,Q,$){let Z=new V9,W=new t,K=new t,H=new J0,Y=new cQ({depthPacking:tH}),X=new nQ,U={},G=$.maxTextureSize,E={[Q6]:i0,[i0]:Q6,[R8]:R8},N=new e0({defines:{VSM_SAMPLES:8},uniforms:{shadow_pass:{value:null},resolution:{value:new t},radius:{value:4}},vertexShader:S5,fragmentShader:j5}),q=N.clone();q.defines.HORIZONTAL_PASS=1;let R=new nJ;R.setAttribute("position",new Z0(new Float32Array([-1,-1,0.5,3,-1,0.5,-1,3,0.5]),3));let F=new k0(R,N),O=this;this.enabled=!1,this.autoUpdate=!0,this.needsUpdate=!1,this.type=a$;let D=this.type;this.render=function(_,C,y){if(O.enabled===!1)return;if(O.autoUpdate===!1&&O.needsUpdate===!1)return;if(_.length===0)return;let z=J.getRenderTarget(),I=J.getActiveCubeFace(),S=J.getActiveMipmapLevel(),p=J.state;if(p.setBlending(m8),p.buffers.depth.getReversed()===!0)p.buffers.color.setClear(0,0,0,0);else p.buffers.color.setClear(1,1,1,1);p.buffers.depth.setTest(!0),p.setScissorTest(!1);let d=D!==O8&&this.type===O8,x=D===O8&&this.type!==O8;for(let o=0,l=_.length;o<l;o++){let QJ=_[o],m=QJ.shadow;if(m===void 0){console.warn("THREE.WebGLShadowMap:",QJ,"has no shadow.");continue}if(m.autoUpdate===!1&&m.needsUpdate===!1)continue;W.copy(m.mapSize);let EJ=m.getFrameExtents();if(W.multiply(EJ),K.copy(m.mapSize),W.x>G||W.y>G){if(W.x>G)K.x=Math.floor(G/EJ.x),W.x=K.x*EJ.x,m.mapSize.x=K.x;if(W.y>G)K.y=Math.floor(G/EJ.y),W.y=K.y*EJ.y,m.mapSize.y=K.y}if(m.map===null||d===!0||x===!0){let SJ=this.type!==O8?{minFilter:W6,magFilter:W6}:{};if(m.map!==null)m.map.dispose();m.map=new Y8(W.x,W.y,SJ),m.map.texture.name=QJ.name+".shadowMap",m.camera.updateProjectionMatrix()}J.setRenderTarget(m.map),J.clear();let NJ=m.getViewportCount();for(let SJ=0;SJ<NJ;SJ++){let mJ=m.getViewport(SJ);H.set(K.x*mJ.x,K.y*mJ.y,K.x*mJ.z,K.y*mJ.w),p.viewport(H),m.updateMatrices(QJ,SJ),Z=m.getFrustum(),L(C,y,m.camera,QJ,this.type)}if(m.isPointLightShadow!==!0&&this.type===O8)k(m,y);m.needsUpdate=!1}D=this.type,O.needsUpdate=!1,J.setRenderTarget(z,I,S)};function k(_,C){let y=Q.update(F);if(N.defines.VSM_SAMPLES!==_.blurSamples)N.defines.VSM_SAMPLES=_.blurSamples,q.defines.VSM_SAMPLES=_.blurSamples,N.needsUpdate=!0,q.needsUpdate=!0;if(_.mapPass===null)_.mapPass=new Y8(W.x,W.y);N.uniforms.shadow_pass.value=_.map.texture,N.uniforms.resolution.value=_.mapSize,N.uniforms.radius.value=_.radius,J.setRenderTarget(_.mapPass),J.clear(),J.renderBufferDirect(C,null,y,N,F,null),q.uniforms.shadow_pass.value=_.mapPass.texture,q.uniforms.resolution.value=_.mapSize,q.uniforms.radius.value=_.radius,J.setRenderTarget(_.map),J.clear(),J.renderBufferDirect(C,null,y,q,F,null)}function M(_,C,y,z){let I=null,S=y.isPointLight===!0?_.customDistanceMaterial:_.customDepthMaterial;if(S!==void 0)I=S;else if(I=y.isPointLight===!0?X:Y,J.localClippingEnabled&&C.clipShadows===!0&&Array.isArray(C.clippingPlanes)&&C.clippingPlanes.length!==0||C.displacementMap&&C.displacementScale!==0||C.alphaMap&&C.alphaTest>0||C.map&&C.alphaTest>0||C.alphaToCoverage===!0){let p=I.uuid,d=C.uuid,x=U[p];if(x===void 0)x={},U[p]=x;let o=x[d];if(o===void 0)o=I.clone(),x[d]=o,C.addEventListener("dispose",A);I=o}if(I.visible=C.visible,I.wireframe=C.wireframe,z===O8)I.side=C.shadowSide!==null?C.shadowSide:C.side;else I.side=C.shadowSide!==null?C.shadowSide:E[C.side];if(I.alphaMap=C.alphaMap,I.alphaTest=C.alphaToCoverage===!0?0.5:C.alphaTest,I.map=C.map,I.clipShadows=C.clipShadows,I.clippingPlanes=C.clippingPlanes,I.clipIntersection=C.clipIntersection,I.displacementMap=C.displacementMap,I.displacementScale=C.displacementScale,I.displacementBias=C.displacementBias,I.wireframeLinewidth=C.wireframeLinewidth,I.linewidth=C.linewidth,y.isPointLight===!0&&I.isMeshDistanceMaterial===!0){let p=J.properties.get(I);p.light=y}return I}function L(_,C,y,z,I){if(_.visible===!1)return;if(_.layers.test(C.layers)&&(_.isMesh||_.isLine||_.isPoints)){if((_.castShadow||_.receiveShadow&&I===O8)&&(!_.frustumCulled||Z.intersectsObject(_))){_.modelViewMatrix.multiplyMatrices(y.matrixWorldInverse,_.matrixWorld);let d=Q.update(_),x=_.material;if(Array.isArray(x)){let o=d.groups;for(let l=0,QJ=o.length;l<QJ;l++){let m=o[l],EJ=x[m.materialIndex];if(EJ&&EJ.visible){let NJ=M(_,EJ,z,I);_.onBeforeShadow(J,_,C,y,d,NJ,m),J.renderBufferDirect(y,null,d,NJ,_,m),_.onAfterShadow(J,_,C,y,d,NJ,m)}}}else if(x.visible){let o=M(_,x,z,I);_.onBeforeShadow(J,_,C,y,d,o,null),J.renderBufferDirect(y,null,d,o,_,null),_.onAfterShadow(J,_,C,y,d,o,null)}}}let p=_.children;for(let d=0,x=p.length;d<x;d++)L(p[d],C,y,z,I)}function A(_){_.target.removeEventListener("dispose",A);for(let y in U){let z=U[y],I=_.target.uuid;if(I in z)z[I].dispose(),delete z[I]}}}var v5={[JQ]:QQ,[$Q]:KQ,[ZQ]:HQ,[x6]:WQ,[QQ]:JQ,[KQ]:$Q,[HQ]:ZQ,[WQ]:x6};function f5(J,Q){function $(){let j=!1,OJ=new J0,GJ=null,IJ=new J0(0,0,0,0);return{setMask:function($J){if(GJ!==$J&&!j)J.colorMask($J,$J,$J,$J),GJ=$J},setLocked:function($J){j=$J},setClear:function($J,r,CJ,pJ,Y0){if(Y0===!0)$J*=pJ,r*=pJ,CJ*=pJ;if(OJ.set($J,r,CJ,pJ),IJ.equals(OJ)===!1)J.clearColor($J,r,CJ,pJ),IJ.copy(OJ)},reset:function(){j=!1,GJ=null,IJ.set(-1,0,0,0)}}}function Z(){let j=!1,OJ=!1,GJ=null,IJ=null,$J=null;return{setReversed:function(r){if(OJ!==r){let CJ=Q.get("EXT_clip_control");if(r)CJ.clipControlEXT(CJ.LOWER_LEFT_EXT,CJ.ZERO_TO_ONE_EXT);else CJ.clipControlEXT(CJ.LOWER_LEFT_EXT,CJ.NEGATIVE_ONE_TO_ONE_EXT);OJ=r;let pJ=$J;$J=null,this.setClear(pJ)}},getReversed:function(){return OJ},setTest:function(r){if(r)XJ(J.DEPTH_TEST);else LJ(J.DEPTH_TEST)},setMask:function(r){if(GJ!==r&&!j)J.depthMask(r),GJ=r},setFunc:function(r){if(OJ)r=v5[r];if(IJ!==r){switch(r){case JQ:J.depthFunc(J.NEVER);break;case QQ:J.depthFunc(J.ALWAYS);break;case $Q:J.depthFunc(J.LESS);break;case x6:J.depthFunc(J.LEQUAL);break;case ZQ:J.depthFunc(J.EQUAL);break;case WQ:J.depthFunc(J.GEQUAL);break;case KQ:J.depthFunc(J.GREATER);break;case HQ:J.depthFunc(J.NOTEQUAL);break;default:J.depthFunc(J.LEQUAL)}IJ=r}},setLocked:function(r){j=r},setClear:function(r){if($J!==r){if(OJ)r=1-r;J.clearDepth(r),$J=r}},reset:function(){j=!1,GJ=null,IJ=null,$J=null,OJ=!1}}}function W(){let j=!1,OJ=null,GJ=null,IJ=null,$J=null,r=null,CJ=null,pJ=null,Y0=null;return{setTest:function(K0){if(!j)if(K0)XJ(J.STENCIL_TEST);else LJ(J.STENCIL_TEST)},setMask:function(K0){if(OJ!==K0&&!j)J.stencilMask(K0),OJ=K0},setFunc:function(K0,U8,G8){if(GJ!==K0||IJ!==U8||$J!==G8)J.stencilFunc(K0,U8,G8),GJ=K0,IJ=U8,$J=G8},setOp:function(K0,U8,G8){if(r!==K0||CJ!==U8||pJ!==G8)J.stencilOp(K0,U8,G8),r=K0,CJ=U8,pJ=G8},setLocked:function(K0){j=K0},setClear:function(K0){if(Y0!==K0)J.clearStencil(K0),Y0=K0},reset:function(){j=!1,OJ=null,GJ=null,IJ=null,$J=null,r=null,CJ=null,pJ=null,Y0=null}}}let K=new $,H=new Z,Y=new W,X=new WeakMap,U=new WeakMap,G={},E={},N=new WeakMap,q=[],R=null,F=!1,O=null,D=null,k=null,M=null,L=null,A=null,_=null,C=new kJ(0,0,0),y=0,z=!1,I=null,S=null,p=null,d=null,x=null,o=J.getParameter(J.MAX_COMBINED_TEXTURE_IMAGE_UNITS),l=!1,QJ=0,m=J.getParameter(J.VERSION);if(m.indexOf("WebGL")!==-1)QJ=parseFloat(/^WebGL (\d)/.exec(m)[1]),l=QJ>=1;else if(m.indexOf("OpenGL ES")!==-1)QJ=parseFloat(/^OpenGL ES (\d)/.exec(m)[1]),l=QJ>=2;let EJ=null,NJ={},SJ=J.getParameter(J.SCISSOR_BOX),mJ=J.getParameter(J.VIEWPORT),U0=new J0().fromArray(SJ),rJ=new J0().fromArray(mJ);function s(j,OJ,GJ,IJ){let $J=new Uint8Array(4),r=J.createTexture();J.bindTexture(j,r),J.texParameteri(j,J.TEXTURE_MIN_FILTER,J.NEAREST),J.texParameteri(j,J.TEXTURE_MAG_FILTER,J.NEAREST);for(let CJ=0;CJ<GJ;CJ++)if(j===J.TEXTURE_3D||j===J.TEXTURE_2D_ARRAY)J.texImage3D(OJ,0,J.RGBA,1,1,IJ,0,J.RGBA,J.UNSIGNED_BYTE,$J);else J.texImage2D(OJ+CJ,0,J.RGBA,1,1,0,J.RGBA,J.UNSIGNED_BYTE,$J);return r}let qJ={};qJ[J.TEXTURE_2D]=s(J.TEXTURE_2D,J.TEXTURE_2D,1),qJ[J.TEXTURE_CUBE_MAP]=s(J.TEXTURE_CUBE_MAP,J.TEXTURE_CUBE_MAP_POSITIVE_X,6),qJ[J.TEXTURE_2D_ARRAY]=s(J.TEXTURE_2D_ARRAY,J.TEXTURE_2D_ARRAY,1,1),qJ[J.TEXTURE_3D]=s(J.TEXTURE_3D,J.TEXTURE_3D,1,1),K.setClear(0,0,0,1),H.setClear(1),Y.setClear(0),XJ(J.DEPTH_TEST),H.setFunc(x6),n(!1),UJ(o$),XJ(J.CULL_FACE),a(m8);function XJ(j){if(G[j]!==!0)J.enable(j),G[j]=!0}function LJ(j){if(G[j]!==!1)J.disable(j),G[j]=!1}function yJ(j,OJ){if(E[j]!==OJ){if(J.bindFramebuffer(j,OJ),E[j]=OJ,j===J.DRAW_FRAMEBUFFER)E[J.FRAMEBUFFER]=OJ;if(j===J.FRAMEBUFFER)E[J.DRAW_FRAMEBUFFER]=OJ;return!0}return!1}function xJ(j,OJ){let GJ=q,IJ=!1;if(j){if(GJ=N.get(OJ),GJ===void 0)GJ=[],N.set(OJ,GJ);let $J=j.textures;if(GJ.length!==$J.length||GJ[0]!==J.COLOR_ATTACHMENT0){for(let r=0,CJ=$J.length;r<CJ;r++)GJ[r]=J.COLOR_ATTACHMENT0+r;GJ.length=$J.length,IJ=!0}}else if(GJ[0]!==J.BACK)GJ[0]=J.BACK,IJ=!0;if(IJ)J.drawBuffers(GJ)}function W0(j){if(R!==j)return J.useProgram(j),R=j,!0;return!1}let T={[$6]:J.FUNC_ADD,[EH]:J.FUNC_SUBTRACT,[NH]:J.FUNC_REVERSE_SUBTRACT};T[qH]=J.MIN,T[DH]=J.MAX;let e={[OH]:J.ZERO,[RH]:J.ONE,[FH]:J.SRC_COLOR,[kH]:J.SRC_ALPHA,[_H]:J.SRC_ALPHA_SATURATE,[BH]:J.DST_COLOR,[LH]:J.DST_ALPHA,[MH]:J.ONE_MINUS_SRC_COLOR,[VH]:J.ONE_MINUS_SRC_ALPHA,[IH]:J.ONE_MINUS_DST_COLOR,[zH]:J.ONE_MINUS_DST_ALPHA,[wH]:J.CONSTANT_COLOR,[CH]:J.ONE_MINUS_CONSTANT_COLOR,[PH]:J.CONSTANT_ALPHA,[AH]:J.ONE_MINUS_CONSTANT_ALPHA};function a(j,OJ,GJ,IJ,$J,r,CJ,pJ,Y0,K0){if(j===m8){if(F===!0)LJ(J.BLEND),F=!1;return}if(F===!1)XJ(J.BLEND),F=!0;if(j!==GH){if(j!==O||K0!==z){if(D!==$6||L!==$6)J.blendEquation(J.FUNC_ADD),D=$6,L=$6;if(K0)switch(j){case h6:J.blendFuncSeparate(J.ONE,J.ONE_MINUS_SRC_ALPHA,J.ONE,J.ONE_MINUS_SRC_ALPHA);break;case r$:J.blendFunc(J.ONE,J.ONE);break;case t$:J.blendFuncSeparate(J.ZERO,J.ONE_MINUS_SRC_COLOR,J.ZERO,J.ONE);break;case e$:J.blendFuncSeparate(J.DST_COLOR,J.ONE_MINUS_SRC_ALPHA,J.ZERO,J.ONE);break;default:console.error("THREE.WebGLState: Invalid blending: ",j);break}else switch(j){case h6:J.blendFuncSeparate(J.SRC_ALPHA,J.ONE_MINUS_SRC_ALPHA,J.ONE,J.ONE_MINUS_SRC_ALPHA);break;case r$:J.blendFuncSeparate(J.SRC_ALPHA,J.ONE,J.ONE,J.ONE);break;case t$:console.error("THREE.WebGLState: SubtractiveBlending requires material.premultipliedAlpha = true");break;case e$:console.error("THREE.WebGLState: MultiplyBlending requires material.premultipliedAlpha = true");break;default:console.error("THREE.WebGLState: Invalid blending: ",j);break}k=null,M=null,A=null,_=null,C.set(0,0,0),y=0,O=j,z=K0}return}if($J=$J||OJ,r=r||GJ,CJ=CJ||IJ,OJ!==D||$J!==L)J.blendEquationSeparate(T[OJ],T[$J]),D=OJ,L=$J;if(GJ!==k||IJ!==M||r!==A||CJ!==_)J.blendFuncSeparate(e[GJ],e[IJ],e[r],e[CJ]),k=GJ,M=IJ,A=r,_=CJ;if(pJ.equals(C)===!1||Y0!==y)J.blendColor(pJ.r,pJ.g,pJ.b,Y0),C.copy(pJ),y=Y0;O=j,z=!1}function i(j,OJ){j.side===R8?LJ(J.CULL_FACE):XJ(J.CULL_FACE);let GJ=j.side===i0;if(OJ)GJ=!GJ;n(GJ),j.blending===h6&&j.transparent===!1?a(m8):a(j.blending,j.blendEquation,j.blendSrc,j.blendDst,j.blendEquationAlpha,j.blendSrcAlpha,j.blendDstAlpha,j.blendColor,j.blendAlpha,j.premultipliedAlpha),H.setFunc(j.depthFunc),H.setTest(j.depthTest),H.setMask(j.depthWrite),K.setMask(j.colorWrite);let IJ=j.stencilWrite;if(Y.setTest(IJ),IJ)Y.setMask(j.stencilWriteMask),Y.setFunc(j.stencilFunc,j.stencilRef,j.stencilFuncMask),Y.setOp(j.stencilFail,j.stencilZFail,j.stencilZPass);ZJ(j.polygonOffset,j.polygonOffsetFactor,j.polygonOffsetUnits),j.alphaToCoverage===!0?XJ(J.SAMPLE_ALPHA_TO_COVERAGE):LJ(J.SAMPLE_ALPHA_TO_COVERAGE)}function n(j){if(I!==j){if(j)J.frontFace(J.CW);else J.frontFace(J.CCW);I=j}}function UJ(j){if(j!==YH){if(XJ(J.CULL_FACE),j!==S)if(j===o$)J.cullFace(J.BACK);else if(j===XH)J.cullFace(J.FRONT);else J.cullFace(J.FRONT_AND_BACK)}else LJ(J.CULL_FACE);S=j}function HJ(j){if(j!==p){if(l)J.lineWidth(j);p=j}}function ZJ(j,OJ,GJ){if(j){if(XJ(J.POLYGON_OFFSET_FILL),d!==OJ||x!==GJ)J.polygonOffset(OJ,GJ),d=OJ,x=GJ}else LJ(J.POLYGON_OFFSET_FILL)}function lJ(j){if(j)XJ(J.SCISSOR_TEST);else LJ(J.SCISSOR_TEST)}function uJ(j){if(j===void 0)j=J.TEXTURE0+o-1;if(EJ!==j)J.activeTexture(j),EJ=j}function sJ(j,OJ,GJ){if(GJ===void 0)if(EJ===null)GJ=J.TEXTURE0+o-1;else GJ=EJ;let IJ=NJ[GJ];if(IJ===void 0)IJ={type:void 0,texture:void 0},NJ[GJ]=IJ;if(IJ.type!==j||IJ.texture!==OJ){if(EJ!==GJ)J.activeTexture(GJ),EJ=GJ;J.bindTexture(j,OJ||qJ[j]),IJ.type=j,IJ.texture=OJ}}function P(){let j=NJ[EJ];if(j!==void 0&&j.type!==void 0)J.bindTexture(j.type,null),j.type=void 0,j.texture=void 0}function V(){try{J.compressedTexImage2D(...arguments)}catch(j){console.error("THREE.WebGLState:",j)}}function v(){try{J.compressedTexImage3D(...arguments)}catch(j){console.error("THREE.WebGLState:",j)}}function c(){try{J.texSubImage2D(...arguments)}catch(j){console.error("THREE.WebGLState:",j)}}function JJ(){try{J.texSubImage3D(...arguments)}catch(j){console.error("THREE.WebGLState:",j)}}function u(){try{J.compressedTexSubImage2D(...arguments)}catch(j){console.error("THREE.WebGLState:",j)}}function VJ(){try{J.compressedTexSubImage3D(...arguments)}catch(j){console.error("THREE.WebGLState:",j)}}function YJ(){try{J.texStorage2D(...arguments)}catch(j){console.error("THREE.WebGLState:",j)}}function _J(){try{J.texStorage3D(...arguments)}catch(j){console.error("THREE.WebGLState:",j)}}function vJ(){try{J.texImage2D(...arguments)}catch(j){console.error("THREE.WebGLState:",j)}}function KJ(){try{J.texImage3D(...arguments)}catch(j){console.error("THREE.WebGLState:",j)}}function FJ(j){if(U0.equals(j)===!1)J.scissor(j.x,j.y,j.z,j.w),U0.copy(j)}function PJ(j){if(rJ.equals(j)===!1)J.viewport(j.x,j.y,j.z,j.w),rJ.copy(j)}function AJ(j,OJ){let GJ=U.get(OJ);if(GJ===void 0)GJ=new WeakMap,U.set(OJ,GJ);let IJ=GJ.get(j);if(IJ===void 0)IJ=J.getUniformBlockIndex(OJ,j.name),GJ.set(j,IJ)}function MJ(j,OJ){let IJ=U.get(OJ).get(j);if(X.get(OJ)!==IJ)J.uniformBlockBinding(OJ,IJ,j.__bindingPointIndex),X.set(OJ,IJ)}function oJ(){J.disable(J.BLEND),J.disable(J.CULL_FACE),J.disable(J.DEPTH_TEST),J.disable(J.POLYGON_OFFSET_FILL),J.disable(J.SCISSOR_TEST),J.disable(J.STENCIL_TEST),J.disable(J.SAMPLE_ALPHA_TO_COVERAGE),J.blendEquation(J.FUNC_ADD),J.blendFunc(J.ONE,J.ZERO),J.blendFuncSeparate(J.ONE,J.ZERO,J.ONE,J.ZERO),J.blendColor(0,0,0,0),J.colorMask(!0,!0,!0,!0),J.clearColor(0,0,0,0),J.depthMask(!0),J.depthFunc(J.LESS),H.setReversed(!1),J.clearDepth(1),J.stencilMask(4294967295),J.stencilFunc(J.ALWAYS,0,4294967295),J.stencilOp(J.KEEP,J.KEEP,J.KEEP),J.clearStencil(0),J.cullFace(J.BACK),J.frontFace(J.CCW),J.polygonOffset(0,0),J.activeTexture(J.TEXTURE0),J.bindFramebuffer(J.FRAMEBUFFER,null),J.bindFramebuffer(J.DRAW_FRAMEBUFFER,null),J.bindFramebuffer(J.READ_FRAMEBUFFER,null),J.useProgram(null),J.lineWidth(1),J.scissor(0,0,J.canvas.width,J.canvas.height),J.viewport(0,0,J.canvas.width,J.canvas.height),G={},EJ=null,NJ={},E={},N=new WeakMap,q=[],R=null,F=!1,O=null,D=null,k=null,M=null,L=null,A=null,_=null,C=new kJ(0,0,0),y=0,z=!1,I=null,S=null,p=null,d=null,x=null,U0.set(0,0,J.canvas.width,J.canvas.height),rJ.set(0,0,J.canvas.width,J.canvas.height),K.reset(),H.reset(),Y.reset()}return{buffers:{color:K,depth:H,stencil:Y},enable:XJ,disable:LJ,bindFramebuffer:yJ,drawBuffers:xJ,useProgram:W0,setBlending:a,setMaterial:i,setFlipSided:n,setCullFace:UJ,setLineWidth:HJ,setPolygonOffset:ZJ,setScissorTest:lJ,activeTexture:uJ,bindTexture:sJ,unbindTexture:P,compressedTexImage2D:V,compressedTexImage3D:v,texImage2D:vJ,texImage3D:KJ,updateUBOMapping:AJ,uniformBlockBinding:MJ,texStorage2D:YJ,texStorage3D:_J,texSubImage2D:c,texSubImage3D:JJ,compressedTexSubImage2D:u,compressedTexSubImage3D:VJ,scissor:FJ,viewport:PJ,reset:oJ}}function b5(J,Q,$,Z,W,K,H){let Y=Q.has("WEBGL_multisampled_render_to_texture")?Q.get("WEBGL_multisampled_render_to_texture"):null,X=typeof navigator>"u"?!1:/OculusBrowser/g.test(navigator.userAgent),U=new t,G=new WeakMap,E,N=new WeakMap,q=!1;try{q=typeof OffscreenCanvas<"u"&&new OffscreenCanvas(1,1).getContext("2d")!==null}catch(P){}function R(P,V){return q?new OffscreenCanvas(P,V):i9("canvas")}function F(P,V,v){let c=1,JJ=sJ(P);if(JJ.width>v||JJ.height>v)c=v/Math.max(JJ.width,JJ.height);if(c<1)if(typeof HTMLImageElement<"u"&&P instanceof HTMLImageElement||typeof HTMLCanvasElement<"u"&&P instanceof HTMLCanvasElement||typeof ImageBitmap<"u"&&P instanceof ImageBitmap||typeof VideoFrame<"u"&&P instanceof VideoFrame){let u=Math.floor(c*JJ.width),VJ=Math.floor(c*JJ.height);if(E===void 0)E=R(u,VJ);let YJ=V?R(u,VJ):E;return YJ.width=u,YJ.height=VJ,YJ.getContext("2d").drawImage(P,0,0,u,VJ),console.warn("THREE.WebGLRenderer: Texture has been resized from ("+JJ.width+"x"+JJ.height+") to ("+u+"x"+VJ+")."),YJ}else{if("data"in P)console.warn("THREE.WebGLRenderer: Image in DataTexture is too big ("+JJ.width+"x"+JJ.height+").");return P}return P}function O(P){return P.generateMipmaps}function D(P){J.generateMipmap(P)}function k(P){if(P.isWebGLCubeRenderTarget)return J.TEXTURE_CUBE_MAP;if(P.isWebGL3DRenderTarget)return J.TEXTURE_3D;if(P.isWebGLArrayRenderTarget||P.isCompressedArrayTexture)return J.TEXTURE_2D_ARRAY;return J.TEXTURE_2D}function M(P,V,v,c,JJ=!1){if(P!==null){if(J[P]!==void 0)return J[P];console.warn("THREE.WebGLRenderer: Attempt to use non-existing WebGL internal format '"+P+"'")}let u=V;if(V===J.RED){if(v===J.FLOAT)u=J.R32F;if(v===J.HALF_FLOAT)u=J.R16F;if(v===J.UNSIGNED_BYTE)u=J.R8}if(V===J.RED_INTEGER){if(v===J.UNSIGNED_BYTE)u=J.R8UI;if(v===J.UNSIGNED_SHORT)u=J.R16UI;if(v===J.UNSIGNED_INT)u=J.R32UI;if(v===J.BYTE)u=J.R8I;if(v===J.SHORT)u=J.R16I;if(v===J.INT)u=J.R32I}if(V===J.RG){if(v===J.FLOAT)u=J.RG32F;if(v===J.HALF_FLOAT)u=J.RG16F;if(v===J.UNSIGNED_BYTE)u=J.RG8}if(V===J.RG_INTEGER){if(v===J.UNSIGNED_BYTE)u=J.RG8UI;if(v===J.UNSIGNED_SHORT)u=J.RG16UI;if(v===J.UNSIGNED_INT)u=J.RG32UI;if(v===J.BYTE)u=J.RG8I;if(v===J.SHORT)u=J.RG16I;if(v===J.INT)u=J.RG32I}if(V===J.RGB_INTEGER){if(v===J.UNSIGNED_BYTE)u=J.RGB8UI;if(v===J.UNSIGNED_SHORT)u=J.RGB16UI;if(v===J.UNSIGNED_INT)u=J.RGB32UI;if(v===J.BYTE)u=J.RGB8I;if(v===J.SHORT)u=J.RGB16I;if(v===J.INT)u=J.RGB32I}if(V===J.RGBA_INTEGER){if(v===J.UNSIGNED_BYTE)u=J.RGBA8UI;if(v===J.UNSIGNED_SHORT)u=J.RGBA16UI;if(v===J.UNSIGNED_INT)u=J.RGBA32UI;if(v===J.BYTE)u=J.RGBA8I;if(v===J.SHORT)u=J.RGBA16I;if(v===J.INT)u=J.RGBA32I}if(V===J.RGB){if(v===J.UNSIGNED_INT_5_9_9_9_REV)u=J.RGB9_E5;if(v===J.UNSIGNED_INT_10F_11F_11F_REV)u=J.R11F_G11F_B10F}if(V===J.RGBA){let VJ=JJ?vZ:tJ.getTransfer(c);if(v===J.FLOAT)u=J.RGBA32F;if(v===J.HALF_FLOAT)u=J.RGBA16F;if(v===J.UNSIGNED_BYTE)u=VJ===G0?J.SRGB8_ALPHA8:J.RGBA8;if(v===J.UNSIGNED_SHORT_4_4_4_4)u=J.RGBA4;if(v===J.UNSIGNED_SHORT_5_5_5_1)u=J.RGB5_A1}if(u===J.R16F||u===J.R32F||u===J.RG16F||u===J.RG32F||u===J.RGBA16F||u===J.RGBA32F)Q.get("EXT_color_buffer_float");return u}function L(P,V){let v;if(P){if(V===null||V===H6||V===Y6)v=J.DEPTH24_STENCIL8;else if(V===l8)v=J.DEPTH32F_STENCIL8;else if(V===m6)v=J.DEPTH24_STENCIL8,console.warn("DepthTexture: 16 bit depth attachment is not supported with stencil. Using 24-bit attachment.")}else if(V===null||V===H6||V===Y6)v=J.DEPTH_COMPONENT24;else if(V===l8)v=J.DEPTH_COMPONENT32F;else if(V===m6)v=J.DEPTH_COMPONENT16;return v}function A(P,V){if(O(P)===!0||P.isFramebufferTexture&&P.minFilter!==W6&&P.minFilter!==O9)return Math.log2(Math.max(V.width,V.height))+1;else if(P.mipmaps!==void 0&&P.mipmaps.length>0)return P.mipmaps.length;else if(P.isCompressedTexture&&Array.isArray(P.image))return V.mipmaps.length;else return 1}function _(P){let V=P.target;if(V.removeEventListener("dispose",_),y(V),V.isVideoTexture)G.delete(V)}function C(P){let V=P.target;V.removeEventListener("dispose",C),I(V)}function y(P){let V=Z.get(P);if(V.__webglInit===void 0)return;let v=P.source,c=N.get(v);if(c){let JJ=c[V.__cacheKey];if(JJ.usedTimes--,JJ.usedTimes===0)z(P);if(Object.keys(c).length===0)N.delete(v)}Z.remove(P)}function z(P){let V=Z.get(P);J.deleteTexture(V.__webglTexture);let v=P.source,c=N.get(v);delete c[V.__cacheKey],H.memory.textures--}function I(P){let V=Z.get(P);if(P.depthTexture)P.depthTexture.dispose(),Z.remove(P.depthTexture);if(P.isWebGLCubeRenderTarget)for(let c=0;c<6;c++){if(Array.isArray(V.__webglFramebuffer[c]))for(let JJ=0;JJ<V.__webglFramebuffer[c].length;JJ++)J.deleteFramebuffer(V.__webglFramebuffer[c][JJ]);else J.deleteFramebuffer(V.__webglFramebuffer[c]);if(V.__webglDepthbuffer)J.deleteRenderbuffer(V.__webglDepthbuffer[c])}else{if(Array.isArray(V.__webglFramebuffer))for(let c=0;c<V.__webglFramebuffer.length;c++)J.deleteFramebuffer(V.__webglFramebuffer[c]);else J.deleteFramebuffer(V.__webglFramebuffer);if(V.__webglDepthbuffer)J.deleteRenderbuffer(V.__webglDepthbuffer);if(V.__webglMultisampledFramebuffer)J.deleteFramebuffer(V.__webglMultisampledFramebuffer);if(V.__webglColorRenderbuffer){for(let c=0;c<V.__webglColorRenderbuffer.length;c++)if(V.__webglColorRenderbuffer[c])J.deleteRenderbuffer(V.__webglColorRenderbuffer[c])}if(V.__webglDepthRenderbuffer)J.deleteRenderbuffer(V.__webglDepthRenderbuffer)}let v=P.textures;for(let c=0,JJ=v.length;c<JJ;c++){let u=Z.get(v[c]);if(u.__webglTexture)J.deleteTexture(u.__webglTexture),H.memory.textures--;Z.remove(v[c])}Z.remove(P)}let S=0;function p(){S=0}function d(){let P=S;if(P>=W.maxTextures)console.warn("THREE.WebGLTextures: Trying to use "+P+" texture units while this GPU supports only "+W.maxTextures);return S+=1,P}function x(P){let V=[];return V.push(P.wrapS),V.push(P.wrapT),V.push(P.wrapR||0),V.push(P.magFilter),V.push(P.minFilter),V.push(P.anisotropy),V.push(P.internalFormat),V.push(P.format),V.push(P.type),V.push(P.generateMipmaps),V.push(P.premultiplyAlpha),V.push(P.flipY),V.push(P.unpackAlignment),V.push(P.colorSpace),V.join()}function o(P,V){let v=Z.get(P);if(P.isVideoTexture)lJ(P);if(P.isRenderTargetTexture===!1&&P.isExternalTexture!==!0&&P.version>0&&v.__version!==P.version){let c=P.image;if(c===null)console.warn("THREE.WebGLRenderer: Texture marked for update but no image data found.");else if(c.complete===!1)console.warn("THREE.WebGLRenderer: Texture marked for update but image is incomplete");else{qJ(v,P,V);return}}else if(P.isExternalTexture)v.__webglTexture=P.sourceTexture?P.sourceTexture:null;$.bindTexture(J.TEXTURE_2D,v.__webglTexture,J.TEXTURE0+V)}function l(P,V){let v=Z.get(P);if(P.isRenderTargetTexture===!1&&P.version>0&&v.__version!==P.version){qJ(v,P,V);return}$.bindTexture(J.TEXTURE_2D_ARRAY,v.__webglTexture,J.TEXTURE0+V)}function QJ(P,V){let v=Z.get(P);if(P.isRenderTargetTexture===!1&&P.version>0&&v.__version!==P.version){qJ(v,P,V);return}$.bindTexture(J.TEXTURE_3D,v.__webglTexture,J.TEXTURE0+V)}function m(P,V){let v=Z.get(P);if(P.version>0&&v.__version!==P.version){XJ(v,P,V);return}$.bindTexture(J.TEXTURE_CUBE_MAP,v.__webglTexture,J.TEXTURE0+V)}let EJ={[pH]:J.REPEAT,[mH]:J.CLAMP_TO_EDGE,[dH]:J.MIRRORED_REPEAT},NJ={[W6]:J.NEAREST,[lH]:J.NEAREST_MIPMAP_NEAREST,[p6]:J.NEAREST_MIPMAP_LINEAR,[O9]:J.LINEAR,[UQ]:J.LINEAR_MIPMAP_NEAREST,[K6]:J.LINEAR_MIPMAP_LINEAR},SJ={[$Y]:J.NEVER,[XY]:J.ALWAYS,[ZY]:J.LESS,[fZ]:J.LEQUAL,[WY]:J.EQUAL,[YY]:J.GEQUAL,[KY]:J.GREATER,[HY]:J.NOTEQUAL};function mJ(P,V){if(V.type===l8&&Q.has("OES_texture_float_linear")===!1&&(V.magFilter===O9||V.magFilter===UQ||V.magFilter===p6||V.magFilter===K6||V.minFilter===O9||V.minFilter===UQ||V.minFilter===p6||V.minFilter===K6))console.warn("THREE.WebGLRenderer: Unable to use linear filtering with floating point textures. OES_texture_float_linear not supported on this device.");if(J.texParameteri(P,J.TEXTURE_WRAP_S,EJ[V.wrapS]),J.texParameteri(P,J.TEXTURE_WRAP_T,EJ[V.wrapT]),P===J.TEXTURE_3D||P===J.TEXTURE_2D_ARRAY)J.texParameteri(P,J.TEXTURE_WRAP_R,EJ[V.wrapR]);if(J.texParameteri(P,J.TEXTURE_MAG_FILTER,NJ[V.magFilter]),J.texParameteri(P,J.TEXTURE_MIN_FILTER,NJ[V.minFilter]),V.compareFunction)J.texParameteri(P,J.TEXTURE_COMPARE_MODE,J.COMPARE_REF_TO_TEXTURE),J.texParameteri(P,J.TEXTURE_COMPARE_FUNC,SJ[V.compareFunction]);if(Q.has("EXT_texture_filter_anisotropic")===!0){if(V.magFilter===W6)return;if(V.minFilter!==p6&&V.minFilter!==K6)return;if(V.type===l8&&Q.has("OES_texture_float_linear")===!1)return;if(V.anisotropy>1||Z.get(V).__currentAnisotropy){let v=Q.get("EXT_texture_filter_anisotropic");J.texParameterf(P,v.TEXTURE_MAX_ANISOTROPY_EXT,Math.min(V.anisotropy,W.getMaxAnisotropy())),Z.get(V).__currentAnisotropy=V.anisotropy}}}function U0(P,V){let v=!1;if(P.__webglInit===void 0)P.__webglInit=!0,V.addEventListener("dispose",_);let c=V.source,JJ=N.get(c);if(JJ===void 0)JJ={},N.set(c,JJ);let u=x(V);if(u!==P.__cacheKey){if(JJ[u]===void 0)JJ[u]={texture:J.createTexture(),usedTimes:0},H.memory.textures++,v=!0;JJ[u].usedTimes++;let VJ=JJ[P.__cacheKey];if(VJ!==void 0){if(JJ[P.__cacheKey].usedTimes--,VJ.usedTimes===0)z(V)}P.__cacheKey=u,P.__webglTexture=JJ[u].texture}return v}function rJ(P,V,v){return Math.floor(Math.floor(P/v)/V)}function s(P,V,v,c){let u=P.updateRanges;if(u.length===0)$.texSubImage2D(J.TEXTURE_2D,0,0,0,V.width,V.height,v,c,V.data);else{u.sort((KJ,FJ)=>KJ.start-FJ.start);let VJ=0;for(let KJ=1;KJ<u.length;KJ++){let FJ=u[VJ],PJ=u[KJ],AJ=FJ.start+FJ.count,MJ=rJ(PJ.start,V.width,4),oJ=rJ(FJ.start,V.width,4);if(PJ.start<=AJ+1&&MJ===oJ&&rJ(PJ.start+PJ.count-1,V.width,4)===MJ)FJ.count=Math.max(FJ.count,PJ.start+PJ.count-FJ.start);else++VJ,u[VJ]=PJ}u.length=VJ+1;let YJ=J.getParameter(J.UNPACK_ROW_LENGTH),_J=J.getParameter(J.UNPACK_SKIP_PIXELS),vJ=J.getParameter(J.UNPACK_SKIP_ROWS);J.pixelStorei(J.UNPACK_ROW_LENGTH,V.width);for(let KJ=0,FJ=u.length;KJ<FJ;KJ++){let PJ=u[KJ],AJ=Math.floor(PJ.start/4),MJ=Math.ceil(PJ.count/4),oJ=AJ%V.width,j=Math.floor(AJ/V.width),OJ=MJ,GJ=1;J.pixelStorei(J.UNPACK_SKIP_PIXELS,oJ),J.pixelStorei(J.UNPACK_SKIP_ROWS,j),$.texSubImage2D(J.TEXTURE_2D,0,oJ,j,OJ,1,v,c,V.data)}P.clearUpdateRanges(),J.pixelStorei(J.UNPACK_ROW_LENGTH,YJ),J.pixelStorei(J.UNPACK_SKIP_PIXELS,_J),J.pixelStorei(J.UNPACK_SKIP_ROWS,vJ)}}function qJ(P,V,v){let c=J.TEXTURE_2D;if(V.isDataArrayTexture||V.isCompressedArrayTexture)c=J.TEXTURE_2D_ARRAY;if(V.isData3DTexture)c=J.TEXTURE_3D;let JJ=U0(P,V),u=V.source;$.bindTexture(c,P.__webglTexture,J.TEXTURE0+v);let VJ=Z.get(u);if(u.version!==VJ.__version||JJ===!0){$.activeTexture(J.TEXTURE0+v);let YJ=tJ.getPrimaries(tJ.workingColorSpace),_J=V.colorSpace===R9?null:tJ.getPrimaries(V.colorSpace),vJ=V.colorSpace===R9||YJ===_J?J.NONE:J.BROWSER_DEFAULT_WEBGL;J.pixelStorei(J.UNPACK_FLIP_Y_WEBGL,V.flipY),J.pixelStorei(J.UNPACK_PREMULTIPLY_ALPHA_WEBGL,V.premultiplyAlpha),J.pixelStorei(J.UNPACK_ALIGNMENT,V.unpackAlignment),J.pixelStorei(J.UNPACK_COLORSPACE_CONVERSION_WEBGL,vJ);let KJ=F(V.image,!1,W.maxTextureSize);KJ=uJ(V,KJ);let FJ=K.convert(V.format,V.colorSpace),PJ=K.convert(V.type),AJ=M(V.internalFormat,FJ,PJ,V.colorSpace,V.isVideoTexture);mJ(c,V);let MJ,oJ=V.mipmaps,j=V.isVideoTexture!==!0,OJ=VJ.__version===void 0||JJ===!0,GJ=u.dataReady,IJ=A(V,KJ);if(V.isDepthTexture){if(AJ=L(V.format===l6,V.type),OJ)if(j)$.texStorage2D(J.TEXTURE_2D,1,AJ,KJ.width,KJ.height);else $.texImage2D(J.TEXTURE_2D,0,AJ,KJ.width,KJ.height,0,FJ,PJ,null)}else if(V.isDataTexture)if(oJ.length>0){if(j&&OJ)$.texStorage2D(J.TEXTURE_2D,IJ,AJ,oJ[0].width,oJ[0].height);for(let $J=0,r=oJ.length;$J<r;$J++)if(MJ=oJ[$J],j){if(GJ)$.texSubImage2D(J.TEXTURE_2D,$J,0,0,MJ.width,MJ.height,FJ,PJ,MJ.data)}else $.texImage2D(J.TEXTURE_2D,$J,AJ,MJ.width,MJ.height,0,FJ,PJ,MJ.data);V.generateMipmaps=!1}else if(j){if(OJ)$.texStorage2D(J.TEXTURE_2D,IJ,AJ,KJ.width,KJ.height);if(GJ)s(V,KJ,FJ,PJ)}else $.texImage2D(J.TEXTURE_2D,0,AJ,KJ.width,KJ.height,0,FJ,PJ,KJ.data);else if(V.isCompressedTexture)if(V.isCompressedArrayTexture){if(j&&OJ)$.texStorage3D(J.TEXTURE_2D_ARRAY,IJ,AJ,oJ[0].width,oJ[0].height,KJ.depth);for(let $J=0,r=oJ.length;$J<r;$J++)if(MJ=oJ[$J],V.format!==F8)if(FJ!==null)if(j){if(GJ)if(V.layerUpdates.size>0){let CJ=eQ(MJ.width,MJ.height,V.format,V.type);for(let pJ of V.layerUpdates){let Y0=MJ.data.subarray(pJ*CJ/MJ.data.BYTES_PER_ELEMENT,(pJ+1)*CJ/MJ.data.BYTES_PER_ELEMENT);$.compressedTexSubImage3D(J.TEXTURE_2D_ARRAY,$J,0,0,pJ,MJ.width,MJ.height,1,FJ,Y0)}V.clearLayerUpdates()}else $.compressedTexSubImage3D(J.TEXTURE_2D_ARRAY,$J,0,0,0,MJ.width,MJ.height,KJ.depth,FJ,MJ.data)}else $.compressedTexImage3D(J.TEXTURE_2D_ARRAY,$J,AJ,MJ.width,MJ.height,KJ.depth,0,MJ.data,0,0);else console.warn("THREE.WebGLRenderer: Attempt to load unsupported compressed texture format in .uploadTexture()");else if(j){if(GJ)$.texSubImage3D(J.TEXTURE_2D_ARRAY,$J,0,0,0,MJ.width,MJ.height,KJ.depth,FJ,PJ,MJ.data)}else $.texImage3D(J.TEXTURE_2D_ARRAY,$J,AJ,MJ.width,MJ.height,KJ.depth,0,FJ,PJ,MJ.data)}else{if(j&&OJ)$.texStorage2D(J.TEXTURE_2D,IJ,AJ,oJ[0].width,oJ[0].height);for(let $J=0,r=oJ.length;$J<r;$J++)if(MJ=oJ[$J],V.format!==F8)if(FJ!==null)if(j){if(GJ)$.compressedTexSubImage2D(J.TEXTURE_2D,$J,0,0,MJ.width,MJ.height,FJ,MJ.data)}else $.compressedTexImage2D(J.TEXTURE_2D,$J,AJ,MJ.width,MJ.height,0,MJ.data);else console.warn("THREE.WebGLRenderer: Attempt to load unsupported compressed texture format in .uploadTexture()");else if(j){if(GJ)$.texSubImage2D(J.TEXTURE_2D,$J,0,0,MJ.width,MJ.height,FJ,PJ,MJ.data)}else $.texImage2D(J.TEXTURE_2D,$J,AJ,MJ.width,MJ.height,0,FJ,PJ,MJ.data)}else if(V.isDataArrayTexture)if(j){if(OJ)$.texStorage3D(J.TEXTURE_2D_ARRAY,IJ,AJ,KJ.width,KJ.height,KJ.depth);if(GJ)if(V.layerUpdates.size>0){let $J=eQ(KJ.width,KJ.height,V.format,V.type);for(let r of V.layerUpdates){let CJ=KJ.data.subarray(r*$J/KJ.data.BYTES_PER_ELEMENT,(r+1)*$J/KJ.data.BYTES_PER_ELEMENT);$.texSubImage3D(J.TEXTURE_2D_ARRAY,0,0,0,r,KJ.width,KJ.height,1,FJ,PJ,CJ)}V.clearLayerUpdates()}else $.texSubImage3D(J.TEXTURE_2D_ARRAY,0,0,0,0,KJ.width,KJ.height,KJ.depth,FJ,PJ,KJ.data)}else $.texImage3D(J.TEXTURE_2D_ARRAY,0,AJ,KJ.width,KJ.height,KJ.depth,0,FJ,PJ,KJ.data);else if(V.isData3DTexture)if(j){if(OJ)$.texStorage3D(J.TEXTURE_3D,IJ,AJ,KJ.width,KJ.height,KJ.depth);if(GJ)$.texSubImage3D(J.TEXTURE_3D,0,0,0,0,KJ.width,KJ.height,KJ.depth,FJ,PJ,KJ.data)}else $.texImage3D(J.TEXTURE_3D,0,AJ,KJ.width,KJ.height,KJ.depth,0,FJ,PJ,KJ.data);else if(V.isFramebufferTexture){if(OJ)if(j)$.texStorage2D(J.TEXTURE_2D,IJ,AJ,KJ.width,KJ.height);else{let{width:$J,height:r}=KJ;for(let CJ=0;CJ<IJ;CJ++)$.texImage2D(J.TEXTURE_2D,CJ,AJ,$J,r,0,FJ,PJ,null),$J>>=1,r>>=1}}else if(oJ.length>0){if(j&&OJ){let $J=sJ(oJ[0]);$.texStorage2D(J.TEXTURE_2D,IJ,AJ,$J.width,$J.height)}for(let $J=0,r=oJ.length;$J<r;$J++)if(MJ=oJ[$J],j){if(GJ)$.texSubImage2D(J.TEXTURE_2D,$J,0,0,FJ,PJ,MJ)}else $.texImage2D(J.TEXTURE_2D,$J,AJ,FJ,PJ,MJ);V.generateMipmaps=!1}else if(j){if(OJ){let $J=sJ(KJ);$.texStorage2D(J.TEXTURE_2D,IJ,AJ,$J.width,$J.height)}if(GJ)$.texSubImage2D(J.TEXTURE_2D,0,0,0,FJ,PJ,KJ)}else $.texImage2D(J.TEXTURE_2D,0,AJ,FJ,PJ,KJ);if(O(V))D(c);if(VJ.__version=u.version,V.onUpdate)V.onUpdate(V)}P.__version=V.version}function XJ(P,V,v){if(V.image.length!==6)return;let c=U0(P,V),JJ=V.source;$.bindTexture(J.TEXTURE_CUBE_MAP,P.__webglTexture,J.TEXTURE0+v);let u=Z.get(JJ);if(JJ.version!==u.__version||c===!0){$.activeTexture(J.TEXTURE0+v);let VJ=tJ.getPrimaries(tJ.workingColorSpace),YJ=V.colorSpace===R9?null:tJ.getPrimaries(V.colorSpace),_J=V.colorSpace===R9||VJ===YJ?J.NONE:J.BROWSER_DEFAULT_WEBGL;J.pixelStorei(J.UNPACK_FLIP_Y_WEBGL,V.flipY),J.pixelStorei(J.UNPACK_PREMULTIPLY_ALPHA_WEBGL,V.premultiplyAlpha),J.pixelStorei(J.UNPACK_ALIGNMENT,V.unpackAlignment),J.pixelStorei(J.UNPACK_COLORSPACE_CONVERSION_WEBGL,_J);let vJ=V.isCompressedTexture||V.image[0].isCompressedTexture,KJ=V.image[0]&&V.image[0].isDataTexture,FJ=[];for(let r=0;r<6;r++){if(!vJ&&!KJ)FJ[r]=F(V.image[r],!0,W.maxCubemapSize);else FJ[r]=KJ?V.image[r].image:V.image[r];FJ[r]=uJ(V,FJ[r])}let PJ=FJ[0],AJ=K.convert(V.format,V.colorSpace),MJ=K.convert(V.type),oJ=M(V.internalFormat,AJ,MJ,V.colorSpace),j=V.isVideoTexture!==!0,OJ=u.__version===void 0||c===!0,GJ=JJ.dataReady,IJ=A(V,PJ);mJ(J.TEXTURE_CUBE_MAP,V);let $J;if(vJ){if(j&&OJ)$.texStorage2D(J.TEXTURE_CUBE_MAP,IJ,oJ,PJ.width,PJ.height);for(let r=0;r<6;r++){$J=FJ[r].mipmaps;for(let CJ=0;CJ<$J.length;CJ++){let pJ=$J[CJ];if(V.format!==F8)if(AJ!==null)if(j){if(GJ)$.compressedTexSubImage2D(J.TEXTURE_CUBE_MAP_POSITIVE_X+r,CJ,0,0,pJ.width,pJ.height,AJ,pJ.data)}else $.compressedTexImage2D(J.TEXTURE_CUBE_MAP_POSITIVE_X+r,CJ,oJ,pJ.width,pJ.height,0,pJ.data);else console.warn("THREE.WebGLRenderer: Attempt to load unsupported compressed texture format in .setTextureCube()");else if(j){if(GJ)$.texSubImage2D(J.TEXTURE_CUBE_MAP_POSITIVE_X+r,CJ,0,0,pJ.width,pJ.height,AJ,MJ,pJ.data)}else $.texImage2D(J.TEXTURE_CUBE_MAP_POSITIVE_X+r,CJ,oJ,pJ.width,pJ.height,0,AJ,MJ,pJ.data)}}}else{if($J=V.mipmaps,j&&OJ){if($J.length>0)IJ++;let r=sJ(FJ[0]);$.texStorage2D(J.TEXTURE_CUBE_MAP,IJ,oJ,r.width,r.height)}for(let r=0;r<6;r++)if(KJ){if(j){if(GJ)$.texSubImage2D(J.TEXTURE_CUBE_MAP_POSITIVE_X+r,0,0,0,FJ[r].width,FJ[r].height,AJ,MJ,FJ[r].data)}else $.texImage2D(J.TEXTURE_CUBE_MAP_POSITIVE_X+r,0,oJ,FJ[r].width,FJ[r].height,0,AJ,MJ,FJ[r].data);for(let CJ=0;CJ<$J.length;CJ++){let Y0=$J[CJ].image[r].image;if(j){if(GJ)$.texSubImage2D(J.TEXTURE_CUBE_MAP_POSITIVE_X+r,CJ+1,0,0,Y0.width,Y0.height,AJ,MJ,Y0.data)}else $.texImage2D(J.TEXTURE_CUBE_MAP_POSITIVE_X+r,CJ+1,oJ,Y0.width,Y0.height,0,AJ,MJ,Y0.data)}}else{if(j){if(GJ)$.texSubImage2D(J.TEXTURE_CUBE_MAP_POSITIVE_X+r,0,0,0,AJ,MJ,FJ[r])}else $.texImage2D(J.TEXTURE_CUBE_MAP_POSITIVE_X+r,0,oJ,AJ,MJ,FJ[r]);for(let CJ=0;CJ<$J.length;CJ++){let pJ=$J[CJ];if(j){if(GJ)$.texSubImage2D(J.TEXTURE_CUBE_MAP_POSITIVE_X+r,CJ+1,0,0,AJ,MJ,pJ.image[r])}else $.texImage2D(J.TEXTURE_CUBE_MAP_POSITIVE_X+r,CJ+1,oJ,AJ,MJ,pJ.image[r])}}}if(O(V))D(J.TEXTURE_CUBE_MAP);if(u.__version=JJ.version,V.onUpdate)V.onUpdate(V)}P.__version=V.version}function LJ(P,V,v,c,JJ,u){let VJ=K.convert(v.format,v.colorSpace),YJ=K.convert(v.type),_J=M(v.internalFormat,VJ,YJ,v.colorSpace),vJ=Z.get(V),KJ=Z.get(v);if(KJ.__renderTarget=V,!vJ.__hasExternalTextures){let FJ=Math.max(1,V.width>>u),PJ=Math.max(1,V.height>>u);if(JJ===J.TEXTURE_3D||JJ===J.TEXTURE_2D_ARRAY)$.texImage3D(JJ,u,_J,FJ,PJ,V.depth,0,VJ,YJ,null);else $.texImage2D(JJ,u,_J,FJ,PJ,0,VJ,YJ,null)}if($.bindFramebuffer(J.FRAMEBUFFER,P),ZJ(V))Y.framebufferTexture2DMultisampleEXT(J.FRAMEBUFFER,c,JJ,KJ.__webglTexture,0,HJ(V));else if(JJ===J.TEXTURE_2D||JJ>=J.TEXTURE_CUBE_MAP_POSITIVE_X&&JJ<=J.TEXTURE_CUBE_MAP_NEGATIVE_Z)J.framebufferTexture2D(J.FRAMEBUFFER,c,JJ,KJ.__webglTexture,u);$.bindFramebuffer(J.FRAMEBUFFER,null)}function yJ(P,V,v){if(J.bindRenderbuffer(J.RENDERBUFFER,P),V.depthBuffer){let c=V.depthTexture,JJ=c&&c.isDepthTexture?c.type:null,u=L(V.stencilBuffer,JJ),VJ=V.stencilBuffer?J.DEPTH_STENCIL_ATTACHMENT:J.DEPTH_ATTACHMENT,YJ=HJ(V);if(ZJ(V))Y.renderbufferStorageMultisampleEXT(J.RENDERBUFFER,YJ,u,V.width,V.height);else if(v)J.renderbufferStorageMultisample(J.RENDERBUFFER,YJ,u,V.width,V.height);else J.renderbufferStorage(J.RENDERBUFFER,u,V.width,V.height);J.framebufferRenderbuffer(J.FRAMEBUFFER,VJ,J.RENDERBUFFER,P)}else{let c=V.textures;for(let JJ=0;JJ<c.length;JJ++){let u=c[JJ],VJ=K.convert(u.format,u.colorSpace),YJ=K.convert(u.type),_J=M(u.internalFormat,VJ,YJ,u.colorSpace),vJ=HJ(V);if(v&&ZJ(V)===!1)J.renderbufferStorageMultisample(J.RENDERBUFFER,vJ,_J,V.width,V.height);else if(ZJ(V))Y.renderbufferStorageMultisampleEXT(J.RENDERBUFFER,vJ,_J,V.width,V.height);else J.renderbufferStorage(J.RENDERBUFFER,_J,V.width,V.height)}}J.bindRenderbuffer(J.RENDERBUFFER,null)}function xJ(P,V){if(V&&V.isWebGLCubeRenderTarget)throw Error("Depth Texture with cube render targets is not supported");if($.bindFramebuffer(J.FRAMEBUFFER,P),!(V.depthTexture&&V.depthTexture.isDepthTexture))throw Error("renderTarget.depthTexture must be an instance of THREE.DepthTexture");let c=Z.get(V.depthTexture);if(c.__renderTarget=V,!c.__webglTexture||V.depthTexture.image.width!==V.width||V.depthTexture.image.height!==V.height)V.depthTexture.image.width=V.width,V.depthTexture.image.height=V.height,V.depthTexture.needsUpdate=!0;o(V.depthTexture,0);let JJ=c.__webglTexture,u=HJ(V);if(V.depthTexture.format===GQ)if(ZJ(V))Y.framebufferTexture2DMultisampleEXT(J.FRAMEBUFFER,J.DEPTH_ATTACHMENT,J.TEXTURE_2D,JJ,0,u);else J.framebufferTexture2D(J.FRAMEBUFFER,J.DEPTH_ATTACHMENT,J.TEXTURE_2D,JJ,0);else if(V.depthTexture.format===l6)if(ZJ(V))Y.framebufferTexture2DMultisampleEXT(J.FRAMEBUFFER,J.DEPTH_STENCIL_ATTACHMENT,J.TEXTURE_2D,JJ,0,u);else J.framebufferTexture2D(J.FRAMEBUFFER,J.DEPTH_STENCIL_ATTACHMENT,J.TEXTURE_2D,JJ,0);else throw Error("Unknown depthTexture format")}function W0(P){let V=Z.get(P),v=P.isWebGLCubeRenderTarget===!0;if(V.__boundDepthTexture!==P.depthTexture){let c=P.depthTexture;if(V.__depthDisposeCallback)V.__depthDisposeCallback();if(c){let JJ=()=>{delete V.__boundDepthTexture,delete V.__depthDisposeCallback,c.removeEventListener("dispose",JJ)};c.addEventListener("dispose",JJ),V.__depthDisposeCallback=JJ}V.__boundDepthTexture=c}if(P.depthTexture&&!V.__autoAllocateDepthBuffer){if(v)throw Error("target.depthTexture not supported in Cube render targets");let c=P.texture.mipmaps;if(c&&c.length>0)xJ(V.__webglFramebuffer[0],P);else xJ(V.__webglFramebuffer,P)}else if(v){V.__webglDepthbuffer=[];for(let c=0;c<6;c++)if($.bindFramebuffer(J.FRAMEBUFFER,V.__webglFramebuffer[c]),V.__webglDepthbuffer[c]===void 0)V.__webglDepthbuffer[c]=J.createRenderbuffer(),yJ(V.__webglDepthbuffer[c],P,!1);else{let JJ=P.stencilBuffer?J.DEPTH_STENCIL_ATTACHMENT:J.DEPTH_ATTACHMENT,u=V.__webglDepthbuffer[c];J.bindRenderbuffer(J.RENDERBUFFER,u),J.framebufferRenderbuffer(J.FRAMEBUFFER,JJ,J.RENDERBUFFER,u)}}else{let c=P.texture.mipmaps;if(c&&c.length>0)$.bindFramebuffer(J.FRAMEBUFFER,V.__webglFramebuffer[0]);else $.bindFramebuffer(J.FRAMEBUFFER,V.__webglFramebuffer);if(V.__webglDepthbuffer===void 0)V.__webglDepthbuffer=J.createRenderbuffer(),yJ(V.__webglDepthbuffer,P,!1);else{let JJ=P.stencilBuffer?J.DEPTH_STENCIL_ATTACHMENT:J.DEPTH_ATTACHMENT,u=V.__webglDepthbuffer;J.bindRenderbuffer(J.RENDERBUFFER,u),J.framebufferRenderbuffer(J.FRAMEBUFFER,JJ,J.RENDERBUFFER,u)}}$.bindFramebuffer(J.FRAMEBUFFER,null)}function T(P,V,v){let c=Z.get(P);if(V!==void 0)LJ(c.__webglFramebuffer,P,P.texture,J.COLOR_ATTACHMENT0,J.TEXTURE_2D,0);if(v!==void 0)W0(P)}function e(P){let V=P.texture,v=Z.get(P),c=Z.get(V);P.addEventListener("dispose",C);let JJ=P.textures,u=P.isWebGLCubeRenderTarget===!0,VJ=JJ.length>1;if(!VJ){if(c.__webglTexture===void 0)c.__webglTexture=J.createTexture();c.__version=V.version,H.memory.textures++}if(u){v.__webglFramebuffer=[];for(let YJ=0;YJ<6;YJ++)if(V.mipmaps&&V.mipmaps.length>0){v.__webglFramebuffer[YJ]=[];for(let _J=0;_J<V.mipmaps.length;_J++)v.__webglFramebuffer[YJ][_J]=J.createFramebuffer()}else v.__webglFramebuffer[YJ]=J.createFramebuffer()}else{if(V.mipmaps&&V.mipmaps.length>0){v.__webglFramebuffer=[];for(let YJ=0;YJ<V.mipmaps.length;YJ++)v.__webglFramebuffer[YJ]=J.createFramebuffer()}else v.__webglFramebuffer=J.createFramebuffer();if(VJ)for(let YJ=0,_J=JJ.length;YJ<_J;YJ++){let vJ=Z.get(JJ[YJ]);if(vJ.__webglTexture===void 0)vJ.__webglTexture=J.createTexture(),H.memory.textures++}if(P.samples>0&&ZJ(P)===!1){v.__webglMultisampledFramebuffer=J.createFramebuffer(),v.__webglColorRenderbuffer=[],$.bindFramebuffer(J.FRAMEBUFFER,v.__webglMultisampledFramebuffer);for(let YJ=0;YJ<JJ.length;YJ++){let _J=JJ[YJ];v.__webglColorRenderbuffer[YJ]=J.createRenderbuffer(),J.bindRenderbuffer(J.RENDERBUFFER,v.__webglColorRenderbuffer[YJ]);let vJ=K.convert(_J.format,_J.colorSpace),KJ=K.convert(_J.type),FJ=M(_J.internalFormat,vJ,KJ,_J.colorSpace,P.isXRRenderTarget===!0),PJ=HJ(P);J.renderbufferStorageMultisample(J.RENDERBUFFER,PJ,FJ,P.width,P.height),J.framebufferRenderbuffer(J.FRAMEBUFFER,J.COLOR_ATTACHMENT0+YJ,J.RENDERBUFFER,v.__webglColorRenderbuffer[YJ])}if(J.bindRenderbuffer(J.RENDERBUFFER,null),P.depthBuffer)v.__webglDepthRenderbuffer=J.createRenderbuffer(),yJ(v.__webglDepthRenderbuffer,P,!0);$.bindFramebuffer(J.FRAMEBUFFER,null)}}if(u){$.bindTexture(J.TEXTURE_CUBE_MAP,c.__webglTexture),mJ(J.TEXTURE_CUBE_MAP,V);for(let YJ=0;YJ<6;YJ++)if(V.mipmaps&&V.mipmaps.length>0)for(let _J=0;_J<V.mipmaps.length;_J++)LJ(v.__webglFramebuffer[YJ][_J],P,V,J.COLOR_ATTACHMENT0,J.TEXTURE_CUBE_MAP_POSITIVE_X+YJ,_J);else LJ(v.__webglFramebuffer[YJ],P,V,J.COLOR_ATTACHMENT0,J.TEXTURE_CUBE_MAP_POSITIVE_X+YJ,0);if(O(V))D(J.TEXTURE_CUBE_MAP);$.unbindTexture()}else if(VJ){for(let YJ=0,_J=JJ.length;YJ<_J;YJ++){let vJ=JJ[YJ],KJ=Z.get(vJ),FJ=J.TEXTURE_2D;if(P.isWebGL3DRenderTarget||P.isWebGLArrayRenderTarget)FJ=P.isWebGL3DRenderTarget?J.TEXTURE_3D:J.TEXTURE_2D_ARRAY;if($.bindTexture(FJ,KJ.__webglTexture),mJ(FJ,vJ),LJ(v.__webglFramebuffer,P,vJ,J.COLOR_ATTACHMENT0+YJ,FJ,0),O(vJ))D(FJ)}$.unbindTexture()}else{let YJ=J.TEXTURE_2D;if(P.isWebGL3DRenderTarget||P.isWebGLArrayRenderTarget)YJ=P.isWebGL3DRenderTarget?J.TEXTURE_3D:J.TEXTURE_2D_ARRAY;if($.bindTexture(YJ,c.__webglTexture),mJ(YJ,V),V.mipmaps&&V.mipmaps.length>0)for(let _J=0;_J<V.mipmaps.length;_J++)LJ(v.__webglFramebuffer[_J],P,V,J.COLOR_ATTACHMENT0,YJ,_J);else LJ(v.__webglFramebuffer,P,V,J.COLOR_ATTACHMENT0,YJ,0);if(O(V))D(YJ);$.unbindTexture()}if(P.depthBuffer)W0(P)}function a(P){let V=P.textures;for(let v=0,c=V.length;v<c;v++){let JJ=V[v];if(O(JJ)){let u=k(P),VJ=Z.get(JJ).__webglTexture;$.bindTexture(u,VJ),D(u),$.unbindTexture()}}}let i=[],n=[];function UJ(P){if(P.samples>0){if(ZJ(P)===!1){let{textures:V,width:v,height:c}=P,JJ=J.COLOR_BUFFER_BIT,u=P.stencilBuffer?J.DEPTH_STENCIL_ATTACHMENT:J.DEPTH_ATTACHMENT,VJ=Z.get(P),YJ=V.length>1;if(YJ)for(let vJ=0;vJ<V.length;vJ++)$.bindFramebuffer(J.FRAMEBUFFER,VJ.__webglMultisampledFramebuffer),J.framebufferRenderbuffer(J.FRAMEBUFFER,J.COLOR_ATTACHMENT0+vJ,J.RENDERBUFFER,null),$.bindFramebuffer(J.FRAMEBUFFER,VJ.__webglFramebuffer),J.framebufferTexture2D(J.DRAW_FRAMEBUFFER,J.COLOR_ATTACHMENT0+vJ,J.TEXTURE_2D,null,0);$.bindFramebuffer(J.READ_FRAMEBUFFER,VJ.__webglMultisampledFramebuffer);let _J=P.texture.mipmaps;if(_J&&_J.length>0)$.bindFramebuffer(J.DRAW_FRAMEBUFFER,VJ.__webglFramebuffer[0]);else $.bindFramebuffer(J.DRAW_FRAMEBUFFER,VJ.__webglFramebuffer);for(let vJ=0;vJ<V.length;vJ++){if(P.resolveDepthBuffer){if(P.depthBuffer)JJ|=J.DEPTH_BUFFER_BIT;if(P.stencilBuffer&&P.resolveStencilBuffer)JJ|=J.STENCIL_BUFFER_BIT}if(YJ){J.framebufferRenderbuffer(J.READ_FRAMEBUFFER,J.COLOR_ATTACHMENT0,J.RENDERBUFFER,VJ.__webglColorRenderbuffer[vJ]);let KJ=Z.get(V[vJ]).__webglTexture;J.framebufferTexture2D(J.DRAW_FRAMEBUFFER,J.COLOR_ATTACHMENT0,J.TEXTURE_2D,KJ,0)}if(J.blitFramebuffer(0,0,v,c,0,0,v,c,JJ,J.NEAREST),X===!0){if(i.length=0,n.length=0,i.push(J.COLOR_ATTACHMENT0+vJ),P.depthBuffer&&P.resolveDepthBuffer===!1)i.push(u),n.push(u),J.invalidateFramebuffer(J.DRAW_FRAMEBUFFER,n);J.invalidateFramebuffer(J.READ_FRAMEBUFFER,i)}}if($.bindFramebuffer(J.READ_FRAMEBUFFER,null),$.bindFramebuffer(J.DRAW_FRAMEBUFFER,null),YJ)for(let vJ=0;vJ<V.length;vJ++){$.bindFramebuffer(J.FRAMEBUFFER,VJ.__webglMultisampledFramebuffer),J.framebufferRenderbuffer(J.FRAMEBUFFER,J.COLOR_ATTACHMENT0+vJ,J.RENDERBUFFER,VJ.__webglColorRenderbuffer[vJ]);let KJ=Z.get(V[vJ]).__webglTexture;$.bindFramebuffer(J.FRAMEBUFFER,VJ.__webglFramebuffer),J.framebufferTexture2D(J.DRAW_FRAMEBUFFER,J.COLOR_ATTACHMENT0+vJ,J.TEXTURE_2D,KJ,0)}$.bindFramebuffer(J.DRAW_FRAMEBUFFER,VJ.__webglMultisampledFramebuffer)}else if(P.depthBuffer&&P.resolveDepthBuffer===!1&&X){let V=P.stencilBuffer?J.DEPTH_STENCIL_ATTACHMENT:J.DEPTH_ATTACHMENT;J.invalidateFramebuffer(J.DRAW_FRAMEBUFFER,[V])}}}function HJ(P){return Math.min(W.maxSamples,P.samples)}function ZJ(P){let V=Z.get(P);return P.samples>0&&Q.has("WEBGL_multisampled_render_to_texture")===!0&&V.__useRenderToTexture!==!1}function lJ(P){let V=H.render.frame;if(G.get(P)!==V)G.set(P,V),P.update()}function uJ(P,V){let{colorSpace:v,format:c,type:JJ}=P;if(P.isCompressedTexture===!0||P.isVideoTexture===!0)return V;if(v!==u6&&v!==R9)if(tJ.getTransfer(v)===G0){if(c!==F8||JJ!==d8)console.warn("THREE.WebGLTextures: sRGB encoded textures have to use RGBAFormat and UnsignedByteType.")}else console.error("THREE.WebGLTextures: Unsupported texture color space:",v);return V}function sJ(P){if(typeof HTMLImageElement<"u"&&P instanceof HTMLImageElement)U.width=P.naturalWidth||P.width,U.height=P.naturalHeight||P.height;else if(typeof VideoFrame<"u"&&P instanceof VideoFrame)U.width=P.displayWidth,U.height=P.displayHeight;else U.width=P.width,U.height=P.height;return U}this.allocateTextureUnit=d,this.resetTextureUnits=p,this.setTexture2D=o,this.setTexture2DArray=l,this.setTexture3D=QJ,this.setTextureCube=m,this.rebindTextures=T,this.setupRenderTarget=e,this.updateRenderTargetMipmap=a,this.updateMultisampleRenderTarget=UJ,this.setupDepthRenderbuffer=W0,this.setupFrameBufferTexture=LJ,this.useMultisampledRTT=ZJ}function h5(J,Q){function $(Z,W=R9){let K,H=tJ.getTransfer(W);if(Z===d8)return J.UNSIGNED_BYTE;if(Z===QZ)return J.UNSIGNED_SHORT_4_4_4_4;if(Z===$Z)return J.UNSIGNED_SHORT_5_5_5_1;if(Z===nH)return J.UNSIGNED_INT_5_9_9_9_REV;if(Z===sH)return J.UNSIGNED_INT_10F_11F_11F_REV;if(Z===uH)return J.BYTE;if(Z===cH)return J.SHORT;if(Z===m6)return J.UNSIGNED_SHORT;if(Z===JZ)return J.INT;if(Z===H6)return J.UNSIGNED_INT;if(Z===l8)return J.FLOAT;if(Z===d6)return J.HALF_FLOAT;if(Z===iH)return J.ALPHA;if(Z===oH)return J.RGB;if(Z===F8)return J.RGBA;if(Z===GQ)return J.DEPTH_COMPONENT;if(Z===l6)return J.DEPTH_STENCIL;if(Z===aH)return J.RED;if(Z===ZZ)return J.RED_INTEGER;if(Z===rH)return J.RG;if(Z===WZ)return J.RG_INTEGER;if(Z===KZ)return J.RGBA_INTEGER;if(Z===EQ||Z===NQ||Z===qQ||Z===DQ)if(H===G0)if(K=Q.get("WEBGL_compressed_texture_s3tc_srgb"),K!==null){if(Z===EQ)return K.COMPRESSED_SRGB_S3TC_DXT1_EXT;if(Z===NQ)return K.COMPRESSED_SRGB_ALPHA_S3TC_DXT1_EXT;if(Z===qQ)return K.COMPRESSED_SRGB_ALPHA_S3TC_DXT3_EXT;if(Z===DQ)return K.COMPRESSED_SRGB_ALPHA_S3TC_DXT5_EXT}else return null;else if(K=Q.get("WEBGL_compressed_texture_s3tc"),K!==null){if(Z===EQ)return K.COMPRESSED_RGB_S3TC_DXT1_EXT;if(Z===NQ)return K.COMPRESSED_RGBA_S3TC_DXT1_EXT;if(Z===qQ)return K.COMPRESSED_RGBA_S3TC_DXT3_EXT;if(Z===DQ)return K.COMPRESSED_RGBA_S3TC_DXT5_EXT}else return null;if(Z===HZ||Z===YZ||Z===XZ||Z===UZ)if(K=Q.get("WEBGL_compressed_texture_pvrtc"),K!==null){if(Z===HZ)return K.COMPRESSED_RGB_PVRTC_4BPPV1_IMG;if(Z===YZ)return K.COMPRESSED_RGB_PVRTC_2BPPV1_IMG;if(Z===XZ)return K.COMPRESSED_RGBA_PVRTC_4BPPV1_IMG;if(Z===UZ)return K.COMPRESSED_RGBA_PVRTC_2BPPV1_IMG}else return null;if(Z===GZ||Z===EZ||Z===NZ)if(K=Q.get("WEBGL_compressed_texture_etc"),K!==null){if(Z===GZ||Z===EZ)return H===G0?K.COMPRESSED_SRGB8_ETC2:K.COMPRESSED_RGB8_ETC2;if(Z===NZ)return H===G0?K.COMPRESSED_SRGB8_ALPHA8_ETC2_EAC:K.COMPRESSED_RGBA8_ETC2_EAC}else return null;if(Z===qZ||Z===DZ||Z===OZ||Z===RZ||Z===FZ||Z===MZ||Z===kZ||Z===VZ||Z===LZ||Z===zZ||Z===BZ||Z===IZ||Z===_Z||Z===wZ)if(K=Q.get("WEBGL_compressed_texture_astc"),K!==null){if(Z===qZ)return H===G0?K.COMPRESSED_SRGB8_ALPHA8_ASTC_4x4_KHR:K.COMPRESSED_RGBA_ASTC_4x4_KHR;if(Z===DZ)return H===G0?K.COMPRESSED_SRGB8_ALPHA8_ASTC_5x4_KHR:K.COMPRESSED_RGBA_ASTC_5x4_KHR;if(Z===OZ)return H===G0?K.COMPRESSED_SRGB8_ALPHA8_ASTC_5x5_KHR:K.COMPRESSED_RGBA_ASTC_5x5_KHR;if(Z===RZ)return H===G0?K.COMPRESSED_SRGB8_ALPHA8_ASTC_6x5_KHR:K.COMPRESSED_RGBA_ASTC_6x5_KHR;if(Z===FZ)return H===G0?K.COMPRESSED_SRGB8_ALPHA8_ASTC_6x6_KHR:K.COMPRESSED_RGBA_ASTC_6x6_KHR;if(Z===MZ)return H===G0?K.COMPRESSED_SRGB8_ALPHA8_ASTC_8x5_KHR:K.COMPRESSED_RGBA_ASTC_8x5_KHR;if(Z===kZ)return H===G0?K.COMPRESSED_SRGB8_ALPHA8_ASTC_8x6_KHR:K.COMPRESSED_RGBA_ASTC_8x6_KHR;if(Z===VZ)return H===G0?K.COMPRESSED_SRGB8_ALPHA8_ASTC_8x8_KHR:K.COMPRESSED_RGBA_ASTC_8x8_KHR;if(Z===LZ)return H===G0?K.COMPRESSED_SRGB8_ALPHA8_ASTC_10x5_KHR:K.COMPRESSED_RGBA_ASTC_10x5_KHR;if(Z===zZ)return H===G0?K.COMPRESSED_SRGB8_ALPHA8_ASTC_10x6_KHR:K.COMPRESSED_RGBA_ASTC_10x6_KHR;if(Z===BZ)return H===G0?K.COMPRESSED_SRGB8_ALPHA8_ASTC_10x8_KHR:K.COMPRESSED_RGBA_ASTC_10x8_KHR;if(Z===IZ)return H===G0?K.COMPRESSED_SRGB8_ALPHA8_ASTC_10x10_KHR:K.COMPRESSED_RGBA_ASTC_10x10_KHR;if(Z===_Z)return H===G0?K.COMPRESSED_SRGB8_ALPHA8_ASTC_12x10_KHR:K.COMPRESSED_RGBA_ASTC_12x10_KHR;if(Z===wZ)return H===G0?K.COMPRESSED_SRGB8_ALPHA8_ASTC_12x12_KHR:K.COMPRESSED_RGBA_ASTC_12x12_KHR}else return null;if(Z===CZ||Z===PZ||Z===AZ)if(K=Q.get("EXT_texture_compression_bptc"),K!==null){if(Z===CZ)return H===G0?K.COMPRESSED_SRGB_ALPHA_BPTC_UNORM_EXT:K.COMPRESSED_RGBA_BPTC_UNORM_EXT;if(Z===PZ)return K.COMPRESSED_RGB_BPTC_SIGNED_FLOAT_EXT;if(Z===AZ)return K.COMPRESSED_RGB_BPTC_UNSIGNED_FLOAT_EXT}else return null;if(Z===TZ||Z===SZ||Z===jZ||Z===yZ)if(K=Q.get("EXT_texture_compression_rgtc"),K!==null){if(Z===TZ)return K.COMPRESSED_RED_RGTC1_EXT;if(Z===SZ)return K.COMPRESSED_SIGNED_RED_RGTC1_EXT;if(Z===jZ)return K.COMPRESSED_RED_GREEN_RGTC2_EXT;if(Z===yZ)return K.COMPRESSED_SIGNED_RED_GREEN_RGTC2_EXT}else return null;if(Z===Y6)return J.UNSIGNED_INT_24_8;return J[Z]!==void 0?J[Z]:null}return{convert:$}}var x5=`
void main() {

	gl_Position = vec4( position, 1.0 );

}`,g5=`
uniform sampler2DArray depthColor;
uniform float depthWidth;
uniform float depthHeight;

void main() {

	vec2 coord = vec2( gl_FragCoord.x / depthWidth, gl_FragCoord.y / depthHeight );

	if ( coord.x >= 1.0 ) {

		gl_FragDepth = texture( depthColor, vec3( coord.x - 1.0, coord.y, 1 ) ).r;

	} else {

		gl_FragDepth = texture( depthColor, vec3( coord.x, coord.y, 0 ) ).r;

	}

}`;class UU{constructor(){this.texture=null,this.mesh=null,this.depthNear=0,this.depthFar=0}init(J,Q){if(this.texture===null){let $=new wQ(J.texture);if(J.depthNear!==Q.depthNear||J.depthFar!==Q.depthFar)this.depthNear=J.depthNear,this.depthFar=J.depthFar;this.texture=$}}getMesh(J){if(this.texture!==null){if(this.mesh===null){let Q=J.cameras[0].viewport,$=new e0({vertexShader:x5,fragmentShader:g5,uniforms:{depthColor:{value:this.texture},depthWidth:{value:Q.z},depthHeight:{value:Q.w}}});this.mesh=new k0(new U6(20,20),$)}}return this.mesh}reset(){this.texture=null,this.mesh=null}getDepthTexture(){return this.texture}}class GU extends H8{constructor(J,Q){super();let $=this,Z=null,W=1,K=null,H="local-floor",Y=1,X=null,U=null,G=null,E=null,N=null,q=null,R=typeof XRWebGLBinding<"u",F=new UU,O={},D=Q.getContextAttributes(),k=null,M=null,L=[],A=[],_=new t,C=null,y=new I0;y.viewport=new J0;let z=new I0;z.viewport=new J0;let I=[y,z],S=new TW,p=null,d=null;this.cameraAutoUpdate=!0,this.enabled=!1,this.isPresenting=!1,this.getController=function(s){let qJ=L[s];if(qJ===void 0)qJ=new o6,L[s]=qJ;return qJ.getTargetRaySpace()},this.getControllerGrip=function(s){let qJ=L[s];if(qJ===void 0)qJ=new o6,L[s]=qJ;return qJ.getGripSpace()},this.getHand=function(s){let qJ=L[s];if(qJ===void 0)qJ=new o6,L[s]=qJ;return qJ.getHandSpace()};function x(s){let qJ=A.indexOf(s.inputSource);if(qJ===-1)return;let XJ=L[qJ];if(XJ!==void 0)XJ.update(s.inputSource,s.frame,X||K),XJ.dispatchEvent({type:s.type,data:s.inputSource})}function o(){Z.removeEventListener("select",x),Z.removeEventListener("selectstart",x),Z.removeEventListener("selectend",x),Z.removeEventListener("squeeze",x),Z.removeEventListener("squeezestart",x),Z.removeEventListener("squeezeend",x),Z.removeEventListener("end",o),Z.removeEventListener("inputsourceschange",l);for(let s=0;s<L.length;s++){let qJ=A[s];if(qJ===null)continue;A[s]=null,L[s].disconnect(qJ)}p=null,d=null,F.reset();for(let s in O)delete O[s];J.setRenderTarget(k),N=null,E=null,G=null,Z=null,M=null,rJ.stop(),$.isPresenting=!1,J.setPixelRatio(C),J.setSize(_.width,_.height,!1),$.dispatchEvent({type:"sessionend"})}this.setFramebufferScaleFactor=function(s){if(W=s,$.isPresenting===!0)console.warn("THREE.WebXRManager: Cannot change framebuffer scale while presenting.")},this.setReferenceSpaceType=function(s){if(H=s,$.isPresenting===!0)console.warn("THREE.WebXRManager: Cannot change reference space type while presenting.")},this.getReferenceSpace=function(){return X||K},this.setReferenceSpace=function(s){X=s},this.getBaseLayer=function(){return E!==null?E:N},this.getBinding=function(){if(G===null&&R)G=new XRWebGLBinding(Z,Q);return G},this.getFrame=function(){return q},this.getSession=function(){return Z},this.setSession=async function(s){if(Z=s,Z!==null){if(k=J.getRenderTarget(),Z.addEventListener("select",x),Z.addEventListener("selectstart",x),Z.addEventListener("selectend",x),Z.addEventListener("squeeze",x),Z.addEventListener("squeezestart",x),Z.addEventListener("squeezeend",x),Z.addEventListener("end",o),Z.addEventListener("inputsourceschange",l),D.xrCompatible!==!0)await Q.makeXRCompatible();if(C=J.getPixelRatio(),J.getSize(_),!(R&&("createProjectionLayer"in XRWebGLBinding.prototype))){let XJ={antialias:D.antialias,alpha:!0,depth:D.depth,stencil:D.stencil,framebufferScaleFactor:W};N=new XRWebGLLayer(Z,Q,XJ),Z.updateRenderState({baseLayer:N}),J.setPixelRatio(1),J.setSize(N.framebufferWidth,N.framebufferHeight,!1),M=new Y8(N.framebufferWidth,N.framebufferHeight,{format:F8,type:d8,colorSpace:J.outputColorSpace,stencilBuffer:D.stencil,resolveDepthBuffer:N.ignoreDepthValues===!1,resolveStencilBuffer:N.ignoreDepthValues===!1})}else{let XJ=null,LJ=null,yJ=null;if(D.depth)yJ=D.stencil?Q.DEPTH24_STENCIL8:Q.DEPTH_COMPONENT24,XJ=D.stencil?l6:GQ,LJ=D.stencil?Y6:H6;let xJ={colorFormat:Q.RGBA8,depthFormat:yJ,scaleFactor:W};G=this.getBinding(),E=G.createProjectionLayer(xJ),Z.updateRenderState({layers:[E]}),J.setPixelRatio(1),J.setSize(E.textureWidth,E.textureHeight,!1),M=new Y8(E.textureWidth,E.textureHeight,{format:F8,type:d8,depthTexture:new _Q(E.textureWidth,E.textureHeight,LJ,void 0,void 0,void 0,void 0,void 0,void 0,XJ),stencilBuffer:D.stencil,colorSpace:J.outputColorSpace,samples:D.antialias?4:0,resolveDepthBuffer:E.ignoreDepthValues===!1,resolveStencilBuffer:E.ignoreDepthValues===!1})}M.isXRRenderTarget=!0,this.setFoveation(Y),X=null,K=await Z.requestReferenceSpace(H),rJ.setContext(Z),rJ.start(),$.isPresenting=!0,$.dispatchEvent({type:"sessionstart"})}},this.getEnvironmentBlendMode=function(){if(Z!==null)return Z.environmentBlendMode},this.getDepthTexture=function(){return F.getDepthTexture()};function l(s){for(let qJ=0;qJ<s.removed.length;qJ++){let XJ=s.removed[qJ],LJ=A.indexOf(XJ);if(LJ>=0)A[LJ]=null,L[LJ].disconnect(XJ)}for(let qJ=0;qJ<s.added.length;qJ++){let XJ=s.added[qJ],LJ=A.indexOf(XJ);if(LJ===-1){for(let xJ=0;xJ<L.length;xJ++)if(xJ>=A.length){A.push(XJ),LJ=xJ;break}else if(A[xJ]===null){A[xJ]=XJ,LJ=xJ;break}if(LJ===-1)break}let yJ=L[LJ];if(yJ)yJ.connect(XJ)}}let QJ=new w,m=new w;function EJ(s,qJ,XJ){QJ.setFromMatrixPosition(qJ.matrixWorld),m.setFromMatrixPosition(XJ.matrixWorld);let LJ=QJ.distanceTo(m),yJ=qJ.projectionMatrix.elements,xJ=XJ.projectionMatrix.elements,W0=yJ[14]/(yJ[10]-1),T=yJ[14]/(yJ[10]+1),e=(yJ[9]+1)/yJ[5],a=(yJ[9]-1)/yJ[5],i=(yJ[8]-1)/yJ[0],n=(xJ[8]+1)/xJ[0],UJ=W0*i,HJ=W0*n,ZJ=LJ/(-i+n),lJ=ZJ*-i;if(qJ.matrixWorld.decompose(s.position,s.quaternion,s.scale),s.translateX(lJ),s.translateZ(ZJ),s.matrixWorld.compose(s.position,s.quaternion,s.scale),s.matrixWorldInverse.copy(s.matrixWorld).invert(),yJ[10]===-1)s.projectionMatrix.copy(qJ.projectionMatrix),s.projectionMatrixInverse.copy(qJ.projectionMatrixInverse);else{let uJ=W0+ZJ,sJ=T+ZJ,P=UJ-lJ,V=HJ+(LJ-lJ),v=e*T/sJ*uJ,c=a*T/sJ*uJ;s.projectionMatrix.makePerspective(P,V,v,c,uJ,sJ),s.projectionMatrixInverse.copy(s.projectionMatrix).invert()}}function NJ(s,qJ){if(qJ===null)s.matrixWorld.copy(s.matrix);else s.matrixWorld.multiplyMatrices(qJ.matrixWorld,s.matrix);s.matrixWorldInverse.copy(s.matrixWorld).invert()}this.updateCamera=function(s){if(Z===null)return;let{near:qJ,far:XJ}=s;if(F.texture!==null){if(F.depthNear>0)qJ=F.depthNear;if(F.depthFar>0)XJ=F.depthFar}if(S.near=z.near=y.near=qJ,S.far=z.far=y.far=XJ,p!==S.near||d!==S.far)Z.updateRenderState({depthNear:S.near,depthFar:S.far}),p=S.near,d=S.far;S.layers.mask=s.layers.mask|6,y.layers.mask=S.layers.mask&3,z.layers.mask=S.layers.mask&5;let LJ=s.parent,yJ=S.cameras;NJ(S,LJ);for(let xJ=0;xJ<yJ.length;xJ++)NJ(yJ[xJ],LJ);if(yJ.length===2)EJ(S,y,z);else S.projectionMatrix.copy(y.projectionMatrix);SJ(s,S,LJ)};function SJ(s,qJ,XJ){if(XJ===null)s.matrix.copy(qJ.matrixWorld);else s.matrix.copy(XJ.matrixWorld),s.matrix.invert(),s.matrix.multiply(qJ.matrixWorld);if(s.matrix.decompose(s.position,s.quaternion,s.scale),s.updateMatrixWorld(!0),s.projectionMatrix.copy(qJ.projectionMatrix),s.projectionMatrixInverse.copy(qJ.projectionMatrixInverse),s.isPerspectiveCamera)s.fov=G9*2*Math.atan(1/s.projectionMatrix.elements[5]),s.zoom=1}this.getCamera=function(){return S},this.getFoveation=function(){if(E===null&&N===null)return;return Y},this.setFoveation=function(s){if(Y=s,E!==null)E.fixedFoveation=s;if(N!==null&&N.fixedFoveation!==void 0)N.fixedFoveation=s},this.hasDepthSensing=function(){return F.texture!==null},this.getDepthSensingMesh=function(){return F.getMesh(S)},this.getCameraTexture=function(s){return O[s]};let mJ=null;function U0(s,qJ){if(U=qJ.getViewerPose(X||K),q=qJ,U!==null){let XJ=U.views;if(N!==null)J.setRenderTargetFramebuffer(M,N.framebuffer),J.setRenderTarget(M);let LJ=!1;if(XJ.length!==S.cameras.length)S.cameras.length=0,LJ=!0;for(let T=0;T<XJ.length;T++){let e=XJ[T],a=null;if(N!==null)a=N.getViewport(e);else{let n=G.getViewSubImage(E,e);if(a=n.viewport,T===0)J.setRenderTargetTextures(M,n.colorTexture,n.depthStencilTexture),J.setRenderTarget(M)}let i=I[T];if(i===void 0)i=new I0,i.layers.enable(T),i.viewport=new J0,I[T]=i;if(i.matrix.fromArray(e.transform.matrix),i.matrix.decompose(i.position,i.quaternion,i.scale),i.projectionMatrix.fromArray(e.projectionMatrix),i.projectionMatrixInverse.copy(i.projectionMatrix).invert(),i.viewport.set(a.x,a.y,a.width,a.height),T===0)S.matrix.copy(i.matrix),S.matrix.decompose(S.position,S.quaternion,S.scale);if(LJ===!0)S.cameras.push(i)}let yJ=Z.enabledFeatures;if(yJ&&yJ.includes("depth-sensing")&&Z.depthUsage=="gpu-optimized"&&R){G=$.getBinding();let T=G.getDepthInformation(XJ[0]);if(T&&T.isValid&&T.texture)F.init(T,Z.renderState)}if(yJ&&yJ.includes("camera-access")&&R){J.state.unbindTexture(),G=$.getBinding();for(let T=0;T<XJ.length;T++){let e=XJ[T].camera;if(e){let a=O[e];if(!a)a=new wQ,O[e]=a;let i=G.getCameraImage(e);a.sourceTexture=i}}}}for(let XJ=0;XJ<L.length;XJ++){let LJ=A[XJ],yJ=L[XJ];if(LJ!==null&&yJ!==void 0)yJ.update(LJ,qJ,X||K)}if(mJ)mJ(s,qJ);if(qJ.detectedPlanes)$.dispatchEvent({type:"planesdetected",data:qJ});q=null}let rJ=new eX;rJ.setAnimationLoop(U0),this.setAnimationLoop=function(s){mJ=s},this.dispose=function(){}}}var z9=new s0,p5=new hJ;function m5(J,Q){function $(O,D){if(O.matrixAutoUpdate===!0)O.updateMatrix();D.value.copy(O.matrix)}function Z(O,D){if(D.color.getRGB(O.fogColor.value,mZ(J)),D.isFog)O.fogNear.value=D.near,O.fogFar.value=D.far;else if(D.isFogExp2)O.fogDensity.value=D.density}function W(O,D,k,M,L){if(D.isMeshBasicMaterial)K(O,D);else if(D.isMeshLambertMaterial)K(O,D);else if(D.isMeshToonMaterial)K(O,D),E(O,D);else if(D.isMeshPhongMaterial)K(O,D),G(O,D);else if(D.isMeshStandardMaterial){if(K(O,D),N(O,D),D.isMeshPhysicalMaterial)q(O,D,L)}else if(D.isMeshMatcapMaterial)K(O,D),R(O,D);else if(D.isMeshDepthMaterial)K(O,D);else if(D.isMeshDistanceMaterial)K(O,D),F(O,D);else if(D.isMeshNormalMaterial)K(O,D);else if(D.isLineBasicMaterial){if(H(O,D),D.isLineDashedMaterial)Y(O,D)}else if(D.isPointsMaterial)X(O,D,k,M);else if(D.isSpriteMaterial)U(O,D);else if(D.isShadowMaterial)O.color.value.copy(D.color),O.opacity.value=D.opacity;else if(D.isShaderMaterial)D.uniformsNeedUpdate=!1}function K(O,D){if(O.opacity.value=D.opacity,D.color)O.diffuse.value.copy(D.color);if(D.emissive)O.emissive.value.copy(D.emissive).multiplyScalar(D.emissiveIntensity);if(D.map)O.map.value=D.map,$(D.map,O.mapTransform);if(D.alphaMap)O.alphaMap.value=D.alphaMap,$(D.alphaMap,O.alphaMapTransform);if(D.bumpMap){if(O.bumpMap.value=D.bumpMap,$(D.bumpMap,O.bumpMapTransform),O.bumpScale.value=D.bumpScale,D.side===i0)O.bumpScale.value*=-1}if(D.normalMap){if(O.normalMap.value=D.normalMap,$(D.normalMap,O.normalMapTransform),O.normalScale.value.copy(D.normalScale),D.side===i0)O.normalScale.value.negate()}if(D.displacementMap)O.displacementMap.value=D.displacementMap,$(D.displacementMap,O.displacementMapTransform),O.displacementScale.value=D.displacementScale,O.displacementBias.value=D.displacementBias;if(D.emissiveMap)O.emissiveMap.value=D.emissiveMap,$(D.emissiveMap,O.emissiveMapTransform);if(D.specularMap)O.specularMap.value=D.specularMap,$(D.specularMap,O.specularMapTransform);if(D.alphaTest>0)O.alphaTest.value=D.alphaTest;let k=Q.get(D),M=k.envMap,L=k.envMapRotation;if(M){if(O.envMap.value=M,z9.copy(L),z9.x*=-1,z9.y*=-1,z9.z*=-1,M.isCubeTexture&&M.isRenderTargetTexture===!1)z9.y*=-1,z9.z*=-1;O.envMapRotation.value.setFromMatrix4(p5.makeRotationFromEuler(z9)),O.flipEnvMap.value=M.isCubeTexture&&M.isRenderTargetTexture===!1?-1:1,O.reflectivity.value=D.reflectivity,O.ior.value=D.ior,O.refractionRatio.value=D.refractionRatio}if(D.lightMap)O.lightMap.value=D.lightMap,O.lightMapIntensity.value=D.lightMapIntensity,$(D.lightMap,O.lightMapTransform);if(D.aoMap)O.aoMap.value=D.aoMap,O.aoMapIntensity.value=D.aoMapIntensity,$(D.aoMap,O.aoMapTransform)}function H(O,D){if(O.diffuse.value.copy(D.color),O.opacity.value=D.opacity,D.map)O.map.value=D.map,$(D.map,O.mapTransform)}function Y(O,D){O.dashSize.value=D.dashSize,O.totalSize.value=D.dashSize+D.gapSize,O.scale.value=D.scale}function X(O,D,k,M){if(O.diffuse.value.copy(D.color),O.opacity.value=D.opacity,O.size.value=D.size*k,O.scale.value=M*0.5,D.map)O.map.value=D.map,$(D.map,O.uvTransform);if(D.alphaMap)O.alphaMap.value=D.alphaMap,$(D.alphaMap,O.alphaMapTransform);if(D.alphaTest>0)O.alphaTest.value=D.alphaTest}function U(O,D){if(O.diffuse.value.copy(D.color),O.opacity.value=D.opacity,O.rotation.value=D.rotation,D.map)O.map.value=D.map,$(D.map,O.mapTransform);if(D.alphaMap)O.alphaMap.value=D.alphaMap,$(D.alphaMap,O.alphaMapTransform);if(D.alphaTest>0)O.alphaTest.value=D.alphaTest}function G(O,D){O.specular.value.copy(D.specular),O.shininess.value=Math.max(D.shininess,0.0001)}function E(O,D){if(D.gradientMap)O.gradientMap.value=D.gradientMap}function N(O,D){if(O.metalness.value=D.metalness,D.metalnessMap)O.metalnessMap.value=D.metalnessMap,$(D.metalnessMap,O.metalnessMapTransform);if(O.roughness.value=D.roughness,D.roughnessMap)O.roughnessMap.value=D.roughnessMap,$(D.roughnessMap,O.roughnessMapTransform);if(D.envMap)O.envMapIntensity.value=D.envMapIntensity}function q(O,D,k){if(O.ior.value=D.ior,D.sheen>0){if(O.sheenColor.value.copy(D.sheenColor).multiplyScalar(D.sheen),O.sheenRoughness.value=D.sheenRoughness,D.sheenColorMap)O.sheenColorMap.value=D.sheenColorMap,$(D.sheenColorMap,O.sheenColorMapTransform);if(D.sheenRoughnessMap)O.sheenRoughnessMap.value=D.sheenRoughnessMap,$(D.sheenRoughnessMap,O.sheenRoughnessMapTransform)}if(D.clearcoat>0){if(O.clearcoat.value=D.clearcoat,O.clearcoatRoughness.value=D.clearcoatRoughness,D.clearcoatMap)O.clearcoatMap.value=D.clearcoatMap,$(D.clearcoatMap,O.clearcoatMapTransform);if(D.clearcoatRoughnessMap)O.clearcoatRoughnessMap.value=D.clearcoatRoughnessMap,$(D.clearcoatRoughnessMap,O.clearcoatRoughnessMapTransform);if(D.clearcoatNormalMap){if(O.clearcoatNormalMap.value=D.clearcoatNormalMap,$(D.clearcoatNormalMap,O.clearcoatNormalMapTransform),O.clearcoatNormalScale.value.copy(D.clearcoatNormalScale),D.side===i0)O.clearcoatNormalScale.value.negate()}}if(D.dispersion>0)O.dispersion.value=D.dispersion;if(D.iridescence>0){if(O.iridescence.value=D.iridescence,O.iridescenceIOR.value=D.iridescenceIOR,O.iridescenceThicknessMinimum.value=D.iridescenceThicknessRange[0],O.iridescenceThicknessMaximum.value=D.iridescenceThicknessRange[1],D.iridescenceMap)O.iridescenceMap.value=D.iridescenceMap,$(D.iridescenceMap,O.iridescenceMapTransform);if(D.iridescenceThicknessMap)O.iridescenceThicknessMap.value=D.iridescenceThicknessMap,$(D.iridescenceThicknessMap,O.iridescenceThicknessMapTransform)}if(D.transmission>0){if(O.transmission.value=D.transmission,O.transmissionSamplerMap.value=k.texture,O.transmissionSamplerSize.value.set(k.width,k.height),D.transmissionMap)O.transmissionMap.value=D.transmissionMap,$(D.transmissionMap,O.transmissionMapTransform);if(O.thickness.value=D.thickness,D.thicknessMap)O.thicknessMap.value=D.thicknessMap,$(D.thicknessMap,O.thicknessMapTransform);O.attenuationDistance.value=D.attenuationDistance,O.attenuationColor.value.copy(D.attenuationColor)}if(D.anisotropy>0){if(O.anisotropyVector.value.set(D.anisotropy*Math.cos(D.anisotropyRotation),D.anisotropy*Math.sin(D.anisotropyRotation)),D.anisotropyMap)O.anisotropyMap.value=D.anisotropyMap,$(D.anisotropyMap,O.anisotropyMapTransform)}if(O.specularIntensity.value=D.specularIntensity,O.specularColor.value.copy(D.specularColor),D.specularColorMap)O.specularColorMap.value=D.specularColorMap,$(D.specularColorMap,O.specularColorMapTransform);if(D.specularIntensityMap)O.specularIntensityMap.value=D.specularIntensityMap,$(D.specularIntensityMap,O.specularIntensityMapTransform)}function R(O,D){if(D.matcap)O.matcap.value=D.matcap}function F(O,D){let k=Q.get(D).light;O.referencePosition.value.setFromMatrixPosition(k.matrixWorld),O.nearDistance.value=k.shadow.camera.near,O.farDistance.value=k.shadow.camera.far}return{refreshFogUniforms:Z,refreshMaterialUniforms:W}}function d5(J,Q,$,Z){let W={},K={},H=[],Y=J.getParameter(J.MAX_UNIFORM_BUFFER_BINDINGS);function X(k,M){let L=M.program;Z.uniformBlockBinding(k,L)}function U(k,M){let L=W[k.id];if(L===void 0)R(k),L=G(k),W[k.id]=L,k.addEventListener("dispose",O);let A=M.program;Z.updateUBOMapping(k,A);let _=Q.render.frame;if(K[k.id]!==_)N(k),K[k.id]=_}function G(k){let M=E();k.__bindingPointIndex=M;let L=J.createBuffer(),A=k.__size,_=k.usage;return J.bindBuffer(J.UNIFORM_BUFFER,L),J.bufferData(J.UNIFORM_BUFFER,A,_),J.bindBuffer(J.UNIFORM_BUFFER,null),J.bindBufferBase(J.UNIFORM_BUFFER,M,L),L}function E(){for(let k=0;k<Y;k++)if(H.indexOf(k)===-1)return H.push(k),k;return console.error("THREE.WebGLRenderer: Maximum number of simultaneously usable uniforms groups reached."),0}function N(k){let M=W[k.id],L=k.uniforms,A=k.__cache;J.bindBuffer(J.UNIFORM_BUFFER,M);for(let _=0,C=L.length;_<C;_++){let y=Array.isArray(L[_])?L[_]:[L[_]];for(let z=0,I=y.length;z<I;z++){let S=y[z];if(q(S,_,z,A)===!0){let p=S.__offset,d=Array.isArray(S.value)?S.value:[S.value],x=0;for(let o=0;o<d.length;o++){let l=d[o],QJ=F(l);if(typeof l==="number"||typeof l==="boolean")S.__data[0]=l,J.bufferSubData(J.UNIFORM_BUFFER,p+x,S.__data);else if(l.isMatrix3)S.__data[0]=l.elements[0],S.__data[1]=l.elements[1],S.__data[2]=l.elements[2],S.__data[3]=0,S.__data[4]=l.elements[3],S.__data[5]=l.elements[4],S.__data[6]=l.elements[5],S.__data[7]=0,S.__data[8]=l.elements[6],S.__data[9]=l.elements[7],S.__data[10]=l.elements[8],S.__data[11]=0;else l.toArray(S.__data,x),x+=QJ.storage/Float32Array.BYTES_PER_ELEMENT}J.bufferSubData(J.UNIFORM_BUFFER,p,S.__data)}}}J.bindBuffer(J.UNIFORM_BUFFER,null)}function q(k,M,L,A){let _=k.value,C=M+"_"+L;if(A[C]===void 0){if(typeof _==="number"||typeof _==="boolean")A[C]=_;else A[C]=_.clone();return!0}else{let y=A[C];if(typeof _==="number"||typeof _==="boolean"){if(y!==_)return A[C]=_,!0}else if(y.equals(_)===!1)return y.copy(_),!0}return!1}function R(k){let M=k.uniforms,L=0,A=16;for(let C=0,y=M.length;C<y;C++){let z=Array.isArray(M[C])?M[C]:[M[C]];for(let I=0,S=z.length;I<S;I++){let p=z[I],d=Array.isArray(p.value)?p.value:[p.value];for(let x=0,o=d.length;x<o;x++){let l=d[x],QJ=F(l),m=L%A,EJ=m%QJ.boundary,NJ=m+EJ;if(L+=EJ,NJ!==0&&A-NJ<QJ.storage)L+=A-NJ;p.__data=new Float32Array(QJ.storage/Float32Array.BYTES_PER_ELEMENT),p.__offset=L,L+=QJ.storage}}}let _=L%A;if(_>0)L+=A-_;return k.__size=L,k.__cache={},this}function F(k){let M={boundary:0,storage:0};if(typeof k==="number"||typeof k==="boolean")M.boundary=4,M.storage=4;else if(k.isVector2)M.boundary=8,M.storage=8;else if(k.isVector3||k.isColor)M.boundary=16,M.storage=12;else if(k.isVector4)M.boundary=16,M.storage=16;else if(k.isMatrix3)M.boundary=48,M.storage=48;else if(k.isMatrix4)M.boundary=64,M.storage=64;else if(k.isTexture)console.warn("THREE.WebGLRenderer: Texture samplers can not be part of an uniforms group.");else console.warn("THREE.WebGLRenderer: Unsupported uniform value type.",k);return M}function O(k){let M=k.target;M.removeEventListener("dispose",O);let L=H.indexOf(M.__bindingPointIndex);H.splice(L,1),J.deleteBuffer(W[M.id]),delete W[M.id],delete K[M.id]}function D(){for(let k in W)J.deleteBuffer(W[k]);H=[],W={},K={}}return{bind:X,update:U,dispose:D}}class l5{constructor(J={}){let{canvas:Q=UY(),context:$=null,depth:Z=!0,stencil:W=!1,alpha:K=!1,antialias:H=!1,premultipliedAlpha:Y=!0,preserveDrawingBuffer:X=!1,powerPreference:U="default",failIfMajorPerformanceCaveat:G=!1,reversedDepthBuffer:E=!1}=J;this.isWebGLRenderer=!0;let N;if($!==null){if(typeof WebGLRenderingContext<"u"&&$ instanceof WebGLRenderingContext)throw Error("THREE.WebGLRenderer: WebGL 1 is not supported since r163.");N=$.getContextAttributes().alpha}else N=K;let q=new Uint32Array(4),R=new Int32Array(4),F=null,O=null,D=[],k=[];this.domElement=Q,this.debug={checkShaderErrors:!0,onShaderError:null},this.autoClear=!0,this.autoClearColor=!0,this.autoClearDepth=!0,this.autoClearStencil=!0,this.sortObjects=!0,this.clippingPlanes=[],this.localClippingEnabled=!1,this.toneMapping=T8,this.toneMappingExposure=1,this.transmissionResolutionScale=1;let M=this,L=!1;this._outputColorSpace=QY;let A=0,_=0,C=null,y=-1,z=null,I=new J0,S=new J0,p=null,d=new kJ(0),x=0,o=Q.width,l=Q.height,QJ=1,m=null,EJ=null,NJ=new J0(0,0,o,l),SJ=new J0(0,0,o,l),mJ=!1,U0=new V9,rJ=!1,s=!1,qJ=new hJ,XJ=new w,LJ=new J0,yJ={background:null,fog:null,environment:null,overrideMaterial:null,isScene:!0},xJ=!1;function W0(){return C===null?QJ:1}let T=$;function e(B,f){return Q.getContext(B,f)}try{let B={alpha:!0,depth:Z,stencil:W,antialias:H,premultipliedAlpha:Y,preserveDrawingBuffer:X,powerPreference:U,failIfMajorPerformanceCaveat:G};if("setAttribute"in Q)Q.setAttribute("data-engine",`three.js r${HH}`);if(Q.addEventListener("webglcontextlost",OJ,!1),Q.addEventListener("webglcontextrestored",GJ,!1),Q.addEventListener("webglcontextcreationerror",IJ,!1),T===null){if(T=e("webgl2",B),T===null)if(e("webgl2"))throw Error("Error creating WebGL context with your selected attributes.");else throw Error("Error creating WebGL context.")}}catch(B){throw console.error("THREE.WebGLRenderer: "+B.message),B}let a,i,n,UJ,HJ,ZJ,lJ,uJ,sJ,P,V,v,c,JJ,u,VJ,YJ,_J,vJ,KJ,FJ,PJ,AJ,MJ;function oJ(){if(a=new HD(T),a.init(),PJ=new h5(T,a),i=new eq(T,a,J,PJ),n=new f5(T,a),i.reversedDepthBuffer&&E)n.buffers.depth.setReversed(!0);UJ=new UD(T),HJ=new z5,ZJ=new b5(T,a,n,HJ,i,PJ,UJ),lJ=new QD(M),uJ=new KD(M),sJ=new ON(T),AJ=new rq(T,sJ),P=new YD(T,sJ,UJ,AJ),V=new ED(T,P,sJ,UJ),vJ=new GD(T,i,ZJ),VJ=new JD(HJ),v=new L5(M,lJ,uJ,a,i,AJ,VJ),c=new m5(M,HJ),JJ=new I5,u=new T5(a),_J=new aq(M,lJ,uJ,n,V,N,Y),YJ=new y5(M,V,i),MJ=new d5(T,UJ,i,n),KJ=new tq(T,a,UJ),FJ=new XD(T,a,UJ),UJ.programs=v.programs,M.capabilities=i,M.extensions=a,M.properties=HJ,M.renderLists=JJ,M.shadowMap=YJ,M.state=n,M.info=UJ}oJ();let j=new GU(M,T);this.xr=j,this.getContext=function(){return T},this.getContextAttributes=function(){return T.getContextAttributes()},this.forceContextLoss=function(){let B=a.get("WEBGL_lose_context");if(B)B.loseContext()},this.forceContextRestore=function(){let B=a.get("WEBGL_lose_context");if(B)B.restoreContext()},this.getPixelRatio=function(){return QJ},this.setPixelRatio=function(B){if(B===void 0)return;QJ=B,this.setSize(o,l,!1)},this.getSize=function(B){return B.set(o,l)},this.setSize=function(B,f,h=!0){if(j.isPresenting){console.warn("THREE.WebGLRenderer: Can't change size while VR device is presenting.");return}if(o=B,l=f,Q.width=Math.floor(B*QJ),Q.height=Math.floor(f*QJ),h===!0)Q.style.width=B+"px",Q.style.height=f+"px";this.setViewport(0,0,B,f)},this.getDrawingBufferSize=function(B){return B.set(o*QJ,l*QJ).floor()},this.setDrawingBufferSize=function(B,f,h){o=B,l=f,QJ=h,Q.width=Math.floor(B*h),Q.height=Math.floor(f*h),this.setViewport(0,0,B,f)},this.getCurrentViewport=function(B){return B.copy(I)},this.getViewport=function(B){return B.copy(NJ)},this.setViewport=function(B,f,h,g){if(B.isVector4)NJ.set(B.x,B.y,B.z,B.w);else NJ.set(B,f,h,g);n.viewport(I.copy(NJ).multiplyScalar(QJ).round())},this.getScissor=function(B){return B.copy(SJ)},this.setScissor=function(B,f,h,g){if(B.isVector4)SJ.set(B.x,B.y,B.z,B.w);else SJ.set(B,f,h,g);n.scissor(S.copy(SJ).multiplyScalar(QJ).round())},this.getScissorTest=function(){return mJ},this.setScissorTest=function(B){n.setScissorTest(mJ=B)},this.setOpaqueSort=function(B){m=B},this.setTransparentSort=function(B){EJ=B},this.getClearColor=function(B){return B.copy(_J.getClearColor())},this.setClearColor=function(){_J.setClearColor(...arguments)},this.getClearAlpha=function(){return _J.getClearAlpha()},this.setClearAlpha=function(){_J.setClearAlpha(...arguments)},this.clear=function(B=!0,f=!0,h=!0){let g=0;if(B){let b=!1;if(C!==null){let WJ=C.texture.format;b=WJ===KZ||WJ===WZ||WJ===ZZ}if(b){let WJ=C.texture.type,RJ=WJ===d8||WJ===H6||WJ===m6||WJ===Y6||WJ===QZ||WJ===$Z,wJ=_J.getClearColor(),zJ=_J.getClearAlpha(),fJ=wJ.r,gJ=wJ.g,TJ=wJ.b;if(RJ)q[0]=fJ,q[1]=gJ,q[2]=TJ,q[3]=zJ,T.clearBufferuiv(T.COLOR,0,q);else R[0]=fJ,R[1]=gJ,R[2]=TJ,R[3]=zJ,T.clearBufferiv(T.COLOR,0,R)}else g|=T.COLOR_BUFFER_BIT}if(f)g|=T.DEPTH_BUFFER_BIT;if(h)g|=T.STENCIL_BUFFER_BIT,this.state.buffers.stencil.setMask(4294967295);T.clear(g)},this.clearColor=function(){this.clear(!0,!1,!1)},this.clearDepth=function(){this.clear(!1,!0,!1)},this.clearStencil=function(){this.clear(!1,!1,!0)},this.dispose=function(){Q.removeEventListener("webglcontextlost",OJ,!1),Q.removeEventListener("webglcontextrestored",GJ,!1),Q.removeEventListener("webglcontextcreationerror",IJ,!1),_J.dispose(),JJ.dispose(),u.dispose(),HJ.dispose(),lJ.dispose(),uJ.dispose(),V.dispose(),AJ.dispose(),MJ.dispose(),v.dispose(),j.dispose(),j.removeEventListener("sessionstart",U8),j.removeEventListener("sessionend",G8),s8.stop()};function OJ(B){B.preventDefault(),console.log("THREE.WebGLRenderer: Context Lost."),L=!0}function GJ(){console.log("THREE.WebGLRenderer: Context Restored."),L=!1;let B=UJ.autoReset,f=YJ.enabled,h=YJ.autoUpdate,g=YJ.needsUpdate,b=YJ.type;oJ(),UJ.autoReset=B,YJ.enabled=f,YJ.autoUpdate=h,YJ.needsUpdate=g,YJ.type=b}function IJ(B){console.error("THREE.WebGLRenderer: A WebGL context could not be created. Reason: ",B.statusMessage)}function $J(B){let f=B.target;f.removeEventListener("dispose",$J),r(f)}function r(B){CJ(B),HJ.remove(B)}function CJ(B){let f=HJ.get(B).programs;if(f!==void 0){if(f.forEach(function(h){v.releaseProgram(h)}),B.isShaderMaterial)v.releaseShaderCache(B)}}this.renderBufferDirect=function(B,f,h,g,b,WJ){if(f===null)f=yJ;let RJ=b.isMesh&&b.matrixWorld.determinant()<0,wJ=EU(B,f,h,g,b);n.setMaterial(g,RJ);let zJ=h.index,fJ=1;if(g.wireframe===!0){if(zJ=P.getWireframeAttribute(h),zJ===void 0)return;fJ=2}let gJ=h.drawRange,TJ=h.attributes.position,aJ=gJ.start*fJ,H0=(gJ.start+gJ.count)*fJ;if(WJ!==null)aJ=Math.max(aJ,WJ.start*fJ),H0=Math.min(H0,(WJ.start+WJ.count)*fJ);if(zJ!==null)aJ=Math.max(aJ,0),H0=Math.min(H0,zJ.count);else if(TJ!==void 0&&TJ!==null)aJ=Math.max(aJ,0),H0=Math.min(H0,TJ.count);let O0=H0-aJ;if(O0<0||O0===1/0)return;AJ.setup(b,g,wJ,h,zJ);let E0,X0=KJ;if(zJ!==null)E0=sJ.get(zJ),X0=FJ,X0.setIndex(E0);if(b.isMesh)if(g.wireframe===!0)n.setLineWidth(g.wireframeLinewidth*W0()),X0.setMode(T.LINES);else X0.setMode(T.TRIANGLES);else if(b.isLine){let jJ=g.linewidth;if(jJ===void 0)jJ=1;if(n.setLineWidth(jJ*W0()),b.isLineSegments)X0.setMode(T.LINES);else if(b.isLineLoop)X0.setMode(T.LINE_LOOP);else X0.setMode(T.LINE_STRIP)}else if(b.isPoints)X0.setMode(T.POINTS);else if(b.isSprite)X0.setMode(T.TRIANGLES);if(b.isBatchedMesh)if(b._multiDrawInstances!==null)o9("THREE.WebGLRenderer: renderMultiDrawInstances has been deprecated and will be removed in r184. Append to renderMultiDraw arguments and use indirection."),X0.renderMultiDrawInstances(b._multiDrawStarts,b._multiDrawCounts,b._multiDrawCount,b._multiDrawInstances);else if(!a.get("WEBGL_multi_draw")){let{_multiDrawStarts:jJ,_multiDrawCounts:N0,_multiDrawCount:$0}=b,d0=zJ?sJ.get(zJ).bytesPerElement:1,_9=HJ.get(g).currentProgram.getUniforms();for(let l0=0;l0<$0;l0++)_9.setValue(T,"_gl_DrawID",l0),X0.render(jJ[l0]/d0,N0[l0])}else X0.renderMultiDraw(b._multiDrawStarts,b._multiDrawCounts,b._multiDrawCount);else if(b.isInstancedMesh)X0.renderInstances(aJ,O0,b.count);else if(h.isInstancedBufferGeometry){let jJ=h._maxInstanceCount!==void 0?h._maxInstanceCount:1/0,N0=Math.min(h.instanceCount,jJ);X0.renderInstances(aJ,O0,N0)}else X0.render(aJ,O0)};function pJ(B,f,h){if(B.transparent===!0&&B.side===R8&&B.forceSinglePass===!1)B.side=i0,B.needsUpdate=!0,Y7(B,f,h),B.side=Q6,B.needsUpdate=!0,Y7(B,f,h),B.side=R8;else Y7(B,f,h)}this.compile=function(B,f,h=null){if(h===null)h=B;if(O=u.get(h),O.init(f),k.push(O),h.traverseVisible(function(b){if(b.isLight&&b.layers.test(f.layers)){if(O.pushLight(b),b.castShadow)O.pushShadow(b)}}),B!==h)B.traverseVisible(function(b){if(b.isLight&&b.layers.test(f.layers)){if(O.pushLight(b),b.castShadow)O.pushShadow(b)}});O.setupLights();let g=new Set;return B.traverse(function(b){if(!(b.isMesh||b.isPoints||b.isLine||b.isSprite))return;let WJ=b.material;if(WJ)if(Array.isArray(WJ))for(let RJ=0;RJ<WJ.length;RJ++){let wJ=WJ[RJ];pJ(wJ,h,b),g.add(wJ)}else pJ(WJ,h,b),g.add(WJ)}),O=k.pop(),g},this.compileAsync=function(B,f,h=null){let g=this.compile(B,f,h);return new Promise((b)=>{function WJ(){if(g.forEach(function(RJ){if(HJ.get(RJ).currentProgram.isReady())g.delete(RJ)}),g.size===0){b(B);return}setTimeout(WJ,10)}if(a.get("KHR_parallel_shader_compile")!==null)WJ();else setTimeout(WJ,10)})};let Y0=null;function K0(B){if(Y0)Y0(B)}function U8(){s8.stop()}function G8(){s8.start()}let s8=new eX;if(s8.setAnimationLoop(K0),typeof self<"u")s8.setContext(self);this.setAnimationLoop=function(B){Y0=B,j.setAnimationLoop(B),B===null?s8.stop():s8.start()},j.addEventListener("sessionstart",U8),j.addEventListener("sessionend",G8),this.render=function(B,f){if(f!==void 0&&f.isCamera!==!0){console.error("THREE.WebGLRenderer.render: camera is not an instance of THREE.Camera.");return}if(L===!0)return;if(B.matrixWorldAutoUpdate===!0)B.updateMatrixWorld();if(f.parent===null&&f.matrixWorldAutoUpdate===!0)f.updateMatrixWorld();if(j.enabled===!0&&j.isPresenting===!0){if(j.cameraAutoUpdate===!0)j.updateCamera(f);f=j.getCamera()}if(B.isScene===!0)B.onBeforeRender(M,B,f,C);if(O=u.get(B,k.length),O.init(f),k.push(O),qJ.multiplyMatrices(f.projectionMatrix,f.matrixWorldInverse),U0.setFromProjectionMatrix(qJ,hZ,f.reversedDepth),s=this.localClippingEnabled,rJ=VJ.init(this.clippingPlanes,s),F=JJ.get(B,D.length),F.init(),D.push(F),j.enabled===!0&&j.isPresenting===!0){let WJ=M.xr.getDepthSensingMesh();if(WJ!==null)W$(WJ,f,-1/0,M.sortObjects)}if(W$(B,f,0,M.sortObjects),F.finish(),M.sortObjects===!0)F.sort(m,EJ);if(xJ=j.enabled===!1||j.isPresenting===!1||j.hasDepthSensing()===!1,xJ)_J.addToRenderList(F,B);if(this.info.render.frame++,rJ===!0)VJ.beginShadows();let h=O.state.shadowsArray;if(YJ.render(h,B,f),rJ===!0)VJ.endShadows();if(this.info.autoReset===!0)this.info.reset();let{opaque:g,transmissive:b}=F;if(O.setupLights(),f.isArrayCamera){let WJ=f.cameras;if(b.length>0)for(let RJ=0,wJ=WJ.length;RJ<wJ;RJ++){let zJ=WJ[RJ];oW(g,b,B,zJ)}if(xJ)_J.render(B);for(let RJ=0,wJ=WJ.length;RJ<wJ;RJ++){let zJ=WJ[RJ];iW(F,B,zJ,zJ.viewport)}}else{if(b.length>0)oW(g,b,B,f);if(xJ)_J.render(B);iW(F,B,f)}if(C!==null&&_===0)ZJ.updateMultisampleRenderTarget(C),ZJ.updateRenderTargetMipmap(C);if(B.isScene===!0)B.onAfterRender(M,B,f);if(AJ.resetDefaultState(),y=-1,z=null,k.pop(),k.length>0){if(O=k[k.length-1],rJ===!0)VJ.setGlobalState(M.clippingPlanes,O.state.camera)}else O=null;if(D.pop(),D.length>0)F=D[D.length-1];else F=null};function W$(B,f,h,g){if(B.visible===!1)return;if(B.layers.test(f.layers)){if(B.isGroup)h=B.renderOrder;else if(B.isLOD){if(B.autoUpdate===!0)B.update(f)}else if(B.isLight){if(O.pushLight(B),B.castShadow)O.pushShadow(B)}else if(B.isSprite){if(!B.frustumCulled||U0.intersectsSprite(B)){if(g)LJ.setFromMatrixPosition(B.matrixWorld).applyMatrix4(qJ);let RJ=V.update(B),wJ=B.material;if(wJ.visible)F.push(B,RJ,wJ,h,LJ.z,null)}}else if(B.isMesh||B.isLine||B.isPoints){if(!B.frustumCulled||U0.intersectsObject(B)){let RJ=V.update(B),wJ=B.material;if(g){if(B.boundingSphere!==void 0){if(B.boundingSphere===null)B.computeBoundingSphere();LJ.copy(B.boundingSphere.center)}else{if(RJ.boundingSphere===null)RJ.computeBoundingSphere();LJ.copy(RJ.boundingSphere.center)}LJ.applyMatrix4(B.matrixWorld).applyMatrix4(qJ)}if(Array.isArray(wJ)){let zJ=RJ.groups;for(let fJ=0,gJ=zJ.length;fJ<gJ;fJ++){let TJ=zJ[fJ],aJ=wJ[TJ.materialIndex];if(aJ&&aJ.visible)F.push(B,RJ,aJ,h,LJ.z,TJ)}}else if(wJ.visible)F.push(B,RJ,wJ,h,LJ.z,null)}}}let WJ=B.children;for(let RJ=0,wJ=WJ.length;RJ<wJ;RJ++)W$(WJ[RJ],f,h,g)}function iW(B,f,h,g){let{opaque:b,transmissive:WJ,transparent:RJ}=B;if(O.setupLightsView(h),rJ===!0)VJ.setGlobalState(M.clippingPlanes,h);if(g)n.viewport(I.copy(g));if(b.length>0)H7(b,f,h);if(WJ.length>0)H7(WJ,f,h);if(RJ.length>0)H7(RJ,f,h);n.buffers.depth.setTest(!0),n.buffers.depth.setMask(!0),n.buffers.color.setMask(!0),n.setPolygonOffset(!1)}function oW(B,f,h,g){if((h.isScene===!0?h.overrideMaterial:null)!==null)return;if(O.state.transmissionRenderTarget[g.id]===void 0)O.state.transmissionRenderTarget[g.id]=new Y8(1,1,{generateMipmaps:!0,type:a.has("EXT_color_buffer_half_float")||a.has("EXT_color_buffer_float")?d6:d8,minFilter:K6,samples:4,stencilBuffer:W,resolveDepthBuffer:!1,resolveStencilBuffer:!1,colorSpace:tJ.workingColorSpace});let WJ=O.state.transmissionRenderTarget[g.id],RJ=g.viewport||I;WJ.setSize(RJ.z*M.transmissionResolutionScale,RJ.w*M.transmissionResolutionScale);let wJ=M.getRenderTarget(),zJ=M.getActiveCubeFace(),fJ=M.getActiveMipmapLevel();if(M.setRenderTarget(WJ),M.getClearColor(d),x=M.getClearAlpha(),x<1)M.setClearColor(16777215,0.5);if(M.clear(),xJ)_J.render(h);let gJ=M.toneMapping;M.toneMapping=T8;let TJ=g.viewport;if(g.viewport!==void 0)g.viewport=void 0;if(O.setupLightsView(g),rJ===!0)VJ.setGlobalState(M.clippingPlanes,g);if(H7(B,h,g),ZJ.updateMultisampleRenderTarget(WJ),ZJ.updateRenderTargetMipmap(WJ),a.has("WEBGL_multisampled_render_to_texture")===!1){let aJ=!1;for(let H0=0,O0=f.length;H0<O0;H0++){let E0=f[H0],X0=E0.object,jJ=E0.geometry,N0=E0.material,$0=E0.group;if(N0.side===R8&&X0.layers.test(g.layers)){let d0=N0.side;N0.side=i0,N0.needsUpdate=!0,aW(X0,h,g,jJ,N0,$0),N0.side=d0,N0.needsUpdate=!0,aJ=!0}}if(aJ===!0)ZJ.updateMultisampleRenderTarget(WJ),ZJ.updateRenderTargetMipmap(WJ)}if(M.setRenderTarget(wJ,zJ,fJ),M.setClearColor(d,x),TJ!==void 0)g.viewport=TJ;M.toneMapping=gJ}function H7(B,f,h){let g=f.isScene===!0?f.overrideMaterial:null;for(let b=0,WJ=B.length;b<WJ;b++){let RJ=B[b],wJ=RJ.object,zJ=RJ.geometry,fJ=RJ.group,gJ=RJ.material;if(gJ.allowOverride===!0&&g!==null)gJ=g;if(wJ.layers.test(h.layers))aW(wJ,f,h,zJ,gJ,fJ)}}function aW(B,f,h,g,b,WJ){if(B.onBeforeRender(M,f,h,g,b,WJ),B.modelViewMatrix.multiplyMatrices(h.matrixWorldInverse,B.matrixWorld),B.normalMatrix.getNormalMatrix(B.modelViewMatrix),b.onBeforeRender(M,f,h,g,B,WJ),b.transparent===!0&&b.side===R8&&b.forceSinglePass===!1)b.side=i0,b.needsUpdate=!0,M.renderBufferDirect(h,f,g,b,B,WJ),b.side=Q6,b.needsUpdate=!0,M.renderBufferDirect(h,f,g,b,B,WJ),b.side=R8;else M.renderBufferDirect(h,f,g,b,B,WJ);B.onAfterRender(M,f,h,g,b,WJ)}function Y7(B,f,h){if(f.isScene!==!0)f=yJ;let g=HJ.get(B),b=O.state.lights,WJ=O.state.shadowsArray,RJ=b.state.version,wJ=v.getParameters(B,b.state,WJ,f,h),zJ=v.getProgramCacheKey(wJ),fJ=g.programs;if(g.environment=B.isMeshStandardMaterial?f.environment:null,g.fog=f.fog,g.envMap=(B.isMeshStandardMaterial?uJ:lJ).get(B.envMap||g.environment),g.envMapRotation=g.environment!==null&&B.envMap===null?f.environmentRotation:B.envMapRotation,fJ===void 0)B.addEventListener("dispose",$J),fJ=new Map,g.programs=fJ;let gJ=fJ.get(zJ);if(gJ!==void 0){if(g.currentProgram===gJ&&g.lightsStateVersion===RJ)return tW(B,wJ),gJ}else wJ.uniforms=v.getUniforms(B),B.onBeforeCompile(wJ,M),gJ=v.acquireProgram(wJ,zJ),fJ.set(zJ,gJ),g.uniforms=wJ.uniforms;let TJ=g.uniforms;if(!B.isShaderMaterial&&!B.isRawShaderMaterial||B.clipping===!0)TJ.clippingPlanes=VJ.uniform;if(tW(B,wJ),g.needsLights=qU(B),g.lightsStateVersion=RJ,g.needsLights)TJ.ambientLightColor.value=b.state.ambient,TJ.lightProbe.value=b.state.probe,TJ.directionalLights.value=b.state.directional,TJ.directionalLightShadows.value=b.state.directionalShadow,TJ.spotLights.value=b.state.spot,TJ.spotLightShadows.value=b.state.spotShadow,TJ.rectAreaLights.value=b.state.rectArea,TJ.ltc_1.value=b.state.rectAreaLTC1,TJ.ltc_2.value=b.state.rectAreaLTC2,TJ.pointLights.value=b.state.point,TJ.pointLightShadows.value=b.state.pointShadow,TJ.hemisphereLights.value=b.state.hemi,TJ.directionalShadowMap.value=b.state.directionalShadowMap,TJ.directionalShadowMatrix.value=b.state.directionalShadowMatrix,TJ.spotShadowMap.value=b.state.spotShadowMap,TJ.spotLightMatrix.value=b.state.spotLightMatrix,TJ.spotLightMap.value=b.state.spotLightMap,TJ.pointShadowMap.value=b.state.pointShadowMap,TJ.pointShadowMatrix.value=b.state.pointShadowMatrix;return g.currentProgram=gJ,g.uniformsList=null,gJ}function rW(B){if(B.uniformsList===null){let f=B.currentProgram.getUniforms();B.uniformsList=K7.seqWithValue(f.seq,B.uniforms)}return B.uniformsList}function tW(B,f){let h=HJ.get(B);h.outputColorSpace=f.outputColorSpace,h.batching=f.batching,h.batchingColor=f.batchingColor,h.instancing=f.instancing,h.instancingColor=f.instancingColor,h.instancingMorph=f.instancingMorph,h.skinning=f.skinning,h.morphTargets=f.morphTargets,h.morphNormals=f.morphNormals,h.morphColors=f.morphColors,h.morphTargetsCount=f.morphTargetsCount,h.numClippingPlanes=f.numClippingPlanes,h.numIntersection=f.numClipIntersection,h.vertexAlphas=f.vertexAlphas,h.vertexTangents=f.vertexTangents,h.toneMapping=f.toneMapping}function EU(B,f,h,g,b){if(f.isScene!==!0)f=yJ;ZJ.resetTextureUnits();let WJ=f.fog,RJ=g.isMeshStandardMaterial?f.environment:null,wJ=C===null?M.outputColorSpace:C.isXRRenderTarget===!0?C.texture.colorSpace:u6,zJ=(g.isMeshStandardMaterial?uJ:lJ).get(g.envMap||RJ),fJ=g.vertexColors===!0&&!!h.attributes.color&&h.attributes.color.itemSize===4,gJ=!!h.attributes.tangent&&(!!g.normalMap||g.anisotropy>0),TJ=!!h.morphAttributes.position,aJ=!!h.morphAttributes.normal,H0=!!h.morphAttributes.color,O0=T8;if(g.toneMapped){if(C===null||C.isXRRenderTarget===!0)O0=M.toneMapping}let E0=h.morphAttributes.position||h.morphAttributes.normal||h.morphAttributes.color,X0=E0!==void 0?E0.length:0,jJ=HJ.get(g),N0=O.state.lights;if(rJ===!0){if(s===!0||B!==z){let y0=B===z&&g.id===y;VJ.setState(g,B,y0)}}let $0=!1;if(g.version===jJ.__version){if(jJ.needsLights&&jJ.lightsStateVersion!==N0.state.version)$0=!0;else if(jJ.outputColorSpace!==wJ)$0=!0;else if(b.isBatchedMesh&&jJ.batching===!1)$0=!0;else if(!b.isBatchedMesh&&jJ.batching===!0)$0=!0;else if(b.isBatchedMesh&&jJ.batchingColor===!0&&b.colorTexture===null)$0=!0;else if(b.isBatchedMesh&&jJ.batchingColor===!1&&b.colorTexture!==null)$0=!0;else if(b.isInstancedMesh&&jJ.instancing===!1)$0=!0;else if(!b.isInstancedMesh&&jJ.instancing===!0)$0=!0;else if(b.isSkinnedMesh&&jJ.skinning===!1)$0=!0;else if(!b.isSkinnedMesh&&jJ.skinning===!0)$0=!0;else if(b.isInstancedMesh&&jJ.instancingColor===!0&&b.instanceColor===null)$0=!0;else if(b.isInstancedMesh&&jJ.instancingColor===!1&&b.instanceColor!==null)$0=!0;else if(b.isInstancedMesh&&jJ.instancingMorph===!0&&b.morphTexture===null)$0=!0;else if(b.isInstancedMesh&&jJ.instancingMorph===!1&&b.morphTexture!==null)$0=!0;else if(jJ.envMap!==zJ)$0=!0;else if(g.fog===!0&&jJ.fog!==WJ)$0=!0;else if(jJ.numClippingPlanes!==void 0&&(jJ.numClippingPlanes!==VJ.numPlanes||jJ.numIntersection!==VJ.numIntersection))$0=!0;else if(jJ.vertexAlphas!==fJ)$0=!0;else if(jJ.vertexTangents!==gJ)$0=!0;else if(jJ.morphTargets!==TJ)$0=!0;else if(jJ.morphNormals!==aJ)$0=!0;else if(jJ.morphColors!==H0)$0=!0;else if(jJ.toneMapping!==O0)$0=!0;else if(jJ.morphTargetsCount!==X0)$0=!0}else $0=!0,jJ.__version=g.version;let d0=jJ.currentProgram;if($0===!0)d0=Y7(g,f,b);let _9=!1,l0=!1,O6=!1,q0=d0.getUniforms(),a0=jJ.uniforms;if(n.useProgram(d0.program))_9=!0,l0=!0,O6=!0;if(g.id!==y)y=g.id,l0=!0;if(_9||z!==B){if(n.buffers.depth.getReversed()&&B.reversedDepth!==!0)B._reversedDepth=!0,B.updateProjectionMatrix();q0.setValue(T,"projectionMatrix",B.projectionMatrix),q0.setValue(T,"viewMatrix",B.matrixWorldInverse);let x0=q0.map.cameraPosition;if(x0!==void 0)x0.setValue(T,XJ.setFromMatrixPosition(B.matrixWorld));if(i.logarithmicDepthBuffer)q0.setValue(T,"logDepthBufFC",2/(Math.log(B.far+1)/Math.LN2));if(g.isMeshPhongMaterial||g.isMeshToonMaterial||g.isMeshLambertMaterial||g.isMeshBasicMaterial||g.isMeshStandardMaterial||g.isShaderMaterial)q0.setValue(T,"isOrthographic",B.isOrthographicCamera===!0);if(z!==B)z=B,l0=!0,O6=!0}if(b.isSkinnedMesh){q0.setOptional(T,b,"bindMatrix"),q0.setOptional(T,b,"bindMatrixInverse");let y0=b.skeleton;if(y0){if(y0.boneTexture===null)y0.computeBoneTexture();q0.setValue(T,"boneTexture",y0.boneTexture,ZJ)}}if(b.isBatchedMesh){if(q0.setOptional(T,b,"batchingTexture"),q0.setValue(T,"batchingTexture",b._matricesTexture,ZJ),q0.setOptional(T,b,"batchingIdTexture"),q0.setValue(T,"batchingIdTexture",b._indirectTexture,ZJ),q0.setOptional(T,b,"batchingColorTexture"),b._colorsTexture!==null)q0.setValue(T,"batchingColorTexture",b._colorsTexture,ZJ)}let r0=h.morphAttributes;if(r0.position!==void 0||r0.normal!==void 0||r0.color!==void 0)vJ.update(b,h,d0);if(l0||jJ.receiveShadow!==b.receiveShadow)jJ.receiveShadow=b.receiveShadow,q0.setValue(T,"receiveShadow",b.receiveShadow);if(g.isMeshGouraudMaterial&&g.envMap!==null)a0.envMap.value=zJ,a0.flipEnvMap.value=zJ.isCubeTexture&&zJ.isRenderTargetTexture===!1?-1:1;if(g.isMeshStandardMaterial&&g.envMap===null&&f.environment!==null)a0.envMapIntensity.value=f.environmentIntensity;if(l0){if(q0.setValue(T,"toneMappingExposure",M.toneMappingExposure),jJ.needsLights)NU(a0,O6);if(WJ&&g.fog===!0)c.refreshFogUniforms(a0,WJ);c.refreshMaterialUniforms(a0,g,QJ,l,O.state.transmissionRenderTarget[B.id]),K7.upload(T,rW(jJ),a0,ZJ)}if(g.isShaderMaterial&&g.uniformsNeedUpdate===!0)K7.upload(T,rW(jJ),a0,ZJ),g.uniformsNeedUpdate=!1;if(g.isSpriteMaterial)q0.setValue(T,"center",b.center);if(q0.setValue(T,"modelViewMatrix",b.modelViewMatrix),q0.setValue(T,"normalMatrix",b.normalMatrix),q0.setValue(T,"modelMatrix",b.matrixWorld),g.isShaderMaterial||g.isRawShaderMaterial){let y0=g.uniformsGroups;for(let x0=0,K$=y0.length;x0<K$;x0++){let i8=y0[x0];MJ.update(i8,d0),MJ.bind(i8,d0)}}return d0}function NU(B,f){B.ambientLightColor.needsUpdate=f,B.lightProbe.needsUpdate=f,B.directionalLights.needsUpdate=f,B.directionalLightShadows.needsUpdate=f,B.pointLights.needsUpdate=f,B.pointLightShadows.needsUpdate=f,B.spotLights.needsUpdate=f,B.spotLightShadows.needsUpdate=f,B.rectAreaLights.needsUpdate=f,B.hemisphereLights.needsUpdate=f}function qU(B){return B.isMeshLambertMaterial||B.isMeshToonMaterial||B.isMeshPhongMaterial||B.isMeshStandardMaterial||B.isShadowMaterial||B.isShaderMaterial&&B.lights===!0}this.getActiveCubeFace=function(){return A},this.getActiveMipmapLevel=function(){return _},this.getRenderTarget=function(){return C},this.setRenderTargetTextures=function(B,f,h){let g=HJ.get(B);if(g.__autoAllocateDepthBuffer=B.resolveDepthBuffer===!1,g.__autoAllocateDepthBuffer===!1)g.__useRenderToTexture=!1;HJ.get(B.texture).__webglTexture=f,HJ.get(B.depthTexture).__webglTexture=g.__autoAllocateDepthBuffer?void 0:h,g.__hasExternalTextures=!0},this.setRenderTargetFramebuffer=function(B,f){let h=HJ.get(B);h.__webglFramebuffer=f,h.__useDefaultFramebuffer=f===void 0};let DU=T.createFramebuffer();this.setRenderTarget=function(B,f=0,h=0){C=B,A=f,_=h;let g=!0,b=null,WJ=!1,RJ=!1;if(B){let zJ=HJ.get(B);if(zJ.__useDefaultFramebuffer!==void 0)n.bindFramebuffer(T.FRAMEBUFFER,null),g=!1;else if(zJ.__webglFramebuffer===void 0)ZJ.setupRenderTarget(B);else if(zJ.__hasExternalTextures)ZJ.rebindTextures(B,HJ.get(B.texture).__webglTexture,HJ.get(B.depthTexture).__webglTexture);else if(B.depthBuffer){let TJ=B.depthTexture;if(zJ.__boundDepthTexture!==TJ){if(TJ!==null&&HJ.has(TJ)&&(B.width!==TJ.image.width||B.height!==TJ.image.height))throw Error("WebGLRenderTarget: Attached DepthTexture is initialized to the incorrect size.");ZJ.setupDepthRenderbuffer(B)}}let fJ=B.texture;if(fJ.isData3DTexture||fJ.isDataArrayTexture||fJ.isCompressedArrayTexture)RJ=!0;let gJ=HJ.get(B).__webglFramebuffer;if(B.isWebGLCubeRenderTarget){if(Array.isArray(gJ[f]))b=gJ[f][h];else b=gJ[f];WJ=!0}else if(B.samples>0&&ZJ.useMultisampledRTT(B)===!1)b=HJ.get(B).__webglMultisampledFramebuffer;else if(Array.isArray(gJ))b=gJ[h];else b=gJ;I.copy(B.viewport),S.copy(B.scissor),p=B.scissorTest}else I.copy(NJ).multiplyScalar(QJ).floor(),S.copy(SJ).multiplyScalar(QJ).floor(),p=mJ;if(h!==0)b=DU;if(n.bindFramebuffer(T.FRAMEBUFFER,b)&&g)n.drawBuffers(B,b);if(n.viewport(I),n.scissor(S),n.setScissorTest(p),WJ){let zJ=HJ.get(B.texture);T.framebufferTexture2D(T.FRAMEBUFFER,T.COLOR_ATTACHMENT0,T.TEXTURE_CUBE_MAP_POSITIVE_X+f,zJ.__webglTexture,h)}else if(RJ){let zJ=f;for(let fJ=0;fJ<B.textures.length;fJ++){let gJ=HJ.get(B.textures[fJ]);T.framebufferTextureLayer(T.FRAMEBUFFER,T.COLOR_ATTACHMENT0+fJ,gJ.__webglTexture,h,zJ)}}else if(B!==null&&h!==0){let zJ=HJ.get(B.texture);T.framebufferTexture2D(T.FRAMEBUFFER,T.COLOR_ATTACHMENT0,T.TEXTURE_2D,zJ.__webglTexture,h)}y=-1},this.readRenderTargetPixels=function(B,f,h,g,b,WJ,RJ,wJ=0){if(!(B&&B.isWebGLRenderTarget)){console.error("THREE.WebGLRenderer.readRenderTargetPixels: renderTarget is not THREE.WebGLRenderTarget.");return}let zJ=HJ.get(B).__webglFramebuffer;if(B.isWebGLCubeRenderTarget&&RJ!==void 0)zJ=zJ[RJ];if(zJ){n.bindFramebuffer(T.FRAMEBUFFER,zJ);try{let fJ=B.textures[wJ],gJ=fJ.format,TJ=fJ.type;if(!i.textureFormatReadable(gJ)){console.error("THREE.WebGLRenderer.readRenderTargetPixels: renderTarget is not in RGBA or implementation defined format.");return}if(!i.textureTypeReadable(TJ)){console.error("THREE.WebGLRenderer.readRenderTargetPixels: renderTarget is not in UnsignedByteType or implementation defined type.");return}if(f>=0&&f<=B.width-g&&(h>=0&&h<=B.height-b)){if(B.textures.length>1)T.readBuffer(T.COLOR_ATTACHMENT0+wJ);T.readPixels(f,h,g,b,PJ.convert(gJ),PJ.convert(TJ),WJ)}}finally{let fJ=C!==null?HJ.get(C).__webglFramebuffer:null;n.bindFramebuffer(T.FRAMEBUFFER,fJ)}}},this.readRenderTargetPixelsAsync=async function(B,f,h,g,b,WJ,RJ,wJ=0){if(!(B&&B.isWebGLRenderTarget))throw Error("THREE.WebGLRenderer.readRenderTargetPixels: renderTarget is not THREE.WebGLRenderTarget.");let zJ=HJ.get(B).__webglFramebuffer;if(B.isWebGLCubeRenderTarget&&RJ!==void 0)zJ=zJ[RJ];if(zJ)if(f>=0&&f<=B.width-g&&(h>=0&&h<=B.height-b)){n.bindFramebuffer(T.FRAMEBUFFER,zJ);let fJ=B.textures[wJ],gJ=fJ.format,TJ=fJ.type;if(!i.textureFormatReadable(gJ))throw Error("THREE.WebGLRenderer.readRenderTargetPixelsAsync: renderTarget is not in RGBA or implementation defined format.");if(!i.textureTypeReadable(TJ))throw Error("THREE.WebGLRenderer.readRenderTargetPixelsAsync: renderTarget is not in UnsignedByteType or implementation defined type.");let aJ=T.createBuffer();if(T.bindBuffer(T.PIXEL_PACK_BUFFER,aJ),T.bufferData(T.PIXEL_PACK_BUFFER,WJ.byteLength,T.STREAM_READ),B.textures.length>1)T.readBuffer(T.COLOR_ATTACHMENT0+wJ);T.readPixels(f,h,g,b,PJ.convert(gJ),PJ.convert(TJ),0);let H0=C!==null?HJ.get(C).__webglFramebuffer:null;n.bindFramebuffer(T.FRAMEBUFFER,H0);let O0=T.fenceSync(T.SYNC_GPU_COMMANDS_COMPLETE,0);return T.flush(),await GY(T,O0,4),T.bindBuffer(T.PIXEL_PACK_BUFFER,aJ),T.getBufferSubData(T.PIXEL_PACK_BUFFER,0,WJ),T.deleteBuffer(aJ),T.deleteSync(O0),WJ}else throw Error("THREE.WebGLRenderer.readRenderTargetPixelsAsync: requested read bounds are out of range.")},this.copyFramebufferToTexture=function(B,f=null,h=0){let g=Math.pow(2,-h),b=Math.floor(B.image.width*g),WJ=Math.floor(B.image.height*g),RJ=f!==null?f.x:0,wJ=f!==null?f.y:0;ZJ.setTexture2D(B,0),T.copyTexSubImage2D(T.TEXTURE_2D,h,0,0,RJ,wJ,b,WJ),n.unbindTexture()};let OU=T.createFramebuffer(),RU=T.createFramebuffer();if(this.copyTextureToTexture=function(B,f,h=null,g=null,b=0,WJ=null){if(WJ===null)if(b!==0)o9("WebGLRenderer: copyTextureToTexture function signature has changed to support src and dst mipmap levels."),WJ=b,b=0;else WJ=0;let RJ,wJ,zJ,fJ,gJ,TJ,aJ,H0,O0,E0=B.isCompressedTexture?B.mipmaps[WJ]:B.image;if(h!==null)RJ=h.max.x-h.min.x,wJ=h.max.y-h.min.y,zJ=h.isBox3?h.max.z-h.min.z:1,fJ=h.min.x,gJ=h.min.y,TJ=h.isBox3?h.min.z:0;else{let r0=Math.pow(2,-b);if(RJ=Math.floor(E0.width*r0),wJ=Math.floor(E0.height*r0),B.isDataArrayTexture)zJ=E0.depth;else if(B.isData3DTexture)zJ=Math.floor(E0.depth*r0);else zJ=1;fJ=0,gJ=0,TJ=0}if(g!==null)aJ=g.x,H0=g.y,O0=g.z;else aJ=0,H0=0,O0=0;let X0=PJ.convert(f.format),jJ=PJ.convert(f.type),N0;if(f.isData3DTexture)ZJ.setTexture3D(f,0),N0=T.TEXTURE_3D;else if(f.isDataArrayTexture||f.isCompressedArrayTexture)ZJ.setTexture2DArray(f,0),N0=T.TEXTURE_2D_ARRAY;else ZJ.setTexture2D(f,0),N0=T.TEXTURE_2D;T.pixelStorei(T.UNPACK_FLIP_Y_WEBGL,f.flipY),T.pixelStorei(T.UNPACK_PREMULTIPLY_ALPHA_WEBGL,f.premultiplyAlpha),T.pixelStorei(T.UNPACK_ALIGNMENT,f.unpackAlignment);let $0=T.getParameter(T.UNPACK_ROW_LENGTH),d0=T.getParameter(T.UNPACK_IMAGE_HEIGHT),_9=T.getParameter(T.UNPACK_SKIP_PIXELS),l0=T.getParameter(T.UNPACK_SKIP_ROWS),O6=T.getParameter(T.UNPACK_SKIP_IMAGES);T.pixelStorei(T.UNPACK_ROW_LENGTH,E0.width),T.pixelStorei(T.UNPACK_IMAGE_HEIGHT,E0.height),T.pixelStorei(T.UNPACK_SKIP_PIXELS,fJ),T.pixelStorei(T.UNPACK_SKIP_ROWS,gJ),T.pixelStorei(T.UNPACK_SKIP_IMAGES,TJ);let q0=B.isDataArrayTexture||B.isData3DTexture,a0=f.isDataArrayTexture||f.isData3DTexture;if(B.isDepthTexture){let r0=HJ.get(B),y0=HJ.get(f),x0=HJ.get(r0.__renderTarget),K$=HJ.get(y0.__renderTarget);n.bindFramebuffer(T.READ_FRAMEBUFFER,x0.__webglFramebuffer),n.bindFramebuffer(T.DRAW_FRAMEBUFFER,K$.__webglFramebuffer);for(let i8=0;i8<zJ;i8++){if(q0)T.framebufferTextureLayer(T.READ_FRAMEBUFFER,T.COLOR_ATTACHMENT0,HJ.get(B).__webglTexture,b,TJ+i8),T.framebufferTextureLayer(T.DRAW_FRAMEBUFFER,T.COLOR_ATTACHMENT0,HJ.get(f).__webglTexture,WJ,O0+i8);T.blitFramebuffer(fJ,gJ,RJ,wJ,aJ,H0,RJ,wJ,T.DEPTH_BUFFER_BIT,T.NEAREST)}n.bindFramebuffer(T.READ_FRAMEBUFFER,null),n.bindFramebuffer(T.DRAW_FRAMEBUFFER,null)}else if(b!==0||B.isRenderTargetTexture||HJ.has(B)){let r0=HJ.get(B),y0=HJ.get(f);n.bindFramebuffer(T.READ_FRAMEBUFFER,OU),n.bindFramebuffer(T.DRAW_FRAMEBUFFER,RU);for(let x0=0;x0<zJ;x0++){if(q0)T.framebufferTextureLayer(T.READ_FRAMEBUFFER,T.COLOR_ATTACHMENT0,r0.__webglTexture,b,TJ+x0);else T.framebufferTexture2D(T.READ_FRAMEBUFFER,T.COLOR_ATTACHMENT0,T.TEXTURE_2D,r0.__webglTexture,b);if(a0)T.framebufferTextureLayer(T.DRAW_FRAMEBUFFER,T.COLOR_ATTACHMENT0,y0.__webglTexture,WJ,O0+x0);else T.framebufferTexture2D(T.DRAW_FRAMEBUFFER,T.COLOR_ATTACHMENT0,T.TEXTURE_2D,y0.__webglTexture,WJ);if(b!==0)T.blitFramebuffer(fJ,gJ,RJ,wJ,aJ,H0,RJ,wJ,T.COLOR_BUFFER_BIT,T.NEAREST);else if(a0)T.copyTexSubImage3D(N0,WJ,aJ,H0,O0+x0,fJ,gJ,RJ,wJ);else T.copyTexSubImage2D(N0,WJ,aJ,H0,fJ,gJ,RJ,wJ)}n.bindFramebuffer(T.READ_FRAMEBUFFER,null),n.bindFramebuffer(T.DRAW_FRAMEBUFFER,null)}else if(a0)if(B.isDataTexture||B.isData3DTexture)T.texSubImage3D(N0,WJ,aJ,H0,O0,RJ,wJ,zJ,X0,jJ,E0.data);else if(f.isCompressedArrayTexture)T.compressedTexSubImage3D(N0,WJ,aJ,H0,O0,RJ,wJ,zJ,X0,E0.data);else T.texSubImage3D(N0,WJ,aJ,H0,O0,RJ,wJ,zJ,X0,jJ,E0);else if(B.isDataTexture)T.texSubImage2D(T.TEXTURE_2D,WJ,aJ,H0,RJ,wJ,X0,jJ,E0.data);else if(B.isCompressedTexture)T.compressedTexSubImage2D(T.TEXTURE_2D,WJ,aJ,H0,E0.width,E0.height,X0,E0.data);else T.texSubImage2D(T.TEXTURE_2D,WJ,aJ,H0,RJ,wJ,X0,jJ,E0);if(T.pixelStorei(T.UNPACK_ROW_LENGTH,$0),T.pixelStorei(T.UNPACK_IMAGE_HEIGHT,d0),T.pixelStorei(T.UNPACK_SKIP_PIXELS,_9),T.pixelStorei(T.UNPACK_SKIP_ROWS,l0),T.pixelStorei(T.UNPACK_SKIP_IMAGES,O6),WJ===0&&f.generateMipmaps)T.generateMipmap(N0);n.unbindTexture()},this.initRenderTarget=function(B){if(HJ.get(B).__webglFramebuffer===void 0)ZJ.setupRenderTarget(B)},this.initTexture=function(B){if(B.isCubeTexture)ZJ.setTextureCube(B,0);else if(B.isData3DTexture)ZJ.setTexture3D(B,0);else if(B.isDataArrayTexture||B.isCompressedArrayTexture)ZJ.setTexture2DArray(B,0);else ZJ.setTexture2D(B,0);n.unbindTexture()},this.resetState=function(){A=0,_=0,C=null,n.reset(),AJ.reset()},typeof __THREE_DEVTOOLS__<"u")__THREE_DEVTOOLS__.dispatchEvent(new CustomEvent("observe",{detail:this}))}get coordinateSystem(){return hZ}get outputColorSpace(){return this._outputColorSpace}set outputColorSpace(J){this._outputColorSpace=J;let Q=this.getContext();Q.drawingBufferColorSpace=tJ._getDrawingBufferColorSpace(J),Q.unpackColorSpace=tJ._getUnpackColorSpace()}}export{UY as createCanvasElement,nU as ZeroStencilOp,bU as ZeroSlopeEnding,OH as ZeroFactor,fU as ZeroCurvatureEnding,hU as WrapAroundEnding,HW as WireframeGeometry,o6 as WebXRController,MG as WebGPUCoordinateSystem,h5 as WebGLUtils,l5 as WebGLRenderer,Y8 as WebGLRenderTarget,lZ as WebGLCubeRenderTarget,hZ as WebGLCoordinateSystem,EY as WebGLArrayRenderTarget,NY as WebGL3DRenderTarget,tZ as VideoTexture,IY as VideoFrameTexture,t9 as VectorKeyframeTrack,J0 as Vector4,w as Vector3,t as Vector2,O8 as VSMShadowMap,m6 as UnsignedShortType,$Z as UnsignedShort5551Type,QZ as UnsignedShort4444Type,H6 as UnsignedIntType,nH as UnsignedInt5999Type,Y6 as UnsignedInt248Type,sH as UnsignedInt101111Type,d8 as UnsignedByteType,LY as UniformsUtils,DJ as UniformsLib,WX as UniformsGroup,hW as Uniform,FY as Uint8ClampedBufferAttribute,RY as Uint8BufferAttribute,FQ as Uint32BufferAttribute,RQ as Uint16BufferAttribute,BU as UVMapping,lQ as TubeGeometry,pU as TrianglesDrawMode,mU as TriangleStripDrawMode,dU as TriangleFanDrawMode,m0 as Triangle,dQ as TorusKnotGeometry,mQ as TorusGeometry,kG as TimestampQuery,XX as Timer,AX as TextureUtils,lY as TextureLoader,F0 as Texture,pQ as TetrahedronGeometry,eH as TangentSpaceNormalMap,MU as TOUCH,t$ as SubtractiveBlending,EH as SubtractEquation,n8 as StringKeyframeTrack,qG as StreamReadUsage,GG as StreamDrawUsage,RG as StreamCopyUsage,aY as StereoCamera,EG as StaticReadUsage,XG as StaticDrawUsage,DG as StaticCopyUsage,FH as SrcColorFactor,_H as SrcAlphaSaturateFactor,kH as SrcAlphaFactor,VQ as SpriteMaterial,cZ as Sprite,qX as SpotLightHelper,LW as SpotLight,vQ as SplineCurve,wW as SphericalHarmonics3,UX as Spherical,$7 as SphereGeometry,_0 as Sphere,C8 as Source,sZ as SkinnedMesh,DX as SkeletonHelper,zQ as Skeleton,cH as ShortType,W8 as ShapeUtils,CX as ShapePath,gQ as ShapeGeometry,p8 as Shape,YW as ShadowMaterial,e0 as ShaderMaterial,M8 as ShaderLib,iJ as ShaderChunk,uZ as Scene,G0 as SRGBTransfer,QY as SRGBColorSpace,SZ as SIGNED_RED_RGTC1_Format,yZ as SIGNED_RED_GREEN_RGTC2_Format,xQ as RingGeometry,NH as ReverseSubtractEquation,iU as ReplaceStencilOp,pH as RepeatWrapping,ZX as RenderTarget3D,OQ as RenderTarget,vH as ReinhardToneMapping,ZZ as RedIntegerFormat,aH as RedFormat,_W as RectAreaLight,YX as Raycaster,F9 as Ray,XW as RawShaderMaterial,WZ as RGIntegerFormat,rH as RGFormat,cU as RGDepthPacking,EQ as RGB_S3TC_DXT1_Format,HZ as RGB_PVRTC_4BPPV1_Format,YZ as RGB_PVRTC_2BPPV1_Format,EZ as RGB_ETC2_Format,GZ as RGB_ETC1_Format,AZ as RGB_BPTC_UNSIGNED_Format,PZ as RGB_BPTC_SIGNED_Format,PU as RGBIntegerFormat,oH as RGBFormat,uU as RGBDepthPacking,DQ as RGBA_S3TC_DXT5_Format,qQ as RGBA_S3TC_DXT3_Format,NQ as RGBA_S3TC_DXT1_Format,XZ as RGBA_PVRTC_4BPPV1_Format,UZ as RGBA_PVRTC_2BPPV1_Format,NZ as RGBA_ETC2_EAC_Format,CZ as RGBA_BPTC_Format,VZ as RGBA_ASTC_8x8_Format,kZ as RGBA_ASTC_8x6_Format,MZ as RGBA_ASTC_8x5_Format,FZ as RGBA_ASTC_6x6_Format,RZ as RGBA_ASTC_6x5_Format,OZ as RGBA_ASTC_5x5_Format,DZ as RGBA_ASTC_5x4_Format,qZ as RGBA_ASTC_4x4_Format,wZ as RGBA_ASTC_12x12_Format,_Z as RGBA_ASTC_12x10_Format,BZ as RGBA_ASTC_10x8_Format,zZ as RGBA_ASTC_10x6_Format,LZ as RGBA_ASTC_10x5_Format,IZ as RGBA_ASTC_10x10_Format,KZ as RGBAIntegerFormat,F8 as RGBAFormat,tH as RGBADepthPacking,HH as REVISION,TZ as RED_RGTC1_Format,jZ as RED_GREEN_RGTC2_Format,kW as QuaternionLinearInterpolant,E6 as QuaternionKeyframeTrack,b0 as Quaternion,yQ as QuadraticBezierCurve3,jQ as QuadraticBezierCurve,yW as PropertyMixer,eJ as PropertyBinding,tY as PositionalAudio,u8 as PolyhedronGeometry,kX as PolarGridHelper,IQ as PointsMaterial,rZ as Points,RX as PointLightHelper,zW as PointLight,IX as PlaneHelper,U6 as PlaneGeometry,_8 as Plane,I0 as PerspectiveCamera,y6 as Path,cW as PMREMGenerator,UH as PCFSoftShadowMap,a$ as PCFShadowMap,Z7 as OrthographicCamera,MH as OneMinusSrcColorFactor,VH as OneMinusSrcAlphaFactor,IH as OneMinusDstColorFactor,zH as OneMinusDstAlphaFactor,CH as OneMinusConstantColorFactor,AH as OneMinusConstantAlphaFactor,RH as OneFactor,Q7 as OctahedronGeometry,JY as ObjectSpaceNormalMap,sY as ObjectLoader,Q0 as Object3D,r9 as NumberKeyframeTrack,KG as NotEqualStencilFunc,HQ as NotEqualDepth,HY as NotEqualCompare,h6 as NormalBlending,xU as NormalAnimationBlendMode,T8 as NoToneMapping,R9 as NoColorSpace,m8 as NoBlending,JG as NeverStencilFunc,JQ as NeverDepth,$Y as NeverCompare,gH as NeutralToneMapping,lH as NearestMipmapNearestFilter,p6 as NearestMipmapLinearFilter,IU as NearestMipMapNearestFilter,_U as NearestMipMapLinearFilter,W6 as NearestFilter,TH as MultiplyOperation,e$ as MultiplyBlending,SH as MixOperation,dH as MirroredRepeatWrapping,qH as MinEquation,EW as MeshToonMaterial,uQ as MeshStandardMaterial,UW as MeshPhysicalMaterial,GW as MeshPhongMaterial,NW as MeshNormalMaterial,DW as MeshMatcapMaterial,qW as MeshLambertMaterial,nQ as MeshDistanceMaterial,cQ as MeshDepthMaterial,S8 as MeshBasicMaterial,k0 as Mesh,DH as MaxEquation,hJ as Matrix4,dJ as Matrix3,xW as Matrix2,xG as MathUtils,rQ as MaterialLoader,C0 as Material,FU as MOUSE,TU as LoopRepeat,SU as LoopPingPong,AU as LoopOnce,oQ as LoadingManager,e7 as LoaderUtils,h0 as Loader,vZ as LinearTransfer,yH as LinearToneMapping,u6 as LinearSRGBColorSpace,UQ as LinearMipmapNearestFilter,K6 as LinearMipmapLinearFilter,wU as LinearMipMapNearestFilter,CU as LinearMipMapLinearFilter,sQ as LinearInterpolant,O9 as LinearFilter,X8 as LineSegments,aZ as LineLoop,OW as LineDashedMaterial,WW as LineCurve3,SQ as LineCurve,j0 as LineBasicMaterial,NX as Line3,A8 as Line,CW as LightProbe,j8 as Light,QG as LessStencilFunc,ZG as LessEqualStencilFunc,x6 as LessEqualDepth,fZ as LessEqualCompare,$Q as LessDepth,ZY as LessCompare,s6 as Layers,hQ as LatheGeometry,nZ as LOD,o0 as KeyframeTrack,sU as KeepStencilOp,eU as InvertStencilOp,VG as InterpolationSamplingType,LG as InterpolationSamplingMode,vU as InterpolateSmooth,yU as InterpolateLinear,jU as InterpolateDiscrete,G6 as Interpolant,E9 as InterleavedBufferAttribute,a6 as InterleavedBuffer,JZ as IntType,OY as Int8BufferAttribute,kY as Int32BufferAttribute,MY as Int16BufferAttribute,iZ as InstancedMesh,KX as InstancedInterleavedBuffer,PW as InstancedBufferGeometry,N9 as InstancedBufferAttribute,rU as IncrementWrapStencilOp,oU as IncrementStencilOp,pZ as ImageUtils,J6 as ImageLoader,iY as ImageBitmapLoader,bQ as IcosahedronGeometry,FX as HemisphereLightHelper,VW as HemisphereLight,d6 as HalfFloatType,Y9 as Group,MX as GridHelper,WG as GreaterStencilFunc,HG as GreaterEqualStencilFunc,WQ as GreaterEqualDepth,YY as GreaterEqualCompare,KQ as GreaterDepth,KY as GreaterCompare,bZ as GLSL3,FG as GLSL1,HX as GLBufferAttribute,BQ as FrustumArray,V9 as Frustum,Q6 as FrontSide,_Y as FramebufferTexture,MQ as FogExp2,kQ as Fog,l8 as FloatType,BJ as Float32BufferAttribute,VY as Float16BufferAttribute,D8 as FileLoader,fQ as ExtrudeGeometry,wQ as ExternalTexture,H8 as EventDispatcher,s0 as Euler,XQ as EquirectangularRefractionMapping,YQ as EquirectangularReflectionMapping,$G as EqualStencilFunc,ZQ as EqualDepth,WY as EqualCompare,J7 as EllipseCurve,eZ as EdgesGeometry,NG as DynamicReadUsage,UG as DynamicDrawUsage,OG as DynamicCopyUsage,BH as DstColorFactor,LH as DstAlphaFactor,R8 as DoubleSide,AQ as DodecahedronGeometry,MW as DiscreteInterpolant,VX as DirectionalLightHelper,BW as DirectionalLight,zU as DetachedBindMode,_Q as DepthTexture,l6 as DepthStencilFormat,GQ as DepthFormat,hY as DefaultLoadingManager,tU as DecrementWrapStencilOp,aU as DecrementStencilOp,DY as DataUtils,dY as DataTextureLoader,K8 as DataTexture,c6 as DataArrayTexture,n6 as Data3DTexture,GX as Cylindrical,t6 as CylinderGeometry,hH as CustomToneMapping,GH as CustomBlending,KW as CurvePath,J8 as Curve,YH as CullFaceNone,kU as CullFaceFrontBack,XH as CullFaceFront,o$ as CullFaceBack,FW as CubicInterpolant,ZW as CubicBezierCurve3,TQ as CubicBezierCurve,g6 as CubeUVReflectionMapping,mY as CubeTextureLoader,X6 as CubeTexture,D9 as CubeRefractionMapping,Z6 as CubeReflectionMapping,dZ as CubeCamera,PX as Controls,wH as ConstantColorFactor,PH as ConstantAlphaFactor,e6 as ConeGeometry,pY as CompressedTextureLoader,r6 as CompressedTexture,CY as CompressedCubeTexture,wY as CompressedArrayTexture,tJ as ColorManagement,iQ as ColorKeyframeTrack,kJ as Color,SW as Clock,mH as ClampToEdgeWrapping,PQ as CircleGeometry,fH as CineonToneMapping,$W as CatmullRomCurve3,CQ as CapsuleGeometry,PY as CanvasTexture,LX as CameraHelper,i6 as Camera,q8 as Cache,uH as ByteType,AW as BufferGeometryLoader,nJ as BufferGeometry,Z0 as BufferAttribute,zX as BoxHelper,M9 as BoxGeometry,BX as Box3Helper,w0 as Box3,EX as Box2,c8 as BooleanKeyframeTrack,LQ as Bone,oZ as BatchedMesh,VU as BasicShadowMap,lU as BasicDepthPacking,i0 as BackSide,wX as AxesHelper,oY as AudioLoader,rY as AudioListener,tQ as AudioContext,eY as AudioAnalyser,jW as Audio,LU as AttachedBindMode,_X as ArrowHelper,TW as ArrayCamera,JW as ArcCurve,bY as AnimationUtils,QX as AnimationObjectGroup,$X as AnimationMixer,gY as AnimationLoader,e9 as AnimationClip,bW as AnimationAction,IW as AmbientLight,YG as AlwaysStencilFunc,QQ as AlwaysDepth,XY as AlwaysCompare,iH as AlphaFormat,xH as AgXToneMapping,r$ as AdditiveBlending,gU as AdditiveAnimationBlendMode,jH as AddOperation,$6 as AddEquation,bH as ACESFilmicToneMapping};
