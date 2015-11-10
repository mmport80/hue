defmodule Hue2.TweetInfo2 do
        alias Hue2.Repo
        alias Hue2.Article

        import Timex
        import Ecto.Query
        
        
        ##################################################################
        ##################################################################
        
        
        
        
        #run every 15 mins
        #get and store article data
        
        
        
        #map thru array of tweets
        #go thru each field of each tweet
        #fill each depending on whether info is available
        #
        #ends with storing an article object
        
        
        #every function accepts and returns an article object and a tweet
        
        def store() do
                ExTwitter.home_timeline([count: 200])
                        #filters relevant tweets
                        #creates augmented article objects
                        |> Enum.map(
                                fn(tweet) ->
                                        
                                        tweet =
                                                #use original quoted or retweeted tweet if a quote or a retweet
                                                get_quoted_or_rtwd_status?(tweet)
                                                #init
                                                |> init
                                                #get 'local' media url
                                                |> get_local_media_url
                                                
                                                #get external url
                                                
                                                #get title
                                                
                                                #
                                                
                                                #get media url
                                                
                                                #
                                        
                                end                                                                      
                        )
                        #|> order
                        #change to 10 for prod
                        |> Enum.take(100)
                        |> Enum.map(
                                fn(article) ->
                                        Repo.insert(article)
                                end 
                        )
        end
        
        #recursively find original tweet
        defp get_quoted_or_rtwd_status?( %ExTwitter.Model.Tweet{} = tweet ) do
                cond do
                        tweet.retweeted_status == nil && tweet.quoted_status == nil ->
                                tweet
                        tweet.retweeted_status == nil ->
                                tweet.quoted_status.id |> ExTwitter.show |> get_quoted_or_rtwd_status?
                        true ->
                                tweet.retweeted_status.id |> ExTwitter.show |> get_quoted_or_rtwd_status?
                end
        end
        
        defp init( %ExTwitter.Model.Tweet{} = tweet ) do
                article = %Article{ 
                        media_url:              nil, 
                        #remove trailing t.co url
                        text:                   String.split(tweet.text, [" https://t.co"," http://t.co"]) |> List.first,
                        expanded_url:           nil,
                        title:                  nil,
                        favorite_count:         tweet.favorite_count,
                        retweet_count:          tweet.retweet_count,
                        followers_count:        tweet.user.followers_count,
                        tweet_id:               0,
                        tweet_id_str:           tweet.id_str,
                        tweet_author:           tweet.user.screen_name
                        }        
                %{tweet: tweet, article: article}
        end
        
        #template
        #defp get_local_media_url( %{tweet: %ExTwitter.Model.Tweet{} = tweet, article: %Article{} = article} ) do
        #        %{tweet: tweet, article: article}
        #end
        
        defp get_local_media_url( %{tweet: %ExTwitter.Model.Tweet{} = tweet, article: %Article{} = article} ) do
                %{tweet: tweet, article: article}
        end
        
        #photos but no video
        defp has_photos?( %ExTwitter.Model.Tweet{}=tweet ) do
                Map.has_key?(tweet.entities, :media) && Enum.any?(photos(tweet))
        end
        
        
end
