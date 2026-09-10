Three.js 0.180.0, MIT licence (see LICENSE).
three.module.js is a minified browser bundle of the upstream build/three.module.js and build/three.core.js, produced with:
bun build <upstream-three.module.js> --target browser --minify --outfile three.module.js
OrbitControls.js is the unmodified addon from the same version.
three.core.js is retained as upstream source; the bundled module no longer requests it at runtime.
Upstream: https://github.com/mrdoob/three.js/tree/r180
