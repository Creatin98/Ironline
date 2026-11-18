"""Static sanity checks for the Godot project (no Godot binary required).

Checks:
  * every res:// path referenced in .tscn/.tres/.gd/project.godot exists
  * every ExtResource("id") / SubResource("id") in a scene/resource is declared
  * every $NodePath / @onready get_node path in a script attached to a scene node resolves
  * GDScript files: tab indentation, balanced brackets, no mixed indentation
  * class_name / type references resolve to project classes or known engine classes

Run from the project root:  py -3 tools/validate_project.py
Exit code 0 = no errors.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
errors = []
warnings = []

ENGINE_CLASSES = set("""
Node Node2D Node3D Control CanvasLayer CanvasItem Label Label3D Button CheckBox OptionButton HSlider LineEdit
RichTextLabel ColorRect PanelContainer VBoxContainer HBoxContainer GridContainer BoxContainer Container
StyleBoxFlat StyleBox Theme Font Resource RefCounted Object PackedScene SceneTree SceneTreeTimer Tween
CharacterBody3D RigidBody3D StaticBody3D Area3D CollisionShape3D CapsuleShape3D BoxShape3D SphereShape3D
CylinderShape3D Shape3D MeshInstance3D BoxMesh CapsuleMesh SphereMesh CylinderMesh QuadMesh Mesh ArrayMesh PlaneMesh SurfaceTool OmniLight3D MultiMesh MultiMeshInstance3D Curve Gradient CanvasItemMaterial SpotLight3D GradientTexture2D ShaderMaterial Shader CPUParticles3D QuadMesh
Camera3D Marker3D OmniLight3D DirectionalLight3D WorldEnvironment Environment Sky ProceduralSkyMaterial
StandardMaterial3D BaseMaterial3D Material GeometryInstance3D CPUParticles3D GPUParticles3D Gradient
AudioStreamPlayer AudioStreamPlayer3D AudioStream AudioStreamWAV AudioServer AudioBusLayout
PhysicsDirectSpaceState3D PhysicsRayQueryParameters3D PhysicsMaterial World3D RenderingServer Viewport
Input InputEvent InputEventMouseMotion InputEventMouseButton InputEventKey InputMap DisplayServer
Engine Time OS ConfigFile DirAccess FileAccess ResourceLoader ResourceSaver Callable Signal Variant
Vector2 Vector2i Vector3 Vector3i Vector4 Color Basis Transform3D Transform2D Quaternion Plane AABB Rect2
Array Dictionary String StringName NodePath RID PackedStringArray PackedFloat32Array PackedColorArray
PackedByteArray PackedInt32Array PackedVector3Array int float bool void TextServer MultiplayerAPI
MultiplayerPeer ENetMultiplayerPeer OfflineMultiplayerPeer NavigationRegion3D NavigationAgent3D
NavigationServer3D NavigationMesh RayCast3D Timer AnimationPlayer Decal ShapeCast3D Texture2D
Generic6DOFJoint3D PhysicsMaterial VisualInstance3D Viewport AudioEffectLowPassFilter AudioEffectAmplify AudioEffectFilter AudioEffectLimiter OmniLight3D CPUParticles3D CylinderMesh SphereMesh GradientTexture1D Script GDScript CenterContainer TextureRect ScrollContainer MarginContainer SubViewport SubViewportContainer Image ImageTexture Panel TabContainer AspectRatioContainer Marker2D Line2D Basis GradientTexture2D Gradient KinematicCollision3D ShaderMaterial Shader AABB AudioStreamMP3 RandomNumberGenerator CollisionObject3D PackedVector2Array AudioEffectLimiter PhysicsShapeQueryParameters3D Sprite3D Basis InputEventAction SurfaceTool ArrayMesh, PrimitiveMesh CheckButton ButtonGroup
""".split())

GD_TYPE_PATTERN = re.compile(r"(?::[ \t]*|\bas[ \t]+|\bextends[ \t]+|\bis[ \t]+)([A-Z][A-Za-z0-9_]*)")
LOCAL_NAME_PATTERN = re.compile(r"^\s*(?:enum|const)\s+([A-Za-z_][A-Za-z0-9_]*)", re.M)
NEW_PATTERN = re.compile(r"\b([A-Z][A-Za-z0-9_]*)\.new\(")
RES_PATH_PATTERN = re.compile(r'res://[A-Za-z0-9_\-./]+')


def rel(path):
    return os.path.relpath(path, ROOT).replace("\\", "/")


def walk(exts):
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if not d.startswith(".") and d != "__pycache__"]
        for fn in filenames:
            if os.path.splitext(fn)[1] in exts:
                yield os.path.join(dirpath, fn)


def check_res_paths(path, text):
    for m in RES_PATH_PATTERN.finditer(text):
        p = m.group(0)
        # strip trailing punctuation that regex may catch
        p = p.rstrip(".")
        local = os.path.join(ROOT, p[len("res://"):].replace("/", os.sep))
        if p.endswith("/"):
            if not os.path.isdir(local):
                errors.append(f"{rel(path)}: Ordner fehlt: {p}")
            continue
        if not os.path.exists(local):
            # dynamic prefixes (e.g. SFX_DIR + name) are fine if the directory exists
            if os.path.isdir(os.path.dirname(local)) and "." not in os.path.basename(p):
                continue
            errors.append(f"{rel(path)}: Datei fehlt: {p}")


def parse_scene_nodes(text):
    """Returns dict of node full paths ('.' root) -> type, and declared ext/sub ids."""
    ext_ids = set(re.findall(r'\[ext_resource [^\]]*id="([^"]+)"', text))
    sub_ids = set(re.findall(r'\[sub_resource [^\]]*id="([^"]+)"', text))
    nodes = {}
    scripts = {}
    for m in re.finditer(r'\[node name="([^"]+)"(?: type="([^"]+)")?(?: parent="([^"]+)")?[^\]]*\]([^\[]*)', text):
        name, ntype, parent, body = m.group(1), m.group(2), m.group(3), m.group(4)
        if parent is None:
            full = "."
        elif parent == ".":
            full = name
        else:
            full = parent + "/" + name
        nodes[full] = ntype or "PackedScene"
        sm = re.search(r'script = ExtResource\("([^"]+)"\)', body)
        if sm:
            scripts[full] = sm.group(1)
    ext_paths = dict(re.findall(r'\[ext_resource [^\]]*path="([^"]+)" id="([^"]+)"', text))
    ext_paths = {v: k for k, v in ext_paths.items()}
    return nodes, scripts, ext_ids, sub_ids, ext_paths


def check_scene(path, text):
    nodes, scripts, ext_ids, sub_ids, ext_paths = parse_scene_nodes(text)
    for m in re.finditer(r'ExtResource\("([^"]+)"\)', text):
        if m.group(1) not in ext_ids:
            errors.append(f"{rel(path)}: ExtResource-ID nicht deklariert: {m.group(1)}")
    for m in re.finditer(r'SubResource\("([^"]+)"\)', text):
        if m.group(1) not in sub_ids:
            errors.append(f"{rel(path)}: SubResource-ID nicht deklariert: {m.group(1)}")
    # node path references from scripts attached in this scene
    for node_full, script_id in scripts.items():
        script_path = ext_paths.get(script_id)
        if not script_path:
            continue
        local = os.path.join(ROOT, script_path[len("res://"):].replace("/", os.sep))
        if not os.path.exists(local):
            continue
        with open(local, encoding="utf-8") as f:
            script_text = f.read()
        for m in re.finditer(r'\$([A-Za-z0-9_/]+)', script_text):
            np = m.group(1)
            target = np if node_full == "." else node_full + "/" + np
            if target not in nodes:
                errors.append(f"{rel(path)}: Script {script_path} referenziert $'{np}', Node fehlt in Szene")
    return nodes


def check_gdscript(path, text, class_names):
    lines = text.split("\n")
    depth_round = depth_square = depth_curly = 0
    in_string = False
    for i, line in enumerate(lines, 1):
        stripped = line.lstrip("\t")
        if stripped.startswith(" ") and stripped.strip():
            errors.append(f"{rel(path)}:{i}: Leerzeichen-Einrueckung (Tabs erwartet)")
        # crude bracket balance ignoring strings/comments
        code = re.sub(r'"(?:\\.|[^"\\])*"', '""', line)
        code = re.sub(r"'(?:\\.|[^'\\])*'", "''", code)
        code = code.split("#")[0]
        depth_round += code.count("(") - code.count(")")
        depth_square += code.count("[") - code.count("]")
        depth_curly += code.count("{") - code.count("}")
        if depth_round < 0 or depth_square < 0 or depth_curly < 0:
            errors.append(f"{rel(path)}:{i}: Klammer schliesst ohne Oeffnung")
            depth_round = max(depth_round, 0)
            depth_square = max(depth_square, 0)
            depth_curly = max(depth_curly, 0)
    if depth_round or depth_square or depth_curly:
        errors.append(f"{rel(path)}: unbalancierte Klammern am Dateiende ({depth_round},{depth_square},{depth_curly})")
    # type references
    code_only = "\n".join(l.split("#")[0] for l in lines)
    code_only = re.sub(r'"(?:\\.|[^"\\])*"', '""', code_only)
    local_names = set(LOCAL_NAME_PATTERN.findall(code_only))
    for pat in (GD_TYPE_PATTERN, NEW_PATTERN):
        for m in pat.finditer(code_only):
            name = m.group(1)
            if name in ENGINE_CLASSES or name in class_names or name in local_names:
                continue
            if name in ("Array", "Dictionary"):
                continue
            # enum-like constant access (Teams.Team) is handled: only flag bare type contexts
            errors.append(f"{rel(path)}: unbekannter Typ/Klasse '{name}'")


def main():
    class_names = set()
    autoloads = set()
    gd_files = list(walk({".gd"}))
    for p in gd_files:
        with open(p, encoding="utf-8") as f:
            t = f.read()
        m = re.search(r"^class_name\s+([A-Za-z0-9_]+)", t, re.M)
        if m:
            class_names.add(m.group(1))
    project = os.path.join(ROOT, "project.godot")
    with open(project, encoding="utf-8") as f:
        ptext = f.read()
    for m in re.finditer(r'^([A-Za-z0-9_]+)="\*?(res://[^"]+)"', ptext, re.M):
        autoloads.add(m.group(1))
    class_names |= autoloads
    check_res_paths(project, ptext)

    for p in walk({".tscn", ".tres"}):
        with open(p, encoding="utf-8") as f:
            t = f.read()
        check_res_paths(p, t)
        check_scene(p, t)
    for p in gd_files:
        with open(p, encoding="utf-8") as f:
            t = f.read()
        check_res_paths(p, t)
        check_gdscript(p, t, class_names)

    # autoload scripts must not declare class_name (Godot forbids it for singletons)
    for m in re.finditer(r'^([A-Za-z0-9_]+)="\*?(res://[^"]+)"', ptext, re.M):
        local = os.path.join(ROOT, m.group(2)[len("res://"):].replace("/", os.sep))
        if os.path.exists(local):
            with open(local, encoding="utf-8") as f:
                if re.search(r"^class_name", f.read(), re.M):
                    errors.append(f"{rel(local)}: Autoload-Skript darf kein class_name haben")

    print(f"Skripte: {len(gd_files)}, Klassen: {len(class_names - autoloads)}, Autoloads: {len(autoloads)}")
    for w in warnings:
        print("WARNUNG:", w)
    for e in errors:
        print("FEHLER:", e)
    print("Ergebnis:", "OK" if not errors else f"{len(errors)} Fehler")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
