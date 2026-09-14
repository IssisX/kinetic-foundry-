extends Node3D

## The visible half of the process plant.
##
## Every run and every valve here is built from the graph's own declaration,
## so there is exactly one statement of what the yard is plumbed like. Move
## a route in ProcessPlant and the steel moves with it.

const ProcessPipeScript = preload("res://scripts/process_pipe.gd")
const ProcessValveScript = preload("res://scripts/process_valve.gd")
const GeomUtil = preload("res://scripts/geom.gd")


func _ready() -> void:
    name = "ProcessPlumbing"
    _build_runs()
    _build_valves()


func _build_runs() -> void:
    for spec in ProcessPlant.route_specs():
        var pipe := ProcessPipeScript.new()
        pipe.name = "Pipe_%s" % str(spec.edge)
        add_child(pipe)
        pipe.configure(
            spec.from as Vector3,
            spec.to as Vector3,
            float(spec.radius),
            str(spec.edge)
        )
        _build_supports(spec.from as Vector3, spec.to as Vector3)


## Rack stands under the horizontal runs. Purely structural dressing, but a
## pipe hanging in mid-air reads as a prop rather than as plant.
func _build_supports(from_point: Vector3, to_point: Vector3) -> void:
    var span := to_point - from_point
    var horizontal := Vector2(span.x, span.z).length()
    if horizontal < 4.0:
        return
    var stands := clampi(int(horizontal / 7.0), 1, 5)
    for i in stands:
        var t := (float(i) + 0.5) / float(stands)
        var point := from_point.lerp(to_point, t)
        var height := maxf(point.y - 0.2, 0.4)
        var post := GeomUtil.box_mesh(
            Vector3(0.18, height, 0.18),
            Color(0.22, 0.23, 0.21),
            0.82,
            0.28
        )
        post.position = Vector3(point.x, height * 0.5, point.z)
        add_child(post)
        var cradle := GeomUtil.box_mesh(
            Vector3(0.62, 0.09, 0.30),
            Color(0.30, 0.31, 0.28),
            0.80,
            0.30
        )
        cradle.position = Vector3(point.x, height + 0.02, point.z)
        add_child(cradle)


func _build_valves() -> void:
    for site in ProcessPlant.valve_specs():
        var edge_id := str(site.edge)
        var valve := ProcessValveScript.new()
        valve.name = "Valve_%s" % edge_id
        add_child(valve)
        valve.configure(
            site.position as Vector3,
            edge_id,
            ProcessPlant.edge_label(ProcessPlant.edge_index(edge_id))
        )
        var riser_height: float = maxf(float((site.position as Vector3).y) - 0.3, 0.4)
        var riser := GeomUtil.cylinder_mesh(
            0.09,
            riser_height,
            Color(0.24, 0.25, 0.23),
            0.78,
            0.32
        )
        riser.position = Vector3(
            (site.position as Vector3).x,
            riser_height * 0.5,
            (site.position as Vector3).z
        )
        add_child(riser)
