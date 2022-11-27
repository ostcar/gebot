package web

import (
	"fmt"
	"net/http"

	"github.com/golang-jwt/jwt/v4"
)

type authPayload struct {
	jwt.StandardClaims
	Admin bool `json:"admin"`
}

func createToken(admin bool, secred []byte) (string, error) {
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, authPayload{Admin: admin})

	tokenString, err := token.SignedString(secred)
	if err != nil {
		return "", fmt.Errorf("signing token: %w", err)
	}

	return tokenString, nil
}

func checkClaim(tokenString string, secred []byte, admin bool) (bool, error) {
	var claim authPayload

	_, err := jwt.ParseWithClaims(tokenString, &claim, func(token *jwt.Token) (interface{}, error) {
		return secred, nil
	})
	if err != nil {
		return false, fmt.Errorf("parsing token: %w", err)
	}

	return claim.Admin, nil
}

func isAdmin(r *http.Request, secred string) bool {
	c, err := r.Cookie(cookieName)
	if err != nil {
		return false
	}

	v, _ := checkClaim(c.Value, []byte(secred), true)
	return v
}
