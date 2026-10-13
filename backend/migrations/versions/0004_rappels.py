"""Fréquences de rappel supplémentaires et plusieurs rappels par jour.

Révision : 0004
Précédente : 0003
Créée le : 2026-10-13
"""

from alembic import op

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Tous les 3 jours, une fois par semaine ; heures de rappel supplémentaires."""
    op.execute("ALTER TABLE reglage DROP CONSTRAINT ck_reglage_frequence;")
    op.execute(
        "ALTER TABLE reglage ADD CONSTRAINT ck_reglage_frequence "
        "CHECK (frequence_rappels IN ('quotidien','tous_les_2_jours','tous_les_3_jours','hebdomadaire','desactive'));"
    )
    op.execute("ALTER TABLE reglage ADD COLUMN heures_rappel_sup jsonb NOT NULL DEFAULT '[]';")


def downgrade() -> None:
    """Revient aux trois fréquences d'origine."""
    op.execute("ALTER TABLE reglage DROP COLUMN heures_rappel_sup;")
    op.execute(
        "UPDATE reglage SET frequence_rappels = 'tous_les_2_jours' "
        "WHERE frequence_rappels IN ('tous_les_3_jours', 'hebdomadaire');"
    )
    op.execute("ALTER TABLE reglage DROP CONSTRAINT ck_reglage_frequence;")
    op.execute(
        "ALTER TABLE reglage ADD CONSTRAINT ck_reglage_frequence "
        "CHECK (frequence_rappels IN ('quotidien','tous_les_2_jours','desactive'));"
    )
