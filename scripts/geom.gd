class_name Geom
extends RefCounted

const Detail = preload("res://scripts/surface_detail.gd")

## detail < 0 lets surface_detail.gd pick a class from roughness and metallic,
## which is what every existing call site relies on. Pass Detail.NONE for a mesh
## built without UVs or tangents - normal mapping has no frame to work in there.
static func material(
        color: Color,
        roughness: float = 0.78,
        metallic: float = 0.0,
        detail: int = -1
) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = roughness
    mat.metallic = metallic
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
    mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
    mat.disable_receive_shadows = false
    Detail.apply(
        mat,
        Detail.infer(roughness, metallic) if detail < 0 else detail
    )
    return mat

static func emissive_material(
        color: Color,
        emission_energy: float = 2.5,
        roughness: float = 0.42,
        metallic: float = 0.0
) -> StandardMaterial3D:
    var mat := material(color, roughness, metallic)
    mat.emission_enabled = true
    mat.emission = color
    mat.emission_energy_multiplier = emission_energy
    return mat

static func glass_material(
        tint: Color = Color(0.36, 0.63, 0.72, 0.20),
        roughness: float = 0.12,
        metallic: float = 0.08
) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = tint
    mat.roughness = roughness
    mat.metallic = metallic
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    return mat

static func work_spot(
        parent: Node,
        pos: Vector3,
        aim: Vector3,
        color: Color,
        energy: float,
        range_value: float,
        angle: float = 48.0,
        cast_shadow: bool = false
) -> SpotLight3D:
    var light := SpotLight3D.new()
    light.position = pos
    light.light_color = color
    light.light_energy = energy
    light.light_specular = 0.35
    light.spot_range = range_value
    light.spot_angle = angle
    light.spot_attenuation = 0.58
    light.shadow_enabled = cast_shadow
    light.shadow_bias = 0.04
    light.shadow_normal_bias = 0.8
    light.shadow_blur = 0.7
    parent.add_child(light)
    if parent is Node3D and aim.distance_to(pos) > 0.05:
        var host := parent as Node3D
        var world_aim: Vector3 = host.to_global(aim)
        var dir: Vector3 = world_aim - light.global_position
        if dir.length() > 0.05:
            var up := Vector3.UP
            if absf(dir.normalized().dot(up)) > 0.94:
                up = Vector3.FORWARD
            light.look_at(world_aim, up)
    return light

static func box_mesh(
        size: Vector3,
        color: Color,
        roughness: float = 0.78,
        metallic: float = 0.0,
        detail: int = -1
) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    var node := MeshInstance3D.new()
    node.mesh = mesh
    node.material_override = material(color, roughness, metallic, detail)
    return node

static func cylinder_mesh(
        radius: float,
        height: float,
        color: Color,
        roughness: float = 0.78,
        metallic: float = 0.0,
        detail: int = -1
) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = 16
    var node := MeshInstance3D.new()
    node.mesh = mesh
    node.material_override = material(color, roughness, metallic, detail)
    return node

static func sphere_mesh(
        radius: float,
        color: Color,
        detail: int = -1
) -> MeshInstance3D:
    var mesh := SphereMesh.new()
    mesh.radius = radius
    mesh.height = radius * 2.0
    var node := MeshInstance3D.new()
    node.mesh = mesh
    node.material_override = material(color, 0.78, 0.0, detail)
    return node

static func capsule_mesh(
        radius: float,
        height: float,
        color: Color,
        detail: int = -1
) -> MeshInstance3D:
    var mesh := CapsuleMesh.new()
    mesh.radius = radius
    mesh.height = height
    var node := MeshInstance3D.new()
    node.mesh = mesh
    node.material_override = material(color, 0.78, 0.0, detail)
    return node

static func add_box_collision(
        body: CollisionObject3D,
        size: Vector3
) -> CollisionShape3D:
    var shape := BoxShape3D.new()
    shape.size = size
    var node := CollisionShape3D.new()
    node.shape = shape
    body.add_child(node)
    return node

static func add_cylinder_collision(
        body: CollisionObject3D,
        radius: float,
        height: float
) -> CollisionShape3D:
    var shape := CylinderShape3D.new()
    shape.radius = radius
    shape.height = height
    var node := CollisionShape3D.new()
    node.shape = shape
    body.add_child(node)
    return node

static func add_capsule_collision(
        body: CollisionObject3D,
        radius: float,
        height: float
) -> CollisionShape3D:
    var shape := CapsuleShape3D.new()
    shape.radius = radius
    shape.height = height
    var node := CollisionShape3D.new()
    node.shape = shape
    body.add_child(node)
    return node

static func static_box(
        parent: Node,
        name_text: String,
        position: Vector3,
        size: Vector3,
        color: Color,
        detail: int = -1
) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = name_text
    body.position = position
    parent.add_child(body)
    body.add_child(box_mesh(size, color, 0.78, 0.0, detail))
    add_box_collision(body, size)
    return body


static func add_heightmap_collision(
        body: CollisionObject3D,
        width: int,
        depth: int,
        heights: PackedFloat32Array,
        grid_span: Vector3,
        y_offset: float = 0.0
) -> CollisionShape3D:
    var shape := HeightMapShape3D.new()
    shape.map_width = maxi(width, 2)
    shape.map_depth = maxi(depth, 2)
    shape.map_data = heights
    var node := CollisionShape3D.new()
    node.name = "DeformedHeight"
    node.shape = shape
    node.position.y = y_offset
    var sx := grid_span.x / maxf(float(shape.map_width - 1), 1.0)
    var sz := grid_span.z / maxf(float(shape.map_depth - 1), 1.0)
    node.scale = Vector3(sx, 1.0, sz)
    body.add_child(node)
    return node
