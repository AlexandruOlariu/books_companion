from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Configuration comes from the environment (or a local `.env`).

    The two secrets have no defaults on purpose: the server refuses to start
    without them rather than run with a guessable key.
    """

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str
    jwt_secret: str = Field(min_length=32)
    # Keyed-hash secret for phone numbers. Changing it orphans every stored
    # phone hash, so treat it like a database password and back it up.
    phone_pepper: str = Field(min_length=32)

    # Firebase service-account key for push notifications. Unset: push is off.
    fcm_credentials_file: str | None = None

    access_token_minutes: int = 15
    refresh_token_days: int = 60


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
