import sys
import time

import fpengine.cli
from fpengine.protocol.events import EventWriter

original = EventWriter.terminal


def pause(self, *args, **kwargs):
    original(self, *args, **kwargs)
    time.sleep(2)


EventWriter.terminal = pause
raise SystemExit(fpengine.cli.main(sys.argv[1:]))
