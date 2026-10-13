"""Phrases d'exemple des mots.

Révision : 0003
Précédente : 0002
Créée le : 2026-10-13
"""

from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Ajoute la colonne exemples (liste JSON de phrases anglaises et leur traduction)."""
    op.execute("ALTER TABLE mot ADD COLUMN exemples jsonb;")


def downgrade() -> None:
    """Supprime la colonne exemples."""
    op.execute("ALTER TABLE mot DROP COLUMN exemples;")
