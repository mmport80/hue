defmodule Hue2.Repo.Migrations.CreateUser do
  use Ecto.Migration

  def change do
	create table(:tweets) do
		add :text,                :string	, null: false
    		add :favorite_count,      :integer	, null: false
    		add :retweet_count,       :integer	, null: false
    		add :followers_count,     :integer	, null: false
    		add :media_url,           :string
    		add :expanded_url,        :string
 
    		timestamps
	end

  end
end
