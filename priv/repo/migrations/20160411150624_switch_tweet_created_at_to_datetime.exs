defmodule Hue2.Repo.Migrations.SwitchTweetCreatedAtColToDateTime do
  use Ecto.Migration

  def change do
    alter table(:articles) do
      remove :tweet_created_at
      add :tweet_created_at, :datetime
    end
  end


end
