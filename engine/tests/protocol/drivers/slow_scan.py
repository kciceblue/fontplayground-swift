import sys
import time

import fpengine.cli
import fpengine.commands.scan

original = fpengine.commands.scan.read_faces


def slow(path):
    time.sleep(0.5)
    return original(path)


fpengine.commands.scan.read_faces = slow
raise SystemExit(fpengine.cli.main(sys.argv[1:]))
