defmodule Hue2.Repo.Migrations.NewPartialColRmTweetIdCol do
        use Ecto.Migration
        def change do
                alter table (:articles) do
    
                        add     :partial,       :boolean
                        remove  :tweet_id
                
                end
        end
end
