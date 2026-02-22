# Prefixed API Key System

Demonstrates complete API key lifecycle: generation with Stripe-style prefixes, SHA-256 hashing for storage, validation with prefix-based routing (live vs test environments), and key listing with masked display.

## Pseudocode

```
constants:
    KEY_PREFIXES = {
        secret_live:      "sk_live_",
        secret_test:      "sk_test_",
        publishable_live: "pk_live_",
        publishable_test: "pk_test_",
        restricted_live:  "rk_live_",
        restricted_test:  "rk_test_",
    }
    ENTROPY_BYTES = 32
    VALID_PREFIXES = set of all prefix values

function generateApiKey(type, environment):
    prefix = KEY_PREFIXES["{type}_{environment}"]
    randomBytes = cryptoRandomBytes(ENTROPY_BYTES)
    entropy = base62Encode(randomBytes)
    rawKey = prefix + entropy

    keyHash = sha256(rawKey)
    displayPrefix = rawKey[:12]
    lastFour = rawKey[-4:]

    store({
        id:          generateId("key"),
        hash:        keyHash,
        prefix:      displayPrefix,
        last_four:   lastFour,
        type:        type,
        environment: environment,
        scopes:      defaultScopes(type),
        created_at:  now(),
        last_used_at: null,
        expires_at:  null,
    })

    // Return raw key exactly once
    return { key: rawKey, id: record.id }

function validateApiKey(rawKey):
    // Extract prefix to determine key type and environment
    prefix = extractPrefix(rawKey)
    if prefix not in VALID_PREFIXES:
        return { valid: false, error: "unrecognized_key_format" }

    keyHash = sha256(rawKey)
    record = database.findByHash(keyHash)

    if record is null:
        return { valid: false, error: "invalid_key" }

    if record.expires_at and record.expires_at < now():
        return { valid: false, error: "key_expired" }

    if record.revoked_at:
        return { valid: false, error: "key_revoked" }

    // Update last_used_at (async, non-blocking)
    database.updateLastUsed(record.id, now())

    return {
        valid: true,
        key_id: record.id,
        type: record.type,
        environment: record.environment,
        scopes: record.scopes,
    }

function extractPrefix(rawKey):
    for prefix in VALID_PREFIXES:
        if rawKey.startsWith(prefix):
            return prefix
    return null

function listApiKeys(ownerId):
    records = database.findByOwner(ownerId)
    return records.map(record => {
        id:           record.id,
        display_name: record.prefix + "..." + record.last_four,
        type:         record.type,
        environment:  record.environment,
        scopes:       record.scopes,
        created_at:   record.created_at,
        last_used_at: record.last_used_at,
        expires_at:   record.expires_at,
    })
```

## Node.js

```js
import { randomBytes, createHash, timingSafeEqual } from "node:crypto";

const KEY_PREFIXES = {
  secret_live: "sk_live_",
  secret_test: "sk_test_",
  publishable_live: "pk_live_",
  publishable_test: "pk_test_",
  restricted_live: "rk_live_",
  restricted_test: "rk_test_",
};

const VALID_PREFIXES = new Set(Object.values(KEY_PREFIXES));
const ENTROPY_BYTES = 32;

// Base62 charset: a-z, A-Z, 0-9
const BASE62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

function base62Encode(buffer) {
  let result = "";
  for (const byte of buffer) {
    result += BASE62[byte % 62];
  }
  return result;
}

function sha256(input) {
  return createHash("sha256").update(input).digest("hex");
}

function extractPrefix(rawKey) {
  for (const prefix of VALID_PREFIXES) {
    if (rawKey.startsWith(prefix)) return prefix;
  }
  return null;
}

// --- Key generation ---

export function generateApiKey(db, { type, environment, ownerId, scopes = [] }) {
  const prefixKey = `${type}_${environment}`;
  const prefix = KEY_PREFIXES[prefixKey];
  if (!prefix) throw new Error(`Invalid key type/environment: ${prefixKey}`);

  const entropy = base62Encode(randomBytes(ENTROPY_BYTES));
  const rawKey = prefix + entropy;

  const keyHash = sha256(rawKey);
  const displayPrefix = rawKey.slice(0, 12);
  const lastFour = rawKey.slice(-4);

  const record = db.insertApiKey({
    hash: keyHash,
    prefix: displayPrefix,
    last_four: lastFour,
    type,
    environment,
    owner_id: ownerId,
    scopes,
    created_at: new Date().toISOString(),
    last_used_at: null,
    expires_at: null,
    revoked_at: null,
  });

  // Return raw key exactly once -- it cannot be retrieved later
  return { key: rawKey, id: record.id };
}

// --- Key validation ---

export function validateApiKey(db, rawKey) {
  const prefix = extractPrefix(rawKey);
  if (!prefix) {
    return { valid: false, error: "unrecognized_key_format" };
  }

  const keyHash = sha256(rawKey);
  const record = db.findApiKeyByHash(keyHash);

  if (!record) {
    return { valid: false, error: "invalid_key" };
  }

  if (record.revoked_at) {
    return { valid: false, error: "key_revoked" };
  }

  if (record.expires_at && new Date(record.expires_at) < new Date()) {
    return { valid: false, error: "key_expired" };
  }

  // Non-blocking update of last_used_at
  db.updateLastUsed(record.id, new Date().toISOString());

  // Determine environment from prefix for routing
  const environment = prefix.includes("_live_") ? "live" : "test";

  return {
    valid: true,
    keyId: record.id,
    type: record.type,
    environment,
    scopes: record.scopes,
    ownerId: record.owner_id,
  };
}

// --- Key listing (masked) ---

export function listApiKeys(db, ownerId) {
  const records = db.findApiKeysByOwner(ownerId);
  return records.map((record) => ({
    id: record.id,
    display_name: `${record.prefix}...${record.last_four}`,
    type: record.type,
    environment: record.environment,
    scopes: record.scopes,
    created_at: record.created_at,
    last_used_at: record.last_used_at,
    expires_at: record.expires_at,
  }));
}

// --- Key revocation ---

export function revokeApiKey(db, keyId, ownerId) {
  const record = db.findApiKeyById(keyId);
  if (!record || record.owner_id !== ownerId) {
    return { success: false, error: "key_not_found" };
  }
  if (record.revoked_at) {
    return { success: false, error: "key_already_revoked" };
  }
  db.updateRevokedAt(keyId, new Date().toISOString());
  return { success: true, revoked_at: new Date().toISOString() };
}
```

## Python

```python
import hashlib
import os
import string
from datetime import datetime, timezone

KEY_PREFIXES = {
    ("secret", "live"): "sk_live_",
    ("secret", "test"): "sk_test_",
    ("publishable", "live"): "pk_live_",
    ("publishable", "test"): "pk_test_",
    ("restricted", "live"): "rk_live_",
    ("restricted", "test"): "rk_test_",
}

VALID_PREFIXES = set(KEY_PREFIXES.values())
ENTROPY_BYTES = 32
BASE62 = string.digits + string.ascii_uppercase + string.ascii_lowercase


def _base62_encode(data: bytes) -> str:
    return "".join(BASE62[b % 62] for b in data)


def _sha256(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def _extract_prefix(raw_key: str) -> str | None:
    for prefix in VALID_PREFIXES:
        if raw_key.startswith(prefix):
            return prefix
    return None


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


# --- Key generation ---

def generate_api_key(
    db, *, key_type: str, environment: str, owner_id: str, scopes: list[str] | None = None
) -> dict:
    prefix = KEY_PREFIXES.get((key_type, environment))
    if prefix is None:
        raise ValueError(f"Invalid key type/environment: {key_type}_{environment}")

    entropy = _base62_encode(os.urandom(ENTROPY_BYTES))
    raw_key = prefix + entropy

    key_hash = _sha256(raw_key)
    display_prefix = raw_key[:12]
    last_four = raw_key[-4:]

    record = db.insert_api_key(
        key_hash=key_hash,
        prefix=display_prefix,
        last_four=last_four,
        key_type=key_type,
        environment=environment,
        owner_id=owner_id,
        scopes=scopes or [],
        created_at=_now(),
    )

    # Return raw key exactly once -- it cannot be retrieved later
    return {"key": raw_key, "id": record["id"]}


# --- Key validation ---

def validate_api_key(db, raw_key: str) -> dict:
    prefix = _extract_prefix(raw_key)
    if prefix is None:
        return {"valid": False, "error": "unrecognized_key_format"}

    key_hash = _sha256(raw_key)
    record = db.find_api_key_by_hash(key_hash)

    if record is None:
        return {"valid": False, "error": "invalid_key"}

    if record.get("revoked_at"):
        return {"valid": False, "error": "key_revoked"}

    if record.get("expires_at"):
        expires = datetime.fromisoformat(record["expires_at"])
        if expires < datetime.now(timezone.utc):
            return {"valid": False, "error": "key_expired"}

    # Non-blocking update of last_used_at
    db.update_last_used(record["id"], _now())

    environment = "live" if "_live_" in prefix else "test"

    return {
        "valid": True,
        "key_id": record["id"],
        "type": record["key_type"],
        "environment": environment,
        "scopes": record["scopes"],
        "owner_id": record["owner_id"],
    }


# --- Key listing (masked) ---

def list_api_keys(db, owner_id: str) -> list[dict]:
    records = db.find_api_keys_by_owner(owner_id)
    return [
        {
            "id": r["id"],
            "display_name": f"{r['prefix']}...{r['last_four']}",
            "type": r["key_type"],
            "environment": r["environment"],
            "scopes": r["scopes"],
            "created_at": r["created_at"],
            "last_used_at": r.get("last_used_at"),
            "expires_at": r.get("expires_at"),
        }
        for r in records
    ]


# --- Key revocation ---

def revoke_api_key(db, key_id: str, owner_id: str) -> dict:
    record = db.find_api_key_by_id(key_id)
    if record is None or record["owner_id"] != owner_id:
        return {"success": False, "error": "key_not_found"}
    if record.get("revoked_at"):
        return {"success": False, "error": "key_already_revoked"}
    now = _now()
    db.update_revoked_at(key_id, now)
    return {"success": True, "revoked_at": now}
```

## Key Points

- Every key carries a prefix encoding type (`sk`, `pk`, `rk`) and environment (`live`, `test`)
- Raw keys are returned exactly once at creation; only SHA-256 hashes are stored
- Prefix and last four characters are stored separately for masked dashboard display (`sk_live_4eC3...9qKI`)
- Validation extracts the prefix first for environment routing before hash lookup
- `last_used_at` is updated on every successful validation for rotation auditing
- Revocation is immediate -- revoked keys are rejected on the next validation call
- Base62 encoding avoids ambiguous characters while maximizing entropy density
