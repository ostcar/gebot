module Main exposing (main)

import Browser
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Page.Admin as Admin
import Page.Form as Form


main : Program String Model Msg
main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }


type alias Model =
    { formModel : Form.Model
    , adminModel : Admin.Model
    , onPage : OnPage
    }


type OnPage
    = OnPageForm
    | OnPageAdmin


type Msg
    = ClickedToAdmin
    | MsgForm Form.Msg
    | MsgAdmin Admin.Msg


init : String -> ( Model, Cmd Msg )
init token =
    let
        ( adminModel, adminCmd ) =
            Admin.init token
    in
    ( { formModel = Form.init
      , adminModel = adminModel
      , onPage = OnPageForm
      }
    , Cmd.map MsgAdmin adminCmd
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        MsgForm formMsg ->
            let
                ( formModel, formCmd ) =
                    Form.update formMsg model.formModel
            in
            ( { model | formModel = formModel }
            , Cmd.map MsgForm formCmd
            )

        MsgAdmin adminMsg ->
            let
                ( adminModel, adminCmd ) =
                    Admin.update adminMsg model.adminModel
            in
            ( { model | adminModel = adminModel }
            , Cmd.map MsgAdmin adminCmd
            )

        ClickedToAdmin ->
            ( { model | onPage = OnPageAdmin }
            , Cmd.none
            )


view : Model -> Html Msg
view model =
    let
        content =
            case model.onPage of
                OnPageForm ->
                    Form.view model.formModel |> Html.map MsgForm

                OnPageAdmin ->
                    Admin.view model.adminModel |> Html.map MsgAdmin
    in
    div []
        [ content
        , viewFooter
        ]


viewFooter : Html Msg
viewFooter =
    footer [ class "footer" ]
        [ div [ class "container" ]
            [ a [ href "#", onClick ClickedToAdmin ] [ text "Admin" ]
            ]
        ]


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none
