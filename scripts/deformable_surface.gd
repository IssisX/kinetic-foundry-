class_name DeformableSurface
extends MeshInstance3D

const PLANE_HORIZONTAL := 0
const PLANE_VERTICAL := 1

var network
var grid_columns := 0
var grid_rows := 0
var plane_mode := PLANE_HORIZONTAL
var surface_offset := 0.0
var _tint := Color(0.24, 0.24, 0.22)
var _last_signature := Vector3(INF, INF, INF)

func configure(
        network_ref,
        columns_value: int,
        rows_value: int,
        mode: int,
        tint: Color,
        offset: float = 0.0
) -> void:
    network = network_ref
    grid_columns = maxi(columns_value, 2)
    grid_rows = maxi(rows_value, 2)
    plane_mode = mode
    surface_offset = offset
    _tint = tint
    cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

    var material := StandardMaterial3D.new()
    material.albedo_color = tint
    material.metallic = 0.72
    material.roughness = 0.42
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material_override = material
    sync_from_network(true)

func sync_from_network(force: bool = false) -> void:
    if network == null or not network.has_method("get_node_position"):
        return
    var state: Dictionary = network.get_deformation_state()
    var signature := Vector3(
        float(state.get("max_displacement", 0.0)),
        float(state.get("damage", 0.0)),
        float(state.get("broken_fraction", 0.0))
    )
    if not force and signature.distance_squared_to(_last_signature) < 0.0000006:
        return
    _last_signature = signature
    _rebuild_mesh()

func _rebuild_mesh() -> void:
    var surface_tool := SurfaceTool.new()
    surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

    for row: int in grid_rows:
        var v := float(row) / float(grid_rows - 1)
        for column: int in grid_columns:
            var u := float(column) / float(grid_columns - 1)
            var node_position: Vector3 = network.get_node_position(column, row)
            surface_tool.set_uv(Vector2(u, v))
            surface_tool.add_vertex(_map_point(node_position))

    for row: int in grid_rows - 1:
        for column: int in grid_columns - 1:
            var i00 := row * grid_columns + column
            var i10 := i00 + 1
            var i01 := (row + 1) * grid_columns + column
            var i11 := i01 + 1
            surface_tool.add_index(i00)
            surface_tool.add_index(i10)
            surface_tool.add_index(i11)
            surface_tool.add_index(i00)
            surface_tool.add_index(i11)
            surface_tool.add_index(i01)

    surface_tool.generate_normals()
    mesh = surface_tool.commit()

func _map_point(point: Vector3) -> Vector3:
    if plane_mode == PLANE_VERTICAL:
        return Vector3(
            point.x,
            point.z,
            surface_offset + point.y
        )
    return Vector3(
        point.x,
        surface_offset + point.y,
        point.z
    )
