> module Vocabulink.Html where

> import Vocabulink.CGI
> import Vocabulink.Utils

> import Codec.Binary.UTF8.String
> import Network.CGI
> import Network.URI
> import Text.Regex
> import Text.Regex.Posix
> import Text.XHtml.Strict

A common idiom is to use concatHtml for an element's contents.

> infixr 7 <<|
> (<<|) :: (Html -> Html) -> [Html] -> Html
> h <<| l = h << concatHtml l

This is another common pattern.

> outputHtml :: Html -> CGI CGIResult
> outputHtml = output . renderHtml

> data Dependency = CSS String | JS String

page expects title to already be UTF8 encoded if necessary.

> page :: String -> [Dependency] -> ([Html] -> Html)
> page t ds = \b -> header <<
>   (thetitle << t +++ concatHtml (map includeDep ds)) +++
>   body <<| b

> includeDep :: Dependency -> Html
> includeDep (CSS css) =
>   thelink ! [href ("http://s.vocabulink.com/" ++ css ++ ".css"),
>              rel "stylesheet", thetype "text/css"] << noHtml
> includeDep (JS js) =
>   script ! [src ("http://s.vocabulink.com/" ++ js ++ ".js"),
>             thetype "text/javascript"] << noHtml

It's nice to abstract away creating an element to page the results of a
multi-page query. This will preserve all of the query string in the links it
generates while it replaces the "n" (number of records per page) and "page"
(the page we're on) variables.

First, we the query string.

> pageQueryString :: Int -> Int -> String -> String
> pageQueryString n pg q  =
>   let q1 = q  =~ nRegex  ? subRegex (mkRegex nRegex)  q  ("n=" ++ show n) $
>                            q ++ ("&n=" ++ show n)
>       q2 = q1 =~ pgRegex ? subRegex (mkRegex pgRegex) q1 ("pg=" ++ show pg) $
>                            q1 ++ ("&pg=" ++ show pg) in
>   "?" ++ q2
>     where nRegex  = "n=[^&]+"
>           pgRegex = "pg=[^&]+"

And now for the HTML.

> pager :: Int -> Int -> Int -> CGI Html
> pager n pg total = do
>   q <- getVarE "QUERY_STRING"
>   uri <- requestURI
>   let pth  = uriPath uri
>       q'   = decodeString q
>       prev = pageQueryString n (pg - 1) q'
>       next = pageQueryString n (pg + 1) q'
>   return $ paragraph ! [theclass "pager"] << thespan ! [theclass "controls"] <<|
>     [ (pg > 1 ? anchor ! [href (pth ++ prev), theclass "prev"] $ thespan ! [theclass "prev"]) << "Previous",
>       ((pg * n < total) ? anchor ! [href (pth ++ next), theclass "next"] $ thespan ! [theclass "next"]) << "Next" ]
