"""Services gratuits LRCLIB et Deezer dans le suivi des quotas.

Révision : 0002
Précédente : 0001
Créée le : 2026-10-12
"""

from alembic import op

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Autorise lrclib et deezer dans quota_api."""
    op.execute("ALTER TABLE quota_api DROP CONSTRAINT ck_quota_api;")
    op.execute(
        "ALTER TABLE quota_api ADD CONSTRAINT ck_quota_api "
        "CHECK (api IN ('musixmatch','genius','deepl','ollama','lrclib','deezer'));"
    )


def downgrade() -> None:
    """Revient à la liste d'origine (les compteurs des nouveaux services sont supprimés)."""
    op.execute("DELETE FROM quota_api WHERE api IN ('lrclib','deezer');")
    op.execute("ALTER TABLE quota_api DROP CONSTRAINT ck_quota_api;")
    op.execute(
        "ALTER TABLE quota_api ADD CONSTRAINT ck_quota_api "
        "CHECK (api IN ('musixmatch','genius','deepl','ollama'));"
    )
