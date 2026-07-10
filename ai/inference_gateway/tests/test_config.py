from __future__ import annotations
from app.config import Settings, get_settings


class TestConfig:
    def test_default_settings(self):
        s = Settings()
        assert s.env == "dev"
        assert s.port == 8090
        assert s.renderer == "mock"

    def test_settings_from_env(self, monkeypatch):
        monkeypatch.setenv("VTO_ENV", "staging")
        monkeypatch.setenv("VTO_RENDERER", "idm-vton")
        s = Settings()
        assert s.env == "staging"
        assert s.renderer == "idm-vton"

    def test_get_settings_is_cached(self):
        a = get_settings()
        b = get_settings()
        assert a is b
