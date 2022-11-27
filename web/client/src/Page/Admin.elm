module Page.Admin exposing (Model, Msg, init, update, view)

import Gebot
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Jwt


type alias Model =
    { permission : Permission
    , error : Maybe String
    , gebote : StateGebote
    }


type Permission
    = PermissionAdmin
    | PermissionNone String


type StateGebote
    = StateNone
    | StateSuccess (List Gebot.Gebot)
    | StateRequested
    | StateError String


type Msg
    = InsertedLoginPassword String
    | ClickedLogin
    | ReceivedAuth (Result Http.Error String)
    | ReceivedGebote (Result Http.Error (List Gebot.Gebot))
    | ClickedDelete Gebot.ID
    | ReceivedDelete (Result Http.Error ())
    | ClickedRefresh


permissionFromBool : Bool -> Permission
permissionFromBool isAdmin =
    if isAdmin then
        PermissionAdmin

    else
        PermissionNone ""


permissionFromJWT : String -> Permission
permissionFromJWT token =
    let
        decoder =
            Decode.field "admin" Decode.bool
    in
    Jwt.decodeToken decoder token
        |> Result.andThen (permissionFromBool >> Result.Ok)
        |> Result.withDefault (PermissionNone "")


init : String -> ( Model, Cmd Msg )
init token =
    let
        permission =
            permissionFromJWT token
    in
    ( { permission = permission
      , error = Nothing
      , gebote = StateNone
      }
    , fetchAsAdmin permission
    )


fetchAsAdmin : Permission -> Cmd Msg
fetchAsAdmin permission =
    case permission of
        PermissionAdmin ->
            Gebot.fetch ReceivedGebote

        PermissionNone _ ->
            Cmd.none


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        InsertedLoginPassword pass ->
            ( { model | permission = PermissionNone pass }
            , Cmd.none
            )

        ClickedLogin ->
            case model.permission of
                PermissionAdmin ->
                    ( model, Cmd.none )

                PermissionNone pass ->
                    ( { model | permission = PermissionNone "" }
                    , sendLogin pass
                    )

        ReceivedAuth result ->
            case result of
                Ok _ ->
                    ( { model | permission = PermissionAdmin, gebote = StateRequested }
                    , Gebot.fetch ReceivedGebote
                    )

                Err err ->
                    ( { model | error = buildErrorMessage err |> Just }, Cmd.none )

        ReceivedGebote result ->
            case result of
                Ok gebote ->
                    ( { model | gebote = StateSuccess gebote }
                    , Cmd.none
                    )

                Err err ->
                    ( { model | gebote = buildErrorMessage err |> StateError }
                    , Cmd.none
                    )

        ClickedDelete id ->
            ( model
            , Gebot.delete ReceivedDelete id
            )

        ReceivedDelete result ->
            case result of
                Ok _ ->
                    ( model
                    , Gebot.fetch ReceivedGebote
                    )

                Err err ->
                    ( { model | gebote = buildErrorMessage err |> StateError }
                    , Cmd.none
                    )

        ClickedRefresh ->
            ( model
            , Gebot.fetch ReceivedGebote
            )


sendLogin : String -> Cmd Msg
sendLogin pass =
    Http.post
        { url = "/api/login"
        , body = Http.jsonBody (passwordEncoder pass)
        , expect = Http.expectString ReceivedAuth
        }


passwordEncoder : String -> Encode.Value
passwordEncoder pass =
    Encode.object
        [ ( "password", Encode.string pass ) ]


buildErrorMessage : Http.Error -> String
buildErrorMessage httpError =
    case httpError of
        Http.BadUrl message ->
            message

        Http.Timeout ->
            "Server is taking too long to respond. Please try again later."

        Http.NetworkError ->
            "Unable to reach server."

        Http.BadStatus statusCode ->
            "Request failed with status code: " ++ String.fromInt statusCode

        Http.BadBody message ->
            message


view : Model -> Html Msg
view model =
    case model.permission of
        PermissionAdmin ->
            viewGebote model

        PermissionNone formPass ->
            viewLogin model formPass


viewGebote : Model -> Html Msg
viewGebote model =
    case model.gebote of
        StateNone ->
            text "TODO"

        StateRequested ->
            text "Warte auf Server"

        StateError err ->
            "Error: " ++ err |> text

        StateSuccess gebote ->
            viewGeboteList gebote


viewGeboteList : List Gebot.Gebot -> Html Msg
viewGeboteList gebote =
    let
        geboteNr =
            List.map2 Tuple.pair (List.range 1 (List.length gebote)) gebote
    in
    div []
        [ button [ type_ "button", class "btn btn-danger", onClick ClickedRefresh ] [ text "Aktualisieren" ]
        , table
            [ class "table" ]
            (List.map viewGebotLine geboteNr ++ viewGebotSummary gebote)
        ]


viewGebotLine : ( Int, Gebot.Gebot ) -> Html Msg
viewGebotLine ( nr, gebot ) =
    tr []
        [ td [] [ String.fromInt nr |> text ]
        , td [] [ Gebot.toString gebot |> text ]
        , td [] [ button [ type_ "button", class "btn btn-danger", onClick (ClickedDelete gebot.id) ] [ text "✖" ] ]
        ]


viewGebotSummary : List Gebot.Gebot -> List (Html Msg)
viewGebotSummary gebote =
    let
        sum =
            List.foldl (\g s -> g.cent + s) 0 gebote

        average =
            sum // List.length gebote
    in
    [ tr []
        [ td [] [ text "Alle" ]
        , td [] [ Gebot.centToString sum |> text ]
        , td [] [ text "" ]
        ]
    , tr []
        [ td [] [ text "Durchschnitt" ]
        , td [] [ Gebot.centToString average |> text ]
        , td [] [ text "" ]
        ]
    ]


viewLogin : Model -> String -> Html Msg
viewLogin model formPassword =
    div []
        [ h5 [] [ text "Login" ]
        , input
            [ type_ "password"
            , value formPassword
            , onInput InsertedLoginPassword
            ]
            []
        , button [ class "btn btn-primary", onClick ClickedLogin ] [ text "Anmelden" ]
        , Maybe.withDefault "" model.error |> text
        ]
