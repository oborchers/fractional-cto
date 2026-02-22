# Prefixed ID Generator

Complete ID generation utility with a prefix registry, generation, validation, and parsing. Covers both Node.js (TypeScript) and Python implementations.

## Node.js (TypeScript)

```typescript
import { ulid } from "ulid";

// --- Prefix Registry (single source of truth) ---

const ID_PREFIXES = {
  user: "usr",
  organization: "org",
  order: "ord",
  product: "prod",
  invoice: "inv",
  payment: "pay",
  subscription: "sub",
  webhook_endpoint: "wh",
  event: "evt",
  session: "sess",
  token: "tok",
  api_key: "key",
  customer: "cus",
  price: "price",
  transaction: "txn",
} as const;

type ResourceType = keyof typeof ID_PREFIXES;
type Prefix = (typeof ID_PREFIXES)[ResourceType];
type PrefixedId<T extends ResourceType> =
  `${(typeof ID_PREFIXES)[T]}_${string}`;

// Reverse lookup: prefix string -> resource type
const PREFIX_TO_TYPE: Record<string, ResourceType> = Object.fromEntries(
  Object.entries(ID_PREFIXES).map(([type, prefix]) => [prefix, type as ResourceType])
) as Record<string, ResourceType>;

// --- Generation ---

function generateId<T extends ResourceType>(type: T): PrefixedId<T> {
  const prefix = ID_PREFIXES[type];
  return `${prefix}_${ulid()}` as PrefixedId<T>;
}

// Usage:
// generateId("customer")    -> "cus_01HXK3GJ5V8WJKPT2MNR9QZK1"
// generateId("order")       -> "ord_01HXK3GJ6WABCDE7FGHJ2KLMN"

// --- Validation ---

const PREFIXED_ID_REGEX = /^[a-z]{2,5}_[a-zA-Z0-9]{14,27}$/;

function isValidPrefixedId(id: string): boolean {
  return PREFIXED_ID_REGEX.test(id);
}

function validateIdType(id: string, expectedType: ResourceType): void {
  const expectedPrefix = ID_PREFIXES[expectedType];

  if (!id.startsWith(expectedPrefix + "_")) {
    throw new InvalidIdError(
      `Expected ${expectedType} ID (prefix '${expectedPrefix}_'), got '${id}'`
    );
  }

  if (!isValidPrefixedId(id)) {
    throw new InvalidIdError(
      `Malformed ID: '${id}' does not match expected format`
    );
  }
}

class InvalidIdError extends Error {
  public readonly type = "invalid_request_error";
  public readonly statusCode = 400;

  constructor(message: string) {
    super(message);
    this.name = "InvalidIdError";
  }
}

// Usage:
// validateIdType("cus_01HXK3GJ5V", "customer")  -> passes
// validateIdType("ord_01HXK3GJ5V", "customer")  -> throws InvalidIdError

// --- Parsing ---

interface ParsedId {
  prefix: string;
  resourceType: ResourceType | null;
  randomPart: string;
  raw: string;
}

function parseId(id: string): ParsedId {
  const separatorIndex = id.indexOf("_");
  if (separatorIndex === -1) {
    return { prefix: "", resourceType: null, randomPart: id, raw: id };
  }

  // Handle multi-char prefixes by finding the FIRST underscore
  const prefix = id.substring(0, separatorIndex);
  const randomPart = id.substring(separatorIndex + 1);
  const resourceType = PREFIX_TO_TYPE[prefix] ?? null;

  return { prefix, resourceType, randomPart, raw: id };
}

// Usage:
// parseId("cus_01HXK3GJ5V8WJKPT2MNR9QZK1")
// -> { prefix: "cus", resourceType: "customer", randomPart: "01HXK3GJ5V8WJKPT2MNR9QZK1", raw: "cus_..." }

// --- Branded Types (compile-time safety) ---

type CustomerId = string & { readonly __brand: "CustomerId" };
type OrderId = string & { readonly __brand: "OrderId" };

function asCustomerId(id: string): CustomerId {
  validateIdType(id, "customer");
  return id as CustomerId;
}

function asOrderId(id: string): OrderId {
  validateIdType(id, "order");
  return id as OrderId;
}

// Now the type system prevents mixing IDs:
// function getCustomer(id: CustomerId): Promise<Customer> { ... }
// function getOrder(id: OrderId): Promise<Order> { ... }
//
// getCustomer(orderId)  -> TypeScript compilation error
```

## Python

```python
import re
from dataclasses import dataclass
from enum import Enum
from typing import Optional
from ulid import ULID


# --- Prefix Registry (single source of truth) ---

class ResourceType(str, Enum):
    USER = "user"
    ORGANIZATION = "organization"
    ORDER = "order"
    PRODUCT = "product"
    INVOICE = "invoice"
    PAYMENT = "payment"
    SUBSCRIPTION = "subscription"
    WEBHOOK_ENDPOINT = "webhook_endpoint"
    EVENT = "event"
    SESSION = "session"
    TOKEN = "token"
    API_KEY = "api_key"
    CUSTOMER = "customer"
    PRICE = "price"
    TRANSACTION = "transaction"


ID_PREFIXES: dict[ResourceType, str] = {
    ResourceType.USER: "usr",
    ResourceType.ORGANIZATION: "org",
    ResourceType.ORDER: "ord",
    ResourceType.PRODUCT: "prod",
    ResourceType.INVOICE: "inv",
    ResourceType.PAYMENT: "pay",
    ResourceType.SUBSCRIPTION: "sub",
    ResourceType.WEBHOOK_ENDPOINT: "wh",
    ResourceType.EVENT: "evt",
    ResourceType.SESSION: "sess",
    ResourceType.TOKEN: "tok",
    ResourceType.API_KEY: "key",
    ResourceType.CUSTOMER: "cus",
    ResourceType.PRICE: "price",
    ResourceType.TRANSACTION: "txn",
}

PREFIX_TO_TYPE: dict[str, ResourceType] = {
    prefix: rtype for rtype, prefix in ID_PREFIXES.items()
}


# --- Generation ---

def generate_id(resource_type: ResourceType) -> str:
    """Generate a prefixed ID with a ULID random part."""
    prefix = ID_PREFIXES[resource_type]
    return f"{prefix}_{ULID()}"


# Usage:
# generate_id(ResourceType.CUSTOMER)  -> "cus_01HXK3GJ5V8WJKPT2MNR9QZK1"
# generate_id(ResourceType.ORDER)     -> "ord_01HXK3GJ6WABCDE7FGHJ2KLMN"


# --- Validation ---

PREFIXED_ID_PATTERN = re.compile(r"^[a-z]{2,5}_[a-zA-Z0-9]{14,27}$")


class InvalidIdError(ValueError):
    """Raised when a prefixed ID is malformed or has the wrong type."""

    def __init__(self, message: str):
        super().__init__(message)
        self.type = "invalid_request_error"
        self.status_code = 400


def is_valid_prefixed_id(id_value: str) -> bool:
    """Check whether a string matches the prefixed ID format."""
    return bool(PREFIXED_ID_PATTERN.match(id_value))


def validate_id_type(id_value: str, expected_type: ResourceType) -> None:
    """Validate that an ID has the correct prefix for the expected resource type."""
    expected_prefix = ID_PREFIXES[expected_type]

    if not id_value.startswith(f"{expected_prefix}_"):
        raise InvalidIdError(
            f"Expected {expected_type.value} ID (prefix '{expected_prefix}_'), "
            f"got '{id_value}'"
        )

    if not is_valid_prefixed_id(id_value):
        raise InvalidIdError(
            f"Malformed ID: '{id_value}' does not match expected format"
        )


# --- Parsing ---

@dataclass(frozen=True)
class ParsedId:
    prefix: str
    resource_type: Optional[ResourceType]
    random_part: str
    raw: str


def parse_id(id_value: str) -> ParsedId:
    """Parse a prefixed ID into its components."""
    separator_index = id_value.find("_")
    if separator_index == -1:
        return ParsedId(
            prefix="",
            resource_type=None,
            random_part=id_value,
            raw=id_value,
        )

    prefix = id_value[:separator_index]
    random_part = id_value[separator_index + 1:]
    resource_type = PREFIX_TO_TYPE.get(prefix)

    return ParsedId(
        prefix=prefix,
        resource_type=resource_type,
        random_part=random_part,
        raw=id_value,
    )


# Usage:
# parse_id("cus_01HXK3GJ5V8WJKPT2MNR9QZK1")
# -> ParsedId(prefix="cus", resource_type=ResourceType.CUSTOMER,
#             random_part="01HXK3GJ5V8WJKPT2MNR9QZK1", raw="cus_...")
```

## Key Points

- Maintain the prefix registry as a single source of truth -- every resource type maps to exactly one prefix
- Use ULID for the random part to get time-sortable, B-tree-friendly IDs
- Validate both the format (regex) and the type (prefix match) at the API boundary
- Branded types in TypeScript prevent passing a customer ID where an order ID is expected at compile time
- The `parseId` function enables generic ID routing without knowing the resource type in advance
- Never reuse or reassign a prefix -- retire old ones and create new ones instead
