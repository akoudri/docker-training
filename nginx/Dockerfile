FROM nginx:1.25.3-alpine@sha256:6a2f8b28e45c4adea04ec516939f7f372b5b5e5e3103353e7c7ee82bdc16f2a2

# Copier une configuration nginx sécurisée (à créer séparément)
COPY ./nginx.conf /etc/nginx/nginx.conf
COPY ./default.conf /etc/nginx/conf.d/default.conf

# Créer un utilisateur non-root
RUN addgroup -S nginxgroup && adduser -S -G nginxgroup nginxuser && \
    # S'assurer que les répertoires nécessaires appartiennent à l'utilisateur non-root
    chown -R nginxuser:nginxgroup /var/cache/nginx && \
    chown -R nginxuser:nginxgroup /var/log/nginx && \
    chown -R nginxuser:nginxgroup /etc/nginx/conf.d && \
    # Créer le répertoire pour le contenu statique avec les bonnes permissions
    mkdir -p /usr/share/nginx/html && \
    chown -R nginxuser:nginxgroup /usr/share/nginx/html

# Copier le contenu statique
COPY --chown=nginxuser:nginxgroup ./html /usr/share/nginx/html

# Supprimer les fichiers par défaut qui pourraient exposer des informations
RUN rm -rf /usr/share/nginx/html/50x.html /usr/share/nginx/html/index.html

# Définir des variables d'environnement pour limiter les processus worker
ENV NGINX_WORKER_PROCESSES=auto
ENV NGINX_WORKER_CONNECTIONS=1024

# Ajouter un healthcheck
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost/ || exit 1

# Exposer uniquement le port nécessaire
EXPOSE 80

# Passer à l'utilisateur non-root
USER nginxuser