defmodule Friends.Social.Report do
  use Ecto.Schema
  import Ecto.Changeset

  schema "reports" do
    belongs_to :reporter, Friends.Social.User
    belongs_to :reported, Friends.Social.User
    field :reason, :string
    field :status, :string, default: "pending" # pending, resolved, dismissed

    timestamps()
  end

  def changeset(report, attrs) do
    report
    |> cast(attrs, [:reporter_id, :reported_id, :reason, :status])
    |> validate_required([:reporter_id, :reported_id, :reason])
  end
end
