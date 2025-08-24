import subprocess

def pkg_config_exists(package_name: str) -> bool:
    try:
        subprocess.run(["pkg-config", "--exists", package_name], check=True)
        return True
    except subprocess.CalledProcessError:
        return False

def get_pkg_config_cflags(package_name: str) -> list[str]:
    try:
        result = subprocess.run(["pkg-config", "--cflags", "--libs", package_name], capture_output=True, text=True, check=True)
        return result.stdout.split()
    except subprocess.CalledProcessError:
        return []

def get_pkg_config_libs(package_name: str) -> list[str]:
    try:
        result = subprocess.run(["pkg-config", "--libs", package_name], capture_output=True, text=True, check=True)
        return result.stdout.split()
    except subprocess.CalledProcessError:
        return []