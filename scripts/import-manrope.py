"""Imports Manrope (#455) as /Game/Station/UI/Fonts: one font face per weight and
the `Manrope` font that names them, which StationUi::Font loads.

Runs inside the editor. The raw fonts stay out of the repository, like the
project's other sources: the variable `Manrope[wght].ttf` of google/fonts
(ofl/manrope) cut into static weights with fontTools, because Slate does not read
variable axes (see docs/unreal-setup.md).

Usage (the full editor: the font importer needs Slate, which a commandlet lacks):
  STATION_FONT_DIR=<folder with Manrope-Regular.ttf and the rest> \
    UnrealEditor "$PWD/unreal/ProyectoMed.uproject" \
    -ExecutePythonScript="$PWD/scripts/import-manrope.py" -ExecCmds=Quit \
    -unattended -nullrhi -nosplash
"""

import os

import unreal

DESTINATION = "/Game/Station/UI/Fonts"
# Typeface names, as StationUi.h names them. The files carry the same names.
WEIGHTS = ["Regular", "Medium", "SemiBold", "Bold", "ExtraBold"]


def import_face(folder: str, weight: str) -> str:
    task = unreal.AssetImportTask()
    task.filename = os.path.join(folder, f"Manrope-{weight}.ttf")
    task.destination_path = DESTINATION
    task.destination_name = f"Manrope_{weight}"
    task.automated = True
    task.replace_existing = True
    task.save = True
    unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([task])
    path = f"{DESTINATION}/Manrope_{weight}"
    if not unreal.EditorAssetLibrary.does_asset_exist(path):
        raise RuntimeError(f"{task.filename} was not imported")
    return path


def typeface_text(faces: dict[str, str]) -> str:
    # FFontData's fields are hidden from Python, so the typefaces go in as text.
    entries = ",".join(
        f'(Name="{weight}",Font=(FontFaceAsset="/Script/Engine.FontFace\'{path}.{path.rsplit("/", 1)[1]}\'",SubFaceIndex=0))'
        for weight, path in faces.items()
    )
    return f"(DefaultTypeface=(Fonts=({entries})))"


def main() -> None:
    folder = os.environ["STATION_FONT_DIR"]
    faces = {weight: import_face(folder, weight) for weight in WEIGHTS}

    font_path = f"{DESTINATION}/Manrope"
    font = unreal.EditorAssetLibrary.load_asset(font_path)
    if font is None:
        font = unreal.AssetToolsHelpers.get_asset_tools().create_asset(
            "Manrope", DESTINATION, unreal.Font, unreal.FontFactory()
        )
    font.set_editor_property("font_cache_type", unreal.FontCacheType.RUNTIME)
    composite = unreal.CompositeFont()
    if not composite.import_text(typeface_text(faces)):
        raise RuntimeError("the typefaces did not parse")
    font.set_editor_property("composite_font", composite)
    if not unreal.EditorAssetLibrary.save_loaded_asset(font, only_if_is_dirty=False):
        raise RuntimeError(f"{font_path} was not saved")


main()
