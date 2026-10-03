# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Teaching material for a Docker training course (slides: `Formation Docker.pdf`). Each top-level directory is an independent hands-on exercise, not part of a single application. Course-facing docs (e.g. `AWS/README.md`) are written in French — keep that language when editing them.

## Exercises

- `docker-compose.yml` (root) — multi-service demo stack: Postgres (`5432`), pgAdmin (`9090`), nginx serving `./nginx/html` via bind mount (`80/443`), cAdvisor (`8080`). Run with `docker compose up -d`.
- `nginx/` — minimal image that bakes `html/` into `nginx:latest` (contrast with the bind-mount approach in the root compose file).
- `flask/` — minimal Flask app on port 5000. `docker build -t flask-app flask/ && docker run -p 5000:5000 flask-app`. `training.tf` is an unrelated GCP Compute VM definition (exported from the GCP console) used to provision a training host.
- `AWS/` — pushing images to ECR and running them on ECS Fargate, fully from the command line (no console steps). Two paths; don't mix them (`destroy_all` would also delete Terraform-managed resources):
  - `ecs.sh deploy|list|url|logs|destroy <app> | destroy_all` — idempotent AWS CLI script deploying **several apps side by side**. `<app>` is a repo-root folder or any path with a Dockerfile; the folder name is the app name; port comes from the last `EXPOSE` (default 80, override with `PORT`). Per-app resources: ECR `docker-training/<app>`, family `docker-training-<app>`, service `<app>`, SG `docker-training-<app>-sg`, logs `/ecs/docker-training/<app>`. Shared: cluster `docker-training-cluster`, role `docker-training-task-execution`. `destroy_all` sweeps everything prefixed `docker-training`. Renders `taskdef.template.json` with `envsubst` into a temp file (snap-installed AWS CLI can't read `file:///dev/stdin`).
  - `terraform/` — single app (nginx by default), legacy names (`docker-training`, `docker-training-service`...); its `Makefile` first applies `-target=aws_ecr_repository.app` because the image must be pushed before the service exists.
  - Both call `push-docker.sh` (builds `--platform linux/amd64`, needs `$DOCKER_REGISTRY`, optional `REPOSITORY`). `setup-iam.sh create|delete <user>` is run once by an admin: training user with `iam-policy.json` (scoped to `docker-training-*` roles) plus `SignInLocalDevelopmentAccess`, and creates the region's default VPC if missing. Auth is via `aws login` (CLI ≥ 2.32), not access keys; the AWS provider is pinned `~> 6.23` for that reason.
  - Verified against a real account: `ecs.sh` deploy/list/url/logs/destroy. Not yet verified: `destroy_all`, Terraform path, `setup-iam.sh`, and the restricted IAM policy (tests ran as root). After a task stops, AWS takes 3–5 min to release its ENI, so SG deletion waits on `describe-network-interfaces`.
- `react-2048/` — third-party Next.js 2048 game (MIT, mateuszsokola) used as the CI/CD subject. Its `docker-compose.yml` runs Jenkins with the host Docker socket mounted (Docker-outside-of-Docker); `images/dockeragent/` is a Jenkins inbound agent with docker/maven/git, and `images/nodejs/` is a Node 20 build image with `netlify-cli` and `node-jq` for deploy steps. On `main` there is no Dockerfile for the game itself and no Jenkinsfile: those are exercise answers and live on the `solutions` branch (`react-2048/Dockerfile`, `react-2048/scripts/Jenkinsfile`, plus `ubuntu/`, `wordpress/`). Keep exercise solutions off `main`; to work on `solutions` without disturbing `main`, use a worktree (`git worktree add ../docker-training-solutions solutions`).

## react-2048 commands

Run from `react-2048/` (Node version in `.nvmrc`: 20.10.0):

```bash
npm install
npm run dev            # http://localhost:3000
npm run build          # static export to out/ (next.config.js: output: "export")
npm run lint           # next lint
npm run check-code     # prettier --check
npm test               # jest, also writes test-report.html (jest-html-reporter)
npm run test-coverage  # writes coverage/
npx jest __tests__/reducers/game-reducer.test.ts   # single test file
```

`coverage/` and `test-report.html` are committed outputs of those commands (they are what the CI pipeline publishes), so running tests will modify tracked files.

Architecture: game state lives in a single `useReducer` (`reducers/game-reducer.ts`) exposed through `context/game-context.tsx`, which owns the game logic (moving tiles, spawning random tiles, win/lose detection) and throttles moves to match the animation durations in `constants.ts`. Components in `components/` only read from the context. Imports use the `@/` path alias.
