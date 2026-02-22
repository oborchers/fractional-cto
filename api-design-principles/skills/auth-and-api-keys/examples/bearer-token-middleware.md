# Bearer Token Authentication Middleware

Demonstrates authentication middleware that extracts Bearer tokens from the `Authorization` header, validates them as either API keys (prefix-based) or JWTs, returns proper 401/403 errors with descriptive messages, and attaches an auth context to the request for downstream handlers.

## Pseudocode

```
constants:
    API_KEY_PREFIXES = ["sk_live_", "sk_test_", "pk_live_", "pk_test_", "rk_live_", "rk_test_"]

function authMiddleware(request, response, next):
    authHeader = request.headers["Authorization"]

    // --- 401: No credentials ---
    if authHeader is null:
        return response.status(401).json({
            error: {
                type: "authentication_error",
                message: "No API key provided. Include your API key in the Authorization header: Authorization: Bearer <key>",
            }
        })

    // --- 401: Malformed header ---
    if not authHeader.startsWith("Bearer "):
        return response.status(401).json({
            error: {
                type: "authentication_error",
                message: "Invalid Authorization header format. Expected: Bearer <token>",
            }
        })

    token = authHeader.removePrefix("Bearer ").trim()

    if isApiKey(token):
        result = validateApiKey(token)
    else:
        result = validateJwt(token)

    // --- 401: Invalid or expired token ---
    if not result.valid:
        return response.status(401).json({
            error: {
                type: "authentication_error",
                message: result.errorMessage,
                code: result.errorCode,
            }
        })

    // Attach auth context for downstream handlers
    request.auth = {
        key_id:      result.keyId,
        owner_id:    result.ownerId,
        type:        result.type,         // "api_key" or "jwt"
        environment: result.environment,  // "live" or "test"
        scopes:      result.scopes,
    }

    next()

function isApiKey(token):
    return any(token.startsWith(prefix) for prefix in API_KEY_PREFIXES)

function requireScopes(...requiredScopes):
    return function(request, response, next):
        missingScopes = requiredScopes.filter(s => s not in request.auth.scopes)

        // --- 403: Authenticated but insufficient permissions ---
        if missingScopes.length > 0:
            return response.status(403).json({
                error: {
                    type: "authorization_error",
                    message: "Your API key does not have the required permissions.",
                    required_scopes: requiredScopes,
                    missing_scopes: missingScopes,
                }
            })

        next()
```

## Node.js / Express

```js
import jwt from "jsonwebtoken";
import { validateApiKey } from "./api-keys.js";

const API_KEY_PREFIXES = [
  "sk_live_", "sk_test_",
  "pk_live_", "pk_test_",
  "rk_live_", "rk_test_",
];

const JWT_PUBLIC_KEY = process.env.JWT_PUBLIC_KEY;
const JWT_AUDIENCE = process.env.JWT_AUDIENCE;
const JWT_ISSUER = process.env.JWT_ISSUER;

function isApiKey(token) {
  return API_KEY_PREFIXES.some((prefix) => token.startsWith(prefix));
}

// --- Main auth middleware ---

export function authenticate(req, res, next) {
  const authHeader = req.headers.authorization;

  // 401: No credentials
  if (!authHeader) {
    return res.status(401).json({
      error: {
        type: "authentication_error",
        message:
          "No API key provided. Include your API key in the Authorization header: Authorization: Bearer <key>",
      },
    });
  }

  // 401: Malformed header
  if (!authHeader.startsWith("Bearer ")) {
    return res.status(401).json({
      error: {
        type: "authentication_error",
        message: "Invalid Authorization header format. Expected: Bearer <token>",
      },
    });
  }

  const token = authHeader.slice(7).trim();

  if (!token) {
    return res.status(401).json({
      error: {
        type: "authentication_error",
        message: "Bearer token is empty.",
      },
    });
  }

  // Route to the correct validator based on token format
  const result = isApiKey(token)
    ? validateApiKeyToken(token)
    : validateJwtToken(token);

  if (!result.valid) {
    return res.status(401).json({
      error: {
        type: "authentication_error",
        message: result.message,
        code: result.code,
      },
    });
  }

  // Attach auth context for downstream route handlers
  req.auth = {
    keyId: result.keyId,
    ownerId: result.ownerId,
    type: result.type,
    environment: result.environment,
    scopes: result.scopes,
  };

  next();
}

function validateApiKeyToken(token) {
  const result = validateApiKey(db, token);

  if (!result.valid) {
    const messages = {
      invalid_key: "Invalid API key provided.",
      key_revoked: "This API key has been revoked.",
      key_expired: "This API key has expired. Create a new key in your dashboard.",
      unrecognized_key_format: "Unrecognized API key format.",
    };
    return {
      valid: false,
      message: messages[result.error] || "Authentication failed.",
      code: result.error,
    };
  }

  return {
    valid: true,
    keyId: result.keyId,
    ownerId: result.ownerId,
    type: "api_key",
    environment: result.environment,
    scopes: result.scopes,
  };
}

function validateJwtToken(token) {
  try {
    const payload = jwt.verify(token, JWT_PUBLIC_KEY, {
      algorithms: ["RS256"],       // Only accept RS256 -- reject "none" and HS256
      audience: JWT_AUDIENCE,
      issuer: JWT_ISSUER,
      clockTolerance: 30,          // 30-second tolerance for clock skew
    });

    return {
      valid: true,
      keyId: payload.jti || null,
      ownerId: payload.sub,
      type: "jwt",
      environment: "live",
      scopes: (payload.scope || "").split(" ").filter(Boolean),
    };
  } catch (err) {
    const messages = {
      TokenExpiredError: "Access token has expired. Refresh your token.",
      JsonWebTokenError: "Invalid access token.",
      NotBeforeError: "Token is not yet valid.",
    };
    return {
      valid: false,
      message: messages[err.name] || "Token validation failed.",
      code: err.name === "TokenExpiredError" ? "token_expired" : "invalid_token",
    };
  }
}

// --- Scope authorization middleware ---

export function requireScopes(...requiredScopes) {
  return (req, res, next) => {
    const missing = requiredScopes.filter((s) => !req.auth.scopes.includes(s));

    // 403: Authenticated but insufficient permissions
    if (missing.length > 0) {
      return res.status(403).json({
        error: {
          type: "authorization_error",
          message: `Your API key does not have the required permissions. Missing: ${missing.join(", ")}`,
          required_scopes: requiredScopes,
          missing_scopes: missing,
        },
      });
    }

    next();
  };
}

// --- Usage example ---
// app.get("/v1/charges", authenticate, requireScopes("charges:read"), listCharges);
// app.post("/v1/charges", authenticate, requireScopes("charges:write"), createCharge);
// app.delete("/v1/customers/:id", authenticate, requireScopes("customers:delete"), deleteCustomer);
```

## Python / FastAPI

```python
from datetime import datetime, timezone
from typing import Annotated

import jwt
from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel

from .api_keys import validate_api_key

API_KEY_PREFIXES = ("sk_live_", "sk_test_", "pk_live_", "pk_test_", "rk_live_", "rk_test_")

JWT_PUBLIC_KEY = open("public_key.pem").read()
JWT_AUDIENCE = "https://api.example.com"
JWT_ISSUER = "https://auth.example.com"

bearer_scheme = HTTPBearer(auto_error=False)


class AuthContext(BaseModel):
    key_id: str | None
    owner_id: str
    type: str          # "api_key" or "jwt"
    environment: str   # "live" or "test"
    scopes: list[str]


def _is_api_key(token: str) -> bool:
    return any(token.startswith(prefix) for prefix in API_KEY_PREFIXES)


def _validate_api_key_token(token: str) -> AuthContext:
    result = validate_api_key(db, token)

    if not result["valid"]:
        messages = {
            "invalid_key": "Invalid API key provided.",
            "key_revoked": "This API key has been revoked.",
            "key_expired": "This API key has expired. Create a new key in your dashboard.",
            "unrecognized_key_format": "Unrecognized API key format.",
        }
        raise HTTPException(
            status_code=401,
            detail={
                "type": "authentication_error",
                "message": messages.get(result["error"], "Authentication failed."),
                "code": result["error"],
            },
        )

    return AuthContext(
        key_id=result["key_id"],
        owner_id=result["owner_id"],
        type="api_key",
        environment=result["environment"],
        scopes=result["scopes"],
    )


def _validate_jwt_token(token: str) -> AuthContext:
    try:
        payload = jwt.decode(
            token,
            JWT_PUBLIC_KEY,
            algorithms=["RS256"],      # Only accept RS256
            audience=JWT_AUDIENCE,
            issuer=JWT_ISSUER,
            leeway=30,                 # 30-second clock skew tolerance
        )
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=401,
            detail={
                "type": "authentication_error",
                "message": "Access token has expired. Refresh your token.",
                "code": "token_expired",
            },
        )
    except jwt.InvalidTokenError:
        raise HTTPException(
            status_code=401,
            detail={
                "type": "authentication_error",
                "message": "Invalid access token.",
                "code": "invalid_token",
            },
        )

    return AuthContext(
        key_id=payload.get("jti"),
        owner_id=payload["sub"],
        type="jwt",
        environment="live",
        scopes=payload.get("scope", "").split(),
    )


# --- Main auth dependency ---

async def authenticate(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
) -> AuthContext:
    # 401: No credentials
    if credentials is None:
        raise HTTPException(
            status_code=401,
            detail={
                "type": "authentication_error",
                "message": "No API key provided. Include your API key in the Authorization header: Authorization: Bearer <key>",
            },
        )

    token = credentials.credentials

    if not token:
        raise HTTPException(
            status_code=401,
            detail={
                "type": "authentication_error",
                "message": "Bearer token is empty.",
            },
        )

    if _is_api_key(token):
        return _validate_api_key_token(token)
    return _validate_jwt_token(token)


# --- Scope authorization dependency factory ---

def require_scopes(*required_scopes: str):
    def checker(auth: Annotated[AuthContext, Depends(authenticate)]) -> AuthContext:
        missing = [s for s in required_scopes if s not in auth.scopes]

        # 403: Authenticated but insufficient permissions
        if missing:
            raise HTTPException(
                status_code=403,
                detail={
                    "type": "authorization_error",
                    "message": f"Your API key does not have the required permissions. Missing: {', '.join(missing)}",
                    "required_scopes": list(required_scopes),
                    "missing_scopes": missing,
                },
            )

        return auth

    return checker


# --- Usage example ---
#
# @app.get("/v1/charges")
# async def list_charges(auth: Annotated[AuthContext, Depends(require_scopes("charges:read"))]):
#     ...
#
# @app.post("/v1/charges")
# async def create_charge(auth: Annotated[AuthContext, Depends(require_scopes("charges:write"))]):
#     ...
#
# @app.delete("/v1/customers/{customer_id}")
# async def delete_customer(auth: Annotated[AuthContext, Depends(require_scopes("customers:delete"))]):
#     ...
```

## Key Points

- Extract the Bearer token from the `Authorization` header; reject missing or malformed headers with 401
- Route validation based on token format: prefixed tokens go through API key validation, everything else goes through JWT verification
- JWT validation pins the algorithm to `RS256` and rejects `none` and `HS256` to prevent algorithm confusion attacks
- Always validate JWT `aud` (audience) and `iss` (issuer) claims to prevent cross-service token reuse
- Allow 30 seconds of clock skew tolerance for JWT expiration checks
- Attach a typed auth context (key ID, owner, type, environment, scopes) to the request for downstream handlers
- Return 401 for authentication failures (missing, invalid, expired credentials) with descriptive messages and error codes
- Return 403 for authorization failures (valid credentials, insufficient scopes) and include the specific missing scopes so developers can self-diagnose
- Scope checking is a separate middleware/dependency, composable per route -- keeping auth and authz concerns decoupled
