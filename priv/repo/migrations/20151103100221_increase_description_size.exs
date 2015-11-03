defmodule Hue2.Repo.Migrations.IncreaseDescriptionSize do
use Ecto.Migration
        def change do
                alter table(:articles) do
                        modify :description, :string, size: 1000
                end
        end
end
