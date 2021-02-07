class_name Octree
extends Reference
# Top level Octree Node wrapper
# It provides some convenience when working with heavy Nodes.
# - Node structure is split 2 level deep (8*8) for easier threaded searches and insertions.
# - Matching Node Mutexes are created to ease in threaded searching
# - Search wrapper functions are provided

# The actual top-level OctreeNode
var _octree : OctreeNode

# The effectively 8*8 top-level OctreeNodes
var _octant_nodes : Array = []
var _octant_mutexes : Array = []

func _init(center: Vector3 = Vector3.ZERO, size: float = 1.0, max_items: int = 1000):
    _create_storage(size, center, max_items)

func _create_storage(size: float, center: Vector3, max_items: int) -> void:
    # Create Node storage that is split 2 level deep (8*8)
    # Create Mutexes for threaded searching and insertions
    _octant_mutexes = []
    _octant_nodes = []

    _octree = OctreeNode.new(center, size, max_items)
    _octree._create_octant_nodes()

    for node in _octree._octant_nodes:
        node._create_octant_nodes()

        # Use nested Arrays so that we can still use OctreeNode._get_octant_index
        _octant_nodes.append(node._octant_nodes)
        _octant_mutexes.append(
            [
                Mutex.new(),
                Mutex.new(),
                Mutex.new(),
                Mutex.new(),
                Mutex.new(),
                Mutex.new(),
                Mutex.new(),
                Mutex.new()
            ]
        )

func _get_flat_storage_array() -> Array:
    # Just to make it easier to use the searcher
    var nodes := []
    for _octant_node_array in _octant_nodes:
        nodes += _octant_node_array

    return nodes

func _get_flat_mutex_array() -> Array:
    var mutexes := []
    for _octant_mutex_array in _octant_mutexes:
        mutexes += _octant_mutex_array

    return mutexes

func data_count() -> int:
    # Convenience method to help query stored data size
    if not _octant_nodes.is_empty():
        var count = 0
        for octant_array in _octant_nodes:
            for node in octant_array:

                count += node.data_count()

        return count

    return 0

func add(position : Vector3, data) -> bool:
    # Wrapper method around the underlying OctreeNode's Add method
    # It *should* be safe to use this from Threads
    var octant_index_1 = OctreeNode._get_octant_index(position, _octree._center)
    var octant_index_2 = OctreeNode._get_octant_index(
        position, _octree._octant_nodes[octant_index_1]._center
    )

    return _octant_nodes[octant_index_1][octant_index_2].add(
        position, data, _octant_mutexes[octant_index_1][octant_index_2]
    )
