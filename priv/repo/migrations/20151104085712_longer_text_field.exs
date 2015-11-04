defmodule Hue2.Repo.Migrations.IncreaseDescriptionSize do
use Ecto.Migration
        def change do
                alter table(:articles) do
                        modify :text, :string, size: 2083
                        
                end
        end
end
