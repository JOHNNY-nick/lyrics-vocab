"""Tables reglage, sync_op et quota_api (17.4)."""

import uuid
from datetime import date, datetime, time

from sqlalchemy import Boolean, CheckConstraint, Date, DateTime, Integer, Text, Time, text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, SynchroMixin


class Reglage(SynchroMixin, Base):
    """Ligne unique des réglages."""

    __tablename__ = "reglage"
    __table_args__ = (
        CheckConstraint(
            "frequence_rappels IN ('quotidien','tous_les_2_jours','desactive')",
            name="ck_reglage_frequence",
        ),
        CheckConstraint("mots_par_session BETWEEN 5 AND 100", name="ck_reglage_mots_session"),
        CheckConstraint("mode_revision IN ('rappel','melange')", name="ck_reglage_mode"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    frequence_rappels: Mapped[str] = mapped_column(
        Text, nullable=False, server_default=text("'quotidien'")
    )
    heure_rappel: Mapped[time] = mapped_column(Time, nullable=False, server_default=text("'19:00'"))
    mots_par_session: Mapped[int] = mapped_column(
        Integer, nullable=False, server_default=text("20")
    )
    mode_revision: Mapped[str] = mapped_column(
        Text, nullable=False, server_default=text("'rappel'")
    )
    heure_changement_jour: Mapped[time] = mapped_column(
        Time, nullable=False, server_default=text("'04:00'")
    )
    sync_wifi_seulement: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("false")
    )


class SyncOp(Base):
    """Opération de synchronisation déjà appliquée (idempotence, SYN-18)."""

    __tablename__ = "sync_op"

    op_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    appareil_id: Mapped[str] = mapped_column(Text, nullable=False)
    type: Mapped[str] = mapped_column(Text, nullable=False)
    applique_le: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )
    resultat: Mapped[dict] = mapped_column(JSONB, nullable=False)


class QuotaApi(Base):
    """Compteur d'appels par service et par jour (QUO-01, QUO-04)."""

    __tablename__ = "quota_api"
    __table_args__ = (
        CheckConstraint(
            "api IN ('musixmatch','genius','deepl','ollama','lrclib','deezer')", name="ck_quota_api"
        ),
    )

    api: Mapped[str] = mapped_column(Text, primary_key=True)
    jour: Mapped[date] = mapped_column(Date, primary_key=True)
    nb: Mapped[int] = mapped_column(Integer, nullable=False, server_default=text("0"))
    caracteres: Mapped[int] = mapped_column(Integer, nullable=False, server_default=text("0"))
