import subprocess
import asyncio
import os

executable = "git"

async def run_git_command(*args):
    command = [executable] + list(args)
    process = await asyncio.create_subprocess_exec(
        *command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    stdout, stderr = await process.communicate()
    return stdout.decode().strip(), stderr.decode().strip(), process.returncode

async def git_clone(repo_url, dest_dir, branch=None, tag=None):
    args = ["clone", repo_url, dest_dir]
    if branch:
        args.extend(["-b", branch])
    if tag:
        args.extend(["--single-branch", "--branch", tag])
    return await run_git_command(*args)
