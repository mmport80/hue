defmodule Hue2.Repo.Migrations.IncreaseDescriptionSize do
use Ecto.Migration
        def change do
                alter table(:articles) do
                        modify :media_url, :string, size: 2083
                        modify :expanded_url, :string, size: 2083
                end
        end
end
