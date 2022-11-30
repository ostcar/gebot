module Page.Form exposing (Model, Msg, init, update, view)

import Gebot
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Http
import Json.Decode as Json


type alias Model =
    { formGebot : String
    , formGebotErr : Maybe String
    , state : State
    , errMsg : Maybe String
    }


defaultModel : Model
defaultModel =
    { formGebot = ""
    , formGebotErr = Nothing
    , state = OnForm
    , errMsg = Nothing
    }


init : Model
init =
    defaultModel


type State
    = OnForm
    | OnConfirm
    | OnSended
    | OnSuccess
    | OnError String


type Msg
    = ReceivedSendGebot (Result Http.Error ())
    | InsertedGebot String
    | ClickedGebot
    | ClickedGebotConfirm
    | ClickedGebotAbort
    | ClickedBack


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ReceivedSendGebot response ->
            case response of
                Ok _ ->
                    ( { model | state = OnSuccess }
                    , Cmd.none
                    )

                Err e ->
                    ( { model
                        | state = OnError (buildErrorMessage e)
                      }
                    , Cmd.none
                    )

        InsertedGebot gebotStr ->
            let
                gebotErr =
                    case Gebot.centfromString gebotStr of
                        Ok _ ->
                            Nothing

                        Err err ->
                            Just err
            in
            ( { model | formGebot = gebotStr, formGebotErr = gebotErr }
            , Cmd.none
            )

        ClickedGebot ->
            let
                gebot =
                    Gebot.centfromString model.formGebot
            in
            case gebot of
                Ok _ ->
                    ( { model | formGebotErr = Nothing, state = OnConfirm }
                    , Cmd.none
                    )

                Err _ ->
                    ( model
                    , Cmd.none
                    )

        ClickedGebotConfirm ->
            let
                gebot =
                    Gebot.centfromString model.formGebot
            in
            case gebot of
                Ok cent ->
                    ( { model | formGebot = "", formGebotErr = Nothing, state = OnSended }
                    , Gebot.send ReceivedSendGebot cent
                    )

                Err _ ->
                    ( { model | state = OnForm }
                    , Cmd.none
                    )

        ClickedGebotAbort ->
            ( { model | state = OnForm }
            , Cmd.none
            )

        ClickedBack ->
            ( defaultModel
            , Cmd.none
            )


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
    case model.state of
        OnForm ->
            viewGebotForm model

        OnConfirm ->
            viewGebotConfirm model

        OnSended ->
            viewGebotSended

        OnSuccess ->
            viewGebotSuccess

        OnError str ->
            viewGebotServerError str


viewGebotForm : Model -> Html Msg
viewGebotForm model =
    div []
        [ text "Bitte geb ein Gebot ab:"
        , br [] []
        , input
            [ type_ "Gebot"
            , value model.formGebot
            , onInput InsertedGebot
            , onEnter ClickedGebot
            , autofocus True
            ]
            []
        , br [] []
        , button [ type_ "submit", class "btn btn-primary", onClick ClickedGebot ] [ text "Abgeben" ]
        , br [] []
        , Maybe.withDefault "" model.formGebotErr |> text
        ]


onEnter : Msg -> Attribute Msg
onEnter msg =
    let
        isEnter code =
            if code == 13 then
                Json.succeed msg

            else
                Json.fail "not ENTER"
    in
    on "keydown" (Json.andThen isEnter keyCode)


viewGebotConfirm : Model -> Html Msg
viewGebotConfirm model =
    div []
        [ text ("Ist das Gebot von " ++ model.formGebot ++ "€ richtig?")
        , br [] []
        , button [ class "btn btn-primary", onClick ClickedGebotConfirm ] [ text "Ja" ]
        , button [ class "btn btn-primary", onClick ClickedGebotAbort ] [ text "Nein" ]
        ]


viewGebotSuccess : Html Msg
viewGebotSuccess =
    div []
        [ text "Dein Gebot wurde gezählt"
        , br [] []
        , button [ class "btn btn-primary", onClick ClickedBack ] [ text "Zurück" ]
        ]


viewGebotSended : Html Msg
viewGebotSended =
    text "Warte auf Server"


viewGebotServerError : String -> Html Msg
viewGebotServerError str =
    div []
        [ "Dein Stimme konnte leider nicht gezählt werden. Der Server meint: " ++ str |> text
        , button [ class "btn btn-primary", onClick ClickedBack ] [ text "Zurück" ]
        ]
