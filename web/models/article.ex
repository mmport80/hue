defmodule Hue2.Article do
        use Hue2.Web, :model

        schema "articles" do
    
                field :text,                :string
                field :favorite_count,      :integer
                field :retweet_count,       :integer
                field :followers_count,     :integer
                field :media_url,           :string
                field :expanded_url,        :string
                field :title,               :string
                field :description,         :string

                timestamps
        end
end
