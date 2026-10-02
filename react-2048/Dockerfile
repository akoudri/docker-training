# Stage 1: Build the React app (static export to out/)
FROM node:20-alpine AS builder

WORKDIR /app

# Dependencies first, so this layer stays cached while only the sources change
COPY package.json package-lock.json ./
RUN npm ci

COPY . ./
RUN npm run build

# Stage 2: Serve the app with Nginx
FROM nginx:1.27-alpine

COPY --from=builder /app/out /usr/share/nginx/html

EXPOSE 80
