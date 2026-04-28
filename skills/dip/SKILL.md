---
name: dip
description: Run Docker-based development commands using dip, a CLI tool for interacting with Docker Compose. Use when starting services, running commands, or managing containers in dip-based projects.
---

# Dip

Dip is a CLI tool for interacting with Docker Compose, providing convenient shortcuts for development workflows. Commands run inside Docker containers.

## Starting Services

```bash
dip up -d          # Start all services in the background (detached)
dip down           # Stop all services
dip stop           # Stop without removing containers
```

Always use `-d` when starting services so they run in the background.

## Running Commands

Available commands are defined in the project's `dip.yml` file. Read it to discover what's available.

```bash
dip <command>              # Run a dip command
dip sh                     # Open shell in container
```

### Environment Variables

Pass environment variables **after `dip`** and **before the command** to inject them into the container:

```bash
dip RAILS_ENV=test rails db:create
dip NODE_ENV=production yarn build
```

## Restarting Individual Services

```bash
dip compose restart <service>    # Restart a specific service
```

## Viewing Logs

```bash
docker logs <container-name> --tail 20
```

## Gotchas

### Port Conflicts

If `dip up` fails with "port is already allocated", other Docker containers from different projects are occupying the required ports. Run `dipstop` to shut down all running Docker Compose projects, then retry:

```bash
dipstop
dip up -d
```

### Networking Issues

If services can't connect to each other after stopping and starting containers, the containers may have ended up on different Docker networks. A full `dip down && dip up -d` (not just restart) will recreate the network cleanly.

### Missing Dependencies

If a service fails to start due to missing dependencies, install them via dip and restart:

```bash
dip <install-command>
dip compose restart <service>
```
