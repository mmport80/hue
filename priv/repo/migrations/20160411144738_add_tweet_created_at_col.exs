defmodule Hue2.Repo.Migrations.AddTweetCreatedAtCol do
  use Ecto.Migration

  def change do
    alter table(:articles) do
      add :tweet_created_at, :date
    end
  end


end
