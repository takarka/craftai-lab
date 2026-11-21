import pytest
from pydantic import ValidationError

from app.core.config import Settings


@pytest.mark.parametrize("origin", ["*", "https://example.com/", "https://example.com/app", "https://u:p@example.com"])
def test_cors_rejects_non_origin_values(origin):
    with pytest.raises(ValidationError, match="explicit HTTP"):
        Settings(_env_file=None, cors_origins=[origin])


def test_cors_accepts_json_environment(monkeypatch):
    monkeypatch.setenv("CRAFTAI_CORS_ORIGINS", '["https://takarka.github.io"]')
    assert Settings(_env_file=None).cors_origins == ["https://takarka.github.io"]


async def test_browser_preflight_allows_configured_origin_only(client):
    for origin, expected_status in [
        ("http://localhost:8080", 200),
        ("https://takarka.github.io", 200),
        ("https://untrusted.example", 400),
    ]:
        response = await client.options(
            "/mobile/auth/register",
            headers={
                "Origin": origin,
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "authorization,content-type",
            },
        )
        assert response.status_code == expected_status
        if expected_status == 200:
            assert response.headers["access-control-allow-origin"] == origin
        else:
            assert "access-control-allow-origin" not in response.headers
