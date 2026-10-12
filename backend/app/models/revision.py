"""Table revision (17.4)."""

import uuid
from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Text,
    text,
)
from sqlalchemy.dialects.postgresql import REAL, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, SynchroMixin


class Revision(SynchroMixin, Base):
    """Échéance planifiée ou réponse enregistrée (journal append-only)."""

    __tablename__ = "revision"
    __table_args__ = (
        CheckConstraint("repetitions >= 0", name="ck_revision_repetitions"),
        CheckConstraint("facilite >= 1.3", name="ck_revision_facilite"),
        CheckConstraint("intervalle_jours >= 0", name="ck_revision_intervalle"),
        CheckConstraint(
            "statut IN ('planifiee','faite','ignoree','doublon')", name="ck_revision_statut"
        ),
        CheckConstraint("mode IN ('rappel','production')", name="ck_revision_mode"),
        CheckConstraint("char_length(reponse_utilisateur) <= 300", name="ck_revision_reponse"),
        CheckConstraint("verdict IN ('correct','proche','incorrect')", name="ck_revision_verdict"),
        CheckConstraint(
            "char_length(explication_verdict) <= 200", name="ck_revision_explication_verdict"
        ),
        CheckConstraint("qualite BETWEEN 0 AND 5", name="ck_revision_qualite"),
        Index(
            "uq_revision_planifiee",
            "mot_id",
            unique=True,
            postgresql_where=text("statut = 'planifiee' AND deleted_at IS NULL"),
        ),
        Index("ix_revision_due", "statut", "date_prevue"),
        Index("ix_revision_seq", "server_seq"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    mot_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("mot.id", ondelete="RESTRICT"), nullable=False
    )
    date_prevue: Mapped[date] = mapped_column(Date, nullable=False)
    repetitions: Mapped[int] = mapped_column(
        Integer, nullable=False, server_default=text("0"), default=0
    )
    facilite: Mapped[float] = mapped_column(
        REAL, nullable=False, server_default=text("2.5"), default=2.5
    )
    intervalle_jours: Mapped[int] = mapped_column(
        Integer, nullable=False, server_default=text("0"), default=0
    )
    statut: Mapped[str] = mapped_column(Text, nullable=False)
    mode: Mapped[str] = mapped_column(Text, nullable=False)
    phrase_source: Mapped[str | None] = mapped_column(Text)
    reference_en: Mapped[str | None] = mapped_column(Text)
    reponse_utilisateur: Mapped[str | None] = mapped_column(Text)
    verdict: Mapped[str | None] = mapped_column(Text)
    verdict_repli: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("false"), default=False
    )
    explication_verdict: Mapped[str | None] = mapped_column(Text)
    qualite: Mapped[int | None] = mapped_column(Integer)
    repondu_le: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    op_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), unique=True)
    appareil_id: Mapped[str | None] = mapped_column(Text)
