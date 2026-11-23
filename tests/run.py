import os
import sys
from lupa import luajit21 as lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(HERE)
SOURCE_EXTENSIONS = (".lua", ".toc")


def toc_files():
    files = []
    with open(os.path.join(ADDON, "RemindMeWhen.toc"), encoding="ascii") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                files.append(line)
    return files


def main():
    failures = 0
    for name in os.listdir(ADDON):
        if not name.endswith(SOURCE_EXTENSIONS):
            continue
        data = open(os.path.join(ADDON, name), "rb").read()
        bad = [i for i, b in enumerate(data) if b > 127]
        if bad:
            print("NON-ASCII", name, bad[:5])
            failures += 1

    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().TEST_DIR = HERE
    lua.execute(open(os.path.join(HERE, "stubs.lua"), encoding="ascii").read())
    for name in toc_files():
        source = open(os.path.join(ADDON, name), encoding="ascii").read()
        ok, err = lua.eval("function(src, name) local f, e = loadstring(src, name); if not f then return false, e end; return true, nil end")(source, "@" + name)
        if not ok:
            print("SYNTAX", err)
            failures += 1
        else:
            lua.globals().LoadAddonFile(source, name)
    if failures:
        sys.exit(1)
    scenario = sys.argv[1] if len(sys.argv) > 1 else "scenario.lua"
    lua.execute(open(os.path.join(HERE, scenario), encoding="ascii").read())
    print("ALL OK")


main()
