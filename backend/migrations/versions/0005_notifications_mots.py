"""Notifications d'un mot au hasard à intervalle régulier.

Révision : 0005
Précédente : 0004
Créée le : 2026-10-13
"""

from alembic import op

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Intervalle (minutes, 0 : désactivé) et plage horaire des notifications."""
    op.execute(
        "ALTER TABLE reglage ADD COLUMN intervalle_notifications_min integer NOT NULL DEFAULT 120 "
        "CONSTRAINT ck_reglage_intervalle_notifications "
        "CHECK (intervalle_notifications_min IN (0,30,60,120,180,240,360));"
    )
    op.execute("ALTER TABLE reglage ADD COLUMN notifications_debut time NOT NULL DEFAULT '09:00';")
    op.execute("ALTER TABLE reglage ADD COLUMN notifications_fin time NOT NULL DEFAULT '21:00';")


def downgrade() -> None:
    """Supprime l'intervalle et la plage des notifications."""
    op.execute(
        "ALTER TABLE reglage DROP COLUMN intervalle_notifications_min, "
        "DROP COLUMN notifications_debut, DROP COLUMN notifications_fin;"
    )
