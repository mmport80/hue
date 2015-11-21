defmodule Hue2.FeedView do  
        use Hue2.Web, :view
        use Timex

        def date_format(article) do
                {:ok, date } = article.inserted_at
                |> Ecto.DateTime.to_iso8601
                |> DateFormat.parse("{ISOz}")
                {:ok, date} = DateFormat.format(date, "%a, %d %b %Y %H:%M:%S %z", :strftime)
                date
        end

end