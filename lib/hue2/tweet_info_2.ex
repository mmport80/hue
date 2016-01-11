defmodule Hue2.TweetInfo2 do
        alias Hue2.Repo
        alias Hue2.Article

        #import Timex
        import Ecto.Query
        
        ##################################################################
        ##################################################################
        
        #get articles
        #store
        
        def retweet() do
                #what's already been tweeted
                htl = ExTwitter.user_timeline(count: 200)
                        |> Enum.filter(
                                fn(t) -> t.quoted_status != nil
                                end)
                        |> Enum.map(
                                fn(t) -> t.quoted_status.id_str 
                                end)
                
                get_articles() |>
                        Enum.take(1)
                        |> 
                        #map with index or reduce
                        Enum.reduce(
                                0,
                                fn(a, acc) ->
                                        cond do
                                                #check whether article has already been retweeted
                                                Enum.member?(htl, a.tweet_id_str) ->
                                                        #do nothing
                                                        acc + 1
                                                true ->
                                                        #tweet so many stars / top daily pick
                                                        #append add link to orig tweet
                                                        origTweetLink = "https://twitter.com/" <> a.tweet_author <> "/status/" <> a.tweet_id_str
                                                        
                                                        #star emoticon in binary
                                                        star = <<11088 :: utf8>>
                                                        
                                                        #rate posts by stars etc
                                                        
                                                        rating = 
                                                                cond do
                                                                        acc > 6 ->
                                                                                star
                                                                        acc > 3 ->
                                                                                star <> star
                                                                        acc > 0 ->
                                                                                star <> star <> star
                                                                        true ->
                                                                                "~Top Daily Pick~"
                                                                end
                                                        
                                                        IO.inspect a.referrers
                                                        
                                                        #reduce referrers int "\nh/t @xoxo, @yoyo"
                                                        referrers = referrer_string(a.referrers)
                                                        
                                                        #tweet rating and link to original tweet
                                                        ExTwitter.update(rating <> "\n\n\n" <> referrers  <> origTweetLink)
                                                        
                                                        acc + 1
                                        end
                                end )
        end
        
        def referrer_string(referrers) do
                cond do
                        referrers != [] && referrers != nil ->
                                referrer_string = referrers
                                        |> Enum.map(
                                                fn(referrer) ->
                                                        "@" <> referrer
                                                end
                                        )
                                        |> Enum.reduce(
                                                fn(referrer, acc) ->
                                                        acc <> "\n\n"  <> referrer
                                                end
                                        )
                                "\nh/t" <> referrer_string
                         true ->
                                ""
                end
        end
        
        
        ##################################################################
        
        def get_articles() do
                [show: n] = Application.get_env( :hue2, :settings )
                
                #sql query
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
                                 100000 * ( max(article.favorite_count - 1, 0) + max(article.retweet_count - 1, 0) * 2.66 ) / article.followers_count
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
                                                        #id or text is the same...
                                                        (a.tweet_id_str == article.tweet_id_str) || (a.text == article.text)
                                                #if end up with nothing
                                                end ) == [] ->
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
                #increase and reduce frequency -> hopefully avoid crashing bringing everything down...
                ExTwitter.home_timeline([count: 7])
                        #recursively find relevant tweets if need be
                        |> Stream.map(
                                fn(tweet) ->
                                        #use original quoted or retweeted tweet if a quote or a retweet
                                        get_quoted_or_rtwd_status?(tweet, 0, [])               
                        end )
                        #filter out tweets with zero faves & retweets
                        |> Stream.filter(
                                fn( %{ tweet: tweet, current_followers: _, referrers: _  } ) ->
                                        tweet.favorite_count > 0 || tweet.retweet_count > 0
                        end )
                        #map / setup
                        #creates augmented article objects
                        |> Stream.map(
                                fn(tweet) ->
                                        tweet
                                        |> init
                                        #get external url
                                        |> get_expanded_url
                                        #get 'local' media url
                                        |> get_local_media_url
                                        #pull everything from source website
                                        |> get_source_data
                        end )
                        #return only the articles
                        |> Stream.map(
                                fn( %{tweet: %ExTwitter.Model.Tweet{} = _, article: %Hue2.Article{} = article} ) ->
                                        article
                        end )
                        #only store tweets with a link
                        |> Stream.filter(
                                fn(article) ->
                                        article.expanded_url != nil
                        end )
                        #update db
                        |> Enum.map(
                                fn( article ) ->
                                        Repo.insert(article)
                        end )
        end
        
        #recursively find original tweet
        defp get_quoted_or_rtwd_status?( %ExTwitter.Model.Tweet{} = tweet, followers, referrers ) do
                #add up followers, try to count up total tweet audience
                #collect user names along the way for H/Ts 
                cond do
                        tweet.retweeted_status == nil && tweet.quoted_status == nil && tweet.in_reply_to_status_id_str == nil ->
                                #update followers with total countable (approx) audience
                                %{ tweet: tweet, current_followers: followers, referrers: Enum.uniq(referrers) }
                        tweet.quoted_status != nil ->
                                tweet.quoted_status.id
                                |> ExTwitter.show
                                |> get_quoted_or_rtwd_status?( followers + tweet.user.followers_count, [ tweet.user.screen_name | referrers ] )
                        tweet.retweeted_status != nil ->
                                tweet.retweeted_status.id
                                |> ExTwitter.show
                                |> get_quoted_or_rtwd_status?( followers + tweet.user.followers_count, [ tweet.user.screen_name | referrers ] )
                        true ->
                                tweet.in_reply_to_status_id_str
                                |> ExTwitter.show
                                |> get_quoted_or_rtwd_status?( followers + tweet.user.followers_count, [ tweet.user.screen_name | referrers ] )
                end
        end
        
        #template
        #defp get_local_media_url( %{tweet: %ExTwitter.Model.Tweet{} = tweet, article: %Article{} = article} ) do
        #        %{tweet: tweet, article: article}
        #end
        
        #####################################################################
        
        defp init( %{ tweet: tweet, current_followers: current_followers, referrers: referrers  } ) do
                #take array of refers
                #insert array into hters table
                #
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
                        tweet_author:           tweet.user.screen_name,
                        referrers:              referrers
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
                #IO.inspect tweet
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
                #IO.inspect ps
                #IO.inspect length(ps)
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
                
                #IO.puts "article.expanded_url"
                #IO.puts article.expanded_url
                
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
