import os
import shutil

def ensure_dir(dir):
    if os.path.exists(dir):
        shutil.rmtree(dir)
    os.makedirs(dir)

def translate_to_build_path(file_path: str, source_dir: str, build_dir: str) -> str:
    relative_path = os.path.relpath(file_path, source_dir)
    relative_path = relative_path.replace('\\', '/')
    relative_path = relative_path.rsplit('.', 1)[0] + ".o"
    build_path = os.path.join(build_dir, relative_path)
    os.makedirs(os.path.dirname(build_path), exist_ok=True)
    return build_path

def translate_to_build_path_zig(file_path: str, source_dir: str, build_dir: str) -> str:
    relative_path = os.path.relpath(file_path, source_dir)
    relative_path = relative_path.replace('\\', '/')
    relative_path = relative_path.rsplit('.', 1)[0]
    build_path = os.path.join(build_dir, relative_path)
    os.makedirs(os.path.dirname(build_path), exist_ok=True)
    return build_path