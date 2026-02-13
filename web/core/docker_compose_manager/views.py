from django.views import View
from django.shortcuts import render, redirect
from django.contrib import messages
from django.http import StreamingHttpResponse

from .services.docker_manager import DockerManagerService


class DashboardView(View):
    template_name = "dashboard.html"

    def get(self, request):
        service = DockerManagerService()
        projects = service.get_projects()

        context = {
            "running": [p for p in projects if p["status"] == "running"],
            "stopped": [p for p in projects if p["status"] == "stopped"],
            "not_started": [p for p in projects if p["status"] == "not_started"],
        }

        return render(request, self.template_name, context)


class ActionView(View):

    def post(self, request):
        project = request.POST.get("project")
        action = request.POST.get("action")

        # این اکشن‌ها باید استریم شوند
        streaming_actions = {"logs", "status", "top"}

        # اگر از نوع استریم بود → ری‌دایرکت به ویوی استریم
        if action in streaming_actions:
            return redirect("docker_compose_manager:stream", project=project, action=action)

        # اکشن‌های معمولی
        try:
            service = DockerManagerService()
            service.execute(project, action)
            messages.success(request, f"{action} executed for {project}")
        except Exception as e:
            messages.error(request, str(e))

        return redirect("docker_compose_manager:dashboard")


class StreamView(View):

    def get(self, request, project, action):
        service = DockerManagerService()

        output = ""

        if action == "logs":
            # لاگ‌ها را می‌گیریم و یکجا می‌کنیم
            output = "".join(service.stream_logs(project))

        elif action == "status":
            output = "".join(service.stream_status(project))

        elif action == "top":
            output = "".join(service.stream_top(project))

        else:
            output = "Invalid streaming action"

        return render(
            request,
            "output.html",
            {
                "project": project,
                "action": action,
                "output": output
            }
        )
