defmodule Hue2.PageView do
        use Hue2.Web, :view
  
                def convert_to_mp4_url(url) do
                        url
                                |> String.replace("_thumb","")
                                |> String.replace(".jpg",".mp4")
                                |> String.replace(".png",".mp4")
                
                end
end
