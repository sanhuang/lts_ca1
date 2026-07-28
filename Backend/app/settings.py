"""應用設定（pydantic-settings）。"""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "lts-api-bridge"
    app_public_host: str = "lts-api.personalwork.tw"
    api_prefix: str = ""
    ws_path: str = "/ws"

    ros_topic: str = "/gps/fix"
    ros_domain_id: int = 0

    cors_origins: str = "https://lts-map.personalwork.tw,http://localhost:5173"

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
