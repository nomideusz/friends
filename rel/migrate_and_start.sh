#!/bin/sh
set -e

# Run database migrations
/app/bin/friends eval "Ecto.Migrator.with_repo(Friends.Repo, &Ecto.Migrator.run(&1, :up, all: true))"

# Start the app
/app/bin/friends start

