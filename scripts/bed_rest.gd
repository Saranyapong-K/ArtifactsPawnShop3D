extends Area3D
var manager: Node
func interact(_actor: Node) -> void:
	if manager: manager.request_sleep()
