import os
import glob
import asyncio
import argparse

import build_script.utils as utils
import build_script.zig_utils as zig_utils

import build_script.libs.sdl as sdl

arg_parser = argparse.ArgumentParser(description="Build script for Zig and C/C++ sources")
arg_parser.add_argument("--build-dir", default="build", help="Directory for build output")
arg_parser.add_argument("--source-dir", default="src", help="Directory for source files")
arg_parser.add_argument("--target", default="native", help="Target architecture")
arg_parser.add_argument("--mode", choices=["debug", "release"], default="debug", help="Build mode")
arg_parser.add_argument("--output", default="app", help="Output binary path")
args = arg_parser.parse_args()

build_dir: str = args.build_dir
source_dir: str = args.source_dir
target: str = args.target
mode: str = args.mode

output =  os.path.join(build_dir, args.output)

is_target_windows = "windows" in target or (target == "native" and os.name == "nt")

utils.ensure_dir(build_dir)

zig_files = [os.path.join(source_dir, "main.zig")]
c_files = glob.glob(os.path.join(source_dir, "**/*.c"), recursive=True)
cpp_files = glob.glob(os.path.join(source_dir, "**/*.cpp"), recursive=True)

opt: list[str] = []

if "linux" in target or (target == "native" and os.name == "posix" and os.uname().sysname == "Linux"):
    import build_script.platform.linux as platform

elif "macos" in target or (target == "native" and os.name == "posix" and os.uname().sysname == "Darwin"):
    import build_script.platform.macos as platform

elif "windows" in target or (target == "native" and os.name == "nt"):
    import build_script.platform.windows as platform

opt = platform.flags(mode, target)

opt += sdl.init_sdl2()

async def limit_thread(semaphore: asyncio.Semaphore, fun, *args, **kwargs):
    async with semaphore:
        return await fun(*args, **kwargs)

async def gather_tasks(*tasks):
    return await asyncio.gather(*tasks)

def compile_sources(zig_files:list[str] = [], c_files:list[str] = [], cpp_files:list[str] = [], opt: list[str] = opt) -> list[str]:
    sem = asyncio.Semaphore(os.cpu_count())
    tasks = []
    for file in zig_files:
        tasks.append(limit_thread(sem, zig_utils.compile_zig_source_async, file, utils.translate_to_build_path_zig(file, source_dir, build_dir), opt))
    for file in c_files:
        tasks.append(limit_thread(sem, zig_utils.compile_c_source_async, file, utils.translate_to_build_path(file, source_dir, build_dir), opt))
    for file in cpp_files:
        tasks.append(limit_thread(sem, zig_utils.compile_cpp_source_async, file, utils.translate_to_build_path(file, source_dir, build_dir), opt))
    return asyncio.run(gather_tasks(*tasks))

list_object = compile_sources(zig_files, c_files, cpp_files, opt)
if is_target_windows:
    list_object = [obj.replace(".o", ".obj") for obj in list_object]
    output += ".exe"
zig_utils.link_executable(list_object, output, opt)