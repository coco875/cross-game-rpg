from .. import pkg_config_utils

def init_sdl2():
    if not pkg_config_utils.pkg_config_exists("sdl2"):
        raise RuntimeError("SDL2 not found via pkg-config. Please install SDL2 development files.")
    else:
        cflags = pkg_config_utils.get_pkg_config_cflags("sdl2")
        return cflags
