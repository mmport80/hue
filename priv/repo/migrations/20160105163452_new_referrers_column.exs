defmodule Hue2.Repo.Migrations.NewReferrersColumn do
  use Ecto.Migration

  def change do
        alter table (:articles) do
                add     :my_array, {:array, :float}
        end  
  end
end
