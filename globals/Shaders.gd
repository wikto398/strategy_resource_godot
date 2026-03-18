extends Node

var shaders = {
    "hovered": preload("uid://c0myfrirxtnrj")
}

var materials = {}

func load_shader(shader_name: String) -> Material:
    if shader_name in materials:
        return materials[shader_name]
    var material = ShaderMaterial.new()
    material.shader = shaders.get(shader_name)
    if not material.shader:
        DebugLogger.error("Shader not found: " + shader_name)
        return null
    materials[shader_name] = material
    return material
