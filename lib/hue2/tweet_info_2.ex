defmodule Hue2.TweetInfo2 do
        alias Hue2.Repo
        alias Hue2.Article

        #import Timex
        import Ecto.Query
        
        ##################################################################
        
        def get_articles() do
                [show: n] = Application.get_env( :hue2, :settings )
                
                Article 
                |> where(
                        [a], 
                        a.inserted_at > datetime_add(^Ecto.DateTime.utc, -1, "day")
                        ) 
                |> Hue2.Repo.all
                #filter out articles which have videos etc which we do not currently support
                |> Enum.filter(
                        fn(article) ->
                                article.partial == false
                        end
                ) 
                |> order
                |> remove_dupes
                |> Enum.take(n)
        end
        
        defp order(articles) do
                articles
                |> Enum.sort_by(
                        fn(article) ->
                                 (article.favorite_count + max(article.retweet_count - 1, 0) * 2.66) / article.followers_count
                        end 
                )
        end
        
        defp remove_dupes(articles) do
                articles
                |> Enum.reduce(
                        [],
                        fn(article, acc) ->
                                #if tweetid already in don't include anymore
                                cond do
                                        acc
                                        |> Enum.filter(
                                                fn(a) ->
                                                        (a.tweet_id_str == article.tweet_id_str)
                                                        || (a.text == article.text)
                                                end        
                                        ) == [] ->
                                                [article|acc]
                                        true ->
                                                acc
                                end
                        end
                )
        end
        
        ##################################################################
        #get and store article data
        #every function accepts and returns an article object and a tweet
        
        def store() do
                ExTwitter.home_timeline([count: 7])
                        #filters relevant tweets
                        #creates augmented article objects
                        |> Enum.map(
                                fn(tweet) ->
                                        #use original quoted or retweeted tweet if a quote or a retweet
                                        get_quoted_or_rtwd_status?(tweet, 0)
                                        #init - setup article object
                                        |> init
                                        #get external url
                                        |> get_expanded_url
                                        #get 'local' media url
                                        |> get_local_media_url
                                        #pull everything from source website
                                        |> get_source_data
                                end                                                                      
                        )
                        #return only the articles
                        |> Enum.map(
                                fn( %{tweet: %ExTwitter.Model.Tweet{} = _, article: %Hue2.Article{} = article} ) ->
                                        article
                                end
                        )
                        #only store tweets with a link
                        |> Enum.filter(
                                fn(article) ->
                                        article.expanded_url != nil
                                end
                        )
                        |> Enum.map(
                                fn( article ) ->
                                        Repo.insert(article)
                                end
                        )
        end
        
        #recursively find original tweet
        defp get_quoted_or_rtwd_status?( %ExTwitter.Model.Tweet{} = tweet, followers ) do
                #add up followers, try to count up total tweet audience
                cond do
                        tweet.retweeted_status == nil && tweet.quoted_status == nil && tweet.in_reply_to_status_id_str == nil ->
                                #update followers with total countable (approx) audience
                                %{ tweet: tweet, current_followers: followers }
                        tweet.quoted_status != nil ->
                                tweet.quoted_status.id
                                |> ExTwitter.show
                                |> get_quoted_or_rtwd_status?( followers + tweet.user.followers_count )
                        tweet.retweeted_status != nil ->
                                tweet.retweeted_status.id
                                |> ExTwitter.show
                                |> get_quoted_or_rtwd_status?( followers + tweet.user.followers_count )
                        true ->
                                tweet.in_reply_to_status_id_str
                                |> ExTwitter.show
                                |> get_quoted_or_rtwd_status?( followers + tweet.user.followers_count )
                end
        end
        
        #template
        #defp get_local_media_url( %{tweet: %ExTwitter.Model.Tweet{} = tweet, article: %Article{} = article} ) do
        #        %{tweet: tweet, article: article}
        #end
        
        #####################################################################
        
        defp init( %{ tweet: tweet, current_followers: current_followers } ) do
                
                article = %Article{ 
                        media_url:              nil,
                        text:                   tweet.text,
                        expanded_url:           nil,
                        title:                  nil,
                        favorite_count:         tweet.favorite_count,
                        retweet_count:          tweet.retweet_count,
                        #total audience approximation
                        followers_count:        tweet.user.followers_count + current_followers,
                        partial:                false,
                        tweet_id_str:           tweet.id_str,
                        tweet_author:           tweet.user.screen_name
                        }        
                %{tweet: tweet, article: article}
        end
        
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
                
                IO.inspect tweet
                
                cond do
                        #has media and has photos
                        Map.has_key?(tweet.entities, :media) ->
                                cond do
                                        #has video, tweet is partial (do not support video right now)
                                        Enum.any?( videos(tweet) ) ->
                                                %{ vanilla_return | article:  %Article{ article | partial: true } }
                                        #has many photos, update partial - don't support multiple photo tweets
                                        tweet |> photos |> length > 1 ->
                                                %{ vanilla_return | article:  %Article{ article | partial: true } }
                                        #has single photo
                                        tweet |> photos |> length == 1 ->
                                                %{ vanilla_return | article:  %Article{ article | media_url: first_photo(tweet).media_url } }
                                        true ->
                                                vanilla_return
                                end
                        true ->
                                vanilla_return
                end
        end
        
        defp videos(%ExTwitter.Model.Tweet{}=tweet) do
                tweet.entities.media
                        |> Enum.filter(
                                fn(medium) ->
                                        !String.match?(medium.media_url, ~r/ext_tw_video_thumb/)
                                end
                        )
        end
        
        defp photos(%ExTwitter.Model.Tweet{}=tweet) do
                ps = tweet.entities.media
                        |> Enum.filter(
                                fn(medium) ->
                                        medium.type == "photo"
                                end
                        )
                IO.inspect ps
                IO.inspect length(ps)
                ps
        end
        
        defp first_photo(%ExTwitter.Model.Tweet{}=tweet) do
                photos(tweet)
                |> hd
        end
        
        
        #####################################################################
        
        defp get_source_data( %{tweet: %ExTwitter.Model.Tweet{} = tweet, article: %Article{} = article} ) do
                
                vanilla_return = %{tweet: tweet, article: article}
                
                #tmblr causes hackney to crash...
                bad_urls = [
                        "http://tmblr.co/",
                        "https://tmblr.co/",
                        "http://bit.ly/1QW182g"
                        ]
                
                IO.puts "article.expanded_url"
                IO.puts article.expanded_url
                
                cond do
                        article.expanded_url == nil
                                #due to hackney bug
                                || String.starts_with?(article.expanded_url, bad_urls) -> 
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
                                                                #gotta figure out how to do this better - maybe pipes???
                                                
                                                                media_url = http.body |> Floki.find("meta[property='og:image']") |> Floki.attribute("content") |> List.first
                                                                
                                                                if media_url != nil do
                                                                        article = %Article{ article | media_url: media_url }
                                                                end
                                                                
                                                                title = http.body |> Floki.find("meta[property='og:title']") |> Floki.attribute("content") |> List.first
                                
                                                                if title != nil do
                                                                        article = %Article{ article | title: String.slice(title,0,255) }
                                                                end
                                
                                                                description = http.body |> Floki.find("meta[property='og:description']") |> Floki.attribute("content") |> List.first
                                
                                                                if description != nil do
                                                                        article = %Article{ article | text: String.slice(description,0,999) }
                                                                end
                                                                                    
                                                                #return last value
                                                                %{tweet: tweet, article: article}
                                                        #link to PDF / PPT etc                                                        
                                                        true ->
                                                                vanilla_return
                                                end
                                        _ ->
                                                IO.puts "something else happened"
                                                vanilla_return
                                end
                                  
                end

        end
        
        
end
