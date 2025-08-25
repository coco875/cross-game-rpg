from .. import zig_utils 

def flags(mode: str, target: str) -> list[str]:
    if mode == "debug":
        opt = ["-O", zig_utils.DEBUG]
    else:
        opt = ["-O", zig_utils.RELEASE_SAFE]
    opt += ["-target", target]
    opt += ["-ladvapi32", "-lkernel32", "-lntdll", "-luser32", "-lshell32"]
    return opt
