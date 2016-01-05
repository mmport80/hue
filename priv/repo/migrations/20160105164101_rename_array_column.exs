defmodule Hue2.Repo.Migrations.RenameArrayColumn do
  use Ecto.Migration

  def change do
        alter table (:articles) do
                remove  :my_array
                add     :referrers, {:array, :string}
        end 
  end
end
