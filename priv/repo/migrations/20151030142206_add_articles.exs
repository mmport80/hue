defmodule Hue2.Repo.Migrations.AddArticles do
  use Ecto.Migration

  def change do
         create table (:articles) do
    
                add :text,                :string
                add :favorite_count,      :integer
                add :retweet_count,       :integer
                add :followers_count,     :integer
                add :media_url,           :string
                add :expanded_url,        :string
                add :title,               :string
                add :description,         :string
                add :tweet_id,        :integer
                add :tweet_author,    :string
                add :tweet_id_str,        :string

                timestamps
        end
  
  end
end
