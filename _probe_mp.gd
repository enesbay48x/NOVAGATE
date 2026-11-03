extends Node
# Tek process'te coklu MultiplayerAPI mumkun mu? probe:
func _ready() -> void:
	var n := Node.new()
	var sm := SceneMultiplayer.new()
	n.set("multiplayer", sm)
	var after: Variant = n.get("multiplayer")
	print("PROBE set-multiplayer=", ("SETTLED-OBJECT" if after != null else "NULL"), " sa=" + str(sm == after))
	var child := Node.new()
	n.add_child(child)
	var cm: Variant = child.get("multiplayer")
	print("PROBE child-multiplayer=", ("INHERITED" if cm == sm else ("NULL" if cm == null else "other")))
	get_tree().quit(0)
