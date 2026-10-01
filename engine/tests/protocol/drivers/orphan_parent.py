import subprocess
import sys
import time
from pathlib import Path

request, pid_path, log_path = sys.argv[1:]
with open(log_path, "wb") as log:
    helper = subprocess.Popen(
        [sys.executable, "-I", "-B", str(Path(__file__).with_name("slow_forge.py")), "forge"],
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=log,
    )
    helper.stdin.write(request.encode())
    helper.stdin.close()
    Path(pid_path).write_text(str(helper.pid))
    time.sleep(0.5)
