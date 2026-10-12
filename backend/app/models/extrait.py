"""Table extrait (17.3)."""

import uuid

from sqlalchemy import Boolean, CheckConstraint, ForeignKey, Index, Integer, Text, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, SynchroMixin


class Extrait(SynchroMixin, Base):
    """Extrait de 1 à 2 lignes contenant le mot (240 caractères au plus)."""

    __tablename__ = "extrait"
    __table_args__ = (
        CheckConstraint("char_length(texte) <= 240", name="ck_extrait_texte"),
        CheckConstraint("surbrillance_debut >= 0", name="ck_extrait_debut"),
        CheckConstraint(
            "surbrillance_fin > surbrillance_debut AND surbrillance_fin <= char_length(texte)",
            name="ck_extrait_fin",
        ),
        Index(
            "uq_extrait",
            "mot_id",
            "morceau_id",
            unique=True,
            postgresql_where=text("deleted_at IS NULL"),
        ),
        Index("ix_extrait_mot", "mot_id"),
        Index("ix_extrait_seq", "server_seq"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    mot_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("mot.id", ondelete="RESTRICT"), nullable=False
    )
    morceau_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("morceau.id", ondelete="RESTRICT"), nullable=False
    )
    texte: Mapped[str] = mapped_column(Text, nullable=False)
    surbrillance_debut: Mapped[int] = mapped_column(Integer, nullable=False)
    surbrillance_fin: Mapped[int] = mapped_column(Integer, nullable=False)
    hors_liste: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("false"), default=False
    )
