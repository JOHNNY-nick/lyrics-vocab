"""Base déclarative et colonnes communes des tables synchronisées (B.2, 36.2)."""

from datetime import datetime

from sqlalchemy import BigInteger, DateTime, FetchedValue, text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

TABLES_SYNCHRONISEES = ("mot", "artiste", "extrait", "revision", "reglage")
ID_REGLAGE = "00000000-0000-0000-0000-000000000001"


class Base(DeclarativeBase):
    """Classe de base des modèles."""


class SynchroMixin:
    """created_at, updated_at, deleted_at, server_seq (posés par le déclencheur)."""

    __mapper_args__ = {"eager_defaults": True}

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=text("now()"),
        server_onupdate=FetchedValue(),
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    server_seq: Mapped[int] = mapped_column(
        BigInteger, nullable=False, server_default=text("0"), server_onupdate=FetchedValue()
    )
