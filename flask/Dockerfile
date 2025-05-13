# Stage 1: Build stage
FROM python:3.10-slim@sha256:2bac43769ace90ebd3ad83e5392295e25dfc58e58543d3ab326c3330b505283d AS builder

WORKDIR /app

# Copier uniquement les fichiers de dépendances pour optimiser le cache
COPY requirements.txt .

# Installer les dépendances
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir --upgrade setuptools wheel && \
    pip install --no-cache-dir -r requirements.txt && \
    pip install gunicorn

# Stage 2: Production stage
FROM python:3.10-slim@sha256:2bac43769ace90ebd3ad83e5392295e25dfc58e58543d3ab326c3330b505283d

# Créer un utilisateur non privilégié
RUN groupadd -r app && useradd -r -g app app && userdel root

WORKDIR /app

# Copier les dépendances installées depuis le stage builder
COPY --from=builder /usr/local/lib/python3.10/site-packages /usr/local/lib/python3.10/site-packages
COPY --from=builder /usr/local/bin/gunicorn /usr/local/bin/gunicorn

# Copier le code de l'application
COPY --chown=app:app . .

# Ajouter un point de contrôle de santé
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:5000/health || exit 1

# Exposer uniquement le port nécessaire
EXPOSE 5000

# Passer à l'utilisateur non privilégié
USER app

# Utiliser Gunicorn comme serveur WSGI pour la production
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app"]
