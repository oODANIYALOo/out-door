import os
import re
import subprocess
from django.conf import settings
class DockerManagerService:

    def __init__(self):
        # مسیر مطلق و امن
        self.script_path = os.path.abspath(
            os.path.join(settings.BASE_DIR, "../../manager.sh")
        )

        # دایرکتوری اجرای اسکریپت (خیلی مهم برای docker compose)
        self.workdir = os.path.dirname(self.script_path)

    # ──────────────────────────────────────
    # PUBLIC API
    # ──────────────────────────────────────

    def get_projects(self):
        raw = self._run_show()
        cleaned = self._strip_ansi(raw)
        return self._parse_table(cleaned)

    def execute(self, project, action):
        allowed = {
            "up", "down", "stop", "start", "restart",
            "status", "logs", "port", "top",
            "pull", "build", "update",
            "config", "images",
            "remove"
        }

        if action not in allowed:
            raise ValueError("Invalid action")

        result = subprocess.run(
            ["bash", self.script_path, "manage", project, action],
            cwd=self.workdir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        if result.returncode != 0:
            raise RuntimeError(result.stderr or "Command failed")

        return result.stdout

    # ──────────────────────────────────────
    # STREAMING API (REAL-TIME)
    # ──────────────────────────────────────

    def _stream(self, project, action):
        process = subprocess.Popen(
            ["bash", self.script_path, "manage", project, action],
            cwd=self.workdir,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,  # جلوگیری از deadlock
            text=True,
            bufsize=1
        )

        for line in iter(process.stdout.readline, ''):
            yield line

        process.stdout.close()
        process.wait()
    #
    # def interactive_logs_with_pwn(self,command):
    #     """
    #     اجرای دستور در یک ترمینال واقعی با pwntools
    #     """
    #     p = process(command)
    #     try:
    #         while True:
    #             # هر خط آماده را می‌خوانیم
    #             output = p.recv(timeout=0.1)  # هر 0.1 ثانیه
    #             if output:
    #                 yield output.decode(errors="ignore")
    #             if p.poll(block=False) is not None:
    #                 break
    #     finally:
    #         p.close()
    def stream_logs(self, project):
        return self._stream(project, "logs")


    def stream_status(self, project):
        return self._stream(project, "status")

    def stream_top(self, project):
        return self._stream(project, "top")

    # ──────────────────────────────────────
    # INTERNALS
    # ──────────────────────────────────────

    def _run_show(self):
        result = subprocess.run(
            ["bash", self.script_path, "show"],
            cwd=self.workdir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        if result.returncode != 0:
            raise RuntimeError(result.stderr or "Show command failed")

        return result.stdout

    def _strip_ansi(self, text):
        ansi = re.compile(r'\x1B\[[0-?]*[ -/]*[@-~]')
        return ansi.sub('', text)

    def _parse_table(self, output):
        projects = []

        for line in output.splitlines():

            if "|" not in line:
                continue

            if line.strip().startswith("PROJECT"):
                continue

            if line.strip().startswith("Summary"):
                break

            parts = line.split("|")

            if len(parts) < 2:
                continue

            name = parts[0].strip()
            status = parts[1].strip()
            ports = parts[2].strip() if len(parts) > 2 else ""

            normalized_status = self._normalize_status(status)

            projects.append({
                "name": name,
                "status": normalized_status,
                "ports": ports,
            })

        return projects

    def _normalize_status(self, status):
        s = status.lower().strip()

        if "not started" in s or "created" in s:
            return "not_started"

        if any(x in s for x in ["stopped", "exited", "down"]):
            return "stopped"

        if any(x in s for x in ["running", "started", "up"]):
            return "running"

        return "unknown"
