"""Tables artiste et morceau (17.3)."""

import uuid

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    ForeignKey,
    Index,
    Integer,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, SynchroMixin


class Artiste(SynchroMixin, Base):
    """Artiste, préféré ou rencontré lors d'un repli."""

    __tablename__ = "artiste"
    __table_args__ = (
        CheckConstraint("rang IS NULL OR rang >= 1", name="ck_artiste_rang"),
        Index("ix_artiste_pref", "est_prefere", "rang"),
        Index("ix_artiste_seq", "server_seq"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    nom: Mapped[str] = mapped_column(Text, nullable=False)
    genius_id: Mapped[int | None] = mapped_column(Integer, unique=True)
    musixmatch_id: Mapped[int | None] = mapped_column(Integer)
    image_url: Mapped[str | None] = mapped_column(Text)
    est_prefere: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("false"), default=False
    )
    rang: Mapped[int | None] = mapped_column(Integer)


class Morceau(Base):
    """Morceau interrogé (données de référence, non synchronisées)."""

    __tablename__ = "morceau"
    __table_args__ = (
        UniqueConstraint(
            "artiste_id", "musixmatch_track_id", name="morceau_artiste_id_musixmatch_track_id_key"
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    artiste_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("artiste.id", ondelete="RESTRICT"), nullable=False
    )
    titre: Mapped[str] = mapped_column(Text, nullable=False)
    musixmatch_track_id: Mapped[int | None] = mapped_column(Integer)
    genius_song_id: Mapped[int | None] = mapped_column(Integer)
    url_genius: Mapped[str | None] = mapped_column(Text)
    pochette_url: Mapped[str | None] = mapped_column(Text)
