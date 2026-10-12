"""Table mot (17.2)."""

import uuid
from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, Index, Integer, Text, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, SynchroMixin


class Mot(SynchroMixin, Base):
    """Mot ou expression saisi par l'utilisateur."""

    __tablename__ = "mot"
    __table_args__ = (
        CheckConstraint("char_length(terme) BETWEEN 1 AND 100", name="ck_mot_terme"),
        CheckConstraint(
            "char_length(terme_normalise) BETWEEN 1 AND 100", name="ck_mot_terme_normalise"
        ),
        CheckConstraint("char_length(traduction_fr) <= 200", name="ck_mot_traduction"),
        CheckConstraint("char_length(explication) <= 400", name="ck_mot_explication"),
        CheckConstraint(
            "source_explication IN ('ia','traduction_seule')", name="ck_mot_source_explication"
        ),
        CheckConstraint(
            "statut_enrichissement IN ('en_attente','en_cours','ok','partiel','echec')",
            name="ck_mot_statut_enrichissement",
        ),
        CheckConstraint("niveau IN ('nouveau','en_cours','acquis')", name="ck_mot_niveau"),
        CheckConstraint("nb_echecs >= 0", name="ck_mot_nb_echecs"),
        Index(
            "uq_mot_terme",
            "terme_normalise",
            unique=True,
            postgresql_where=text("deleted_at IS NULL"),
        ),
        Index("ix_mot_seq", "server_seq"),
        Index("ix_mot_niveau", "niveau"),
        Index("ix_mot_created", "created_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    terme: Mapped[str] = mapped_column(Text, nullable=False)
    terme_normalise: Mapped[str] = mapped_column(Text, nullable=False)
    traduction_fr: Mapped[str | None] = mapped_column(Text)
    explication: Mapped[str | None] = mapped_column(Text)
    source_explication: Mapped[str | None] = mapped_column(Text)
    statut_enrichissement: Mapped[str] = mapped_column(
        Text, nullable=False, server_default=text("'en_attente'"), default="en_attente"
    )
    erreur_enrichissement: Mapped[str | None] = mapped_column(Text)
    enrichi_le: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    niveau: Mapped[str] = mapped_column(
        Text, nullable=False, server_default=text("'nouveau'"), default="nouveau"
    )
    nb_echecs: Mapped[int] = mapped_column(
        Integer, nullable=False, server_default=text("0"), default=0
    )
    derniere_revision_le: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
