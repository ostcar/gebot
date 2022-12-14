module Gebot exposing
    ( Gebot
    , ID
    , centToString
    , centfromString
    , decoder
    , delete
    , encoder
    , fetch
    , idDecoder
    , idToString
    , listDecoder
    , reset
    , send
    , sort
    , toString
    )

import Http
import Json.Decode as Decode exposing (Decoder, int)
import Json.Decode.Pipeline exposing (required)
import Json.Encode as Encode


type alias Gebot =
    { id : ID
    , cent : Int
    }


decoder : Decoder Gebot
decoder =
    Decode.succeed Gebot
        |> required "id" idDecoder
        |> required "cent" int


encoder : Int -> Encode.Value
encoder cent =
    Encode.object
        [ ( "cent", Encode.int cent ) ]


listDecoder : Decoder (List Gebot)
listDecoder =
    Decode.list decoder


send : (Result Http.Error () -> msg) -> Int -> Cmd msg
send result gebot =
    Http.post
        { url = "/api/gebot"
        , body = Http.jsonBody (encoder gebot)
        , expect = Http.expectWhatever result
        }


type ID
    = ID Int


idToString : ID -> String
idToString (ID id) =
    String.fromInt id


idDecoder : Decoder ID
idDecoder =
    Decode.map ID int


idEncoder : ID -> Encode.Value
idEncoder (ID id) =
    Encode.int id


fetch : (Result Http.Error (List Gebot) -> msg) -> Cmd msg
fetch result =
    Http.get
        { url = "/api/gebot"
        , expect =
            listDecoder
                |> Http.expectJson result
        }


sort : List Gebot -> List Gebot
sort =
    List.sortBy (\g -> g.cent)


delete : (Result Http.Error () -> msg) -> ID -> Cmd msg
delete result id =
    Http.request
        { method = "DELETE"
        , headers = []
        , url = "/api/gebot"
        , body = Http.jsonBody (deleteBodyEncoder id)
        , expect = Http.expectWhatever result
        , timeout = Nothing
        , tracker = Nothing
        }


reset : (Result Http.Error () -> msg) -> Cmd msg
reset result =
    Http.request
        { method = "DELETE"
        , headers = []
        , url = "/api/reset"
        , body = Http.emptyBody
        , expect = Http.expectWhatever result
        , timeout = Nothing
        , tracker = Nothing
        }


deleteBodyEncoder : ID -> Encode.Value
deleteBodyEncoder id =
    Encode.object
        [ ( "id", idEncoder id ) ]


stringToResult : x -> String -> Result x Int
stringToResult err str =
    Result.fromMaybe err (String.toInt str)


centfromString : String -> Result String Int
centfromString input =
    let
        resultEuroCent =
            case String.split "," input of
                euroStr :: centStr :: rest ->
                    if List.length rest > 0 then
                        Err "Es darf nur ein Komma geben"

                    else
                        let
                            qCentStr =
                                case String.length centStr of
                                    1 ->
                                        stringToResult "Wert hinter dem Komma muss eine Zahl sein" (centStr ++ "0")

                                    2 ->
                                        stringToResult "Wert hinter dem Komma muss eine Zahl sein" centStr

                                    _ ->
                                        Err "Wert hinter dem Komma darf nur eine oder zwei Stellen haben"
                        in
                        Result.map2
                            (\euro cent -> ( euro, cent ))
                            (stringToResult "Wert vor dem Komma muss eine Zahl sein" euroStr)
                            qCentStr

                [ euroStr ] ->
                    stringToResult "Wert muss eine Zahl sein" euroStr
                        |> Result.andThen (\euro -> Ok ( euro, 0 ))

                [] ->
                    Err "Kein Wert eingetragen"
    in
    case resultEuroCent of
        Ok ( euro, cent ) ->
            Ok (euro * 100 + cent)

        Err err ->
            Err err


toString : Gebot -> String
toString gebot =
    centToString gebot.cent


centToString : Int -> String
centToString euroCent =
    let
        euro =
            euroCent // 100

        euroString =
            intToFormattedString euro

        cent =
            remainderBy 100 euroCent
    in
    euroString ++ "," ++ intToPadding2String cent ++ " ???"


intToFormattedString : Int -> String
intToFormattedString int =
    String.fromInt int
        |> String.foldr
            (\c list ->
                let
                    last =
                        List.head list |> Maybe.withDefault ""
                in
                if String.length last == 3 then
                    String.fromChar c :: list

                else
                    String.cons c last :: List.drop 1 list
            )
            []
        |> String.join "."


intToPadding2String : Int -> String
intToPadding2String n =
    let
        str =
            String.fromInt n

        formatted =
            if String.length str < 2 then
                "0" ++ str

            else
                str
    in
    formatted
