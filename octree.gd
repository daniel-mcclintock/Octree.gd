class_name Octree
extends Reference
# Shitty Octree for spatially storing data

var _center : Vector3
var _size : float
var _half_size : float
var _aabb

var _data: Dictionary = {}
var _positions: Array = []
var _children : Array = []

var _item_count : int = 0
var max_items : int

func _init(center: Vector3 = Vector3.ZERO, size: float = 1.0, _max_items: int = 1000):
    max_items = _max_items

    _center = center
    _size = size
    _half_size = _size * 0.5

func data_count() -> int:
    if not _children.is_empty():
        var count = 0
        for child in _children:
            count += child.data_count()

        return count
    else:
        return _positions.size()

func _get_aabb() -> AABB:
    # Generate, store and return AABB for native intersection math
    if _aabb:
        return _aabb

    _aabb = AABB(_center - Vector3.ONE * _half_size, Vector3.ONE * _size)
    return _aabb

func check_bounds_point(vec: Vector3) -> bool:
    return _get_aabb().has_point(vec)

func add(position : Vector3, data, mtx : Mutex) -> bool:
    # Add data to this Node for a given Vector3 position
    #
    # Args:
    #     position: The position to store the given data for
    #     data: A object/variant to store in the Octree
    #     mtx: A Mutex to lock the Octree for threaded insertions
    if not _children.is_empty():
        # We have children so offload to them
        mtx.lock()
        var child = _get_child(position)
        mtx.unlock()

        if child == null:
            # Position is outside of Octree Node area
            return false

        return child.add(position, data, mtx)
    else:
        # Add this request payload to appropriate child
        # Store in _data
        mtx.lock()

        if _positions.has(position):
            # we already have this position
            mtx.unlock()
            return false

        _positions.append(position)
        _data[position] = data
        _item_count += 1

        if _item_count == max_items:
            # Too much data, spawn children and shuffle data to them
            _create_children()

            # Transfor data from this node into its children
            for key in _data.keys():
                var child = _get_child(position)
                child._positions.append(position)
                child._data[position] = data
                child._item_count += 1

            _data.clear()
            _positions.clear()
            _item_count = 0

        mtx.unlock()
        return true

func _get_child(position : Vector3) -> Octree:
    # Given a Vector3 position, determine which of this Node's children would store that position
    var oct = 0

    if position.x >= _center.x:
        oct |= 4

    if position.y >= _center.y:
        oct |= 2

    if position.z >= _center.z:
        oct |= 1

    return _children[oct]

func _create_children() -> void:
    # Create child Nodes for this Octree Node, produces 8 octant children Nodes.
    var n_size = _half_size
    var n_hsize = n_size * 0.5
#
    for i in range(0, 8):
        var n_center = _center
        if i&4:
            n_center.x += n_size * 0.5
        else:
            n_center.x += n_size * -0.5

        if i&2:
            n_center.y += n_size * 0.5
        else:
            n_center.y += n_size * -0.5

        if i&1:
            n_center.z += n_size * 0.5
        else:
            n_center.z += n_size * -0.5

        _children.append(
            Octree.new(n_center, n_size, max_items)
        )

func _ray_nodes(origin: Vector3, direction: Vector3, grow: float = 0.0) -> Array:
    # Given a ray (origin, direction) find all intersecting octree nodes.
    #
    # Args:
    #     origin: The start position of the ray
    #     direction: The direction of the ray
    #     grow: Value to increase the size of each Node's AABB when picking ray intersections,
    #           this is useful when a given ray would exclude a Node that would otherwise include
    #           positions for a given search radius(see: searcher.gd)
    if _children.is_empty():
        # This node has no children and therefore stores data, return self
        if _get_aabb().grow(grow).intersects_ray(origin, direction):
            return [self]
    else:
        # This node has children, we should check with its children if the ray intersects
        var c = []
        for child in _children:
            var r = child._ray_nodes(origin, direction, grow)
            if r:
                c += r
        return c

    return []

func _aabb_nodes(aabb: AABB) -> Array:
    # Given an AABB, find all intersecting Octree nodes.
    #
    # Args:
    #     aabb: The AABB to find all intersecting Nodes for.
    if _children.is_empty():
        # This node has no children and therefore stores data, return self
        if _get_aabb().intersects(aabb):
            return [self]
    else:
        # This node has children, we should check with its children if the ray intersects
        var c = []
        for child in _children:
            var r = child._aabb_nodes(aabb)
            if r:
                c += r
        return c
    return []
