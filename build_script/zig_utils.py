import subprocess
import asyncio
import os
from typing import Optional

from . import utils

c_compiler = ["zig", "cc"]
cxx_compiler = ["zig", "c++"]
zig_compiler = ["zig", "build-obj"]

zig_compile_executable = ["zig", "build-exe"]

DEBUG = "Debug"
RELEASE_SAFE = "ReleaseSafe"
RELEASE_FAST = "ReleaseFast"
RELEASE_SMALL = "ReleaseSmall"

def get_zig_version() -> str:
    result = subprocess.run(["zig", "version"], capture_output=True, text=True)
    return result.stdout.strip()

def set_optimization_level(level: str):
    global opt_level
    if level in [DEBUG, RELEASE_SAFE, RELEASE_FAST, RELEASE_SMALL]:
        opt_level = level
    else:
        raise ValueError("Invalid optimization level")

def get_optimization_level() -> str:
    return opt_level

async def compile_source_c_cpp_async(file_path: str, compiler: list[str], output_file: Optional[str] = None, option: list[str] = []) -> str:
    if output_file is None:
        output_file = utils.translate_to_build_path(file_path, "src", "build")
    print("Compile:", file_path, "->", output_file)
    command = compiler + option + [file_path, "-o", output_file]
    res = await asyncio.subprocess.create_subprocess_exec(*command)
    if res.returncode != 0:
        raise RuntimeError(f"Compilation failed for {file_path}")
    return output_file

async def compile_c_source_async(file_path: str, output_file: Optional[str] = None, option: list[str] = []) -> str:
    return await compile_source_c_cpp_async(file_path, c_compiler, output_file, option)

async def compile_cpp_source_async(file_path: str, output_file: Optional[str] = None, option: list[str] = []) -> str:
    return await compile_source_c_cpp_async(file_path, cxx_compiler, output_file, option)

async def compile_zig_source_async(file_path: str, output_file: Optional[str] = None, option: list[str] = []) -> str:
    if output_file is None:
        output_file = utils.translate_to_build_path(file_path, "src", "build")
    print("Compile:", file_path, "->", output_file + ".o")
    command = zig_compiler + option + [file_path, f"-femit-bin={output_file}"]
    cmd_stdout = asyncio.subprocess.PIPE
    res = await asyncio.subprocess.create_subprocess_exec(*command, stdout=cmd_stdout, stderr=cmd_stdout, cwd=os.path.realpath("."))
    await res.wait()
    if res.returncode != 0:
        out = await res.stdout.read()
        err = await res.stderr.read()
        print(out.decode())
        print(err.decode())
        print(" ".join(command))
        raise RuntimeError(f"Compilation failed for {file_path}")
    return output_file + ".o"

async def link_executable_async(object_files: list[str], output_executable: str, option: list[str] = []) -> str:
    command = zig_compile_executable + [f"-femit-bin={output_executable}"] + object_files + option
    cmd_stdout = asyncio.subprocess.PIPE
    print("Compile:", " + ".join(object_files), "->", output_executable)
    res = await asyncio.subprocess.create_subprocess_exec(*command, stdout=cmd_stdout, stderr=cmd_stdout, cwd=os.path.realpath("."))
    await res.wait()
    if res.returncode != 0:
        out = await res.stdout.read()
        err = await res.stderr.read()
        print(out.decode())
        print(err.decode())
        print(" ".join(command))
        raise RuntimeError(f"Linking failed for {output_executable}")
    return output_executable

def link_executable(object_files: list[str], output_executable: str, option: list[str] = []) -> str:
    return asyncio.run(link_executable_async(object_files, output_executable, option))