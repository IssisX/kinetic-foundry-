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
