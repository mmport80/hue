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
                ExTwitter.home_timeline([count: 10])
                        #filters relevant tweets
                        #creates augmented article objects
                        |> Enum.map(
                                fn(tweet) ->
                                        #use original quoted or retweeted tweet if a quote or a retweet
                                        get_quoted_or_rtwd_status?(tweet)
                                        #init
                                        |> init
                                        #get external url
                                        |> get_expanded_url
                                        #get 'local' media url
                                        |> get_local_media_url
                                        #pull everything from source website
                                        |> get_source_data
                                        
                                end                                                                      
                        )
                        |> Enum.filter(
                                fn( x ) ->
                                        IO.inspect x
                                        true
                                end
                        )
                        #return only the articles
                        |> Enum.map(
                                fn( %{tweet: %ExTwitter.Model.Tweet{} = tweet, article: %Hue2.Article{} = article} ) ->
                                        article
                                end
                        )
                        |> order
                        #change to 10 for prod
                        |> Enum.take(200)
                        |> Enum.map(
                                fn( article ) ->
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
                
                IO.puts tweet.text
                
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
        
        defp order(articles) do
                articles
                |> Enum.sort_by(
                        fn(article) ->
                                 - (article.favorite_count + max(article.retweet_count - 1, 0) * 2.66) / article.followers_count
                        end 
                )
        end
        
        #template
        #defp get_local_media_url( %{tweet: %ExTwitter.Model.Tweet{} = tweet, article: %Article{} = article} ) do
        #        %{tweet: tweet, article: article}
        #end
        
        #####################################################################
        
        defp get_expanded_url( %{tweet: %ExTwitter.Model.Tweet{} = tweet, article: %Article{} = article} ) do
                vanilla_return = %{tweet: tweet, article: article}
                cond do
                        has_source_url?(tweet) ->
                                [first_urls|_] = tweet.entities.urls
                                %{ vanilla_return | article: %Article{ article | expanded_url: first_urls.expanded_url } }
                        true ->
                                vanilla_return
                end
                
        end
        
        defp has_source_url?( %ExTwitter.Model.Tweet{}=tweet ) do
                Map.has_key?(tweet.entities, :urls)
                && Enum.any?(tweet.entities.urls)
                && (
                        url = tweet.entities.urls |> List.first
                        !String.match?( url.display_url, ~r/vine.co/ )
                        )
        end
        
        
        #####################################################################
        
        defp get_local_media_url( %{tweet: %ExTwitter.Model.Tweet{} = tweet, article: %Article{} = article} ) do
                vanilla_return = %{tweet: tweet, article: article}
                cond do
                        #has media and has photos
                        Map.has_key?(tweet.entities, :media) && Enum.any?( photos(tweet) ) ->
                                %{ vanilla_return | article:  %Article{ article | media_url: first_photo(tweet).media_url } }
                        true ->
                                vanilla_return
                end
        end
        
        defp photos(%ExTwitter.Model.Tweet{}=tweet) do
                tweet.entities.media
                        |> Enum.filter(
                                fn(medium) ->
                                        medium.type == "photo" && !String.match?(medium.media_url, ~r/ext_tw_video_thumb/)
                                end
                        )
        end
        
        defp first_photo(%ExTwitter.Model.Tweet{}=tweet) do
                photos(tweet)
                |> hd
        end
        
        
        #####################################################################
        
        defp get_source_data( %{tweet: %ExTwitter.Model.Tweet{} = tweet, article: %Article{} = article} ) do
                
                vanilla_return = %{tweet: tweet, article: article}
                
                cond do
                        #tmblr causes hackney to crash...
                        article.expanded_url == nil -> 
                                vanilla_return
                        true ->
                                #spawn so that crashes won't bring everything down
                                case HTTPoison.get(article.expanded_url, [], [ hackney: [follow_redirect: true] ]) do
                                        #prob paywalled
                                        {:error, %HTTPoison.Error{reason: reason} } ->
                                                IO.inspect reason
                                                vanilla_return
                                        {:ok, http} ->
                                                cond do
                                                        #in case link goes to a pdf or something
                                                        String.valid?(http.body) ->
                                                                media_url = http.body |> Floki.find("meta[property='og:image']") |> Floki.attribute("content") |> List.first
                                                
                                                                cond do
                                                                        media_url != nil ->
                                                                                %{ vanilla_return | article: %Article{ article | media_url: media_url } }
                                                                        true ->
                                                                                vanilla_return
                                                                end
                                                
                                                
                                                                title = http.body |> Floki.find("meta[property='og:title']") |> Floki.attribute("content") |> List.first
                                                
                                                                IO.puts "title/"
                                                                IO.puts title
                                                                IO.puts "/title"
                                                                
                                                                cond do
                                                                        title != nil ->
                                                                                %{ vanilla_return | article:  %Article{ article | title: title } }
                                                                        true ->
                                                                                vanilla_return
                                                                end
                                                
                                                
                                                                description = http.body |> Floki.find("meta[property='og:description']") |> Floki.attribute("content") |> List.first
                                                
                                                                cond do
                                                                        description != nil ->
                                                                                %{ vanilla_return | article:  %Article{ article | text: description } }
                                                                        true ->
                                                                                vanilla_return
                                                                end
                                                        #link to PDF / PPT etc                                                        
                                                        true ->
                                                                vanilla_return
                                                end
                                        _ ->
                                                IO.puts "something else happened"
                                                #IO.inspect 
                                                vanilla_return
                                end
                                  
                end
                
        end
        
        
end