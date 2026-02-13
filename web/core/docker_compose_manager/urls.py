from django.urls import path
from .views import DashboardView, ActionView, StreamView

app_name = "docker_compose_manager"

urlpatterns = [
    path("", DashboardView.as_view(), name="dashboard"),
    path("action/", ActionView.as_view(), name="action"),

    # استریم ۳ دستور: logs / status / top
    path("stream/<str:project>/<str:action>/", StreamView.as_view(), name="stream"),
]
