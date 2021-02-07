class_name OctreeSearcher
extends Reference

var _octrees: Array
var _mutexes: Array
var _thread_queue: ThreadQueue

var _mtx := Mutex.new()
var _searching := false
var _search_steps := 0
var _search_steps_complete := 0
var _search_results := []
var _search_nodes := []

var _current_callback: Callable
var _current_sort_origin: Vector3

# Used to skip unnessary search requests by excessive callers.
# This is a bit messy and could be tightened up
var last_camera : Camera3D
var last_camera_origin := Vector3.ZERO
var last_camera_forward := Vector3.ZERO
var last_radial_distance := 0.0
var last_mouse_position := Vector2.ZERO
var last_cone := 0.0
var last_ray_origin := Vector3.ZERO

# Used to grow the search area when searches do not find any results, useful for approximate picking
var radial_distance_accumulator := 0.0

var search_start_time := 0.0
var attempts = 0

func _init(octree: Octree, thread_queue: ThreadQueue):
    _octrees = octree._get_flat_storage_array()
    _mutexes = octree._get_flat_mutex_array()
    _thread_queue = thread_queue

func _callback(results: Array) -> void:
    _mtx.lock()

    if _search_steps > 0:
        _search_steps_complete += 1
        _search_results += results[0]
        _search_nodes += results[1]

        if _search_steps == _search_steps_complete:
            _search_steps = 0
            _search_steps_complete = 0
            _searching = false
            _search_results.sort_custom(sort_radial)
            _current_callback.call_deferred(_search_results, _search_nodes)


            if _search_results.is_empty():
                if radial_distance_accumulator == 0.0:
                    radial_distance_accumulator = last_radial_distance

                radial_distance_accumulator *= 2.0
                attempts += 1
            else:
                print(
                    "attempts: %s\tmsecs: %s\tradial_accumulator: %s" %
                    [attempts, OS.get_ticks_msec() - search_start_time, radial_distance_accumulator]
                )
                attempts = 0

    _mtx.unlock()

func camera_volume_ray(camera: Camera3D, cone: float, radial_distance: float, callback: Callable) -> int:
    _mtx.lock()
    if _searching:
        _mtx.unlock()
        return ERR_BUSY

    if _octrees:
        search_start_time = OS.get_ticks_msec()
        _searching = true
        _current_sort_origin = camera.global_transform.origin
        _search_steps = 0
        _search_steps_complete = 0

        var camera_forward = camera.global_transform.basis.z
        var mouse_position = camera.get_viewport().get_mouse_position()

        if (_current_sort_origin == last_camera_origin and
            camera_forward == last_camera_forward and
            radial_distance == last_radial_distance and
            cone == last_cone and
            last_mouse_position == mouse_position):
                if not _search_results.is_empty() or attempts >= 20:
                    last_radial_distance = radial_distance
                    last_camera_origin = _current_sort_origin
                    last_camera_forward = camera_forward
                    last_mouse_position = mouse_position
                    last_camera = camera
                    last_cone = cone
                    _searching = false
                    _mtx.unlock()
                    # The caller should already have the results
                    return OK

        else:
            radial_distance_accumulator = 0.0

        _current_callback = callback
        _search_results = []
        _search_nodes = []
        last_radial_distance = radial_distance
        last_camera_origin = _current_sort_origin
        last_camera_forward = camera_forward
        last_mouse_position = mouse_position
        last_camera = camera
        last_cone = cone

        for offset in [
            Vector2.ZERO,
        ]:
            var ray_origin = camera.project_position(
                mouse_position + (offset * cone), camera.near
               )
            last_ray_origin = ray_origin


            var ray_normal = camera.project_ray_normal(
                mouse_position + (offset * cone)
            )

            for o in _octrees:
                _search_steps += 1
                _thread_queue.add_job(_ray_hits, _callback, [o, ray_origin, ray_normal, camera, radial_distance + radial_distance_accumulator])

        _thread_queue.start()
    _mtx.unlock()
    return OK


func _ray_hits(args) -> Array:
    # Single argument wrapper around Octree._ray_nodes
    var node = args[0]
    var origin: Vector3 = args[1]
    var normal: Vector3 = args[2]
    var camera: Camera3D = args[3]
    var radial_distance: float = args[4]

    var hits := []
    var nodes := []

    for o in node._ray_nodes(origin, normal, radial_distance * 0.5):
        if o._item_count > 0:
            nodes.append(o)
            for position in o._data.keys():
                var dist = _dist_of_nearest_point_along_ray_segment(
                    origin, origin + (normal * Global.galaxy_scale * 2), position
                )

                # exclude behind camera
                if (dist[0] < radial_distance * dist[1]) and not camera.is_position_behind(position):
                    hits.append([o._data[position], dist[0], dist[1]])

    return [hits, nodes]

func sort_distance(a, b) -> bool:
    # sort based on distance to the ray origin
    return (
        a[1].distance_squared_to(_current_sort_origin) >
        b[1].distance_squared_to(_current_sort_origin)
    )

func sort_radial(a, b) -> bool:
    # sort based on distance to the ray
    # div by distance along ray to remove bias to nearer points
    return (a[1] / a[2]) < (b[1] / b[2])


func _dist_of_nearest_point_along_ray_segment(
        start : Vector3, end : Vector3, point : Vector3
    ) -> Array:
    # returns array == [dist_to_ray, dist_along_ray]
    # Given a ray segment (start, end) calculate the distance of the closest
    var dir : Vector3 = (start - end).normalized()
    var v : Vector3 = point - start
    var d : float = v.dot(dir)

    return [
        abs(point.distance_to(start + dir * d)),
        abs(d),
    ]
