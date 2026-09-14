class_name SurfaceDetail
extends RefCounted

## Micro-relief for every surface in the yard.
##
## Every mesh in this game is an untextured primitive, so until this existed a
## steel plate, a concrete pier and a painted machine panel differed only by a
## flat RGB tint and a scalar roughness. One normal per face means there is no
## light response at all below polygon scale, and no amount of lighting or
## tonemap work can add one - the surface has no micro-geometry to catch light.
##
## This builds a small library of tiling relief maps and hands them to the
## StandardMaterial3D that geom.gd already returns, so all of the existing mesh
## call sites pick up sub-polygon shading without any of them being edited.
##
## Triplanar rather than the primitives' own UVs, deliberately: a BoxMesh sized
## 10 x 0.2 x 4 carries wildly different texel density on each face, so a single
## scale would read correctly on none of them. Triplanar projects from position,
## so density is uniform no matter what a caller sized its box to. Object space
## rather than world space, so relief stays glued to the excavator arm and the
## humanoid limbs instead of swimming as they move.
##
## Mipmaps are the anti-aliasing. High-frequency relief evaluated analytically
## per pixel has to band-limit itself - fading each octave out as its period
## approaches one pixel - or it crawls and shimmers under camera motion, which
## is worse than being flat. Sampling a mipmapped texture gets that band-limit
## from hardware trilinear filtering instead, for free and at every distance.

enum {
	NONE,
	STEEL,
	CAST,
	CONCRETE,
	PAINTED,
	RUBBER
}

const TEX_SIZE := 192

## Relief depth per surface class. These are small on purpose. Micro-relief is
## supposed to break the specular term, not the diffuse one: perturb the normal
## hard enough and N.L swings with it, the surface stops reading as texture and
## starts reading as blotchy paint. Concrete gets the most because aggregate
## genuinely is coarse; paint gets almost none because paint is a levelling
## coat and its only real relief is orange peel.
const DEPTH := {
	STEEL: 0.26,
	CAST: 0.52,
	CONCRETE: 0.66,
	PAINTED: 0.16,
	RUBBER: 0.30
}

## Tiles per metre of object space, per axis. Steel is anisotropic on purpose:
## plate comes off a rolling mill with directional grain. Kept near 2:1 - past
## that the bands stop reading as grain and start reading as corrugation, which
## is a different (and wrong) piece of geometry.
const TILING := {
	STEEL: Vector3(0.95, 1.90, 0.95),
	CAST: Vector3(1.60, 1.60, 1.60),
	CONCRETE: Vector3(0.90, 0.90, 0.90),
	PAINTED: Vector3(2.60, 2.60, 2.60),
	RUBBER: Vector3(3.80, 3.80, 3.80)
}

static var _cache: Dictionary = {}


## Kept as its own texture per class rather than one shared map with per-class
## strength: the character of the relief is the point. Cellular noise pits like
## corrosion, fractal noise creases like worked metal, and no scalar converts
## one into the other.
static func _build_noise(kind: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = 20250914 + kind
	match kind:
		STEEL:
			# Fine fractal grain: mill scale and draw marks, not lumps.
			noise.noise_type = FastNoiseLite.TYPE_PERLIN
			noise.frequency = 0.045
			noise.fractal_type = FastNoiseLite.FRACTAL_FBM
			noise.fractal_octaves = 4
			noise.fractal_gain = 0.46
		CAST:
			# Cellular F1 reads as pitting - cast and corroded surfaces are
			# made of cavities, which fractal noise cannot produce.
			noise.noise_type = FastNoiseLite.TYPE_CELLULAR
			noise.frequency = 0.030
			noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
			noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
			noise.fractal_type = FastNoiseLite.FRACTAL_FBM
			noise.fractal_octaves = 3
			noise.fractal_gain = 0.40
		CONCRETE:
			# Aggregate: large cells for stones, fractal on top for the paste.
			noise.noise_type = FastNoiseLite.TYPE_CELLULAR
			noise.frequency = 0.022
			noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN_SQUARED
			noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
			noise.fractal_type = FastNoiseLite.FRACTAL_FBM
			noise.fractal_octaves = 4
			noise.fractal_gain = 0.55
		PAINTED:
			# Orange peel: one smooth low-amplitude scale, nothing sharp.
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			noise.frequency = 0.055
			noise.fractal_type = FastNoiseLite.FRACTAL_FBM
			noise.fractal_octaves = 2
			noise.fractal_gain = 0.35
		_:
			# Rubber and anything else: even fine stipple.
			noise.noise_type = FastNoiseLite.TYPE_VALUE
			noise.frequency = 0.090
			noise.fractal_type = FastNoiseLite.FRACTAL_FBM
			noise.fractal_octaves = 3
			noise.fractal_gain = 0.50
	return noise


static func texture(kind: int) -> Texture2D:
	if kind == NONE:
		return null
	if _cache.has(kind):
		return _cache[kind]
	var tex := NoiseTexture2D.new()
	tex.width = TEX_SIZE
	tex.height = TEX_SIZE
	# Seamless, or every primitive in the yard shows the same grid of tile
	# boundaries and the relief becomes the most obvious thing on screen.
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.as_normal_map = true
	tex.bump_strength = 3.0
	tex.noise = _build_noise(kind)
	_cache[kind] = tex
	return tex


## Callers pass roughness and metallic already; those two numbers carry enough
## of the author's intent to pick a surface class without touching a single one
## of the existing call sites. This is an inference from how a surface was
## specified, not a reading of simulation state - the structures that do carry
## solver state drive their own shader instead.
static func infer(roughness: float, metallic: float) -> int:
	if metallic >= 0.35:
		return STEEL
	if roughness >= 0.88:
		return CONCRETE
	if metallic >= 0.12:
		return CAST
	if roughness <= 0.50:
		return RUBBER
	return PAINTED


static func apply(material: StandardMaterial3D, kind: int) -> void:
	if material == null or kind == NONE:
		return
	var tex := texture(kind)
	if tex == null:
		return
	material.normal_enabled = true
	material.normal_texture = tex
	material.normal_scale = float(DEPTH.get(kind, 0.5))
	material.uv1_triplanar = true
	material.uv1_scale = TILING.get(kind, Vector3.ONE)
	# Sharper than the default blend so a box's three projections meet in a
	# narrow seam instead of smearing a third of every face into a blur.
	material.uv1_triplanar_sharpness = 2.4
