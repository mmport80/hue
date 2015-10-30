defmodule Hue2.Article do
        use Hue2.Web, :model

        #add hat tip link -> original tweeter
        #make a bunch of fields necessary
        #tweetid - to ensure uniqueness
        schema "articles" do
    
                field :text,                :string
                field :favorite_count,      :integer
                field :retweet_count,       :integer
                field :followers_count,     :integer
                field :media_url,           :string
                field :expanded_url,        :string
                field :title,               :string
                field :description,         :string
                field :tweet_id,        :integer
                field :tweet_author,    :string
                field :tweet_id_str,        :string

                timestamps
        end
end
