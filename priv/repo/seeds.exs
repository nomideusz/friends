# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#

# Create default lobby room if it doesn't exist
alias Friends.Social

Social.get_or_create_lobby()

