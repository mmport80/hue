defmodule Hue2.Tweet do
  use Hue2.Web, :model

  schema "tweets" do
    field :text,                :string
    field :favorite_count,      :integer
    field :retweet_count,       :integer
    field :followers_count,     :integer
    field :media_url,           :string
    field :expanded_url,        :string
    field :title,               :string
    
    timestamps
  end
end
