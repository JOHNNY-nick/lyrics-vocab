"""Environnement Alembic : l'URL vient de DATABASE_URL (ou de l'option -x url=...)."""

from alembic import context
from sqlalchemy import create_engine, pool

from app.models import Base

config = context.config
target_metadata = Base.metadata


def _url() -> str:
    url = context.get_x_argument(as_dictionary=True).get("url") or config.get_main_option(
        "sqlalchemy.url"
    )
    if url:
        return url
    from app.core.config import obtenir_parametres

    return obtenir_parametres().database_url


def run_migrations_offline() -> None:
    """Génère le SQL sans connexion."""
    context.configure(url=_url(), target_metadata=target_metadata, literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Applique les migrations sur la base."""
    connexion_existante = config.attributes.get("connection")
    if connexion_existante is not None:
        context.configure(connection=connexion_existante, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()
        return
    moteur = create_engine(_url(), poolclass=pool.NullPool)
    with moteur.connect() as connexion:
        context.configure(connection=connexion, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
