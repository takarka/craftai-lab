"""Freeze the existing Builder/Lab schema before future schema changes.

Revision ID: 0001_initial
Revises: None
"""

from alembic import op

from app.migrations.schema_v1 import metadata

revision = "0001_initial"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    # This is a frozen snapshot, never imported from the current ORM models.
    metadata.create_all(op.get_bind(), checkfirst=False)


def downgrade():
    raise RuntimeError("The initial schema cannot be dropped automatically. Restore a verified backup instead.")
